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

    /// 前面での終わり方の回数（`MXAppExitMetric.foregroundExitData`・札 #596・2026-11-14）。
    /// `memory` がメモリの上限で OS に止められた回（jetsam）。クラッシュ報告が出ない終わり方も数に入る
    static func foregroundExits(normal: Int, memory: Int, abnormal: Int, badAccess: Int, illegal: Int,
                                watchdog: Int, appVersion: String) -> String {
        "fgExit version=\(appVersion) normal=\(normal) memoryLimit=\(memory) abnormal=\(abnormal) "
            + "badAccess=\(badAccess) illegalInstruction=\(illegal) watchdog=\(watchdog)"
    }

    /// 呼び出し履歴（`MXCallStackTree.jsonRepresentation`）から、**落ちたスレッドの上から `limit` 個**を
    /// `名前+0x位置` の形で取り出す（札 #596）。位置は実行ファイルの中の場所（`offsetIntoBinaryTextSegment`）で、
    /// 版の dSYM があれば行に直せる。利用者・端末の情報は入っていない。読めなければ nil
    static func crashedFrames(_ json: Data, limit: Int = 8) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]] else { return nil }
        let thread = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
        var frame = (thread?["callStackRootFrames"] as? [[String: Any]])?.first
        var names: [String] = []
        while let current = frame, names.count < limit {
            let binary = (current["binaryName"] as? String) ?? "?"
            let offset = (current["offsetIntoBinaryTextSegment"] as? NSNumber)?.intValue
            names.append(offset.map { "\(binary)+0x\(String($0, radix: 16))" } ?? binary)
            frame = (current["subFrames"] as? [[String: Any]])?.first
        }
        return names.isEmpty ? nil : names.joined(separator: " ")
    }

    private static func show(_ value: Int?) -> String { value.map(String.init) ?? "-" }
}
