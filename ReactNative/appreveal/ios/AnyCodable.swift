// Type-erased Codable wrapper for heterogeneous JSON values

import Foundation

public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) {
        // Unwrap nested AnyCodable to avoid double-wrapping
        if let codable = value as? AnyCodable {
            self.value = codable.value
        } else {
            self.value = value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let codable as AnyCodable:
            try codable.encode(to: encoder)
        case let array as [AnyCodable]:
            try container.encode(array)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: AnyCodable]:
            try container.encode(dict)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }

    // Convenience accessors
    public var stringValue: String? { value as? String }
    public var intValue: Int? {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch value {
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let number as NSNumber:
            return number.doubleValue
        default:
            return nil
        }
    }
    public var boolValue: Bool? { value as? Bool }
    public var arrayValue: [Any]? { value as? [Any] }
    public var dictionaryValue: [String: AnyCodable]? {
        guard let dict = value as? [String: Any] else { return nil }
        return dict.mapValues { AnyCodable($0) }
    }
}
