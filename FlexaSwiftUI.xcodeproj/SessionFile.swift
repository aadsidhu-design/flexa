import Foundation

struct SessionFile: Codable, Identifiable {
    var id: String { "\(exerciseType)-\(Int(timestamp.timeIntervalSince1970))-\(reps)" }
    
    let exerciseType: String
    let timestamp: Date
    let romPerRep: [Double]
    let sparcHistory: [Double]
    let romHistory: [Double]
    let maxROM: Double
    let reps: Int
    
    func toDictionary() -> [String: Any] {
        return [
            "exerciseType": exerciseType,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "romPerRep": romPerRep,
            "sparcHistory": sparcHistory,
            "romHistory": romHistory,
            "maxROM": maxROM,
            "reps": reps
        ]
    }
}

