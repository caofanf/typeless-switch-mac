import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }
}

struct JSONRPCRequest: Codable, Equatable, Sendable {
    let jsonrpc: String
    let id: String
    let method: String
    let params: JSONValue

    init(id: String, method: String, params: JSONValue = .object([:])) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JSONRPCErrorPayload: Codable, Equatable, Sendable {
    let code: String
    let message: String
    let details: JSONValue?
}

struct JSONRPCResponse: Codable, Equatable, Sendable {
    let jsonrpc: String
    let id: String
    let result: JSONValue?
    let error: JSONRPCErrorPayload?
}

struct JSONRPCNotification: Codable, Equatable, Sendable {
    let jsonrpc: String
    let method: String
    let params: JSONValue?
}

struct JSONRPCIncomingMessage: Decodable, Sendable {
    let jsonrpc: String
    let id: String?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: JSONRPCErrorPayload?
}
