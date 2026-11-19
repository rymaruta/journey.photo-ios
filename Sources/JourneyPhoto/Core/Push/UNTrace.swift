import Foundation

/// 一時の枝 claude/xcode27-dm-time だけ: 通知の窓口（UNUserNotificationCenter）を呼んだ時間を、時刻つきでファイルに書く（#647）。
/// UI テストが `-JPUNTraceFile <path>` を渡したときだけ書く。アプリのログは UI テストのログに出ないため、ファイルを試験の側が読む
enum UNTrace {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var opened = false
    private static let wall: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ label: String, start: Date, main: Bool) {
        let ms = Date().timeIntervalSince(start) * 1000
        lock.lock(); defer { lock.unlock() }
        if !opened {
            opened = true
            if let path = UserDefaults.standard.string(forKey: "JPUNTraceFile"), !path.isEmpty {
                FileManager.default.createFile(atPath: path, contents: nil)
                handle = FileHandle(forWritingAtPath: path)
            }
        }
        guard let handle else { return }
        let line = "UN wall=\(wall.string(from: start)) main=\(main ? 1 : 0) ms=\(String(format: "%.1f", ms)) \(label)\n"
        handle.write(Data(line.utf8))
    }

    static func sync<T>(_ label: String, _ body: () -> T) -> T {
        let start = Date()
        let main = Thread.isMainThread
        let value = body()
        write(label, start: start, main: main)
        return value
    }

    static func async<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
        let start = Date()
        let main = Thread.isMainThread
        let value = try await body()
        write(label, start: start, main: main)
        return value
    }
}
