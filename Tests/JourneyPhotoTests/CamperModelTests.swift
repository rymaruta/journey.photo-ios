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

    /// 一覧: 31 分類・各 4 種類以上・id は重ならない・珍しさは「いつもの」が多く「とても珍しい」が少ない
    func testCatalogShape() {
        XCTAssertGreaterThanOrEqual(CamperCategory.allCases.count, 18)
        XCTAssertGreaterThanOrEqual(CamperCatalog.all.count, 80)
        for c in CamperCategory.allCases {
            XCTAssertGreaterThanOrEqual(CamperCatalog.parts(c).count, 4, c.rawValue)
            if !c.optional {
                XCTAssertGreaterThanOrEqual(CamperCatalog.parts(c).filter { $0.unlock == .starter }.count, 1, "\(c) に最初から持つ部品が無い")
            }
        }
        XCTAssertEqual(Set(CamperCatalog.all.map(\.id)).count, CamperCatalog.all.count, "id が重なっている")
        let count = { (r: CamperRarity) in CamperCatalog.all.filter { $0.rarity == r }.count }
        XCTAssertGreaterThan(count(.common), count(.occasional))
        XCTAssertGreaterThan(count(.occasional), count(.rare))
        XCTAssertGreaterThan(count(.rare), count(.veryRare))
        XCTAssertGreaterThan(count(.veryRare), 0)
    }

    /// 持っている部品は端末で数えた値で決まる
    func testOwnership() {
        var s = CamperStats()
        let starters = CamperCatalog.owned(s)
        XCTAssertTrue(starters.contains("wheel.chrome"))
        XCTAssertFalse(starters.contains("wheel.steel"))
        s.posts = 30
        XCTAssertTrue(CamperCatalog.owned(s).contains("wheel.steel"))
        s.earlyShots = 3
        XCTAssertTrue(CamperCatalog.owned(s).contains("light.rally"))
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
        l.pick(CamperCatalog.part("wheel.deep")!)
        l.pick(CamperCatalog.part("chair.hammock")!)
        let owned = CamperCatalog.owned(CamperStats())
        let clean = l.sanitized(owned: owned)
        XCTAssertEqual(clean.key(.wheel), "chrome")
        XCTAssertEqual(clean.key(.chair), CamperLoadout.none)
        XCTAssertNil(clean.pickedPart(.chair))
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
        XCTAssertEqual(arrivals.first?.id, "light.rally", "いちばん珍しいものが先")
        XCTAssertTrue(CamperStore.arrivals(owned: owned, seen: owned).isEmpty)
        let d = defaults()
        let store = CamperStore(userId: "me", defaults: d)
        XCTAssertNil(store.seen)
        store.markSeen(owned)
        XCTAssertEqual(store.seen, owned)
    }

    /// 投稿から数える（夜・朝・季節・都道府県・同じ場所・日）
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
            try photo("1", exif: "2024:12:24 21:10:00", location: "京都府京都市", lat: 35.0, color: "#2f6a30"),
            try photo("2", exif: "2024:07:01 05:20:00", location: "長野県松本市", lat: 35.0, color: "#6f9fd8"),
            try photo("3", exif: "2024-04-10T12:00", location: "神奈川県鎌倉市", lat: 35.0),
            try photo("4", exif: nil, location: "東京都", lat: 36.0),
        ]
        let s = CamperCounting.stats(photos: photos, books: 2)
        XCTAssertEqual(s.posts, 4)
        XCTAssertEqual(s.books, 2)
        XCTAssertEqual(s.nightShots, 1)
        XCTAssertEqual(s.earlyShots, 1)
        XCTAssertEqual(s.winterShots, 1)
        XCTAssertEqual(s.summerShots, 1)
        XCTAssertEqual(s.springShots, 1)
        XCTAssertEqual(s.prefectures, 4)
        XCTAssertEqual(s.samePlace, 3)
        XCTAssertEqual(s.forestShots, 1)
        XCTAssertEqual(s.skyShots, 1)
        XCTAssertEqual(s.days, 3)
        XCTAssertEqual(CamperCounting.prefecture(in: "神奈川県"), "神奈川", "奈良に当たっている")
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
        l.pick(CamperCatalog.part("chair.canvas")!)
        let text = CamperText.accessibilityLabel(stage: .camper, mood: .night, loadout: l, doorOpen: true, preview: nil)
        XCTAssertTrue(text.contains("キャンピングカー") || text.contains("Camper"))
        XCTAssertTrue(text.contains("帆布の椅子") || text.contains("Canvas chair"))
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
}
