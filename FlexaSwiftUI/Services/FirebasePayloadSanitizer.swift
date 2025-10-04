import Foundation
import CoreGraphics

/// Utility responsible for coercing arbitrary session payloads into Firestore-friendly values.
/// - Ensures no NaN/Infinite doubles
/// - Normalises numeric types to Firestore-supported variants
/// - Recursively sanitises arrays and dictionaries
/// - Removes values that cannot be encoded (e.g. unsupported classes)
struct FirebasePayloadSanitizer {
    static func sanitizeDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            guard let cleaned = sanitize(value) else { continue }
            result[key] = cleaned
        }
        return result
    }

    static func sanitize(_ value: Any) -> Any? {
        switch value {
        case let double as Double:
            return double.isFinite ? double : nil
        case let float as Float:
            let converted = Double(float)
            return converted.isFinite ? converted : nil
        case let cgFloat as CGFloat:
            let converted = Double(cgFloat)
            return converted.isFinite ? converted : nil
        case let int as Int:
            return int
        case let int8 as Int8:
            return Int(int8)
        case let int16 as Int16:
            return Int(int16)
        case let int32 as Int32:
            return Int(int32)
        case let int64 as Int64:
            return int64
        case let uint as UInt:
            return Int(uint)
        case let uint8 as UInt8:
            return Int(uint8)
        case let uint16 as UInt16:
            return Int(uint16)
        case let uint32 as UInt32:
            return Int(uint32)
        case let uint64 as UInt64:
            return uint64 <= UInt64(Int.max) ? Int(uint64) : nil
        case let bool as Bool:
            return bool
        case let string as String:
            return string
        case let date as Date:
            return date
        case let data as Data:
            return data
        case let timeInterval as TimeInterval:
            let converted = Double(timeInterval)
            return converted.isFinite ? converted : nil
        case let dict as [String: Any]:
            return sanitizeDictionary(dict)
        case let array as [Any]:
            let sanitized = array.compactMap { sanitize($0) }
            return sanitized
        case Optional<Any>.none:
            return nil
        case let optional as Optional<Any>:
            if let unwrapped = optional { return sanitize(unwrapped) }
            return nil
        case let number as NSNumber:
            // Distinguish between booleans and numeric numbers.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            let converted = number.doubleValue
            return converted.isFinite ? converted : nil
        default:
            return nil
        }
    }
}
