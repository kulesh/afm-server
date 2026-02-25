import Foundation

// MARK: - Generation Config

struct GenerationConfig {
    let temperature: Double?
    let maxTokens: Int?
    let systemPrompt: String?

    init(from request: ChatCompletionRequest) {
        self.temperature = request.temperature
        self.maxTokens = request.maxTokens
        self.systemPrompt = request.messages.first(where: { $0.role == "system" })?.content
    }
}

// MARK: - Request Types

struct ChatCompletionRequest: Codable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?
    let tools: [ToolDefinition]?
    let toolChoice: ToolChoice?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
    }
}

struct ChatMessage: Codable, Sendable {
    let role: String
    let content: String?
    let name: String?
    let toolCallId: String?
    let toolCalls: [AssistantToolCall]?

    init(
        role: String,
        content: String? = nil,
        name: String? = nil,
        toolCallId: String? = nil,
        toolCalls: [AssistantToolCall]? = nil
    ) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCallId = "tool_call_id"
        case toolCalls = "tool_calls"
    }
}

struct ToolDefinition: Codable, Equatable, Sendable {
    let type: String
    let function: FunctionDefinition

    init(type: String = "function", function: FunctionDefinition) {
        self.type = type
        self.function = function
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "function" else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported tool type '\(type)'. Only 'function' is supported."
            )
        }
        let function = try container.decode(FunctionDefinition.self, forKey: .function)
        self.init(type: type, function: function)
    }
}

struct FunctionDefinition: Codable, Equatable, Sendable {
    let name: String
    let description: String?
    let parameters: JSONSchema?

    init(name: String, description: String? = nil, parameters: JSONSchema? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: container, debugDescription: "Function name must not be empty.")
        }
        let description = try container.decodeIfPresent(String.self, forKey: .description)
        let parameters = try container.decodeIfPresent(JSONSchema.self, forKey: .parameters)
        self.init(name: name, description: description, parameters: parameters)
    }
}

enum ToolChoice: Codable, Equatable, Sendable {
    case auto
    case none
    case required
    case function(name: String)

    private struct ForcedChoice: Codable, Equatable {
        let type: String
        let function: ForcedFunction
    }

    private struct ForcedFunction: Codable, Equatable {
        let name: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let raw = try? container.decode(String.self) {
            switch raw {
            case "auto":
                self = .auto
            case "none":
                self = .none
            case "required":
                self = .required
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid tool_choice '\(raw)'.")
            }
            return
        }

        let forced = try container.decode(ForcedChoice.self)
        guard forced.type == "function" else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Forced tool_choice type must be 'function'.")
        }
        guard !forced.function.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Forced function tool_choice name must not be empty.")
        }
        self = .function(name: forced.function.name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .auto:
            try container.encode("auto")
        case .none:
            try container.encode("none")
        case .required:
            try container.encode("required")
        case .function(let name):
            try container.encode(ForcedChoice(type: "function", function: ForcedFunction(name: name)))
        }
    }
}

final class JSONSchema: Codable, Equatable, @unchecked Sendable {
    let type: String?
    let description: String?
    let properties: [String: JSONSchema]?
    let required: [String]?
    let items: JSONSchema?
    let enumValues: [String]?
    let additionalProperties: JSONSchemaAdditionalProperties?

    enum CodingKeys: String, CodingKey {
        case type, description, properties, required, items
        case enumValues = "enum"
        case additionalProperties
    }

    init(
        type: String? = nil,
        description: String? = nil,
        properties: [String: JSONSchema]? = nil,
        required: [String]? = nil,
        items: JSONSchema? = nil,
        enumValues: [String]? = nil,
        additionalProperties: JSONSchemaAdditionalProperties? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.items = items
        self.enumValues = enumValues
        self.additionalProperties = additionalProperties
    }

    static func == (lhs: JSONSchema, rhs: JSONSchema) -> Bool {
        lhs.type == rhs.type &&
        lhs.description == rhs.description &&
        lhs.properties == rhs.properties &&
        lhs.required == rhs.required &&
        lhs.items == rhs.items &&
        lhs.enumValues == rhs.enumValues &&
        lhs.additionalProperties == rhs.additionalProperties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.properties = try container.decodeIfPresent([String: JSONSchema].self, forKey: .properties)
        self.required = try container.decodeIfPresent([String].self, forKey: .required)
        self.items = try container.decodeIfPresent(JSONSchema.self, forKey: .items)
        self.enumValues = try container.decodeIfPresent([String].self, forKey: .enumValues)
        self.additionalProperties = try container.decodeIfPresent(JSONSchemaAdditionalProperties.self, forKey: .additionalProperties)

        do {
            try Self.validate(schema: self, path: "$")
        } catch let error as SchemaValidationError {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: error.description)
        }
    }

    private static func validate(schema: JSONSchema, path: String) throws {
        let supportedTypes: Set<String> = ["object", "string", "number", "integer", "boolean", "array"]

        if let type = schema.type, !supportedTypes.contains(type) {
            throw SchemaValidationError("\(path).type '\(type)' is not supported.")
        }

        if let type = schema.type, type != "object", (schema.properties != nil || schema.required != nil) {
            throw SchemaValidationError("\(path) only object schemas can define 'properties' or 'required'.")
        }

        if schema.required != nil, schema.properties == nil {
            throw SchemaValidationError("\(path) cannot define 'required' without 'properties'.")
        }

        if let type = schema.type, type != "array", schema.items != nil {
            throw SchemaValidationError("\(path) only array schemas can define 'items'.")
        }

        if let values = schema.enumValues, values.isEmpty {
            throw SchemaValidationError("\(path).enum must not be empty.")
        }

        if let properties = schema.properties {
            for (name, nestedSchema) in properties {
                try validate(schema: nestedSchema, path: "\(path).properties.\(name)")
            }
        }

        if let items = schema.items {
            try validate(schema: items, path: "\(path).items")
        }

        if case .schema(let nestedSchema)? = schema.additionalProperties {
            try validate(schema: nestedSchema, path: "\(path).additionalProperties")
        }
    }
}

indirect enum JSONSchemaAdditionalProperties: Codable, Equatable, Sendable {
    case bool(Bool)
    case schema(JSONSchema)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
            return
        }
        if let schemaValue = try? container.decode(JSONSchema.self) {
            self = .schema(schemaValue)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "additionalProperties must be a boolean or schema object.")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):
            try container.encode(value)
        case .schema(let schema):
            try container.encode(schema)
        }
    }
}

private struct SchemaValidationError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

// MARK: - Response Types (Non-streaming)

struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatChoice]
    let usage: UsageInfo
}

struct ChatChoice: Codable {
    let index: Int
    let message: ChatMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct UsageInfo: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Response Types (Streaming)

struct ChatCompletionChunk: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChunkChoice]
}

struct ChunkChoice: Codable {
    let index: Int
    let delta: ChunkDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

struct ChunkDelta: Codable {
    let role: String?
    let content: String?
}

struct AssistantToolCall: Codable, Equatable, Sendable {
    let id: String
    let type: String
    let function: ToolCallFunction

    init(id: String, type: String = "function", function: ToolCallFunction) {
        self.id = id
        self.type = type
        self.function = function
    }
}

struct ToolCallFunction: Codable, Equatable, Sendable {
    let name: String
    let arguments: String
}

// MARK: - Models Endpoint

struct ModelsResponse: Codable {
    let object: String
    let data: [ModelInfo]
}

struct ModelInfo: Codable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}
