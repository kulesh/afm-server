import Foundation
import FoundationModels

enum ToolingError: Error, LocalizedError, Equatable {
    case unknownTool(String)
    case invalidToolChoice(String)
    case invalidArguments(String)
    case toolTimeout(String)
    case toolOutputTooLarge(String)
    case toolArgumentsTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool '\(name)'."
        case .invalidToolChoice(let message):
            return message
        case .invalidArguments(let message):
            return message
        case .toolTimeout(let name):
            return "Tool '\(name)' timed out."
        case .toolOutputTooLarge(let name):
            return "Tool '\(name)' returned too much data."
        case .toolArgumentsTooLarge(let name):
            return "Tool '\(name)' arguments exceed allowed size."
        }
    }
}

struct ToolRuntimeLimits: Sendable {
    let maxArgumentBytes: Int
    let maxOutputBytes: Int
    let timeoutNanoseconds: UInt64

    static let `default` = ToolRuntimeLimits(
        maxArgumentBytes: 16_384,
        maxOutputBytes: 16_384,
        timeoutNanoseconds: 2_000_000_000
    )
}

struct AvailableTool: Codable, Equatable {
    let name: String
    let description: String
}

struct RegisteredTool: Sendable {
    let name: String
    let description: String
    let parameters: JSONSchema
    let handler: @Sendable (GeneratedContent) async throws -> String
}

struct RuntimeTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let definition: RegisteredTool
    let limits: ToolRuntimeLimits

    var name: String { definition.name }
    var description: String { definition.description }
    var parameters: GenerationSchema { try! JSONSchemaConverter.toGenerationSchema(definition.parameters) }

    func call(arguments: GeneratedContent) async throws -> String {
        let argumentBytes = arguments.jsonString.utf8.count
        if argumentBytes > limits.maxArgumentBytes {
            throw ToolingError.toolArgumentsTooLarge(name)
        }

        let output = try await withTimeout(nanoseconds: limits.timeoutNanoseconds) {
            try await definition.handler(arguments)
        }
        if output.utf8.count > limits.maxOutputBytes {
            throw ToolingError.toolOutputTooLarge(name)
        }
        return output
    }

    private func withTimeout<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw ToolingError.toolTimeout(name)
            }

            guard let result = try await group.next() else {
                throw ToolingError.toolTimeout(name)
            }
            group.cancelAll()
            return result
        }
    }
}

struct ToolSelection: Sendable {
    let runtimeTools: [RuntimeTool]
    let instructions: String?
}

struct ToolRegistry {
    static let shared = ToolRegistry()

    private let toolsByName: [String: RegisteredTool]

    init(tools: [RegisteredTool] = BuiltInTools.all) {
        self.toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    func availableTools() -> [AvailableTool] {
        toolsByName.values
            .map { AvailableTool(name: $0.name, description: $0.description) }
            .sorted { $0.name < $1.name }
    }

    func selectTools(
        requestedDefinitions: [ToolDefinition],
        toolChoice: ToolChoice?,
        limits: ToolRuntimeLimits = .default
    ) throws -> ToolSelection {
        if requestedDefinitions.isEmpty || toolChoice == .some(.none) {
            return ToolSelection(runtimeTools: [], instructions: nil)
        }

        let requestedNames = requestedDefinitions.map(\.function.name)
        let uniqueNames = Array(Set(requestedNames)).sorted()

        let unknown = uniqueNames.filter { toolsByName[$0] == nil }
        if let firstUnknown = unknown.first {
            throw ToolingError.unknownTool(firstUnknown)
        }

        var selectedNames = uniqueNames
        var instructions: String?

        switch toolChoice ?? .auto {
        case .none:
            selectedNames = []
        case .required:
            instructions = "You must call at least one tool before your final response."
        case .function(let name):
            guard uniqueNames.contains(name) else {
                throw ToolingError.invalidToolChoice("tool_choice requests '\(name)' but it is not present in tools.")
            }
            selectedNames = [name]
            instructions = "Use only the '\(name)' tool for this response."
        case .auto:
            break
        }

        let runtimeTools = selectedNames.compactMap { name -> RuntimeTool? in
            guard let tool = toolsByName[name] else { return nil }
            return RuntimeTool(definition: tool, limits: limits)
        }
        return ToolSelection(runtimeTools: runtimeTools, instructions: instructions)
    }
}

enum BuiltInTools {
    static let all: [RegisteredTool] = [
        RegisteredTool(
            name: "current_time",
            description: "Get the current date and time for an optional IANA timezone identifier.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "timezone": JSONSchema(type: "string", description: "Optional IANA timezone, for example 'America/Los_Angeles'.")
                ],
                required: []
            ),
            handler: { arguments in
                struct Args: Decodable {
                    let timezone: String?
                }
                struct Output: Encodable {
                    let iso8601: String
                    let timezone: String
                    let unix: Int
                }

                let args = try decodeArguments(Args.self, from: arguments)
                let timezoneId = args.timezone ?? TimeZone.current.identifier
                guard let timezone = TimeZone(identifier: timezoneId) else {
                    throw ToolingError.invalidArguments("Invalid timezone '\(timezoneId)'.")
                }

                let date = Date()
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                formatter.timeZone = timezone

                let output = Output(
                    iso8601: formatter.string(from: date),
                    timezone: timezone.identifier,
                    unix: Int(date.timeIntervalSince1970)
                )
                return try encodeJSON(output)
            }
        ),
        RegisteredTool(
            name: "math_add",
            description: "Add a list of numbers and return the sum.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "numbers": JSONSchema(
                        type: "array",
                        description: "Numbers to add together.",
                        items: JSONSchema(type: "number")
                    )
                ],
                required: ["numbers"]
            ),
            handler: { arguments in
                struct Args: Decodable {
                    let numbers: [Double]
                }
                struct Output: Encodable {
                    let sum: Double
                    let count: Int
                }

                let args = try decodeArguments(Args.self, from: arguments)
                if args.numbers.isEmpty {
                    throw ToolingError.invalidArguments("numbers must contain at least one value.")
                }
                if args.numbers.count > 256 {
                    throw ToolingError.invalidArguments("numbers exceeds maximum count of 256.")
                }
                let sum = args.numbers.reduce(0, +)
                return try encodeJSON(Output(sum: sum, count: args.numbers.count))
            }
        ),
        RegisteredTool(
            name: "echo",
            description: "Echo input text for testing tool-call integration.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "text": JSONSchema(type: "string", description: "Text to echo back.")
                ],
                required: ["text"]
            ),
            handler: { arguments in
                struct Args: Decodable {
                    let text: String
                }
                struct Output: Encodable {
                    let text: String
                }

                let args = try decodeArguments(Args.self, from: arguments)
                if args.text.utf8.count > 8_192 {
                    throw ToolingError.invalidArguments("text exceeds maximum size.")
                }
                return try encodeJSON(Output(text: args.text))
            }
        )
    ]
}

private func decodeArguments<T: Decodable>(_ type: T.Type, from content: GeneratedContent) throws -> T {
    let data = Data(content.jsonString.utf8)
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw ToolingError.invalidArguments("Invalid tool arguments: \(error.localizedDescription)")
    }
}

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8) ?? "{}"
}

private enum JSONSchemaConverter {
    static func toGenerationSchema(_ schema: JSONSchema) throws -> GenerationSchema {
        let root = try toDynamicSchema(schema, name: "ToolArguments")
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func toDynamicSchema(_ schema: JSONSchema, name: String) throws -> DynamicGenerationSchema {
        let effectiveType = schema.type ?? (schema.properties != nil ? "object" : nil)

        switch effectiveType {
        case "object":
            let properties = schema.properties ?? [:]
            let requiredSet = Set(schema.required ?? [])
            let dynamicProperties = try properties.keys.sorted().map { key in
                let propertySchema = properties[key]!
                return try DynamicGenerationSchema.Property(
                    name: key,
                    description: propertySchema.description,
                    schema: toDynamicSchema(propertySchema, name: key.capitalized),
                    isOptional: !requiredSet.contains(key)
                )
            }
            return DynamicGenerationSchema(
                name: name,
                description: schema.description,
                properties: dynamicProperties
            )
        case "string":
            if let enumValues = schema.enumValues, !enumValues.isEmpty {
                return DynamicGenerationSchema(name: name, description: schema.description, anyOf: enumValues)
            }
            return DynamicGenerationSchema(type: String.self)
        case "number":
            return DynamicGenerationSchema(type: Double.self)
        case "integer":
            return DynamicGenerationSchema(type: Int.self)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        case "array":
            guard let itemSchema = schema.items else {
                throw ToolingError.invalidArguments("Array schema for '\(name)' must define items.")
            }
            return DynamicGenerationSchema(arrayOf: try toDynamicSchema(itemSchema, name: "\(name)Item"))
        default:
            throw ToolingError.invalidArguments("Unsupported schema type '\(effectiveType ?? "nil")' for '\(name)'.")
        }
    }
}
