import XCTest
@testable import JourneyPhoto

@MainActor
final class StoryDraftStoreTests: XCTestCase {

    private func make() -> (StoryDraftStore, UserDefaults, URL) {
        let suite = UserDefaults(suiteName: "story-draft-\(UUID().uuidString)")!
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("story-draft-\(UUID().uuidString)")
        return (StoryDraftStore(defaults: suite, directory: dir), suite, dir)
    }

    private let now = "2026-09-22T10:00:00.000Z"

    @discardableResult
    private func save(_ store: StoryDraftStore, caption: String = "また来たい",
                      overlays: [TextOverlay] = [TextOverlay(text: "ここ", x: 0.3, y: 0.7)]) -> Bool {
        store.save(imageData: Data("jpeg".utf8), fileName: "a.jpg", contentType: "image/jpeg",
                   coords: Photo.Coords(lat: 34.14, lng: 133.68), caption: caption,
                   location: "高屋神社", overlays: overlays, song: nil,
                   durationSec: 7, savedAt: now)
    }

    func testSavesAndComesBack() async throws {
        let (store, defaults, dir) = make()
        store.use(userId: "u1")
        XCTAssertNil(store.draft)
        XCTAssertTrue(save(store))

        let reopened = StoryDraftStore(defaults: defaults, directory: dir)
        reopened.use(userId: "u1")
        let draft = try XCTUnwrap(reopened.draft)
        XCTAssertEqual(draft.caption, "また来たい")
        XCTAssertEqual(draft.location, "高屋神社")
        XCTAssertEqual(draft.durationSec, 7)
        XCTAssertEqual(draft.coords?.lat, 34.14)
        XCTAssertEqual(reopened.imageData(), Data("jpeg".utf8))
    }

    /// 置いた文字は**位置と見た目ごと**戻る（戻らないと置き直しになる）
    func testOverlaysComeBackWithTheirPlace() async throws {
        let (store, defaults, dir) = make()
        store.use(userId: "u1")
        save(store, overlays: [TextOverlay(text: "サウナ", x: 0.2, y: 0.9, size: 0.12,
                                           style: .banner, kind: .place)])
        let reopened = StoryDraftStore(defaults: defaults, directory: dir)
        reopened.use(userId: "u1")
        let overlay = try XCTUnwrap(reopened.draft?.overlays.first)
        XCTAssertEqual(overlay.text, "サウナ")
        XCTAssertEqual(overlay.x, 0.2)
        XCTAssertEqual(overlay.y, 0.9)
        XCTAssertEqual(overlay.size, 0.12)
        XCTAssertEqual(overlay.kind, .place)
        XCTAssertEqual(overlay.style, .banner)
    }

    /// **1件だけ。** 2件目は1件目を上書きする
    func testKeepsOnlyOne() async {
        let (store, _, _) = make()
        store.use(userId: "u1")
        save(store, caption: "ひとつめ")
        save(store, caption: "ふたつめ")
        XCTAssertEqual(store.draft?.caption, "ふたつめ")
    }

    /// 同じ端末で人が変わったら**前の人の書きかけを見せない**
    func testDoesNotLeakBetweenAccounts() async {
        let (store, _, _) = make()
        store.use(userId: "u1")
        save(store)
        store.use(userId: "u2")
        XCTAssertNil(store.draft)
        store.use(userId: "u1")
        XCTAssertNotNil(store.draft)
    }

    /// 捨てたら**画像のファイルも消える**（残すと容量を静かに食う）
    func testClearRemovesTheFileToo() async throws {
        let (store, _, dir) = make()
        store.use(userId: "u1")
        save(store)
        let file = dir.appendingPathComponent(try XCTUnwrap(store.draft).imageFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        store.clear()
        XCTAssertNil(store.draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    /// 画像の名前は**起動をまたいでも同じ**で、人ごとに別。
    /// 以前は `hashValue`（起動のたびに変わる）から作っていた
    func testImageFileNameIsStable() {
        let a = StoryDraftStore.imageFileName(forKey: "journey-photo-story-draft:u1")
        XCTAssertEqual(a, StoryDraftStore.imageFileName(forKey: "journey-photo-story-draft:u1"))
        XCTAssertNotEqual(a, StoryDraftStore.imageFileName(forKey: "journey-photo-story-draft:u2"))
        XCTAssertTrue(a.hasPrefix("story-draft-"))
        XCTAssertTrue(a.hasSuffix(".jpg"))
        XCTAssertFalse(a.contains("/"))
    }

    /// 何度保存しても**画像は1つ**
    func testSavingAgainKeepsOneImage() async throws {
        let (store, _, dir) = make()
        store.use(userId: "u1")
        save(store, caption: "ひとつめ")
        save(store, caption: "ふたつめ")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.filter { $0.hasPrefix("story-draft-") }.count, 1)
    }

    /// 🔴 **古い名前で残った画像を片づける。** 別の人の下書きの画像は残す
    func testSweepsOrphanedImages() async throws {
        let (store, defaults, dir) = make()
        store.use(userId: "u2")
        save(store)
        let kept = dir.appendingPathComponent(try XCTUnwrap(store.draft).imageFile)
        // `hashValue` 時代の名前で、どこからも指されていない画像
        let orphan = dir.appendingPathComponent("story-draft-4242424242.jpg")
        try Data("old".utf8).write(to: orphan)

        let reopened = StoryDraftStore(defaults: defaults, directory: dir)
        reopened.use(userId: "u1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }

    /// 下書きが古い名前を指していたら、保存し直したときに古い画像を消す
    func testReplacesTheImageUnderTheOldName() async throws {
        let (store, defaults, dir) = make()
        store.use(userId: "u1")
        save(store)
        // 下書きの記録を「古い名前を指している」形に書き換える
        var draft = try XCTUnwrap(store.draft)
        let legacy = dir.appendingPathComponent("story-draft-99.jpg")
        try Data("old".utf8).write(to: legacy)
        draft.imageFile = "story-draft-99.jpg"
        defaults.set(try JSONEncoder().encode(draft), forKey: "journey-photo-story-draft:u1")

        save(store, caption: "書き直し")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(store.imageData(), Data("jpeg".utf8))
    }

    /// **画像が消えていたら下書きごと片づける。**
    /// 印だけ残すと「続きから」で白い画面になる
    func testDropsTheDraftWhenTheImageIsGone() async throws {
        let (store, defaults, dir) = make()
        store.use(userId: "u1")
        save(store)
        let file = dir.appendingPathComponent(try XCTUnwrap(store.draft).imageFile)
        try FileManager.default.removeItem(at: file)

        let reopened = StoryDraftStore(defaults: defaults, directory: dir)
        reopened.use(userId: "u1")
        XCTAssertNil(reopened.draft)
        XCTAssertNil(defaults.data(forKey: "journey-photo-story-draft:u1"))
    }
}
