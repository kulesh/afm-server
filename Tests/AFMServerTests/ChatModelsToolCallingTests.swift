import XCTest
@testable import AFMServer

final class ChatModelsToolCallingTests: XCTestCase {
    func testDecodesRequestWithToolsAndAutoToolChoice() throws {
        let request = try decodeRequest(
            """
            {
              "model": "apple-on-device",
              "messages": [{"role": "user", "content": "Weather in SF?"}],
              "tools": [
                {
                  "type": "function",
                  "function": {
                    "name": "get_weather",
                    "description": "Get weather",
                    "parameters": {
                      "type": "object",
                      "properties": {
                        "city": {"type": "string"}
                      },
                      "required": ["city"]
                    }
                  }
                }
              ],
              "tool_choice": "auto"
            }
            """
        )

        XCTAssertEqual(request.tools?.count, 1)
        XCTAssertEqual(request.tools?.first?.function.name, "get_weather")
        XCTAssertEqual(request.toolChoice, .auto)
    }

    func testDecodesRequestWithForcedToolChoiceObject() throws {
        let request = try decodeRequest(
            """
            {
              "model": "apple-on-device",
              "messages": [{"role": "user", "content": "Hi"}],
              "tools": [
                {
                  "type": "function",
                  "function": {
                    "name": "lookup_time",
                    "parameters": {"type": "object"}
                  }
                }
              ],
              "tool_choice": {
                "type": "function",
                "function": {"name": "lookup_time"}
              }
            }
            """
        )

        XCTAssertEqual(request.toolChoice, .function(name: "lookup_time"))
    }

    func testRejectsUnsupportedToolType() throws {
        XCTAssertThrowsError(
            try decodeRequest(
                """
                {
                  "model": "apple-on-device",
                  "messages": [{"role": "user", "content": "Hi"}],
                  "tools": [
                    {
                      "type": "retrieval",
                      "function": {"name": "lookup", "parameters": {"type": "object"}}
                    }
                  ]
                }
                """
            )
        )
    }

    func testRejectsInvalidToolChoiceString() throws {
        XCTAssertThrowsError(
            try decodeRequest(
                """
                {
                  "model": "apple-on-device",
                  "messages": [{"role": "user", "content": "Hi"}],
                  "tool_choice": "sometimes"
                }
                """
            )
        )
    }

    func testRejectsUnsupportedJSONSchemaType() throws {
        XCTAssertThrowsError(
            try decodeRequest(
                """
                {
                  "model": "apple-on-device",
                  "messages": [{"role": "user", "content": "Hi"}],
                  "tools": [
                    {
                      "type": "function",
                      "function": {
                        "name": "bad_schema",
                        "parameters": {"type": "null"}
                      }
                    }
                  ]
                }
                """
            )
        )
    }

    func testToolCallCodingKeysRoundTrip() throws {
        let message = ChatMessage(
            role: "assistant",
            content: nil,
            name: nil,
            toolCallId: nil,
            toolCalls: [
                AssistantToolCall(
                    id: "call_1",
                    function: ToolCallFunction(name: "lookup_time", arguments: #"{"city":"SF"}"#)
                )
            ]
        )

        let data = try JSONEncoder().encode(message)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(encoded.contains("\"tool_calls\""))
        XCTAssertFalse(encoded.contains("\"toolCallId\""))

        let decoded = try JSONDecoder().decode(
            ChatMessage.self,
            from: Data(#"{"role":"tool","content":"ok","tool_call_id":"call_1"}"#.utf8)
        )
        XCTAssertEqual(decoded.toolCallId, "call_1")
    }

    private func decodeRequest(_ json: String) throws -> ChatCompletionRequest {
        try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    }
}
