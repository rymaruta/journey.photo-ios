import XCTest
import CoreBluetooth
@testable import JourneyPhoto
// 選択の印（`PhotosPickerItem`）は SwiftUI と PhotosUI の両方が要る（`Tools/check-cross-imports.py`）
import SwiftUI
import PhotosUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 完成度レビューの「データ消失・表示のずれ」（2026-10-16）。
///
/// 1. 送信中にアプリが終了されると、送れていない写真が知らせも無く消えた（送信の控え）
/// 2. 投稿・ストーリーの書きかけが自動で残らなかった（裏に回ったときの自動の書きかけ）
/// 3. 写真選びの `preferredItemEncoding: .current`
/// 4. スポットのページからの投稿がマイページ・ホームに先に出なかった
/// 5. 新しい投稿が公開の一覧（探す・地図・ホームのおすすめ）に最大60秒出なかった
/// 6. すれちがいで Bluetooth を切っても何も知らせなかった
/// 7. 選択を外した写真・空にして閉じた画面の写しが、自動の書きかけ・送信の控えに残った
@MainActor
final class NoDataLossTests: XCTestCase {

    private let defaults = UserDefaults(suiteName: "NoDataLossTests.\(UUID().uuidString)")!
    nonisolated private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NoDataLossTests-\(UUID().uuidString)")

    override func setUp() {
        super.setUp()
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func saved() -> UploadDraftStore { UploadDraftStore(defaults: defaults, directory: directory) }
    private func auto() -> UploadDraftStore { UploadDraftStore(defaults: defaults, directory: directory, slot: .auto) }
    /// その人の送信の控え（古い順）
    private func journals(_ owner: String = "a") -> [(id: String, draft: UploadDraftStore.Draft)] {
        saved().journals(for: owner)
    }

    private func model(owner: String?) -> UploadViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: config)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.drafts = saved()
        model.autoDrafts = auto()
        model.draftOwner = owner
        model.makeDraftThumbnail = { _ in nil }
        return model
    }

    private func shot(_ byte: UInt8) -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: Data(repeating: byte, count: 16), fileName: "photo\(byte).jpg",
                               contentType: "image/jpeg", exif: nil, coords: nil,
                               takenOn: "2026-09-12", dominantColor: "#334455")
    }

    private func photo(_ byte: UInt8, title: String) -> PendingPhoto {
        var p = PendingPhoto(prepared: shot(byte))
        p.title = title
        return p
    }

    private static let presign = """
    {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
    """
    private static let saveOK = #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 1. 送信の控え

    /// 🔴 **新しい投稿（下書きから開き直していない）も、送り始める前に控えに書く。** 1枚目の保存が
    /// 通った瞬間（ここでアプリが終了されても）、まだ送っていない2枚目は控えに残っている
    func testNewPostIsJournaledBeforeSending() async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: Self.saveOK),
        ]
        let model = model(owner: "a")
        model.items = [photo(1, title: "1枚目"), photo(2, title: "2枚目")]
        var whileSaving: [(id: String, draft: UploadDraftStore.Draft)] = []
        model.onSaved = { [unowned self] _ in
            if whileSaving.isEmpty { whileSaving = self.journals() }
        }
        await model.submit()
        XCTAssertEqual(whileSaving.count, 1, "送り始める前に控えを書いていない（落ちたら写真が消える）")
        XCTAssertEqual(whileSaving.first?.draft.items.map(\.title), ["1枚目", "2枚目"], "まだ送っていない写真が控えに無い")
        XCTAssertEqual(whileSaving.first?.draft.items.first?.inFlight, true, "送っている1枚に印が無い")
        XCTAssertNil(whileSaving.first?.draft.items.last?.inFlight)
        XCTAssertTrue(model.didPostAll, "前提: 全部上がった")
        XCTAssertTrue(journals().isEmpty, "全部送れたのに控えが残った（次に開いて二重に尋ねる）")
        XCTAssertNil(saved().draft(for: "a"), "本人の下書きの枠に書いた")
        XCTAssertNil(auto().draft(for: "a"), "書きかけの枠に書いた")
    }

    /// 送れなかった写真は控えに残り、次の起動で知らせ、「続きから」で戻せる。上がった写真は戻らない
    func testUnsentPhotoSurvivesAndIsAnnouncedAndRestored() async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: Self.saveOK),
        ]
        let first = model(owner: "a")
        first.items = [photo(1, title: "上がる"), photo(2, title: "届かない")]
        await first.submit()
        let left = journals()
        XCTAssertEqual(left.first?.draft.items.map(\.title), ["届かない"], "送れなかった写真が控えに無い・上がった写真が残った")
        XCTAssertNil(left.first?.draft.items.first?.inFlight)

        // 次の起動（アプリが終了されていた）
        let notice = UploadDraftRules.interruptedNotice(left)
        XCTAssertEqual(notice?.resumeId, left.first?.id, "送れなかった投稿を知らせない")
        XCTAssertTrue(notice?.message.contains(L("1 件", "1 post")) == true, notice?.message ?? "")

        let next = model(owner: "a")
        let restored = await next.restoreDraft(from: .send(left[0].id))
        XCTAssertTrue(restored)
        XCTAssertEqual(next.items.map(\.title), ["届かない"])
        XCTAssertEqual(next.journalId, left[0].id, "戻した控えをこの画面が引き継がない（送り直すと控えが2件になる）")
        XCTAssertFalse(next.restoredDraft, "控えを本人の下書きとして扱った（閉じる確認の言い方がずれる）")
    }

    /// 送っている途中だった（届いたか分からない）写真だけなら「続きから」は出さず、確かめるよう言う
    func testInterruptedNoticeForUnsureOnly() async {
        let unsure = UploadDraftStore.Item(imageFile: "x", fileName: "a.jpg", contentType: "image/jpeg",
                                           title: "", caption: "", location: "", locationClearedByUser: false,
                                           key: "k", inFlight: true)
        let draft = UploadDraftStore.Draft(items: [unsure], tagsText: "", category: "", published: true,
                                           audience: "everyone", groupsAsOnePost: false, savedAt: "")
        let notice = UploadDraftRules.interruptedNotice([(id: "j1", draft: draft)])
        XCTAssertNil(notice?.resumeId, "戻せない控えに「続きから」を出した")
        XCTAssertEqual(notice?.unsureOnlyIds, ["j1"], "戻せない控えを片づけない")
        XCTAssertNil(UploadDraftRules.interruptedNotice([]))
    }

    /// 起動のあとに知らせる配線
    func testRootViewAnnouncesInterruptedUpload() async throws {
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains(".task(id: auth.userId) { await offerInterruptedUpload() }"))
        XCTAssertTrue(root.contains("UploadDraftRules.interruptedNotice("))
        XCTAssertTrue(root.contains("UploadDraftStore().journals(for: userId)"))
    }

    // MARK: - 2. 自動の書きかけ

    /// 🔴 **裏に回ったら、本人の下書きとは別の枠に黙って残す**（前の下書きを上書きしない）。
    /// 写真が無ければ書かない。保存し直したら自動の枠は消える
    func testAutoSaveUsesItsOwnSlot() async {
        let earlier = model(owner: "a")
        earlier.items = [photo(9, title: "前の下書き")]
        XCTAssertTrue(earlier.saveDraft())

        let empty = model(owner: "a")
        await empty.autoSaveDraft()
        XCTAssertNil(auto().draft(for: "a"), "写真が無いのに書いた")

        let writing = model(owner: "a")
        writing.items = [photo(1, title: "書きかけ")]
        writing.tagsText = "雲海"
        await writing.autoSaveDraft()
        XCTAssertEqual(auto().draft(for: "a")?.items.map(\.title), ["書きかけ"], "裏に回っても残らない")
        XCTAssertTrue(journals().isEmpty, "裏に回っただけで送信の控えを書いた（起動で知らせてしまう）")
        XCTAssertEqual(saved().draft(for: "a")?.items.map(\.title), ["前の下書き"], "本人の下書きを黙って上書きした")

        // 次に開いたとき「続きから」
        let next = model(owner: "a")
        let restored = await next.restoreDraft(from: .auto)
        XCTAssertTrue(restored)
        XCTAssertEqual(next.items.map(\.title), ["書きかけ"])
        XCTAssertEqual(next.tagsText, "雲海")

        // 下書きに保存したら、自動の枠は要らない
        XCTAssertTrue(next.saveDraft())
        XCTAssertNil(auto().draft(for: "a"), "下書きに移したのに自動の書きかけが残った（二重に尋ねる）")
    }

    /// 写真を外したら・全部外してから裏に回ったら、前の自動の書きかけから消す（外した写真が蘇らない）
    func testAutoSaveClearsRemovedPhotos() async {
        let model = model(owner: "a")
        model.items = [photo(1, title: "x")]
        await model.autoSaveDraft()
        XCTAssertNotNil(auto().draft(for: "a"))
        model.remove(model.items[0].id)
        XCTAssertNil(auto().draft(for: "a"), "外した写真が自動の枠に残った")
        model.items = [photo(2, title: "y")]
        await model.autoSaveDraft()
        model.items = []
        await model.autoSaveDraft()
        XCTAssertNil(auto().draft(for: "a"), "写真が無いのに前の書きかけを残した")
    }

    /// 自動の枠は退会で消える・起動の掃除で消されない
    func testAutoSlotSurvivesSweepAndIsRemovedWithAccount() async {
        let model = model(owner: "a")
        model.items = [photo(1, title: "x")]
        await model.autoSaveDraft()
        saved().sweepOrphans()
        XCTAssertNotNil(auto().draft(for: "a"), "起動の掃除が自動の書きかけの画像を消した")
        AccountLocalData.remove(userId: "a", username: nil, defaults: defaults, draftDirectory: directory,
                                offlineTripsRoot: directory.appendingPathComponent("offline"))
        XCTAssertNil(auto().draft(for: "a"), "退会した人の自動の書きかけが残った")
    }

    /// ストーリー: 自動の枠は本人の下書きと別。掃除で互いの画像を消さない
    func testStoryAutoSlotIsSeparate() async {
        let savedStore = StoryDraftStore(defaults: defaults, directory: directory)
        let autoStore = StoryDraftStore(defaults: defaults, directory: directory, slot: .auto)
        savedStore.use(userId: "a")
        autoStore.use(userId: "a")
        XCTAssertTrue(savedStore.save(imageData: Data([1]), fileName: "a.jpg", contentType: "image/jpeg", coords: nil,
                                      caption: "下書き", location: "", overlays: [], song: nil, durationSec: 5, savedAt: "1"))
        XCTAssertTrue(autoStore.save(imageData: Data([2]), fileName: "b.jpg", contentType: "image/jpeg", coords: nil,
                                     caption: "書きかけ", location: "", overlays: [], song: nil, durationSec: 5, savedAt: "2"))
        // 開き直す（`use` は掃除もする）
        let savedAgain = StoryDraftStore(defaults: defaults, directory: directory)
        let autoAgain = StoryDraftStore(defaults: defaults, directory: directory, slot: .auto)
        savedAgain.use(userId: "a")
        autoAgain.use(userId: "a")
        XCTAssertEqual(savedAgain.draft?.caption, "下書き", "自動の書きかけが本人の下書きを上書きした")
        XCTAssertEqual(autoAgain.draft?.caption, "書きかけ")
        XCTAssertNotNil(savedAgain.imageData(), "自動の枠の掃除が本人の下書きの画像を消した")
        XCTAssertNotNil(autoAgain.imageData(), "本人の枠の掃除が自動の書きかけの画像を消した")
        autoAgain.clear()
        let check = StoryDraftStore(defaults: defaults, directory: directory)
        check.use(userId: "a")
        XCTAssertEqual(check.draft?.caption, "下書き", "自動の書きかけを消したら本人の下書きまで消えた")
    }

    /// ストーリー: 写真が無ければ書かない（前の分を消す）・読み込み中は触らない
    func testStoryAutoSaveRule() async {
        XCTAssertEqual(StorySimpleRules.autoSave(hasShots: true, loading: false), .write)
        XCTAssertEqual(StorySimpleRules.autoSave(hasShots: false, loading: false), .clear)
        XCTAssertEqual(StorySimpleRules.autoSave(hasShots: true, loading: true), .skip)
    }

    /// 画面の配線: 裏に回ったら書く・開いたら「続きから」・閉じる/投稿で消す
    func testAutoSaveIsWired() async throws {
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("await model.autoSaveDraft()"), "投稿: 裏に回っても書かない")
        XCTAssertTrue(upload.contains("model.autoDrafts = autoStore"))
        XCTAssertTrue(upload.contains("Button(L(\"続きから\", \"Continue\")) { restoreDraft(from: .auto) }"))
        XCTAssertTrue(upload.contains("model.discardAutoDraft()"), "投稿をやめても自動の書きかけが残る")

        let story = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(story.contains("await autoSaveDraft()"), "ストーリー: 裏に回っても書かない")
        XCTAssertTrue(story.contains("@StateObject private var autoDrafts = StoryDraftStore(slot: .auto)"))
        XCTAssertTrue(story.contains("Button(L(\"続きから\", \"Continue\")) { restoreDraft(from: autoDrafts) }"))
        XCTAssertGreaterThanOrEqual(story.components(separatedBy: "clearAutoDraft()").count - 1, 5,
                                    "保存・投稿・保存せずに閉じる・削除のどれかで自動の書きかけを消していない")
    }

    // MARK: - 3. 写真選び

    /// 🔴 ストーリーの「＋→ライブラリ」と投稿の「追加」も元の形のまま受け取る（埋め込みの写真選びと同じ）
    func testSheetPickersUseCurrentEncoding() async throws {
        let story = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        let storySheet = try XCTUnwrap(story.range(of: ".photosPicker(isPresented: $showLibrary"))
        XCTAssertTrue(story[storySheet.upperBound...].prefix(260).contains("preferredItemEncoding: .current"),
                      "ストーリーの「＋→ライブラリ」が作り直しを待つ")
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        let uploadSheet = try XCTUnwrap(upload.range(of: ".photosPicker(isPresented: $showLibrary"))
        XCTAssertTrue(upload[uploadSheet.upperBound...].prefix(260).contains("preferredItemEncoding: .current"),
                      "投稿の「追加」が作り直しを待つ")
    }

    /// UI 試験: ＋から足した1枚が並ぶのを待ってから「シェアする」を見る（読み込み前に通らない）
    func testStoryPickerUITestWaitsForTheAddedShot() async throws {
        let test = try source("UITests/JourneyPhotoUITests/StoryPickerTests.swift")
        XCTAssertTrue(test.contains("addFromLibrarySheet(app, tag: \"\\(tag)-6\", before: count)"))
        XCTAssertTrue(test.contains("app.buttons[\"\\(before + 1)枚目\"]"))
    }

    // MARK: - 4. 投稿画面の onSaved

    /// 🔴 **投稿画面を開く所は全部、上がった写真を外へ渡す**（スポットのページからの投稿が
    /// マイページ・ホームに先に出なかった）
    func testEveryUploadViewPassesOnSaved() async throws {
        let sources = Self.root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var opened = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            var rest = text[...]
            while let r = rest.range(of: "UploadView(") {
                let before = rest[..<r.lowerBound].suffix(1)
                rest = rest[r.upperBound...]
                // `struct UploadView(` は無い。`PreviewUploadView(` などの別の名前は数えない
                if let c = before.first, c.isLetter { continue }
                opened += 1
                // 呼び出しの閉じかっこまで（入れ子のかっこを数える）
                var depth = 1
                var call = ""
                for ch in rest {
                    if ch == "(" { depth += 1 }
                    if ch == ")" { depth -= 1; if depth == 0 { break } }
                    call.append(ch)
                }
                XCTAssertTrue(call.contains("onSaved:") && call.contains("notePosted"),
                              "\(file.lastPathComponent) の UploadView に onSaved（notePosted）が無い")
            }
        }
        XCTAssertGreaterThanOrEqual(opened, 2, "投稿画面を開く所が見つからない")
    }

    // MARK: - 5. 公開の一覧に重ねる

    private func postedPhoto(_ json: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    /// 公開した写真だけを重ねる（絞った写真・下書きは重ねない）。同じ id は読んだ行を採る
    func testOverlayPublicSkipsRestrictedAndUnpublished() async throws {
        let open = try postedPhoto(#"{"id":"n1","src":"https://x/n1.jpg","published":true,"createdAt":"2026-10-16T01:00:00Z","userId":"a"}"#)
        let limited = try postedPhoto(#"{"id":"n2","src":"https://x/n2.jpg","published":true,"audience":"followers","createdAt":"2026-10-16T01:00:00Z","userId":"a"}"#)
        let draft = try postedPhoto(#"{"id":"n3","src":"https://x/n3.jpg","published":false,"createdAt":"2026-10-16T01:00:00Z","userId":"a"}"#)
        let old = try postedPhoto(#"{"id":"o1","src":"https://x/o1.jpg","published":true,"createdAt":"2026-10-01T00:00:00Z","userId":"b"}"#)
        let merged = PostedPhotos.overlayPublic(loaded: [old], posted: [open, limited, draft])
        XCTAssertEqual(merged.map(\.id), ["n1", "o1"], "絞った写真・下書きを公開の一覧に出した・新しい投稿が出ない")
        let caughtUp = try postedPhoto(#"{"id":"n1","src":"https://x/n1-server.jpg","published":true,"createdAt":"2026-10-16T01:00:00Z","userId":"a"}"#)
        XCTAssertEqual(PostedPhotos.overlayPublic(loaded: [caughtUp, old], posted: [open]).first?.src,
                       "https://x/n1-server.jpg", "読んだ行より保存の応答の行を採った")
        XCTAssertEqual(PostedPhotos.overlayPublic(loaded: [old], posted: []).map(\.id), ["o1"])
    }

    /// 🔴 **一覧の控え（60秒）の間でも、閉じた投稿画面の写真が公開の一覧に出る**。期限を過ぎたら重ねない
    func testPublicGalleryShowsJustPostedPhoto() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        ScriptedProtocol.script = [
            .init(match: "photos.json", status: 200,
                  body: #"[{"id":"o1","src":"https://x/o1.jpg","published":true,"createdAt":"2026-10-01T00:00:00Z","userId":"b"}]"#),
        ]
        let ledger = PostedPhotos.Ledger()
        let service = PublicGalleryService(url: URL(string: "https://site.example.test/app/data/photos.json")!,
                                           session: URLSession(configuration: config),
                                           snapshot: PhotoSnapshotStore(fileName: UUID().uuidString),
                                           posted: ledger)
        let before = try await service.fetchPhotos()
        XCTAssertEqual(before.map(\.id), ["o1"])
        ledger.note([try postedPhoto(#"{"id":"n1","src":"https://x/n1.jpg","published":true,"createdAt":"2026-10-16T01:00:00Z","userId":"a"}"#)])
        // 控え（60秒）の間の読み直し
        let after = try await service.fetchPhotos()
        XCTAssertEqual(after.map(\.id), ["n1", "o1"], "新しい投稿が公開の一覧に出ない（控えの60秒待つ）")

        let expired = PostedPhotos.Ledger()
        expired.note(ledger.photos(), at: Date().addingTimeInterval(-(PostedPhotos.keepSeconds + 1)))
        XCTAssertTrue(expired.photos().isEmpty, "期限を過ぎた控えを重ねた")
        expired.note([])
        XCTAssertTrue(expired.photos().isEmpty)
    }

    /// 投稿画面を閉じたら公開の一覧の控えにも渡す
    func testTabRouterFeedsThePublicLedger() async throws {
        let router = try source("Sources/JourneyPhoto/Core/Storage/TabRouter.swift")
        XCTAssertTrue(router.contains("PostedPhotos.Ledger.shared.note(posting)"))
    }

    // MARK: - 6. Bluetooth がオフ

    /// 🔴 **すれちがいをオンにしていて Bluetooth の電源が切れていたら、設定画面で言う**
    func testPassShowsBluetoothOffNotice() async throws {
        XCTAssertTrue(PassRadio.showsPowerOffNotice(enabled: true, state: .poweredOff))
        XCTAssertFalse(PassRadio.showsPowerOffNotice(enabled: false, state: .poweredOff), "オフにしている人に出した")
        XCTAssertFalse(PassRadio.showsPowerOffNotice(enabled: true, state: .poweredOn))
        XCTAssertFalse(PassRadio.showsPowerOffNotice(enabled: true, state: .unknown))

        let radio = try source("Sources/JourneyPhoto/Services/PassRadio.swift")
        XCTAssertTrue(radio.contains("powerState = central.state"), "電源の状態を受け取っていない")
        let view = try source("Sources/JourneyPhoto/Features/Pass/PassSettingsView.swift")
        XCTAssertTrue(view.contains("PassRadio.showsPowerOffNotice(enabled: pass.settings.enabled, state: radio.powerState)"))
        XCTAssertTrue(view.contains("Bluetooth がオフです"))
    }

    // MARK: - 読み直しの指摘（2026-10-16）

    /// 🔴 [1] ストーリー: 自動の書きかけを尋ねた回は、本人の下書きの問いに答えていない。
    /// その回の投稿・保存で本人の下書きを消さない・置き換えない（送れなかった問いの分岐と同じ）
    func testStoryAutoAskKeepsTheUnansweredSavedDraft() async throws {
        let story = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        let ask = try XCTUnwrap(story.range(of: "                showRestoreAuto = true\n"))
        XCTAssertTrue(story[ask.upperBound...].prefix(300)
                        .contains("if prepared == nil { unansweredDraftStamp = drafts.draft?.savedAt }"),
                      "自動の書きかけを尋ねた回に投稿すると、無関係な本人の下書きが消える")
    }

    /// 🔴 [2] **本人の下書きを開いて送る途中で終わり →「続きから」で送ったら、本人の下書きからも外れる**。
    /// 残ると、次に本人の下書きを開いて送ったとき同じ写真がもう一度投稿された
    func testResumedPhotoLeavesTheSavedDraftToo() async {
        let first = model(owner: "a")
        first.items = [photo(1, title: "上がる"), photo(2, title: "続きから")]
        XCTAssertTrue(first.saveDraft())

        // 本人の下書きを開いて送る。1枚目は上がり、2枚目は届かない（終了したのと同じく控えに残る）
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: Self.saveOK),
        ]
        let opened = model(owner: "a")
        let restoredSaved = await opened.restoreDraft()
        XCTAssertTrue(restoredSaved)
        await opened.submit()
        XCTAssertEqual(saved().draft(for: "a")?.items.map(\.title), ["続きから"], "前提")
        let left = journals()
        XCTAssertEqual(left.first?.draft.items.map(\.title), ["続きから"], "前提")

        // 次の起動: 自動の枠の「続きから」で送る
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: Self.saveOK),
        ]
        let resumed = model(owner: "a")
        let restoredJournal = await resumed.restoreDraft(from: .send(left[0].id))
        XCTAssertTrue(restoredJournal)
        // 本人の下書きの続きなので「下書きに保存」で閉じても「置き換わります」と言わない
        XCTAssertFalse(UploadDraftRules.closeDialog(block: resumed.draftSaveBlock,
                                                    replacesOther: !resumed.restoredDraft && resumed.storedDraft != nil,
                                                    restored: resumed.restoredDraft).message
                        .contains(L("置き換わります", "replaces")), "同じ下書きの続きなのに「置き換わります」と言う")
        await resumed.submit()
        XCTAssertTrue(resumed.didPostAll, "前提: 上がった")
        XCTAssertNil(saved().draft(for: "a"), "続きから送った写真が本人の下書きに残った（次にもう一度投稿される）")
        XCTAssertTrue(journals().isEmpty)
    }

    /// [2] ストーリー: 自動の書きかけは開いていた本人の下書きの印を持ち、続きから戻すと同じ下書きの続きになる
    func testStoryAutoDraftRemembersTheSavedDraftItContinues() async throws {
        let autoStore = StoryDraftStore(defaults: defaults, directory: directory, slot: .auto)
        autoStore.use(userId: "a")
        let ok = await autoStore.saveInBackground(
            shots: [StoryDraftStore.ShotInput(imageData: Data([1]), fileName: "a.jpg", contentType: "image/jpeg",
                                              coords: nil, overlays: [])],
            caption: "", location: "", song: nil, durationSec: 5, archive: false, allowReplies: true,
            basedOn: "saved-1", savedAt: "2")
        XCTAssertTrue(ok)
        let again = StoryDraftStore(defaults: defaults, directory: directory, slot: .auto)
        again.use(userId: "a")
        XCTAssertEqual(again.draft?.basedOn, "saved-1", "開いていた本人の下書きの印が残らない")
        XCTAssertTrue(StorySimpleRules.autoRestoreContinuesSaved(basedOn: "saved-1", savedStamp: "saved-1"))
        XCTAssertFalse(StorySimpleRules.autoRestoreContinuesSaved(basedOn: "saved-1", savedStamp: "saved-2"),
                       "別の下書き（後で保存し直したもの）まで片づける")
        XCTAssertFalse(StorySimpleRules.autoRestoreContinuesSaved(basedOn: nil, savedStamp: "saved-1"))
        let story = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(story.contains("basedOn: openedDraftStamp"), "自動の書きかけに開いていた下書きの印を書いていない")
        XCTAssertTrue(story.contains("StorySimpleRules.autoRestoreContinuesSaved(basedOn: draft.basedOn"))
    }

    /// 🔴 [3] **人が替わったら、投稿したばかりの写真の控えも捨てる**（前の人の写真を次の人の一覧に重ねない）
    func testSwitchingUserDropsThePostedLedger() async throws {
        let ledger = PostedPhotos.Ledger()
        let service = PublicGalleryService(url: URL(string: "https://site.example.test/app/data/photos.json")!,
                                           snapshot: PhotoSnapshotStore(fileName: UUID().uuidString),
                                           posted: ledger)
        ledger.note([try postedPhoto(#"{"id":"n1","src":"https://x/n1.jpg","published":true,"userId":"a"}"#)])
        await service.setRestrictedLoader(nil)
        XCTAssertTrue(ledger.photos().isEmpty, "人が替わっても前の人の投稿の控えが残った")
    }

    /// 🔴 [4] **尋ねていない自動の書きかけには触らない**。テーマ・スポット・旅の写真から開いた回は尋ねないので、
    /// 自動の枠を渡さない（黙って上書き・削除しない）。開いたとき空だった・尋ねたときだけ触る
    func testOpenActionAndAutoSlotOwnership() async throws {
        typealias R = UploadDraftRules
        let withContent = R.openAction(journalIds: [], hasAutoDraft: true, hasSavedDraft: false,
                                       opensWithContent: true, alreadyAsked: false)
        XCTAssertEqual(withContent, .none)
        XCTAssertFalse(R.ownsAutoSlot(hasAutoDraft: true, action: withContent),
                       "尋ねていない自動の書きかけを上書き・削除する")
        XCTAssertTrue(R.ownsAutoSlot(hasAutoDraft: false, action: .none), "開いたとき空なら使ってよい")
        XCTAssertEqual(R.openAction(journalIds: [], hasAutoDraft: true, hasSavedDraft: true, opensWithContent: false,
                                    alreadyAsked: false), .askAuto)
        XCTAssertTrue(R.ownsAutoSlot(hasAutoDraft: true, action: .askAuto))
        XCTAssertEqual(R.openAction(journalIds: [], hasAutoDraft: false, hasSavedDraft: true, opensWithContent: false,
                                    alreadyAsked: false), .askSaved)
        XCTAssertEqual(R.openAction(journalIds: ["j1", "j2"], hasAutoDraft: true, hasSavedDraft: true,
                                    opensWithContent: false, alreadyAsked: false), .askJournal("j1"),
                       "送れなかった投稿を古い順に1件ずつ尋ねない")
        XCTAssertEqual(R.openAction(journalIds: ["j1"], hasAutoDraft: true, hasSavedDraft: true, opensWithContent: false,
                                    alreadyAsked: true), .none)
        XCTAssertFalse(StorySimpleRules.ownsAutoSlot(hasAutoDraft: true, asked: false))
        XCTAssertTrue(StorySimpleRules.ownsAutoSlot(hasAutoDraft: true, asked: true))
        XCTAssertTrue(StorySimpleRules.ownsAutoSlot(hasAutoDraft: false, asked: false))
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("UploadDraftRules.ownsAutoSlot(hasAutoDraft: hasAuto, action: action)"))
        let story = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(story.contains("guard autoSlotOwned else { return }"))
    }

    /// 🔴 [5] **「この写真を見て撮影」を付け終えたら、送信の控えからも外す**（続きから送ると別の写真に付き、
    /// 作者に通知が2回届く）
    func testInspiredLeavesTheJournalOnceAttached() async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200,
                  body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg","inspiredBy":"src-1"}}"#),
        ]
        let model = model(owner: "a")
        model.items = [photo(1, title: "付く"), photo(2, title: "届かない")]
        model.inspired = InspiredBy.Pick(id: "src-1", title: "夕焼け", thumbURL: nil, authorName: nil, location: nil)
        await model.submit()
        let left = journals().first?.draft
        XCTAssertEqual(left?.items.map(\.title), ["届かない"], "前提")
        XCTAssertNil(left?.inspired, "付け終えた元の写真が控えに残った（続きから送ると通知が2回届く）")
    }

    /// 🔴 [6] **画像は主スレッドの外で書き、後から始まった保存が勝つ**。先に始まった裏の書き込みが遅れて
    /// 終わっても新しい記録を上書きしない。書いている間に消したら書き戻さない
    func testBackgroundSaveLaterWinsAndClearIsNotUndone() async throws {
        let store = auto()
        store.writeFiles = { pairs in
            // 1 で始まる本体（先に始まる保存）だけ遅らせる
            if pairs.first?.0.first == 1 { try await Task.sleep(nanoseconds: 200_000_000) }
            for (data, url) in pairs { try data.write(to: url, options: .atomic) }
        }
        func input(_ byte: UInt8, _ title: String) -> [UploadDraftStore.ItemInput] {
            [UploadDraftStore.ItemInput(imageData: Data(repeating: byte, count: 4), item: UploadDraftStore.Item(
                imageFile: "", fileName: "a.jpg", contentType: "image/jpeg", title: title, caption: "",
                location: "", locationClearedByUser: false))]
        }
        let fields = UploadDraftStore.Draft(items: [], tagsText: "", category: "", published: true,
                                            audience: "everyone", groupsAsOnePost: false, savedAt: "")
        let older = Task { await store.saveInBackground(input(1, "古い"), fields: fields, for: "a") }
        await Task.yield()
        let newer = Task { await store.saveInBackground(input(2, "新しい"), fields: fields, for: "a") }
        _ = await (older.value, newer.value)
        XCTAssertEqual(auto().draft(for: "a")?.items.map(\.title), ["新しい"], "遅れて終わった古い保存が上書きした")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("upload-draft-") }
        XCTAssertEqual(files.count, 1, "負けた保存の画像が残った")

        let late = Task { await store.saveInBackground(input(1, "消した後"), fields: fields, for: "a") }
        await Task.yield()
        store.clear(for: "a")
        _ = await late.value
        XCTAssertNil(auto().draft(for: "a"), "消した後に裏の保存が書き戻した")

        let model = try source("Sources/JourneyPhoto/Features/Upload/UploadViewModel.swift")
        XCTAssertTrue(model.contains("await store.saveInBackground(draftInputs(keys: keys)"),
                      "送信の控え・自動の書きかけを主スレッドで書いている")
        let view = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertTrue(view.contains("let window = BackgroundWindow(name: \"upload-autosave\")\n                Task {"),
                      "裏に回ったときの書き込みの猶予を、裏に回った瞬間に取っていない")
        let story = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(story.contains("await autoDrafts.saveInBackground("))
        XCTAssertTrue(story.contains("let window = BackgroundWindow(name: \"story-autosave\")\n                Task {"))
    }

    /// 🔴 [7] 起動のときの知らせで「続きから」を押して来たら、投稿の画面で尋ね直さずに戻す
    func testResumeFromLaunchNoticeDoesNotAskAgain() async throws {
        XCTAssertEqual(UploadDraftRules.openAction(journalIds: ["j1", "j2"], hasAutoDraft: true, hasSavedDraft: true,
                                                   opensWithContent: false, alreadyAsked: false, resumeJournal: "j2"),
                       .resumeJournal("j2"))
        XCTAssertEqual(UploadDraftRules.openAction(journalIds: [], hasAutoDraft: false, hasSavedDraft: true,
                                                   opensWithContent: false, alreadyAsked: false, resumeJournal: "gone"),
                       .askSaved, "消えた控えを戻そうとした")
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains("resumeJournal: resumeJournalId"))
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("case .resumeJournal(let id): restoreDraft(from: .send(id))"))
    }

    /// 🔴 [8] **続きから送った写真は、途中まで送った束と同じ投稿に入る**（束の印を控えに持つ）
    func testResumedPhotoKeepsTheGroup() async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: Self.saveOK),
        ]
        let first = model(owner: "a")
        first.items = [photo(1, title: "上がる"), photo(2, title: "続きから")]
        first.groupsAsOnePost = true
        await first.submit()
        let group = first.groupId
        XCTAssertNotNil(group, "前提: 束の印がある")
        let left = journals()
        XCTAssertEqual(left.first?.draft.groupId, group, "束の印を控えに持っていない")
        let next = model(owner: "a")
        let restored = await next.restoreDraft(from: .send(left[0].id))
        XCTAssertTrue(restored)
        XCTAssertEqual(next.groupId, group, "続きから送ると別の投稿に割れる")
    }

    // MARK: - 送信の控えを投稿ごとに（2026-10-16 の読み直し）

    private func failSecond() {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: Self.saveOK),
        ]
    }

    /// 🔴 [A] **テーマ・スポットから開いた回（書きかけの枠を持たない）でも、送るときは必ず控えを書く**。
    /// 前の書きかけには触らない。書きかけの枠を持つ画面なら、控えを書いた時点で書きかけを消す
    func testJournalIsAlwaysWrittenAndLeavesOtherSlotsAlone() async {
        // 前にアプリが終了した書きかけ
        let earlier = model(owner: "a")
        earlier.items = [photo(9, title: "前の書きかけ")]
        await earlier.autoSaveDraft()
        XCTAssertNotNil(auto().draft(for: "a"), "前提")

        // スポットから開いた画面（尋ねていない書きかけには触らない＝枠を渡さない）
        failSecond()
        let spot = model(owner: "a")
        spot.autoDrafts = nil
        spot.items = [photo(1, title: "上がる"), photo(2, title: "スポットの2枚目")]
        await spot.submit()
        XCTAssertEqual(journals().map { $0.draft.items.map(\.title) }, [["スポットの2枚目"]],
                       "書きかけの枠を持たない画面の送信が控えを書かない（終了すると写真が消える）")
        XCTAssertEqual(auto().draft(for: "a")?.items.map(\.title), ["前の書きかけ"], "尋ねていない書きかけを上書き・削除した")

        // 書きかけの枠を持つ画面: 控えを書いたら書きかけは消す（同じ写真を2か所に置かない）
        failSecond()
        let owner = model(owner: "a")
        owner.items = [photo(3, title: "上がる"), photo(4, title: "別の投稿")]
        await owner.autoSaveDraft()
        await owner.submit()
        XCTAssertNil(auto().draft(for: "a"), "控えに移した書きかけが残った（続きから2回送れる）")
        XCTAssertEqual(Set(journals().map { $0.draft.items.map(\.title) }), [["スポットの2枚目"], ["別の投稿"]],
                       "投稿ごとの控えにならない（前の控えを上書き・まとめた）")

        // 画面を閉じる（やめる）と、その画面の控えだけ消える
        owner.discardJournal()
        XCTAssertEqual(journals().map { $0.draft.items.map(\.title) }, [["スポットの2枚目"]], "ほかの画面の控えまで消した")

        // 送れずに残った画面が裏に回ったら、書きかけではなく自分の控えを書き直す（同じ写真を2か所に置かない）
        await spot.autoSaveDraft()
        XCTAssertEqual(journals().count, 1)
        XCTAssertNil(auto().draft(for: "a"), "控えのある画面が書きかけにも同じ写真を書いた")
    }

    /// 🔴 [B] 起動の知らせは控えを数え、「続きから」は古い順に1件
    func testLaunchNoticeCountsJournalsOldestFirst() async {
        func entry(_ id: String, _ at: String, unsure: Bool = false) -> (id: String, draft: UploadDraftStore.Draft) {
            let item = UploadDraftStore.Item(imageFile: "x", fileName: "a.jpg", contentType: "image/jpeg", title: id,
                                             caption: "", location: "", locationClearedByUser: false, key: id,
                                             inFlight: unsure ? true : nil)
            return (id: id, draft: UploadDraftStore.Draft(items: [item], tagsText: "", category: "", published: true,
                                                          audience: "everyone", groupsAsOnePost: false, savedAt: at))
        }
        let now = ISO8601DateFormatter().date(from: "2026-10-16T00:00:00Z")!
        let notice = UploadDraftRules.interruptedNotice([entry("old", "2026-10-15T00:00:00Z"),
                                                         entry("new", "2026-10-15T12:00:00Z"),
                                                         entry("unsure", "2026-10-15T13:00:00Z", unsure: true)], now: now)
        XCTAssertEqual(notice?.resumeId, "old", "古い順に1件ではない")
        XCTAssertTrue(notice?.message.contains(L("2 件", "2 post")) == true, notice?.message ?? "")
        XCTAssertEqual(notice?.unsureOnlyIds, ["unsure"])
        XCTAssertEqual(notice?.cleanupIds, [], "少なく新しいのに片づけを勧めた")

        // 実際の置き場では古い順に並ぶ
        failSecond()
        let a = model(owner: "a")
        a.items = [photo(1, title: "x"), photo(2, title: "一つ目")]
        await a.submit()
        failSecond()
        let b = model(owner: "a")
        b.items = [photo(3, title: "x"), photo(4, title: "二つ目")]
        await b.submit()
        XCTAssertEqual(journals().map { $0.draft.items.map(\.title) }, [["一つ目"], ["二つ目"]])
    }

    /// 🔴 [C] 控えが3件を超えた・7日を過ぎたら片づけを勧める
    func testOldOrManyJournalsSuggestCleanup() async {
        let now = ISO8601DateFormatter().date(from: "2026-10-16T00:00:00Z")!
        let list: [(id: String, savedAt: String)] = [
            (id: "a", savedAt: "2026-10-01T00:00:00Z"),   // 7日を過ぎた
            (id: "b", savedAt: "2026-10-14T00:00:00Z"),
            (id: "c", savedAt: "2026-10-15T00:00:00Z"),
            (id: "d", savedAt: "2026-10-15T06:00:00Z"),
        ]
        XCTAssertEqual(UploadDraftRules.journalsToClean(list, now: now), ["a"], "古い・溢れた控えを勧めない")
        XCTAssertEqual(UploadDraftRules.journalsToClean(Array(list.dropFirst()), now: now), [])
        let five = (0..<5).map { (id: "j\($0)", savedAt: "2026-10-15T0\($0):00:00Z") }
        XCTAssertEqual(UploadDraftRules.journalsToClean(five, now: now), ["j0", "j1"], "3件を超えた古いものを勧めない")
    }

    /// 🔴 [C] 退会でその人の控えを全部（画像の頭も）消す。区切りで別の人（"a:b"）を取り違えない
    func testAccountRemovalDeletesJournalsOnlyForThatPerson() async throws {
        failSecond()
        let a = model(owner: "a")
        a.items = [photo(1, title: "x"), photo(2, title: "a の控え")]
        await a.submit()
        failSecond()
        let ab = model(owner: "a:b")
        ab.items = [photo(3, title: "x"), photo(4, title: "a:b の控え")]
        await ab.submit()
        XCTAssertEqual(journals("a").count, 1, "区切りで別の人の控えを数えた")
        XCTAssertEqual(journals("a:b").count, 1)
        XCTAssertNil(UploadDraftStore.journalId(fromKey: "journey-photo-upload-draft:send:a:b:\(UUID().uuidString)", userId: "a"))
        // 記録から外れた画像（書いている途中で落ちた回）
        let strayKey = UploadDraftStore.key(for: "a", slot: .send(UUID().uuidString))!
        let stray = UploadDraftStore.imageFileName(forKey: strayKey, token: "dead", index: 0)
        try Data([1]).write(to: directory.appendingPathComponent(stray))

        AccountLocalData.remove(userId: "a", username: nil, defaults: defaults, draftDirectory: directory,
                                offlineTripsRoot: directory.appendingPathComponent("offline"))
        XCTAssertTrue(journals("a").isEmpty, "退会した人の送信の控えが残った")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(stray).path),
                       "記録から外れた控えの画像が残った")
        XCTAssertEqual(journals("a:b").count, 1, "別の人の控えまで消した")
    }

    /// 🔴 [D] 保存の回は鍵ごとに数え、1枚ずつの書き換えでも進む。別の入れ物から外した写真を、
    /// 遅れて終わった裏の保存が書き戻さない
    func testItemEditsSupersedeABackgroundSaveOnTheSameKey() async {
        let first = auto()
        func input(_ byte: UInt8, _ title: String, key: String) -> [UploadDraftStore.ItemInput] {
            [UploadDraftStore.ItemInput(imageData: Data(repeating: byte, count: 4), item: UploadDraftStore.Item(
                imageFile: "", fileName: "a.jpg", contentType: "image/jpeg", title: title, caption: "",
                location: "", locationClearedByUser: false, key: key))]
        }
        let fields = UploadDraftStore.Draft(items: [], tagsText: "", category: "", published: true,
                                            audience: "everyone", groupsAsOnePost: false, savedAt: "")
        XCTAssertTrue(first.save(input(1, "外す", key: "k1") + input(2, "残す", key: "k2"), fields: fields, for: "a"))
        first.writeFiles = { pairs in
            try await Task.sleep(nanoseconds: 200_000_000)
            for (data, url) in pairs { try data.write(to: url, options: .atomic) }
        }
        let late = Task { await first.saveInBackground(input(1, "外す", key: "k1") + input(2, "残す", key: "k2"),
                                                      fields: fields, for: "a") }
        await Task.yield()
        // 別の入れ物（同じ鍵）から1枚外す
        auto().removeItem(key: "k1", for: "a")
        _ = await late.value
        XCTAssertEqual(auto().draft(for: "a")?.items.map(\.title), ["残す"], "外した写真を遅れた保存が書き戻した")
    }

    /// 🔴 本人の下書きを**保存し直したあと**に控えから戻しても、前の下書きの印は戻さない（`savedKeysNow`）。
    /// 戻すと、別物になった今の下書きを「開いた」ことになり、保存で黙って置き換え・元の写真の印を消す
    func testJournalDoesNotReattachToAResavedDraft() async {
        let first = model(owner: "a")
        first.items = [photo(1, title: "上がる"), photo(2, title: "控えに残る")]
        XCTAssertTrue(first.saveDraft())
        failSecond()
        let opened = model(owner: "a")
        let restoredSaved = await opened.restoreDraft()
        XCTAssertTrue(restoredSaved)
        await opened.submit()
        let left = journals()
        XCTAssertNotNil(left.first?.draft.items.first?.savedKey, "前提: 控えが本人の下書きの印を持つ")

        // 本人の下書きを別の中身で保存し直す
        let other = model(owner: "a")
        other.items = [photo(7, title: "新しい下書き")]
        XCTAssertTrue(other.saveDraft())

        let resumed = model(owner: "a")
        let restored = await resumed.restoreDraft(from: .send(left[0].id))
        XCTAssertTrue(restored)
        XCTAssertFalse(resumed.restoredDraft, "保存し直した別の下書きを「開いた」ことにした（前の印を戻した）")
        XCTAssertTrue(UploadDraftRules.closeDialog(block: resumed.draftSaveBlock,
                                                   replacesOther: !resumed.restoredDraft && resumed.storedDraft != nil,
                                                   restored: resumed.restoredDraft).message
                        .contains(L("置き換わります", "replaces")), "別の下書きを置き換えると言わない")
    }

    /// 「古いものを片づける」は何を何件消すかを言う。投稿画面の問いには控えに触らない「あとで」がある。
    /// 届いたか分からない間は控えを書き直さないことを注記している
    func testCleanupWordingAndLaterButton() async throws {
        XCTAssertEqual(UploadDraftRules.cleanupButtonTitle(count: 2), L("まだ送っていない写真の投稿 2 件を削除",
                                                                         "Delete 2 unsent post(s) and their photos"))
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains("UploadDraftRules.cleanupButtonTitle(count: notice.cleanupIds.count)"))
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        let ask = try XCTUnwrap(upload.range(of: "presenting: askingJournal) { id in"))
        XCTAssertTrue(upload[ask.upperBound...].prefix(700).contains("Button(L(\"あとで\", \"Later\"), role: .cancel)"),
                      "送れなかった投稿の問いに「あとで」が無い（削除するか戻すかしか選べない）")
        let model = try source("Sources/JourneyPhoto/Features/Upload/UploadViewModel.swift")
        XCTAssertTrue(model.contains("届いたか分からない写真がある間（`visibilityLocked`"))
    }

    // MARK: - 7. 外した写真の写し（2026-10-16）

    /// 条件が立つまで待つ（最長5秒）。切り離した読み込み（`pickerItems` の didSet）の終わりを時間で当てない
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "待っても条件が立たなかった", file: file, line: line)
    }

    private func picked(_ byte: UInt8, title: String, key: PhotosPickerItem) -> PendingPhoto {
        var p = photo(byte, title: title)
        p.pickerItem = key
        return p
    }

    /// 🔴 **A・B を送って B だけ残ったあと、「追加」で B の選択を外したら、控えからも外す。** 残すと次の起動の
    /// 「送れなかった投稿」から B が戻り、本人が外した写真が投稿されえた（帯の × だけが外していた）
    func testUnselectedPhotoLeavesTheJournal() async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: Self.saveOK),
        ]
        let model = model(owner: "a")
        model.loadPickedData = { _ in nil }
        let a = PhotosPickerItem(itemIdentifier: "a")
        let b = PhotosPickerItem(itemIdentifier: "b")
        model.items = [picked(1, title: "上がる", key: a), picked(2, title: "届かない", key: b)]
        model.pickerItems = [a, b]
        await model.submit()
        XCTAssertEqual(journals().first?.draft.items.map(\.title), ["届かない"], "前提: B が控えに残る")
        XCTAssertEqual(model.items.map(\.title), ["届かない"])

        // 「追加」で B の選択を外す
        model.pickerItems = []
        await waitUntil { model.items.isEmpty }
        XCTAssertTrue(journals().isEmpty, "選択を外した写真が送信の控えに残った（次の起動で戻り、投稿されうる）")
        XCTAssertFalse(model.hasDraft, "前提: 欄も空なので × は確かめずに閉じる")
    }

    /// 選択を外した写真は、裏に回ったときに残した自動の書きかけからも外す（帯の × と同じ）
    func testUnselectedPhotoLeavesTheAutoDraft() async {
        let model = model(owner: "a")
        model.loadPickedData = { _ in nil }
        let a = PhotosPickerItem(itemIdentifier: "a")
        let b = PhotosPickerItem(itemIdentifier: "b")
        model.items = [picked(1, title: "残す", key: a), picked(2, title: "外す", key: b)]
        model.pickerItems = [a, b]
        await model.autoSaveDraft()
        XCTAssertEqual(auto().draft(for: "a")?.items.map(\.title), ["残す", "外す"])

        model.pickerItems = [a]
        await waitUntil { model.items.count == 1 }
        XCTAssertEqual(auto().draft(for: "a")?.items.map(\.title), ["残す"], "選択を外した写真が自動の書きかけに残った")
        model.pickerItems = []
        await waitUntil { model.items.isEmpty }
        XCTAssertNil(auto().draft(for: "a"), "全部外したのに自動の書きかけが残った")
    }

    /// 🔴 **× で確かめずに閉じる（中身が無い）ときは、この画面の書きかけ・控えを片づける。**
    /// 中身があるときは触らない。本人の下書き・ほかの画面の控えにも触らない
    func testClosingAnEmptyScreenClearsItsLeftovers() async {
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: Self.saveOK),
        ]
        let keep = model(owner: "a")
        keep.items = [photo(9, title: "本人の下書き")]
        XCTAssertTrue(keep.saveDraft())

        // ほかの画面の控え（送れなかった投稿）
        let other = model(owner: "a")
        other.items = [photo(7, title: "上がる"), photo(8, title: "ほかの控え")]
        await other.submit()
        XCTAssertEqual(journals().count, 1)

        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign, once: true),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: Self.saveOK),
        ]
        let screen = model(owner: "a")
        screen.items = [photo(1, title: "上がる"), photo(2, title: "この画面の控え")]
        await screen.submit()
        XCTAssertEqual(journals().count, 2, "前提: この画面の控えができる")

        // 中身があるうちは片づけない（確認を出す側）
        screen.closeWithoutDraft()
        XCTAssertEqual(journals().count, 2, "書きかけがあるのに控えを消した")

        // 写しから外れない形で空になった画面（片づけの漏れの受け皿）
        screen.items = []
        XCTAssertFalse(screen.hasDraft)
        screen.closeWithoutDraft()
        XCTAssertEqual(journals().map { $0.draft.items.map(\.title) }, [["ほかの控え"]],
                       "空にして閉じた画面の控えが残った・ほかの画面の控えを消した")
        XCTAssertEqual(saved().draft(for: "a")?.items.map(\.title), ["本人の下書き"], "本人の下書きを消した")

        // 自動の書きかけ
        let writing = model(owner: "a")
        writing.items = [photo(3, title: "書きかけ")]
        await writing.autoSaveDraft()
        XCTAssertNotNil(auto().draft(for: "a"))
        writing.items = []
        writing.closeWithoutDraft()
        XCTAssertNil(auto().draft(for: "a"), "空にして閉じたのに自動の書きかけが残った（次に開くと外した写真が戻る）")
    }

    /// 投稿の × の配線: 確かめずに閉じる道で片づける
    func testUploadCloseWithoutDraftIsWired() async throws {
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        let cancel = try XCTUnwrap(upload.range(of: "if model.hasDraft {"))
        XCTAssertTrue(upload[cancel.upperBound...].prefix(300).contains("model.closeWithoutDraft()"),
                      "× で確かめずに閉じる道が自動の書きかけ・控えを片づけない")
    }

    /// ストーリー: 変更なし（`.now`）で閉じる道でも自動の書きかけを消す。2つの ✕ が同じ道を通る
    func testStoryCloseWithoutChangesClearsAutoDraft() async throws {
        XCTAssertEqual(StorySimpleRules.close(.now), .closeClearingAutoDraft,
                       "写真を全部外して閉じても自動の書きかけを消さない（次に開くと外した写真が戻る）")
        XCTAssertEqual(StorySimpleRules.close(.confirm), .confirm)
        XCTAssertEqual(StorySimpleRules.close(.wait), .stay)

        let story = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertEqual(story.components(separatedBy: "switch StorySimpleRules.close(leave) {").count - 1, 2,
                       "✕ のどれかが閉じ方の決まりを通っていない")
        XCTAssertEqual(story.components(separatedBy: "case .closeClearingAutoDraft: closeWithoutChanges()").count - 1, 2)
        // 関数の中身（次の「\n    }」まで）だけを見る
        let start = try XCTUnwrap(story.range(of: "private func closeWithoutChanges() {"))
        let end = try XCTUnwrap(story.range(of: "\n    }", range: start.upperBound..<story.endIndex))
        XCTAssertTrue(story[start.upperBound..<end.lowerBound].contains("clearAutoDraft()"),
                      "変更なしで閉じる道が自動の書きかけを消さない")
    }
}
