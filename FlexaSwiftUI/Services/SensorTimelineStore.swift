import Foundation

struct SensorTimeline: Codable {
    let dt: Double // seconds per sample
    let accel: [Double] // |g|
    let gyro: [Double]  // |rad/s|
    let sparc: [Double]? // optional SPARC timeline (abs)
}

extension LocalDataManager {
    private var sensorDirName: String { "sensor_timelines" }
    
    private func sensorDirectoryURL() -> URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let base = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent(sensorDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private func sensorFilename(exerciseType: String, timestamp: Date) -> String {
        let safeType = exerciseType.replacingOccurrences(of: " ", with: "_").lowercased()
        let epoch = Int(timestamp.timeIntervalSince1970)
        return "sensor_\(safeType)_\(epoch).json"
    }
    
    func saveSensorTimeline(exerciseType: String, timestamp: Date, data: SensorTimeline) {
        let url = sensorDirectoryURL().appendingPathComponent(sensorFilename(exerciseType: exerciseType, timestamp: timestamp))
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            let payload = try enc.encode(data)
            try payload.write(to: url, options: .atomic)
            print("💾 [LOCAL] Saved sensor timeline at \(url.lastPathComponent) (", data.accel.count, "samples)")
        } catch {
            print("⚠️ [LOCAL] Failed saving sensor timeline: \(error)")
        }
    }
    
    func loadSensorTimeline(exerciseType: String, timestamp: Date, toleranceSec: TimeInterval = 300) -> SensorTimeline? {
        let dir = sensorDirectoryURL()
        do {
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            let safeType = exerciseType.replacingOccurrences(of: " ", with: "_").lowercased()
            let targetEpoch = timestamp.timeIntervalSince1970
            let candidates = files.filter { $0.lastPathComponent.hasPrefix("sensor_\(safeType)_") }
            let best = candidates.min(by: { a, b in
                let ea = extractEpoch(from: a.lastPathComponent) ?? .infinity
                let eb = extractEpoch(from: b.lastPathComponent) ?? .infinity
                return abs(ea - targetEpoch) < abs(eb - targetEpoch)
            })
            if let best = best, let epoch = extractEpoch(from: best.lastPathComponent), abs(epoch - targetEpoch) <= toleranceSec {
                let data = try Data(contentsOf: best)
                let dec = JSONDecoder()
                let timeline = try dec.decode(SensorTimeline.self, from: data)
                return timeline
            }
        } catch {
            print("⚠️ [LOCAL] Failed loading sensor timeline: \(error)")
        }
        return nil
    }
    
    private func extractEpoch(from filename: String) -> TimeInterval? {
        // sensor_<type>_<epoch>.json
        guard let underscore = filename.lastIndex(of: "_") else { return nil }
        let start = filename.index(after: underscore)
        let end = filename.lastIndex(of: ".") ?? filename.endIndex
        let substr = filename[start..<end]
        return TimeInterval(substr)
    }
}
