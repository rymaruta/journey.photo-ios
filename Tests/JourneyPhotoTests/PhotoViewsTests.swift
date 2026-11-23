import XCTest
@testable import JourneyPhoto

/// 写真の閲覧数（札 #707・案の頁「写真の閲覧数」版5）。
///
/// 固定したいのは:
///  1. 1行の状態と言葉（まだ閲覧されていない／読み込み中／失敗／圏外／数）。読めた数は圏外になっても残す
///  2. 0回は押せない（シートを開かない）・1回以上だけ内訳のシートを開く
///  3. 数の書き方（1,234回・1万2,480回）・割合・数え始めた日
///  4. 送る条件: 本人・ログインの確かめ中・圏外・UI テストの見本の利用者では送らない。同じ写真は30分以内に送らない
///  5. 1行は自分の写真だけ・送るのは詳細だけ（画面のソースで縛る）
final class PhotoViewsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "PhotoViewsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private let some = PhotoViewCounts(app: 820, web: 414, since: "2026-12-01")
    private let none = PhotoViewCounts(app: 0, web: 0, since: nil)

    // MARK: 1行の状態と言葉

    func testRowStates() {
        XCTAssertEqual(PhotoViews.rowState(counts: nil, failed: false, offline: false), .loading)
        XCTAssertEqual(PhotoViews.rowState(counts: nil, failed: true, offline: false), .failed)
        XCTAssertEqual(PhotoViews.rowState(counts: nil, failed: true, offline: true), .offline)
        XCTAssertEqual(PhotoViews.rowState(counts: nil, failed: false, offline: true), .offline)
        // 読めた数は圏外になっても残す
        XCTAssertEqual(PhotoViews.rowState(counts: some, failed: false, offline: true), .loaded(some))
    }

    func testRowWordsJapanese() {
        XCTAssertNil(PhotoViews.rowText(.loading, language: "ja"))
        XCTAssertEqual(PhotoViews.rowText(.loaded(some), language: "ja"), "閲覧数 1,234回")
        XCTAssertEqual(PhotoViews.rowText(.loaded(none), language: "ja"), "まだ閲覧されていません")
        XCTAssertEqual(PhotoViews.rowText(.failed, language: "ja"), "閲覧数を読み込めませんでした")
        XCTAssertEqual(PhotoViews.rowText(.offline, language: "ja"), "圏外のため、閲覧数は出せません")
    }

    func testRowWordsEnglish() {
        XCTAssertEqual(PhotoViews.rowText(.loaded(some), language: "en"), "Views 1,234")
        XCTAssertEqual(PhotoViews.rowText(.loaded(none), language: "en"), "No views yet")
    }

    func testZeroDoesNotOpenSheet() {
        XCTAssertFalse(PhotoViews.opensSheet(.loaded(none)))
        XCTAssertTrue(PhotoViews.opensSheet(.loaded(some)))
        XCTAssertFalse(PhotoViews.opensSheet(.loading))
        XCTAssertFalse(PhotoViews.opensSheet(.failed))
        XCTAssertFalse(PhotoViews.opensSheet(.offline))
    }

    // MARK: 数の書き方

    func testNumberFormat() {
        XCTAssertEqual(PhotoViews.times(0, language: "ja"), "0回")
        XCTAssertEqual(PhotoViews.times(1_234, language: "ja"), "1,234回")
        XCTAssertEqual(PhotoViews.times(9_999, language: "ja"), "9,999回")
        XCTAssertEqual(PhotoViews.times(10_000, language: "ja"), "1万回")
        XCTAssertEqual(PhotoViews.times(12_480, language: "ja"), "1万2,480回")
        XCTAssertEqual(PhotoViews.times(1_234_567, language: "ja"), "123万4,567回")
        XCTAssertEqual(PhotoViews.times(12_480, language: "en"), "12,480")
        XCTAssertEqual(PhotoViews.number(-5, language: "ja"), "0")
    }

    func testPercentAndSince() {
        XCTAssertEqual(PhotoViews.appPercent(some), 66)
        XCTAssertNil(PhotoViews.appPercent(none))
        XCTAssertEqual(PhotoViews.sinceLine("2026-12-01", language: "ja"), "2026年12月1日から数えています")
        XCTAssertEqual(PhotoViews.sinceLine("2026-12-01", language: "en"), "Counting since Dec 1, 2026")
        XCTAssertNil(PhotoViews.sinceLine(nil))
        XCTAssertNil(PhotoViews.sinceLine("2026-13-01"))
    }

    func testDecodeCounts() throws {
        let c = try JSONDecoder().decode(PhotoViewCounts.self, from: Data(#"{"app":3,"web":4,"total":7,"since":"2026-12-01"}"#.utf8))
        XCTAssertEqual(c, PhotoViewCounts(app: 3, web: 4, since: "2026-12-01"))
        let empty = try JSONDecoder().decode(PhotoViewCounts.self, from: Data(#"{"since":null}"#.utf8))
        XCTAssertEqual(empty.total, 0)
    }

    // MARK: 送る条件

    func testMayRecord() {
        XCTAssertTrue(PhotoViews.mayRecord(isMine: false, signInResolving: false, offline: false, previewSession: false))
        XCTAssertFalse(PhotoViews.mayRecord(isMine: true, signInResolving: false, offline: false, previewSession: false), "本人は送らない")
        XCTAssertFalse(PhotoViews.mayRecord(isMine: false, signInResolving: true, offline: false, previewSession: false), "ログインの確かめ中は待つ")
        XCTAssertFalse(PhotoViews.mayRecord(isMine: false, signInResolving: false, offline: true, previewSession: false), "圏外では送らない")
        XCTAssertFalse(PhotoViews.mayRecord(isMine: false, signInResolving: false, offline: false, previewSession: true))
    }

    func testThirtyMinuteDedup() {
        let log = PhotoViewSendLog(defaults: freshDefaults())
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(log.shouldSend("p1", now: t0))
        log.markSent("p1", now: t0)
        XCTAssertFalse(log.shouldSend("p1", now: t0.addingTimeInterval(30 * 60 - 1)))
        XCTAssertTrue(log.shouldSend("p2", now: t0.addingTimeInterval(1)), "別の写真は送る")
        XCTAssertTrue(log.shouldSend("p1", now: t0.addingTimeInterval(30 * 60)), "30分たてば送る")
        XCTAssertEqual(PhotoViews.dedupInterval, 30 * 60)
    }

    func testDedupLogStaysSmall() {
        let d = freshDefaults()
        let log = PhotoViewSendLog(defaults: d)
        for i in 0..<(PhotoViewSendLog.maxEntries + 20) {
            log.markSent("p\(i)", now: Date(timeIntervalSince1970: Double(i)))
        }
        let stored = d.dictionary(forKey: PhotoViewSendLog.key) ?? [:]
        XCTAssertEqual(stored.count, PhotoViewSendLog.maxEntries)
        XCTAssertNotNil(stored["p\(PhotoViewSendLog.maxEntries + 19)"], "新しい方を残す")
    }

    func testUniqueSafeIds() {
        XCTAssertEqual(PhotoViews.uniqueSafeIds(["a", "a", "b#c", "", "d"]), ["a", "d"])
    }

    // MARK: 画面のソース（Linux では SwiftUI を動かせないので、置き場と条件を文字で縛る）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testRowOnlyOnMyPhotosAndBeaconOnDetail() throws {
        let detail = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("if isMine && !postPreview {\n                PhotoViewsRow("), "1行は自分の写真だけ（プレビューでは出さない）")
        XCTAssertTrue(detail.contains(".photoViewBeacon(photoId: current.id, isMine: isMine)"), "詳細で送る")
        XCTAssertEqual(detail.components(separatedBy: "PhotoViewsRow(").count - 1, 1)
        // ホームの並び・一覧では送らない（送るのは詳細だけ）
        for path in ["Sources/JourneyPhoto/Features/Gallery/GalleryView.swift", "Sources/JourneyPhoto/Features/Profile/MyPageView.swift"] {
            XCTAssertFalse(try source(path).contains("photoViewBeacon"), path)
        }
        let mypage = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        XCTAssertTrue(mypage.contains("MyPageViewsLine(photoIds: model.photos.map(\\.id))"))
    }

    func testSheetOnlyForOneOrMore() throws {
        let views = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoViewsViews.swift")
        XCTAssertTrue(views.contains("if let counts, PhotoViews.opensSheet(.loaded(counts)) {"))
        XCTAssertTrue(views.contains("case .loaded(let c) where c.total == 0:"), "0回は押せない1行")
        XCTAssertFalse(views.contains("zeroBody"), "0回のシートは作らない")
        // 共有はリンクだけ（画像を渡さない）
        XCTAssertTrue(views.contains("ShareLink(item: shareURL)"))
    }
}
