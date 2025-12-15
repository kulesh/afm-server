import Foundation
import SwiftUI

// Thread-safe request counter using actor
actor RequestCounter {
    private var _count: Int = 0

    var count: Int { _count }

    func increment() {
        _count += 1
    }
}

@MainActor
class ServerManager: ObservableObject {
    static let shared = ServerManager()

    @Published var isRunning = false
    @Published var modelAvailable = false
    @Published var requestCount = 0
    @Published var port: UInt16 = 11535

    private var server: HTTPServer?
    private let llmClient = FoundationModelsClient()
    private let requestCounter = RequestCounter()

    func start() {
        guard !isRunning else { return }

        let client = llmClient
        let counter = requestCounter

        server = HTTPServer(port: port) { request in
            await counter.increment()
            return await Self.handleRequest(request, llmClient: client)
        }

        Task { @MainActor [weak self] in
            do {
                try await self?.server?.start()
            } catch {
                print("Server error: \(error)")
                self?.isRunning = false
            }
        }

        // Poll request count
        Task {
            while !Task.isCancelled && server != nil {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let count = await counter.count
                if count != requestCount {
                    requestCount = count
                }
            }
        }

        isRunning = true
    }

    func stop() {
        Task {
            await server?.stop()
        }
        server = nil
        isRunning = false
        print("AFM Server stopped")
    }

    func checkModelAvailability() {
        Task {
            let available = await llmClient.isModelAvailable()
            await MainActor.run {
                self.modelAvailable = available
            }
        }
    }

    // MARK: - Request Handling

    private static func handleRequest(_ request: HTTPRequest, llmClient: FoundationModelsClient) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return .ok(json: #"{"status":"ok"}"#)

        case ("GET", "/v1/models"):
            let response = ModelsResponse(
                object: "list",
                data: [
                    ModelInfo(
                        id: "apple-on-device",
                        object: "model",
                        created: Int(Date().timeIntervalSince1970),
                        ownedBy: "apple"
                    )
                ]
            )
            if let data = try? JSONEncoder().encode(response),
               let json = String(data: data, encoding: .utf8) {
                return .ok(json: json)
            }
            return .error(500, "Failed to encode response")

        case ("POST", "/v1/chat/completions"):
            return await handleChatCompletion(request, llmClient: llmClient)

        default:
            return .error(404, "Not Found")
        }
    }

    private static func handleChatCompletion(_ request: HTTPRequest, llmClient: FoundationModelsClient) async -> HTTPResponse {
        guard let body = request.body,
              let chatRequest = try? JSONDecoder().decode(ChatCompletionRequest.self, from: body) else {
            return .error(400, "Invalid request body")
        }

        // Generate response
        let responseText = await llmClient.generateResponse(messages: chatRequest.messages)

        // Check for streaming
        if chatRequest.stream == true {
            return buildStreamingResponse(responseText: responseText)
        }

        // Non-streaming response
        let chatResponse = ChatCompletionResponse(
            id: "chatcmpl-\(UUID().uuidString.prefix(8))",
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: "apple-on-device",
            choices: [
                ChatChoice(
                    index: 0,
                    message: ChatMessage(role: "assistant", content: responseText),
                    finishReason: "stop"
                )
            ],
            usage: UsageInfo(
                promptTokens: chatRequest.messages.reduce(0) { $0 + ($1.content?.count ?? 0) / 4 },
                completionTokens: responseText.count / 4,
                totalTokens: (chatRequest.messages.reduce(0) { $0 + ($1.content?.count ?? 0) } + responseText.count) / 4
            )
        )

        if let data = try? JSONEncoder().encode(chatResponse),
           let json = String(data: data, encoding: .utf8) {
            return .ok(json: json)
        }
        return .error(500, "Failed to encode response")
    }

    private static func buildStreamingResponse(responseText: String) -> HTTPResponse {
        let responseId = "chatcmpl-\(UUID().uuidString.prefix(8))"
        var body = ""
        let words = responseText.split(separator: " ")

        for (index, word) in words.enumerated() {
            let chunk = ChatCompletionChunk(
                id: responseId,
                object: "chat.completion.chunk",
                created: Int(Date().timeIntervalSince1970),
                model: "apple-on-device",
                choices: [
                    ChunkChoice(
                        index: 0,
                        delta: ChunkDelta(
                            role: index == 0 ? "assistant" : nil,
                            content: String(word) + (index < words.count - 1 ? " " : "")
                        ),
                        finishReason: nil
                    )
                ]
            )
            if let chunkData = try? JSONEncoder().encode(chunk),
               let chunkJson = String(data: chunkData, encoding: .utf8) {
                body += "data: \(chunkJson)\n\n"
            }
        }

        // Final chunk
        let finalChunk = ChatCompletionChunk(
            id: responseId,
            object: "chat.completion.chunk",
            created: Int(Date().timeIntervalSince1970),
            model: "apple-on-device",
            choices: [
                ChunkChoice(
                    index: 0,
                    delta: ChunkDelta(role: nil, content: nil),
                    finishReason: "stop"
                )
            ]
        )
        if let finalData = try? JSONEncoder().encode(finalChunk),
           let finalJson = String(data: finalData, encoding: .utf8) {
            body += "data: \(finalJson)\n\n"
        }
        body += "data: [DONE]\n\n"

        return .ok(json: body, streaming: true)
    }
}
