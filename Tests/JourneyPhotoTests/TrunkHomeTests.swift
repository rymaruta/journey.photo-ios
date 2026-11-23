import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 旅のトランクの最初の画面（札 #711・案「トランクを見やすく」版3・2026-11-23 owner 承認）。
/// 状態で替わる大きいボタン1つ・4つのカード・6つの状態・「回して見る」・圏外で前に読んだトランクを出す
final class TrunkHomeTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: 大きいボタンの選び方

    func testPrimaryFollowsWhatYouHave() {
        XCTAssertEqual(TrunkHome.primary(pocket: 2, coins: 3, isEmpty: false), .stick, "貼っていないラベルがあれば貼る")
        XCTAssertEqual(TrunkHome.primary(pocket: 1, coins: 0, isEmpty: false), .stick)
        XCTAssertEqual(TrunkHome.primary(pocket: 0, coins: 3, isEmpty: false), .gacha, "ラベルが無くて硬貨があれば回す")
        XCTAssertEqual(TrunkHome.primary(pocket: 0, coins: 0, isEmpty: false), .post, "どちらも無ければ投稿")
        // まだ何も届いていない人は、硬貨があっても投稿（初めの一歩）
        XCTAssertEqual(TrunkHome.primary(pocket: 0, coins: 1, isEmpty: true), .post)
    }

    func testPrimaryWording() {
        XCTAssertEqual(TrunkHome.title(.stick), "ラベルを貼る")
        XCTAssertEqual(TrunkHome.title(.gacha), "カプセルを回す")
        XCTAssertEqual(TrunkHome.title(.post), "写真を投稿")
        XCTAssertEqual(TrunkHome.subtitle(.stick, pocket: 2, coins: 3), "貼っていないラベルが 2 枚")
        XCTAssertEqual(TrunkHome.subtitle(.gacha, pocket: 0, coins: 3), "硬貨が 3 枚あります")
        XCTAssertEqual(TrunkHome.subtitle(.post, pocket: 0, coins: 0), "投稿するとラベルと硬貨が届きます")
    }

    /// 大きいボタンと同じことはカードに出さない。カードは4つ（タグに対応していないサーバーでは3つ）
    func testTilesNeverRepeatThePrimary() {
        let same: [TrunkHomeAction: TrunkHomeTile] = [.stick: .stick, .gacha: .gacha]
        for action in [TrunkHomeAction.stick, .gacha, .post] {
            let tiles = TrunkHome.tiles(for: action, showsTags: true)
            XCTAssertEqual(tiles.count, 4, "\(action)")
            XCTAssertEqual(Set(tiles).count, 4)
            if let dup = same[action] { XCTAssertFalse(tiles.contains(dup), "\(action) の入口が2つ並ぶ") }
            // 目印は大きいボタンとカードで重ならない（UI テストが1つに決められる）
            let ids = tiles.map(TrunkHome.identifier) + [TrunkHome.identifier(action)]
            XCTAssertEqual(Set(ids).count, ids.count, "\(action) の目印が重なる")
            XCTAssertEqual(TrunkHome.tiles(for: action, showsTags: false), tiles.filter { $0 != .tags })
        }
        XCTAssertEqual(TrunkHome.tiles(for: .stick, showsTags: true), [.gacha, .parts, .tags, .open])
        XCTAssertEqual(TrunkHome.tiles(for: .gacha, showsTags: true), [.parts, .tags, .open, .stick])
    }

    /// 2つずつの段。3枚（手荷物タグに対応していないサーバー）なら3枚目は1段を横いっぱいに使う（左に1枚だけ残さない）
    func testThreeTilesWidenTheLastOne() throws {
        for action in [TrunkHomeAction.stick, .gacha, .post] {
            let four = TrunkHome.tiles(for: action, showsTags: true)
            XCTAssertEqual(TrunkHome.tileRows(four).map(\.count), [2, 2], "\(action)")
            let three = TrunkHome.tiles(for: action, showsTags: false)
            XCTAssertEqual(three.count, 3)
            let rows = TrunkHome.tileRows(three)
            XCTAssertEqual(rows.map(\.count), [2, 1], "\(action) の3枚目が1段を使っていない")
            XCTAssertEqual(rows.flatMap { $0 }, three, "並びが変わった")
        }
        // 画面は段ごとに横に並べる（2列の格子だと最後の1枚が左に残る）
        let main = try source("Features/Trunk/TrunkView.swift")
        XCTAssertTrue(main.contains("let rows = TrunkHome.tileRows(TrunkHome.tiles(for: TrunkHome.primary(state), showsTags: state.supportsTagPicks))"))
        XCTAssertTrue(main.contains("ForEach(rows, id: \\.self) { row in"))
        XCTAssertTrue(main.contains(".frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)"), "カードが横いっぱいに広がらない")
    }

    func testTileWording() {
        let state = TrunkSample.state(isPro: false, coins: 3)
        XCTAssertEqual(TrunkHome.tileValue(.gacha, state: state), "硬貨 3 枚")
        XCTAssertEqual(TrunkHome.tileValue(.stick, state: state), "手持ち \(state.pocket.count) 枚")
        XCTAssertEqual(TrunkHome.tileValue(.open, state: state), "メダルと乗車券")
        let c = TrunkPartsBoxText.collected(state.ownedParts)
        XCTAssertEqual(TrunkHome.tileValue(.parts, state: state), "\(c.owned) / \(c.total) 集めた")
        XCTAssertEqual(TrunkHome.tileTitle(.tags), TrunkTagText.title)
        XCTAssertEqual(TrunkHome.spinTitle, "回して見る")
        XCTAssertEqual(TrunkHome.stuckCaption, "貼ったラベル")
        // 「・」「·」で区切らない・「撮りどき」「捨てる」を出さない（CLAUDE.md の好み）
        var words = [TrunkHome.firstNote, TrunkHome.offlineSavedNote, TrunkHome.offlineRetry, TrunkHome.stillOffline,
                     TrunkHome.spinTitle, TrunkHome.spinLabel]
        for action in [TrunkHomeAction.stick, .gacha, .post] {
            words += [TrunkHome.title(action), TrunkHome.subtitle(action, pocket: 2, coins: 3)]
        }
        for tile in TrunkHomeTile.allCases { words += [TrunkHome.tileTitle(tile), TrunkHome.tileValue(tile, state: state)] }
        for word in words {
            XCTAssertFalse(word.contains("・") || word.contains("·"), "「\(word)」を中黒で区切っている")
            XCTAssertFalse(word.contains("撮りどき") || word.contains("捨て"), word)
        }
    }

    // MARK: 6つの状態

    @MainActor
    private func screen(_ home: String?, empty: Bool = false) async -> TrunkHomeScreen {
        let model = TrunkViewModel(preview: empty ? .empty : .sample, previewPro: false, previewCoins: nil, previewHome: home)
        await model.load(offline: false)
        return TrunkHome.screen(loading: model.phase == .loading, offline: model.phase == .offline,
                                showingSaved: model.showingSaved, state: model.state)
    }

    @MainActor
    func testSixStatesFromTheSamples() async {
        let labels = await screen(nil)
        XCTAssertEqual(labels, .labels)
        let coins = await screen("coins")
        XCTAssertEqual(coins, .coins)
        let none = await screen("none")
        XCTAssertEqual(none, .none)
        let first = await screen("first")
        XCTAssertEqual(first, .first)
        let loading = await screen("loading")
        XCTAssertEqual(loading, .loading)
        let offline = await screen("offline")
        XCTAssertEqual(offline, .offline(saved: true))
        XCTAssertEqual(TrunkHome.screen(loading: false, offline: true, showingSaved: false, state: nil), .offline(saved: false))
    }

    // MARK: 圏外: 前に読んだトランクを出す（無ければ今までどおり）

    private var session: URLSession!

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

    @MainActor
    private func offlineModel() -> TrunkViewModel {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil)
        model.bind(TrunkService(api: api))
        StubProtocol.fail(with: URLError(.notConnectedToInternet))
        return model
    }

    @MainActor
    func testOfflineShowsSavedTrunkWhenWeHaveOne() async {
        let saved = TrunkSample.state(isPro: false)
        let model = offlineModel()
        await model.load(offline: true, saved: saved)
        XCTAssertEqual(model.phase, .loaded, "前に読んだトランクがあるのに「電波がありません」だけになる")
        XCTAssertTrue(model.showingSaved)
        XCTAssertEqual(model.state?.stuck.map(\.id), saved.stuck.map(\.id))
        XCTAssertNil(model.actionError, "上のお知らせに赤の一行を重ねている")
        // もう一度押しても読めない: 出したまま、赤の一行も出さない
        await model.load(offline: true, saved: saved)
        XCTAssertTrue(model.showingSaved)
        XCTAssertNil(model.actionError)
    }

    @MainActor
    func testOfflineWithoutSavedTrunkKeepsTheNoSignalScreen() async {
        let model = offlineModel()
        await model.load(offline: true, saved: nil)
        XCTAssertEqual(model.phase, .offline)
        XCTAssertFalse(model.showingSaved)
        XCTAssertNil(model.state)
    }

    /// 電波はあるのに読めない（サーバーの失敗）ときは、前に読んだトランクで隠さない
    @MainActor
    func testServerFailureIsNotHiddenBySavedTrunk() async {
        let model = offlineModel()
        await model.load(offline: false, saved: TrunkSample.state(isPro: false))
        XCTAssertFalse(model.showingSaved)
        if case .failed = model.phase {} else { XCTFail("失敗の画面にならない: \(model.phase)") }
    }

    /// 圏外で前に読んだトランクを出している間は、下の「手持ちのラベル」「トランクの型」も押せない（カードと同じ薄さ）
    func testMenuRowsAreDisabledWhileShowingSaved() throws {
        let main = try source("Features/Trunk/TrunkView.swift")
        XCTAssertTrue(main.contains("menu(state, disabled: saved)"), "圏外の間も下の行が押せる")
        for id in ["trunk.pocket", "trunk.models"] {
            let row = "            .buttonStyle(JPRowButtonStyle())\n            .disabled(disabled)\n            .opacity(disabled ? 0.4 : 1)\n            .accessibilityIdentifier(\"\(id)\")"
            XCTAssertTrue(main.contains(row), "\(id) が圏外の間も押せる・薄くならない")
        }
    }

    /// 電波が戻ったら読み直す（前に読んだトランク・「電波がありません」を出しているときだけ）
    func testReloadsWhenSignalComesBack() throws {
        XCTAssertTrue(TrunkHome.reloadsWhenBack(offline: false, showingSaved: true, phaseOffline: false))
        XCTAssertTrue(TrunkHome.reloadsWhenBack(offline: false, showingSaved: false, phaseOffline: true))
        XCTAssertFalse(TrunkHome.reloadsWhenBack(offline: true, showingSaved: true, phaseOffline: false), "圏外になったときに読み直す")
        XCTAssertFalse(TrunkHome.reloadsWhenBack(offline: false, showingSaved: false, phaseOffline: false), "読めている画面を読み直す")
        let main = try source("Features/Trunk/TrunkView.swift")
        XCTAssertTrue(main.contains(".onChange(of: connectivity.isOffline) { _, offline in"), "電波の見張りを使っていない")
        XCTAssertTrue(main.contains("guard TrunkHome.reloadsWhenBack(offline: offline, showingSaved: model.showingSaved,"))
    }

    // MARK: 初めて開いたときだけ揺らす（端末に1回）

    func testIntroPlaysOncePerDevice() throws {
        let suite = "TrunkHomeTests.intro.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(TrunkHome.takeIntro(defaults))
        XCTAssertFalse(TrunkHome.takeIntro(defaults), "2回目も揺れる")
        XCTAssertFalse(TrunkHome.introKey.contains("userId"), "人ごとの印にしない（端末に1回）")
    }

    // MARK: 画面の組み（Linux では描けないので書き方で見る）

    func testScreenLayout() throws {
        let main = try source("Features/Trunk/TrunkView.swift")
        XCTAssertFalse(main.contains("押すと手に取って回せます"), "「押すと手に取って回せます」の文が残っている")
        XCTAssertFalse(main.contains("最近貼ったラベル"), "最近貼ったラベルの段が残っている")
        XCTAssertTrue(main.contains("\"trunk.spin.chip\""), "「回して見る」が無い")
        XCTAssertTrue(main.contains("TrunkStuckLabelsView(labels: state.stuck)"), "「貼ったラベル」から一覧へ行けない")
        // 写真の無い画面の主ボタン: 真鍮の塗りに墨（板・CLAUDE.md の owner の好み）
        XCTAssertTrue(main.contains(".foregroundStyle(WebTheme.accentText)"))
        XCTAssertTrue(main.contains(".background(WebTheme.accentFill, in: Capsule())"))
        XCTAssertTrue(main.contains("minHeight: JPHeight.primaryButton"), "主ボタンが 50 でない")
        // 圏外は前に読んだトランク（メモリの写し）を渡す
        XCTAssertTrue(main.contains("TrunkEntryStore.shared.state(for: $0)"))
        XCTAssertTrue(main.contains("await model.load(offline: connectivity.isOffline, saved: savedState)"))
        // 揺れは「動きを減らす」で止める
        XCTAssertTrue(main.contains("if !reduceMotion {"))
        // 受け取りの設定は #706 のあとに移す（今は残す）
        XCTAssertTrue(main.contains("\"trunk.receive\""))
    }

    /// 見本の鍵は Debug だけ
    func testPreviewKeyIsDebugOnly() throws {
        let preview = try source("Core/Auth/PreviewSession.swift")
        XCTAssertTrue(preview.contains("static let trunkHomeKey = \"JPPreviewTrunkHome\""))
        XCTAssertNil(PreviewSession.trunkHome, "テストで見本が効いている")
    }
}
