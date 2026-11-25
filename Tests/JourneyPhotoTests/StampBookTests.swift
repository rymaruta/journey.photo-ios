import XCTest
@testable import JourneyPhoto

/// 旅のスタンプ帳（札 #712）。端末が自分の写真から作る帳面の決まり
final class StampBookTests: XCTestCase {

    // MARK: - 見本の台帳と写真

    private func spot(_ id: String, name: String? = nil, prefecture: String? = nil, country: String? = nil,
                      category: String? = "寺院", stage: String = "published", lat: Double = 35.0, lng: Double = 135.7) throws -> OfficialSpot {
        var region: [String] = []
        if let prefecture { region.append("\"prefecture\":\"\(prefecture)\"") }
        if let country { region.append("\"country\":\"\(country)\"") }
        let regionField = region.isEmpty ? "" : ",\"region\":{\(region.joined(separator: ","))}"
        let categoryField = category.map { ",\"category\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"\(id)\",\"slug\":\"\(id)\",\"name\":\"\(name ?? id)\",\"stage\":\"\(stage)\"\(regionField)\(categoryField),\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}}".utf8))
    }

    private func photo(_ id: String, spotId: String? = nil, date: String? = nil, createdAt: String? = nil,
                       location: String? = nil, lat: Double? = nil, lng: Double? = nil,
                       published: Bool? = nil, spotAuto: String? = nil, owner: String? = "u_me") throws -> Photo {
        var row: [String: Any] = ["id": id, "src": "/uploads/\(id).jpg"]
        if let owner { row["userId"] = owner }
        if let spotId { row["spotId"] = spotId }
        if let date { row["date"] = date }
        if let createdAt { row["createdAt"] = createdAt }
        if let location { row["location"] = location }
        if let lat, let lng { row["coords"] = ["lat": lat, "lng": lng] }
        if let published { row["published"] = published }
        if let spotAuto { row["spotAuto"] = spotAuto }
        return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: row))
    }

    private let me = "u_me"

    private func ledger() throws -> [OfficialSpot] {
        [
            try spot("sp_kinkaku", name: "鹿苑寺（金閣寺）", prefecture: "京都府", category: "寺院"),
            try spot("sp_fushimi", name: "伏見稲荷大社", prefecture: "京都府", category: "神社"),
            try spot("sp_arashi", name: "嵐山 竹林の小径", prefecture: "京都府", category: "並木道"),
            try spot("sp_otaru", name: "小樽運河", prefecture: "北海道", category: "運河", lat: 43.2, lng: 141.0),
            try spot("sp_hall", name: "ハルシュタット", prefecture: "オーバーエースターライヒ州", country: "オーストリア",
                     category: "町並み", lat: 47.56, lng: 13.65),
            try spot("sp_draft", name: "下書きの所", prefecture: "京都府", stage: "review"),
        ]
    }

    // MARK: - 押される条件

    /// 他人の写真・持ち主の分からない写真・ログインしていないときは押さない（`PhotoOwnership.isMine`）
    func testOnlyOwnPhotosStamp() throws {
        let photos = [
            try photo("mine", spotId: "sp_kinkaku", date: "2026-11-23"),
            try photo("other", spotId: "sp_otaru", date: "2026-11-22", owner: "u_other"),
            try photo("unknown", spotId: "sp_fushimi", date: "2026-11-21", owner: nil),
        ]
        let book = StampBook.build(me: me, photos: photos, spots: try ledger(), links: .empty, matcher: nil)
        XCTAssertEqual(book.stamps.map(\.spotId), ["sp_kinkaku"], "他人の写真か持ち主の分からない写真でスタンプが押された")
        XCTAssertEqual(book.stamps.first?.photos.map(\.id), ["mine"])
        XCTAssertTrue(StampBook.build(me: nil, photos: photos, spots: try ledger(), links: .empty, matcher: nil).isEmpty,
                      "ログインしていないのにスタンプが押された")
        let screen = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Profile/StampBookScreen.swift"), encoding: .utf8)
        XCTAssertTrue(screen.contains("StampBook.buildCancellable(me: userId,"), "帳面を自分の id で作っていない")
    }

    /// 本人が選んだ `spotId` の写真で、そのスポットのスタンプが1つ押される。同じ所の写真は1つにまとまる
    func testExplicitSpotIdStampsOncePerSpot() throws {
        let photos = [
            try photo("a", spotId: "sp_kinkaku", date: "2026-11-23"),
            try photo("b", spotId: "sp_kinkaku", date: "2025-04-01"),
            try photo("c", spotId: "sp_otaru", createdAt: "2025-08-12T10:00:00Z"),
        ]
        let book = StampBook.build(me: me, photos: photos, spots: try ledger(), links: .empty, matcher: nil)
        // 並びは「はじめて撮った日」の新しい順（金閣寺は 2025-04-01 が最初、小樽は 2025-08-12）
        XCTAssertEqual(book.stamps.map(\.spotId), ["sp_otaru", "sp_kinkaku"], "はじめて撮った日の新しい順に並んでいない")
        let kinkaku = try XCTUnwrap(book.stamps.last)
        XCTAssertEqual(kinkaku.photos.map(\.id), ["a", "b"], "写真が新しい順に並んでいない")
        XCTAssertEqual(kinkaku.firstDay, "2025-04-01", "はじめて撮った日がいちばん古い日でない")
        XCTAssertEqual(kinkaku.prefecture, "京都府")
        XCTAssertNil(kinkaku.country)
        XCTAssertEqual(book.stamps.first?.firstDay, "2025-08-12", "撮影日の無い写真は投稿した日を使う")
        XCTAssertEqual(book.prefectures, ["北海道", "京都府"], "県が北からの順でない")
    }

    /// 結びの表（公開の写真）でも押される。本人が外した写真は表にあっても押さない
    func testLinksTableAndOffMark() throws {
        let links = SpotPhotoLinks(links: ["auto": "sp_fushimi", "off": "sp_fushimi"])
        let photos = [try photo("auto"), try photo("off", spotAuto: "off")]
        let book = StampBook.build(me: me, photos: photos, spots: try ledger(), links: links, matcher: nil)
        XCTAssertEqual(book.stamps.map(\.spotId), ["sp_fushimi"])
        XCTAssertEqual(book.stamps.first?.photos.map(\.id), ["auto"], "外した写真まで数えた")
        // この端末で外した分（サイトの作り直しの前）も効く
        let offHere = links.with(["auto": .off(spotId: "sp_fushimi")])
        XCTAssertTrue(StampBook.build(me: me, photos: [try photo("auto")], spots: try ledger(), links: offHere, matcher: nil).isEmpty)
    }

    /// 表に無い写真（自分だけの写真など）は、端末の突き合わせ（撮影地の名前と位置）で結ぶ。外した写真は突き合わせない
    func testMatcherForPhotosOutsideTheTable() throws {
        let index = SpotMatchIndex(rows: [
            .init(id: "sp_otaru", name: "小樽運河", key: SpotMatcher.normalize("小樽運河"), aliases: [],
                  coords: Photo.Coords(lat: 43.2, lng: 141.0), prefecture: "北海道"),
        ])
        let matcher = SpotMatcher(index: index)
        let privatePhoto = try photo("p", location: "小樽運河", lat: 43.2, lng: 141.0, published: false)
        let book = StampBook.build(me: me, photos: [privatePhoto], spots: try ledger(), links: .empty, matcher: matcher)
        XCTAssertEqual(book.stamps.map(\.spotId), ["sp_otaru"], "自分だけの写真を突き合わせで結んでいない")
        let off = try photo("q", location: "小樽運河", lat: 43.2, lng: 141.0, spotAuto: "off")
        XCTAssertTrue(StampBook.build(me: me, photos: [off], spots: try ledger(), links: .empty, matcher: matcher).isEmpty,
                      "本人が外した写真を突き合わせで結んだ")
    }

    /// 索引に無いスポット・下書きのスポット・結ばれていない写真は押さない
    func testUnknownDraftAndUnlinkedPhotosAreSkipped() throws {
        let photos = [try photo("x", spotId: "sp_gone"), try photo("y", spotId: "sp_draft"), try photo("z", location: "どこか")]
        let book = StampBook.build(me: me, photos: photos, spots: try ledger(), links: .empty, matcher: nil)
        XCTAssertTrue(book.isEmpty)
        XCTAssertEqual(StampBook.empty.prefectures, [])
    }

    /// 写真を消すとスタンプも消える（保存せず、写真から毎回作る）
    func testRemovingPhotoRemovesStamp() throws {
        let all = [try photo("a", spotId: "sp_kinkaku"), try photo("b", spotId: "sp_otaru")]
        XCTAssertEqual(StampBook.build(me: me, photos: all, spots: try ledger(), links: .empty, matcher: nil).stamps.count, 2)
        XCTAssertEqual(StampBook.build(me: me, photos: [all[0]], spots: try ledger(), links: .empty, matcher: nil).stamps.map(\.spotId),
                       ["sp_kinkaku"])
    }

    // MARK: - 県と海外・数

    func testPrefecturePagesTotalsAndAbroad() throws {
        let photos = [
            try photo("a", spotId: "sp_kinkaku", date: "2026-11-23"),
            try photo("b", spotId: "sp_fushimi", date: "2026-11-22"),
            try photo("h", spotId: "sp_hall", date: "2024-09-18"),
        ]
        let book = StampBook.build(me: me, photos: photos, spots: try ledger(), links: .empty, matcher: nil)
        XCTAssertEqual(book.totals["京都府"], 3, "下書きを分母に数えた、または県の数が違う")
        XCTAssertNil(book.totals["オーバーエースターライヒ州"], "海外の州を県に数えた")
        XCTAssertEqual(book.stamps(in: "京都府").map(\.spotId), ["sp_fushimi", "sp_kinkaku"], "県のページは押された順（古い順）")
        XCTAssertEqual(book.remaining(in: "京都府"), 1)
        XCTAssertNil(book.remaining(in: "沖縄県"))
        XCTAssertEqual(book.prefectures, ["京都府"])
        XCTAssertEqual(book.abroad.map(\.spotId), ["sp_hall"])
        XCTAssertEqual(book.abroad.first?.country, "オーストリア")
        XCTAssertEqual(book.abroad.first?.frame, .abroad)
        XCTAssertEqual(book.countryCount, 1)
        XCTAssertEqual(book.recent.map(\.spotId), ["sp_kinkaku", "sp_fushimi", "sp_hall"])
    }

    // MARK: - 図柄

    func testFrameByCategory() {
        XCTAssertEqual(StampFrame.of(category: "寺院", abroad: false), .history)
        XCTAssertEqual(StampFrame.of(category: "城跡", abroad: false), .history)
        XCTAssertEqual(StampFrame.of(category: "運河", abroad: false), .town)
        XCTAssertEqual(StampFrame.of(category: "温泉街", abroad: false), .town)
        XCTAssertEqual(StampFrame.of(category: "湖", abroad: false), .nature)
        XCTAssertEqual(StampFrame.of(category: nil, abroad: false), .nature)
        XCTAssertEqual(StampFrame.of(category: "寺院", abroad: true), .abroad)
        XCTAssertTrue(StampFrame.historyKinds.isDisjoint(with: StampFrame.townKinds))
    }

    /// 地方で8色。47県すべてに色があり、同じ地方は同じ色
    func testInkByRegion() {
        XCTAssertEqual(StampInk.byRegion.count, PrefectureRegions.all.count)
        XCTAssertEqual(Set(StampInk.byRegion).count, 8)
        for prefecture in RegionList.prefectures {
            XCTAssertNotEqual(StampInk.color(prefecture: prefecture), StampInk.abroad, "\(prefecture) に地方の色が無い")
        }
        XCTAssertEqual(StampInk.color(prefecture: "京都府"), StampInk.color(prefecture: "三重県"))
        XCTAssertEqual(StampInk.color(prefecture: "沖縄県"), StampInk.color(prefecture: "福岡県"))
        XCTAssertEqual(StampInk.color(prefecture: nil), StampInk.abroad)
    }

    /// 傾きは場所ごとに決まり（-7〜7）、同じ場所はいつも同じ
    func testTiltIsStablePerSpot() {
        XCTAssertEqual(StampLayout.tilt("sp_kinkaku"), StampLayout.tilt("sp_kinkaku"))
        let tilts = ["sp_a", "sp_b", "sp_c", "sp_d", "sp_e", "sp_f"].map(StampLayout.tilt)
        XCTAssertTrue(tilts.allSatisfy { (-7...7).contains($0) })
        XCTAssertGreaterThan(Set(tilts).count, 1, "どの場所も同じ傾き")
        // 案の頁の模型と同じ FNV-1a（"a" の値）
        XCTAssertEqual(StampLayout.hash("a"), 0xE40C292C)
    }

    func testNameLines() {
        XCTAssertEqual(StampLayout.nameLines("嵐山 竹林の小径"), ["嵐山", "竹林の小径"])
        XCTAssertEqual(StampLayout.nameLines("鹿苑寺（金閣寺）"), ["鹿苑寺", "（金閣寺）"])
        XCTAssertEqual(StampLayout.nameLines("横浜赤レンガ倉庫"), ["横浜赤レ", "ンガ倉庫"])
        XCTAssertEqual(StampLayout.nameLines("万座毛"), ["万座毛"])
        XCTAssertEqual(StampLayout.nameLines("a b c"), ["a", "b"], "3行以上にしない")
        XCTAssertEqual(StampLayout.nameSize(["万座毛"]), 15)
        XCTAssertEqual(StampLayout.nameSize(["（金閣寺）"]), 12)
    }

    func testSilhouetteFitsTheBox() throws {
        let fit = try XCTUnwrap(StampLayout.silhouetteFit(bounds: CGRect(x: 100, y: 200, width: 80, height: 40)))
        XCTAssertEqual(fit.scale, 0.5, accuracy: 1e-9)
        XCTAssertEqual(140 * fit.scale + fit.dx, 50, accuracy: 1e-9, "真ん中が箱の真ん中に来ない")
        XCTAssertEqual(220 * fit.scale + fit.dy, 52, accuracy: 1e-9)
        XCTAssertNil(StampLayout.silhouetteFit(bounds: .zero))
    }

    // MARK: - 言葉

    func testWordsHaveNoMiddleDotAndReadNaturally() throws {
        let stamp = try XCTUnwrap(StampBook.build(me: me, photos: [try photo("a", spotId: "sp_kinkaku", date: "2026-11-23")],
                                                  spots: try ledger(), links: .empty, matcher: nil).stamps.first)
        XCTAssertEqual(StampBookText.stampDate(stamp.firstDay), "2026.11.23")
        XCTAssertEqual(StampBookText.stampDate(nil), "")
        let texts = [StampBookText.title, StampBookText.entryDetail, StampBookText.howTo, StampBookText.emptyTitle,
                     StampBookText.emptySlot, StampBookText.nextSlot, StampBookText.browseSpots, StampBookText.remainingTitle,
                     StampBookText.remainingNote("京都府"), StampBookText.firstDayLabel, StampBookText.photosHere,
                     StampBookText.loadFailed, StampBookText.countries(2), StampBookText.ratio(3, 68),
                     StampBookText.mapAccessibility(["京都府", "北海道"]), StampBookText.accessibility(stamp),
                     StampBookText.countsAccessibility(stamps: 3, prefectures: 2),
                     StampBookText.rowAccessibility(prefecture: "京都府", have: 3, total: 68)]
        for text in texts {
            XCTAssertFalse(text.contains("・") || text.contains("·"), text)
            XCTAssertFalse(text.contains("撮りどき"), text)
        }
        XCTAssertEqual(StampBookText.ratio(3, 68), "3 / 68")
        XCTAssertEqual(StampBookText.ratio(3, nil), "3")
    }

    // MARK: - 画面写真の見本

    func testSamples() throws {
        XCTAssertEqual(StampBookSamples.book("empty")?.isEmpty, true)
        let few = try XCTUnwrap(StampBookSamples.book("few"))
        XCTAssertEqual(few.stamps.count, 3)
        XCTAssertEqual(few.prefectures.count, 3, "少しの見本は別々の県にする")
        let many = try XCTUnwrap(StampBookSamples.book("many"))
        XCTAssertGreaterThan(many.stamps.count, 20)
        XCTAssertFalse(many.abroad.isEmpty)
        XCTAssertEqual(Set(many.stamps.map(\.frame)), Set(StampFrame.allCases), "4つの枠が出ない")
        for name in many.prefectures { XCTAssertNotNil(many.totals[name], "\(name) の分母が無い") }
        XCTAssertNil(StampBookSamples.book("other"))
    }

    // MARK: - 入口と本人だけ

    /// マイページとメニューが同じ入口の部品を使い、行き先はスタンプ帳。人のページには入口を置かない（owner 2026-11-23）
    func testEntryIsOneSharedPartAndOnlyOnOwnPages() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
        func read(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        // マイページは荷札の列（札 #714）の札。縦の行（`StampBookMyPageRow`）は 1.2.0 の統合で荷札に替えた
        XCTAssertTrue(try read("Features/Profile/MyPageView.swift").contains("StampBookToolTag()"))
        XCTAssertFalse(try read("Features/Profile/MyPageView.swift").contains("StampBookMyPageRow"))
        XCTAssertTrue(try read("Features/Common/SiteMenuView.swift").contains("StampBookMenuRow()"))
        let entry = try read("Features/Profile/StampBookScreen.swift")
        XCTAssertEqual(entry.components(separatedBy: "StampBookEntry.destination()").count - 1, 2,
                       "行き先が入口の部品を通っていない")
        let other = try read("Features/Profile/UserProfileView.swift")
        XCTAssertFalse(other.contains("StampBook"), "人のページにスタンプ帳の入口がある（本人だけの帳面）")
        // 共有の道を置かない（画像の書き出し・共有のシート）
        let screen = entry + (try read("Features/Profile/StampBookView.swift"))
        XCTAssertFalse(screen.contains("ShareLink") || screen.contains("ImageRenderer") || screen.contains("UIActivityViewController"),
                       "スタンプ帳に共有の道がある")
    }

    /// ログアウトで前の人の帳面（同じ起動の間の覚え）を手放す
    func testSignOutForgetsTheBook() throws {
        let auth = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Core/Auth/AuthStore.swift"), encoding: .utf8)
        XCTAssertTrue(auth.contains("StampBookModel" + ".forget()"))
    }

    // MARK: - 重さ（2026-11-23 確かめ役の指摘）

    /// 作り物の材料: 観光スポット `spots` 件（47都道府県に散らす）と、自分の写真 `count` 枚
    /// （半分は本人が選んだ `spotId`、4分の1は結びの表、4分の1は撮影地の名前で突き合わせ）
    private func heavyInput(count: Int, spots spotCount: Int) throws
        -> (photos: [Photo], spots: [OfficialSpot], links: SpotPhotoLinks, index: SpotMatchIndex) {
        let prefectures = RegionList.prefectures
        var spotRows: [[String: Any]] = []
        var matchRows: [SpotMatchIndex.Row] = []
        for i in 0..<spotCount {
            let name = "作り物の観光地\(i)番"
            let lat = 31.0 + Double(i % 140) * 0.1, lng = 130.0 + Double(i / 140) * 0.3
            spotRows.append(["spotId": "sp_\(i)", "slug": "s\(i)", "name": name, "stage": "published",
                             "region": ["prefecture": prefectures[i % prefectures.count]], "category": "寺院",
                             "coords": ["lat": lat, "lng": lng]])
            matchRows.append(.init(id: "sp_\(i)", name: name, key: SpotMatcher.normalize(name), aliases: [],
                                   coords: Photo.Coords(lat: lat, lng: lng), prefecture: prefectures[i % prefectures.count]))
        }
        let spots = try JSONDecoder.api.decode([OfficialSpot].self, from: JSONSerialization.data(withJSONObject: spotRows))
        var photoRows: [[String: Any]] = []
        var links: [String: String] = [:]
        for i in 0..<count {
            let target = (i * 7) % spotCount
            var row: [String: Any] = ["id": "p\(i)", "src": "/uploads/p\(i).jpg", "userId": me,
                                      "date": String(format: "2025-%02d-%02d", i % 12 + 1, i % 28 + 1)]
            switch i % 4 {
            case 0, 1: row["spotId"] = "sp_\(target)"
            case 2: links["p\(i)"] = "sp_\(target)"
            default: row["location"] = "作り物の観光地\(target)番"
            }
            photoRows.append(row)
        }
        let photos = try JSONDecoder.api.decode([Photo].self, from: JSONSerialization.data(withJSONObject: photoRows))
        return (photos, spots, SpotPhotoLinks(links: links), SpotMatchIndex(rows: matchRows))
    }

    /// 5,000 枚の写真で帳面を作る時間（突き合わせの下ごしらえを含む）。上限を超えたら落とす。
    /// 上限は Linux の Debug（最適化なし）で測った値の数倍（数は報告と `measured` の行に出す）
    func testBuildFiveThousandPhotosStaysUnderLimit() throws {
        let input = try heavyInput(count: 5_000, spots: 4_640)
        let start = Date()
        let matcher = SpotMatcher(index: input.index)
        let book = StampBook.build(me: me, photos: input.photos, spots: input.spots, links: input.links, matcher: matcher)
        let seconds = Date().timeIntervalSince(start)
        print("measured [StampBook.build 5000 photos] \(String(format: "%.3f", seconds)) s")
        XCTAssertFalse(book.isEmpty)
        XCTAssertEqual(book.stamps.reduce(0) { $0 + $1.photos.count }, 5_000, "結ばれるはずの写真が抜けた")
        XCTAssertLessThan(seconds, Self.fiveThousandLimit, "5,000 枚で帳面を作るのに \(seconds) 秒かかった")
    }

    /// 5,000 枚の上限（秒）
    static let fiveThousandLimit: TimeInterval = 20

    /// 止める合図が来ていたら、作りかけを捨てて CancellationError で抜ける
    func testCancellableBuildStopsWhenCancelled() async throws {
        let input = try heavyInput(count: 300, spots: 200)
        let me = me  // 試験の持ち物（self）を別の仕事へ渡さない（2026-11-25 Swift 6）
        let task = Task { () throws -> StampBook in
            withUnsafeCurrentTask { $0?.cancel() }
            return try StampBook.buildCancellable(me: me, photos: input.photos, spots: input.spots, links: input.links,
                                                  matcher: nil)
        }
        do {
            _ = try await task.value
            XCTFail("止める合図を見ていない")
        } catch is CancellationError {
        }
        // 合図が無ければ、ふつうの build と同じ帳面
        let full = try StampBook.buildCancellable(me: me, photos: input.photos, spots: input.spots, links: input.links,
                                                  matcher: nil)
        XCTAssertEqual(full, StampBook.build(me: me, photos: input.photos, spots: input.spots, links: input.links, matcher: nil))
    }

    /// 材料の目印: 同じ材料なら同じ値、写真の id・spotId・撮影地・題・日、表と索引の件数が変われば違う値
    func testFingerprintChangesOnlyWithInputs() throws {
        let spots = try ledger()
        let base = [try photo("a", spotId: "sp_kinkaku", date: "2026-11-23", location: "京都")]
        func key(_ photos: [Photo], links: SpotPhotoLinks = .empty, spots: [OfficialSpot]? = nil, match: Int? = 10) -> Int {
            StampBook.fingerprint(me: me, photos: photos, spots: spots ?? (try? ledger()) ?? [], links: links, matchRows: match)
        }
        XCTAssertEqual(key(base), key([try photo("a", spotId: "sp_kinkaku", date: "2026-11-23", location: "京都")]))
        XCTAssertNotEqual(key(base), key([try photo("b", spotId: "sp_kinkaku", date: "2026-11-23", location: "京都")]))
        XCTAssertNotEqual(key(base), key([try photo("a", spotId: "sp_otaru", date: "2026-11-23", location: "京都")]))
        XCTAssertNotEqual(key(base), key([try photo("a", spotId: "sp_kinkaku", date: "2026-11-23", location: "大阪")]))
        XCTAssertNotEqual(key(base), key([try photo("a", spotId: "sp_kinkaku", date: "2026-11-22", location: "京都")]))
        XCTAssertNotEqual(key(base), key([try photo("a", spotId: "sp_kinkaku", date: "2026-11-23", location: "京都", spotAuto: "off")]))
        XCTAssertNotEqual(key(base), key(base + [try photo("c")]))
        XCTAssertNotEqual(key(base), key(base, links: SpotPhotoLinks(links: ["x": "sp_otaru"])))
        XCTAssertNotEqual(key(base), key(base, links: SpotPhotoLinks.empty.with(["a": .off(spotId: "sp_kinkaku")])))
        XCTAssertNotEqual(key(base), key(base, spots: Array(spots.dropLast())))
        XCTAssertNotEqual(key(base), key(base, match: 11))
        XCTAssertNotEqual(key(base), StampBook.fingerprint(me: "u_other", photos: base, spots: spots, links: .empty, matchRows: 10))
    }

    /// 読み込みの係の決まり（画面の処理の外で下ごしらえ・同じ材料なら作り直さない・止める合図・ログアウト）
    func testModelBuildsOffMainAndReusesSameInputs() throws {
        let screen = try source("Features/Profile/StampBookScreen.swift")
        let detached = try XCTUnwrap(screen.range(of: "Task.detached(priority: .userInitiated)"))
        let matcher = try XCTUnwrap(screen.range(of: "SpotMatcher.init(index:)"))
        XCTAssertLessThan(detached.lowerBound, matcher.lowerBound, "突き合わせの下ごしらえが画面の処理の中にある")
        XCTAssertEqual(screen.components(separatedBy: "SpotMatcher.init(index:)").count - 1, 1, "下ごしらえが2か所にある")
        XCTAssertFalse(screen.contains("= SpotMatcher("), "下ごしらえが画面の処理の中にある")
        XCTAssertTrue(screen.contains("StampBook.buildCancellable("), "止める合図を見ない作り方を使っている")
        XCTAssertTrue(screen.contains("onCancel: { job.cancel() }"), "閉じても外の処理が止まらない")
        let fingerprint = try XCTUnwrap(screen.range(of: "memory.fingerprint == key"))
        XCTAssertLessThan(fingerprint.lowerBound, detached.lowerBound, "同じ材料でも作り直している")
        // ログインしていないときは失敗の文を出さない
        XCTAssertTrue(screen.contains("phase = .signedOut"))
        XCTAssertTrue(screen.contains("if model.phase == .signedOut {"))
    }

    // MARK: - 押される瞬間（案の頁の1）

    func testPressedOnlyForFirstStampAtThatSpot() throws {
        let spots = try ledger()
        let before = StampBook.build(me: me, photos: [try photo("a", spotId: "sp_kinkaku", date: "2026-01-01"),
                                                      try photo("b", spotId: "sp_fushimi", date: "2026-01-02")],
                                     spots: spots, links: .empty, matcher: nil)
        // 京都府で3つめ
        let pressed = try XCTUnwrap(StampMoment.pressed(spotIds: ["sp_arashi"], before: before, spots: spots, today: "2026-11-23"))
        XCTAssertEqual(pressed.stamp.spotId, "sp_arashi")
        XCTAssertEqual(pressed.stamp.firstDay, "2026-11-23")
        XCTAssertEqual(pressed.ordinal, 3)
        XCTAssertEqual(StampBookText.pressedFact(place: pressed.stamp.placeName, ordinal: pressed.ordinal), "京都府で3つめのスタンプです")
        // もう押してある所・下書き・知らない所・空は出さない。初めての所が後ろにあればそれ
        XCTAssertNil(StampMoment.pressed(spotIds: ["sp_kinkaku"], before: before, spots: spots, today: "2026-11-23"))
        XCTAssertNil(StampMoment.pressed(spotIds: ["sp_draft", "sp_nowhere", ""], before: before, spots: spots, today: "2026-11-23"))
        XCTAssertEqual(StampMoment.pressed(spotIds: ["sp_kinkaku", "sp_otaru"], before: before, spots: spots,
                                           today: "2026-11-23")?.stamp.spotId, "sp_otaru")
        // 前の帳面が分からないときは出さない（初めてか分からないのに祝わない）
        XCTAssertNil(StampMoment.pressed(spotIds: ["sp_arashi"], before: nil, spots: spots, today: "2026-11-23"))
        // 海外は国ごとに数える
        let abroad = try XCTUnwrap(StampMoment.pressed(spotIds: ["sp_hall"], before: before, spots: spots, today: "2026-11-23"))
        XCTAssertEqual(abroad.stamp.placeName, "オーストリア")
        XCTAssertEqual(abroad.ordinal, 1)
        XCTAssertEqual(abroad.stamp.frame, .abroad)
    }

    // MARK: - 届いた画面の中で押す（1.2.0 の統合）

    /// 投稿した写真の観光スポット: 選んだもの → 自動の候補。本人が切った写真は外す。日付は端末の時間帯の YYYY-MM-DD
    func testPressedSpotAndDayRules() {
        XCTAssertEqual(StampMoment.spotId(explicit: "sp_a", candidate: "sp_b", off: nil), "sp_a")
        XCTAssertEqual(StampMoment.spotId(explicit: nil, candidate: "sp_b", off: nil), "sp_b")
        XCTAssertEqual(StampMoment.spotId(explicit: nil, candidate: "sp_b", off: false), "sp_b")
        XCTAssertNil(StampMoment.spotId(explicit: nil, candidate: "sp_b", off: true), "切った候補で押している")
        XCTAssertNil(StampMoment.spotId(explicit: nil, candidate: nil, off: nil))
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        // 2026-11-22 15:30 UTC は東京の 11-23 0:30
        XCTAssertEqual(StampMoment.day(Date(timeIntervalSince1970: 1_795_361_400), timeZone: tokyo), "2026-11-23")
    }

    /// 届いた束にスタンプを入れる。束が重なっても1つだけ（先のものを残す）
    @MainActor
    func testArrivalBatchCarriesOneStamp() async {
        let arrivals = TrunkArrivals()
        let first = StampBookSamples.pressed
        arrivals.deliver([.init(label: TrunkSample.arrived, photoTitle: "朝")], notice: nil, stamp: first)
        let other = StampMoment.Pressed(stamp: StampBook.Stamp(spotId: "sp_x", name: "x", prefecture: "京都府", country: nil,
                                                               frame: first.stamp.frame, firstDay: "2026-11-23", photos: []),
                                        ordinal: 4)
        arrivals.deliver([.init(label: TrunkSample.arrived, photoTitle: "夜")], notice: nil, stamp: other)
        XCTAssertEqual(arrivals.consume()?.stamp, first)
    }

    /// ラベル → 硬貨とかけら → スタンプの順で、同じ画面の中に出す（別の全画面にしない）。投稿の終わりで判定して束に入れる
    func testStampIsWiredIntoTheArrivedScreen() throws {
        // 硬貨が札に入ったあとに落ち始める
        let coinRests = ArrivalSequence.labelAt + ArrivalSequence.landAfter + TrunkMotion.coinAfterLabel + TrunkMotion.coinFallSeconds
        XCTAssertGreaterThan(ArrivalSequence.stampAt, coinRests, "スタンプが硬貨より先に落ちる")
        let view = try source("Features/Trunk/LabelArrivedView.swift")
        let chips = try XCTUnwrap(view.range(of: "                        chips\n                        stampMoment\n"),
                                  "スタンプが硬貨とかけらの札の下に無い")
        XCTAssertNotNil(chips)
        XCTAssertTrue(view.contains("StampPressedView(pressed: pressed) { showStampBook = true }"))
        XCTAssertTrue(view.contains("ArrivalSequence.stampAt"))
        let upload = try source("Features/Upload/UploadViewModel.swift")
        XCTAssertTrue(upload.contains("StampBookModel.shared.pressed(spotIds: stampSpotIds, userId: savedPhotoOwner ?? draftOwner)"))
        XCTAssertTrue(upload.contains("notice: labelNotice, coins: dealtCoins, stamp: stamp)"))
        // 全画面の押される瞬間は置かない（投稿のあとの画面は1枚）
        let pressed = try source("Features/Profile/StampBookView.swift")
        XCTAssertFalse(pressed.contains("labelAlsoArrived"), "ラベルの画面の代わりに出す形が残っている")
    }

    /// 押される瞬間の部品: 0.62 秒・紙が 2pt 沈む・軽い触覚1回・動きを減らす設定では動かさない
    func testPressedViewMotionRules() throws {
        XCTAssertEqual(StampMoment.landDuration, 0.62)
        XCTAssertEqual(StampMoment.paperSink, 2)
        let view = try source("Features/Profile/StampBookView.swift")
        XCTAssertTrue(view.contains(".sensoryFeedback(.impact(weight: .light), trigger: tick)"))
        XCTAssertTrue(view.contains("guard !reduceMotion else {"))
        XCTAssertFalse(view.contains("AudioServices") || view.contains("AVAudio"), "音を出している")
        XCTAssertTrue(view.contains(".onTapGesture { play() }"), "紙を押しても、もう一度動かない")
    }

    // MARK: - 入口の最近の3つ・状態・言葉

    func testEntryShowsRecentThreeInBothRows() throws {
        let screen = try source("Features/Profile/StampBookScreen.swift")
        XCTAssertEqual(screen.components(separatedBy: "accessory: StampBookEntry.recentAccessory(model.book)").count - 1, 2,
                       "マイページとメニューの行が同じ最近の3つの部品を使っていない")
        XCTAssertNil(StampBookEntry.recentCount(nil))
        XCTAssertNil(StampBookEntry.recentCount(.empty))
        XCTAssertEqual(StampBookEntry.recentCount(StampBookSamples.book("many")), 3)
        XCTAssertEqual(StampBookEntry.recentCount(StampBookSamples.book("few")), 3)
    }

    func testStatesAndSlotRules() throws {
        let screen = try source("Features/Profile/StampBookScreen.swift")
        let view = try source("Features/Profile/StampBookView.swift")
        XCTAssertFalse(view.contains("minimumScaleFactor"), "12pt の字を縮めている")
        XCTAssertGreaterThanOrEqual(StampEmptySlot.minimumSide, 96)
        // 圏外で前の帳面を出しているときは一行（ほかの画面の圏外の帯と同じ部品）
        XCTAssertTrue(screen.contains("JPStateBand(kind: .offline, title: StampBookText.offlineSaved"))
        XCTAssertEqual(StampBookText.offlineSaved, "電波が無いので、前に読んだ帳面です")
        // 押せない「観光スポットを見る」は押せない見た目
        XCTAssertTrue(screen.contains(".opacity(browsable ? 1 : StampBookEntry.disabledOpacity)"))
        XCTAssertTrue(screen.contains(".disabled(!browsable)"))
        // 名前は「旅のスタンプ帳」にそろえる（題・行・文）
        XCTAssertEqual(StampBookEntry.title, "旅のスタンプ帳")
        for text in [StampBookText.loadFailed, StampBookText.onlyYou, StampBookText.openBook] {
            XCTAssertTrue(text.contains("旅のスタンプ帳"), text)
        }
        for text in [StampBookText.offlineSaved, StampBookText.pressedTitle("浅草寺"),
                     StampBookText.recentAccessibility(["浅草寺", "東京タワー"]), StampBookText.openBook] {
            XCTAssertFalse(text.contains("・") || text.contains("·"), text)
        }
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto").appendingPathComponent(path), encoding: .utf8)
    }
}
