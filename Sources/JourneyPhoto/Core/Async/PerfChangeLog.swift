import Foundation
import SwiftUI
#if os(iOS) && DEBUG
import Darwin
#endif

/// **画面の body が「なぜ」評価し直されたか**を数える（2026-11-14・札 #594 の下調べ。直しではなく、直す前の事実取り）。
///
/// run 1231（`testUsageSurveyProbe`）で、ホームにいない段（地図・DM・投稿）でもホームの格子（`home.tile.body`）が
/// 60〜135 回、ホームの body が数回評価し直されていた。どの状態（`@EnvironmentObject`・`@State`・親から渡された値）
/// の変化が引き金かを、SwiftUI 自身の答え（`View._printChanges()`・body の評価ごとに
/// `GalleryView: @self, _auth changed.` を標準出力に書く）から取る。
///
/// - 画面の body の頭で `let _ = PerfChangeLog.note(Self.self)` を呼ぶ（UI テストのときだけ `_printChanges` を呼ぶ）
/// - 標準出力を管（pipe）につなぎ替え、行を読んで `PerfTimeline` に `chg.<画面>.<理由>` で数える。
///   読んだ行は元の標準出力にもそのまま書く（消さない）
///
/// **UI テストのときだけ**（`-JPPreviewPerfProbe YES`・Debug のみ）。本番は `note` が何もしない
enum PerfChangeLog {

    /// body の評価の理由を書かせる（無効なら何もしない）
    @MainActor
    static func note<V: View>(_ type: V.Type) {
        guard PerfRecorder.shared.isEnabled else { return }
        V._printChanges()
    }

    /// `_printChanges` の 1 行から数える名前を作る（`chg.GalleryView._auth` など）。形が違えば空。
    ///
    ///     "GalleryView: @self, _auth changed." → ["chg.GalleryView.@self", "chg.GalleryView._auth"]
    ///     "HomeFeedTile: unchanged."           → ["chg.HomeFeedTile.unchanged"]
    static func keys(fromLine line: String) -> [String] {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = text.range(of: ": ") else { return [] }
        let rawView = String(text[..<colon.lowerBound])
        // 総称の型は `<` の前まで（`Foo<Bar>` → `Foo`）。空白を含むものは別の出力
        let view = rawView.split(separator: "<").first.map(String.init) ?? rawView
        guard !view.isEmpty, !view.contains(" ") else { return [] }
        let rest = String(text[colon.upperBound...])
        if rest == "unchanged." { return ["chg.\(view).unchanged"] }
        guard rest.hasSuffix(" changed.") else { return [] }
        let names = rest.dropLast(" changed.".count).components(separatedBy: ", ").filter { !$0.isEmpty }
        return names.map { "chg.\(view).\($0)" }
    }

    #if os(iOS) && DEBUG
    nonisolated(unsafe) private static var started = false

    /// 標準出力を読み始める（`PerfStallWatcher.start` から・主スレッド）
    static func start() {
        guard PerfRecorder.shared.isEnabled, !started else { return }
        started = true
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return }
        let original = dup(STDOUT_FILENO)
        fflush(stdout)
        // 管につなぐと標準出力は既定でまとめ書きになり、行が遅れて届く（段の境目をまたぐ）。1 行ずつにする
        setvbuf(stdout, nil, _IOLBF, 0)
        guard original >= 0, dup2(fds[1], STDOUT_FILENO) >= 0 else { return }
        close(fds[1])
        let readEnd = fds[0]
        let thread = Thread {
            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = read(readEnd, &buffer, buffer.count)
                if n <= 0 { break }
                _ = buffer.withUnsafeBytes { write(original, $0.baseAddress, n) }
                pending.append(contentsOf: buffer[0..<n])
                while let newline = pending.firstIndex(of: 0x0A) {
                    let lineData = pending[pending.startIndex..<newline]
                    pending.removeSubrange(pending.startIndex...newline)
                    guard let line = String(data: lineData, encoding: .utf8) else { continue }
                    for key in keys(fromLine: line) { PerfTimeline.shared.count(key) }
                }
            }
        }
        thread.name = "perf.changes"
        thread.qualityOfService = .utility
        thread.start()
    }
    #else
    static func start() {}
    #endif
}
