import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 「行きたい場所」をサーバー（`/user/spots`）に繋いだ（2026-09-27）。
///
/// 仕掛けは写真の保存と同じ（`LocalEdits` の印・持ち主の照合・押したら先に控えを変えて
/// 失敗したら戻す）。ここで見るのは、その仕掛けが「行きたい」でも効いているかと、
/// **端末にしか無かった分をサーバーへ上げるか**（上げずに入れ替えると消える）。
@MainActor
final class WishlistSyncTests: XCTestCase {

    private var session: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() async throws {
        StubProtocol.reset()
        try await super.tearDown()
    }

    private func service() -> SavedSpotService {
        SavedSpotService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                        tokenProvider: StubTokenProvider(token: "t"),
                                        session: session))
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    private func store(_ defaults: UserDefaults, user: String?) -> WishlistStore {
        let store = WishlistStore(defaults: defaults)
        store.use(userId: user)
        return store
    }

    /// 送り始めるまで待つ（`Task` がまだ走っていない回に先へ進まない）
    private func waitUntilSending(_ key: String, in wishlist: WishlistStore) async {
        for _ in 0..<200 where !wishlist.isSending(key) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(wishlist.isSending(key), "送り始めなかった")
    }

    /// 送った `POST /user/spots` の鍵（届いた順）
    private func postedSlugs() -> [String] {
        StubProtocol.bodies.compactMap { body in
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["slug"] as? String
        }
    }

    // MARK: - 口の形（`api-user/src/savedSpots.ts`）

    func testListReadsSlugs() async throws {
        StubProtocol.respond(status: 200, body: #"{"slugs":["パリ","SPOT-takaya"]}"#)
        let slugs = try await service().mySpots()
        XCTAssertEqual(slugs, ["パリ", "SPOT-takaya"])
        XCTAssertEqual(StubProtocol.requests, ["GET /user/spots"])
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer t")
    }

    /// 足すのは **POST** で本文 `{slug}`（PUT ではない）
    func testSaveSendsSlugInBody() async throws {
        StubProtocol.respond(status: 200, body: #"{"saved":true,"slugs":["パリ"]}"#)
        let after = try await service().save("パリ")
        XCTAssertEqual(after, ["パリ"])
        XCTAssertEqual(StubProtocol.requests, ["POST /user/spots"])
        XCTAssertEqual(postedSlugs(), ["パリ"])
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    /// 🔴 **鍵の `/` は道の区切りにしない**（`%2F` で1つの区切りに収める）。以前は符号化せずに
    /// そのまま道に入れていたので、`a/../../account` のような鍵が別の口を叩きえた
    func testUnsaveKeepsSlashesInsideOneSegment() async throws {
        StubProtocol.respond(status: 200, body: #"{"saved":false,"slugs":[]}"#)
        try await service().unsave("a/../../account")
        let url = try XCTUnwrap(StubProtocol.lastRequest?.url)
        XCTAssertTrue(url.absoluteString.hasSuffix("/user/spots/a%2F..%2F..%2Faccount"), "\(url.absoluteString)")
        XCTAssertFalse(url.absoluteString.contains("%25"), "二重に符号化している: \(url.absoluteString)")

        // ? と # と % も区切り・問い合わせにしない
        try await service().unsave("京都?x=1#y%z")
        let other = try XCTUnwrap(StubProtocol.lastRequest?.url)
        XCTAssertNil(other.query, "鍵の ? が問い合わせになった: \(other.absoluteString)")
        XCTAssertTrue(other.absoluteString.hasSuffix("%3Fx=1%23y%25z"), "\(other.absoluteString)")
    }

    /// 🔴 **日本語の鍵は、`/` を守るために先に符号化しても二重にならない。** 鍵の符号化
    /// （`pathSegment`）のあと `APIClient` がもう一度 `%` を符号化すると `%25E4…` になり、
    /// サーバーは別の鍵を外しにいく——200 が返るのに外れない
    func testUnsaveDoesNotDoubleEncodeJapaneseKeys() async throws {
        StubProtocol.respond(status: 200, body: #"{"saved":false,"slugs":[]}"#)
        try await service().unsave("京都/祇園")
        let url = try XCTUnwrap(StubProtocol.lastRequest?.url)
        XCTAssertFalse(url.absoluteString.contains("%25"), "二重に符号化している: \(url.absoluteString)")
        XCTAssertTrue(url.absoluteString.hasSuffix("/user/spots/%E4%BA%AC%E9%83%BD%2F%E7%A5%87%E5%9C%92"),
                      "\(url.absoluteString)")
        // サーバーが1回戻すと元の鍵になる（`url.path` は Linux と Apple で %2F の戻し方が違うので使わない）
        let segment = url.absoluteString.components(separatedBy: "/user/spots/").last
        XCTAssertEqual(segment?.removingPercentEncoding, "京都/祇園", "サーバーが戻す鍵が元の鍵と違う")
    }

    /// 点だけの鍵（`.`・`..`）と空の鍵は要求を出さない
    func testUnsaveRefusesDotOnlyKeys() async {
        for key in ["", ".", ".."] {
            StubProtocol.reset()
            do {
                try await service().unsave(key)
                XCTFail("投げるはず: \(key)")
            } catch {
                XCTAssertEqual(error as? APIError, .invalidIdentifier)
            }
            XCTAssertEqual(StubProtocol.requestCount, 0, "点だけの鍵で要求を出している: \(key)")
        }
    }

    /// 🔴 **外す鍵はパスに1回だけ符号化して乗る。** 二重にすると、サーバーは
    /// `%E3%83…` という別の鍵を外しにいき、200 が返るのに外れない
    func testUnsaveEncodesTheKeyOnceInThePath() async throws {
        StubProtocol.respond(status: 200, body: #"{"saved":false,"slugs":[]}"#)
        try await service().unsave("パリ")
        let url = try XCTUnwrap(StubProtocol.lastRequest?.url)
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(url.path, "/user/spots/パリ")
        XCTAssertTrue(url.absoluteString.hasSuffix("/user/spots/%E3%83%91%E3%83%AA"), "\(url.absoluteString)")
        XCTAssertFalse(url.absoluteString.contains("%25"), "二重に符号化している: \(url.absoluteString)")
    }

    /// 書き込みの失敗（500）は失敗として返る（この一覧が唯一の状態）
    func testServerFailureSurfaces() async {
        StubProtocol.respond(status: 500, body: #"{"error":"保存に失敗しました"}"#)
        do {
            try await service().save("パリ")
            XCTFail("500 を成功として返した")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 500, message: "保存に失敗しました"))
        }
    }

    /// 送れない形（200 バイト超・`#`・`/`・空）はサーバーに出さない
    func testCanSendMatchesTheServerRules() async {
        XCTAssertTrue(SavedSpotService.canSend("パリ"))
        XCTAssertTrue(SavedSpotService.canSend("SPOT-takaya"))
        XCTAssertTrue(SavedSpotService.canSend(String(repeating: "あ", count: 66)))    // 198 バイト
        XCTAssertFalse(SavedSpotService.canSend(String(repeating: "あ", count: 67)))   // 201 バイト
        XCTAssertFalse(SavedSpotService.canSend(""))
        XCTAssertFalse(SavedSpotService.canSend("a#b"))
        XCTAssertFalse(SavedSpotService.canSend("a/b"))
    }

    // MARK: - 押す（先に変え、失敗したら戻す）

    /// 🔴 **押したらすぐ変わり、送れなかったら戻して知らせる**
    func testToggleIsOptimisticAndRevertsOnFailure() async {
        let wishlist = store(defaults(), user: "u1")
        StubProtocol.respond(path: "/user/spots", status: 500, body: #"{"error":"保存に失敗しました"}"#, delay: 0.2)
        let task = Task { await WishlistSync.toggle("パリ", store: wishlist, service: service()) }
        await waitUntilSending("パリ", in: wishlist)
        XCTAssertTrue(wishlist.contains("パリ"), "答えを待たずに変わっていない")
        let outcome = await task.value
        XCTAssertFalse(wishlist.contains("パリ"), "失敗したのに「行きたい」のまま")
        XCTAssertEqual(outcome, .failed(wanted: true, message: "保存に失敗しました"))
        XCTAssertEqual(WishlistSync.notice(for: outcome)?.kind, .failure, "失敗を知らせていない")
        XCTAssertEqual(StubProtocol.requests, ["POST /user/spots"])
    }

    /// 外すのに失敗したら、入った状態に戻す
    func testRemoveRevertsOnFailure() async {
        let wishlist = store(defaults(), user: "u1")
        wishlist.set("パリ", wanted: true)
        StubProtocol.respond(status: 503, body: #"{"error":"混み合っています。もう一度お試しください"}"#)
        let outcome = await WishlistSync.set("パリ", wanted: false, store: wishlist, service: service())
        XCTAssertTrue(wishlist.contains("パリ"))
        XCTAssertEqual(outcome, .failed(wanted: false, message: "混み合っています。もう一度お試しください"))
        XCTAssertEqual(StubProtocol.requests, ["DELETE /user/spots/パリ"])
    }

    func testToggleSucceedsAgainstTheServer() async {
        let wishlist = store(defaults(), user: "u1")
        StubProtocol.respond(status: 200, body: #"{"saved":true,"slugs":["パリ"]}"#)
        let outcome = await WishlistSync.toggle("パリ", store: wishlist, service: service())
        XCTAssertEqual(outcome, .synced(wanted: true))
        XCTAssertTrue(wishlist.contains("パリ"))
        XCTAssertEqual(postedSlugs(), ["パリ"])
    }

    /// **未ログインは端末だけ**（口は 401 なので叩かない）
    func testSignedOutStaysLocal() async {
        let wishlist = store(defaults(), user: nil)
        let outcome = await WishlistSync.toggle("パリ", store: wishlist, service: service())
        XCTAssertEqual(outcome, .local(wanted: true))
        XCTAssertTrue(wishlist.contains("パリ"))
        XCTAssertEqual(StubProtocol.requestCount, 0)
    }

    /// 🔴 **送っている間に人が替わったら、失敗の巻き戻しを次の人の控えに書かない**
    func testFailureAfterUserSwitchDoesNotTouchTheNextPerson() async {
        let d = defaults()
        let wishlist = store(d, user: "a")
        StubProtocol.respond(path: "/user/spots", status: 500, body: #"{"error":"x"}"#, delay: 0.2)
        let task = Task { await WishlistSync.set("パリ", wanted: true, store: wishlist, service: service()) }
        await waitUntilSending("パリ", in: wishlist)
        wishlist.use(userId: "b")
        wishlist.set("パリ", wanted: true)   // b も同じ場所を入れていた
        _ = await task.value
        XCTAssertTrue(wishlist.contains("パリ"), "前の人の失敗で次の人の「行きたい」を外した")
    }

    // MARK: - 同期（起動・ログイン）

    /// 🔴 **取りに行っている間に押した分を、押す前の一覧で消さない**
    func testServerListDoesNotClobberAnInFlightToggle() async {
        let wishlist = store(defaults(), user: "u1")
        _ = wishlist.replace(with: [], for: "u1")        // 同期済みの人
        let mark = wishlist.syncMark
        StubProtocol.respond(path: "/user/spots", status: 200, body: #"{"saved":true,"slugs":["パリ"]}"#, delay: 0.2)
        let toggle = Task { await WishlistSync.toggle("パリ", store: wishlist, service: service()) }
        await waitUntilSending("パリ", in: wishlist)
        // 押す前に読み始めた一覧が、押した後に返ってくる
        wishlist.replace(with: ["東京"], for: "u1", since: mark)
        XCTAssertEqual(wishlist.spotIds, ["東京", "パリ"], "送っている最中の「行きたい」を一覧で消した")
        _ = await toggle.value
        XCTAssertEqual(wishlist.spotIds, ["東京", "パリ"])
    }

    /// 🔴 **前の人の一覧の答えを、次にログインした人の控えに書かない**
    func testUserSwitchDropsStaleResponse() async {
        let wishlist = store(defaults(), user: "a")
        let mark = wishlist.syncMark
        wishlist.use(userId: "b")
        wishlist.set("b の場所", wanted: true)
        // 持ち主の照合（`for:`）は通して、**印だけで**弾かれることを見る
        wishlist.replace(with: ["a の場所"], for: "b", since: mark)
        XCTAssertEqual(wishlist.spotIds, ["b の場所"], "前の人の一覧を書いている")
        // 持ち主が違う答えも書かない
        wishlist.replace(with: ["a の場所"], for: "a")
        XCTAssertEqual(wishlist.spotIds, ["b の場所"])
    }

    /// 同期の途中で人が替わった（`isCurrent` が偽）なら、一覧も送信もしない
    func testSyncForAPersonWhoLeftWritesNothing() async {
        let d = defaults()
        d.set(["パリ"], forKey: "journey-photo-wishlist:a")
        let wishlist = store(d, user: "a")
        let mark = wishlist.syncMark
        StubProtocol.respond(status: 200, body: #"{"slugs":["a の場所"]}"#)
        await WishlistSync.sync(owner: "a", since: mark, store: wishlist, service: service(),
                                isCurrent: { false })
        XCTAssertEqual(wishlist.spotIds, ["パリ"])
        XCTAssertEqual(StubProtocol.requests, ["GET /user/spots"], "いなくなった人の分を送った")
    }

    /// 🔴 **端末にしか無かった「行きたい」を、最初の同期でサーバーへ上げる**。
    /// 上げずに入れ替えると、この仕組みより前に押した場所が全部消える
    func testFirstSyncUploadsDeviceOnlyKeys() async {
        let d = defaults()
        d.set(["パリ", "SPOT-takaya", "東京"], forKey: "journey-photo-wishlist:u1")
        let wishlist = store(d, user: "u1")
        let mark = wishlist.syncMark
        StubProtocol.respond(status: 200, body: #"{"saved":true,"slugs":["東京","大阪"]}"#)
        await WishlistSync.sync(owner: "u1", since: mark, store: wishlist, service: service(),
                                isCurrent: { true })
        XCTAssertEqual(Set(postedSlugs()), ["パリ", "SPOT-takaya"], "サーバーに無い分を送っていない（東京は既に在る）")
        XCTAssertEqual(wishlist.spotIds, ["パリ", "SPOT-takaya", "東京", "大阪"])

        // 2回目からは入れ替える（Web で外した場所を端末の控えで生き返らせない）
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: #"{"slugs":["大阪"]}"#)
        await WishlistSync.sync(owner: "u1", since: wishlist.syncMark, store: wishlist, service: service(),
                                isCurrent: { true })
        XCTAssertEqual(wishlist.spotIds, ["大阪"])
        XCTAssertTrue(postedSlugs().isEmpty, "送り終えた分をまた送った")
    }

    /// **未ログインで押した分は、ログインした後の同期で送る**（同期済みの人でも）
    func testAnonymousKeysAreUploadedAfterSignIn() async {
        let d = defaults()
        let wishlist = store(d, user: "u1")
        _ = wishlist.replace(with: [], for: "u1")         // 前に同期した人
        wishlist.use(userId: nil)
        wishlist.set("京都", wanted: true)
        wishlist.use(userId: "u1")
        XCTAssertTrue(wishlist.contains("京都"))
        StubProtocol.respond(status: 200, body: #"{"slugs":[]}"#)
        await WishlistSync.sync(owner: "u1", since: wishlist.syncMark, store: wishlist, service: service(),
                                isCurrent: { true })
        XCTAssertEqual(postedSlugs(), ["京都"])
        XCTAssertTrue(wishlist.contains("京都"), "引き継いだ分をサーバーの一覧で消した")
    }

    /// 🔴 **待っている間に外したものは上げない**
    func testFirstSyncDoesNotUploadWhatWasRemovedMeanwhile() async {
        let d = defaults()
        d.set(["パリ", "京都"], forKey: "journey-photo-wishlist:u1")
        let wishlist = store(d, user: "u1")
        let mark = wishlist.syncMark
        wishlist.set("パリ", wanted: false)      // 一覧を待っている間に外した
        StubProtocol.respond(status: 200, body: #"{"slugs":[]}"#)
        await WishlistSync.sync(owner: "u1", since: mark, store: wishlist, service: service(),
                                isCurrent: { true })
        XCTAssertEqual(postedSlugs(), ["京都"])
        XCTAssertEqual(wishlist.spotIds, ["京都"])

        // 未送信のまま外したものも、次の同期で生き返らない
        let toSend = wishlist.replace(with: [], for: "u1")
        XCTAssertTrue(toSend.isEmpty)
    }

    /// 🔴 **1件ずつ送っている間に外したものは、その後も送らない**
    func testUploadSkipsWhatWasRemovedDuringEarlierUploads() async {
        let d = defaults()
        d.set(["a-場所", "b-場所"], forKey: "journey-photo-wishlist:u1")
        let wishlist = store(d, user: "u1")
        StubProtocol.respond(path: "/user/spots", status: 200, body: #"{"slugs":[]}"#, delay: 0.1)
        let sync = Task {
            await WishlistSync.sync(owner: "u1", since: wishlist.syncMark, store: wishlist, service: service(),
                                    isCurrent: { true })
        }
        await waitUntilSending("a-場所", in: wishlist)     // 1件目を送っている最中
        _ = await WishlistSync.set("b-場所", wanted: false, store: wishlist, service: service())
        await sync.value
        XCTAssertEqual(postedSlugs(), ["a-場所"], "外した場所を後から送った")
        XCTAssertEqual(wishlist.spotIds, ["a-場所"])
    }

    /// 送れなかった分は端末に残し、次の同期で送り直す
    func testFailedUploadIsRetriedNextSync() async {
        let d = defaults()
        d.set(["パリ"], forKey: "journey-photo-wishlist:u1")
        let wishlist = store(d, user: "u1")
        StubProtocol.respondInOrder([(200, #"{"slugs":[]}"#), (500, #"{"error":"x"}"#)])
        await WishlistSync.sync(owner: "u1", since: wishlist.syncMark, store: wishlist, service: service(),
                                isCurrent: { true })
        XCTAssertTrue(wishlist.contains("パリ"), "送れなかった分を消した")

        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: #"{"slugs":[]}"#)
        await WishlistSync.sync(owner: "u1", since: wishlist.syncMark, store: wishlist, service: service(),
                                isCurrent: { true })
        XCTAssertEqual(postedSlugs(), ["パリ"], "送り直していない")
    }

    /// **送れない形（200 バイト超）は送らずに端末に残す**（400 を毎回踏まない・消さない）
    func testOversizedKeyStaysLocalWithoutUpload() async {
        let long = String(repeating: "あ", count: 70)    // 210 バイト（切り詰め前の端末に残りうる）
        let d = defaults()
        d.set([long], forKey: "journey-photo-wishlist:u1")
        let wishlist = store(d, user: "u1")
        StubProtocol.respond(status: 200, body: #"{"slugs":[]}"#)
        await WishlistSync.sync(owner: "u1", since: wishlist.syncMark, store: wishlist, service: service(),
                                isCurrent: { true })
        XCTAssertEqual(StubProtocol.requests, ["GET /user/spots"])
        XCTAssertTrue(wishlist.contains(long))
        // 2回目の入れ替えでも消さない
        wishlist.replace(with: [], for: "u1", since: wishlist.syncMark)
        XCTAssertTrue(wishlist.contains(long))
        // **外すときは送る**（サーバーは外すときに長さを見ない——サーバーにある昔の長い
        // 鍵を外せるように。端末にしか無い鍵なら、サーバーでは何も起きない）
        let outcome = await WishlistSync.set(long, wanted: false, store: wishlist, service: service())
        XCTAssertEqual(outcome, .local(wanted: false), "未送信の鍵は端末で外して済ませる")
        XCTAssertFalse(wishlist.contains(long))
    }

    /// 退会の片づけは未送信の印も消す（`AccountLocalData`）
    func testRemoveDataClearsUnsentMarks() async {
        let d = defaults()
        d.set(["パリ"], forKey: "journey-photo-wishlist:gone")
        let wishlist = store(d, user: "gone")
        _ = wishlist.replace(with: [], for: "gone")
        XCTAssertNotNil(d.object(forKey: "journey-photo-wishlist-unsent:gone"))
        AccountLocalData.remove(userId: "gone", username: nil, defaults: d)
        XCTAssertNil(d.object(forKey: "journey-photo-wishlist:gone"))
        XCTAssertNil(d.object(forKey: "journey-photo-wishlist-unsent:gone"))
    }

    // MARK: - 7d2b59e のレビュー

    /// 🔴 **押して届いた鍵は未送信から外す。** 最初の同期の間に押すと未送信に入ったまま残り、
    /// その後 Web で外すと、次の同期で「サーバーに無い未送信」として生き返った
    func testPressedKeyThatReachedTheServerIsNotUploadedAgain() async {
        let wishlist = store(defaults(), user: "u1")
        wishlist.set("パリ", wanted: true)
        // 最初の同期の入れ替えで、サーバーに無い「パリ」が未送信に入る
        _ = wishlist.replace(with: [], for: "u1")
        XCTAssertTrue(wishlist.isUnsent("パリ", for: "u1"), "前提: 未送信に入っている")
        StubProtocol.respond(status: 200, body: #"{"saved":true,"slugs":["パリ"]}"#)
        _ = await WishlistSync.set("パリ", wanted: true, store: wishlist, service: service())
        XCTAssertFalse(wishlist.isUnsent("パリ", for: "u1"), "届いたのに未送信のまま")
        // Web で外された後の同期で、送り直して生き返らせない
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: #"{"slugs":[]}"#)
        await WishlistSync.sync(owner: "u1", since: wishlist.syncMark, store: wishlist, service: service(),
                                isCurrent: { true })
        XCTAssertEqual(postedSlugs(), [], "Web で外した場所を送り直して生き返らせた")
        XCTAssertFalse(wishlist.contains("パリ"))
    }

    /// **サーバーにある長い鍵も外せる**（外すときはサーバーも長さを見ない）
    func testLongKeyCanBeRemoved() async {
        let long = String(repeating: "あ", count: 70)    // 210 バイト
        XCTAssertFalse(SavedSpotService.canSend(long))
        XCTAssertTrue(SavedSpotService.canRemove(long))
        XCTAssertFalse(SavedSpotService.canRemove(".."), "パスで畳まれて別の口に届く")
        XCTAssertFalse(SavedSpotService.canSend("."))
        let wishlist = store(defaults(), user: "u1")
        _ = wishlist.replace(with: [long], for: "u1")
        StubProtocol.respond(status: 200, body: #"{"saved":false,"slugs":[]}"#)
        let outcome = await WishlistSync.set(long, wanted: false, store: wishlist, service: service())
        XCTAssertEqual(outcome, .synced(wanted: false), "サーバーに外す要求を送っていない")
        XCTAssertEqual(StubProtocol.requestCount, 1)
    }

    /// **未送信の鍵は、圏外でも外せる**（直前の同期でサーバーに無かった鍵）。答えを待って
    /// 戻していたので「外せませんでした」になり、取り消しでは次の同期で送り直されていた
    func testUnsentKeyIsRemovedEvenWhenTheServerFails() async {
        let wishlist = store(defaults(), user: "u1")
        wishlist.set("京都", wanted: true)
        _ = wishlist.replace(with: [], for: "u1")
        XCTAssertTrue(wishlist.isUnsent("京都", for: "u1"), "前提: 未送信")
        StubProtocol.respond(status: 500, body: #"{"error":"x"}"#)
        let outcome = await WishlistSync.set("京都", wanted: false, store: wishlist, service: service())
        XCTAssertEqual(outcome, .removedOnThisDevice, "届かなかったのに黙って「外しました」とだけ言う")
        XCTAssertEqual(WishlistSync.removalNotice(for: outcome)?.kind, .failure,
                       "マイページの外すボタンが黙る（知らせは失敗のときだけ出していた）")
        XCTAssertNil(WishlistSync.removalNotice(for: .local(wanted: false)), "成功を一覧で言う")
        XCTAssertFalse(wishlist.contains("京都"), "圏外で外せない")
        XCTAssertEqual(StubProtocol.requests.last, "DELETE /user/spots/京都", "外す要求を送っていない")
        // 次の同期でも送らない・戻らない
        StubProtocol.reset()
        StubProtocol.respond(status: 200, body: #"{"slugs":[]}"#)
        await WishlistSync.sync(owner: "u1", since: wishlist.syncMark, store: wishlist, service: service(),
                                isCurrent: { true })
        XCTAssertEqual(postedSlugs(), [])
        XCTAssertFalse(wishlist.contains("京都"))
    }
}
