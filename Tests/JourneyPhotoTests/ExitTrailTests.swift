import XCTest
@testable import JourneyPhoto

/// 前に居るまま終わったときの足跡（札 #596・2026-11-14・`ExitTrail`）
final class ExitTrailTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "ExitTrailTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// 前に居るまま（背面へ行かずに）次の起動が来たら、最後の段とメモリを1件残す
    func testForegroundEndIsKeptWithLastStepAndMemory() {
        ExitTrail.launched(defaults: defaults, now: t0, memoryBytes: 50 << 20, version: "1.1.87 (3)")
        ExitTrail.mark("app.active", defaults: defaults, now: t0, memoryBytes: 60 << 20, version: "1.1.87 (3)")
        ExitTrail.mark("story.viewer.open n=2 i=0", defaults: defaults, now: t0.addingTimeInterval(5),
                       memoryBytes: 812 << 20, version: "1.1.87 (3)")
        // ここで OS に止められた（何も書かれない）→ 次の起動
        let kept = ExitTrail.launched(defaults: defaults, now: t0.addingTimeInterval(60), memoryBytes: 40 << 20,
                                      version: "1.1.87 (3)")
        XCTAssertEqual(kept, ExitTrail.Record(step: "story.viewer.open n=2 i=0", memMB: 812,
                                              at: t0.addingTimeInterval(5), version: "1.1.87 (3)"))
        XCTAssertEqual(ExitTrail.record(defaults: defaults), kept)
        let text = ExitTrail.attachment(defaults: defaults, limit: 400)
        XCTAssertEqual(text, "[終了の記録] 1.1.87 (3) 2027-01-15T08:00:05Z step=story.viewer.open n=2 i=0 mem=812MB")
    }

    /// 背面へ行ってから止められた（アプリの切り替えで閉じた・裏で止められた）回は残さない。
    /// 起動しただけ（前に出ていない・OS に裏で起こされた）回も残さない
    func testBackgroundEndAndBackgroundLaunchAreNotKept() {
        ExitTrail.launched(defaults: defaults, now: t0, memoryBytes: nil, version: "v")
        ExitTrail.mark("story.viewer.open n=1 i=0", defaults: defaults, now: t0, memoryBytes: nil, version: "v")
        ExitTrail.enteredBackground(defaults: defaults, now: t0, memoryBytes: nil, version: "v")
        XCTAssertNil(ExitTrail.launched(defaults: defaults, now: t0, memoryBytes: nil, version: "v"))
        // 起動の印だけ（`app.active` が来ないまま次の起動）
        XCTAssertNil(ExitTrail.launched(defaults: defaults, now: t0, memoryBytes: nil, version: "v"))
        XCTAssertNil(ExitTrail.record(defaults: defaults))
        XCTAssertNil(ExitTrail.attachment(defaults: defaults, limit: 400))
    }

    /// MetricKit の1行も添える。消したら両方消える。上限に収める
    func testMetricLineAndClearAndLimit() {
        ExitTrail.mark("story.media ok i=0/2", defaults: defaults, now: t0, memoryBytes: 1 << 20, version: "v")
        ExitTrail.launched(defaults: defaults, now: t0, memoryBytes: nil, version: "v")
        ExitTrail.keepMetric("fgExit version=1.1.87 normal=3 memoryLimit=2 abnormal=0", defaults: defaults)
        let text = ExitTrail.attachment(defaults: defaults, limit: 400) ?? ""
        XCTAssertTrue(text.contains("step=story.media ok i=0/2 mem=1MB"), text)
        XCTAssertTrue(text.hasSuffix("[MetricKit] fgExit version=1.1.87 normal=3 memoryLimit=2 abnormal=0"), text)
        XCTAssertLessThanOrEqual(ExitTrail.attachment(defaults: defaults, limit: 30)?.utf16.count ?? 0, 30)
        ExitTrail.clear(defaults: defaults)
        XCTAssertNil(ExitTrail.attachment(defaults: defaults, limit: 400))
    }

    /// 段の名前に id・写真を入れていない（決まった名前と数だけ）。本番の版でも書く（`#if DEBUG` で囲まない）
    func testStepsCarryNoIdentifiersAndRunInRelease() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = ["Sources/JourneyPhoto/Features/Stories/StoryViewerView.swift",
                     "Sources/JourneyPhoto/Features/Stories/StoriesRow.swift",
                     "Sources/JourneyPhoto/Features/Stories/StoryAvatar.swift"]
        var marks: [String] = []
        for file in files {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            marks += text.components(separatedBy: "\n").filter { $0.contains("ExitTrail.mark(") }
        }
        XCTAssertGreaterThanOrEqual(marks.count, 6, "閲覧画面・輪を押した所の足跡が足りない")
        for line in marks {
            XCTAssertFalse(line.contains(".id") || line.contains("userId") || line.contains("src") || line.contains("caption"),
                           "足跡に id・中身を入れている: \(line)")
        }
        let delegate = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/App/AppDelegate.swift"), encoding: .utf8)
        XCTAssertTrue(delegate.contains("ExitTrail.launched()"))
        let app = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/App/JourneyPhotoApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("ExitTrail.enteredBackground()"))
        XCTAssertTrue(app.contains("ExitTrail.mark(\"app.active\")"))
        let trail = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Core/Diagnostics/ExitTrail.swift"), encoding: .utf8)
        XCTAssertFalse(trail.contains("#if DEBUG"), "本番の版でも書く")
    }

    /// 意見の本文に添える。**サーバーの上限 1000（UTF-16）を超えない**——記録の方を切る
    func testFeedbackBodyStaysWithinTheServerLimit() {
        XCTAssertEqual(FeedbackSheet.body(text: "落ちました", trail: nil), "落ちました")
        XCTAssertEqual(FeedbackSheet.body(text: "落ちました", trail: "[終了の記録] x"), "落ちました\n\n[終了の記録] x")
        let long = String(repeating: "あ", count: 990)
        let body = FeedbackSheet.body(text: long, trail: String(repeating: "x", count: 300))
        XCTAssertEqual(body.utf16.count, FeedbackService.textMax)
        XCTAssertEqual(FeedbackSheet.body(text: String(repeating: "あ", count: 1000), trail: "x"),
                       String(repeating: "あ", count: 1000), "本文だけで上限なら記録は添えない")
    }
}

/// MetricKit の整形（札 #596）
final class DiagnosticsExitTests: XCTestCase {

    func testForegroundExitsLine() {
        XCTAssertEqual(DiagnosticsSummary.foregroundExits(normal: 3, memory: 2, abnormal: 1, badAccess: 0, illegal: 0,
                                                          watchdog: 0, appVersion: "1.1.87"),
                       "fgExit version=1.1.87 normal=3 memoryLimit=2 abnormal=1 badAccess=0 illegalInstruction=0 watchdog=0")
    }

    /// 落ちたスレッド（`threadAttributed`）の上から順に `名前+0x位置`。ほかのスレッドは見ない
    func testCrashedFramesFollowTheAttributedThread() {
        let json = """
        {"callStackTree":{},"callStackPerThread":true,"callStacks":[
          {"threadAttributed":false,"callStackRootFrames":[{"binaryName":"libsystem","offsetIntoBinaryTextSegment":16}]},
          {"threadAttributed":true,"callStackRootFrames":[{"binaryName":"JourneyPhoto","offsetIntoBinaryTextSegment":4096,
            "subFrames":[{"binaryName":"SwiftUI","offsetIntoBinaryTextSegment":255,
              "subFrames":[{"binaryName":"UIKitCore"}]}]}]}
        ]}
        """
        XCTAssertEqual(DiagnosticsSummary.crashedFrames(Data(json.utf8)), "JourneyPhoto+0x1000 SwiftUI+0xff UIKitCore")
        XCTAssertEqual(DiagnosticsSummary.crashedFrames(Data(json.utf8), limit: 1), "JourneyPhoto+0x1000")
        XCTAssertNil(DiagnosticsSummary.crashedFrames(Data("{}".utf8)))
    }
}
