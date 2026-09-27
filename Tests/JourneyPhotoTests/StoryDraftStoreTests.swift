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
    func testImageFileNameIsStable() async {
        let a = StoryDraftStore.imageFileName(forKey: "journey-photo-story-draft:u1")
        XCTAssertEqual(a, StoryDraftStore.imageFileName(forKey: "journey-photo-story-draft:u1"))
        XCTAssertNotEqual(a, StoryDraftStore.imageFileName(forKey: "journey-photo-story-draft:u2"))
        XCTAssertTrue(a.hasPrefix("story-draft-"))
        XCTAssertTrue(a.hasSuffix(".jpg"))
        XCTAssertFalse(a.contains("/"))
        // **期待する文字列そのもので見る。** 同じ起動の中で2回比べるだけだと
        // `hashValue` に戻しても通ってしまう（値が変わるのは起動をまたいだとき）
        XCTAssertEqual(StoryDraftStore.imageFileName(forKey: "ab"), "story-draft-6162.jpg")
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

    /// アップデート直後の起動: 古い名前を**指している**画像は片づけで消さない
    /// （下書きはそのまま戻る）
    func testKeepsTheImageAnOldDraftStillPointsTo() async throws {
        let (store, defaults, dir) = make()
        store.use(userId: "u1")
        save(store)
        var draft = try XCTUnwrap(store.draft)
        let legacy = dir.appendingPathComponent("story-draft-77.jpg")
        try Data("old".utf8).write(to: legacy)
        try FileManager.default.removeItem(at: dir.appendingPathComponent(draft.imageFile))
        draft.imageFile = "story-draft-77.jpg"
        defaults.set(try JSONEncoder().encode(draft), forKey: "journey-photo-story-draft:u1")

        let reopened = StoryDraftStore(defaults: defaults, directory: dir)
        reopened.use(userId: "u1")
        XCTAssertNotNil(reopened.draft)
        XCTAssertEqual(reopened.imageData(), Data("old".utf8))
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

    // MARK: - 並べた写真を全部残す

    private func shot(_ n: UInt8, text: String) -> StoryDraftStore.ShotInput {
        StoryDraftStore.ShotInput(imageData: Data([n]), fileName: "\(n).jpg", contentType: "image/jpeg",
                                  coords: Photo.Coords(lat: Double(n), lng: 0),
                                  overlays: [TextOverlay(text: text, x: 0.1, y: 0.2)])
    }

    @discardableResult
    private func saveShots(_ store: StoryDraftStore, _ inputs: [StoryDraftStore.ShotInput]) -> Bool {
        store.save(shots: inputs, caption: "並び", location: "", song: nil, durationSec: 5, savedAt: now)
    }

    /// 🔴 **3枚並べて保存したら3枚戻る。** 以前は表示中の1枚しか残さず、
    /// 「保存しました」と出るのに開き直すと1枚だった
    func testSavesEveryShotInOrder() async throws {
        let (store, defaults, dir) = make()
        store.use(userId: "u1")
        XCTAssertTrue(saveShots(store, [shot(1, text: "一"), shot(2, text: "二"), shot(3, text: "三")]))

        let reopened = StoryDraftStore(defaults: defaults, directory: dir)
        reopened.use(userId: "u1")
        let restored = reopened.shotImages()
        XCTAssertEqual(restored.map(\.data), [Data([1]), Data([2]), Data([3])])
        XCTAssertEqual(restored.map { $0.shot.overlays.first?.text }, ["一", "二", "三"])
        XCTAssertEqual(restored.map { $0.shot.coords?.lat }, [1, 2, 3])
        XCTAssertEqual(reopened.draft?.caption, "並び")
    }

    /// 枚数を減らして保存し直したら、**使わなくなった画像を残さない**
    func testSavingFewerShotsRemovesTheLeftovers() async throws {
        let (store, _, dir) = make()
        store.use(userId: "u1")
        saveShots(store, [shot(1, text: "一"), shot(2, text: "二"), shot(3, text: "三")])
        saveShots(store, [shot(4, text: "四")])
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.filter { $0.hasPrefix("story-draft-") }.count, 1)
        XCTAssertEqual(store.shotImages().map(\.data), [Data([4])])
    }

    /// 捨てたら**全部の画像**が消える。片づけも2枚目以降を消さない
    func testClearAndSweepHandleEveryShot() async throws {
        let (store, defaults, dir) = make()
        store.use(userId: "u1")
        saveShots(store, [shot(1, text: "一"), shot(2, text: "二")])
        let reopened = StoryDraftStore(defaults: defaults, directory: dir)
        reopened.use(userId: "u1")
        XCTAssertEqual(reopened.shotImages().count, 2, "片づけが2枚目を消した")
        reopened.clear()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.filter { $0.hasPrefix("story-draft-") }, [])
    }

    /// 前の版が保存した1枚だけの下書き（`extraShots` が無い）もそのまま戻る
    func testReadsAnOldSingleShotDraft() async throws {
        let (store, defaults, dir) = make()
        store.use(userId: "u1")
        save(store)
        let data = try XCTUnwrap(defaults.data(forKey: "journey-photo-story-draft:u1"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "extraShots")
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "journey-photo-story-draft:u1")
        let reopened = StoryDraftStore(defaults: defaults, directory: dir)
        reopened.use(userId: "u1")
        XCTAssertEqual(reopened.shotImages().map(\.data), [Data("jpeg".utf8)])
    }
}
