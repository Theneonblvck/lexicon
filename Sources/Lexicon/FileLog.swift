import Foundation

/// Lightweight append-only file logger used for development/verification. Writes
/// to /tmp/lexicon-capture.log so capture behavior can be observed without
/// relying on the unified logging system. Enabled whenever the env var
/// LEXICON_FILE_LOG is set, or always in this pre-release build.
enum FileLog {
    static let path = "/tmp/lexicon-capture.log"
    private static let queue = DispatchQueue(label: "com.lexicon.app.filelog")

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
