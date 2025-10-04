import Foundation

final class Logger {
    static let shared = Logger()
    private let fileURL: URL

    private init() {
        let fm = FileManager.default
        let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        fileURL = docs!.appendingPathComponent("app.log")
    }

    func info(_ msg: String) {
        write(level: "INFO", msg: msg)
    }
    func warn(_ msg: String) {
        write(level: "WARN", msg: msg)
    }
    func error(_ msg: String) {
        write(level: "ERROR", msg: msg)
    }

    private func write(level: String, msg: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let fh = try? FileHandle(forWritingTo: fileURL) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    try? fh.close()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
