import XCTest
import CoreBluetooth
@testable import JourneyPhoto
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
        var whileSaving: UploadDraftStore.Draft?
        let peek = auto()
        model.onSaved = { _ in
            if whileSaving == nil { whileSaving = peek.draft(for: "a") }
        }
        await model.submit()
        XCTAssertEqual(whileSaving?.sending, true, "送り始める前に控えを書いていない（落ちたら写真が消える）")
        XCTAssertEqual(whileSaving?.items.map(\.title), ["1枚目", "2枚目"], "まだ送っていない写真が控えに無い")
        XCTAssertEqual(whileSaving?.items.first?.inFlight, true, "送っている1枚に印が無い")
        XCTAssertNil(whileSaving?.items.last?.inFlight)
        XCTAssertTrue(model.didPostAll, "前提: 全部上がった")
        XCTAssertNil(auto().draft(for: "a"), "全部送れたのに控えが残った（次に開いて二重に尋ねる）")
        XCTAssertNil(saved().draft(for: "a"), "本人の下書きの枠に書いた")
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
        let left = auto().draft(for: "a")
        XCTAssertEqual(left?.items.map(\.title), ["届かない"], "送れなかった写真が控えに無い・上がった写真が残った")
        XCTAssertNil(left?.items.first?.inFlight)

        // 次の起動（アプリが終了されていた）
        let notice = UploadDraftRules.interruptedNotice(left)
        XCTAssertEqual(notice?.canResume, true, "送れなかった投稿を知らせない")
        XCTAssertTrue(notice?.message.contains(L("1 枚", "1 photo")) == true, notice?.message ?? "")

        let next = model(owner: "a")
        XCTAssertNotNil(next.storedAutoDraft)
        let restored = await next.restoreDraft(from: .auto)
        XCTAssertTrue(restored)
        XCTAssertEqual(next.items.map(\.title), ["届かない"])
        XCTAssertFalse(next.restoredDraft, "自動の枠を本人の下書きとして扱った（閉じる確認の言い方がずれる）")
    }

    /// 送っている途中だった（届いたか分からない）写真だけなら「続きから」は出さず、確かめるよう言う
    func testInterruptedNoticeForUnsureOnly() async {
        let unsure = UploadDraftStore.Item(imageFile: "x", fileName: "a.jpg", contentType: "image/jpeg",
                                           title: "", caption: "", location: "", locationClearedByUser: false,
                                           key: "k", inFlight: true)
        var draft = UploadDraftStore.Draft(items: [unsure], tagsText: "", category: "", published: true,
                                           audience: "everyone", groupsAsOnePost: false, savedAt: "")
        XCTAssertNil(UploadDraftRules.interruptedNotice(draft), "自動の書きかけ（送信の控えでない）を知らせた")
        draft.sending = true
        XCTAssertEqual(UploadDraftRules.interruptedNotice(draft)?.canResume, false)
        XCTAssertNil(UploadDraftRules.interruptedNotice(nil))
    }

    /// 起動のあとに知らせる配線
    func testRootViewAnnouncesInterruptedUpload() async throws {
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains(".task(id: auth.userId) { await offerInterruptedUpload() }"))
        XCTAssertTrue(root.contains("UploadDraftRules.interruptedNotice("))
        XCTAssertTrue(root.contains("UploadDraftStore(slot: .auto).draft(for: userId)"))
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
        XCTAssertNil(auto().draft(for: "a")?.sending, "自動の書きかけを送信の控えにした（起動で知らせてしまう）")
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
        XCTAssertTrue(upload.contains("if phase == .background { Task { await model.autoSaveDraft() } }"), "投稿: 裏に回っても書かない")
        XCTAssertTrue(upload.contains("model.autoDrafts = autoStore"))
        XCTAssertTrue(upload.contains("Button(L(\"続きから\", \"Continue\")) { restoreDraft(from: .auto) }"))
        XCTAssertTrue(upload.contains("model.discardAutoDraft()"), "投稿をやめても自動の書きかけが残る")

        let story = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(story.contains("if phase == .background { Task { await autoSaveDraft() } }"), "ストーリー: 裏に回っても書かない")
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
        XCTAssertEqual(auto().draft(for: "a")?.items.map(\.title), ["続きから"], "前提")

        // 次の起動: 自動の枠の「続きから」で送る
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: Self.presign),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: Self.saveOK),
        ]
        let resumed = model(owner: "a")
        let restoredAuto = await resumed.restoreDraft(from: .auto)
        XCTAssertTrue(restoredAuto)
        await resumed.submit()
        XCTAssertTrue(resumed.didPostAll, "前提: 上がった")
        XCTAssertNil(saved().draft(for: "a"), "続きから送った写真が本人の下書きに残った（次にもう一度投稿される）")
        XCTAssertNil(auto().draft(for: "a"))
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
        let withContent = R.openAction(hasAutoDraft: true, hasSavedDraft: false, opensWithContent: true,
                                       alreadyAsked: false, resumesAuto: false)
        XCTAssertEqual(withContent, .none)
        XCTAssertFalse(R.ownsAutoSlot(hasAutoDraft: true, action: withContent),
                       "尋ねていない自動の書きかけを上書き・削除する")
        XCTAssertTrue(R.ownsAutoSlot(hasAutoDraft: false, action: .none), "開いたとき空なら使ってよい")
        XCTAssertEqual(R.openAction(hasAutoDraft: true, hasSavedDraft: true, opensWithContent: false,
                                    alreadyAsked: false, resumesAuto: false), .askAuto)
        XCTAssertTrue(R.ownsAutoSlot(hasAutoDraft: true, action: .askAuto))
        XCTAssertEqual(R.openAction(hasAutoDraft: false, hasSavedDraft: true, opensWithContent: false,
                                    alreadyAsked: false, resumesAuto: false), .askSaved)
        XCTAssertEqual(R.openAction(hasAutoDraft: true, hasSavedDraft: true, opensWithContent: false,
                                    alreadyAsked: true, resumesAuto: false), .none)
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
        let left = auto().draft(for: "a")
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
        XCTAssertTrue(model.contains("BackgroundWindow(name: \"upload-autosave\")"), "裏に回ったときの書き込みを守っていない")
        let story = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(story.contains("await autoDrafts.saveInBackground("))
        XCTAssertTrue(story.contains("BackgroundWindow(name: \"story-autosave\")"))
    }

    /// 🔴 [7] 起動のときの知らせで「続きから」を押して来たら、投稿の画面で尋ね直さずに戻す
    func testResumeFromLaunchNoticeDoesNotAskAgain() async throws {
        XCTAssertEqual(UploadDraftRules.openAction(hasAutoDraft: true, hasSavedDraft: true, opensWithContent: false,
                                                   alreadyAsked: false, resumesAuto: true), .resumeAuto)
        XCTAssertEqual(UploadDraftRules.openAction(hasAutoDraft: false, hasSavedDraft: true, opensWithContent: false,
                                                   alreadyAsked: false, resumesAuto: true), .askSaved)
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains("resumesAutoDraft: resumeInterruptedUpload"))
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("case .resumeAuto: restoreDraft(from: .auto)"))
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
        XCTAssertEqual(auto().draft(for: "a")?.groupId, group, "束の印を控えに持っていない")
        let next = model(owner: "a")
        let restored = await next.restoreDraft(from: .auto)
        XCTAssertTrue(restored)
        XCTAssertEqual(next.groupId, group, "続きから送ると別の投稿に割れる")
    }
}
