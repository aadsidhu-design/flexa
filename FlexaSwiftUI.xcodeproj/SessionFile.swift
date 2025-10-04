import Foundation

struct SessionFile: Codable, Identifiable {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var id: String { "\(exerciseType)-\(Int(timestamp.timeIntervalSince1970))-\(reps)" }
    
    let exerciseType: String
    let timestamp: Date
    let romPerRep: [Double]
    let sparcHistory: [Double]
    let romHistory: [Double]
    let maxROM: Double
    let reps: Int
    let sparcDataPoints: [SPARCPoint]

    init(
        exerciseType: String,
        timestamp: Date,
        romPerRep: [Double],
        sparcHistory: [Double],
        romHistory: [Double],
        maxROM: Double,
        reps: Int,
        sparcDataPoints: [SPARCPoint] = []
    ) {
        self.exerciseType = exerciseType
        self.timestamp = timestamp
        self.romPerRep = romPerRep
        self.sparcHistory = sparcHistory
        self.romHistory = romHistory
        self.maxROM = maxROM
        self.reps = reps
        self.sparcDataPoints = sparcDataPoints
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseType
        case timestamp
        case romPerRep
        case sparcHistory
        case romHistory
        case maxROM
        case reps
        case sparcDataPoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseType = try container.decode(String.self, forKey: .exerciseType)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        romPerRep = try container.decode([Double].self, forKey: .romPerRep)
        sparcHistory = try container.decode([Double].self, forKey: .sparcHistory)
        romHistory = try container.decode([Double].self, forKey: .romHistory)
        maxROM = try container.decode(Double.self, forKey: .maxROM)
        reps = try container.decode(Int.self, forKey: .reps)
        sparcDataPoints = try container.decodeIfPresent([SPARCPoint].self, forKey: .sparcDataPoints) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exerciseType, forKey: .exerciseType)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(romPerRep, forKey: .romPerRep)
        try container.encode(sparcHistory, forKey: .sparcHistory)
        try container.encode(romHistory, forKey: .romHistory)
        try container.encode(maxROM, forKey: .maxROM)
        try container.encode(reps, forKey: .reps)
        if !sparcDataPoints.isEmpty {
            try container.encode(sparcDataPoints, forKey: .sparcDataPoints)
        }
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "exerciseType": exerciseType,
            "timestamp": SessionFile.isoFormatter.string(from: timestamp),
            "romPerRep": romPerRep,
            "sparcHistory": sparcHistory,
            "romHistory": romHistory,
            "maxROM": maxROM,
            "reps": reps,
            "sparcDataPoints": sparcDataPoints.map { [
                "timestamp": SessionFile.isoFormatter.string(from: $0.timestamp),
                "sparc": $0.sparc
            ]}
        ]
    }
}

