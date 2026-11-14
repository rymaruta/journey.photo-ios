import Foundation

/// **アプリが前に居るまま終わったか**を、次に開いたときに知るための小さな足跡（2026-11-14 判断・札 #596）。
///
/// owner の報告「ストーリーを開いた瞬間に落ちる」で、TestFlight の落ちた記録が 0 件だった。メモリの上限で OS に
/// 止められた（jetsam）回は、落ちた知らせもクラッシュ報告も出ない。だから**本番の版でも**、ストーリーを開く・
/// 絵が出る、の段ごとに「最後の段とメモリ量」だけを端末に書いておき、次に開いたときに
/// 「前に居るまま終わった（背面へ行かなかった）」なら、その最後の段を1件だけ残す。
///
/// - 書くのは**決まった短い段の名前・数（束の数・位置）・メモリ（MB）・版・時刻**だけ。写真・ストーリーの id・
///   端末の識別子・利用者の情報は入れない
/// - 端末の中だけ（`UserDefaults`）。**外へ出るのは、利用者が「意見を送る」で添えたときだけ**（`FeedbackSheet`）
/// - 背面へ行ったら「前に居ない」に替える。背面で OS に止められる・アプリの切り替えで上へ払って閉じる、は
///   ふつうの終わりなので残さない
/// - MetricKit の知らせ（前回までのクラッシュ・前面での終わり方の回数）も、短い1行にしてここに残す（`MetricKitReceiver`）
enum ExitTrail {

    /// いまの足跡（段ごとに書き換える）
    struct Mark: Codable, Equatable {
        var step: String
        var memMB: Int
        var at: Date
        var version: String
        /// 前に居るか（背面へ行ったら false）
        var foreground: Bool
    }

    /// 前に居るまま終わった回の足跡（次に開いたときに残す）
    struct Record: Codable, Equatable {
        var step: String
        var memMB: Int
        var at: Date
        var version: String
    }

    static let markKey = "exitTrail.mark"
    static let recordKey = "exitTrail.record"
    static let metricKey = "exitTrail.metric"
    /// 段の名前の長さの上限（決まった名前しか渡さないが、念のため）
    static let stepMax = 60

    private static let lock = NSLock()

    // MARK: - 書く

    /// 段を書く（前に居る）。メインでも裏でも呼べる。重さは `UserDefaults` に小さい値を1つ書くだけ
    static func mark(_ step: String, defaults: UserDefaults = .standard, now: Date = Date(),
                     memoryBytes: Int? = PerfTimeline.physFootprint(), version: String = currentVersion) {
        let value = Mark(step: String(step.prefix(stepMax)), memMB: (memoryBytes ?? 0) / 1_048_576,
                         at: now, version: version, foreground: true)
        write(value, key: markKey, defaults: defaults)
    }

    /// 背面へ行った（ここで止められても、前に居るまま終わったことにはしない）
    static func enteredBackground(defaults: UserDefaults = .standard, now: Date = Date(),
                                  memoryBytes: Int? = PerfTimeline.physFootprint(), version: String = currentVersion) {
        let value = Mark(step: "app.background", memMB: (memoryBytes ?? 0) / 1_048_576,
                         at: now, version: version, foreground: false)
        write(value, key: markKey, defaults: defaults)
    }

    /// 起動したときに1回。**前回の足跡が「前に居る」のままなら、前に居るまま終わった**として残し、足跡を新しくする。
    /// - Returns: 今回残した記録（無ければ nil）
    @discardableResult
    static func launched(defaults: UserDefaults = .standard, now: Date = Date(),
                         memoryBytes: Int? = PerfTimeline.physFootprint(), version: String = currentVersion) -> Record? {
        var kept: Record?
        if let previous: Mark = read(markKey, defaults: defaults), previous.foreground {
            let record = Record(step: previous.step, memMB: previous.memMB, at: previous.at, version: previous.version)
            write(record, key: recordKey, defaults: defaults)
            kept = record
        }
        // 起動の印は「前に居ない」で書く。前に出たら `app.active` が替える（OS に裏で起こされたまま止められた回を、
        // 前に居るまま終わったと数えない）
        let launch = Mark(step: "app.launch", memMB: (memoryBytes ?? 0) / 1_048_576, at: now, version: version,
                          foreground: false)
        write(launch, key: markKey, defaults: defaults)
        return kept
    }

    /// MetricKit の知らせを1行で残す（新しいものが来たら替える）
    static func keepMetric(_ line: String, defaults: UserDefaults = .standard) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(String(line.prefix(metricMax)), forKey: metricKey)
    }

    static let metricMax = 400

    /// 送り終えた・利用者が外した（添えたものを2度送らない）
    static func clear(defaults: UserDefaults = .standard) {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: recordKey)
        defaults.removeObject(forKey: metricKey)
    }

    // MARK: - 読む

    static func record(defaults: UserDefaults = .standard) -> Record? { read(recordKey, defaults: defaults) }

    static func metric(defaults: UserDefaults = .standard) -> String? {
        lock.lock(); defer { lock.unlock() }
        return defaults.string(forKey: metricKey)
    }

    /// 意見に添える文（無ければ nil）。**`limit` 文字（UTF-16）に収める**（意見の本文の上限の残り）
    static func attachment(defaults: UserDefaults = .standard, limit: Int) -> String? {
        summary(record: record(defaults: defaults), metric: metric(defaults: defaults), limit: limit)
    }

    /// 添える文の形（試験で見る）。例:
    /// `[終了の記録] 1.1.87 (3) 2026-11-14T10:00:00Z step=story.open n=2 i=0 mem=812MB` と、MetricKit の1行
    static func summary(record: Record?, metric: String?, limit: Int) -> String? {
        var lines: [String] = []
        if let record {
            lines.append("[終了の記録] \(record.version) \(iso.string(from: record.at)) step=\(record.step) mem=\(record.memMB)MB")
        }
        if let metric, !metric.isEmpty { lines.append("[MetricKit] \(metric)") }
        guard !lines.isEmpty, limit > 0 else { return nil }
        let text = lines.joined(separator: "\n")
        guard text.utf16.count > limit else { return text }
        // 収まらない分は後ろから落とす（字の途中で切らない）
        var cut = ""
        for character in text {
            if (cut + String(character)).utf16.count > limit { break }
            cut.append(character)
        }
        return cut.isEmpty ? nil : cut
    }

    // MARK: - 中身

    static var currentVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func write<T: Encodable>(_ value: T, key: String, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        lock.lock(); defer { lock.unlock() }
        defaults.set(data, forKey: key)
    }

    private static func read<T: Decodable>(_ key: String, defaults: UserDefaults) -> T? {
        lock.lock()
        let data = defaults.data(forKey: key)
        lock.unlock()
        return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
