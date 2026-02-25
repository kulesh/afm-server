import Foundation
import FoundationModels

struct CompletionGenerationResult: Sendable {
    let content: String?
    let toolCalls: [AssistantToolCall]
    let finishReason: String
}

actor FoundationModelsClient {
    private var session: LanguageModelSession?
    private var currentInstructions: String?

    // MARK: - Model Availability

    func isModelAvailable() async -> Bool {
        do {
            let availability = SystemLanguageModel.default.availability
            switch availability {
            case .available:
                return true
            case .unavailable:
                return false
            @unknown default:
                return false
            }
        }
    }

    // MARK: - Text Generation

    func generateResponse(messages: [ChatMessage], config: GenerationConfig? = nil) async -> String {
        do {
            let session = getSession(instructions: config?.systemPrompt)
            let prompt = buildPrompt(from: messages, excludeSystem: config?.systemPrompt != nil)
            let options = buildGenerationOptions(from: config)

            let response = try await session.respond(to: prompt, options: options)
            return response.content

        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Tool-Aware Generation

    func generateCompletion(request: ChatCompletionRequest) async throws -> CompletionGenerationResult {
        let config = GenerationConfig(from: request)
        let hasToolMessages = request.messages.contains { $0.role == "tool" }
        let toolSelection = try ToolRegistry.shared.selectTools(
            requestedDefinitions: request.tools ?? [],
            toolChoice: request.toolChoice
        )

        if toolSelection.runtimeTools.isEmpty {
            let content = await generateResponse(messages: request.messages, config: config)
            return CompletionGenerationResult(content: content, toolCalls: [], finishReason: "stop")
        }

        let instructions = combineInstructions(
            systemPrompt: config.systemPrompt,
            toolInstructions: toolSelection.instructions
        )
        let toolSession = LanguageModelSession(
            model: .default,
            tools: toolSelection.runtimeTools,
            instructions: instructions
        )

        let prompt = buildPrompt(from: request.messages, excludeSystem: config.systemPrompt != nil)
        let options = buildGenerationOptions(from: config)
        let response = try await toolSession.respond(to: prompt, options: options)

        let toolCalls = extractToolCalls(from: response.transcriptEntries)
        if !toolCalls.isEmpty && !hasToolMessages {
            return CompletionGenerationResult(content: nil, toolCalls: toolCalls, finishReason: "tool_calls")
        }

        return CompletionGenerationResult(content: response.content, toolCalls: toolCalls, finishReason: "stop")
    }

    // MARK: - Streaming Generation

    nonisolated func generateResponseStream(messages: [ChatMessage], config: GenerationConfig? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let session = await self.getSession(instructions: config?.systemPrompt)
                    let prompt = await self.buildPrompt(from: messages, excludeSystem: config?.systemPrompt != nil)
                    let options = await self.buildGenerationOptions(from: config)
                    var lastContent = ""

                    for try await snapshot in session.streamResponse(to: prompt, options: options) {
                        let currentContent = snapshot.content
                        if currentContent.count > lastContent.count {
                            let newContent = String(currentContent.dropFirst(lastContent.count))
                            continuation.yield(newContent)
                            lastContent = currentContent
                        }
                    }
                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func getSession(instructions: String?) -> LanguageModelSession {
        if session == nil || currentInstructions != instructions {
            if let instructions = instructions, !instructions.isEmpty {
                session = LanguageModelSession(instructions: instructions)
            } else {
                session = LanguageModelSession()
            }
            currentInstructions = instructions
        }
        return session!
    }

    private func buildGenerationOptions(from config: GenerationConfig?) -> GenerationOptions {
        guard let config = config,
              config.temperature != nil || config.maxTokens != nil else {
            return GenerationOptions()
        }

        // Scale OpenAI temperature (0-2) to Apple's range (0-1)
        let temp = config.temperature.map { max(0.0, min(1.0, $0 / 2.0)) }

        if let t = temp, t == 0 {
            return GenerationOptions(
                sampling: .greedy,
                temperature: 0,
                maximumResponseTokens: config.maxTokens
            )
        }

        return GenerationOptions(
            temperature: temp,
            maximumResponseTokens: config.maxTokens
        )
    }

    private func combineInstructions(systemPrompt: String?, toolInstructions: String?) -> String? {
        let parts = [systemPrompt, toolInstructions]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }

    private func extractToolCalls(from entries: ArraySlice<Transcript.Entry>) -> [AssistantToolCall] {
        var calls: [AssistantToolCall] = []

        for entry in entries {
            guard case .toolCalls(let toolCalls) = entry else { continue }
            for call in toolCalls {
                calls.append(
                    AssistantToolCall(
                        id: call.id,
                        function: ToolCallFunction(
                            name: call.toolName,
                            arguments: call.arguments.jsonString
                        )
                    )
                )
            }
        }

        return calls
    }

    private func buildPrompt(from messages: [ChatMessage], excludeSystem: Bool = false) -> String {
        var prompt = ""
        for message in messages {
            if excludeSystem && message.role == "system" { continue }

            switch message.role {
            case "system":
                guard let content = message.content else { continue }
                prompt += "System: \(content)\n\n"
            case "user":
                guard let content = message.content else { continue }
                prompt += "User: \(content)\n\n"
            case "assistant":
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    for call in toolCalls {
                        prompt += "AssistantToolCall[\(call.id)] \(call.function.name): \(call.function.arguments)\n"
                    }
                    prompt += "\n"
                }
                if let content = message.content {
                    prompt += "Assistant: \(content)\n\n"
                }
            case "tool":
                let nameOrId = message.name ?? message.toolCallId ?? "tool"
                let content = message.content ?? ""
                prompt += "Tool[\(nameOrId)]: \(content)\n\n"
            default:
                guard let content = message.content else { continue }
                prompt += "\(content)\n\n"
            }
        }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
