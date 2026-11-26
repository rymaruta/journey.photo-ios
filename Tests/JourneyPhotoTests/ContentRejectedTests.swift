import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 言葉の判定の断り（`content_rejected`・2026-11-26 からサーバーが返す）。
///
/// サーバーは利用者の書いた文にひどい言葉があると、保存せずに 400 と
/// `{"error":"不適切な言葉が…","code":"content_rejected"}` を返す。アプリは
/// - 汎用の「受け付けられませんでした」ではなく、何を直せばよいか分かる文を出す（日本語・英語）
/// - 書いた文を入力欄に残す（打ち直させない）
/// - 再送の箱（ストーリー・投稿・登録の名前の控え・旅行プランの自動保存）で同じ文を送り直し続けない
@MainActor
final class ContentRejectedTests: XCTestCase {

    /// 本番のサーバーの本文（`api-user` の言葉の判定）
    private let rejectedBody = #"{"error":"不適切な言葉が含まれているため、保存できませんでした。言葉を変えてもう一度お試しください","code":"content_rejected"}"#

    private let ja = "使えない言葉が含まれています。言葉を変えてもう一度お試しください。"
    private let en = "This contains words that aren't allowed. Please change them and try again."

    override func setUp() {
        super.setUp()
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func api() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        return APIClient(baseURL: URL(string: "https://api.example.test")!,
                  tokenProvider: StubTokenProvider(token: "t"), session: session, retryPause: { _ in })
    }

    // MARK: - 見分ける（API のエラーの型）

    /// 400 と `code: content_rejected` は、どの口でも `isContentRejected` になり、決まった文を出す
    func testServerRejectionBecomesContentRejectedWithClearText() async {
        StubProtocol.respond(status: 400, body: rejectedBody)
        do {
            _ = try await SocialService(api: api()).postComment(photoId: "p1", text: "ひどい言葉")
            XCTFail("投げるはず")
        } catch {
            let apiError = error as? APIError
            XCTAssertEqual(apiError?.isContentRejected, true, "\(error)")
            XCTAssertTrue(APIError.isContentRejected(error))
            XCTAssertEqual(apiError?.description(language: "ja"), ja)
            XCTAssertEqual(apiError?.description(language: "en"), en, "英語の画面でも何を直すか分かる文")
        }
    }

    /// ほかの 400（`code` の違う断り・`code` の無い断り）は今までどおり。言葉の断りと取り違えない
    func testOtherBadRequestsAreNotContentRejected() async {
        StubProtocol.respond(status: 400, body: #"{"error":"本文が長すぎます","code":"badRequest"}"#)
        do {
            _ = try await SocialService(api: api()).postComment(photoId: "p1", text: "a")
            XCTFail("投げるはず")
        } catch {
            XCTAssertEqual((error as? APIError)?.isContentRejected, false)
            XCTAssertEqual((error as? APIError)?.description(language: "ja"), "本文が長すぎます")
        }
        XCTAssertFalse(APIError.server(status: 400, message: "").isContentRejected)
        XCTAssertFalse(APIError.server(status: 403, message: APIError.contentRejectedMessage).isContentRejected,
                       "400 以外は言葉の断りにしない")
        XCTAssertFalse(APIError.isContentRejected(nil))
    }

    // MARK: - メッセージ（DM・グループ）

    /// DM の断りも同じ文。**吹き出しにせず入力欄に戻す**（「もう一度送る」では通らない）
    func testDMRefusalReturnsToFieldWithClearText() async {
        StubProtocol.respond(status: 400, body: rejectedBody)
        do {
            _ = try await DMService(api: api()).send("a_b", text: "ひどい言葉", clientId: "c1")
            XCTFail("投げるはず")
        } catch let refused as DMService.Refused {
            XCTAssertEqual(refused.code, "content_rejected")
            XCTAssertTrue(APIError.isContentRejected(refused))
            XCTAssertTrue(DMText.returnsToField(code: refused.code), "欄に戻す")
            XCTAssertTrue(GroupText.returnsToField(code: refused.code), "グループも欄に戻す")
            XCTAssertEqual(DMText.refusal(status: 400, code: refused.code, fallback: refused.message, language: "ja"), ja)
            XCTAssertEqual(DMText.refusal(status: 400, code: refused.code, fallback: refused.message, language: "en"), en)
            XCTAssertEqual(GroupText.refusal(status: 400, code: refused.code, fallback: refused.message, language: "en"), en)
        } catch {
            XCTFail("断りの形で返るはず: \(error)")
        }
    }

    /// 欄に戻すとき、送っている間に打ち足した文も、送れなかった文も消さない
    func testReturnedTextKeepsWhatWasTypedMeanwhile() {
        XCTAssertEqual(DMUnsend.draft(current: "", returning: "ひどい言葉"), "ひどい言葉")
        XCTAssertEqual(DMUnsend.draft(current: "続き", returning: "ひどい言葉"), "続き\nひどい言葉")
    }

    // MARK: - ストーリー（再送の箱）

    private func job(_ n: UInt8, caption: String = "ひとこと", editable: Bool = true) -> StoryUploadCenter.Job {
        var job = StoryUploadCenter.Job(imageData: Data([n]), caption: caption, location: "撮影地", coords: nil,
                                        song: nil, durationSec: 5, archive: true, allowReplies: false)
        if editable {
            job.editShot = StoryDraftStore.ShotInput(imageData: Data([n, n]), fileName: "\(n).jpg",
                                                      contentType: "image/jpeg", coords: nil, overlays: [])
        }
        return job
    }

    private func settle(_ center: StoryUploadCenter) async {
        for _ in 0..<200 {
            if case .sending = center.phase { await Task.yield(); continue }
            return
        }
    }

    /// 断られたら止め、**「もう一度送る」でも送らない**（同じ文では何度送っても断られる）
    func testStoryQueueDoesNotResendRejectedText() async {
        let center = StoryUploadCenter()
        var sends = 0
        let started = center.start([job(1), job(2)], ownerId: "me", currentUserId: { "me" },
                                   send: { _, _ in
            sends += 1
            throw APIError.server(status: 400, message: APIError.contentRejectedMessage)
        })
        XCTAssertTrue(started)
        await settle(center)
        XCTAssertEqual(sends, 1)
        XCTAssertTrue(center.needsEditing)
        guard case .failed(let message, let remaining) = center.phase else { return XCTFail("\(center.phase)") }
        XCTAssertEqual(remaining, 2)
        XCTAssertEqual(message, APIError.contentRejectedText())
        center.retry()
        await settle(center)
        XCTAssertEqual(sends, 1, "言葉の判定で断られた並びを送り直した")
    }

    /// 作る画面へ戻す: 焼き込む前の1枚と、書いた文（ひとこと・撮影地）をそのまま返し、並びは空ける
    func testStoryTakeBackReturnsWrittenTextAndEmptiesQueue() async {
        let center = StoryUploadCenter()
        center.start([job(1), job(2)], ownerId: "me", currentUserId: { "me" }, draftToClear: "stamp",
                     send: { _, _ in throw APIError.server(status: 400, message: APIError.contentRejectedMessage) })
        await settle(center)
        XCTAssertTrue(center.canTakeBackForEditing)
        let back = center.takeBackForEditing()
        XCTAssertEqual(back?.shots.map(\.imageData), [Data([1, 1]), Data([2, 2])], "焼き込む前の1枚を戻す")
        XCTAssertEqual(back?.caption, "ひとこと")
        XCTAssertEqual(back?.location, "撮影地")
        XCTAssertEqual(back?.archive, true)
        XCTAssertEqual(back?.allowReplies, false)
        XCTAssertEqual(back?.draftStamp, "stamp", "1本も出ていなければ元の下書きの続きとして開く")
        XCTAssertEqual(center.phase, .idle)
        XCTAssertFalse(center.needsEditing)
    }

    /// ほかの失敗（通信など）は今までどおり送り直せる。戻す道は出さない
    func testOtherStoryFailuresStillRetry() async {
        let center = StoryUploadCenter()
        var fail = true
        var sends = 0
        center.start([job(1)], ownerId: "me", currentUserId: { "me" }, send: { _, _ in
            sends += 1
            if fail { fail = false; throw APIError.unreachable }
        })
        await settle(center)
        XCTAssertFalse(center.needsEditing)
        XCTAssertFalse(center.canTakeBackForEditing)
        XCTAssertNil(center.takeBackForEditing())
        center.retry()
        await settle(center)
        XCTAssertEqual(sends, 2)
        XCTAssertEqual(center.phase, .idle)
    }

    /// 動画の1本など、戻せる形の無い並びは戻さない（「やめる」だけ）
    func testStoryWithoutEditableShotCannotBeTakenBack() async {
        let center = StoryUploadCenter()
        center.start([job(1, editable: false)], ownerId: "me", currentUserId: { "me" },
                     send: { _, _ in throw APIError.server(status: 400, message: APIError.contentRejectedMessage) })
        await settle(center)
        XCTAssertTrue(center.needsEditing)
        XCTAssertFalse(center.canTakeBackForEditing)
    }

    // MARK: - 旅行プラン（自動保存）・名前の欄・登録の名前の控え

    /// 旅行プランの自動保存: 言葉の断りのあとは、直したら止めを外す（ほかの断りは「もう一度試す」を待つ）
    func testTripAutosaveLiftsOnlyContentRejectionOnEdit() {
        XCTAssertTrue(TripAutosave.liftsOnEdit(.failed(APIError.contentRejectedText())))
        XCTAssertFalse(TripAutosave.liftsOnEdit(.failed("通信を確かめて、もう一度お試しください。")))
        XCTAssertFalse(TripAutosave.liftsOnEdit(.conflict))
        XCTAssertFalse(TripAutosave.liftsOnEdit(.offline))
        XCTAssertFalse(TripAutosave.liftsOnEdit(nil))
    }

    /// アルバムの名前: 言葉の断りだけ、欄を開き直して理由を出す
    func testAlbumNameProblemOnlyForContentRejection() {
        XCTAssertEqual(AlbumsViewModel.nameProblem(APIError.server(status: 400, message: APIError.contentRejectedMessage)),
                       APIError.contentRejectedText())
        XCTAssertNil(AlbumsViewModel.nameProblem(APIError.unreachable))
        XCTAssertNil(AlbumsViewModel.nameProblem(APIError.server(status: 400, message: "名前が長すぎます")))
    }

    /// 登録のときに預かった名前: 言葉の断りなら控えを捨てる（ログインのたびに送り直さない）。通信の失敗は残す
    func testPendingSignUpNameIsDroppedOnlyWhenRejected() {
        XCTAssertTrue(SignInView.dropsPendingName(after: APIError.server(status: 400, message: APIError.contentRejectedMessage)))
        XCTAssertFalse(SignInView.dropsPendingName(after: APIError.unreachable))
        XCTAssertFalse(SignInView.dropsPendingName(after: APIError.server(status: 500, message: "")))
    }
}
