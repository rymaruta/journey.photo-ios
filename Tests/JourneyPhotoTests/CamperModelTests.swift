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
    /// 端末だけ 99（うち 1 つはキャンプ場が出来てから）／要サーバー 33・いつものは最初から（ルーフテントだけ空き）
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
        XCTAssertEqual(CamperCatalog.available.count, 98, "端末だけ 99 のうち、キャンプ場の焚き火はキャンプ場ができてから")
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
        XCTAssertEqual(CamperUnlock.server("x").fraction(s), 0)
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
        XCTAssertEqual(s.months, 2)
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
        XCTAssertTrue(page.contains("CamperGarageView(ownerName: model.profile?.name, userId: auth.userId,"))
        XCTAssertTrue(page.contains("CamperCounting.stats(photos: model.photos, books: TripBook.shelfTrips(from: model.photos).count)"))
        XCTAssertTrue(page.contains(".accessibilityIdentifier(\"trips.camper\")"))
    }

    /// 退会で飾りを消す
    func testAccountRemovalForgetsCamper() throws {
        let data = try source("Sources/JourneyPhoto/Core/Storage/AccountLocalData.swift")
        XCTAssertTrue(data.contains("CamperStore.removeData(for: userId, defaults: defaults)"))
    }

    /// SceneKit: 板の指定（physicallyBased・clearCoat・SCNFloor の映り込み・太陽の落ち影・まとめて描く）
    func testSceneKitFollowsTheBoard() throws {
        let scene = try source("Sources/JourneyPhoto/Features/Camper/CamperScene.swift")
        for needle in [".physicallyBased", "clearCoat.contents", "SCNFloor()", "castsShadow = true", "flattenedClone()",
                       "reflectivity", "lightingEnvironment", "CamperBuilder.build(next)", "Task.detached"] {
            XCTAssertTrue(scene.contains(needle), needle)
        }
        let view = try source("Sources/JourneyPhoto/Features/Camper/CamperGarageView.swift")
        XCTAssertTrue(view.contains("accessibilityReduceMotion"), "視差効果を減らすを見ていない")
        XCTAssertTrue(view.contains("store.save(loadout)"))
        XCTAssertTrue(view.contains("guard owned.contains(part.id) else { return }"), "持っていない部品を付けられる")
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
}
