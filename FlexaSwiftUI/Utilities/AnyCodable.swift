import Foundation

// Lightweight AnyCodable implementation for storing heterogeneous dictionaries in UserDefaults
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self.value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            self.value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            self.value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            self.value = stringVal
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            self.value = arr.map { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported AnyCodable value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intVal as Int:
            try container.encode(intVal)
        case let doubleVal as Double:
            try container.encode(doubleVal)
        case let boolVal as Bool:
            try container.encode(boolVal)
        case let stringVal as String:
            try container.encode(stringVal)
        case let dict as [String: Any]:
            let wrapped = dict.mapValues { AnyCodable($0) }
            try container.encode(wrapped)
        case let arr as [Any]:
            let wrapped = arr.map { AnyCodable($0) }
            try container.encode(wrapped)
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported AnyCodable value")
            throw EncodingError.invalidValue(value, context)
        }
    }
}
