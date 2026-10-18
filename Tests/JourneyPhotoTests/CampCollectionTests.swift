import XCTest
@testable import JourneyPhoto

/// 集める決まり（端末だけで判定 79・要サーバーは「近日」で数えない）と、キャンプ場の中身の入れ物
final class CampCollectionTests: XCTestCase {

    private var tokyo: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        tokyo.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func shot(_ i: Int, at: Date, subjects: [CampSubject] = [], pref: String? = nil, loc: String? = nil,
                      alt: Double? = nil, people: Bool = false) -> CampShot {
        CampShot(id: "s\(i)", takenAt: at, latitude: nil, longitude: nil, altitude: alt, prefecture: pref, locality: loc,
                 subjects: subjects, hasPeople: people)
    }

    func testStartsWithTheTwentyThreeCommons() {
        let owned = CampCollection.owned(shots: [], calendar: tokyo)
        XCTAssertEqual(owned, Set(CampCatalog.starters.map(\.id)))
        let tally = CampCollection.tally(owned: owned)
        XCTAssertEqual(tally.owned, 23)
        XCTAssertEqual(tally.total, 79, "要サーバーの 17 は数から外す")
    }

    func testPhotoCountAndPeopleAreNotCounted() {
        let base = date(2026, 7, 1)
        var shots = (0..<39).map { shot($0, at: base.addingTimeInterval(Double($0) * 3600)) }
        shots.append(shot(99, at: base, people: true))
        XCTAssertFalse(CampCollection.owned(shots: shots, calendar: tokyo).contains("camp.tarp.diamond"), "人の写った写真まで数えた")
        shots.append(shot(100, at: base))
        XCTAssertTrue(CampCollection.owned(shots: shots, calendar: tokyo).contains("camp.tarp.diamond"))
        XCTAssertEqual(CampCollection.progress(.photos(40), shots: shots, calendar: tokyo), CampProgress(current: 40, target: 40))
    }

    func testSubjectsSeasonsAndTimes() {
        let forest = (0..<10).map { shot($0, at: date(2026, 10, 1 + $0), subjects: [.forest]) }
        XCTAssertTrue(CampCollection.owned(shots: forest, calendar: tokyo).contains("camp.firewood.log_round"))
        // 秋の森の写真 5 枚（10 月の森）
        XCTAssertTrue(CampCollection.owned(shots: forest, calendar: tokyo).contains("camp.flora.mushrooms"))
        // 春の森では数えない
        let spring = (0..<5).map { shot($0, at: date(2026, 4, 1 + $0), subjects: [.forest]) }
        XCTAssertFalse(CampCollection.owned(shots: spring, calendar: tokyo).contains("camp.flora.mushrooms"))
        // 夜明け前（4 時）3 枚
        let predawn = (0..<3).map { shot($0, at: date(2026, 5, 1 + $0, 4)) }
        XCTAssertTrue(CampCollection.owned(shots: predawn, calendar: tokyo).contains("camp.cookware.percolator"))
        // 海辺の夕方（17 時）
        let sea = (0..<5).map { shot($0, at: date(2026, 8, 1 + $0, 17), subjects: [.seaside]) }
        XCTAssertTrue(CampCollection.owned(shots: sea, calendar: tokyo).contains("camp.torch.tiki"))
        let seaNoon = (0..<5).map { shot($0, at: date(2026, 8, 1 + $0, 12), subjects: [.seaside]) }
        XCTAssertFalse(CampCollection.owned(shots: seaNoon, calendar: tokyo).contains("camp.torch.tiki"))
    }

    /// 満月の夜（2024-01-25 は満月・2024-01-11 は新月）
    func testFullMoonNight() {
        XCTAssertTrue(CampMoon.isFull(at: date(2024, 1, 25, 21)))
        XCTAssertFalse(CampMoon.isFull(at: date(2024, 1, 11, 21)))
        XCTAssertTrue(CampCollection.owned(shots: [shot(1, at: date(2024, 1, 25, 21))], calendar: tokyo)
            .contains("camp.lantern.candle_brass"))
        // 満月の日でも昼は数えない
        XCTAssertFalse(CampCollection.owned(shots: [shot(1, at: date(2024, 1, 25, 12))], calendar: tokyo)
            .contains("camp.lantern.candle_brass"))
    }

    /// 一年続けて撮る: 12 か月続けて（年をまたいでよい）。1 か月抜けたら数え直し
    func testYearRound() {
        let start = date(2025, 6, 10)
        let year = (0..<12).map { shot($0, at: tokyo.date(byAdding: .month, value: $0, to: start)!) }
        XCTAssertEqual(CampCollection.longestMonthStreak(year, calendar: tokyo), 12)
        XCTAssertTrue(CampCollection.owned(shots: year, calendar: tokyo).contains("camp.torch.iron_basket"))
        let gap = year.enumerated().filter { $0.offset != 5 }.map(\.element)
        XCTAssertLessThan(CampCollection.longestMonthStreak(gap, calendar: tokyo), 12)
    }

    func testPlacesPrefecturesAndSamePlace() {
        let prefs = ["北海道", "青森県", "岩手県", "宮城県", "秋田県"]
        let five = prefs.enumerated().map { shot($0.offset, at: date(2026, 6, 1), pref: $0.element, loc: "町\($0.offset)") }
        XCTAssertTrue(CampCollection.owned(shots: five, calendar: tokyo).contains("camp.sign.arrow_post"), "撮影地 5 か所")
        XCTAssertEqual(CampCollection.progress(.prefectures(15), shots: five, calendar: tokyo).current, 5)
        let same = (0..<5).map { shot($0, at: date(2026, 6, 1 + $0), pref: "長野県", loc: "白馬村") }
        XCTAssertTrue(CampCollection.owned(shots: same, calendar: tokyo).contains("camp.water.spring_well"), "同じ場所で 5 回")
        XCTAssertEqual(CampCollection.progress(.places(8), shots: same, calendar: tokyo).current, 1)
        // 地名が無くても緯度経度の升目で同じ場所に数える
        var a = shot(1, at: date(2026, 1, 1)); a.latitude = 35.001; a.longitude = 138.001
        var b = shot(2, at: date(2026, 1, 2)); b.latitude = 35.004; b.longitude = 138.006
        XCTAssertEqual(CampCollection.placeKey(a), CampCollection.placeKey(b))
    }

    func testAltitude() {
        let high = (0..<5).map { shot($0, at: date(2026, 8, 1), alt: 1200) }
        let owned = CampCollection.owned(shots: high, calendar: tokyo)
        XCTAssertTrue(owned.contains("camp.tree.birch"))
        XCTAssertFalse(owned.contains("camp.rock.stacked_cairn"), "1200m は山頂ではない")
        XCTAssertTrue(CampCollection.owned(shots: [shot(1, at: date(2026, 8, 1), alt: 3000)], calendar: tokyo)
            .contains("camp.rock.stacked_cairn"))
    }

    /// 要サーバーの部品は、どれだけ撮っても持てない（サーバーの口ができるまで「近日」）
    func testServerPartsNeverUnlock() {
        let lots = (0..<400).map { i in
            shot(i, at: date(2024 + i / 120, 1 + (i / 10) % 12, 1 + i % 28, [4, 7, 12, 17, 21][i % 5]),
                 subjects: CampSubject.allCases, pref: "県\(i % 30)", loc: "町\(i % 30)", alt: 3000)
        }
        let owned = CampCollection.owned(shots: lots + [shot(999, at: date(2024, 1, 25, 21))], calendar: tokyo)
        for part in CampCatalog.allParts where part.needsServer {
            XCTAssertFalse(owned.contains(part.id), part.id)
            XCTAssertEqual(CampPartState.of(part, owned: owned), .comingSoon)
        }
        XCTAssertEqual(CampCollection.tally(owned: owned).owned, 79, "端末だけの 79 は全部集まる")
    }

    func testDexFilters() {
        let owned: Set<String> = ["camp.tent.ridge_canvas", "camp.tent.dome"]
        let unseen: Set<String> = ["camp.tent.dome"]
        let tent = CampCatalog.categories[0].parts
        XCTAssertEqual(tent.filter { CampDexFilter.owned.includes($0, owned: owned, unseen: unseen) }.count, 2)
        XCTAssertEqual(tent.filter { CampDexFilter.missing.includes($0, owned: owned, unseen: unseen) }.count, 2)
        XCTAssertEqual(tent.filter { CampDexFilter.new.includes($0, owned: owned, unseen: unseen) }.map(\.key), ["dome"])
        XCTAssertEqual(tent.filter { CampDexFilter.rarity(.epic).includes($0, owned: owned, unseen: unseen) }.map(\.key), ["bell"])
    }

    // MARK: - 入れ物

    @MainActor
    func testStorePlacesAndGrows() async {
        let store = CampStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                              persists: false)
        XCTAssertEqual(store.stage, .fire)
        let layers = CampLayerSplit.fallback(unitHeight: 480)
        for i in 0..<6 {
            let s = CampShot(id: "s\(i)", takenAt: Date(), subjects: [.forest])
            let c = CampCutoutRecord(id: "c\(i)", shotId: s.id, layers: layers, spot: i % 3, title: "森", place: nil,
                                     takenAt: Date(), createdAt: Date(timeIntervalSince1970: Double(i)))
            store.add(shot: s, cutout: c, layerImages: [], photo: nil, sky: nil)
            if i == 0 { XCTAssertEqual(store.stage, .tent, "1 枚目でテント場") }
        }
        XCTAssertEqual(store.stage, .camp)
        XCTAssertEqual(store.placed.map(\.id), ["c3", "c4", "c5"], "置き場所ごとに新しい 1 つ")
        store.place("c5", spot: nil)
        XCTAssertEqual(store.placed.map(\.id), ["c3", "c4", "c2"])
        XCTAssertEqual(store.stage, .tent, "あとで置くにした切り絵は育ちに数えない")
    }

    @MainActor
    func testStoreNewPartsAndName() async {
        let store = CampStore(directory: FileManager.default.temporaryDirectory, persists: false)
        XCTAssertTrue(store.unseen.isEmpty, "最初からの部品は新着にしない")
        for i in 0..<10 {
            store.add(shot: CampShot(id: "f\(i)", takenAt: Date(), subjects: [.forest]), cutout: nil, layerImages: [],
                      photo: nil, sky: nil)
        }
        XCTAssertTrue(store.unseen.contains("camp.firewood.log_round"))
        store.markSeen()
        XCTAssertTrue(store.unseen.isEmpty)
        store.rename("  ひかり野営地  ")
        XCTAssertEqual(store.displayName(owner: nil), "ひかり野営地")
        store.rename("")
        XCTAssertFalse(store.displayName(owner: nil).isEmpty)
    }

    @MainActor
    func testStoreSavesAndLoads() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = CampStore(directory: dir)
        a.add(shot: CampShot(id: "x", takenAt: Date(timeIntervalSince1970: 1_700_000_000), subjects: [.snow]),
              cutout: CampCutoutRecord(id: "c", shotId: "x", layers: CampLayerSplit.fallback(unitHeight: 400), spot: 1,
                                       title: "雪", place: "白馬村", takenAt: Date(), createdAt: Date()),
              layerImages: [Data([1, 2, 3])], photo: Data([9]), sky: nil)
        let b = CampStore(directory: dir)
        XCTAssertEqual(b.shots.map(\.id), ["x"])
        XCTAssertEqual(b.placed.first?.layers, a.placed.first?.layers)
        XCTAssertEqual(try Data(contentsOf: b.imageURL(cutout: "c", layer: 0)), Data([1, 2, 3]))
        try? FileManager.default.removeItem(at: dir)
    }
}

/// 写った物の分類の拾い方と、マイページの入口（画面は模型で動かせないので、書いてあることを見る）
final class CampWiringTests: XCTestCase {

    func testSubjectsFromClassifierLabels() {
        let labels: [(String, Float)] = [("forest", 0.8), ("snow", 0.5), ("beach", 0.1), ("night_sky", 0.4), ("tree", 0.6)]
        XCTAssertEqual(CampSubjectRule.subjects(labels: labels), [.starrySky, .forest, .snow])
        XCTAssertTrue(CampSubjectRule.showsPeople(labels: [("people", 0.7)]))
        XCTAssertFalse(CampSubjectRule.showsPeople(labels: [("people", 0.2)]))
        XCTAssertFalse(CampSubjectRule.title([.forest], season: .summer).isEmpty)
        XCTAssertNotEqual(CampSubjectRule.title([.forest], season: .summer), CampSubjectRule.title([], season: .summer))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 入口はマイページの旅の記録の札（旅のトランクの行のすぐ下）。サーバーを待たずに出す
    func testMyPageHasCampEntryBelowTrunk() throws {
        let view = try source("Features/Profile/MyPageView.swift")
        guard let trunk = view.range(of: "\"trips.trunk\""),
              let camp = view.range(of: "NavigationLink { CampHomeView(ownerName: model.profile?.name) }"),
              let albums = view.range(of: "NavigationLink { AlbumsView() }") else {
            return XCTFail("旅のトランク・キャンプ場・共同アルバムの行のどれかが無い")
        }
        XCTAssertLessThan(trunk.lowerBound, camp.lowerBound)
        XCTAssertLessThan(camp.lowerBound, albums.lowerBound)
        XCTAssertTrue(view.contains("\"trips.camp\""), "画面写真で探す名前が無い")
        // トランクの「口が読めた人だけ」の条件の中に入れていない
        let between = view[trunk.upperBound..<camp.lowerBound]
        XCTAssertTrue(between.contains("}"), "キャンプ場の行がトランクの出し分けの中にある")
    }

    /// 写真の上（撮る・切り出す）は白だけ。真鍮は置く画面（写真の無い黒地）の主ボタンと眉ラベルだけ
    func testCaptureUsesWhiteOnPhoto() throws {
        let capture = try source("Features/Camp/CampCaptureView.swift")
        XCTAssertTrue(capture.contains("let accent = onPhoto ? Color.white : WebTheme.accent"), "写真の上の手順の印が白でない")
        let stage = try source("Features/Camp/CampCutStage.swift")
        XCTAssertFalse(stage.contains("WebTheme.accent"), "切り出す写真の上に真鍮がある")
        // 「捨てる」と言わない（保存せずに閉じる）
        XCTAssertTrue(capture.contains("保存せずに閉じる"))
    }

    /// 要サーバーの部品は「近日」（図鑑）。サーバーの口は足していない（DB と費用は owner の承認が要る）
    func testServerPartsShowComingSoon() throws {
        let dex = try source("Features/Camp/CampDexView.swift")
        XCTAssertTrue(dex.contains("L(\"近日\", \"Soon\")"))
        let catalog = try source("Core/Camp/CampCatalog.swift")
        XCTAssertFalse(catalog.contains("APIClient"))
    }
}
