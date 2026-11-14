import Foundation
import SwiftUI

/// 札 #435（起動直後に操作が効かない／ホームに戻される）と #429（アプリの重さ）の**原因を数で取る記録**
/// （2026-11-04 判断）。
///
/// **UI テストのときだけ有効**（`-JPPreviewPerfProbe YES`・Debug のみ・`PreviewSession.perfProbe`）。
/// 無効のときは何も記録せず、アプリの動作は変えない。直しではなく、直す前に値を取るための仕組み。
///
/// 記録するもの（すべて起動からの経過 ms。起動 = `JourneyPhotoApp.init` で `markLaunch` した時点）:
/// - `sel`: `RootView` の `selection`（下のタブ）を書いた全箇所の「どこで・何から何へ」
/// - `task`: 起動後の `.task(id: auth.state)` の始めと終わり
/// - `stall`: メインスレッドの停止（画面の表示の刻み `CADisplayLink` の間隔が 100ms を超えた回数・最大の間隔）
/// - `body`: ホーム・マイページ・写真詳細の `body` を評価した回数
///
/// 見えない要素 `perf.probe`（`PerfProbeOverlay`）の `accessibilityValue` に `summary()` を出し、
/// UI テストが読む（`UITests/.../PerfProbeSupport.swift`・失敗したときは添付に残す）
///
/// **UI テストとの対応**（`Tools/pick-ui-tests.py` が PR の差分から関連 UI テストを選ぶ手がかり・2026-11-07）:
/// UI テストは `"perf.probe"`（見えない要素の識別子）の値を、`SmokeTests`（起動の見張り）と `CriticalFlowTests`
/// （失敗したときに添付に残す）と `PerformanceTests`（名指しで流す）から読む。識別子がこのファイルに無いと、
/// 関連テストを特定できず PR の検証が UI テストを全件流す（#493 は上限を超えて打ち切られた）
final class PerfRecorder: @unchecked Sendable {

    /// 本番（と UI テスト）で使う1つ。無効なら全部の口が何もしない
    static let shared = PerfRecorder(enabled: PreviewSession.perfProbe)

    /// body の評価を数える画面
    enum BodyScreen: String, CaseIterable, Sendable {
        case home
        case myPage
        case photoDetail
        /// 探す（`SearchView`・2026-11-13 札 #590「探すの検索が重い」）
        case search
    }

    struct SelectionEntry: Equatable, Sendable {
        let ms: Int
        let site: String
        let from: String
        let to: String
    }

    struct TaskSpan: Equatable, Sendable {
        let name: String
        let startMs: Int
        var endMs: Int?
    }

    /// 履歴の上限（暴走しても見えない要素の値を膨らませない）
    static let selectionCap = 200
    static let taskCap = 50
    /// 停止の一覧の上限（長いものから残す）
    static let stallEventCap = 12
    /// 出来事の一覧の上限（先に起きた順に残し、溢れた数は `+Ndropped` で残す・2026-11-07）
    static let eventCap = 64
    /// メインスレッドの積み(スタック)の見本の上限と、1 件に残す段の数（2026-11-07・`PerfMainSampler`）
    static let sampleCap = 16
    static let sampleFrameCap = 14

    let isEnabled: Bool
    private let clock: () -> TimeInterval
    /// 0ms の時刻（`PerfTimeline` も同じ起点にする・2026-11-13 札 #594）
    let origin: TimeInterval
    private let lock = NSLock()
    private var selections: [SelectionEntry] = []
    private var droppedSelections = 0
    private var tasks: [TaskSpan] = []
    private var bodyCounts: [BodyScreen: Int] = [:]
    private var stall = StallMeter()
    /// 100ms を超えた停止の一覧（起点と長さ）。長いものから `stallEventCap` 件だけ残す（2026-11-07・札 #435・#429）
    private var stallEvents: [StallEvent] = []
    /// 時刻付きの出来事（`event(_:)`）。停止の起点（`stalls=`）と突き合わせて「何の最中に止まったか」を見る
    private var events: [PerfEvent] = []
    private var droppedEvents = 0
    /// 残した名前（**同じ名前は最初の1回だけ**残す。`app.body` のように何度も起きるものが枠を使い切らないように）
    private var eventNames: Set<String> = []
    /// 名前ごとの回数（`hit(_:)`）
    private var hitCounts: [String: Int] = [:]
    /// 止まっている最中のメインスレッドの積み（`PerfMainSampler` が撮る）。止まった時刻と突き合わせて「何をしていたか」を見る
    private var samples: [PerfSample] = []
    /// 探すの語ごとの記録（`searchBody(query:)`・2026-11-13 札 #590）。語が替わるたびに1つ足す
    private var searchWindows: [SearchWindow] = []
    private var droppedSearchWindows = 0
    /// 撮影スポットを語で当てた（`SearchView.spotHits`）回数・合計・最大（起動から通して）
    private var spotHitsTotal = SearchWindow.SpotHits()

    /// - Parameter clock: 秒を返す時計（試験で差し替える）。作った時点を 0ms とする
    init(enabled: Bool, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.isEnabled = enabled
        self.clock = clock
        self.origin = clock()
    }

    /// 起動の0ms をここに合わせる（`JourneyPhotoApp.init`）。`shared` を作るだけ
    func markLaunch() {}

    private func elapsedMs() -> Int {
        Int(((clock() - origin) * 1000).rounded())
    }

    // MARK: - selection

    /// 下のタブを書いた。`site` は書いた場所の名前（`RootView.select(_:at:)` の呼び出し元）
    func recordSelection<T>(site: String, from: T, to: T) {
        guard isEnabled else { return }
        let now = elapsedMs()
        let entry = SelectionEntry(ms: now, site: site, from: "\(from)", to: "\(to)")
        lock.lock()
        defer { lock.unlock() }
        if selections.count < Self.selectionCap {
            selections.append(entry)
        } else {
            droppedSelections += 1
        }
    }

    // MARK: - task

    /// `.task` の始め。返す番号を `endTask` に渡す（無効のときは -1）
    @discardableResult
    func beginTask(_ name: String) -> Int {
        guard isEnabled else { return -1 }
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        guard tasks.count < Self.taskCap else { return -1 }
        tasks.append(TaskSpan(name: name, startMs: now, endMs: nil))
        return tasks.count - 1
    }

    func endTask(_ index: Int) {
        guard isEnabled, index >= 0 else { return }
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        guard tasks.indices.contains(index) else { return }
        tasks[index].endMs = now
    }

    // MARK: - stall

    /// 画面の表示の刻み（`CADisplayLink.timestamp`・秒）。前の刻みとの間隔を測る
    func recordFrame(at timestamp: TimeInterval) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        // 探すの語ごとの記録にも、刻みの間隔（最大）と 100ms を超えた回数を足す（札 #590）
        if let last = stall.lastTimestamp, !searchWindows.isEmpty, droppedSearchWindows == 0 {
            let gap = Int(((timestamp - last) * 1000).rounded())
            searchWindows[searchWindows.count - 1].addFrameGap(gap, thresholdMs: stall.thresholdMs)
        }
        // 刻みが戻ってきた時刻（`task=` と同じ時計）から長さを引くと、止まり始めた時刻になる。
        // どの処理の最中に止まったかを、`task=`・`sel=` の時刻と突き合わせて見られる
        guard let gapMs = stall.ingest(timestamp) else { return }
        let event = StallEvent(startMs: max(0, elapsedMs() - gapMs), gapMs: gapMs)
        if stallEvents.count < Self.stallEventCap {
            stallEvents.append(event)
        } else if let smallest = stallEvents.indices.min(by: { stallEvents[$0].gapMs < stallEvents[$1].gapMs }),
                  stallEvents[smallest].gapMs < gapMs {
            stallEvents[smallest] = event
        }
    }

    /// 裏に入った・戻った。**その間の空きを停止に数えない**
    func resetFrames() {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        stall.reset()
    }

    // MARK: - event

    /// 時刻付きの出来事を1つ残す（2026-11-07・札 #435 / #429。**測るだけで動作は変えない**）。**同じ名前は最初の1回だけ**。
    /// 名前は `画面.出来事` の短い語（始めは `>`・終わりは `<` を末尾に付ける）。無効のときは名前も作らない
    func event(_ name: @autoclosure () -> String) {
        guard isEnabled else { return }
        let now = elapsedMs()
        let label = name()
        lock.lock()
        defer { lock.unlock() }
        guard eventNames.insert(label).inserted else { return }
        if events.count < Self.eventCap {
            events.append(PerfEvent(ms: now, name: label))
        } else {
            droppedEvents += 1
        }
    }

    // MARK: - sample

    /// 止まっている最中のメインスレッドの積みを 1 件残す（`frames` は浅い方から）。上限を超えたら捨てる
    func recordSample(frames: [String]) {
        guard isEnabled else { return }
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        guard samples.count < Self.sampleCap else { return }
        samples.append(PerfSample(ms: now, frames: Array(frames.prefix(Self.sampleFrameCap))))
    }

    /// 止まっている最中の積みの見本を空にする（上限に達した後の停止も撮れるように・2026-11-11 旅のトランクの計測）。無効なら何もしない
    func clearSamples() {
        guard isEnabled else { return }
        lock.lock()
        samples = []
        lock.unlock()
    }

    /// 何度も起きる出来事を数える（2026-11-07・札 #435 / #429）。**1〜4 回目と、2 の累乗の回だけ**
    /// `名前#回数` として時刻つきで残す（`home.tile#8` が +9100 なら、8 回目の評価が 9100ms）。無効のときは何もしない
    func hit(_ name: @autoclosure () -> String) {
        guard isEnabled else { return }
        let now = elapsedMs()
        let key = name()
        // 段ごとの回数は通しの記録にも足す（`PerfTimeline`・2026-11-13 札 #594。こちらの枠が尽きても数える）
        PerfTimeline.shared.count(key)
        lock.lock()
        defer { lock.unlock() }
        guard hitCounts[key] != nil || hitCounts.count < 32 else { return }
        let n = (hitCounts[key] ?? 0) + 1
        hitCounts[key] = n
        guard n <= 4 || (n & (n - 1)) == 0 else { return }
        if events.count < Self.eventCap {
            events.append(PerfEvent(ms: now, name: "\(key)#\(n)"))
        } else {
            droppedEvents += 1
        }
    }

    /// 引き金になりうる出来事を、**そのときまでの評価回数つき**で残す（`home.seasonShelf.set{home=8,mosaic=8,tile=33,shelf=0}`）。
    /// 引き金どうしの間の差が、その引き金で何回描き直されたか（2026-11-07・札 #435 / #429）。同じ名前も毎回残す。無効なら何もしない
    func mark(_ label: @autoclosure () -> String) {
        guard isEnabled else { return }
        let now = elapsedMs()
        let text = label()
        lock.lock()
        defer { lock.unlock() }
        let counts = "{home=\(bodyCounts[.home] ?? 0),mosaic=\(hitCounts["home.mosaic.body"] ?? 0),"
            + "tile=\(hitCounts["home.tile.body"] ?? 0),shelf=\(hitCounts["home.shelf.body"] ?? 0)}"
        if events.count < Self.eventCap {
            events.append(PerfEvent(ms: now, name: text + counts))
        } else {
            droppedEvents += 1
        }
    }

    // MARK: - 探す（2026-11-13 札 #590「探すの検索が重い」）

    /// 探すの `body` を1回評価した（`let _ = PerfRecorder.shared.searchBody(query: query)`・body の頭で呼ぶ）。
    /// `bodyHit(.search)` と同じ数え方に加えて、**語ごとの記録**（`srch=`）に足す: 前の評価と語が違えば新しい語の記録を始める。
    /// 1字打つと、その字の語の記録に body の回数・撮影スポットを当てた回数と時間・刻みの間隔の最大が貯まる。
    /// 最初の語の記録を始めるときに、止まっている最中の積みの見本を空にする（起動の停止で枠を使い切らないように）
    func searchBody(query: String) {
        guard isEnabled else { return }
        bodyHit(.search)
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        if searchWindows.last?.query != query {
            if searchWindows.isEmpty, droppedSearchWindows == 0 { samples = [] }
            if searchWindows.count < Self.searchWindowCap {
                searchWindows.append(SearchWindow(query: query, startMs: now))
            } else {
                droppedSearchWindows += 1
                // 枠を使い切ったら、最後の記録を使い回さない（数が混ざる）。数えるのは止める
                return
            }
        }
        searchWindows[searchWindows.count - 1].bodies += 1
    }

    /// 撮影スポットを語で当てる（`SearchView.spotHits`）時間を測って足す。**無効のときは測らずにそのまま返す**
    func searchSpotHits<T>(_ body: () -> T) -> T {
        guard isEnabled else { return body() }
        let start = clock()
        let result = body()
        let ms = (clock() - start) * 1000
        lock.lock()
        defer { lock.unlock() }
        spotHitsTotal.add(ms)
        if !searchWindows.isEmpty, droppedSearchWindows == 0 {
            searchWindows[searchWindows.count - 1].spotHits.add(ms)
        }
        return result
    }

    /// 探すの `officialSpots` が書き換わった（`.onChange(of: officialSpots)`）回数と、その中で束ね直した時間を、
    /// 今の語の記録に足す（`c<回数>/<合計>ms`・2026-11-14 札 #590）。×で消した直後の 3.4 秒の止まり（回 1235）が、
    /// 撮影スポットの書き換え（発見の札の表紙の詳細を重ねた）の後に起きたかを数字で見る。**無効のときは測らずにそのまま走る**
    func searchSpotsChanged(_ body: () -> Void) {
        guard isEnabled else { return body() }
        let start = clock()
        body()
        let ms = (clock() - start) * 1000
        lock.lock()
        defer { lock.unlock() }
        if !searchWindows.isEmpty, droppedSearchWindows == 0 {
            searchWindows[searchWindows.count - 1].spotsChanged.add(ms)
        }
    }

    /// 語ごとの記録の上限（3回 ×「京」「京都」「（空）」「富」「富士」「富士山」「（空）」= 21 と、開いたときの空の分）
    static let searchWindowCap = 32

    // MARK: - body

    /// `body` を1回評価した。**評価ごとに1足す**（`let _ = PerfRecorder.shared.bodyHit(.home)`）。
    /// 最初の 2 回は出来事にも残す（`body.home#1`）
    func bodyHit(_ screen: BodyScreen) {
        guard isEnabled else { return }
        // 段ごとの回数は通しの記録にも足す（`PerfTimeline`・2026-11-13 札 #594）
        PerfTimeline.shared.count("body.\(screen.rawValue)")
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        bodyCounts[screen, default: 0] += 1
        let n = bodyCounts[screen, default: 0]
        if n <= 4 || (n & (n - 1)) == 0 {
            if events.count < Self.eventCap {
                events.append(PerfEvent(ms: now, name: "body.\(screen.rawValue)#\(n)"))
            } else {
                droppedEvents += 1
            }
        }
    }

    func bodyCount(_ screen: BodyScreen) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return bodyCounts[screen] ?? 0
    }

    // MARK: - 出力

    /// 見えない要素の値。**形を変えるときは `PerfProbeTests` も合わせる**:
    ///
    ///     sel=[+120ms home>search@tabs.set;…] | task=[#0 auth.state 80-310ms;…] | stall=2/180ms/540f | body=home:12,myPage:3,photoDetail:0 | t=1234ms | stalls=[+1750ms 1634ms;…] | ev=[+12 app.init.start;…] | samples=[+5300 Foo`bar^Baz`qux;…]
    func summary() -> String {
        let now = elapsedMs()
        lock.lock()
        defer { lock.unlock() }
        var sel = selections.map { "+\($0.ms)ms \($0.from)>\($0.to)@\($0.site)" }
        if droppedSelections > 0 { sel.append("+\(droppedSelections)dropped") }
        var task: [String] = []
        for (index, span) in tasks.enumerated() {
            let end: String
            if let endMs = span.endMs { end = "\(endMs)ms" } else { end = "…" }
            task.append("#\(index) \(span.name) \(span.startMs)-\(end)")
        }
        let body = BodyScreen.allCases.map { "\($0.rawValue):\(bodyCounts[$0] ?? 0)" }
        return "sel=[\(sel.joined(separator: ";"))]"
            + " | task=[\(task.joined(separator: ";"))]"
            + " | stall=\(stall.count)/\(stall.maxMs)ms/\(stall.frames)f"
            + " | body=\(body.joined(separator: ","))"
            + " | t=\(now)ms"
            // 後ろに足した（読む側は `key=` で引く）。起点の順。無ければ空
            + " | stalls=[\(stallEvents.sorted { $0.startMs < $1.startMs }.map { "+\($0.startMs)ms \($0.gapMs)ms" }.joined(separator: ";"))]"
            // さらに後ろ（2026-11-07）: 時刻付きの出来事。`+ms 名前`（ms は起動から）。起きた順。溢れた数は `+Ndropped`
            + " | ev=[\((events.map { "+\($0.ms) \($0.name)" } + (droppedEvents > 0 ? ["+\(droppedEvents)dropped"] : [])).joined(separator: ";"))]"
            // さらに後ろ（2026-11-07）: 止まっている最中のメインスレッドの積み。`+撮った ms 段^段^…`（浅い方＝いま実行中の処理が先）
            + " | samples=[\(samples.map { "+\($0.ms) " + $0.frames.joined(separator: "^") }.joined(separator: ";"))]"
            // さらに後ろ（2026-11-13 札 #590）: 撮影スポットを語で当てた 回数/合計/最大（起動から通して）と、探すの語ごとの記録
            + " | spot=\(spotHitsTotal.count)/\(spotHitsTotal.totalMs)ms/\(spotHitsTotal.maxMs)ms"
            + " | srch=[\((searchWindows.map(\.summary) + (droppedSearchWindows > 0 ? ["+\(droppedSearchWindows)dropped"] : [])).joined(separator: ";"))]"
    }
}

/// メインスレッドの停止の数え方（画面の表示の刻みの間隔が閾値を超えた回数・最大の間隔）。
/// 刻みを渡すだけの純粋な型にして、Linux の試験でも確かめる
struct StallMeter: Equatable {
    /// これを超える間隔を「停止」と数える（ミリ秒）。60Hz の1コマは約 16.7ms
    var thresholdMs: Double = 100
    private(set) var lastTimestamp: TimeInterval?
    /// 間隔が閾値を超えた回数
    private(set) var count = 0
    /// 最も長かった間隔（ミリ秒）
    private(set) var maxMs = 0
    /// 間隔を測った回数
    private(set) var frames = 0

    /// 閾値を超えた間隔（ミリ秒）を返す（超えなければ nil）
    @discardableResult
    mutating func ingest(_ timestamp: TimeInterval) -> Int? {
        defer { lastTimestamp = timestamp }
        guard let last = lastTimestamp else { return nil }
        let gapMs = (timestamp - last) * 1000
        frames += 1
        maxMs = max(maxMs, Int(gapMs.rounded()))
        guard gapMs > thresholdMs else { return nil }
        count += 1
        return Int(gapMs.rounded())
    }

    /// 次の刻みを「最初の1回」にする（裏から戻った直後の長い空きを数えない）
    mutating func reset() {
        lastTimestamp = nil
    }
}

/// 探すの語 1 つ分の記録（2026-11-13 札 #590）。語が画面の `body` に初めて来た時刻から、次の語が来るまで。
/// 形は `+1234ms 京都 b3 h9/3012ms/400ms g450ms s2 c1/80ms`（始めた ms・語・body の回数・撮影スポットを当てた 回数/合計/最大・
/// 刻みの間隔の最大・100ms を超えた回数・`officialSpots` が書き換わった回数/束ね直した合計（2026-11-14 に足した））。空の語は `(空)`。語の中の `;` `|` `[` `]` と空白は `_` に替える
struct SearchWindow: Equatable {
    /// 回数・合計・最大（ms・整数に丸めて出す）
    struct SpotHits: Equatable {
        var count = 0
        private var total = 0.0
        private var max = 0.0
        var totalMs: Int { Int(total.rounded()) }
        var maxMs: Int { Int(max.rounded()) }

        mutating func add(_ ms: Double) {
            count += 1
            total += ms
            max = Swift.max(max, ms)
        }
    }

    let query: String
    let startMs: Int
    var bodies = 0
    var spotHits = SpotHits()
    /// `officialSpots` が書き換わった回数・その中の時間（`searchSpotsChanged`・2026-11-14）
    var spotsChanged = SpotHits()
    /// 刻みの間隔の最大（ms）と、閾値を超えた回数
    private(set) var maxGapMs = 0
    private(set) var stalls = 0

    init(query: String, startMs: Int) {
        self.query = query
        self.startMs = startMs
    }

    mutating func addFrameGap(_ gapMs: Int, thresholdMs: Double) {
        maxGapMs = max(maxGapMs, gapMs)
        if Double(gapMs) > thresholdMs { stalls += 1 }
    }

    /// 値に出す語（区切りの字と空白を `_` に）
    static func label(_ query: String) -> String {
        guard !query.isEmpty else { return "(空)" }
        return String(query.map { ";|[]".contains($0) || $0.isWhitespace ? "_" : $0 })
    }

    var summary: String {
        "+\(startMs)ms \(Self.label(query)) b\(bodies) h\(spotHits.count)/\(spotHits.totalMs)ms/\(spotHits.maxMs)ms"
            + " g\(maxGapMs)ms s\(stalls) c\(spotsChanged.count)/\(spotsChanged.totalMs)ms"
    }
}

/// 止まっている最中のメインスレッドの積みの見本 1 件（撮った時刻と、浅い方からの段）
struct PerfSample: Equatable, Sendable {
    let ms: Int
    let frames: [String]
}

/// 時刻付きの出来事 1 件（起動から何 ms に何が起きたか）
struct PerfEvent: Equatable, Sendable {
    let ms: Int
    let name: String
}

/// 画面の出来事を残す印（`.perfMark("home.appear")`）。出たとき（`onAppear`）に `PerfRecorder.event` へ1つ。
/// 見た目も動きも変えない。無効のとき（本番）は何もしない
extension View {
    func perfMark(_ name: String) -> some View {
        onAppear { PerfRecorder.shared.event(name) }
    }
}

/// 100ms を超えた停止 1 件（起動から何 ms に止まり始め、何 ms 止まったか）
struct StallEvent: Equatable {
    let startMs: Int
    let gapMs: Int
}
