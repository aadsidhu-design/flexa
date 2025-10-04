import Foundation

/// Detailed session file structure for enhanced graphing capabilities
struct SessionFile: Codable, Identifiable {
    let id: String
    let exerciseType: String
    let timestamp: Date
    let romPerRep: [Double]        // ROM achieved in each rep (most important for graphing)
    let sparcHistory: [Double]     // SPARC values throughout session
    let romHistory: [Double]       // Raw ROM samples during session
    let maxROM: Double            // Peak ROM achieved
    let reps: Int                 // Total reps completed
    let sparcDataPoints: [SPARCPoint] // Real-time SPARC timeline for smoothness graphing

    /// Initialize session file with data from motion service
    init(
        id: String = UUID().uuidString,
        exerciseType: String,
        timestamp: Date,
        romPerRep: [Double],
        sparcHistory: [Double],
        romHistory: [Double],
        maxROM: Double,
        reps: Int,
        sparcDataPoints: [SPARCPoint] = []
    ) {
        self.id = id
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
        case id
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
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.exerciseType = try container.decode(String.self, forKey: .exerciseType)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.romPerRep = try container.decode([Double].self, forKey: .romPerRep)
        self.sparcHistory = try container.decode([Double].self, forKey: .sparcHistory)
        self.romHistory = try container.decode([Double].self, forKey: .romHistory)
        self.maxROM = try container.decode(Double.self, forKey: .maxROM)
        self.reps = try container.decode(Int.self, forKey: .reps)
        self.sparcDataPoints = try container.decodeIfPresent([SPARCPoint].self, forKey: .sparcDataPoints) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
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
            "id": id,
            "exerciseType": exerciseType,
            "timestamp": timestamp,
            "romPerRep": romPerRep,
            "sparcHistory": sparcHistory,
            "romHistory": romHistory,
            "maxROM": maxROM,
            "reps": reps,
            "sparcDataPoints": sparcDataPoints.map { [
                "timestamp": $0.timestamp,
                "sparc": $0.sparc
            ] }
        ]
    }
}
