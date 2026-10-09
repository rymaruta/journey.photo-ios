import XCTest
@testable import JourneyPhoto

/// 「電波なしで使える旅」（Pro・板 72〜72e・2026-10-09）の画面を持たない決まり。
/// 容量の数え方・保存の状態の移り変わり・プランが変わったかの判定・光の時刻の並べ方・文面・場所の番号
final class OfflineTripTests: XCTestCase {

    // MARK: - 材料

    private func spot(_ id: String, name: String = "銀山温泉", lat: Double = 38.58, lng: Double = 140.53,
                      prefecture: String = "山形県", city: String = "尾花沢市") throws -> OfficialSpot {
        let json = #"{"spotId":"\#(id)","slug":"\#(id)","name":"\#(name)","stage":"published","region":{"prefecture":"\#(prefecture)","city":"\#(city)"},"coords":{"lat":\#(lat),"lng":\#(lng)}}"#
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private func plan(_ days: [[TripItem]], start: String? = "2026-10-10", end: String? = "2026-10-11",
                      title: String = "山形") -> TripPlan {
        TripPlan(planId: "p1", title: title, startDate: start, endDate: end, days: days.map { TripDay(items: $0) })
    }

    // MARK: - 容量

    func testByteLabels() {
        XCTAssertEqual(OfflineTripBytes.label(0), "0 MB")
        XCTAssertEqual(OfflineTripBytes.label(50_000), "0.1 MB 未満", "小さくても 0 と言わない")
        XCTAssertEqual(OfflineTripBytes.label(4_240_000), "4.2 MB")
        XCTAssertEqual(OfflineTripBytes.label(24_400_000), "24 MB")
        XCTAssertEqual(OfflineTripBytes.label(1_300_000_000), "1.3 GB")
    }

    func testEstimateGrowsWithStops() {
        XCTAssertEqual(OfflineTripBytes.estimate(stops: 0), 0)
        XCTAssertEqual(OfflineTripBytes.estimate(stops: 1), OfflineTripBytes.perStopEstimate + OfflineTripBytes.overheadEstimate)
        // 板の「6 か所で約 24 MB」に近い桁（作例3枚と地図1枚）
        let six = OfflineTripBytes.estimate(stops: 6)
        XCTAssertTrue((5_000_000...30_000_000).contains(six), "\(six)")
    }

    func testCountsFilesInSubfolders() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("offline-count-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: dir.appendingPathComponent("x.jpg"))
        try Data(count: 2_500).write(to: dir.appendingPathComponent("a/b/y.jpg"))
        XCTAssertEqual(OfflineTripBytes.count(in: dir), 3_500, "下の階層も数え、フォルダそのものは数えない")
        XCTAssertEqual(OfflineTripBytes.count(in: dir.appendingPathComponent("none")), 0)
    }

    // MARK: - 保存の状態

    func testSavingThenFinished() {
        var s = OfflineSaveStatus()
        s = OfflineSaveStatus.reduce(s, .started(total: 6, estimate: 24_000_000, alreadyDone: 0))
        XCTAssertEqual(s.phase(isPro: true, change: .none),
                       .saving(.init(done: 0, total: 6, bytes: 0, estimate: 24_000_000)))
        s = OfflineSaveStatus.reduce(s, .progressed(done: 3, bytes: 12_000_000))
        // 戻らない（遅れて届いた古い進み）
        s = OfflineSaveStatus.reduce(s, .progressed(done: 2, bytes: 12_000_000))
        XCTAssertEqual(s.running?.done, 3)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        s = OfflineSaveStatus.reduce(s, .finished(bytes: 23_000_000, at: at))
        XCTAssertEqual(s.phase(isPro: true, change: .none), .saved(.init(bytes: 23_000_000, savedAt: at)))
        XCTAssertNil(s.running)
    }

    func testStopKeepsPartialForResume() {
        var s = OfflineSaveStatus.reduce(OfflineSaveStatus(), .started(total: 6, estimate: 1, alreadyDone: 0))
        s = OfflineSaveStatus.reduce(s, .progressed(done: 2, bytes: 10))
        s = OfflineSaveStatus.reduce(s, .stopped)
        XCTAssertEqual(s.phase(isPro: true, change: .none), .interrupted(.init(done: 2, total: 6)))
        // 続きから: 済んだぶんから数える
        s = OfflineSaveStatus.reduce(s, .started(total: 6, estimate: 1, alreadyDone: 2))
        XCTAssertEqual(s.running?.done, 2)
        XCTAssertNil(s.partial)
    }

    func testFailureKeepsPartialAndMessage() {
        var s = OfflineSaveStatus.reduce(OfflineSaveStatus(), .started(total: 4, estimate: 1, alreadyDone: 1))
        s = OfflineSaveStatus.reduce(s, .failed("電波"))
        XCTAssertEqual(s.partial, .init(done: 1, total: 4))
        XCTAssertEqual(s.error, "電波")
        // 次に始めたら文は消す
        s = OfflineSaveStatus.reduce(s, .started(total: 4, estimate: 1, alreadyDone: 1))
        XCTAssertNil(s.error)
    }

    func testResavingKeepsOldCopyWhileInterrupted() {
        let at = Date(timeIntervalSince1970: 1)
        var s = OfflineSaveStatus.reduce(OfflineSaveStatus(), .finished(bytes: 5, at: at))
        s = OfflineSaveStatus.reduce(s, .started(total: 3, estimate: 1, alreadyDone: 0))
        s = OfflineSaveStatus.reduce(s, .stopped)
        XCTAssertEqual(s.saved, .init(bytes: 5, savedAt: at), "保存し直しが止まっても前の中身は残る")
        XCTAssertEqual(s.phase(isPro: true, change: .none), .interrupted(.init(done: 0, total: 3)),
                       "続きから保存を先に出す")
    }

    func testFoundPartialAfterRelaunch() {
        let s = OfflineSaveStatus.reduce(OfflineSaveStatus(), .foundPartial(done: 9, total: 4))
        XCTAssertEqual(s.partial, .init(done: 4, total: 4), "済んだ数は全体を超えない")
        // 走っている間は上書きしない
        let running = OfflineSaveStatus.reduce(OfflineSaveStatus(), .started(total: 4, estimate: 1, alreadyDone: 0))
        XCTAssertEqual(OfflineSaveStatus.reduce(running, .foundPartial(done: 1, total: 4)), running)
    }

    func testDeletedClearsEverything() {
        var s = OfflineSaveStatus.reduce(OfflineSaveStatus(), .finished(bytes: 5, at: Date()))
        s = OfflineSaveStatus.reduce(s, .deleted)
        XCTAssertEqual(s, OfflineSaveStatus())
    }

    func testPhaseByProAndChange() {
        let empty = OfflineSaveStatus()
        XCTAssertEqual(empty.phase(isPro: true, change: .none), .before)
        XCTAssertEqual(empty.phase(isPro: false, change: .none), .free)
        XCTAssertEqual(empty.phase(isPro: nil, change: .none), .hidden, "Pro か分からないうちは札を出さない")
        let saved = OfflineSaveStatus.reduce(empty, .finished(bytes: 1, at: Date(timeIntervalSince1970: 0)))
        // Pro が切れても保存済みは見える（owner 2026-10-09）
        XCTAssertEqual(saved.phase(isPro: false, change: .none), .saved(.init(bytes: 1, savedAt: Date(timeIntervalSince1970: 0))))
        XCTAssertEqual(saved.phase(isPro: true, change: .added(1)),
                       .stale(.init(bytes: 1, savedAt: Date(timeIntervalSince1970: 0)), .added(1)))
    }

    func testOnlySavingNeedsPro() {
        for action in [OfflineTripAccess.Action.save, .resume, .resave] {
            XCTAssertTrue(OfflineTripAccess.needsPro(action, isPro: false))
            // 🔴 Pro か分からない（圏外で開いた）ときは案内を出さない——払っている人に案内が開いた
            XCTAssertFalse(OfflineTripAccess.needsPro(action, isPro: nil))
            XCTAssertEqual(OfflineTripAccess.decide(action, isPro: nil), .unverified)
            XCTAssertEqual(OfflineTripAccess.decide(action, isPro: false), .paywall)
            XCTAssertEqual(OfflineTripAccess.decide(action, isPro: true), .proceed)
            XCTAssertFalse(OfflineTripAccess.needsPro(action, isPro: true))
        }
        XCTAssertFalse(OfflineTripAccess.needsPro(.view, isPro: false), "見るのは誰でも")
        XCTAssertFalse(OfflineTripAccess.needsPro(.delete, isPro: false), "消すのは誰でも")
    }

    // MARK: - プランが変わったか

    func testPlanChanges() {
        let a = TripItem.spot(spotId: "sp_a", note: nil), b = TripItem.spot(spotId: "sp_b", note: nil)
        let c = TripItem.location(slug: "c", note: nil)
        let saved = OfflineTripPrint(plan([[a, b]]))
        XCTAssertEqual(saved.change(to: OfflineTripPrint(plan([[a, b]]))), .none)
        XCTAssertEqual(saved.change(to: OfflineTripPrint(plan([[a, b], [c]]))), .added(1))
        XCTAssertEqual(saved.change(to: OfflineTripPrint(plan([[a]]))), .removed(1))
        XCTAssertEqual(saved.change(to: OfflineTripPrint(plan([[b, a]]))), .other, "並べ替え")
        XCTAssertEqual(saved.change(to: OfflineTripPrint(plan([[a, c]]))), .other, "入れ替え（増えて減った）")
        XCTAssertEqual(saved.change(to: OfflineTripPrint(plan([[a, b]], start: "2026-11-01"))), .other, "日付")
        XCTAssertEqual(saved.change(to: OfflineTripPrint(plan([[a, .spot(spotId: "sp_b", note: "朝")]]))), .other, "メモ")
        // メモの前後の空白だけは変わったと言わない
        let noted = OfflineTripPrint(plan([[.spot(spotId: "sp_a", note: "朝")]]))
        XCTAssertEqual(noted.change(to: OfflineTripPrint(plan([[.spot(spotId: "sp_a", note: " 朝 ")]]))), .none)
        // 増えただけ・メモ付きの場所が増えた
        XCTAssertEqual(saved.change(to: OfflineTripPrint(plan([[a, b, .location(slug: "d", note: "夕方")]]))), .added(1))
    }

    func testStaleMessages() {
        XCTAssertNil(OfflineTripText.staleMessage(.none))
        XCTAssertEqual(OfflineTripText.staleMessage(.added(1)),
                       "保存したあとに場所が 1 か所増えました。増えた場所は、保存し直すまで圏外では出ません。")
        XCTAssertTrue(OfflineTripText.staleMessage(.removed(2))!.contains("2 か所減りました"))
        XCTAssertTrue(OfflineTripText.staleMessage(.other)!.contains("保存し直すまで"))
    }

    // MARK: - 光の時刻

    func testLightTimesInLocalClockAndDayOrder() throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")
        let light = try XCTUnwrap(OfflineLight.make(date: "2026-10-10", coords: .init(lat: 38.58, lng: 140.53), zone: tokyo))
        // Web の sunTimes.test.ts と同じ日の入り（銀山温泉 2026-10-10・`TripLightTests`）
        XCTAssertEqual(light.sunset, "17:09")
        XCTAssertFalse(light.sunrise!.hasPrefix("0"), "時の頭の 0 は落とす（板「6:51」）")
        XCTAssertEqual(light.entries.map(\.label), ["朝のブルーアワー", "日の出", "日の入り", "夕のブルーアワー"])
        XCTAssertTrue(light.morningBlue!.contains("〜"))
        XCTAssertEqual(light.line, "日の出 \(light.sunrise!) · 日の入り 17:09")
    }

    func testLightNeedsDateCoordsAndZone() {
        let c = Photo.Coords(lat: 38.58, lng: 140.53)
        XCTAssertNil(OfflineLight.make(date: nil, coords: c, zone: .current), "日付の決まらない日")
        XCTAssertNil(OfflineLight.make(date: "2026-10-10", coords: nil, zone: .current))
        XCTAssertNil(OfflineLight.make(date: "2026-10-10", coords: c, zone: nil), "時計が決まらない場所")
    }

    func testPolarDaysSkipMissingEntries() {
        let light = OfflineLight(morningBlue: nil, sunrise: nil, sunset: nil, eveningBlue: "11:00〜13:00")
        XCTAssertEqual(light.entries.map(\.label), ["夕のブルーアワー"], "無い枠は出さない")
        XCTAssertEqual(light.line, "ブルーアワー 11:00〜13:00", "日の出・日の入りが無い日はブルーアワー")
        XCTAssertNil(OfflineLight(morningBlue: nil, sunrise: nil, sunset: nil, eveningBlue: nil).line)
    }

    // MARK: - 場所の番号

    func testStopsAreNumberedAcrossDays() throws {
        let a = try spot("sp_a", name: "A"), b = try spot("sp_b", name: "B", lat: 38.6)
        let p = plan([[.spot(spotId: "sp_a", note: " 日没の30分前 "), .spot(spotId: "sp_missing", note: nil)],
                      [.spot(spotId: "sp_b", note: "")]])
        let stops = OfflineTripPlan.stops(of: p, index: [a, b], places: [])
        XCTAssertEqual(stops.map(\.number), [1, 2, 3], "日をまたいで通し番号（地図の点と揃える）")
        XCTAssertEqual(stops.map(\.dayIndex), [0, 0, 1])
        XCTAssertEqual(stops.map(\.date), ["2026-10-10", "2026-10-10", "2026-10-11"])
        XCTAssertEqual(stops[0].name, "A")
        XCTAssertEqual(stops[0].address, "山形県 尾花沢市")
        XCTAssertEqual(stops[0].note, "日没の30分前")
        XCTAssertNil(stops[2].note, "空のメモは無いのと同じ")
        XCTAssertNotNil(stops[0].light, "日本のスポットは東京の時計で光の時刻")
        XCTAssertNil(stops[1].coords, "索引に無い場所は座標なし（番号は数える）")
        XCTAssertNil(stops[1].light)
        XCTAssertEqual(stops[1].key, "spot:sp_missing")
    }

    func testLocationLightOnlyInsideJapan() {
        XCTAssertEqual(OfflineTripPlan.zoneForLocation(.init(lat: 35.68, lng: 139.76))?.identifier, "Asia/Tokyo")
        XCTAssertNil(OfflineTripPlan.zoneForLocation(.init(lat: 48.85, lng: 2.35)), "外国の撮影地は時計を決めない")
    }

    // MARK: - 地図の範囲

    func testOverviewRegionCoversAllPoints() throws {
        let r = try XCTUnwrap(OfflineTripMap.overview([.init(lat: 35, lng: 139), .init(lat: 36, lng: 140)]))
        XCTAssertEqual(r.lat, 35.5, accuracy: 1e-9)
        XCTAssertEqual(r.lng, 139.5, accuracy: 1e-9)
        XCTAssertGreaterThan(r.latDelta, 1, "縁で点が切れない余白")
        let one = try XCTUnwrap(OfflineTripMap.overview([.init(lat: 35, lng: 139)]))
        XCTAssertEqual(one.latDelta, OfflineTripMap.minOverviewSpan, "1か所でも狭すぎない")
        XCTAssertNil(OfflineTripMap.overview([]))
        XCTAssertNil(OfflineTripMap.overview([.init(lat: .nan, lng: 0)]))
    }

    // MARK: - 文面

    func testTexts() {
        let utc = TimeZone(identifier: "UTC")!
        let at = TripPlanText.date(fromYMD: "2026-10-09")!
        XCTAssertEqual(OfflineTripText.savedLine(bytes: 24_000_000, savedAt: at, zone: utc), "24 MB · 10月9日に保存")
        XCTAssertEqual(OfflineTripText.settingsDetail(count: 2, bytes: 48_000_000), "2 件 · 48 MB")
        XCTAssertEqual(OfflineTripText.progressPlaces(done: 3, total: 6), "3 / 6 か所")
        XCTAssertEqual(OfflineTripText.progressBytes(bytes: 12_000_000, estimate: 24_000_000), "12 / 24 MB")
        XCTAssertEqual(OfflineTripText.progressBytes(bytes: 30_000_000, estimate: 24_000_000), "30 / 30 MB",
                       "見込みを超えたら見込みを合わせる")
        XCTAssertEqual(OfflineTripText.progressAccessibility(done: 3, total: 6), "6 か所のうち 3 か所")
        XCTAssertEqual(OfflineTripText.dateRange(start: "2026-12-24", end: "2026-12-25", short: true), "12月24日〜25日")
        XCTAssertEqual(OfflineTripText.dateRange(start: "2026-11-30", end: "2026-12-01", short: true), "11月30日〜12月1日")
        XCTAssertEqual(OfflineTripText.dateRange(start: "2026-12-24", end: "2026-12-25", short: false),
                       "2026年12月24日 〜 2026年12月25日")
        XCTAssertNil(OfflineTripText.dateRange(start: nil, end: nil, short: true))
        XCTAssertEqual(OfflineTripText.coordinates(.init(lat: 35.658584, lng: 139.745433)), "35.65858, 139.74543")
        XCTAssertEqual(OfflineTripText.mapsNote, "電波が無いと開けないことがあります")
        XCTAssertTrue(OfflineTripText.beforeBody(stops: 6).hasPrefix("6 か所の作例"))
        XCTAssertTrue(OfflineTripText.estimateLine(stops: 6).hasPrefix("約 "))
    }

    func testSavedRow() {
        let m = OfflineTripManifest(planId: "p", title: "t", startDate: "2026-12-24", endDate: "2026-12-25",
                                    savedAt: TripPlanText.date(fromYMD: "2026-10-09")!,
                                    print: OfflineTripPrint(plan([])),
                                    days: [.init(number: 1, date: nil, stops: [stop(1), stop(2)]),
                                           .init(number: 2, date: nil, stops: [stop(3), stop(4)])],
                                    overviewMap: nil, bytes: 24_000_000)
        XCTAssertEqual(m.stopCount, 4)
        XCTAssertEqual(OfflineTripText.savedRow(m, zone: TimeZone(identifier: "UTC")!),
                       "12月24日〜25日 · 4 か所 · 24 MB · 10月9日に保存")
    }

    private func stop(_ n: Int) -> OfflineTripManifest.Stop {
        .init(number: n, key: "spot:\(n)", name: "\(n)", address: nil, coords: nil, note: nil, light: nil,
              samples: [], map: nil)
    }

    func testPaywallBenefitWording() {
        // owner 2026-10-09: 「迷わない」をやめる
        let offline = ProBenefit.all.first { $0.icon == .offline }
        XCTAssertEqual(offline?.body, "地図・作例・光の時刻を端末に。圏外でも、どこで何を撮るか分かる")
    }
}

extension OfflineTripTests {
    /// 日を足して場所を置いた・空の日を足しただけ
    func testAddedDayCountsAsAdded() {
        let a = TripItem.spot(spotId: "sp_a", note: nil)
        let saved = OfflineTripPrint(plan([[a]]))
        XCTAssertEqual(saved.change(to: OfflineTripPrint(plan([[a], []]))), .other, "日程の形が変わった（空の日）")
        XCTAssertEqual(saved.change(to: OfflineTripPrint(plan([[], [a]]))), .other, "別の日へ移した")
    }
}

extension OfflineTripTests {
    /// 🔴 **保存した画像は主スレッドの外で読んで絵に戻す**（2026-10-09。`.task` は主スレッドで走り、
    /// 数百KB の JPEG を並べて開くと画面が引っかかった）。Linux では描けないので文で確かめる
    func testStoredImageDecodesOffMainThread() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let src = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Trips/OfflineTripView.swift"),
                             encoding: .utf8)
        let start = try XCTUnwrap(src.range(of: "struct OfflineStoredImage"))
        let end = try XCTUnwrap(src.range(of: "struct OfflineStopNumber"))
        let body = String(src[start.lowerBound..<end.lowerBound])
        let detached = try XCTUnwrap(body.range(of: "Task.detached"))
        let read = try XCTUnwrap(body.range(of: "Data(contentsOf: url)"))
        XCTAssertLessThan(detached.lowerBound, read.lowerBound, "ファイルを読むのは Task.detached の中")
    }
}
