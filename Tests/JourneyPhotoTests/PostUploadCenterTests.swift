import XCTest
@testable import JourneyPhoto
import UIKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **「投稿する」で画面を閉じ、裏で送る**（2026-11-18 owner 採用・案 B2「投稿を送る」・`PostUploadCenter`）。
///
/// 🔴 守ること:
/// - 画面（`UploadView`）を閉じても、係が画面のモデルを持って送り終える（裏の猶予 `BackgroundWindow` も取る）
/// - 失敗しても写真と文は消えない（係が持つ・送信の控えも端末に残る）。「もう一度」で送り直せる
/// - 共有カードは画面いっぱいに出さず、知らせの「カードにする」から開く
@MainActor
final class PostUploadCenterTests: XCTestCase {

    private var session: URLSession!
    private let draftDefaults = UserDefaults(suiteName: "PostUploadCenterTests.\(UUID().uuidString)")!
    private let draftDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PostUploadCenterTests-\(UUID().uuidString)", isDirectory: true)
    private var begun: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        session = URLSession(configuration: config)
        ScriptedProtocol.reset()
        begun = []
        BackgroundWindow.beginTask = { [unowned self] name, _ in
            self.begun.append(name)
            return UIBackgroundTaskIdentifier(rawValue: self.begun.count)
        }
        BackgroundWindow.endTask = { _ in }
    }

    override func tearDown() async throws {
        ScriptedProtocol.reset()
        BackgroundWindow.beginTask = { name, expired in
            UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expired)
        }
        BackgroundWindow.endTask = { UIApplication.shared.endBackgroundTask($0) }
        try? FileManager.default.removeItem(at: draftDirectory)
        try await super.tearDown()
    }

    private func api() -> APIClient {
        APIClient(baseURL: URL(string: "https://api.example.test")!,
                  tokenProvider: StubTokenProvider(token: "t"), session: session)
    }

    /// 投稿の画面が作るのと同じモデル（下書きと送信の控えの置き場つき・持ち主 "a"）
    private func model(titles: [String] = ["雲海"]) -> UploadViewModel {
        let model = UploadViewModel(uploads: UploadService(api: api(), session: session), albums: AlbumService(api: api()),
                                    photos: PhotoService(api: api()), discovery: DiscoveryService(api: api()))
        model.locationPreference = UploadLocationPreference(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        model.drafts = UploadDraftStore(defaults: draftDefaults, directory: draftDirectory)
        model.autoDrafts = UploadDraftStore(defaults: draftDefaults, directory: draftDirectory, slot: .auto)
        model.draftOwner = "a"
        model.makeDraftThumbnail = { _ in nil }
        model.groupsAsOnePost = false
        model.items = titles.enumerated().map { index, title in
            var photo = PendingPhoto(prepared: ImagePreparer.Prepared(
                data: Data(repeating: UInt8(index + 1), count: 16), fileName: "p\(index).jpg", contentType: "image/jpeg",
                exif: nil, coords: nil, takenOn: nil))
            photo.title = title
            return photo
        }
        return model
    }

    private func scriptSuccess() {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
            """),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
    }

    private func scriptFailure() {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [.init(match: "/upload/presigned-url", status: 500, body: #"{"error":"x"}"#)]
    }

    /// 係が送り終える（成功・失敗のどちらか）まで待つ
    private func waitUntilSettled(_ center: PostUploadCenter, timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if center.jobs.allSatisfy({ !$0.sending }) { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("係が送り終えない")
    }

    // MARK: - 画面を閉じても送り終える

    /// 🔴 渡したらすぐ「送信中」。画面のモデルを手放しても（画面を閉じた）、係が持って送り終え、
    /// 送っている間は裏の猶予（`photo-upload`）を取る。終わったら係からも外れる
    func testSendsAfterTheScreenIsClosed() async {
        scriptSuccess()
        let center = PostUploadCenter()
        var notices: [PostUploadCenter.Notice] = []
        center.onNotice = { notice, _ in notices.append(notice) }
        weak var released: UploadViewModel?
        do {
            let screenModel = model()
            released = screenModel
            XCTAssertTrue(center.start(screenModel), "送れる形なのに受けない")
            XCTAssertEqual(center.phase, .sending(done: 0, total: 1), "渡した瞬間に「送信中」にならない（輪が出ない）")
            XCTAssertFalse(center.start(screenModel), "同じ投稿を二度受けた")
        }
        // 画面は閉じた（ここではモデルへの参照を何も持っていない）
        XCTAssertNotNil(released, "画面を閉じたら送る途中のモデルが消えた（係が持っていない）")
        await waitUntilSettled(center)
        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.count, 1, "閉じたあとに送り終えていない")
        XCTAssertTrue(begun.contains("photo-upload"), "裏に回っても送り終える猶予を取っていない")
        XCTAssertTrue(center.jobs.isEmpty)
        XCTAssertEqual(center.phase, .idle)
        XCTAssertEqual(center.finished, 1, "送り終えた合図（輪・マイページの読み直し）が出ない")
        XCTAssertEqual(notices.count, 1)
        if case .posted = notices.first {} else { XCTFail("「投稿しました」の知らせでない: \(notices)") }
        XCTAssertNil(released, "送り終えたのにモデルを持ち続けている")
    }

    /// 共有カードは画面いっぱいに出さない（知らせの「カードにする」から開く・1.1.83 の決めを置き換え）
    func testCardIsOfferedFromTheNoticeNotAFullScreenSheet() async {
        scriptSuccess()
        let center = PostUploadCenter()
        center.onNotice = { _, _ in }
        let m = model()
        m.showsCardSheet = { true }
        XCTAssertTrue(center.start(m))
        XCTAssertFalse(m.showsCardSheet(), "係に渡したのに、共有カードを画面いっぱいに出す設定のまま")
        await waitUntilSettled(center)
        XCTAssertNil(m.postedCard, "共有カードを画面いっぱいに出した")
    }

    // MARK: - 失敗しても消えない

    /// 🔴 送れなかったら、写真と文は係が持ったまま（送信の控えも端末に残る）。「もう一度」で送り直せる
    func testFailureKeepsPhotosAndTextAndRetries() async {
        scriptFailure()
        let center = PostUploadCenter()
        var notices: [PostUploadCenter.Notice] = []
        center.onNotice = { notice, _ in notices.append(notice) }
        let m = model(titles: ["雲海", "鳥居"])
        XCTAssertTrue(center.start(m))
        await waitUntilSettled(center)
        guard case .failed? = notices.last else { return XCTFail("「送れませんでした」の知らせが無い: \(notices)") }
        guard case .failed = center.phase else { return XCTFail("輪が「送れませんでした」にならない: \(center.phase)") }
        XCTAssertEqual(center.jobs.count, 1, "送れなかった投稿を手放した")
        XCTAssertEqual(center.failedJob?.model.items.map(\.title), ["雲海", "鳥居"], "送れなかった写真と題が消えた")
        // 強制終了しても次の起動で戻せる（送信の控え）
        let journals = UploadDraftStore(defaults: draftDefaults, directory: draftDirectory).journals(for: "a")
        XCTAssertEqual(journals.first?.draft.items.map(\.title), ["雲海", "鳥居"], "送信の控えに写真と題が残っていない")
        // 係が持っている控えは、投稿の画面を開いたときに尋ねない（二重に送らない）
        let held = center.heldJournalIds
        XCTAssertEqual(held, Set(journals.map(\.id)))
        XCTAssertTrue(PostUploadCenter.askable(journals.map(\.id), held: held).isEmpty)

        // 「もう一度」
        scriptSuccess()
        center.retry()
        XCTAssertEqual(center.phase, .sending(done: 0, total: 2), "もう一度で「送信中」に戻らない")
        await waitUntilSettled(center)
        XCTAssertTrue(center.jobs.isEmpty, "送り直しても終わらない")
        XCTAssertEqual(center.finished, 1)
        if case .posted = notices.last {} else { XCTFail("送り直したあと「投稿しました」が出ない: \(notices)") }
    }

    /// 輪の「投稿の画面で直す」: 係から外して、写真と文ごと画面に渡す（画面の「投稿する」でまた係へ）
    func testTakeForEditingHandsTheSameModelBack() async {
        scriptFailure()
        let center = PostUploadCenter()
        center.onNotice = { _, _ in }
        let m = model(titles: ["雲海"])
        XCTAssertTrue(center.start(m))
        await waitUntilSettled(center)
        let back = center.takeForEditing()
        XCTAssertTrue(back === m, "別のモデルを渡した（写真と文が消える）")
        XCTAssertEqual(back?.items.map(\.title), ["雲海"])
        XCTAssertTrue(center.jobs.isEmpty)
        XCTAssertEqual(center.phase, .idle)
        scriptSuccess()
        XCTAssertTrue(center.start(m), "直したあとに係へ戻せない")
        await waitUntilSettled(center)
        XCTAssertEqual(center.finished, 1)
    }

    /// 送れる形でなければ受けない（画面は閉じない）
    func testRefusesWhenThereIsNothingToSend() async {
        let center = PostUploadCenter()
        let empty = model(titles: [])
        XCTAssertFalse(center.start(empty))
        XCTAssertTrue(center.jobs.isEmpty)
        XCTAssertEqual(center.phase, .idle)
    }

    /// 別の人が入ったら、送れずに持っている前の人の投稿を手放す（控えは前の人の枠に残る）
    func testUserChangeDropsAnotherPersonsHeldPost() async {
        scriptFailure()
        let center = PostUploadCenter()
        center.onNotice = { _, _ in }
        XCTAssertTrue(center.start(model()))
        await waitUntilSettled(center)
        center.userChanged(to: "a")
        XCTAssertEqual(center.jobs.count, 1, "同じ人なのに手放した")
        center.userChanged(to: "b")
        XCTAssertTrue(center.jobs.isEmpty, "別の人に前の人の投稿を持たせた")
    }

    // MARK: - 人が替わったら（2026-11-18 確かめ役の指摘）

    /// 🔴 送っている途中で人が替わったら、残りの写真を別の人の名前で上げない。1枚ごとに持ち主と比べて止め、
    /// 写真と文は持ったまま送れなかった投稿にする。別の人の「もう一度」では送らない。持ち主に戻れば送れる
    func testOwnerChangeMidSendStopsAndKeepsTheRest() async {
        scriptSuccess()
        let center = PostUploadCenter()
        var notices: [PostUploadCenter.Notice] = []
        center.onNotice = { notice, _ in notices.append(notice) }
        var current: String? = "a"
        center.currentUserId = { current }
        let m = model(titles: ["雲海", "鳥居"])
        // 1枚目が上がった直後に別の人がログインした
        m.onSaved = { _ in current = "b" }
        XCTAssertTrue(center.start(m))
        await waitUntilSettled(center)
        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.count, 1,
                       "人が替わったあとも残りの写真を送った（別の人の名前で上がる）")
        XCTAssertTrue(m.stoppedForOwner)
        XCTAssertEqual(center.failedJob?.model.items.map(\.title), ["鳥居"], "止めた残りの写真と題が消えた")
        XCTAssertTrue(notices.isEmpty, "別の人に前の人の投稿の知らせを出した: \(notices)")
        // 別の人の「もう一度」では送らない
        m.onSaved = nil
        center.retry()
        XCTAssertFalse(center.jobs.first?.sending ?? true, "別の人の「もう一度」で送り始めた")
        // 持ち主に戻れば送れる
        current = "a"
        center.retry()
        await waitUntilSettled(center)
        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.count, 2)
        XCTAssertTrue(center.jobs.isEmpty)
    }

    /// 🔴 本体を置いている間に人が替わったら、保存を送らない（保存の鍵は新しい人のもの）。置いた本体は残し、
    /// 持ち主に戻ったら同じ鍵で保存する（本体を置き直さない・二重にしない）
    func testOwnerChangeWhilePlacingTheBodyStopsBeforeSave() async {
        scriptSuccess()
        let m = model(titles: ["雲海"])
        // 1回目（本体を置く前の1枚ごとの確かめ）は持ち主、2回目（保存の直前）は別の人
        var checks = 0
        var ownerBack = false
        m.ownerStillSignedIn = {
            checks += 1
            return checks == 1 || ownerBack
        }
        await m.submit()
        let puts = ScriptedProtocol.calls.filter { $0.path == "/put" }.count
        XCTAssertGreaterThan(puts, 0, "本体を置いていない")
        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.count, 0,
                       "本体を置いている間に人が替わったのに、保存を送った（別の人の名前で上がる）")
        XCTAssertTrue(m.stoppedForOwner)
        XCTAssertEqual(m.items.map(\.title), ["雲海"], "止めた写真と題が消えた")
        // 持ち主に戻った: 置いた本体の鍵で保存する（置き直さない）
        ownerBack = true
        await m.submit()
        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/put" }.count, puts, "置いた本体を捨てて置き直した")
        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.count, 1)
        XCTAssertFalse(m.stoppedForOwner)
    }

    /// 🔴 「送信をやめる」は失敗ではない: 知らせは「送信をやめました」、失敗の触覚（`failures`）は鳴らさない。
    /// 輪は送れなかった投稿として残す（写真と文を持ったまま・「もう一度送る」で送れる）
    func testStoppingIsNotReportedAsAFailure() async {
        scriptSuccess()
        let center = PostUploadCenter()
        var notices: [PostUploadCenter.Notice] = []
        center.onNotice = { notice, _ in notices.append(notice) }
        let m = model(titles: ["雲海", "鳥居"])
        // 1枚目が上がった直後に輪の「送信をやめる」
        m.onSaved = { _ in center.cancelSending() }
        XCTAssertTrue(center.start(m))
        await waitUntilSettled(center)
        XCTAssertEqual(notices, [.cancelled], "やめたのに失敗の知らせを出した")
        XCTAssertEqual(center.failures, 0, "やめたのに失敗の触覚を鳴らした")
        XCTAssertEqual(center.failedJob?.failure, PostUploadOutcome.cancelledText)
        XCTAssertEqual(center.failedJob?.model.items.map(\.title), ["鳥居"], "やめた残りの写真と題が消えた")
        XCTAssertEqual(center.phase, .failed(message: PostUploadOutcome.cancelledText), "輪が送れなかった投稿として残らない")
        // もう一度送れば、ふつうに上がる（やめた印は残らない）
        m.onSaved = nil
        center.retry()
        await waitUntilSettled(center)
        guard case .posted? = notices.last else { return XCTFail("もう一度送っても上がらない: \(notices)") }
        XCTAssertTrue(center.jobs.isEmpty)
    }

    /// 持ち主の分からない投稿は受けない（別の人の「もう一度」で上がる穴をふさぐ）。いまの人でない投稿も受けない
    func testRefusesPostsWithoutTheCurrentOwner() async {
        let center = PostUploadCenter()
        center.currentUserId = { "a" }
        let noOwner = model()
        noOwner.draftOwner = nil
        XCTAssertFalse(center.start(noOwner), "持ち主の分からない投稿を受けた")
        let other = model()
        other.draftOwner = "b"
        XCTAssertFalse(center.start(other), "いまの人でない人の投稿を受けた")
        XCTAssertTrue(center.jobs.isEmpty)
    }

    /// 送っている最中に別の人が入った（`userChanged`）: 止めて手放す
    func testUserChangedWhileSendingStopsAndDrops() async {
        scriptSuccess()
        let center = PostUploadCenter()
        center.onNotice = { _, _ in }
        var current: String? = "a"
        center.currentUserId = { current }
        let m = model(titles: ["雲海", "鳥居", "滝"])
        m.onSaved = { [weak center] _ in
            current = "b"
            center?.userChanged(to: "b")
        }
        XCTAssertTrue(center.start(m))
        await waitUntilSettled(center)
        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.count, 1, "人が替わっても残りを送った")
        XCTAssertTrue(center.jobs.isEmpty, "別の人に前の人の投稿を持たせた")
    }

    /// 輪の「送信をやめる」: いまの1枚のあと残りを送らず、写真と文は持ったまま
    func testCancelSendingKeepsTheRest() async {
        scriptSuccess()
        let center = PostUploadCenter()
        center.onNotice = { _, _ in }
        let m = model(titles: ["雲海", "鳥居"])
        m.onSaved = { [weak center] _ in center?.cancelSending() }
        XCTAssertTrue(center.start(m))
        await waitUntilSettled(center)
        XCTAssertEqual(ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.count, 1, "やめたのに残りを送った")
        XCTAssertEqual(center.failedJob?.model.items.map(\.title), ["鳥居"], "やめた残りの写真と題が消えた")
    }

    /// アルバムが消えた失敗は「もう一度」では直らない。知らせは「直す」（投稿の画面へ）、輪も「もう一度送る」を出さない
    func testAlbumGoneAsksToEditInsteadOfRetry() async {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
            """),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 404, body: #"{"error":"album not found"}"#),
        ]
        let center = PostUploadCenter()
        var notices: [PostUploadCenter.Notice] = []
        center.onNotice = { notice, _ in notices.append(notice) }
        let m = model(titles: ["雲海"])
        m.selectedAlbumId = "al_gone"
        XCTAssertTrue(center.start(m))
        await waitUntilSettled(center)
        guard case .failedNeedsEditing? = notices.last else { return XCTFail("「直す」の知らせでない: \(notices)") }
        XCTAssertFalse(center.canRetry(center.failedJob), "アルバムが消えた回に「もう一度送る」を出す")
        center.requestEditing(center.failedJob!.id)
        XCTAssertNotNil(center.editRequest)
        XCTAssertEqual(PostUploadOutcome.of(didPostAll: false, remaining: 1, message: "x", needsEditing: true),
                       .failedNeedsEditing("x"))
    }

    // MARK: - 決まり

    func testOutcomeRules() async {
        XCTAssertEqual(PostUploadOutcome.of(didPostAll: true, remaining: 0, message: nil), .posted)
        XCTAssertEqual(PostUploadOutcome.of(didPostAll: false, remaining: 0, message: "曲を付けられませんでした"),
                       .postedWithNote("曲を付けられませんでした"))
        XCTAssertEqual(PostUploadOutcome.of(didPostAll: false, remaining: 2, message: "2枚目から"), .failed("2枚目から"))
        XCTAssertEqual(PostUploadOutcome.failedText, L("送れませんでした", "Couldn\u{2019}t post"))
        XCTAssertEqual(PostUploadOutcome.retryAction, L("もう一度", "Try again"))
        XCTAssertEqual(PostedCardHabit.quietText, L("投稿しました", "Posted"))
        XCTAssertEqual(PostedCardHabit.quietAction, L("カードにする", "Make a card"))
    }

    /// 輪は1つ。送っている方を先に見せ（満ちていく）、止まった方を押すと送り直す
    func testRingCombinesStoryAndPost() async {
        XCTAssertEqual(PostUploadProgress.done(uploadingIndex: 0, total: 3), 0)
        XCTAssertEqual(PostUploadProgress.done(uploadingIndex: 2, total: 3), 1)
        XCTAssertEqual(PostUploadProgress.fraction(done: 0, total: 4), 0.08, "0枚目で輪が消えて止まって見える")
        XCTAssertEqual(PostUploadProgress.fraction(done: 2, total: 4), 0.5)
        let sending = UploadRing.of(story: .idle, post: .sending(done: 1, total: 4))
        XCTAssertNil(sending.failed)
        XCTAssertEqual(sending.progress, 0.25)
        XCTAssertEqual(UploadRing.name(sending), L("送信中…", "Sending…"))
        let both = UploadRing.of(story: .sending(done: 1, total: 1), post: .failed(message: "x"))
        XCTAssertNil(both.failed, "送っている間に止まった方を先に見せた")
        XCTAssertEqual(UploadRing.of(story: .idle, post: .failed(message: "x")).failed, .post)
        XCTAssertEqual(UploadRing.of(story: .failed(message: "x", remaining: 1), post: .failed(message: "y")).failed, .story)
    }

    // MARK: - 画面の配線

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 「投稿する」は係に渡してすぐ閉じる。画面で送り終えるのを待つ道・共有カードを画面いっぱいに出す道は無い
    func testUploadScreenHandsOffAndCloses() async throws {
        let view = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(view.contains("guard PostUploadCenter.shared.start(model, onPosted: onPosted) else {"))
        XCTAssertTrue(view.contains("            return\n        }\n        dismiss()"), "渡したらすぐ閉じていない")
        XCTAssertFalse(view.contains("await model.submit()"), "画面の中で送り終えるのを待っている")
        XCTAssertFalse(view.contains(".sheet(item: $model.postedCard"), "送ったあと共有カードを画面いっぱいに出している")
        // ホームの自分の輪が進み具合を出し、止まったら直せる
        let row = try source("Features/Stories/StoriesRow.swift")
        XCTAssertTrue(row.contains("if uploads.isBusy || posts.isBusy {\n                            uploadRing(ordered.mine)"))
        XCTAssertTrue(row.contains("let ring = UploadRing.of(story: uploads.phase, post: posts.phase)"))
        XCTAssertTrue(row.contains("if let job = posts.failedJob { posts.requestEditing(job.id) }"),
                      "輪の「投稿の画面で直す」がアプリの根の口を通らない")
        // 🔴 「直す」はアプリの根（`RootView`）で受けて開く——どのタブにいても開く（2026-11-18 確かめ役の指摘:
        // ホームの輪だけが受けていて、ほかのタブで知らせの「直す」を押しても開かなかった）
        XCTAssertFalse(row.contains("posts.editRequest"), "「直す」をホームの輪だけで受けている（ほかのタブで開かない）")
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains(".onChange(of: postUploads.editRequest) { _, id in"), "「直す」をアプリの根で受けていない")
        XCTAssertTrue(root.contains("if let model = postUploads.takeForEditing(id) { editingPost = EditingPost(model: model) }"))
        // 🔴 ほかの画面が出ている間は係から外さずに待つ（札 #692: 外してからシートを出せず、投稿が消えた）
        let request = try XCTUnwrap(root.range(of: ".onChange(of: postUploads.editRequest)"))
        let body = String(root[request.lowerBound...].prefix(1400))
        let wait = try XCTUnwrap(body.range(of: "while !Task.isCancelled && (ModalProbe.isPresenting() || ModalProbe.isTransitioning())"),
                                 "「直す」でほかの画面が閉じるのを待たない")
        let take = try XCTUnwrap(body.range(of: "postUploads.takeForEditing(id)"))
        XCTAssertLessThan(wait.lowerBound, take.lowerBound, "ほかの画面が閉じる前に係から外している")
        XCTAssertTrue(root.contains("UploadView(resuming: editing.model, onSaved: { TabRouter.shared.notePosted($0) })"))
        // 知らせの口と人の入れ替わり（アプリの起動時）
        let app = try source("App/JourneyPhotoApp.swift")
        XCTAssertTrue(app.contains("PostUploadCenter.shared.configure(toasts: toasts, currentUserId: { auth.userId })"))
        XCTAssertTrue(app.contains("PostUploadCenter.shared.userChanged(to: auth.userId)"))
    }
}
