import Foundation
import SwiftUI
import Hummingbird

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
    @Published var isRunning = false
    @Published var modelAvailable = false
    @Published var requestCount = 0
    @Published var port: Int = 11535

    private var serverTask: Task<Void, Error>?
    private let llmClient = FoundationModelsClient()
    private let requestCounter = RequestCounter()

    func start() {
        guard !isRunning else { return }

        let currentPort = port
        let client = llmClient
        let counter = requestCounter

        serverTask = Task.detached {
            do {
                let router = AFMRouter.build(llmClient: client, requestCounter: counter)
                let app = Application(
                    router: router,
                    configuration: .init(
                        address: .hostname("127.0.0.1", port: currentPort)
                    )
                )

                await MainActor.run {
                    self.isRunning = true
                }

                print("AFM Server starting on http://127.0.0.1:\(currentPort)")
                try await app.run()
            } catch {
                print("Server error: \(error)")
                await MainActor.run {
                    self.isRunning = false
                }
            }
        }

        // Poll request count
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                let count = await counter.count
                if count != requestCount {
                    requestCount = count
                }
            }
        }
    }

    func stop() {
        serverTask?.cancel()
        serverTask = nil
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
}

// Separate struct for building routes (not MainActor-isolated)
enum AFMRouter {
    static func build(llmClient: FoundationModelsClient, requestCounter: RequestCounter) -> Router<BasicRequestContext> {
        let router = Router()

        // Health check
        router.get("/health") { _, _ in
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(string: #"{"status":"ok"}"#))
            )
        }

        // List models
        router.get("/v1/models") { _, _ in
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
            let data = try JSONEncoder().encode(response)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        }

        // Chat completions
        router.post("/v1/chat/completions") { request, _ in
            await requestCounter.increment()

            // Parse request body
            let body = try await request.body.collect(upTo: 1024 * 1024) // 1MB limit
            let chatRequest = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)

            // Generate response
            let responseText = await llmClient.generateResponse(messages: chatRequest.messages)

            // Check for streaming
            if chatRequest.stream == true {
                return try buildStreamingResponse(responseText: responseText)
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

            let data = try JSONEncoder().encode(chatResponse)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        }

        return router
    }

    private static func buildStreamingResponse(responseText: String) throws -> Response {
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
            let chunkData = try JSONEncoder().encode(chunk)
            body += "data: \(String(data: chunkData, encoding: .utf8) ?? "")\n\n"
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
        let finalData = try JSONEncoder().encode(finalChunk)
        body += "data: \(String(data: finalData, encoding: .utf8) ?? "")\n\n"
        body += "data: [DONE]\n\n"

        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
                .init("Connection")!: "keep-alive"
            ],
            body: .init(byteBuffer: ByteBuffer(string: body))
        )
    }
}
