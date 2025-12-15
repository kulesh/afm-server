import Foundation
import FoundationModels

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

        if temp == 0 {
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

    private func buildPrompt(from messages: [ChatMessage], excludeSystem: Bool = false) -> String {
        var prompt = ""
        for message in messages {
            guard let content = message.content else { continue }
            if excludeSystem && message.role == "system" { continue }
            switch message.role {
            case "system":
                prompt += "System: \(content)\n\n"
            case "user":
                prompt += "User: \(content)\n\n"
            case "assistant":
                prompt += "Assistant: \(content)\n\n"
            default:
                prompt += "\(content)\n\n"
            }
        }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
