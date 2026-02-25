import FoundationModels
import XCTest
@testable import AFMServer

final class ToolRegistryTests: XCTestCase {
    func testSelectToolsAutoReturnsRequestedTools() throws {
        let registry = ToolRegistry()
        let selection = try registry.selectTools(
            requestedDefinitions: [
                ToolDefinition(function: FunctionDefinition(name: "math_add"))
            ],
            toolChoice: .auto
        )

        XCTAssertEqual(selection.runtimeTools.count, 1)
        XCTAssertEqual(selection.runtimeTools.first?.name, "math_add")
        XCTAssertNil(selection.instructions)
    }

    func testSelectToolsNoneReturnsEmptySelection() throws {
        let registry = ToolRegistry()
        let selection = try registry.selectTools(
            requestedDefinitions: [
                ToolDefinition(function: FunctionDefinition(name: "math_add"))
            ],
            toolChoice: .some(.none)
        )

        XCTAssertTrue(selection.runtimeTools.isEmpty)
    }

    func testSelectToolsForcedFunctionRestrictsSelection() throws {
        let registry = ToolRegistry()
        let selection = try registry.selectTools(
            requestedDefinitions: [
                ToolDefinition(function: FunctionDefinition(name: "math_add")),
                ToolDefinition(function: FunctionDefinition(name: "echo"))
            ],
            toolChoice: .function(name: "echo")
        )

        XCTAssertEqual(selection.runtimeTools.map(\.name), ["echo"])
        XCTAssertEqual(selection.instructions, "Use only the 'echo' tool for this response.")
    }

    func testSelectToolsUnknownToolThrows() throws {
        let registry = ToolRegistry()
        XCTAssertThrowsError(
            try registry.selectTools(
                requestedDefinitions: [
                    ToolDefinition(function: FunctionDefinition(name: "does_not_exist"))
                ],
                toolChoice: .auto
            )
        ) { error in
            XCTAssertEqual(error as? ToolingError, .unknownTool("does_not_exist"))
        }
    }

    func testRuntimeToolRejectsMalformedArguments() async throws {
        let registry = ToolRegistry()
        let selection = try registry.selectTools(
            requestedDefinitions: [
                ToolDefinition(function: FunctionDefinition(name: "math_add"))
            ],
            toolChoice: .auto
        )
        let tool = try XCTUnwrap(selection.runtimeTools.first)

        await XCTAssertThrowsAsyncError(
            try await tool.call(arguments: GeneratedContent(json: "{}"))
        ) { error in
            guard case .invalidArguments = error as? ToolingError else {
                XCTFail("Expected invalidArguments, got \(error)")
                return
            }
        }
    }

    func testRuntimeToolTimeout() async throws {
        let slowTool = RegisteredTool(
            name: "slow_tool",
            description: "Slow test tool",
            parameters: JSONSchema(type: "object", properties: [:], required: []),
            handler: { _ in
                try await Task.sleep(nanoseconds: 200_000_000)
                return #"{"ok":true}"#
            }
        )
        let registry = ToolRegistry(tools: [slowTool])

        let selection = try registry.selectTools(
            requestedDefinitions: [
                ToolDefinition(function: FunctionDefinition(name: "slow_tool"))
            ],
            toolChoice: .auto,
            limits: ToolRuntimeLimits(maxArgumentBytes: 1_024, maxOutputBytes: 1_024, timeoutNanoseconds: 10_000_000)
        )
        let tool = try XCTUnwrap(selection.runtimeTools.first)

        await XCTAssertThrowsAsyncError(
            try await tool.call(arguments: GeneratedContent(json: "{}"))
        ) { error in
            XCTAssertEqual(error as? ToolingError, .toolTimeout("slow_tool"))
        }
    }
}

private func XCTAssertThrowsAsyncError<T>(
    _ expression: @autoclosure @escaping () async throws -> T,
    _ verify: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw an error", file: file, line: line)
    } catch {
        verify(error)
    }
}
