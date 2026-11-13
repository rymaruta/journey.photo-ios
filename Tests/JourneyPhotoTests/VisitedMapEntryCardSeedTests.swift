import XCTest
@testable import JourneyPhoto

/// マイページの札「行った県」が、UI テストの見本（`-JPPreviewVisitedMap YES`）では行った県の画面と同じ 31 県を出すこと。
/// 見本が無いときは端末の記録を読むこと（2026-11-13 判断・run 1203 の絵で札が 0/47、画面が 31/47 と割れていた）
final class VisitedMapEntryCardSeedTests: XCTestCase {

    private let keys = [PreviewSession.defaultsKey, PreviewSession.visitedMapKey]
    private var saved: [String: Any] = [:]
    private var suite: UserDefaults!
    private let suiteName = "VisitedMapEntryCardSeedTests"

    override func setUp() {
        super.setUp()
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        UserDefaults().removePersistentDomain(forName: suiteName)
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// 見本の利用者で `-JPPreviewVisitedMap YES` なら、札も見本の 31 県（画面の `seedForPreview` と同じ数）
    func testPreviewSeedIsShownOnTheCard() throws {
        #if DEBUG
        UserDefaults.standard.set("preview-user", forKey: PreviewSession.defaultsKey)
        UserDefaults.standard.set(true, forKey: PreviewSession.visitedMapKey)
        let seed = try XCTUnwrap(PreviewSession.visitedMapSeed)
        let record = VisitedMapEntryCard.load(for: "preview-user", store: VisitedPrefectureStore(defaults: suite))
        XCTAssertEqual(record.visitedCount, 31)
        XCTAssertEqual(record.visitedCount, seed.visitedCount, "札と画面の見本の数が割れている")
        // 見本は端末に書かない
        XCTAssertEqual(VisitedPrefectureStore(defaults: suite).load(for: "preview-user").visitedCount, 0)
        #else
        throw XCTSkip("見本は Debug のみ")
        #endif
    }

    /// 見本が無ければ（製品の動き）端末の記録を読む
    func testWithoutPreviewTheCardReadsTheStore() {
        UserDefaults.standard.removeObject(forKey: PreviewSession.defaultsKey)
        UserDefaults.standard.removeObject(forKey: PreviewSession.visitedMapKey)
        let store = VisitedPrefectureStore(defaults: suite)
        var book = VisitedPrefectures()
        book.add("北海道", day: "2026-01-01")
        book.add("沖縄県", day: "2026-01-02")
        store.save(book, for: "u1")
        XCTAssertNil(PreviewSession.visitedMapSeed)
        XCTAssertEqual(VisitedMapEntryCard.load(for: "u1", store: store).visitedCount, 2)
        XCTAssertEqual(VisitedMapEntryCard.load(for: "u2", store: store).visitedCount, 0)
    }
}
