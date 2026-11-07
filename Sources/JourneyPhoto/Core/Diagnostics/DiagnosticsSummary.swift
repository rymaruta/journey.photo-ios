import Foundation

/// MetricKit が OS から受け取った診断（クラッシュ・ハング・起動時間）を、端末のログ（`os.Logger`）に
/// 出す一行にする整形（2026-11-07 判断）。**サーバーには送らない**（新しい口は承認が要る・
/// プライバシーマニフェストにも「収集」を足さずに済む）。MetricKit に触らない純粋な部分だけをここに置き、
/// Linux の単体テストで確かめる（受け取り口は `MetricKitReceiver`）。
///
/// 見るとき: Mac の Console.app か `log show --predicate 'category == "MetricKit"'`、
/// 実機なら Xcode の Organizer（クラッシュ）と合わせて読む。
enum DiagnosticsSummary {

    /// 1行に入れる呼び出し履歴の長さ。`os.Logger` は長い文字列を途中で切る（目安 1KB）ので、
    /// 超える分は `chunks` で分けて出す
    static let chunkSize = 800
    /// 呼び出し履歴の出力の上限（文字数）。際限なくログを埋めない
    static let chunkLimit = 8_000

    static func crash(signal: Int?, exceptionType: Int?, exceptionCode: Int?,
                      terminationReason: String?, appVersion: String) -> String {
        "crash version=\(appVersion) signal=\(show(signal)) exceptionType=\(show(exceptionType)) "
            + "exceptionCode=\(show(exceptionCode)) termination=\(terminationReason ?? "-")"
    }

    static func hang(milliseconds: Double, appVersion: String) -> String {
        "hang version=\(appVersion) duration_ms=\(Int(milliseconds.rounded()))"
    }

    /// CPU・ディスク書き込みの上限超え（`kind` は "cpu" / "diskWrite"）
    static func exception(kind: String, appVersion: String) -> String {
        "\(kind)-exception version=\(appVersion)"
    }

    /// 起動（初回描画まで）の分布。`buckets` は (始まり ms, 終わり ms, 件数)。
    /// 時間の短い順のまま `0-500ms:12 500-1000ms:3` の形にする（件数 0 の区間は省く）
    static func launch(buckets: [(startMs: Double, endMs: Double, count: Int)], appVersion: String) -> String {
        let parts = buckets
            .filter { $0.count > 0 }
            .map { "\(Int($0.startMs.rounded()))-\(Int($0.endMs.rounded()))ms:\($0.count)" }
        let total = buckets.reduce(0) { $0 + $1.count }
        return "launch version=\(appVersion) samples=\(total) firstDraw=[\(parts.joined(separator: " "))]"
    }

    /// 長い文字列を `size` 文字ずつに分ける（全体で `limit` 文字まで・超えた分は捨てて最後に印を付ける）
    static func chunks(_ text: String, size: Int = chunkSize, limit: Int = chunkLimit) -> [String] {
        guard size > 0, !text.isEmpty else { return [] }
        let clipped = text.count > limit ? String(text.prefix(limit)) : text
        var result: [String] = []
        var index = clipped.startIndex
        while index < clipped.endIndex {
            let end = clipped.index(index, offsetBy: size, limitedBy: clipped.endIndex) ?? clipped.endIndex
            result.append(String(clipped[index..<end]))
            index = end
        }
        if text.count > limit { result.append("…(\(text.count - limit) 文字を省略)") }
        return result
    }

    private static func show(_ value: Int?) -> String { value.map(String.init) ?? "-" }
}
