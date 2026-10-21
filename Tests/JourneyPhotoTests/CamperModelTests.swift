import XCTest
@testable import JourneyPhoto

/// 写真で作るキャンピングカーの「段・持っている部品・覚える飾り」（2026-10-18・札 #307）
final class CamperModelTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let name = "camper.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// 段は旅の一冊の数で決まる（3 冊でキャンピングカー・10 冊でトレーラーつき）
    func testStageFromBooks() {
        XCTAssertEqual(CamperStage.stage(books: 0), .van)
        XCTAssertEqual(CamperStage.stage(books: 2), .van)
        XCTAssertEqual(CamperStage.stage(books: 3), .camper)
        XCTAssertEqual(CamperStage.stage(books: 9), .camper)
        XCTAssertEqual(CamperStage.stage(books: 10), .trailer)
        XCTAssertEqual(CamperStage.stage(books: 99), .trailer)
    }

    /// 図鑑（板 CamperDex）: 33 分類 × 4 つ = 132 個・id は「分類.部品」（英小文字と _）・珍しさ 32/41/40/19・
    /// 端末だけ 99（うち 1 つは #339 で外したキャンプ場向けの焚き火で近日）／要サーバー 33・いつものは最初から（ルーフテントだけ空き）
    func testDexMatchesTheBoard() {
        let dexCats = CamperCategory.allCases.filter(\.inDex)
        XCTAssertEqual(dexCats.count, 33)
        XCTAssertEqual(CamperCatalog.dex.count, 132)
        for c in dexCats { XCTAssertEqual(CamperCatalog.parts(c).count, 4, c.rawValue) }
        XCTAssertEqual(Set(CamperCatalog.all.map(\.id)).count, CamperCatalog.all.count, "id が重なっている")
        for p in CamperCatalog.dex {
            XCTAssertNotNil(p.id.range(of: "^[a-z_]+\\.[a-z_]+$", options: .regularExpression), p.id)
        }
        let count = { (r: CamperRarity) in CamperCatalog.dex.filter { $0.rarity == r }.count }
        XCTAssertEqual([count(.common), count(.occasional), count(.rare), count(.veryRare)], [32, 41, 40, 19])
        let server = CamperCatalog.dex.filter { if case .server = $0.unlock { return true }; return false }
        XCTAssertEqual(server.count, 33)
        XCTAssertEqual(CamperCatalog.available.count, 98, "端末だけ 99 のうち、キャンプ場向けの焚き火は近日のまま")
        XCTAssertEqual(CamperCatalog.dex.filter { $0.unlock == .starter }.count, 32)
        XCTAssertTrue(CamperCatalog.parts(.roofTent).allSatisfy { $0.unlock != .starter })
        // 図鑑の付箋の対応表
        for id in ["wheel.chrome_dish", "wheel.steel_black", "wheel.brass_spoke", "headlight.rally_brass", "roof_cargo.crate_mat",
                   "roof_cargo.canoe", "awning.indigo_stripe", "awning.rust_stripe", "sticker_edge.signed"] {
            XCTAssertNotNil(CamperCatalog.part(id), id)
        }
        // 塗装は図鑑の数に入れない
        XCTAssertEqual(CamperCatalog.paints.count, 4)
        XCTAssertFalse(CamperCatalog.dex.contains { $0.category == .paint })
    }

    /// 要サーバーの部品は数をいくら重ねても届かない（「近日」）
    func testServerPartsNeverArrive() {
        var s = CamperStats()
        s.posts = 10_000
        s.books = 1000
        s.prefectures = 47
        let owned = CamperCatalog.owned(s)
        XCTAssertFalse(owned.contains("wheel.brass_spoke"))
        XCTAssertFalse(owned.contains("sticker_edge.holo"))
        XCTAssertEqual(CamperUnlock.server("x", "x").fraction(s), 0)
        XCTAssertLessThanOrEqual(CamperCatalog.dexCount(owned).total, 98)
    }

    /// 持っている部品は端末で数えた値で決まる
    func testOwnership() {
        var s = CamperStats()
        let starters = CamperCatalog.owned(s)
        XCTAssertTrue(starters.contains("wheel.chrome_dish"))
        XCTAssertFalse(starters.contains("wheel.steel_black"))
        s.posts = 30
        XCTAssertTrue(CamperCatalog.owned(s).contains("wheel.steel_black"))
        s.earlyShots = 3
        XCTAssertTrue(CamperCatalog.owned(s).contains("headlight.rally_brass"))
        s.books = 10
        XCTAssertTrue(CamperCatalog.owned(s).contains("mirror.tall_tow"), "トレーラーまで育てる")
        XCTAssertEqual(CamperUnlock.posts(30).fraction(CamperStats(posts: 15)), 0.5, accuracy: 1e-9)
    }

    /// 飾りは人ごとに覚え、別の人に替わったら前の人の色を使わない
    func testLoadoutIsPerUser() {
        let d = defaults()
        let a = CamperStore(userId: "a", defaults: d)
        var l = CamperLoadout.standard
        l.pick(CamperCatalog.part("paint.mist")!)
        l.awningOpen = true
        a.save(l)
        XCTAssertEqual(CamperStore(userId: "a", defaults: d).load(), l)
        XCTAssertEqual(CamperStore(userId: "b", defaults: d).load(), .standard, "別の人に前の人の飾りが出た")
        XCTAssertEqual(CamperStore(userId: nil, defaults: d).load(), .standard)
        // 退会で消える
        CamperStore.removeData(for: "a", defaults: d)
        XCTAssertEqual(CamperStore(userId: "a", defaults: d).load(), .standard)
    }

    /// 持っていない部品は覚えていても付けない（最初の部品・付けないに戻す）
    func testSanitizeDropsLockedParts() {
        var l = CamperLoadout.standard
        l.pick(CamperCatalog.part("wheel.brass_spoke")!)
        l.pick(CamperCatalog.part("roof_tent.wing")!)
        let owned = CamperCatalog.owned(CamperStats())
        let clean = l.sanitized(owned: owned)
        XCTAssertEqual(clean.key(.wheel), "chrome_dish")
        XCTAssertEqual(clean.key(.roofTent), CamperLoadout.none)
        XCTAssertNil(clean.pickedPart(.roofTent))
    }

    /// 届いた部品: 見せた印より後に増えたものだけ・最初から持つ部品は出さない・珍しい順
    func testArrivals() {
        var s = CamperStats()
        s.posts = 30
        s.earlyShots = 3
        let owned = CamperCatalog.owned(s)
        let arrivals = CamperStore.arrivals(owned: owned, seen: CamperCatalog.owned(CamperStats()))
        XCTAssertFalse(arrivals.isEmpty)
        XCTAssertFalse(arrivals.contains { $0.unlock == .starter })
        XCTAssertEqual(arrivals.first?.id, "headlight.rally_brass", "いちばん珍しいものが先")
        XCTAssertTrue(CamperStore.arrivals(owned: owned, seen: owned).isEmpty)
        let d = defaults()
        let store = CamperStore(userId: "me", defaults: d)
        XCTAssertNil(store.seen)
        store.markSeen(owned)
        XCTAssertEqual(store.seen, owned)
    }

    /// 投稿から数える（夜・朝・季節・都道府県・場所・同じ場所・山と海・満月）
    func testCountingFromPhotos() throws {
        func photo(_ id: String, exif: String?, location: String?, lat: Double? = nil, color: String? = nil) throws -> Photo {
            var json: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg"]
            if let exif { json["exif"] = ["dateTimeOriginal": exif] }
            if let location { json["location"] = location }
            if let lat { json["coords"] = ["lat": lat, "lng": 135.0] }
            if let color { json["dominantColor"] = color }
            return try JSONDecoder().decode(Photo.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let photos = [
            // 2024-09-18 は満月（中秋の名月の翌日）。山の夜
            try photo("1", exif: "2024:09:18 21:10:00", location: "長野県 八ヶ岳", lat: 35.0, color: "#2f6a30"),
            // 同じ日に海辺
            try photo("2", exif: "2024:09:18 05:20:00", location: "神奈川県鎌倉市 由比ヶ浜", lat: 35.0, color: "#6f9fd8"),
            try photo("3", exif: "2024-12-10T08:00", location: "京都府京都市", lat: 35.0),
            try photo("4", exif: nil, location: "沖縄県 那覇市", lat: 26.2),
        ]
        let s = CamperCounting.stats(photos: photos, books: 2)
        XCTAssertEqual(s.posts, 4)
        XCTAssertEqual(s.books, 2)
        XCTAssertEqual(s.nightShots, 1)
        XCTAssertEqual(s.earlyShots, 1)
        XCTAssertEqual(s.morningShots, 2)
        XCTAssertEqual(s.winterShots, 1)
        XCTAssertEqual(s.prefectures, 4)
        XCTAssertEqual(s.places, 2)
        XCTAssertEqual(s.samePlace, 3)
        XCTAssertEqual(s.forestShots, 1)
        XCTAssertEqual(s.skyShots, 1)
        XCTAssertEqual(s.mountainShots, 1)
        XCTAssertEqual(s.seaShots, 1)
        XCTAssertEqual(s.seaAndMountainDays, 1)
        XCTAssertEqual(s.fullMoonShots, 1)
        XCTAssertEqual(s.southIslandShots, 1)
        // 2024 年 9 月と 12 月は続いていない（続いた月の最長は 1）
        XCTAssertEqual(s.months, 1)
        XCTAssertEqual(CamperCounting.prefecture(in: "神奈川県"), "神奈川", "奈良に当たっている")
        XCTAssertFalse(CamperCounting.isFullMoon(year: 2024, month: 10, day: 2), "新月の日を満月と数えた")
    }

    func testPlateNumber() {
        XCTAssertEqual(CamperCounting.plateNumber(8), "・・・8")
        XCTAssertEqual(CamperCounting.plateNumber(18), "・・18")
        XCTAssertEqual(CamperCounting.plateNumber(1234), "12-34")
    }

    /// 読み上げで車の様子が言葉になる
    func testAccessibilityLabel() {
        var l = CamperLoadout.standard
        l.awningOpen = true
        l.pick(CamperCatalog.part("chair.director_chair")!)
        let text = CamperText.accessibilityLabel(stage: .camper, mood: .night, loadout: l, doorOpen: true, preview: nil)
        XCTAssertTrue(text.contains("キャンピングカー") || text.contains("Camper"))
        XCTAssertTrue(text.contains("ディレクターズ") || text.contains("Director chair"))
        XCTAssertTrue(text.contains("扉が開いている") || text.contains("Door open"))
    }

    private func photo(_ id: String, exif: String? = nil, location: String? = nil, title: String? = nil,
                       published: Bool? = nil) throws -> Photo {
        var json: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg"]
        if let exif { json["exif"] = ["dateTimeOriginal": exif] }
        if let location { json["location"] = location }
        if let title { json["title"] = title }
        if let published { json["published"] = published }
        return try JSONDecoder().decode(Photo.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// 下書き（published == false）は数えない。公開・不明（古い投稿）は数える（#312 の見直し）
    func testDraftsAreNotCounted() throws {
        let photos = [try photo("a", exif: "2024:05:01 21:00:00", location: "長野県 八ヶ岳", published: true),
                      try photo("b", exif: "2024:05:02 21:00:00", location: "長野県 八ヶ岳"),
                      try photo("draft", exif: "2024:05:03 21:00:00", location: "長野県 八ヶ岳", published: false)]
        let s = CamperCounting.count(photos)
        XCTAssertEqual(s.posts, 2, "下書きを数えた")
        XCTAssertEqual(s.nightShots, 2)
        XCTAssertEqual(s.mountainShots, 2)
        XCTAssertEqual(CamperCounting.stats(photos: photos, books: 0).posts, 2)
        XCTAssertEqual(CamperCounting.count([try photo("d", published: false)]).posts, 0)
    }

    /// 地名の中の「山・海・浜・港」に当たらない（北海道・岡山・富山・山形・山口・山梨・和歌山・横浜・浜松・港区）
    func testPlaceNamesAreNotNature() throws {
        for loc in ["北海道札幌市", "岡山県岡山市", "富山県富山市", "山形県", "山口県下関市", "山梨県甲府市", "和歌山県",
                    "神奈川県横浜市", "静岡県浜松市", "東京都港区"] {
            let s = CamperCounting.count([try photo(loc, location: loc)])
            XCTAssertEqual(s.mountainShots, 0, loc)
            XCTAssertEqual(s.seaShots, 0, loc)
        }
        // 地名を外しても、景色の言葉は残る
        XCTAssertEqual(CamperCounting.count([try photo("1", location: "北海道 羊蹄山")]).mountainShots, 1)
        XCTAssertEqual(CamperCounting.count([try photo("2", location: "静岡県浜松市 中田島の浜")]).seaShots, 1)
        XCTAssertEqual(CamperCounting.count([try photo("3", location: "富山県 富山湾")]).seaShots, 1)
    }

    /// 「海と山を同じ日」は別々の写真に限る（1 枚が海と山の両方に当たるだけでは数えない）
    func testSeaAndMountainNeedTwoPhotos() throws {
        let both = try photo("both", exif: "2024:07:01 10:00:00", location: "鳥取県 大山と日本海")
        XCTAssertEqual(CamperCounting.count([both]).seaAndMountainDays, 0)
        let sea = try photo("sea", exif: "2024:07:01 15:00:00", location: "鳥取県 白兎海岸")
        XCTAssertEqual(CamperCounting.count([both, sea]).seaAndMountainDays, 1)
        let mountainOnly = try photo("m", exif: "2024:07:02 09:00:00", location: "長野県 槍ヶ岳")
        let seaOtherDay = try photo("s", exif: "2024:07:03 09:00:00", location: "神奈川県 七里ヶ浜")
        XCTAssertEqual(CamperCounting.count([mountainOnly, seaOtherDay]).seaAndMountainDays, 0)
    }

    /// 「一年続けて撮る」は続いた 12 か月（年をまたいでもよい・飛んだら数え直し）
    func testMonthsInARow() throws {
        func run(_ months: [(Int, Int)]) throws -> Int {
            try CamperCounting.count(months.enumerated().map { i, ym in
                try photo("p\(i)", exif: String(format: "%04d:%02d:15 12:00:00", ym.0, ym.1))
            }).months
        }
        let year = (0..<12).map { k in (2023 + (k + 4) / 12, (k + 4) % 12 + 1) }  // 2023-05 〜 2024-04
        XCTAssertEqual(try run(year), 12)
        XCTAssertTrue(CamperUnlock.months(12).isMet({ var s = CamperStats(); s.months = 12; return s }()))
        // 12 個の月でも、続いていなければ届かない（2023 年の 6 か月と 2025 年の 6 か月）
        let split = (1...6).map { (2023, $0) } + (1...6).map { (2025, $0) }
        XCTAssertEqual(try run(split), 6)
        XCTAssertEqual(CamperCounting.longestMonthRun([]), 0)
    }

    /// 写真を読む前に開いても、飾りは消えず「届いた」も出し直さない。印は前の印との和集合（#312 の見直し）
    func testArrivalsWaitForPhotos() {
        let d = defaults()
        let store = CamperStore(userId: "me", defaults: d)
        var many = CamperStats()
        many.posts = 30
        many.earlyShots = 3
        let owned = CamperCatalog.owned(many)
        store.markSeen(owned)
        // 写真を読む前（数は 0）: 判定しない・印を消さない
        XCTAssertTrue(store.openArrivals(owned: CamperCatalog.owned(CamperStats()), photosLoaded: false).isEmpty)
        XCTAssertEqual(store.seen, owned)
        // 読めた後: 前に見せたものは出し直さない
        XCTAssertTrue(store.openArrivals(owned: owned, photosLoaded: true).isEmpty)
        // 一時的に数が減っても（読み直しの途中など）、印は減らない
        _ = store.openArrivals(owned: CamperCatalog.owned(CamperStats()), photosLoaded: true)
        XCTAssertEqual(store.seen, owned)
        // 選んだ部品は、持っていない間も保存の値から外さない（見せる時だけ外す）
        var l = CamperLoadout.standard
        l.pick(CamperCatalog.part("wheel.steel_black")!)
        store.save(l)
        XCTAssertEqual(store.load().key(.wheel), "steel_black")
        XCTAssertEqual(store.load().sanitized(owned: CamperCatalog.owned(CamperStats())).key(.wheel), "chrome_dish")
        XCTAssertEqual(store.load().key(.wheel), "steel_black", "見せるために外した値が保存に残った")
    }

    /// 部品の名前・説明・要サーバーの条件に英語がある。言葉は読むたびに選ぶ（一覧を作った時の言語で固めない）
    func testPartsHaveEnglish() {
        for p in CamperCatalog.all {
            XCTAssertFalse(p.nameEn.isEmpty, p.id)
            XCTAssertFalse(p.lookEn.isEmpty, p.id)
            XCTAssertNil(p.nameEn.range(of: "[ぁ-んァ-ン一-龥]", options: .regularExpression), p.id)
            XCTAssertNil(p.lookEn.range(of: "[ぁ-んァ-ン一-龥]", options: .regularExpression), p.id)
            XCTAssertNotEqual(p.lookEn, p.nameEn, "\(p.id): 説明が名前のまま")
            XCTAssertEqual(p.name, L(p.nameJa, p.nameEn))
            XCTAssertEqual(p.look, L(p.lookJa, p.lookEn))
            switch p.unlock {
            case let .server(ja, en), let .later(ja, en):
                XCTAssertFalse(ja.isEmpty, p.id)
                XCTAssertNil(en.range(of: "[ぁ-んァ-ン一-龥]", options: .regularExpression), p.id)
                XCTAssertEqual(p.unlock.condition, L(ja, en))
            default: break
            }
        }
        let source = (try? String(contentsOfFile: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Core/Camper/CamperCatalog.swift").path, encoding: .utf8)) ?? ""
        XCTAssertTrue(source.contains("var name: String { L(nameJa, nameEn) }"), "名前を作った時の言語で固めている")
    }

    /// 開いた時は保存した値をそのまま持ち、持っていない部品も保存から外さない。見せる時だけ外す（#312 の見直し）
    func testEditorKeepsSavedPicks() {
        let d = defaults()
        let store = CamperStore(userId: "me", defaults: d)
        var saved = CamperLoadout.standard
        saved.pick(CamperCatalog.part("wheel.steel_black")!)
        store.save(saved)
        let none = CamperCatalog.owned(CamperStats())
        var editor = CamperGarageEditor()
        editor.open(store)
        XCTAssertEqual(editor.loadout.key(.wheel), "steel_black", "開いた時に保存の値を外した")
        XCTAssertEqual(editor.worn(owned: none).key(.wheel), "chrome_dish")
        // 別の分類を付け替えて保存しても、持っていない間のホイールは保存に残る
        XCTAssertTrue(editor.equip(CamperCatalog.part("paint.mist")!, owned: none, store: store))
        XCTAssertEqual(store.load().key(.wheel), "steel_black")
        XCTAssertEqual(store.load().key(.paint), "mist")
        // 持っていない部品は付けない
        XCTAssertFalse(editor.equip(CamperCatalog.part("wheel.brass_spoke")!, owned: none, store: store))
        XCTAssertEqual(store.load().key(.wheel), "steel_black")
        // 見せるためにオーニングを広げても保存しない
        editor.setAwning(true, store: nil)
        XCTAssertFalse(store.load().awningOpen)
        editor.remove(.roofTent, store: store)
        XCTAssertEqual(store.load().key(.wheel), "steel_black")
    }

    /// 数え直しの目印: 公開と下書きの切り替え・撮影地の直し・間の 1 枚の入れ替え・読めたかで変わる
    func testCountKeyNoticesEdits() throws {
        let a = try photo("a", exif: "2024:05:01 10:00:00", location: "長野県"), b = try photo("b", location: "京都府")
        let c = try photo("c", location: "沖縄県")
        let base = CamperCounting.countKey([a, b, c], loaded: true)
        XCTAssertEqual(base, CamperCounting.countKey([a, b, c], loaded: true))
        XCTAssertNotEqual(base, CamperCounting.countKey([a, b, c], loaded: false))
        XCTAssertNotEqual(base, CamperCounting.countKey([a, try photo("b", location: "京都府", published: false), c], loaded: true))
        XCTAssertNotEqual(base, CamperCounting.countKey([a, try photo("b", location: "大阪府"), c], loaded: true))
        XCTAssertNotEqual(base, CamperCounting.countKey([a, try photo("x", location: "京都府"), c], loaded: true))
        XCTAssertNotEqual(base, CamperCounting.countKey([a, try photo("b", location: "京都府", title: "海"), c], loaded: true))
    }
}

/// 画面のつなぎ（画面は Linux で動かせないので、書き方を見張る）
final class CamperWiringTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        return text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
    }

    /// 入口: マイページの旅の道具の札（トランクの行と同じ形）。数は投稿から端末で数える
    func testEntryOnMyPage() throws {
        let page = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        XCTAssertTrue(page.contains("CamperGarageView(ownerName: model.profile?.name, userId: auth.userId, photos: model.photos,"))
        XCTAssertTrue(page.contains("photosLoaded: model.hasLoadedPhotos)"))
        // マイページを描き直すたびに数えない（数えるのは行き先の中・#312 の見直し）
        XCTAssertFalse(page.contains("CamperCounting.stats("))
        XCTAssertFalse(page.contains("CamperCounting.count("))
        let garage = try source("Sources/JourneyPhoto/Features/Camper/CamperGarageView.swift")
        XCTAssertTrue(garage.contains("stats = CamperCounting.count(photos)"))
        XCTAssertTrue(page.contains(".accessibilityIdentifier(\"trips.camper\")"))
    }

    /// 退会で飾りを消す
    func testAccountRemovalForgetsCamper() throws {
        let data = try source("Sources/JourneyPhoto/Core/Storage/AccountLocalData.swift")
        XCTAssertTrue(data.contains("CamperStore.removeData(for: userId, defaults: defaults)"))
    }

    /// SceneKit: 板の指定（physicallyBased・clearCoat・SCNFloor の映り込み・太陽の落ち影・まとめて描く）
    func testSceneKitFollowsTheBoard() throws {
        // 素材を SceneKit に写す所は `CamperScenePalette` に切り出した（2026-10-19・とおまわり号の中と共に使う）
        let scene = try source("Sources/JourneyPhoto/Features/Camper/CamperScene.swift")
            + source("Sources/JourneyPhoto/Features/Camper/CamperScenePalette.swift")
        for needle in [".physicallyBased", "clearCoat.contents", "SCNFloor()", "castsShadow = true", "flattenedClone()",
                       "reflectivity", "lightingEnvironment", "CamperScenePlan.make(next)", "Task.detached"] {
            XCTAssertTrue(scene.contains(needle), needle)
        }
        let view = try source("Sources/JourneyPhoto/Features/Camper/CamperGarageView.swift")
        XCTAssertTrue(view.contains("accessibilityReduceMotion"), "視差効果を減らすを見ていない")
        // 付け外しは CamperGarageEditor を通す（保存する値を外さない・持っていない部品を付けない）
        XCTAssertTrue(view.contains("editor.open(store)"))
        XCTAssertTrue(view.contains("guard editor.equip(part, owned: owned, store: store) else { return }"))
        XCTAssertFalse(view.contains(".sanitized("), "画面で保存する値を外している")
        XCTAssertFalse(view.contains("store.save("), "画面が editor を通さずに保存している")
        XCTAssertTrue(view.contains("L(\"公開した旅\", \"Public trips\")"))
    }

    /// 画面写真の試験に昼・夜・3 段がある
    func testScreenshotsCoverCamper() throws {
        let ui = try source("UITests/JourneyPhotoUITests/ScreenshotTests.swift")
        for name in ["95-写真で作るキャンピングカー（昼）", "95b-写真で作るキャンピングカー（夜）", "95c-キャンピングカー（バン）",
                     "95d-キャンピングカー（キャンピングカー）", "95e-キャンピングカー（トレーラーつき）"] {
            XCTAssertTrue(ui.contains(name), name)
        }
    }

    /// 見出しの眉ラベル: 名前と「の車」の間を空けない。名前を入れていない人（「ユーザー」）には名前を出さない
    /// （2026-10-18 Mac の絵 run 529 で「ユーザー の車」と出ていた）
    func testEyebrowName() {
        let named = CamperText.eyebrow(owner: "旅人", stage: .camper)
        XCTAssertEqual(named, L("旅人の車 · キャンピングカー", "旅人\u{2019}s camper · Camper"))
        XCTAssertFalse(named.contains(" の車"), "名前と「の車」の間が空いている")
        for none in [nil, "", "  ", "ユーザー", "User", Labels.Common.unnamedUser] {
            let text = CamperText.eyebrow(owner: none, stage: .camper)
            XCTAssertEqual(text, L("わたしの車 · キャンピングカー", "My camper · Camper"), String(describing: none))
            XCTAssertFalse(text.contains("ユーザー") || text.contains("User"))
        }
    }

    /// 図鑑は 132（塗装は別）。分母は第1段で集められる数で、残りは「近日」と書いて見せる
    func testDexNoteShows132() {
        let soon = 132 - CamperCatalog.available.count
        XCTAssertEqual(CamperText.dexNote(), L("図鑑 132 · 近日 \(soon)", "Dex 132 · \(soon) soon"))
        XCTAssertEqual(soon, 34)
    }

    /// 車の名前は「とおまわり号」（英語 Detour・owner の決定）。見出しと部品の一覧に出て、眉ラベルの形は変えない
    func testCarNameIsDetour() throws {
        XCTAssertEqual(CamperText.carName, L("とおまわり号", "Detour"))
        XCTAssertEqual(CamperText.partsTitle, L("とおまわり号の部品", "Detour\u{2019}s parts"))
        XCTAssertEqual(CamperText.eyebrow(owner: nil, stage: .camper), L("わたしの車 · キャンピングカー", "My camper · Camper"))
        let view = try source("Sources/JourneyPhoto/Features/Camper/CamperGarageView.swift")
        XCTAssertTrue(view.contains("Text(CamperText.carName)"))
        XCTAssertTrue(view.contains("Text(CamperText.partsTitle)"))
        XCTAssertFalse(view.contains("ひかり号"))
    }

    /// SCNView の描き方の設定は、炎の揺らぎで切り替えない（切り替えた直後の数枚が描き直されず、夜に替えても昼の絵が
    /// 残った・Mac run 547 の 95b）。止まっている間は動いた時だけ描き、揺らぎ（SCNAction）は動きとして描き直される
    func testSceneViewKeepsRenderingSettings() throws {
        let view = try source("Sources/JourneyPhoto/Features/Camper/CamperSceneView.swift")
        XCTAssertEqual(view.components(separatedBy: "rendersContinuously =").count - 1, 1, "描き続けるかを途中で切り替えている")
        XCTAssertTrue(view.contains("view.rendersContinuously = false"))
        XCTAssertEqual(view.components(separatedBy: "preferredFramesPerSecond =").count - 1, 1)
    }
}
