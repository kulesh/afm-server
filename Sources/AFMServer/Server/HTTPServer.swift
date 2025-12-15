import Foundation
import Network

/// Minimal HTTP server using Network.framework (zero dependencies)
actor HTTPServer {
    private var listener: NWListener?
    private let port: UInt16
    private let requestHandler: @Sendable (HTTPRequest) async -> HTTPResponse

    init(port: UInt16, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.port = port
        self.requestHandler = handler
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("HTTP Server listening on port \(self.port)")
            case .failed(let error):
                print("Server failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .global())
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }

            Task {
                await self.processRequest(data: data, connection: connection)
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) async {
        guard let request = HTTPRequest.parse(data) else {
            let response = HTTPResponse(status: 400, statusText: "Bad Request", body: "Invalid HTTP request")
            sendResponse(response, on: connection)
            return
        }

        let response = await requestHandler(request)

        if response.isStreaming {
            sendStreamingResponse(response, on: connection)
        } else {
            sendResponse(response, on: connection)
        }
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let data = response.serialize()
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendStreamingResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let headers = response.serializeHeaders()
        connection.send(content: headers, completion: .contentProcessed { error in
            if error != nil {
                connection.cancel()
                return
            }

            // Send body chunks
            if let body = response.body {
                connection.send(content: body.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                connection.cancel()
            }
        })
    }
}

// MARK: - HTTP Request

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }

        let lines = string.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        var bodyStartIndex: Int?

        for (index, line) in lines.dropFirst().enumerated() {
            if line.isEmpty {
                bodyStartIndex = index + 2  // +2 because we dropped first and need next line
                break
            }
            let headerParts = line.split(separator: ":", maxSplits: 1)
            if headerParts.count == 2 {
                let key = String(headerParts[0]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(headerParts[1]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        var body: Data?
        if let startIndex = bodyStartIndex, startIndex < lines.count {
            let bodyString = lines[startIndex...].joined(separator: "\r\n")
            body = bodyString.data(using: .utf8)
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}

// MARK: - HTTP Response

struct HTTPResponse: Sendable {
    let status: Int
    let statusText: String
    var headers: [String: String]
    let body: String?
    let isStreaming: Bool

    init(status: Int, statusText: String, headers: [String: String] = [:], body: String? = nil, isStreaming: Bool = false) {
        self.status = status
        self.statusText = statusText
        self.body = body
        self.isStreaming = isStreaming

        var h = headers
        if h["Content-Type"] == nil {
            h["Content-Type"] = "application/json"
        }
        if let body = body, h["Content-Length"] == nil && !isStreaming {
            h["Content-Length"] = "\(body.utf8.count)"
        }
        h["Connection"] = "close"
        self.headers = h
    }

    static func ok(json: String) -> HTTPResponse {
        HTTPResponse(status: 200, statusText: "OK", body: json)
    }

    static func ok(json: String, streaming: Bool) -> HTTPResponse {
        HTTPResponse(
            status: 200,
            statusText: "OK",
            headers: [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache"
            ],
            body: json,
            isStreaming: streaming
        )
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status, statusText: message, body: #"{"error":"\#(message)"}"#)
    }

    func serialize() -> Data {
        var result = "HTTP/1.1 \(status) \(statusText)\r\n"
        for (key, value) in headers {
            result += "\(key): \(value)\r\n"
        }
        result += "\r\n"
        if let body = body {
            result += body
        }
        return result.data(using: .utf8)!
    }

    func serializeHeaders() -> Data {
        var result = "HTTP/1.1 \(status) \(statusText)\r\n"
        for (key, value) in headers {
            result += "\(key): \(value)\r\n"
        }
        result += "\r\n"
        return result.data(using: .utf8)!
    }
}
