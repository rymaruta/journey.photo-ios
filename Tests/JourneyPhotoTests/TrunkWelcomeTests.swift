import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 旅のトランクの「はじめての硬貨」（2026-10-18 owner 承認）。
/// 呼ぶ条件・granted の扱い・失敗で印を残さない・同じ起動中は1回・案内の数・順番・硬貨の数の読み直し
@MainActor
final class TrunkWelcomeTests: XCTestCase {

    private lazy var suite = "TrunkWelcomeTests.\(UUID().uuidString)"
    private lazy var defaults: UserDefaults = {
        let d = UserDefaults(suiteName: suite)!
        let name = suite
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return d
    }()
    private lazy var center = NotificationCenter()
    private lazy var session: URLSession = {
        ScriptedProtocol.reset()
        addTeardownBlock { ScriptedProtocol.reset() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        return URLSession(configuration: config)
    }()

    private func gate() -> TrunkWelcome { TrunkWelcome(defaults: defaults, center: center) }

    private struct Boom: Error {}

    /// 呼んだ回数を数える口
    private final class Counter {
        var calls = 0
    }

    // MARK: 呼ぶ条件

    func testCallsOnlyWhenSignedInAndTrunkAvailable() async {
        let welcome = gate()
        let counter = Counter()
        let ok = { () async throws -> TrunkWelcomeResult in
            counter.calls += 1
            return TrunkWelcomeResult(granted: false, added: 0, coins: 3)
        }
        XCTAssertFalse(welcome.shouldClaim(userId: nil, available: true), "入っていないのに呼ぶ")
        XCTAssertFalse(welcome.shouldClaim(userId: "", available: true))
        XCTAssertFalse(welcome.shouldClaim(userId: "u1", available: false), "トランクが使えないのに呼ぶ")
        _ = await welcome.claim(userId: nil, available: true, call: ok)
        _ = await welcome.claim(userId: "u1", available: false, call: ok)
        XCTAssertEqual(counter.calls, 0)
        XCTAssertFalse(welcome.isDone("u1"), "呼んでいないのに印を残した")
        XCTAssertTrue(welcome.shouldClaim(userId: "u1", available: true))
        _ = await welcome.claim(userId: "u1", available: true, call: ok)
        XCTAssertEqual(counter.calls, 1)
    }

    /// granted=false（既に配った・対象外）: 案内は出さず、その人では以後呼ばない（次の起動でも）
    func testNotGrantedMarksDoneAndStaysQuiet() async {
        let welcome = gate()
        var posted = 0
        let token = center.addObserver(forName: .trunkCoinsChanged, object: nil, queue: nil) { _ in posted += 1 }
        defer { center.removeObserver(token) }
        let grant = await welcome.claim(userId: "u1", available: true) {
            TrunkWelcomeResult(granted: false, added: 0, coins: 5)
        }
        XCTAssertNil(grant)
        XCTAssertFalse(welcome.hasPending, "配っていないのに案内を出す")
        XCTAssertEqual(welcome.requests, 0)
        XCTAssertEqual(posted, 0, "配っていないのに硬貨の読み直しを頼んだ")
        XCTAssertTrue(welcome.isDone("u1"), "granted=false で印を残していない")
        // 次の起動（新しい係・同じ端末の覚え）でも呼ばない
        XCTAssertFalse(gate().shouldClaim(userId: "u1", available: true), "次の起動でまた呼ぶ")
        // 印は人ごと
        XCTAssertTrue(gate().shouldClaim(userId: "u2", available: true), "別の人まで呼ばなくなった")
    }

    /// granted=true: 案内を1回出す・印を残す・硬貨の数の読み直しを頼む（増えたあとの数を添える）
    func testGrantedPresentsOnceAndNotifiesCoins() async {
        let welcome = gate()
        var coins: [Int] = []
        let token = center.addObserver(forName: .trunkCoinsChanged, object: nil, queue: nil) { note in
            if let n = note.userInfo?["coins"] as? Int { coins.append(n) }
        }
        defer { center.removeObserver(token) }
        let grant = await welcome.claim(userId: "u1", available: true) {
            TrunkWelcomeResult(granted: true, added: 10, coins: 12)
        }
        XCTAssertEqual(grant, TrunkWelcome.Grant(added: 10, coins: 12))
        XCTAssertEqual(welcome.requests, 1)
        XCTAssertTrue(welcome.isDone("u1"))
        XCTAssertEqual(coins, [12], "硬貨の数を見せている画面に知らせていない")
        XCTAssertEqual(welcome.consume(), TrunkWelcome.Grant(added: 10, coins: 12))
        XCTAssertNil(welcome.consume(), "案内を二度出す")
        XCTAssertFalse(welcome.shouldClaim(userId: "u1", available: true), "配ったあとにまた呼ぶ")
    }

    /// 古いサーバー（口が無い 404）・圏外・500: 印を残さない。同じ起動中は呼び直さず、次に開いたとき（次の起動）にまた呼ぶ
    func testFailureLeavesNoMarkAndRetriesNextLaunchOnly() async {
        let welcome = gate()
        let counter = Counter()
        for error in [APIError.server(status: 404, message: ""), APIError.unreachable, APIError.server(status: 500, message: "x")] as [Error] {
            let fresh = gate()
            let grant = await fresh.claim(userId: "u-\(counter.calls)", available: true) {
                counter.calls += 1
                throw error
            }
            XCTAssertNil(grant)
            XCTAssertFalse(fresh.isDone("u-\(counter.calls - 1)"), "\(error) で印を残した")
            XCTAssertFalse(fresh.hasPending)
        }
        counter.calls = 0
        _ = await welcome.claim(userId: "u1", available: true) { counter.calls += 1; throw Boom() }
        _ = await welcome.claim(userId: "u1", available: true) { counter.calls += 1; throw Boom() }
        XCTAssertEqual(counter.calls, 1, "同じ起動中に何度も呼んだ")
        XCTAssertFalse(welcome.isDone("u1"))
        // 次の起動
        let nextLaunch = gate()
        XCTAssertTrue(nextLaunch.shouldClaim(userId: "u1", available: true), "失敗のあと、次に開いても呼ばない")
        let grant = await nextLaunch.claim(userId: "u1", available: true) {
            counter.calls += 1
            return TrunkWelcomeResult(granted: true, added: 10, coins: 10)
        }
        XCTAssertEqual(counter.calls, 2)
        XCTAssertEqual(grant?.added, 10)
    }

    /// 同じ起動中は、答えをもらっても・同時に2本呼ばれても1回だけ
    func testCalledOncePerLaunchEvenWhenOverlapping() async {
        let welcome = gate()
        let counter = Counter()
        async let a: TrunkWelcome.Grant? = welcome.claim(userId: "u1", available: true) {
            counter.calls += 1
            try await Task.sleep(nanoseconds: 50_000_000)
            return TrunkWelcomeResult(granted: true, added: 10, coins: 10)
        }
        async let b: TrunkWelcome.Grant? = welcome.claim(userId: "u1", available: true) {
            counter.calls += 1
            return TrunkWelcomeResult(granted: true, added: 10, coins: 10)
        }
        let results = await [a, b]
        XCTAssertEqual(counter.calls, 1, "同じ起動中に2本呼んだ")
        XCTAssertEqual(results.compactMap { $0 }.count, 1)
        XCTAssertEqual(welcome.requests, 1)
    }

    /// 取り消し（人が替わった・画面が消えた）は呼んだうちに数えない（同じ起動中にもう一度呼べる）
    func testCancellationDoesNotCountAsTried() async {
        let welcome = gate()
        _ = await welcome.claim(userId: "u1", available: true) { throw CancellationError() }
        XCTAssertFalse(welcome.isDone("u1"))
        XCTAssertTrue(welcome.shouldClaim(userId: "u1", available: true))
    }

    /// 待つ間に人が替わった: 印は呼んだ人に残すが、次の人に前の人の案内を出さない
    func testUserSwitchWhileWaitingDropsTheNotice() async {
        let welcome = gate()
        let grant = await welcome.claim(userId: "u1", available: true) {
            welcome.noteUser("u2")
            return TrunkWelcomeResult(granted: true, added: 10, coins: 10)
        }
        XCTAssertNil(grant)
        XCTAssertFalse(welcome.hasPending, "次の人に前の人の案内を出す")
        XCTAssertTrue(welcome.isDone("u1"))
        // ログアウトで出す前の案内を下ろす
        _ = await welcome.claim(userId: "u3", available: true) { TrunkWelcomeResult(granted: true, added: 10, coins: 10) }
        XCTAssertTrue(welcome.hasPending)
        welcome.noteUser(nil)
        XCTAssertFalse(welcome.hasPending, "ログアウトしても案内が残る")
    }

    /// 上限 99 に当たって 1 枚も増えなかった回は、配った扱いでも案内を出さない（「+0 枚」を見せない）
    func testGrantedButZeroAddedShowsNothing() async {
        let welcome = gate()
        let grant = await welcome.claim(userId: "u1", available: true) { TrunkWelcomeResult(granted: true, added: 0, coins: 99) }
        XCTAssertNil(grant)
        XCTAssertFalse(welcome.hasPending)
        XCTAssertTrue(welcome.isDone("u1"))
    }

    /// 退会で印を消す（`AccountLocalData.remove`）
    func testRemoveData() async {
        let welcome = gate()
        _ = await welcome.claim(userId: "u1", available: true) { TrunkWelcomeResult(granted: false, added: 0, coins: 0) }
        XCTAssertTrue(welcome.isDone("u1"))
        TrunkWelcome.removeData(for: "u1", defaults: defaults)
        XCTAssertFalse(welcome.isDone("u1"))
        // まだ出していない案内の控えも消す
        _ = await welcome.claim(userId: "u2", available: true) { TrunkWelcomeResult(granted: true, added: 10, coins: 10) }
        XCTAssertNotNil(welcome.storedGrant("u2"))
        TrunkWelcome.removeData(for: "u2", defaults: defaults)
        XCTAssertNil(welcome.storedGrant("u2"), "退会しても案内の控えが残る")
    }

    // MARK: 出せなかった案内の控え（2026-10-18 の見直し）

    /// 応答のあとに待ちが切れた・アプリが終わった・落ちた: 次の起動で、サーバーを呼ばずに一度だけ出す
    func testUnshownNoticeComesBackNextLaunchOnce() async {
        let counter = Counter()
        let first = gate()
        _ = await first.claim(userId: "u1", available: true) {
            counter.calls += 1
            return TrunkWelcomeResult(granted: true, added: 10, coins: 12)
        }
        XCTAssertTrue(first.hasPending)
        // ここで出さずに終わった（consume していない）。次の起動
        let second = gate()
        XCTAssertFalse(second.shouldClaim(userId: "u1", available: true), "二重に配られる（呼ぶ印が無い）")
        XCTAssertTrue(second.restore(userId: "u1"), "出せなかった案内が次の起動で戻らない")
        XCTAssertEqual(second.requests, 1)
        XCTAssertEqual(second.consume(), TrunkWelcome.Grant(added: 10, coins: 12))
        XCTAssertEqual(counter.calls, 1, "戻すのにサーバーを呼んだ")
        // 受け取っただけ（全画面がまだ出ていない）では控えを消さない
        XCTAssertEqual(gate().storedGrant("u1"), TrunkWelcome.Grant(added: 10, coins: 12), "出る前に控えを消した")
        // 実際に出た（`TrunkWelcomeView` の onAppear）ら控えを消す: その次の起動ではもう出ない
        second.noteShown(userId: "u1")
        let third = gate()
        XCTAssertFalse(third.restore(userId: "u1"), "出した案内がまた出る")
        XCTAssertFalse(third.hasPending)
        // 同じ起動の中で restore を何度呼んでも二重に積まない
        let fourth = gate()
        _ = await fourth.claim(userId: "u9", available: true) { TrunkWelcomeResult(granted: true, added: 4, coins: 99) }
        XCTAssertFalse(fourth.restore(userId: "u9"), "出す待ちに二重に積んだ")
        XCTAssertEqual(fourth.requests, 1)
        XCTAssertEqual(fourth.storedGrant("u9"), TrunkWelcome.Grant(added: 4, coins: 99), "上限に当たった枚数を控えていない")
    }

    /// 出そうとした全画面が出なかった（同じ瞬間に別のシートが出始めた）: 控えは残り、出す待ちへ戻る（2026-10-18 の見直し）
    func testPresentationThatNeverAppearedIsRequeued() async {
        let welcome = gate()
        _ = await welcome.claim(userId: "u1", available: true) { TrunkWelcomeResult(granted: true, added: 10, coins: 10) }
        let grant = try? XCTUnwrap(welcome.consume())
        XCTAssertFalse(welcome.hasPending)
        welcome.requeue(TrunkWelcome.Grant(added: 10, coins: 10), userId: "u1")
        XCTAssertTrue(welcome.hasPending, "出なかった案内が待ちへ戻らない")
        XCTAssertEqual(welcome.consume(), grant)
        XCTAssertNotNil(welcome.storedGrant("u1"), "出ていないのに控えが消えた")
        // 別の人には戻さない
        welcome.noteUser("u2")
        welcome.requeue(TrunkWelcome.Grant(added: 10, coins: 10), userId: "u1")
        XCTAssertFalse(welcome.hasPending, "別の人の待ちに前の人の案内を戻した")
        // 出たら消える
        welcome.noteShown(userId: "u1")
        XCTAssertNil(welcome.storedGrant("u1"))
        welcome.noteShown(userId: nil)
    }

    /// 待つ間に人が替わった: いまの人には出さず知らせも流さない。配った人が次に開いたときに出す
    func testSwitchedUserGetsNoNoticeButOwnerSeesItLater() async {
        let welcome = gate()
        var notes: [[AnyHashable: Any]] = []
        let token = center.addObserver(forName: .trunkCoinsChanged, object: nil, queue: nil) { note in
            notes.append(note.userInfo ?? [:])
        }
        defer { center.removeObserver(token) }
        _ = await welcome.claim(userId: "A", available: true) {
            welcome.noteUser("B")
            return TrunkWelcomeResult(granted: true, added: 10, coins: 10)
        }
        XCTAssertTrue(notes.isEmpty, "人が替わったあとに前の人の硬貨の知らせを流した")
        XCTAssertFalse(welcome.restore(userId: "B"), "次の人に前の人の案内を出す")
        XCTAssertFalse(welcome.hasPending)
        // A さんが入り直した
        XCTAssertTrue(welcome.restore(userId: "A"))
        XCTAssertEqual(welcome.consume()?.added, 10)
        // 知らせには配った人が入る
        let other = gate()
        _ = await other.claim(userId: "C", available: true) { TrunkWelcomeResult(granted: true, added: 10, coins: 15) }
        XCTAssertEqual(notes.last?["userId"] as? String, "C")
        XCTAssertEqual(notes.last?["coins"] as? Int, 15)
    }

    func testServicePostsToWelcomeAndThrowsOnMissingRoute() async throws {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let service = TrunkService(api: api)
        ScriptedProtocol.script = [.init(match: "/user/trunk/welcome", status: 200,
                                         body: #"{"granted":true,"added":10,"coins":11}"#, once: true)]
        let result = try await service.welcome()
        XCTAssertEqual(result, TrunkWelcomeResult(granted: true, added: 10, coins: 11))
        XCTAssertEqual(ScriptedProtocol.calls.last?.method, "POST")
        XCTAssertEqual(ScriptedProtocol.calls.last?.path, "/user/trunk/welcome")
        // 古いサーバー（口が無い）: 投げる → `TrunkWelcome` は印を残さない
        ScriptedProtocol.script = []
        do {
            _ = try await service.welcome()
            XCTFail("口が無いのに答えを返した")
        } catch {}
        let welcome = gate()
        _ = await welcome.claim(userId: "u1", available: true) { try await service.welcome() }
        XCTAssertFalse(welcome.isDone("u1"), "404 で印を残した")
    }

    /// 口の有無はマイページの札と同じ1回の読み込みを使う: 確かめた人（口が無かった人も）は、
    /// はじめての硬貨の側からもう1本読まない（`TrunkAvailability.checkedThisLaunch`・2026-10-18）
    func testAvailabilityCheckIsNotRepeatedForTheWelcome() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let availability = TrunkAvailability(defaults: defaults, entry: TrunkEntryStore())
        XCTAssertFalse(availability.checkedThisLaunch.contains("u1"))
        ScriptedProtocol.script = []  // 口が無い（404）
        await availability.refresh(userId: "u1", service: TrunkService(api: api), preview: false)
        XCTAssertFalse(availability.isAvailable)
        XCTAssertTrue(availability.checkedThisLaunch.contains("u1"), "確かめたことを覚えていない（もう1本読む）")
        XCTAssertFalse(availability.checkedThisLaunch.contains("u2"))
        XCTAssertEqual(ScriptedProtocol.calls.count, 1)
        // 一時の失敗（500）・取り消しでは「確かめた」と残さない（はじめての硬貨の側がもう一度確かめられる）
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 500, body: "")]
        await availability.refresh(userId: "u3", service: TrunkService(api: api), preview: false)
        XCTAssertFalse(availability.checkedThisLaunch.contains("u3"), "失敗した読み込みを「確かめた」と覚えた")
        let cancelled = Task { @MainActor in
            await availability.refresh(userId: "u4", service: TrunkService(api: api), preview: false)
        }
        cancelled.cancel()
        await cancelled.value
        XCTAssertFalse(availability.checkedThisLaunch.contains("u4"), "取り消した読み込みを「確かめた」と覚えた")
    }

    // MARK: 硬貨の数の読み直し

    private func label(_ id: String) -> String {
        #"{"id":"\#(id)","kind":"place","place":{"name":"京都"},"seed":1,"at":"2026-10-17T00:00:00Z"}"#
    }

    func testOpenTrunkReloadsCoinsWhenWelcomeIsGranted() async throws {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil, center: center)
        model.bind(TrunkService(api: api))
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[\#(label("p-1"))],"stuck":[],"coins":1,"posts":4}"#, once: true)]
        await model.load(offline: false)
        XCTAssertEqual(model.state?.coins, 1)
        // はじめての硬貨が配られた → 見張りが読み直す
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[\#(label("p-1"))],"stuck":[],"coins":11}"#)]
        center.post(name: .trunkCoinsChanged, object: nil, userInfo: ["coins": 11])
        for _ in 0..<100 where model.state?.coins != 11 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(model.state?.coins, 11, "硬貨が配られても数が古いまま")
        XCTAssertEqual(model.state?.posts, 4, "投稿の数を引き継いでいない")
        XCTAssertNil(model.actionError)
    }

    /// 読み直しが失敗したら、知らせの数だけ映す（押していない人に失敗の一行を出さない）
    func testReloadFailureAppliesNotifiedCoinsQuietly() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil, center: center)
        model.bind(TrunkService(api: api), userId: "u1")
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[],"stuck":[],"coins":2}"#, once: true)]
        await model.load(offline: false)
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 500, body: "")]
        await model.noteCoinsChanged(coins: 12, userId: "u1")
        XCTAssertEqual(model.state?.coins, 12)
        XCTAssertNil(model.actionError, "押していないのに失敗の一行を出した")
    }

    /// 別の人の知らせは受けない。人が分からない知らせの数は、読み直しが失敗しても映さない（2026-10-18 の見直し）
    func testCoinsNoticeForAnotherUserIsIgnored() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil, center: center)
        model.bind(TrunkService(api: api), userId: "B")
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[],"stuck":[],"coins":2}"#, once: true)]
        await model.load(offline: false)
        let callsBefore = ScriptedProtocol.calls.count
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 500, body: "")]
        await model.noteCoinsChanged(coins: 50, userId: "A")
        XCTAssertEqual(model.state?.coins, 2, "別の人の枚数を映した")
        XCTAssertEqual(ScriptedProtocol.calls.count, callsBefore, "別の人の知らせで読み直した")
        // 見ている人が分からない画面: 読み直しはするが、失敗しても知らせの数は映さない
        let unknown = TrunkViewModel(preview: nil, center: center)
        unknown.bind(TrunkService(api: api))
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[],"stuck":[],"coins":3}"#, once: true)]
        await unknown.load(offline: false)
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 500, body: "")]
        await unknown.noteCoinsChanged(coins: 50, userId: "A")
        XCTAssertEqual(unknown.state?.coins, 3, "誰の知らせか確かめずに枚数を映した")
    }

    /// まだ読んでいない画面・見本は読まない（開いたときに読む）
    func testUnloadedOrPreviewModelDoesNotFetch() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let unloaded = TrunkViewModel(preview: nil, center: center)
        unloaded.bind(TrunkService(api: api))
        await unloaded.noteCoinsChanged(coins: 5)
        XCTAssertNil(unloaded.state)
        let preview = TrunkViewModel(preview: .sample, previewPro: false, center: center)
        preview.bind(TrunkService(api: api))
        await preview.load(offline: false)
        await preview.noteCoinsChanged(coins: 50)
        XCTAssertTrue(ScriptedProtocol.calls.isEmpty, "見本・読んでいない画面でサーバーを読んだ")
    }


}

/// はじめての硬貨の言葉・答えの読み方・順番・つなぎ（MainActor を使わない試験）
final class TrunkWelcomeRulesTests: XCTestCase {

    // MARK: 案内の数と言葉

    func testAddedAndCappedWording() {
        XCTAssertEqual(TrunkWelcomeText.added(10).number, "+10")
        XCTAssertEqual(TrunkWelcomeText.added(3).number, "+3", "上限に当たった回に実際の枚数を出していない")
        XCTAssertEqual(TrunkWelcomeText.total(12).number, "12")
        XCTAssertNil(TrunkWelcomeText.cappedNote(10), "10 枚配った回に上限の一言を出す")
        XCTAssertNotNil(TrunkWelcomeText.cappedNote(3))
        XCTAssertTrue(TrunkWelcomeText.cappedNote(3)?.contains("3") ?? false)
        XCTAssertNil(TrunkWelcomeText.cappedNote(0))
        for text in [TrunkWelcomeText.title, TrunkWelcomeText.thanks, TrunkWelcomeText.howToEarn,
                     TrunkWelcomeText.whatItDoes, TrunkWelcomeText.turn, TrunkWelcomeText.later, TrunkWelcomeText.eyebrow] {
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("捨て"))
        }
    }

    // MARK: 答えの読み方と口

    func testDecodesResult() throws {
        let decode = { (json: String) throws -> TrunkWelcomeResult in
            try JSONDecoder().decode(TrunkWelcomeResult.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode(#"{"granted":true,"added":10,"coins":12}"#), TrunkWelcomeResult(granted: true, added: 10, coins: 12))
        XCTAssertEqual(try decode(#"{"granted":false,"added":"0","coins":7.0}"#), TrunkWelcomeResult(granted: false, added: 0, coins: 7))
        XCTAssertEqual(try decode(#"{"granted":true,"added":-3,"coins":-1}"#), TrunkWelcomeResult(granted: true, added: 0, coins: 0))
        // granted の無い本文は答えと見なさない（印を残さないため、投げる）
        XCTAssertThrowsError(try decode(#"{"added":10,"coins":12}"#))
        XCTAssertThrowsError(try decode(#"{}"#))
    }

    // MARK: 順番（PostModalGate）

    func testWelcomeComesLastAndBlocksOthers() {
        XCTAssertTrue(PostModalGate.welcomeMayShow(PostModalSnapshot()))
        let blockers: [(String, PostModalSnapshot)] = [
            ("ほかの画面が出ている", PostModalSnapshot(modalPresenting: true)),
            ("起動の案内（新しくなったこと・贈り物）を決めている", PostModalSnapshot(launchNoticesDeciding: true)),
            ("通知の説明を決めている", PostModalSnapshot(pushPrimerDeciding: true)),
            ("通知の説明が出ている", PostModalSnapshot(pushPrimerShowing: true)),
            ("評価のお願いを決めている", PostModalSnapshot(reviewDeciding: true)),
            ("届いた画面に出すものが残っている", PostModalSnapshot(trunkPending: true)),
            ("届いた画面が出ている", PostModalSnapshot(trunkShowing: true)),
            ("案内がもう出ている", PostModalSnapshot(welcomeShowing: true)),
            ("アプリが前面に出ていない", PostModalSnapshot(sceneActive: false)),
        ]
        for (name, s) in blockers {
            XCTAssertFalse(PostModalGate.welcomeMayShow(s), "\(name)のに案内を出す")
        }
        // 案内が出ている間は、評価のお願いも届いた画面も重ねない
        let showing = PostModalSnapshot(welcomeShowing: true)
        XCTAssertFalse(PostModalGate.reviewMayAsk(showing), "案内の上に評価の窓を重ねた")
        XCTAssertFalse(PostModalGate.trunkMayShow(showing), "案内の上に届いた画面を重ねた")
        // 起動の案内を決めている間でも、評価のお願いの待ちや届いた画面の決まりは前のまま
        XCTAssertTrue(PostModalGate.trunkMayShow(PostModalSnapshot(launchNoticesDeciding: true)))
    }

    // MARK: つなぎ（画面は Linux で動かせないので、書き方を見張る）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testRootViewWiring() throws {
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("tabsWithTrunkWelcome\n"), "案内の修飾子が繋がっていない")
        XCTAssertTrue(root.contains("until: PostModalGate.welcomeMayShow"), "案内が順番の決まりを通っていない")
        XCTAssertTrue(root.contains("await trunkWelcome.claim(userId: userId, available: trunkAvailability.isAvailable) { try await service.welcome() }"),
                      "トランクが使えるかを見ずに呼んでいる")
        XCTAssertTrue(root.contains(".task(id: auth.userId) { await claimTrunkWelcome() }"))
        XCTAssertTrue(root.contains("if trunkWelcome.restore(userId: auth.userId) { return }"), "出せなかった案内を起動で戻していない")
        XCTAssertTrue(root.contains("if !trunkAvailability.isAvailable, !trunkAvailability.checkedThisLaunch.contains(userId) {"),
                      "マイページの札と別に GET /user/trunk をもう1本読む")
        XCTAssertTrue(root.contains("scenePhase == .active"), "前面に戻ったときに出し直さない")
        XCTAssertTrue(root.contains("[tabRouter.postSheetsClosed, tabRouter.menuSheetsClosed]"), "シートを閉じたときに出し直さない")
        XCTAssertTrue(root.contains("welcomeShowing: trunkWelcomeGrant != nil"), "案内が出ていることを順番に渡していない")
        XCTAssertTrue(root.contains("sceneActive: scenePhase == .active"), "裏にいる間も案内を出す")
        XCTAssertTrue(root.contains("TrunkWelcomeView(grant: grant) {\n                    welcomeAppeared = true\n                    trunkWelcome.noteShown(userId: auth.userId)"),
                      "全画面が出たときに控えを消していない")
        XCTAssertTrue(root.contains("trunkWelcome.requeue(grant, userId: owner)"), "出なかった案内を待ちへ戻していない")
        XCTAssertTrue(root.contains("launchNoticesDeciding: launchNoticesDeciding || showWhatsNew || foundingGiftName != nil"))
        XCTAssertTrue(root.contains("welcomeOffer?.cancel()\n                welcomeOffer = nil\n"),
                      "人が替わっても前の人の案内の待ちが止まらない")
        let store = "TrunkWelcome"
        XCTAssertTrue(try source("Core/Storage/AccountLocalData.swift").contains(store + ".removeData(for: userId, defaults: defaults)"),
                      "退会で印を消していない")
        let view = try source("Features/Trunk/TrunkWelcomeView.swift")
        XCTAssertTrue(view.contains(".navigationDestination(isPresented: $showGacha) { TrunkGachaView(model: model) }"),
                      "「カプセルを回す」がカプセルの機械へ進まない")
        XCTAssertTrue(view.contains("model.bind(environment.trunk, userId: auth.userId)"))
        XCTAssertTrue(view.contains(".onAppear {\n            guard !shown else { return }\n            shown = true\n            onShown()"),
                      "出たことを1回だけ知らせていない")
        XCTAssertTrue(view.contains("TrunkCoinMark("), "カプセルの機械の硬貨の描き方を使っていない")
        XCTAssertTrue(view.contains("JPFont.mono("), "数が等幅の数字でない")
        // 2026-10-18（#304）: アイコン・カバーのお礼（板 53）と同じ画面を使うので、目印は言葉の束（`TrunkCoinNoticeCopy.id`）から作る。
        // はじめての硬貨の束の頭は `trunk.welcome` のまま（`ProfileCoverPickTests.testRewardTexts` が見る）
        for part in ["turn", "later", "close"] {
            XCTAssertTrue(view.contains(".accessibilityIdentifier(\"\\(copy.id).\(part)\")"), "trunk.welcome.\(part)")
        }
        XCTAssertEqual(TrunkCoinNoticeCopy.welcome(.init(added: 10, coins: 12)).id, "trunk.welcome")
    }

    // MARK: 全画面が本当に出たか（2026-10-18 の見直し）

    /// 秒数では決めない: 何かが出ている間（自分の全画面が出かけている・遅い端末）は何秒でも待つ
    func testSlowPresentationIsNotGivenBack() {
        var watch = WelcomePresentationWatch()
        let t0 = Date(timeIntervalSince1970: 1_000)
        for second in 0..<30 {
            XCTAssertEqual(watch.check(appeared: false, modalPresenting: true, now: t0.addingTimeInterval(Double(second))),
                           .waiting, "\(second) 秒で、出かけている全画面を下ろした")
        }
        XCTAssertEqual(watch.check(appeared: true, modalPresenting: true, now: t0.addingTimeInterval(31)), .shown)
    }

    /// 何も出ていない状態が続いたら「出なかった」。途中で何かが出たら数え直す
    func testQuietWithoutAppearanceIsGivenBack() {
        var watch = WelcomePresentationWatch()
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false, now: t0), .waiting)
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false, now: t0.addingTimeInterval(0.5)), .waiting)
        // 別のシートが出た: 待ち直し
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: true, now: t0.addingTimeInterval(0.9)), .waiting)
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false, now: t0.addingTimeInterval(1.2)), .waiting)
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false, now: t0.addingTimeInterval(1.9)), .waiting,
                       "何かが出たあとの静けさを数え直していない")
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false,
                                   now: t0.addingTimeInterval(1.2 + WelcomePresentationWatch.quietSeconds)), .giveBack)
    }

    /// 裏にいる間は数えない: 裏へ回る前の静けさを起点に残さず、前面に戻ってから1秒数え直す
    func testBackgroundResetsTheQuietCount() {
        var watch = WelcomePresentationWatch()
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false, now: t0), .waiting)
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false, sceneActive: false, now: t0.addingTimeInterval(0.5)), .waiting)
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false, sceneActive: false, now: t0.addingTimeInterval(20)), .waiting,
                       "裏にいる間に「出なかった」と決めた")
        // 前面に戻った瞬間には決めない
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false, now: t0.addingTimeInterval(20.1)), .waiting,
                       "前面に戻った瞬間に「出なかった」と決めた（一瞬二度出る）")
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false, now: t0.addingTimeInterval(20.6)), .waiting)
        XCTAssertEqual(watch.check(appeared: false, modalPresenting: false, now: t0.addingTimeInterval(21.2)), .giveBack)
    }

    /// 何かが出たまま3秒続いたら問い合わせを1秒に延ばし、閉じたら0.1秒に戻す
    func testPollingSlowsWhileSomethingStaysOpen() {
        var watch = WelcomePresentationWatch()
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(watch.pollInterval, 0.1)
        _ = watch.check(appeared: false, modalPresenting: true, now: t0)
        _ = watch.check(appeared: false, modalPresenting: true, now: t0.addingTimeInterval(2.9))
        XCTAssertEqual(watch.pollInterval, 0.1, "3秒たつ前に延ばした")
        _ = watch.check(appeared: false, modalPresenting: true, now: t0.addingTimeInterval(3.0))
        XCTAssertEqual(watch.pollInterval, 1, "出たままなのに 0.1 秒ごとに問い続ける")
        _ = watch.check(appeared: false, modalPresenting: false, now: t0.addingTimeInterval(10))
        XCTAssertEqual(watch.pollInterval, 0.1, "閉じたのに延ばしたまま")
        // 次に出たときは、また3秒から数える
        _ = watch.check(appeared: false, modalPresenting: true, now: t0.addingTimeInterval(10.5))
        XCTAssertEqual(watch.pollInterval, 0.1, "前の出たままの起点が残っている")
    }

    func testRootViewWatchesPresentationAndClearsOnUserSwitch() throws {
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("watch.check(appeared: welcomeAppeared, modalPresenting: ModalProbe.isPresenting(),\n                                   sceneActive: scenePhase == .active, now: Date())"),
                      "出たかを何も出ていないことで確かめていない")
        XCTAssertFalse(root.contains("for _ in 0..<30 where !welcomeAppeared"), "決まった秒数で出なかったと決めている")
        XCTAssertTrue(root.contains("welcomeOffer = nil\n                trunkWelcomeGrant = nil\n                trunkWelcome.noteUser(userId)"),
                      "人が替わっても出しかけの案内が残る")
    }
}
