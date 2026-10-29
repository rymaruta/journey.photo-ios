import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 下書きを複数持つ（2026-10-29・#400・`DraftLibrary`・`UploadDraftStore.Slot.entry`・`StoryDraftStore.Slot.entry`）。
///
/// owner の決定: 投稿＋ストーリー合わせて20件・投稿は期限なし・ストーリーは保存から7日（2日前から「あと n 日」）・
/// いっぱいなら「下書きを整理する」（黙って古いものを消さない）・下書きから開いて閉じるときは「この下書きを更新」が先頭・
/// 「下書き」は端末の書きかけだけ（マイページの非公開の写真は「非公開」）・ログアウトでは消さず退会で消す。
/// **前の版の1件の下書きは新しい形に移して失わない**
@MainActor
final class MultiDraftsTests: XCTestCase {

    private let defaults = UserDefaults(suiteName: "MultiDraftsTests.\(UUID().uuidString)")!
    nonisolated private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MultiDraftsTests-\(UUID().uuidString)")
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

    private func uploads(_ slot: UploadDraftStore.Slot = .saved) -> UploadDraftStore {
        UploadDraftStore(defaults: defaults, directory: directory, slot: slot)
    }

    private func stories(_ slot: StoryDraftStore.Slot, user: String = "a") -> StoryDraftStore {
        let store = StoryDraftStore(defaults: defaults, directory: directory, slot: slot)
        store.bind(userId: user)
        return store
    }

    private func item(_ title: String = "", location: String = "") -> UploadDraftStore.Item {
        UploadDraftStore.Item(imageFile: "", fileName: "a.jpg", contentType: "image/jpeg", exif: nil,
                              latitude: nil, longitude: nil, takenOn: nil, dominantColor: nil,
                              title: title, caption: "", location: location, photoPlaceName: nil,
                              locationClearedByUser: false, pickedLatitude: nil, pickedLongitude: nil, recipe: nil)
    }

    private func fields(_ date: Date) -> UploadDraftStore.Draft {
        UploadDraftStore.Draft(items: [], tagsText: "", category: "", published: true, audience: "everyone",
                               song: nil, selectedAlbumId: nil, groupsAsOnePost: true,
                               savedAt: UploadDraftStore.savedAtString(date))
    }

    @discardableResult
    private func savePost(_ title: String, photos: Int = 1, at date: Date? = nil, user: String = "a",
                          id: String = UUID().uuidString) -> String {
        let inputs = (0..<photos).map { i in
            UploadDraftStore.ItemInput(imageData: Data(repeating: UInt8(i + 1), count: 32),
                                       item: item(i == 0 ? title : "", location: "松本"))
        }
        XCTAssertTrue(uploads(.entry(id)).save(inputs, fields: fields(date ?? now), for: user))
        return id
    }

    @discardableResult
    private func saveStory(_ text: String, ageDays: Double, user: String = "a", id: String = UUID().uuidString) -> String {
        let store = stories(.entry(id), user: user)
        XCTAssertTrue(store.save(
            shots: [StoryDraftStore.ShotInput(imageData: Data([9, 9, 9]), fileName: "s.jpg", contentType: "image/jpeg",
                                              coords: nil, overlays: [TextOverlay(text: text)])],
            caption: "", location: "小樽", song: nil, durationSec: 5,
            savedAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-ageDays * 86_400))))
        return id
    }

    private func files() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    // MARK: - 移す（前の版の1件を失わない）

    /// 🔴 **前の版の「人ごとに1件」の投稿の下書きは、新しい形の1件に移る**（画像の名前も中身もそのまま）。
    /// 何度呼んでも1件のまま
    func testLegacyPostDraftIsMigrated() async throws {
        let legacy = uploads(.saved)
        XCTAssertTrue(legacy.save([UploadDraftStore.ItemInput(imageData: Data([1, 2, 3]), item: item("前の下書き"))],
                                  fields: fields(now), for: "a"))
        let before = files()
        let lib = library()
        XCTAssertEqual(lib.count(for: "a"), 1, "前の版の下書きが数えられない（移っていない）")
        XCTAssertNil(uploads(.saved).draft(for: "a"), "前の鍵が残った（次の起動でもう一度移る）")
        let entries = lib.entries(for: "a")
        XCTAssertEqual(entries.map(\.title), ["前の下書き"])
        XCTAssertEqual(entries.first?.missingCount, 0, "移したら画像が読めなくなった")
        XCTAssertEqual(files(), before, "移すときに画像を消した・増やした")
        lib.prepare(for: "a")
        XCTAssertEqual(lib.count(for: "a"), 1, "二度移した")
        // 移した後も掃除で画像が消えない（記録が同じ名前を指す）
        uploads().sweepOrphans()
        XCTAssertEqual(files(), before)
    }

    /// 🔴 **前の版のストーリーの下書き（1件）も移る**（保存した時刻＝送信の印も変わらない）
    func testLegacyStoryDraftIsMigrated() async throws {
        let legacy = StoryDraftStore(defaults: defaults, directory: directory)
        legacy.use(userId: "a")
        XCTAssertTrue(legacy.save(imageData: Data([5]), fileName: "a.jpg", contentType: "image/jpeg", coords: nil,
                                  caption: "前のストーリー", location: "", overlays: [], song: nil, durationSec: 5,
                                  savedAt: ISO8601DateFormatter().string(from: now)))
        let lib = library()
        let entries = lib.entries(for: "a")
        XCTAssertEqual(entries.count, 1, "前の版のストーリーの下書きが消えた")
        XCTAssertEqual(entries.first?.kind, .story)
        XCTAssertEqual(entries.first?.title, "前のストーリー")
        let reread = StoryDraftStore(defaults: defaults, directory: directory)
        reread.use(userId: "a")
        XCTAssertNil(reread.draft, "前の鍵が残った")
        XCTAssertEqual(entries.first?.stamp, ISO8601DateFormatter().string(from: now), "送信の印が変わった")
    }

    // MARK: - 何件も持つ・上限

    /// 投稿を2件保存しても前の1件は置き換わらない。並びは自動の書きかけが先頭、あとは新しい順
    func testKeepsManyDraftsNewestFirstWithAutoOnTop() async {
        savePost("古い", at: now.addingTimeInterval(-3_600))
        savePost("新しい", at: now)
        saveStory("ストーリー", ageDays: 0.02)
        XCTAssertTrue(uploads(.auto).save([UploadDraftStore.ItemInput(imageData: Data([7]), item: item("自動"))],
                                          fields: fields(now.addingTimeInterval(-86_400 * 3)), for: "a"))
        let lib = library()
        XCTAssertEqual(lib.entries(for: "a").map(\.title), ["自動", "新しい", "ストーリー", "古い"])
        XCTAssertEqual(lib.count(for: "a"), 3, "自動の書きかけを上限に数えた")
        XCTAssertEqual(lib.count(for: "a", kind: .post), 2)
        XCTAssertEqual(lib.count(for: "a", kind: .story), 1)
        XCTAssertEqual(lib.entries(for: "b"), [], "別の人の下書きが見えた")
    }

    /// 20件でいっぱい（複製もしない）。**黙って古いものを消さない**
    func testLimitIsTwentyAndNothingIsDroppedSilently() async {
        for i in 0..<20 { savePost("下書き\(i)", at: now.addingTimeInterval(Double(-i))) }
        let lib = library()
        XCTAssertTrue(lib.isFull(for: "a"))
        XCTAssertEqual(DraftLibrary.limit, 20)
        let first = lib.entries(for: "a").first!
        XCTAssertNil(lib.duplicate(first.id, kind: .post, for: "a"), "いっぱいなのに複製した")
        XCTAssertEqual(lib.count(for: "a"), 20, "黙って増やした・消した")
        XCTAssertFalse(DraftLibrary.isFull(count: 19))
    }

    // MARK: - ストーリーの期限

    /// 🔴 ストーリーの下書きは保存から7日で消える。2日前から「あと n 日」。投稿の下書きは消えない
    func testStoryDraftsExpireAfterSevenDays() async {
        let old = saveStory("古い", ageDays: 7.1)
        saveStory("あと1日", ageDays: 6.2)
        saveStory("あと3日", ageDays: 4.5)
        savePost("投稿", at: now.addingTimeInterval(-86_400 * 300))
        let lib = library()
        let entries = lib.entries(for: "a")
        XCTAssertFalse(entries.contains { $0.id == old }, "7日を過ぎたストーリーの下書きが残った")
        XCTAssertTrue(entries.contains { $0.title == "投稿" }, "投稿の下書きに期限を付けた")
        let soon = entries.first { $0.title == "あと1日" }!
        let later = entries.first { $0.title == "あと3日" }!
        XCTAssertEqual(DraftLibrary.daysLeft(kind: .story, savedAt: soon.savedAt, now: now), 1)
        XCTAssertEqual(DraftLibrary.daysLeft(kind: .story, savedAt: later.savedAt, now: now), 3)
        XCTAssertTrue(DraftLibrary.showsDaysLeft(1))
        XCTAssertTrue(DraftLibrary.showsDaysLeft(2))
        XCTAssertFalse(DraftLibrary.showsDaysLeft(3), "2日より前から知らせた")
        XCTAssertNil(DraftLibrary.daysLeft(kind: .post, savedAt: now, now: now))
        // 期限で消したストーリーの画像も消えている（1件の画像＝消えなかった3件ぶんだけ）
        XCTAssertEqual(files().filter { $0.hasPrefix("story-draft-") }.count, 2, "期限で消した下書きの画像が残った")
    }

    // MARK: - 読めない写真

    /// 🔴 **写真が1枚読めなくても、下書きごと黙って消さない**（前は消えていた）。一覧が知らせ、
    /// 「読めた分で続ける」で残りが戻る
    func testMissingPhotoKeepsTheDraftAndRestoresTheRest() async throws {
        let id = savePost("雲海", photos: 2)
        let store = uploads(.entry(id))
        let draft = try XCTUnwrap(store.draft(for: "a"))
        try FileManager.default.removeItem(at: store.imageURL(draft.items[1]))
        let entry = try XCTUnwrap(library().entries(for: "a").first)
        XCTAssertEqual(entry.missingCount, 1)
        XCTAssertEqual(entry.readableCount, 1)
        XCTAssertNotNil(uploads(.entry(id)).draft(for: "a"), "読めない写真があるだけで下書きごと消した")

        let model = makeModel(owner: "a")
        let opened = await model.openEntry(id)
        XCTAssertTrue(opened, "読めた分で続けられない")
        XCTAssertEqual(model.items.map(\.title), ["雲海"])
        XCTAssertTrue(model.restoredDraft)
        XCTAssertEqual(model.draftEntryId, id)
    }

    // MARK: - 下書きから開いて閉じる

    /// 「この下書きを更新」は同じ1件に書き、「別の下書きとして保存」は前の1件を残して新しい1件を足す
    func testUpdateAndSaveAsNew() async throws {
        let id = savePost("元の題")
        let model = makeModel(owner: "a")
        let opened = await model.openEntry(id)
        XCTAssertTrue(opened)
        model.items[0].title = "直した題"
        XCTAssertTrue(model.saveDraft(), "この下書きを更新できない")
        XCTAssertEqual(library().count(for: "a"), 1, "更新なのに増えた")
        XCTAssertEqual(uploads(.entry(id)).draft(for: "a")?.items.first?.title, "直した題")

        let again = makeModel(owner: "a")
        let reopened = await again.openEntry(id)
        XCTAssertTrue(reopened)
        again.items[0].title = "別の題"
        XCTAssertTrue(again.saveDraftAsNew())
        let titles = library().entries(for: "a").map(\.title).sorted()
        XCTAssertEqual(titles, ["別の題", "直した題"], "別の下書きとして保存で、開いていた下書きが変わった")
        XCTAssertNotEqual(again.draftEntryId, id)
    }

    /// 新しい投稿を「下書きに保存」すると新しい1件（前の下書きは置き換わらない）
    func testNewPostAddsAnEntryWithoutReplacing() async {
        savePost("前からある")
        let model = makeModel(owner: "a", entry: UUID().uuidString)
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data([4, 4]), fileName: "b.jpg", contentType: "image/jpeg", exif: nil, coords: nil,
            takenOn: nil, dominantColor: nil))]
        model.items[0].title = "新しい"
        XCTAssertTrue(model.saveDraft())
        XCTAssertEqual(library().entries(for: "a").map(\.title).sorted(), ["前からある", "新しい"])
    }

    /// 自動の書きかけ（アプリが途中で終了）は、開いていた下書きの印を持ち、続きから戻すとその下書きの続きになる
    func testAutoDraftContinuesTheOpenedEntry() async throws {
        let id = savePost("開いた下書き")
        let model = makeModel(owner: "a")
        model.autoDrafts = uploads(.auto)
        let opened = await model.openEntry(id)
        XCTAssertTrue(opened)
        model.items[0].title = "書きかけ"
        await model.autoSaveDraft(now: now)
        XCTAssertEqual(uploads(.auto).draft(for: "a")?.entryId, id, "自動の書きかけが開いていた下書きを覚えていない")

        let resumed = makeModel(owner: "a", entry: UUID().uuidString)
        resumed.autoDrafts = uploads(.auto)
        let restored = await resumed.restoreDraft(from: .auto)
        XCTAssertTrue(restored)
        XCTAssertEqual(resumed.draftEntryId, id, "続きから戻しても、どの下書きの続きか分からない（更新先が新しい1件になる）")
        XCTAssertTrue(resumed.restoredDraft)
    }

    // MARK: - 削除・元に戻す・複製

    /// 🔴 削除は一覧から隠すだけ（画像は残す）→「元に戻す」で元の位置に戻る→時間が過ぎたら本当に消す
    func testDeleteUndoAndFinalize() async {
        let a = savePost("A", at: now)
        let b = savePost("B", at: now.addingTimeInterval(-10))
        let lib = library()
        let before = files()
        lib.hide([a])
        XCTAssertEqual(lib.entries(for: "a").map(\.id), [b])
        // 「元に戻す」を待っている間も上限に数える（待っている間に保存して戻すと 21 件になる・見直し）
        XCTAssertEqual(lib.count(for: "a"), 2, "元に戻せる下書きを上限から外した")
        XCTAssertEqual(files(), before, "「元に戻す」の間に画像を消した")
        lib.undo([a])
        XCTAssertEqual(lib.entries(for: "a").map(\.id), [a, b], "元の位置に戻らない")
        lib.hide([a])
        lib.finalize([a], for: "a")
        XCTAssertEqual(lib.entries(for: "a").map(\.id), [b])
        XCTAssertNil(uploads(.entry(a)).draft(for: "a"))
        XCTAssertEqual(files().count, before.count - 1, "消した下書きの画像が残った")
        lib.undo([a])
        XCTAssertEqual(lib.entries(for: "a").map(\.id), [b], "消し終えた後に戻った")
    }

    /// 複製は画像も写す（片方を消してももう片方は開ける）
    func testDuplicateCopiesImages() async throws {
        let id = savePost("元", photos: 2)
        let story = saveStory("夜", ageDays: 1)
        let lib = library()
        let copy = try XCTUnwrap(lib.duplicate(id, kind: .post, for: "a"))
        let storyCopy = try XCTUnwrap(lib.duplicate(story, kind: .story, for: "a"))
        lib.remove(id, for: "a")
        lib.remove(story, for: "a")
        let entries = lib.entries(for: "a")
        XCTAssertEqual(Set(entries.map(\.id)), [copy, storyCopy])
        XCTAssertTrue(entries.allSatisfy { $0.missingCount == 0 }, "複製が元の画像を指していた")
        XCTAssertEqual(entries.first { $0.id == copy }?.photoCount, 2)
    }

    /// 起動し直して送り終えたストーリーは、同じ印の下書きだけ片づける
    func testClearStoryByStamp() async {
        let sent = saveStory("送った", ageDays: 1)
        saveStory("別", ageDays: 2)
        let lib = library()
        let stamp = lib.entries(for: "a").first { $0.id == sent }!.stamp
        XCTAssertEqual(lib.storyEntryId(stamp: stamp, for: "a"), sent)
        lib.clearStory(stamp: stamp, for: "a")
        XCTAssertEqual(lib.entries(for: "a").map(\.title), ["別"])
        // 送っている最中の下書きは一覧に出さない（開き直して二重に出さない）
        let other = lib.entries(for: "a").first!.stamp
        XCTAssertEqual(lib.entries(for: "a", sendingStoryStamp: other), [])
    }

    // MARK: - ログアウト・退会

    /// 🔴 退会ではその人の下書きを全部消す（別の人のは残す）。ログアウトでは何も消さない（人ごとの鍵で残る）
    func testAccountRemovalDeletesOnlyThatPersonsDrafts() async throws {
        savePost("A の投稿", user: "a")
        saveStory("A のストーリー", ageDays: 1, user: "a")
        savePost("B の投稿", user: "b")
        DraftViewPreference(defaults: defaults).set(.rows, for: "a")
        AccountLocalData.remove(userId: "a", username: nil, defaults: defaults, draftDirectory: directory,
                                offlineTripsRoot: directory.appendingPathComponent("offline"),
                                passRoot: directory.appendingPathComponent("pass"))
        let lib = library()
        XCTAssertEqual(lib.entries(for: "a"), [], "退会した人の下書きが残った")
        XCTAssertEqual(lib.entries(for: "b").map(\.title), ["B の投稿"], "別の人の下書きまで消した")
        XCTAssertEqual(files().filter { $0.hasPrefix("story-draft-") }, [], "退会した人のストーリーの画像が残った")
        XCTAssertEqual(DraftViewPreference(defaults: defaults).layout(for: "a"), .grid)

        let auth = try String(contentsOf: Self.root.appendingPathComponent("Sources/JourneyPhoto/Core/Auth/AuthStore.swift"),
                              encoding: .utf8)
        XCTAssertFalse(auth.contains("DraftLibrary") || auth.contains("removeAllEntries"),
                       "ログアウトで下書きを消している（owner 決定: 消さない）")
    }

    // MARK: - 決まりと文言

    /// 閉じるときの選び方: 下書きから開いた → 更新、新しい投稿でいっぱい → 整理、ほかは前の3択
    func testCloseChoice() async {
        typealias R = UploadDraftRules
        XCTAssertEqual(R.closeChoice(block: nil, openedDraft: true, full: true), .update)
        XCTAssertEqual(R.closeChoice(block: nil, openedDraft: false, full: true), .full)
        XCTAssertEqual(R.closeChoice(block: nil, openedDraft: false, full: false), .standard)
        XCTAssertEqual(R.closeChoice(block: .loading, openedDraft: true, full: false), .standard, "読み込み中に更新を出した")
        let message = R.closeDialog(block: nil, replacesOther: false, restored: false, draftCount: 3).message
        XCTAssertTrue(message.contains(L("（いま 3 / 20件）", " (3 of 20)")), "件数を添えていない")
        XCTAssertFalse(message.contains(L("1件だけ", "only one")), "「下書きは1件だけです」が残っている")
    }

    /// ストーリーの閉じる確認: 下書きから開いた回は「この下書きを更新」が先頭、いっぱいなら「下書きを整理する」
    func testStoryLeaveDialog() async {
        let opened = StoryComposerView.leaveDialog(canSaveDraft: true, loading: false, restored: true,
                                                   openedDraft: true, full: false)
        XCTAssertEqual(opened.saveTitle, DraftsText.update)
        XCTAssertEqual(opened.secondary, .saveAsNew)
        XCTAssertEqual(opened.discardTitle, DraftsText.closeWithoutChanges)
        XCTAssertNil(StoryComposerView.leaveDialog(canSaveDraft: true, loading: false, restored: true,
                                                   openedDraft: true, full: true).secondary,
                     "いっぱいなのに「別の下書きとして保存」を出した")
        let full = StoryComposerView.leaveDialog(canSaveDraft: true, loading: false, restored: false, full: true)
        XCTAssertFalse(full.canSave, "いっぱいなのに保存を出した（黙って古いものを消すことになる）")
        XCTAssertEqual(full.secondary, .tidy)
        let fresh = StoryComposerView.leaveDialog(canSaveDraft: true, loading: false, restored: false, draftCount: 4)
        XCTAssertTrue(fresh.message.contains(L("7日で消えます", "7 days")), "ストーリーの下書きの期限を言っていない")
        XCTAssertFalse(StoryComposerView.leaveDialog(canSaveDraft: false, loading: false, restored: false).message
                        .contains(L("1件だけ", "only one")))
    }

    /// 文言: 「捨てる」を使わない・日時・あと n 日・英語の単数
    func testWording() async {
        let all = [DraftsText.update, DraftsText.saveAsNew, DraftsText.closeWithoutChanges, DraftsText.tidy,
                   DraftsText.deleteThisDraft, DraftsText.deleteConfirmMessage, DraftsText.emptyMessage,
                   DraftsText.limitBand, DraftsText.fullMessage(megabytes: 3)]
        XCTAssertTrue(all.allSatisfy { !$0.contains("捨て") }, "「捨てる」が画面に出る")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))!
        XCTAssertEqual(DraftsText.saved(base.addingTimeInterval(-3_600 * 5), now: base, calendar: calendar),
                       L("今日 07:00", "Today 07:00"))
        XCTAssertEqual(DraftsText.saved(base.addingTimeInterval(-86_400), now: base, calendar: calendar),
                       L("昨日 12:00", "Yesterday 12:00"))
        XCTAssertEqual(DraftsText.saved(base.addingTimeInterval(-86_400 * 5), now: base, calendar: calendar),
                       L("10月24日 12:00", "Oct 24, 12:00"))
        XCTAssertEqual(DraftsText.daysLeftShort(2), L("あと2日", "2d left"))
        XCTAssertEqual(DraftsText.photos(1), L("1枚", "1 photo"))
        XCTAssertEqual(DraftsText.storageLine(count: 12, megabytes: 31),
                       L("12 / 20件 · 31 MB · この端末にだけ保存", "12 / 20 · 31 MB · Saved on this device only"))
        XCTAssertEqual(DraftsText.selectionTitle(0), L("選んでください", "Select drafts"))
        XCTAssertEqual(DraftsText.deleteButton(2), L("2件を削除", "Delete 2"))
    }

    /// 表示（格子／行）は人ごとに覚える。既定は格子
    func testLayoutIsRemembered() async {
        let pref = DraftViewPreference(defaults: defaults)
        XCTAssertEqual(pref.layout(for: "a"), .grid)
        pref.set(.rows, for: "a")
        XCTAssertEqual(pref.layout(for: "a"), .rows)
        XCTAssertEqual(pref.layout(for: "b"), .grid, "別の人の選んだ表示が移った")
    }

    // MARK: - 配線

    /// 入口4つ（マイページの格子の先頭・「投稿する」のシートのバッジ・投稿の作成画面の上・ストーリーの写真選びの手前）と、
    /// マイページの非公開の写真の札が「非公開」になっていること、画面写真の試験があること
    func testEntryPointsAreWired() async throws {
        let mypage = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(mypage.contains("if draftCount > 0 { draftsTile }"), "マイページの格子の先頭に下書きの札が無い")
        XCTAssertTrue(mypage.contains(#"Text(L("非公開", "Private"))"#), "非公開の写真の札が「非公開」になっていない")
        XCTAssertFalse(mypage.contains("""
                    Text(L("下書き", "Draft"))
                        .font(JPFont.caption.weight(.semibold))
            """), "非公開の写真に「下書き」の札が残っている")
        let sheet = try source("Features/Upload/PostSheet.swift")
        XCTAssertTrue(sheet.contains("CountBadge(count: drafts)"), "「投稿する」のシートに件数バッジが無い")
        let upload = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("draftsEntryRow"), "投稿の作成画面に「下書き n ›」が無い")
        XCTAssertTrue(upload.contains("hasSavedDraft: false"), "開いたときに本人の下書きを尋ねている（自動の書きかけだけに残す）")
        XCTAssertTrue(upload.contains("Button(DraftsText.update) { saveDraftAndClose(update: true) }"))
        XCTAssertTrue(upload.contains("Button(DraftsText.tidy) { openDraftList(tidying: true) }"))
        let story = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(story.contains("draftsEntryRow"), "ストーリーの写真選びの手前に「下書き n ›」が無い")
        XCTAssertTrue(story.contains("@StateObject private var drafts = StoryDraftStore(slot: .entry(UUID().uuidString))"))
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("openDraft: openPostDraftId"))
        XCTAssertTrue(root.contains("StoryComposerView(openDraft: openStoryDraftId)"))
        let app = try source("App/JourneyPhotoApp.swift")
        XCTAssertTrue(app.contains("DraftLibrary.shared.prepare(for: userId)"), "起動のときに前の版の下書きを移していない")
        XCTAssertTrue(app.contains("DraftLibrary.shared.clearStory(stamp: stamp, for: userId)"))
        let shots = try String(contentsOf: Self.root.appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"),
                               encoding: .utf8)
        XCTAssertTrue(shots.contains("func testCapturesDrafts()"), "下書きの一覧の画面写真の試験が無い")
    }

    // MARK: - 見直し（2026-10-29）

    /// 🔴 [1] 下書き X を書いている途中で終了 → 自動の書きかけ（X の続き）が残る → 一覧から X を開いて「更新」→
    /// 後で自動の書きかけを戻して保存しても、**更新した X を古い中身で上書きしない**（新しい1件になる）
    func testStaleAutoDraftDoesNotOverwriteUpdatedEntry() async throws {
        let x = savePost("最初")
        let writing = makeModel(owner: "a")
        writing.autoDrafts = uploads(.auto)
        let opened = await writing.openEntry(x)
        XCTAssertTrue(opened)
        writing.items[0].title = "書きかけ"
        await writing.autoSaveDraft(now: now)
        XCTAssertEqual(uploads(.auto).draft(for: "a")?.entryId, x, "前提")

        let updating = makeModel(owner: "a")
        let reopened = await updating.openEntry(x)
        XCTAssertTrue(reopened)
        updating.items[0].title = "更新した"
        XCTAssertTrue(updating.saveDraft())

        let resumed = makeModel(owner: "a")
        resumed.autoDrafts = uploads(.auto)
        let restored = await resumed.restoreDraft(from: .auto)
        XCTAssertTrue(restored)
        XCTAssertNotEqual(resumed.draftEntryId, x, "更新済みの下書きの続きと見なした")
        XCTAssertFalse(resumed.restoredDraft, "「この下書きを更新」の形を出す（更新済みの下書きを上書きする）")
        XCTAssertTrue(resumed.saveDraft())
        XCTAssertEqual(uploads(.entry(x)).draft(for: "a")?.items.first?.title, "更新した", "更新した下書きを古い中身で上書きした")
        XCTAssertEqual(library().count(for: "a"), 2)
    }

    /// [1] 自動の書きかけの写真が今の X に残っていれば X の続き。X がもう無ければ X として書き直す
    func testAutoDraftStillContinuesWhenKeysMatchOrEntryIsGone() async throws {
        let x = savePost("最初")
        let writing = makeModel(owner: "a")
        writing.autoDrafts = uploads(.auto)
        let opened = await writing.openEntry(x)
        XCTAssertTrue(opened)
        await writing.autoSaveDraft(now: now)
        let resumed = makeModel(owner: "a")
        resumed.autoDrafts = uploads(.auto)
        let restored = await resumed.restoreDraft(from: .auto)
        XCTAssertTrue(restored)
        XCTAssertEqual(resumed.draftEntryId, x, "印が合うのに続きと見なさない")

        library().remove(x, for: "a")
        let gone = makeModel(owner: "a")
        gone.autoDrafts = uploads(.auto)
        let again = await gone.restoreDraft(from: .auto)
        XCTAssertTrue(again)
        XCTAssertEqual(gone.draftEntryId, x)
    }

    /// 🔴 [2] 「別の下書きとして保存」が書けなかったら、開いていた下書きとのつながり（印）も戻す
    func testSaveAsNewFailureKeepsTheLink() async throws {
        let x = savePost("元", photos: 2)
        let model = makeModel(owner: "a")
        let opened = await model.openEntry(x)
        XCTAssertTrue(opened)
        XCTAssertEqual(model.linkedDraftPhotoCount, 2, "前提")
        // 書けない名前（無いフォルダの下）にして失敗させる
        model.drafts?.makeToken = { "missing-folder/x" }
        XCTAssertFalse(model.saveDraftAsNew())
        XCTAssertEqual(model.draftEntryId, x)
        XCTAssertEqual(model.linkedDraftPhotoCount, 2, "つながりが切れた（上がった写真が下書きに残り、二重に投稿する）")
    }

    /// 🔴 [3] 一覧から開いた下書きで × で外した写真は、その場では記録から消えない（「変更を残さずに閉じる」で戻る）。
    /// 「更新」で外れ、全部上がったときにも外れる
    func testRemovingAPhotoFromAnEntryWaitsForUpdate() async throws {
        let x = savePost("元", photos: 2)
        let model = makeModel(owner: "a")
        let opened = await model.openEntry(x)
        XCTAssertTrue(opened)
        model.remove(model.items[1].id)
        XCTAssertEqual(uploads(.entry(x)).draft(for: "a")?.items.count, 2,
                       "× で外しただけで下書きから消えた（変更を残さずに閉じても戻らない）")
        XCTAssertEqual(model.pendingEntryRemovals.count, 1)
        XCTAssertTrue(model.saveDraft())
        XCTAssertEqual(uploads(.entry(x)).draft(for: "a")?.items.count, 1, "更新しても外れない")

        let y = savePost("別", photos: 2)
        let posting = makeModel(owner: "a")
        let reopened = await posting.openEntry(y)
        XCTAssertTrue(reopened)
        posting.remove(posting.items[1].id)
        posting.applyPendingEntryRemovals()
        XCTAssertEqual(uploads(.entry(y)).draft(for: "a")?.items.count, 1, "送り終えたのに外した写真が下書きに残る")
    }

    /// 開けなかったら、前の新しい1件の枠に戻す（開けなかった下書きを上書きしない）
    func testOpenEntryFailureKeepsTheNewSlot() async {
        let fresh = UUID().uuidString
        let model = makeModel(owner: "a", entry: fresh)
        let opened = await model.openEntry(UUID().uuidString)
        XCTAssertFalse(opened)
        XCTAssertEqual(model.draftEntryId, fresh)
    }

    /// ストーリーの時刻の印はミリ秒まで。同じ秒に保存した2件を片づけで巻き込まない
    func testStoryStampsAreMillisecondPrecise() async throws {
        let stamp = DraftLibrary.storyStamp(now)
        XCTAssertTrue(stamp.contains("."), "ミリ秒が無い")
        XCTAssertEqual(DraftLibrary.storyDate(stamp), now)
        XCTAssertNotNil(DraftLibrary.storyDate(ISO8601DateFormatter().string(from: now)), "前の版の秒までの印が読めない")
        let first = stories(.entry(UUID().uuidString))
        let second = stories(.entry(UUID().uuidString))
        for (store, offset) in [(first, 0.1), (second, 0.4)] {
            XCTAssertTrue(store.save(shots: [StoryDraftStore.ShotInput(imageData: Data([1]), fileName: "s.jpg",
                                                                       contentType: "image/jpeg", coords: nil, overlays: [])],
                                     caption: "", location: "", song: nil, durationSec: 5,
                                     savedAt: DraftLibrary.storyStamp(now.addingTimeInterval(-86_400 + offset))))
        }
        let lib = library()
        lib.clearStory(stamp: first.draft!.savedAt, for: "a")
        XCTAssertEqual(lib.count(for: "a"), 1, "同じ秒の別の下書きまで片づけた")
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertFalse(composer.contains("savedAt: ISO8601DateFormatter().string(from: Date())"), "秒までの印で保存している")
    }

    /// 前の版の1件を移す ID は利用者から決まる（二重に走っても1件）
    func testLegacyEntryIdIsDeterministic() async throws {
        let id = DraftLibrary.legacyEntryId(userId: "a", kind: .post)
        XCTAssertEqual(id, DraftLibrary.legacyEntryId(userId: "a", kind: .post))
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertNotEqual(id, DraftLibrary.legacyEntryId(userId: "a", kind: .story))
        XCTAssertNotEqual(id, DraftLibrary.legacyEntryId(userId: "b", kind: .post))
        // 同じ中身を二度移しても（別の処理が同時に移した）、同じ鍵に入って1件のまま
        XCTAssertTrue(uploads(.saved).save([UploadDraftStore.ItemInput(imageData: Data([1]), item: item("前"))],
                                           fields: fields(now), for: "a"))
        let legacyKey = try XCTUnwrap(UploadDraftStore.key(for: "a", slot: .saved))
        let legacyData = try XCTUnwrap(defaults.data(forKey: legacyKey))
        library().prepare(for: "a")
        defaults.set(legacyData, forKey: legacyKey)
        library().prepare(for: "a")
        XCTAssertEqual(library().count(for: "a"), 1, "二度移して2件になった")
        XCTAssertEqual(uploads().entryIds(for: "a"), [id])
    }

    /// 🔴 [2回目 1] 移したあとに更新した1件があるところへ、前の鍵がまた書かれた（古い版に戻して再び上げた）とき、
    /// **更新した1件を古い中身で上書きしない**（別の ID に移す）。ストーリーも同じ
    func testRemigrationDoesNotOverwriteAnUpdatedEntry() async throws {
        XCTAssertTrue(uploads(.saved).save([UploadDraftStore.ItemInput(imageData: Data([1]), item: item("前"))],
                                           fields: fields(now), for: "a"))
        let lib = library()
        lib.prepare(for: "a")
        let id = DraftLibrary.legacyEntryId(userId: "a", kind: .post)
        XCTAssertTrue(uploads(.entry(id)).save([UploadDraftStore.ItemInput(imageData: Data([2]), item: item("更新した"))],
                                               fields: fields(now), for: "a"))
        XCTAssertTrue(uploads(.saved).save([UploadDraftStore.ItemInput(imageData: Data([3]), item: item("古い版で書いた"))],
                                           fields: fields(now), for: "a"))
        lib.prepare(for: "a")
        XCTAssertEqual(uploads(.entry(id)).draft(for: "a")?.items.first?.title, "更新した", "更新した1件を古い中身で上書きした")
        XCTAssertEqual(lib.entries(for: "a").map(\.title).sorted(), ["古い版で書いた", "更新した"])

        let storyId = DraftLibrary.legacyEntryId(userId: "a", kind: .story)
        let legacyStory = StoryDraftStore(defaults: defaults, directory: directory)
        legacyStory.use(userId: "a")
        XCTAssertTrue(legacyStory.save(imageData: Data([4]), fileName: "a.jpg", contentType: "image/jpeg", coords: nil,
                                       caption: "最初", location: "", overlays: [], song: nil, durationSec: 5,
                                       savedAt: DraftLibrary.storyStamp(now)))
        lib.prepare(for: "a")
        XCTAssertTrue(stories(.entry(storyId)).save(
            shots: [StoryDraftStore.ShotInput(imageData: Data([5]), fileName: "b.jpg", contentType: "image/jpeg",
                                              coords: nil, overlays: [])],
            caption: "更新したストーリー", location: "", song: nil, durationSec: 5,
            savedAt: DraftLibrary.storyStamp(now.addingTimeInterval(1))))
        XCTAssertTrue(legacyStory.save(imageData: Data([6]), fileName: "c.jpg", contentType: "image/jpeg", coords: nil,
                                       caption: "古い版のストーリー", location: "", overlays: [], song: nil, durationSec: 5,
                                       savedAt: DraftLibrary.storyStamp(now.addingTimeInterval(2))))
        lib.prepare(for: "a")
        XCTAssertEqual(stories(.entry(storyId)).draft?.caption, "更新したストーリー", "更新したストーリーの下書きを上書きした")
        XCTAssertEqual(lib.count(for: "a", kind: .story), 2)
    }

    /// 🔴 [2回目 3] 下書きを開いて × で外した写真がある回に終了 → 書きかけから続けて全部送ったら、外した写真も下書きから外れる
    func testAutoDraftCarriesPendingRemovals() async throws {
        let x = savePost("元", photos: 2)
        let writing = makeModel(owner: "a")
        writing.autoDrafts = uploads(.auto)
        let opened = await writing.openEntry(x)
        XCTAssertTrue(opened)
        writing.remove(writing.items[1].id)
        await writing.autoSaveDraft(now: now)
        XCTAssertEqual(uploads(.auto).draft(for: "a")?.pendingRemovals?.count, 1, "書きかけが外した写真を覚えていない")

        let resumed = makeModel(owner: "a")
        resumed.autoDrafts = uploads(.auto)
        let restored = await resumed.restoreDraft(from: .auto)
        XCTAssertTrue(restored)
        XCTAssertEqual(resumed.draftEntryId, x)
        XCTAssertEqual(resumed.pendingEntryRemovals.count, 1, "続けた回に外した写真を引き継がない")
        resumed.applyPendingEntryRemovals()
        XCTAssertEqual(uploads(.entry(x)).draft(for: "a")?.items.count, 1, "外した写真が下書きに残った")
    }

    /// [2回目 2・4] 件数は削除を済ませたら読み直す・複製の押せる判定は上限と同じ数え方・2本目の依頼を捨てない
    func testSecondReviewWiring() async throws {
        for path in ["Features/Upload/UploadView.swift", "Features/Stories/StoryComposerView.swift"] {
            XCTAssertTrue(try source(path).contains(".onChange(of: draftLibrary.revision) { _, _ in refreshDraftCount() }"),
                          "\(path): 削除を済ませても件数を読み直さない")
        }
        let list = try source("Features/Drafts/DraftsView.swift")
        XCTAssertTrue(list.contains(".disabled(DraftLibrary.isFull(count: limitCount) || entry.readableCount == 0)"))
        XCTAssertTrue(list.contains("limitCount = library.count(for: userId)"))
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("queuedDraft = entry"), "待っている間に来た依頼を捨てている")
        XCTAssertTrue(root.contains("next = queuedDraft"))
    }

    /// 格子／行の切り替えは押せる範囲 44・下書きを開く道は待っている間に重ねず、開けなければ知らせる
    func testSmallFixesAreWired() async throws {
        XCTAssertEqual(DraftsView.segmentFaceHeight + DraftsView.segmentTapSlack * 2, 44)
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("guard !openingDraft else {"))
        XCTAssertTrue(root.contains("下書きを開けませんでした"), "開けなかったことを黙っている")
    }

    /// 🔴 上のバーの文字ボタンは切れずに1行（107c の「ャンセ」）: 44×44 の枠をボタンに付けず、字の幅に合わせて広げる。
    /// 英語は「Cancel」「Select all」
    func testBarButtonsAreNotSqueezed() async throws {
        let list = try source("Features/Drafts/DraftsView.swift")
        let toolbar = try XCTUnwrap(list.range(of: "private var toolbar: some ToolbarContent {"))
        let end = try XCTUnwrap(list.range(of: "/// 上のバーの文字ボタン", range: toolbar.upperBound..<list.endIndex))
        let body = String(list[toolbar.upperBound..<end.lowerBound])
        XCTAssertFalse(body.contains(".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)"),
                       "バーのボタンに 44×44 の枠を付けている（字が丸い札に押し込まれて切れる）")
        XCTAssertEqual(body.components(separatedBy: "barLabel(").count - 1, 4, "バーの文字ボタンが共通の形を通っていない")
        XCTAssertTrue(list.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertTrue(try source("Features/Drafts/DraftsText.swift").contains(#"L("すべて", "Select all")"#))
    }

    // MARK: - 道具

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent("Sources/JourneyPhoto/\(path)"), encoding: .utf8)
    }

    private func makeModel(owner: String, entry: String? = nil) -> UploadViewModel {
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.drafts = uploads(.entry(entry ?? UUID().uuidString))
        model.draftOwner = owner
        model.makeDraftThumbnail = { _ in nil }
        return model
    }
}
