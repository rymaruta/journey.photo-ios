import XCTest
@testable import JourneyPhoto

/// 下のタブの画面を、親（`RootView`）が描き直されただけでは描き直さない直し（2026-11-24・札 #594・owner「アプリ全体的に挙動重い」1.2.1）の試験。
///
/// ホーム（`GalleryView`）は 2026-11-14 に直してあった（`HomeTopCardMemoTests.testGalleryViewComparesOnlyWhatItDraws`）。
/// 探す（`SearchView`）と地図（`PhotoMapView`）は同じ閉じた処理（`onOpenNotifications`・`onPost`）を受け取るのに `.equatable()` が無く、
/// 親の状態が1つ変わるたびに body が評価し直されていた
final class TabRedrawTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 閉じた処理が新しくなっただけなら「同じ」。未読の数・受信箱の未読が変われば「違う」
    @MainActor
    func testSearchViewComparesOnlyWhatItDraws() async {
        var calls = 0
        let a = SearchView(unread: 2, onOpenNotifications: { calls += 1 }, messagesUnread: false)
        let b = SearchView(unread: 2, onOpenNotifications: { calls += 2 }, messagesUnread: false)
        XCTAssertTrue(a == b, "閉じた処理が違うだけで描き直している")
        XCTAssertFalse(a == SearchView(unread: 3, onOpenNotifications: {}, messagesUnread: false))
        XCTAssertFalse(a == SearchView(unread: 2, onOpenNotifications: {}, messagesUnread: true))
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testPhotoMapViewComparesOnlyWhatItDraws() async {
        let a = PhotoMapView(unread: 1, onOpenNotifications: {}, messagesUnread: true, onPost: {})
        let b = PhotoMapView(unread: 1, onOpenNotifications: {}, messagesUnread: true, onPost: {})
        XCTAssertTrue(a == b, "閉じた処理が違うだけで描き直している")
        XCTAssertFalse(a == PhotoMapView(unread: 0, onOpenNotifications: {}, messagesUnread: true, onPost: {}))
        XCTAssertFalse(a == PhotoMapView(unread: 1, onOpenNotifications: {}, messagesUnread: false, onPost: {}))
    }

    /// 親から渡す値が増えたら、比べる値も見直す（比べ忘れると、その値が変わっても描き直さない）
    func testPassedValuesAreAllCompared() throws {
        for (path, head, expected) in [
            ("Sources/JourneyPhoto/Features/Search/SearchView.swift", "struct SearchView: View {",
             ["var unread: Int = 0", "var onOpenNotifications: () -> Void = {}", "var messagesUnread = false"]),
            ("Sources/JourneyPhoto/Features/Map/PhotoMapView.swift", "struct PhotoMapView: View {",
             ["var unread: Int = 0", "var onOpenNotifications: () -> Void = {}", "var messagesUnread = false",
              "var onPost: () -> Void = {}"]),
        ] {
            let file = try source(path)
            guard let range = file.range(of: head) else { return XCTFail("\(head) が無い") }
            let body = file[range.upperBound...].components(separatedBy: "\n}\n").first ?? ""
            let passed = body.components(separatedBy: "\n").filter { line in
                (line.hasPrefix("    var ") || line.hasPrefix("    let ")) && !line.contains("{")
                    || line.hasPrefix("    var ") && line.contains("= {")
            }.map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertEqual(passed, expected, "\(path) が親から受け取る値が変わった。== で比べる値も見直す")
        }
    }

    /// `RootView` が探すと地図を `.equatable()` で包んでいる（包まないと `==` は使われない）
    func testRootViewWrapsTabsInEquatable() throws {
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        for call in ["SearchView(unread: unread", "PhotoMapView(unread: unread"] {
            guard let range = root.range(of: call) else { return XCTFail("RootView に \(call) が無い") }
            let after = root[range.upperBound...].prefix(400)
            XCTAssertTrue(after.contains(".equatable()"), "RootView が \(call)…) を .equatable() で包んでいない")
        }
    }
    /// 🔴 ホームの上端の見張り（UI テストのときだけ）は、送るたびにホームの body を評価し直させない（Mac run 1779:
    /// `chg.GalleryView.__feedProbeTop` 270 回・マス 5,521 回）。上端はホームが見張らない入れ物に書き、見えない要素だけが見張る
    func testFeedTopProbeDoesNotRedrawHome() throws {
        let home = try source("Sources/JourneyPhoto/Features/Gallery/GalleryView.swift")
        XCTAssertFalse(home.contains("@State private var feedProbeTop: CGFloat"), "上端をホームの @State に持っている（送るたびにホームを描き直す）")
        XCTAssertTrue(home.contains("@State private var feedProbeTop = FeedTopValue()"))
        XCTAssertFalse(home.contains("@StateObject private var feedProbeTop"), "@StateObject にするとホームが見張ってしまう")
        XCTAssertTrue(home.contains("FeedProbeLabel(value: feedProbeTop)"), "見えない要素が上端を見張っていない")
        XCTAssertTrue(home.contains(".accessibilityIdentifier(\"home.feed.probe\")"))
    }
}
