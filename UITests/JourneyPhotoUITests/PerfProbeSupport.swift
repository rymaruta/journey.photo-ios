import XCTest

/// 起動直後の動きの記録（アプリの `PerfRecorder`・見えない要素 `perf.probe`）を、UI テストから読む・残す道具
/// （2026-11-04・札 #435 起動直後に操作が効かない／ホームに戻される・#429 アプリの重さ）。
///
/// **使い方**
/// - 起動の引数に `enablePerfProbe(app)` を足す（`-JPPreviewPerfProbe YES`・Debug のみ。足さなければ要素は出ない）
/// - 失敗したときに残したいテストは、起動の後に `attachPerfProbeOnFailure(app)` を1回呼ぶ。
///   失敗したテストの終わりに、記録を**ログ（`PERF-PROBE …` の1行）と添付（`perf.probe`・keepAlways）**に残す
/// - 数を取りたいテストは `perfProbeValue(app)` で文字列を読み、`PerfProbeReading` で分ける
///
/// 値の形（アプリの `PerfRecorder.summary()` と同じ。変えるときは両方）:
///
///     sel=[+120ms home>search@tabs.set;…] | task=[#0 auth.state.sync 80-310ms;…] | stall=2/180ms/540f | body=home:12,myPage:3,photoDetail:0,search:5 | t=1234ms | stalls=[+1750ms 1634ms;…] | ev=[+12 app.init.start;…] | samples=[+5300 SwiftUI`xxx^JourneyPhoto`yyy;…] | spot=9/3012ms/400ms | srch=[+2000ms 京 b3 h9/3012ms/400ms g450ms s2;…]
extension XCTestCase {

    /// 起動の引数に足す（`app.launch()` の前）
    func enablePerfProbe(_ app: XCUIApplication) {
        app.launchArguments += ["-JPPreviewPerfProbe", "YES"]
    }

    /// 見えない要素の今の値。要素が無い（足していない・まだ出ていない・落ちている）ときは nil
    func perfProbeValue(_ app: XCUIApplication) -> String? {
        guard app.state == .runningForeground || app.state == .runningBackground else { return nil }
        let probe = app.descendants(matching: .any)[PerfProbeReading.identifier].firstMatch
        guard probe.exists else { return nil }
        return probe.value as? String
    }

    /// `-[PerformanceTests testLaunchProbe]` の `testLaunchProbe`（空白を含まない名前）
    var perfTestName: String {
        let last = name.split(separator: " ").last.map(String.init) ?? name
        return last.replacingOccurrences(of: "]", with: "")
    }

    /// 記録を1行でログに残し、添付にもする。**ログには `XCTContext.runActivity` でも出す**
    /// （`print` が Mac のログに出るかは確かめていない。活動の名前は出る——`PerformanceTests` の `PERF` と同じ）
    @discardableResult
    func notePerfProbe(_ app: XCUIApplication, label: String) -> String {
        let value = perfProbeValue(app) ?? "perf.probe が読めない"
        let line = "PERF-PROBE label=\(label) test=\(perfTestName) \(value)"
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        let note = XCTAttachment(string: line)
        note.name = "perf.probe \(label)"
        note.lifetime = .keepAlways
        add(note)
        return value
    }

    /// このテストが失敗したら、終わりに記録を残す（`addTeardownBlock`・テスト本体の後、アプリを閉じる前）
    func attachPerfProbeOnFailure(_ app: XCUIApplication) {
        addTeardownBlock { [weak self] in
            guard let self, let run = self.testRun, run.totalFailureCount > 0 else { return }
            self.notePerfProbe(app, label: "failure")
        }
    }
}

/// `perf.probe` の値を分けて読む。空・読めない部分は 0 や空にする（落とさない）
struct PerfProbeReading {
    static let identifier = "perf.probe"

    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    /// `"sel=[…] | task=[…] | …"` の `key=` の右（`[` `]` は外す）
    func section(_ key: String) -> String {
        for part in raw.components(separatedBy: " | ") where part.hasPrefix(key + "=") {
            var value = String(part.dropFirst(key.count + 1))
            if value.hasPrefix("["), value.hasSuffix("]") { value = String(value.dropFirst().dropLast()) }
            return value
        }
        return ""
    }

    /// `selection` を書いた履歴（`+120ms home>search@tabs.set` の並び）
    var selections: [String] {
        section("sel").split(separator: ";").map(String.init).filter { !$0.isEmpty }
    }

    /// 100ms を超えた停止の一覧（`+1750ms 1634ms` の並び・起動から止まり始めた時刻と長さ・2026-11-07）
    var stalls: [String] {
        section("stalls").split(separator: ";").map(String.init).filter { !$0.isEmpty }
    }

    /// 時刻付きの出来事の一覧（`+812 app.body` の並び・起動からの ms と名前・起きた順・2026-11-07）。
    /// 末尾の `+Ndropped` は溢れた数
    var events: [String] {
        section("ev").split(separator: ";").map(String.init).filter { !$0.isEmpty }
    }

    /// 止まっている最中のメインスレッドの積みの見本（`+5300 SwiftUI`xxx^JourneyPhoto`yyy` の並び・撮った ms と浅い方からの段・2026-11-07）
    var samples: [String] {
        section("samples").split(separator: ";").map(String.init).filter { !$0.isEmpty }
    }

    /// body の評価回数（`home`・`myPage`・`photoDetail`・`search`）
    func bodyCount(_ screen: String) -> Int {
        for pair in section("body").split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2, kv[0] == screen { return Int(kv[1]) ?? 0 }
        }
        return 0
    }

    /// メインスレッドの停止: (100ms を超えた回数, 最大の間隔 ms)。`2/180ms/540f` の形
    var stall: (count: Int, maxMs: Int) {
        let parts = section("stall").split(separator: "/")
        let count = parts.first.flatMap { Int($0) } ?? 0
        let maxMs = parts.count > 1 ? Int(parts[1].replacingOccurrences(of: "ms", with: "")) ?? 0 : 0
        return (count, maxMs)
    }
}
