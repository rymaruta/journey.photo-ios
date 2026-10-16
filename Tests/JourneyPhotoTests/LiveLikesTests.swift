import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// いいねの数が、詳細画面（いまの数）と一覧（サイトを建てた時点の数）で
/// 食い違っていた件。**一覧の数をいまの数に差し替える**ところを見る。
final class LiveLikesTests: XCTestCase {

    // MARK: - 応答の読み方

    func testReadsCountsAndTreatsMissingLikesAsZero() {
        let data = Data("""
        [{"id":"a","likes":3},{"id":"b"},{"id":"c","likes":0}]
        """.utf8)
        XCTAssertEqual(LiveLikes.counts(from: data), ["a": 3, "b": 0, "c": 0])
    }

    /// 1行が壊れているだけで全部を捨てない
    func testSkipsBrokenRows() {
        let data = Data("""
        [null, {"likes":5}, {"id":"","likes":1}, {"id":"a","likes":2}]
        """.utf8)
        XCTAssertEqual(LiveLikes.counts(from: data), ["a": 2])
    }

    /// 配列でない（キャプティブポータルの HTML・エラーの JSON）なら使わない
    func testRejectsNonArray() {
        XCTAssertNil(LiveLikes.counts(from: Data("<html></html>".utf8)))
        XCTAssertNil(LiveLikes.counts(from: Data(#"{"error":"x"}"#.utf8)))
    }

    // MARK: - 写し方

    private func photo(_ id: String, likes: Int?) throws -> Photo {
        let likesJSON = likes.map { ",\"likes\":\($0)" } ?? ""
        return try JSONDecoder.api.decode(Photo.self,
            from: Data("{\"id\":\"\(id)\",\"src\":\"https://x/\(id).jpg\"\(likesJSON)}".utf8))
    }

    func testOverwritesStaleCountsAndLeavesUnknownPhotos() throws {
        let photos = [try photo("a", likes: 5), try photo("b", likes: nil), try photo("restricted", likes: 7)]
        let asOf = Date(timeIntervalSince1970: 100)
        let out = LiveLikes.apply(["a": 2, "b": 4], asOf: asOf, to: photos)
        XCTAssertEqual(out.map(\.likes), [2, 4, 7])
        XCTAssertEqual(out.map(\.likesAsOf), [asOf, asOf, nil])
    }

    /// 取り消されて 0 になった写真は、古い数を残さず 0 にする
    func testDropsToZero() throws {
        let out = LiveLikes.apply(["a": 0], asOf: Date(), to: [try photo("a", likes: 3)])
        XCTAssertEqual(out.first?.likes, 0)
    }

    // MARK: - 押した答えと一覧の、新しい方

    private func entry(_ count: Int, at seconds: TimeInterval) -> LikeCountStore.Entry {
        LikeCountStore.Entry(count: count, at: Date(timeIntervalSince1970: seconds))
    }

    /// 詳細で押して戻った（答えの方が新しい）→ 答え
    func testAnswerNewerThanListWins() throws {
        var p = try photo("a", likes: 4)
        p.likesAsOf = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(LiveLikes.base(for: p, stored: entry(5, at: 200)), 5)
    }

    /// 🔴 そのあと引き下げ更新でいまの数が取れた（一覧の方が新しい）→ 一覧。
    /// 答えを無条件に優先していた版は、ここで古い答えに止まっていた
    func testListNewerThanAnswerWins() throws {
        var p = try photo("a", likes: 7)
        p.likesAsOf = Date(timeIntervalSince1970: 300)
        XCTAssertEqual(LiveLikes.base(for: p, stored: entry(5, at: 200)), 7)
    }

    /// 🔴 押して数秒で引き下げ更新した回。要求は答えより新しいが、サーバーの
    /// 控え（Lambda の10秒）で中身は押す前の数でありうる → 答えを出す
    func testListWithinServerStalenessLosesToAnswer() throws {
        var p = try photo("a", likes: 4)
        p.likesAsOf = Date(timeIntervalSince1970: 205)
        XCTAssertEqual(LiveLikes.base(for: p, stored: entry(5, at: 200)), 5)
        p.likesAsOf = Date(timeIntervalSince1970: 200 + LiveLikes.serverStaleness)
        XCTAssertEqual(LiveLikes.base(for: p, stored: entry(5, at: 200)), 4)
    }

    /// 静的 JSON のまま（いまの数が取れていない）はどの答えより古い
    func testStaticListLosesToAnswer() throws {
        XCTAssertEqual(LiveLikes.base(for: try photo("a", likes: 9), stored: entry(5, at: 0)), 5)
        XCTAssertEqual(LiveLikes.base(for: try photo("a", likes: 9), stored: nil), 9)
    }

    // MARK: - カードに出す数

    /// 🔴 以前は「いいね済みなら一覧の数に +1」で、**一覧の数に自分のぶんが
    /// 既に入っている**写真は1つ多く出ていた。待っていない間は一覧の数そのまま
    func testDoesNotAddOwnLikeTwice() {
        XCTAssertEqual(LiveLikes.displayCount(base: 3, pendingDelta: 0), 3)
    }

    func testPendingDelta() {
        XCTAssertEqual(LiveLikes.displayCount(base: 3, pendingDelta: 1), 4)
        XCTAssertEqual(LiveLikes.displayCount(base: nil, pendingDelta: 1), 1)
        XCTAssertEqual(LiveLikes.displayCount(base: 0, pendingDelta: -1), 0)
    }

    /// ダブルタップが届かなかったら**押す前の値**に戻す。
    /// 元からいいね済みの写真を「外した」扱いにしない
    func testFailedDoubleTapRestoresPreviousState() {
        XCTAssertTrue(LiveLikes.likedAfterFailedDoubleTap(wasLiked: true))
        XCTAssertFalse(LiveLikes.likedAfterFailedDoubleTap(wasLiked: false))
    }
}

/// 公開一覧が、いいねの数だけいまの数に差し替わるか（本物の読み込みを通す）。
final class PublicGalleryLiveLikesTests: XCTestCase {

    private var session: URLSession!
    private let staticURL = URL(string: "https://site.example.test/app/data/photos.json")!
    private let liveURL = URL(string: "https://admin.example.test/photos")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func service(live: URL?, gate: Gate? = nil, snapshot: String = UUID().uuidString,
                         retryAfterFailure: TimeInterval = 10) -> PublicGalleryService {
        PublicGalleryService(url: staticURL, liveURL: live, session: session,
                             snapshot: PhotoSnapshotStore(fileName: snapshot),
                             beforeLiveRequest: gate.map { gate in { @Sendable () async in await gate.wait() } },
                             liveRetryAfterFailure: retryAfterFailure)
    }

    private let staticBody = """
    [{"id":"a","src":"https://x/a.jpg","likes":5},{"id":"b","src":"https://x/b.jpg"}]
    """

    func testUsesLiveCounts() async throws {
        // 道の照合は「含む」なので、静的 JSON の道を先に置く
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: #"[{"id":"a","likes":2},{"id":"b","likes":1}]"#)
        let photos = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(photos.map(\.likes), [2, 1])
    }

    /// いまの数が取れなくても一覧は出る（数は静的 JSON のまま）
    func testFallsBackWhenLiveFails() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        let gallery = service(live: liveURL)
        let photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a", "b"])
        XCTAssertEqual(photos.map(\.likes), [5, nil])
        // 取りに行ったうえで諦めている（一度も叩かない実装を通さない）
        XCTAssertEqual(StubProtocol.requestCount, 2)

        // 🔴 失敗した後も、控えがある間は**叩き直さない**。
        // 取れた時刻で見ていた版は、呼ぶたびに管理 API を待ってから一覧を返した
        _ = try await gallery.fetchPhotos()
        XCTAssertEqual(StubProtocol.requestCount, 2)
    }

    /// 公開範囲を絞った写真にも、いまの数の時刻が付く。付かないと
    /// 押した答えが永久に勝ち、引き下げ更新でも他の人のいいねが出ない
    func testRestrictedPhotosAreStamped() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        let gallery = service(live: nil)
        let restricted = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"r","src":"https://x/r.jpg","likes":8,"audience":"followers"}"#.utf8))
        await gallery.setRestrictedLoader { [restricted] }
        let photos = try await gallery.fetchPhotos()
        let r = try XCTUnwrap(photos.first { $0.id == "r" })
        XCTAssertEqual(r.likes, 8)
        XCTAssertNotNil(r.likesAsOf)
    }

    /// 🔴 **前の人の要求を待っている間に人が替わったら、その答えを控えに残さない。**
    /// 残すと次の人の一覧に前の人宛ての絞った写真が出ていた
    func testRestrictedAnswerFromThePreviousUserIsDropped() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        let gallery = service(live: nil)
        let restricted = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"r","src":"https://x/r.jpg","likes":8,"audience":"followers"}"#.utf8))
        await gallery.setRestrictedLoader {
            try await Task.sleep(nanoseconds: 300_000_000)
            return [restricted]
        }
        async let first = gallery.fetchPhotos()
        try await Task.sleep(nanoseconds: 100_000_000)
        // 次の人がログインした（その人に絞った写真は無い）
        await gallery.setRestrictedLoader { [] }
        let before = try await first
        XCTAssertFalse(before.contains { $0.id == "r" }, "替わったあとに前の人の答えを返している")
        let after = try await gallery.fetchPhotos()
        XCTAssertFalse(after.contains { $0.id == "r" }, "前の人の答えが控えに残っている")
    }

    /// 🔴 **取得の途中で引き下げ更新したら、自分でも取りに行く。**
    /// 途中の要求の結果で済ませていた版は、その要求が失敗していれば
    /// 利用者が引いたのに、いまの数なしで返っていた
    func testForceDuringInFlightFetchesAgain() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        // 1回目のいまの数だけ、要求の手前で止める（取りに行っている最中を作る）
        let gate = Gate(holds: 1)
        let gallery = service(live: liveURL, gate: gate)
        let first = Task { try await gallery.fetchPhotos() }
        await gate.untilWaiting()
        let forced = Task { try await gallery.fetchPhotos(force: true) }
        // 引き下げ更新が静的 JSON を取りに行き、途中の要求を待つ所まで進めてから放す。
        // ⚠️ **待つ所まで進んだことは見えない**（見る口が無い）。静的 JSON の要求は
        // 同じ呼び出しの `async let` の子より後に actor を離れるので、ふつうは
        // 子が先に待ちに入っているが、保証は下の 50ms だけ。遅れた回は直す前の
        // 形でも4回になり**偽の合格**になりうる（逆向き＝偽の失敗にはならない）
        let deadline = Date().addingTimeInterval(2)
        while StubProtocol.requestCount < 2 {
            guard Date() < deadline else { return XCTFail("引き下げ更新が静的 JSON を取りに行かない") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()
        _ = try await (first.value, forced.value)
        // 静的 JSON 2回 ＋ いまの数 2回（途中の1回に相乗りしない）
        XCTAssertEqual(StubProtocol.requestCount, 4)
    }

    // MARK: - いまの一覧で置き換える（2026-10-16 判断・Web の `usePhotos` と同じ）

    /// 🔴 **`photos.json` に無い生の行が一覧に出る。** 静的 JSON は 2026-09-28 で止まっていて、
    /// Web で見える写真（題「焚き火🔥」）が iOS に出なかった
    func testLiveRowMissingFromStaticJSONIsListed() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: """
        [{"id":"new","src":"https://x/new.jpg","title":"焚き火🔥","createdAt":"2026-10-10T00:00:00Z","likes":3},
         {"id":"a","src":"https://x/a.jpg","likes":2},
         {"id":"b","src":"https://x/b.jpg"}]
        """)
        let photos = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["new", "a", "b"], "生の行が一覧に出ていない")
        let fresh = try XCTUnwrap(photos.first)
        XCTAssertEqual(fresh.likes, 3)
        XCTAssertNotNil(fresh.likesAsOf, "生の行にいまの数の時刻が付いていない")
        // `likes` を持たない生の行は 0（一度もいいねされていない）
        XCTAssertEqual(photos.map(\.likes), [3, 2, 0])
        // 一度だけ読む（静的 JSON 1回＋ GET /photos 1回。数のために二度叩かない）
        XCTAssertEqual(StubProtocol.requestCount, 2)
    }

    /// **同じ id は生の行が正**（題・場所を直したのに静的 JSON の古い姿が出ない）
    func testSameIdPrefersLiveRow() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: """
        [{"id":"a","src":"https://x/a.jpg","location":"古い場所","likes":5}]
        """)
        StubProtocol.respond(path: "/photos", status: 200, body: """
        [{"id":"a","src":"https://x/a2.jpg","location":"新しい場所","likes":1}]
        """)
        let photos = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(photos.count, 1, "同じ id が2行になっている")
        XCTAssertEqual(photos.first?.location, "新しい場所")
        XCTAssertEqual(photos.first?.src, "https://x/a2.jpg")
        XCTAssertEqual(photos.first?.likes, 1)
    }

    /// 置き換え（Web と同じ）: **答えに無い静的 JSON の行は出さない**（サーバーで消した・非公開にした写真）。
    /// 生の行が写真として読めなかった id だけ、静的 JSON の行で埋める（1行の型違いで消さない）
    func testReplacesListAndFillsUnreadableRowsFromStatic() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: """
        [{"id":"b","likes":4},{"id":"c","src":"https://x/c.jpg"}]
        """)
        let photos = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["b", "c"], "サーバーに無い a が残っている、または b を落としている")
        XCTAssertEqual(photos.first?.likes, 4)
    }

    /// **生が失敗なら静的**（今までどおり）。空の配列でも静的（Web の「空なら維持」と同じ）
    func testFallsBackToStaticWhenLiveIsEmpty() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: "[]")
        let photos = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a", "b"])
        XCTAssertEqual(photos.map(\.likes), [5, nil])
    }

    /// 静的 JSON が取れない（端末の控えも無い）ときも、生の一覧が取れていれば出す
    func testLiveListShownWhenStaticFails() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 500, body: "{}")
        StubProtocol.respond(path: "/photos", status: 200, body: #"[{"id":"new","src":"https://x/new.jpg"}]"#)
        let photos = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["new"])
    }

    /// どちらも取れなければ今までどおり投げる（空の一覧を「写真が無い」と出さない）
    func testThrowsWhenBothFail() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 500, body: "{}")
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        do {
            _ = try await service(live: liveURL).fetchPhotos()
            XCTFail("どちらも取れないのに投げていない")
        } catch {}
    }

    /// 🔴 **合わせた後に絞り込みを必ず通す。** 生の行にもブロックした相手・通報した写真・
    /// 消した写真・`published: false` の行が混ざりうる（端末にしか無い印はサーバーでは落とせない）
    func testLiveRowsStillPassModeration() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: """
        [{"id":"ok","src":"https://x/ok.jpg","userId":"u1"},
         {"id":"blocked","src":"https://x/bl.jpg","userId":"u2"},
         {"id":"reported","src":"https://x/re.jpg","userId":"u1"},
         {"id":"gone","src":"https://x/go.jpg","userId":"u1"},
         {"id":"draft","src":"https://x/dr.jpg","userId":"u1","published":false}]
        """)
        let gallery = service(live: liveURL)
        await gallery.setHidden(ModerationSnapshot(blocked: ["u2"], reported: ["reported"], gone: ["gone"]))
        let photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["ok"], "生の行が絞り込みを通っていない")
    }

    /// 限定公開の行（`GET /feed/restricted`）は今までどおり重なる（生の行は公開ぶんだけ）
    func testRestrictedRowsStillMergeOverLiveList() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: """
        [{"id":"new","src":"https://x/new.jpg","createdAt":"2026-10-10T00:00:00Z"}]
        """)
        let gallery = service(live: liveURL)
        let restricted = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"r","src":"https://x/r.jpg","audience":"followers","createdAt":"2026-10-11T00:00:00Z"}"#.utf8))
        await gallery.setRestrictedLoader { [restricted] }
        let photos = try await gallery.fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["r", "new"])
    }

    /// 写真にできない行だけ・静的に無い id だけの答えなら、**一覧は静的に戻る**（空にしない）。
    /// 数だけは写す（`LiveLikes.list` の「1行も写真にできなかった」の guard）
    func testUnusableLiveRowsFallBackToStatic() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: #"[{"id":"x","likes":9},{"id":"a","likes":2,"src":7}]"#)
        let photos = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["a"], "答えに在る id は静的の行で埋め、答えに無い b は出さない")

        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: #"[{"id":"x","likes":9}]"#)
        let onlyUnknown = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(onlyUnknown.map(\.id), ["a", "b"], "写真にできない答えで一覧を空にしている")
        // 答えに無い写真の数は触らない（`apply` の約束）
        XCTAssertEqual(onlyUnknown.map(\.likes), [5, nil])
    }

    /// 成功 → 失敗 → 引き下げ: **失敗した回も、前に取れた生の行は残る**（止まった静的に戻さない）
    func testLiveRowsSurviveALaterFailure() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: #"[{"id":"new","src":"https://x/new.jpg"}]"#)
        let gallery = service(live: liveURL)
        let first = try await gallery.fetchPhotos()
        XCTAssertEqual(first.map(\.id), ["new"])

        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        let forced = try await gallery.fetchPhotos(force: true)
        XCTAssertEqual(StubProtocol.requestCount, 2, "引き下げで取り直していない")
        XCTAssertEqual(forced.map(\.id), ["new"], "失敗した回に生の行が消えた")
    }

    /// 同じ id が答えに2行来ても1つ（先の行）
    func testDuplicateLiveIdsCollapse() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: """
        [{"id":"n","src":"https://x/n1.jpg"},{"id":"n","src":"https://x/n2.jpg"},{"id":"a","src":"https://x/a.jpg"}]
        """)
        let photos = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["n", "a"])
        XCTAssertEqual(photos.first?.src, "https://x/n1.jpg")
    }

    /// 生の行に公開範囲を絞った写真が混ざっても出さない（静的の行でも埋めない）。
    /// 限定公開は `GET /feed/restricted` の方から重なる
    func testRestrictedLiveRowsAreDropped() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: """
        [{"id":"f","src":"https://x/f.jpg"}]
        """)
        StubProtocol.respond(path: "/photos", status: 200, body: """
        [{"id":"ok","src":"https://x/ok.jpg"},
         {"id":"f","src":"https://x/f.jpg","audience":"followers"},
         {"id":"cf","src":"https://x/cf.jpg","audience":"closeFriends"},
         {"id":"odd","src":"https://x/odd.jpg","audience":{"x":1}},
         {"id":"blank","src":"https://x/blank.jpg","audience":""}]
        """)
        let photos = try await service(live: liveURL).fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["ok", "blank"], "絞った行が生の一覧から出ている")
    }

    /// 🔴 生を4秒で諦めた（失敗した）回は、**控えの寿命を縮めて取り直す**。60秒の控えのままだと、
    /// その間は止まった静的の一覧で新しい写真が出ない。
    /// 🔴 **取り直しは裏で走り、手元に一覧があれば待たずに返す**（失敗が続く間、10秒ごとに
    /// 画面を最大4秒待たせない）。届いた答えは次の読み込みで効く。成功した後は60秒叩かない
    func testRetriesSoonAfterLiveFailure() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        // 1回目（失敗する回）は通し、2回目（取り直し）を要求の手前で止める
        let gate = Gate(holds: 1, skip: 1)
        let gallery = service(live: liveURL, gate: gate, retryAfterFailure: 0)
        let failed = try await gallery.fetchPhotos()
        XCTAssertEqual(failed.map(\.id), ["a", "b"])

        StubProtocol.reset()
        StubProtocol.respond(path: "/photos", status: 200, body: #"[{"id":"new","src":"https://x/new.jpg"}]"#)
        // 取り直しが止まっている間に返る（待っていたら、門を開けるまで返らない）。
        // 壊れた回に試験ごと固まらないよう、別の Task で読んで期限で見る
        let retriedTask = Task { try await gallery.fetchPhotos() }
        await gate.untilWaiting(2)
        guard await Self.finishes(retriedTask, within: 1) else {
            await gate.open()
            _ = try? await retriedTask.value
            return XCTFail("取り直しを待ってから返している")
        }
        let retried = try await retriedTask.value
        XCTAssertEqual(retried.map(\.id), ["a", "b"])
        // 取り直しの最中に来た読み込みも待たない
        let during = try await gallery.fetchPhotos()
        XCTAssertEqual(during.map(\.id), ["a", "b"])
        await gate.open()

        // 届いた答えは次の読み込みで効く
        let deadline = Date().addingTimeInterval(2)
        var latest = during
        while latest.map(\.id) != ["new"] {
            guard Date() < deadline else { return XCTFail("裏の取り直しの答えが効かない: \(latest.map(\.id))") }
            try await Task.sleep(nanoseconds: 5_000_000)
            latest = try await gallery.fetchPhotos()
        }
        XCTAssertEqual(StubProtocol.requestCount, 1, "取り直しを1回より多く叩いている")
        _ = try await gallery.fetchPhotos()
        XCTAssertEqual(StubProtocol.requestCount, 1, "成功した後も控えの間に叩き直している")
    }

    /// `task` が `within` 秒のうちに終わるか（終わらなくても取り消さない）
    private static func finishes(_ task: Task<[Photo], Error>, within: TimeInterval) async -> Bool {
        let done = DoneFlag()
        Task { _ = try? await task.value; await done.set() }
        let deadline = Date().addingTimeInterval(within)
        while Date() < deadline {
            let finished = await done.value
            if finished { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return await done.value
    }

    private actor DoneFlag {
        private(set) var value = false
        func set() { value = true }
    }

    /// 失敗の後でも**引き下げ更新は取り直しを待つ**（利用者が自分で引いた回に古い一覧を出さない）
    func testForceAfterFailureWaitsForLiveAnswer() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        // 1回目（失敗する回）は通し、引き下げの取り直しを要求の手前で止める
        let gate = Gate(holds: 1, skip: 1)
        let gallery = service(live: liveURL, gate: gate, retryAfterFailure: 0)
        _ = try await gallery.fetchPhotos()

        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: #"[{"id":"new","src":"https://x/new.jpg"}]"#)
        let forcedTask = Task { try await gallery.fetchPhotos(force: true) }
        await gate.untilWaiting(2)
        let returnedEarly = await Self.finishes(forcedTask, within: 0.3)
        await gate.open()
        let forced = try await forcedTask.value
        XCTAssertFalse(returnedEarly, "引き下げ更新が取り直しを待たずに返った")
        XCTAssertEqual(forced.map(\.id), ["new"], "引き下げ更新が取り直しを待っていない")
    }

    /// 🔴 **網から新しく取れた静的 JSON は、生の控えに負けない。** 生の控えはいつのものか分からない。
    /// 使うのは静的 JSON も端末の控えから出た回だけ（`testOfflineUsesStoredLiveAnswer`）
    func testFreshStaticBeatsStoredLiveAnswer() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: #"[{"id":"old","src":"https://x/old.jpg"}]"#)
        _ = try await service(live: liveURL, snapshot: name).fetchPhotos()

        // 起動し直し: 静的 JSON は網から新しく取れ、生だけ取れない
        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: #"[{"id":"z","src":"https://x/z.jpg"}]"#)
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        let photos = try await service(live: liveURL, snapshot: name).fetchPhotos()
        XCTAssertEqual(photos.map(\.id), ["z"], "網から取れた静的 JSON より生の控えを出している")
    }

    /// 🔴 **圏外では生の控えを先に使う**（なければ静的）。静的の控えだけだと、前に見えていた
    /// 新しい写真（止まった `photos.json` に無い）が圏外で消える
    func testOfflineUsesStoredLiveAnswer() async throws {
        let name = UUID().uuidString
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 200, body: #"[{"id":"new","src":"https://x/new.jpg"},{"id":"a","src":"https://x/a.jpg"}]"#)
        _ = try await service(live: liveURL, snapshot: name).fetchPhotos()

        // 起動し直して圏外（どちらの口も 500）
        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/photos.json", status: 500, body: "{}")
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        let offline = try await service(live: liveURL, snapshot: name).fetchPhotos()
        XCTAssertEqual(offline.map(\.id), ["new", "a"], "圏外で生の控えを使っていない")

        // 生の控えが無ければ静的の控え
        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        let other = UUID().uuidString
        _ = try await service(live: nil, snapshot: other).fetchPhotos()
        StubProtocol.reset()
        StubProtocol.respond(path: "/app/data/photos.json", status: 500, body: "{}")
        StubProtocol.respond(path: "/photos", status: 500, body: "{}")
        let staticOnly = try await service(live: liveURL, snapshot: other).fetchPhotos()
        XCTAssertEqual(staticOnly.map(\.id), ["a", "b"])
    }

    /// 口が設定されていなければ叩かない（既存の試験・未設定の環境）
    func testSkipsWhenNotConfigured() async throws {
        StubProtocol.respond(path: "/app/data/photos.json", status: 200, body: staticBody)
        let photos = try await service(live: nil).fetchPhotos()
        XCTAssertEqual(photos.map(\.likes), [5, nil])
        XCTAssertEqual(StubProtocol.requestCount, 1)
    }
}

/// 詳細で押した数を、ホームと検索に渡す入れ物
@MainActor
final class LikeCountStoreTests: XCTestCase {

    func testKeepsServerAnswers() async {
        let store = LikeCountStore()
        XCTAssertNil(store.entry(for: "a"))
        store.set("a", count: 5, at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(store.entry(for: "a"), LikeCountStore.Entry(count: 5, at: Date(timeIntervalSince1970: 1)))
        store.set("b", count: -1)
        XCTAssertEqual(store.entry(for: "b")?.count, 0)
    }
}
