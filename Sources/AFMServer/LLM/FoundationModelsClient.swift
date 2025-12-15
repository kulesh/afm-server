import Foundation
import FoundationModels

actor FoundationModelsClient {
    private var session: LanguageModelSession?

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

    func generateResponse(messages: [ChatMessage]) async -> String {
        do {
            // Create session if needed
            if session == nil {
                session = LanguageModelSession()
            }

            guard let session = session else {
                return "Error: Could not create language model session"
            }

            // Build prompt from messages
            let prompt = buildPrompt(from: messages)

            // Generate response
            let response = try await session.respond(to: prompt)
            return response.content

        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Streaming Generation

    func generateResponseStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    if session == nil {
                        session = LanguageModelSession()
                    }

                    guard let session = session else {
                        continuation.finish(throwing: NSError(domain: "AFMServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create session"]))
                        return
                    }

                    let prompt = buildPrompt(from: messages)
                    var lastContent = ""

                    for try await snapshot in session.streamResponse(to: prompt) {
                        // Extract the new content since last snapshot
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

    private func buildPrompt(from messages: [ChatMessage]) -> String {
        var prompt = ""
        for message in messages {
            guard let content = message.content else { continue }
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
