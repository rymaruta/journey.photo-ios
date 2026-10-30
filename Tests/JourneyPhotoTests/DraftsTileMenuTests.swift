import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// マイページの「下書き」の枠の長押し（2026-10-30・#408・owner「下書きを長押しで…削除とかもできるようにしたい」）。
///
/// 長押しで最新の下書きを続きから編集・削除、2件以上なら最近の5件。削除は一覧と同じ「元に戻す」つき
/// （`DraftDeleteUndo`）、件数バッジと枠はすぐ減る（`DraftLibrary.shownCount`）。枠の地に最新の縮図を淡く敷く
@MainActor
final class DraftsTileMenuTests: XCTestCase {

    private let defaults = UserDefaults(suiteName: "DraftsTileMenuTests.\(UUID().uuidString)")!
    nonisolated private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DraftsTileMenuTests-\(UUID().uuidString)")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func library() -> DraftLibrary {
        let library = DraftLibrary(defaults: defaults, directory: directory)
        library.now = { [now] in now }
        return library
    }

    private func item(_ title: String) -> UploadDraftStore.Item {
        UploadDraftStore.Item(imageFile: "", fileName: "a.jpg", contentType: "image/jpeg", exif: nil,
                              latitude: nil, longitude: nil, takenOn: nil, dominantColor: nil,
                              title: title, caption: "", location: "", photoPlaceName: nil,
                              locationClearedByUser: false, pickedLatitude: nil, pickedLongitude: nil, recipe: nil)
    }

    private func fields(_ date: Date) -> UploadDraftStore.Draft {
        UploadDraftStore.Draft(items: [], tagsText: "", category: "", published: true, audience: "everyone",
                               song: nil, selectedAlbumId: nil, groupsAsOnePost: true,
                               savedAt: UploadDraftStore.savedAtString(date))
    }

    @discardableResult
    private func savePost(_ title: String, at date: Date, slot: UploadDraftStore.Slot? = nil) -> String {
        let id = UUID().uuidString
        let store = UploadDraftStore(defaults: defaults, directory: directory, slot: slot ?? .entry(id))
        XCTAssertTrue(store.save([UploadDraftStore.ItemInput(imageData: Data([1, 2, 3]), item: item(title))],
                                 fields: fields(date), for: "a"))
        return id
    }

    private func entry(_ id: String, auto: Bool = false, title: String = "", missing: Int = 0,
                       ago: TimeInterval = 0) -> DraftLibrary.Entry {
        DraftLibrary.Entry(id: id, kind: .post, isAuto: auto, savedAt: now.addingTimeInterval(-ago), stamp: "",
                           title: title, place: "", photoCount: 2, missingCount: missing, cover: nil, bytes: 0)
    }

    // MARK: - 件数（バッジ・枠を出すか）

    /// 🔴 **枠の長押しで消したら、バッジと枠をすぐ減らす**: 「元に戻す」を待っているものは画面の件数に数えない。
    /// 上限の数え方（`count(for:)`）は待っているものも数えたまま（21件にしない・#400 の見直し）
    func testShownCountSkipsPendingDeleteAndAuto() async {
        let a = savePost("A", at: now)
        savePost("B", at: now.addingTimeInterval(-60))
        savePost("自動", at: now, slot: .auto)
        let lib = library()
        XCTAssertEqual(lib.shownCount(for: "a"), 2, "自動の書きかけを数えた（枠のバッジは保存した下書きだけ）")
        lib.hide([a])
        XCTAssertEqual(lib.shownCount(for: "a"), 1, "消して「元に戻す」を待っている間もバッジが減らない")
        XCTAssertEqual(lib.count(for: "a"), 2, "上限の数え方から待っているものを外した")
        lib.undo([a])
        XCTAssertEqual(lib.shownCount(for: "a"), 2)
        XCTAssertEqual(lib.shownCount(for: ""), 0)
    }

    // MARK: - 削除と「元に戻す」（一覧とマイページで同じもの）

    /// 消す → 隠すだけ（画像は残る・描き直しの合図）→ 元に戻す → 元の位置。もう一度消して締め切ると本当に消える
    func testDeleteUndoAndFinish() async {
        let a = savePost("A", at: now)
        let b = savePost("B", at: now.addingTimeInterval(-60))
        let lib = library()
        let deleter = DraftDeleteUndo(library: lib, seconds: 60)
        let revision = lib.revision
        deleter.delete([a], owner: "a")
        XCTAssertEqual(deleter.pending, [a])
        XCTAssertGreaterThan(lib.revision, revision, "消しても件数・枠を描き直す合図が出ない")
        XCTAssertEqual(lib.entries(for: "a").map(\.id), [b])
        XCTAssertNotNil(UploadDraftStore(defaults: defaults, directory: directory, slot: .entry(a)).draft(for: "a"),
                        "「元に戻す」の間に下書きを消した")
        deleter.undo()
        XCTAssertNil(deleter.pending)
        XCTAssertEqual(lib.entries(for: "a").map(\.id), [a, b], "元に戻らない")

        deleter.delete([a], owner: "a")
        deleter.finish()
        XCTAssertNil(deleter.pending)
        XCTAssertEqual(lib.entries(for: "a").map(\.id), [b])
        XCTAssertNil(UploadDraftStore(defaults: defaults, directory: directory, slot: .entry(a)).draft(for: "a"),
                     "締め切っても消えない")
        deleter.undo()
        XCTAssertEqual(lib.entries(for: "a").map(\.id), [b], "消し終えた後に戻った")
    }

    /// 次の削除を押したら、前の削除は積まずに済ませる。時間が来たら（画面が無くても）本当に消す
    func testNextDeleteFinishesThePreviousAndTimerFinalizes() async throws {
        let a = savePost("A", at: now)
        let b = savePost("B", at: now.addingTimeInterval(-60))
        let lib = library()
        let deleter = DraftDeleteUndo(library: lib, seconds: 0.05)
        deleter.delete([a], owner: "a")
        deleter.delete([b], owner: "a")
        XCTAssertNil(UploadDraftStore(defaults: defaults, directory: directory, slot: .entry(a)).draft(for: "a"),
                     "前の削除を済ませずに積んだ")
        XCTAssertEqual(deleter.pending, [b])
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(deleter.pending, "時間が来ても「元に戻す」が消えない")
        XCTAssertNil(UploadDraftStore(defaults: defaults, directory: directory, slot: .entry(b)).draft(for: "a"),
                     "時間が来ても消えない")
        XCTAssertEqual(lib.shownCount(for: "a"), 0)
    }

    // MARK: - メニューに並べるもの

    /// 最新は一覧と同じ並びの1件目（自動の書きかけが先頭）。最近の下書きは2件以上のときだけ、最大5件
    func testMenuListsLatestAndUpToFiveRecents() async {
        XCTAssertNil(DraftsTileMenu(entries: []).latest)
        XCTAssertEqual(DraftsTileMenu(entries: []).recents, [])
        let one = DraftsTileMenu(entries: [entry("x")])
        XCTAssertEqual(one.latest?.id, "x")
        XCTAssertEqual(one.recents, [], "1件なのに「最近の下書き」を出した（最新と同じものが2回並ぶ）")
        let many = (0..<7).map { entry("e\($0)", ago: TimeInterval($0)) }
        let sorted = DraftLibrary.sorted([entry("auto", auto: true, ago: 99_999)] + many)
        let menu = DraftsTileMenu(entries: sorted)
        XCTAssertEqual(menu.latest?.id, "auto", "自動の書きかけの扱いが一覧と違う")
        XCTAssertEqual(menu.recents.map(\.id), ["auto", "e0", "e1", "e2", "e3"])
        XCTAssertEqual(DraftsTileMenu.recentLimit, 5)
    }

    /// 読めない写真のある下書きは、開く前に一覧と同じ問いを出す
    func testOpenRouteAsksWhenPhotosAreMissing() async {
        XCTAssertEqual(DraftOpenRoute.route(entry("ok")), .open)
        XCTAssertEqual(DraftOpenRoute.route(entry("broken", missing: 1)), .askMissing)
    }

    /// 言い方: 「捨てる」は使わない（CLAUDE.md）。名前は題、無ければ「題なし」、副題は種類・枚数・日時
    func testWording() async {
        XCTAssertEqual(DraftsText.openList, "下書きの一覧を開く")
        XCTAssertEqual(DraftsText.deleteThisDraft, "この下書きを削除")
        XCTAssertEqual(DraftsText.continueEditing, "続きから編集")
        XCTAssertEqual(DraftsText.title(entry("x")), "題なし")
        XCTAssertTrue(DraftsText.menuSubtitle(entry("x"), now: now).hasPrefix("投稿 · 2枚 · 今日"),
                      DraftsText.menuSubtitle(entry("x"), now: now))
        XCTAssertTrue(DraftsText.tileHint.contains("長押しで続きから編集・削除"))
        for text in [DraftsText.openList, DraftsText.recentSection, DraftsText.tileHint, DraftsText.deleteThisDraft] {
            XCTAssertFalse(text.contains("捨て"), text)
        }
    }

    // MARK: - つながり（画面は Linux で描けないので、作りを読む）

    /// 枠の長押し・浮く絵・読み上げの操作・地の縮図・元に戻すの置き場・すぐ描き直す口
    func testTileIsWired() async throws {
        let tile = try source("Features/Profile/MyPageDraftsTile.swift")
        XCTAssertTrue(tile.contains(".contextMenu {"), "枠に長押しのメニューが無い")
        XCTAssertTrue(tile.contains("DraftPreviewCard(entry: latest, now: library.now())"),
                      "浮く絵が一覧の長押しと同じ部品ではない")
        for action in ["DraftsText.continueEditing) {", "DraftsText.openList) {", "DraftsText.deleteThisDraft) {"] {
            XCTAssertTrue(tile.contains(".accessibilityAction(named: \(action)"), "読み上げの操作が無い: \(action)")
        }
        XCTAssertTrue(tile.contains(".accessibilityHint(DraftsText.tileHint)"))
        XCTAssertTrue(tile.contains("DraftCover(url: cover, showsFailure: false)"), "枠の地に最新の縮図を敷いていない")
        XCTAssertTrue(tile.contains("Button(role: .destructive) { confirmDelete = [latest.id] }"))
        XCTAssertTrue(tile.contains(".draftDialogs(confirmDelete:"), "消す前の確かめ・読めない写真の問いが一覧と違う")
        // 板: 78% 未満の重ねは「写真の上」——真鍮の件数バッジを置けない
        XCTAssertGreaterThanOrEqual(MyPageDraftsTile.scrimOpacity, 0.78)
        XCTAssertLessThan(MyPageDraftsTile.scrimOpacity, 1, "縮図が見えない")

        let mypage = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(mypage.contains("if draftCount > 0 { draftsTile }"), "0件のときの決まりを変えた")
        XCTAssertTrue(mypage.contains("MyPageDraftsTile(userId:"))
        XCTAssertTrue(mypage.contains(".overlay(alignment: .bottom) { DraftUndoBar(deleter: draftDeleter"),
                      "マイページの下に「元に戻す」が無い")
        XCTAssertTrue(mypage.contains("DraftRevisionWatcher { refreshDraftCount() }"), "消しても件数をすぐ読み直さない")
        XCTAssertTrue(mypage.contains("draftCount = DraftLibrary.shared.shownCount(for: userId)"),
                      "バッジが「元に戻す」を待っているものまで数える")
        XCTAssertTrue(mypage.contains("onOpen: { entry in tabRouter.openDraft(entry) }"))
        XCTAssertTrue(mypage.contains(".navigationDestination(isPresented: $showDraftsList)"))

        // 写しを作らない: 一覧も同じ削除・元に戻す・問いを使う
        let list = try source("Features/Drafts/DraftsView.swift")
        XCTAssertTrue(list.contains("@StateObject private var deleter = DraftDeleteUndo()"))
        XCTAssertTrue(list.contains("DraftUndoBar(deleter: deleter)"))
        XCTAssertTrue(list.contains(".draftDialogs(confirmDelete:"))
        XCTAssertFalse(list.contains("library.hide("), "一覧が削除の流れを別に持っている")

        let shots = try String(contentsOf: Self.root.appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"),
                               encoding: .utf8)
        XCTAssertTrue(shots.contains("107a2-マイページ（下書きの枠を長押し）"), "長押しのメニューの画面写真が無い")
    }

    // MARK: - 道具

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent("Sources/JourneyPhoto/\(path)"), encoding: .utf8)
    }
}
