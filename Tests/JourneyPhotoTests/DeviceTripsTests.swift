import XCTest
@testable import JourneyPhoto

/// 端末の写真の一冊（`DeviceTrips`・2026-10-16）。
/// **ここが間違うと、毎回ライブラリを全部読み直す（重い）・人に見える・送れてしまう**——規則ごとに見張る。
final class DeviceTripsTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    /// 2026-09-12 00:00 JST
    private let base = Date(timeIntervalSince1970: 1_789_138_800)
    private let home = (lat: 35.68, lng: 139.76)    // 東京
    private let kyoto = (lat: 35.01, lng: 135.77)   // 約370km

    private func shot(_ id: String, hours: Double, _ place: (lat: Double, lng: Double)? = nil) -> LibraryShot {
        LibraryShot(id: id, date: base.addingTimeInterval(hours * 3600), lat: place?.lat, lng: place?.lng)
    }

    /// 家の日常20枚＋京都の旅6枚（`LibraryTripsTests` と同じ形）
    private func library() -> [LibraryShot] {
        (0..<20).map { shot("h\($0)", hours: -24 * 30 + Double($0) * 5, home) }
            + (0..<6).map { shot("k\($0)", hours: 10 + Double($0), kyoto) }
    }

    // MARK: - 読む段（前回より新しい写真だけ）

    func testFirstStepReadsEverythingOnlyWhenNothingIsRemembered() {
        XCTAssertEqual(DeviceTrips.firstStep(nil), .full)
        XCTAssertEqual(DeviceTrips.firstStep(DeviceTrips.Index()), .full)
    }

    /// 途中で閉じたら続きから（頭から読み直さない）
    func testFirstStepResumesFromTheFrontier() {
        var index = DeviceTrips.Index()
        index.shots = [shot("a", hours: 0)]
        index.frontier = base
        XCTAssertEqual(DeviceTrips.firstStep(index), .resume(before: base))
    }

    /// 🔴 **読み終えたら、次からは前回より新しい写真だけ**（owner の条件 2）
    func testFirstStepAfterCompletionReadsOnlyNewerPhotos() {
        var index = DeviceTrips.Index()
        index.shots = [shot("a", hours: 0)]
        index.complete = true
        index.newest = base
        XCTAssertEqual(DeviceTrips.firstStep(index), .newer(after: base))
    }

    // MARK: - 突き合わせ（数が合わないときだけ）

    private func completeIndex(shots: Int, skipped: Int = 0) -> DeviceTrips.Index {
        var index = DeviceTrips.Index()
        index.shots = (0..<shots).map { shot("s\($0)", hours: Double($0)) }
        index.skipped = (0..<skipped).map { shot("x\($0)", hours: Double($0)) }
        index.complete = true
        index.newest = base
        return index
    }

    func testNoSweepWhenTheCountsMatch() {
        let since = base.addingTimeInterval(-86_400)
        XCTAssertFalse(DeviceTrips.needsSweep(completeIndex(shots: 10, skipped: 2), libraryCount: 12, since: since),
                       "スクリーンショットも数えないと、毎回突き合わせ直す（重い）")
    }

    /// 写真を消した・一部の許可を選び直した
    func testSweepWhenTheCountsDiffer() {
        let since = base.addingTimeInterval(-86_400)
        XCTAssertTrue(DeviceTrips.needsSweep(completeIndex(shots: 10), libraryCount: 9, since: since))
        XCTAssertTrue(DeviceTrips.needsSweep(completeIndex(shots: 10), libraryCount: 11, since: since))
    }

    /// 上限を超えるライブラリで毎回突き合わせない
    func testNoSweepAtTheCapWhenTheLibraryIsLarger() {
        var index = completeIndex(shots: 0)
        index.shots = (0..<DeviceTrips.maxShots).map {
            LibraryShot(id: "s\($0)", date: base.addingTimeInterval(Double($0)), lat: nil, lng: nil)
        }
        XCTAssertFalse(DeviceTrips.needsSweep(index, libraryCount: DeviceTrips.maxShots + 5_000,
                                              since: base.addingTimeInterval(-1)))
    }

    /// 読み終える前は突き合わせない（続きを読む）
    func testNoSweepBeforeCompletion() {
        var index = completeIndex(shots: 10)
        index.complete = false
        XCTAssertFalse(DeviceTrips.needsSweep(index, libraryCount: 500, since: base.addingTimeInterval(-86_400)))
    }

    func testMergedDropsDuplicatesAndOldShotsAndSortsNewestFirst() {
        let since = base
        let old = [shot("a", hours: 1), shot("b", hours: 2), shot("gone", hours: -5)]
        let new = [shot("b", hours: 3), shot("c", hours: 4)]
        let merged = DeviceTrips.merged(old, adding: new, since: since)
        XCTAssertEqual(merged.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(merged.first { $0.id == "b" }?.date, base.addingTimeInterval(3 * 3600), "新しく読んだ方を使う")
    }

    /// 上限を超えたら古い方を落とす
    func testMergedKeepsTheNewestUpToTheLimit() {
        let merged = DeviceTrips.merged([shot("a", hours: 1), shot("b", hours: 2), shot("c", hours: 3)],
                                        adding: [], since: base, limit: 2)
        XCTAssertEqual(merged.map(\.id), ["c", "b"])
    }

    /// 🔴 **覚えている写真は読み直さない**——知らない識別子だけを返す
    func testSweepReusesKnownShotsAndReturnsOnlyUnknownIds() {
        let known = [shot("a", hours: 1, kyoto), shot("deleted", hours: 2)]
        let result = DeviceTrips.sweep(known: known, current: ["new", "a"])
        XCTAssertEqual(result.kept, [shot("a", hours: 1, kyoto)])
        XCTAssertEqual(result.unknown, ["new"])
    }

    // MARK: - 棚に出す一冊

    func testBooksAreFoundWithTheExistingLibraryTripRules() {
        let trips = DeviceTrips.found(in: library())
        XCTAssertEqual(trips.map { $0.shots.map(\.id) }, LibraryTrips.find(library()).map { $0.shots.map(\.id) },
                       "旅の分け方は「旅の写真から」と同じ（写しを作らない）")
        XCTAssertEqual(trips.count, 1)
    }

    /// 🔴 **人の棚には出さない**（owner の条件 9）
    func testBooksAreNeverShownToOthers() {
        let trips = DeviceTrips.found(in: library())
        XCTAssertFalse(DeviceTrips.books(trips, posted: [], zones: [:], isMine: true).isEmpty)
        XCTAssertTrue(DeviceTrips.books(trips, posted: [], zones: [:], isMine: false).isEmpty)
    }

    /// 投稿済みの日がある旅は出さない（投稿した一冊と2冊に見える）
    func testBooksHidePostedTrips() throws {
        let trips = DeviceTrips.found(in: library())
        let day = try XCTUnwrap(trips.first?.days.first?.key)
        let posted = [LibraryTrips.PostedShot(key: day, coords: nil)]
        XCTAssertTrue(DeviceTrips.books(trips, posted: posted, zones: [:], isMine: true).isEmpty)
        let elsewhere = [LibraryTrips.PostedShot(key: "2001-01-01", coords: nil)]
        XCTAssertEqual(DeviceTrips.books(trips, posted: elsewhere, zones: [:], isMine: true).count, 1)
    }

    /// 地名と一緒に分かった土地の時間帯で日を切り直す
    func testBooksRecutWithTheRememberedZone() throws {
        let trips = DeviceTrips.found(in: library())
        let id = try XCTUnwrap(trips.first?.id)
        let book = try XCTUnwrap(DeviceTrips.books(trips, posted: [], zones: [id: "Asia/Tokyo"], isMine: true).first)
        XCTAssertEqual(book.timeZone.identifier, "Asia/Tokyo")
        XCTAssertTrue(book.zoneIsKnown)
    }

    /// 端末の一冊は送らない（owner の条件 9）
    func testDeviceBooksAreNotShared() throws {
        let trip = try XCTUnwrap(DeviceTrips.found(in: library()).first)
        XCTAssertFalse(DeviceTrips.canShare(trip))
        // **画面にも送る口が無いこと**（確かめ役の指摘）。端末の一冊の画面は共有の部品を持たず、
        // 共有のある一冊の画面（`TripBookView`）へは渡らない（型が違う・`TripBook.Trip` だけを受ける）
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let screen = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Trips/DeviceTripShelf.swift"),
                                encoding: .utf8)
        for share in ["ShareLink", "TripBookCard", " TripBookView(", "UIActivityViewController", "shareSheet"] {
            XCTAssertFalse(screen.contains(share), "端末の一冊の画面に共有の口（\(share)）がある")
        }
        // 人のプロフィールには端末の一冊を置かない（置くのはマイページだけ）
        let others = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Profile/UserProfileView.swift"),
                                encoding: .utf8)
        XCTAssertFalse(others.contains("DeviceTrip"))
        let mine = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Profile/MyPageView.swift"),
                              encoding: .utf8)
        XCTAssertTrue(mine.contains("DeviceTripSection(store:"))
        XCTAssertTrue(screen.contains("store.books(posted: posted, isMine: true)"))
    }

    // MARK: - 地名（一冊につき1回）

    private func namedIndex(complete: Bool = true) -> DeviceTrips.Index {
        var index = DeviceTrips.Index()
        index.complete = complete
        return index
    }

    func testLooksUpEachBookOnce() throws {
        let trips = DeviceTrips.found(in: library())
        let id = try XCTUnwrap(trips.first?.id)
        var index = namedIndex()
        XCTAssertEqual(DeviceTrips.toLookUp(trips, index: index, now: base).map(\.id), [id])
        index.names[id] = "京都市"
        XCTAssertTrue(DeviceTrips.toLookUp(trips, index: index, now: base).isEmpty, "引けた一冊をまた引いた")
    }

    /// 引けなかった一冊は1日のあいだ引き直さない
    func testFailedLookupWaitsADay() throws {
        let trips = DeviceTrips.found(in: library())
        let id = try XCTUnwrap(trips.first?.id)
        var index = namedIndex()
        index.failedAt[id] = base
        XCTAssertTrue(DeviceTrips.toLookUp(trips, index: index, now: base.addingTimeInterval(3600)).isEmpty)
        XCTAssertEqual(DeviceTrips.toLookUp(trips, index: index,
                                            now: base.addingTimeInterval(DeviceTrips.nameRetryAfter)).count, 1)
    }

    /// 読みの途中は引かない（旅の id が動く）
    func testNoLookupBeforeTheFirstReadCompletes() {
        let trips = DeviceTrips.found(in: library())
        XCTAssertTrue(DeviceTrips.toLookUp(trips, index: namedIndex(complete: false), now: base).isEmpty)
    }

    func testLookupIsLimitedPerRun() {
        let trips = DeviceTrips.found(in: library())
        XCTAssertEqual(DeviceTrips.toLookUp(trips, index: namedIndex(), now: base, limit: 0).count, 0)
    }

    /// 地名が引けなくても一冊は出す（題は期間）
    func testTitleFallsBackToThePeriod() throws {
        let trip = try XCTUnwrap(LibraryTrips.find(library(), timeZone: tokyo).first)
        XCTAssertEqual(DeviceTrips.title(of: trip, name: nil), LibraryTrips.periodText(trip))
        XCTAssertEqual(DeviceTrips.title(of: trip, name: " "), LibraryTrips.periodText(trip))
        XCTAssertTrue(DeviceTrips.title(of: trip, name: "京都市").contains("京都市"))
        XCTAssertEqual(DeviceTripText.line(trip, name: nil), LibraryTrips.countText(trip))
        XCTAssertTrue(DeviceTripText.line(trip, name: "京都市").hasPrefix(LibraryTrips.periodText(trip)))
    }

    // MARK: - 投稿の流れへ

    /// 🔴 **開いた一冊は、あとから分かった土地の時間帯で日を切り直す**（2026-10-17）。
    /// 開いたときの値のままだと、海外の旅の日が1日ずれたまま「この旅の写真を投稿する」へ渡る
    func testShownBookUsesTheResolvedTimeZone() throws {
        let utc = TimeZone(identifier: "UTC")!
        // 2026-09-11 20:00 UTC は日本では 2026-09-12 05:00。日をまたぐ
        let evening = Date(timeIntervalSince1970: 1_789_156_800)
        let shots = (0..<6).map { i in
            LibraryShot(id: "k\(i)", date: evening.addingTimeInterval(Double(i) * 3600), lat: kyoto.lat, lng: kyoto.lng)
        }
        let homeShots = (0..<8).map { i in
            LibraryShot(id: "h\(i)", date: evening.addingTimeInterval(Double(-48 + i) * 3600), lat: home.lat, lng: home.lng)
        }
        let trip = try XCTUnwrap(LibraryTrips.find(homeShots + shots, home: home, timeZone: utc).first)
        let shown = DeviceTrips.shown(trip, trips: [trip], zones: [trip.id: tokyo.identifier])
        XCTAssertEqual(shown.timeZone.identifier, tokyo.identifier)
        XCTAssertTrue(shown.zoneIsKnown)
        XCTAssertNotEqual(shown.days.map(\.key), trip.days.map(\.key), "土地の時間帯で日を切り直していない")
        // 時間帯が無ければ、開いたときの旅のまま
        XCTAssertEqual(DeviceTrips.shown(trip, trips: [], zones: [:]).days.map(\.key), trip.days.map(\.key))
    }

    /// 🔴 **投稿の流れは、棚が引いた地名と時間帯をそのまま使う**（2026-10-17）。
    /// もう一度地図に聞くと、一冊につき1回の約束を破り、答えが返るまで日が目安のままになる。
    /// 時間帯が無い地名だけは写さない（写すと、流れが時間帯を引きに行かなくなる）
    @MainActor
    func testPostFlowReusesThePlaceTheShelfAlreadyLookedUp() async throws {
        LibraryTripModel.forgetPlaceNames()
        defer { LibraryTripModel.forgetPlaceNames() }
        let trip = try XCTUnwrap(DeviceTrips.found(in: library()).first)
        let model = LibraryTripModel()
        model.adoptDevicePlace(of: trip, names: [trip.id: "京都市"], zones: [:])
        XCTAssertNil(model.name(for: trip.center), "時間帯の無い地名を覚えると、流れが時間帯を引きに行けない")
        XCTAssertNil(model.zone(for: trip.center))

        model.adoptDevicePlace(of: trip, names: [trip.id: "京都市"], zones: [trip.id: tokyo.identifier])
        XCTAssertEqual(model.name(for: trip.center), "京都市")
        XCTAssertEqual(model.zone(for: trip.center)?.identifier, tokyo.identifier)
        // 流れが先に覚えた分は、棚の別の答えで上書きしない
        model.adoptDevicePlace(of: trip, names: [trip.id: "別の市"], zones: [trip.id: "Europe/Paris"])
        XCTAssertEqual(model.name(for: trip.center), "京都市")
        XCTAssertEqual(model.zone(for: trip.center)?.identifier, tokyo.identifier)

        let list = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Trips/LibraryTripListView.swift"), encoding: .utf8)
        let task = try XCTUnwrap(list.range(of: "model.adoptDevicePlace"))
        let load = try XCTUnwrap(list.range(of: "await model.load"))
        XCTAssertLessThan(task.lowerBound, load.lowerBound, "地名を写す前に旅を探している")
        let book = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Trips/DeviceTripShelf.swift"), encoding: .utf8)
        XCTAssertTrue(book.contains("DeviceTrips.shown(trip, trips: store.trips, zones: store.zones)"))
        XCTAssertTrue(book.contains("openTripImport(shown)"))
    }

    func testMatchingFindsTheSameTripOrTheTripWithTheCover() throws {
        let trip = try XCTUnwrap(DeviceTrips.found(in: library()).first)
        XCTAssertEqual(DeviceTrips.matching(trip, in: [trip])?.id, trip.id)
        // 流れの側で旅の始まりが変わっても（id が違う）、表紙の写真を含む旅を開く
        let other = LibraryTrip(id: "other", shots: trip.shots, start: trip.start, end: trip.end, days: trip.days,
                                center: trip.center, timeZone: trip.timeZone)
        XCTAssertEqual(DeviceTrips.matching(trip, in: [other])?.id, "other")
        XCTAssertNil(DeviceTrips.matching(trip, in: []))
    }

    // MARK: - 端末の置き場

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceTripsTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("index.json")
    }

    func testIndexRoundTripsThroughTheFile() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var index = completeIndex(shots: 3, skipped: 1)
        index.shots[0] = shot("k", hours: 5, kyoto)
        index.names["k"] = "京都市"
        index.zones["k"] = "Asia/Tokyo"
        DeviceTripIndexFile.save(index, to: url)
        let loaded = try XCTUnwrap(DeviceTripIndexFile.load(from: url))
        XCTAssertEqual(loaded, index)
        DeviceTripIndexFile.remove(at: url)
        XCTAssertNil(DeviceTripIndexFile.load(from: url))
    }

    /// 覚えるのは識別子・日時・位置だけ（短い鍵）。画像や地名以外の文字は書かない
    func testShotIsStoredWithShortKeysOnly() throws {
        let data = try JSONEncoder().encode(shot("id1", hours: 1, kyoto))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["i", "t", "a", "o"])
    }

    /// 版が違う置き場は読まない（読み直す）
    func testOldVersionIsIgnored() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var index = completeIndex(shots: 1)
        index.version = 0
        DeviceTripIndexFile.save(index, to: url)
        XCTAssertNil(DeviceTripIndexFile.load(from: url))
    }

    /// 🔴 **読む年数は「旅の写真から」と同じ**（棚の一冊から同じ流れを開く・確かめ役の指摘 8）
    func testLookbackMatchesTheTripFlow() {
        XCTAssertEqual(DeviceTrips.lookbackYears, PhotoLibrary.lookbackYears)
    }

    /// 自前の札のボタンは「続ける」（iOS の許可のダイアログの前に「許可」と言わない・2026-10-16 判断）。
    /// 約束の文は実装どおり「旅を探すのに読むのは撮影日時と場所だけ」（表紙は小さく読む）
    func testIntroCardWording() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let screen = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Trips/DeviceTripShelf.swift"),
                                encoding: .utf8)
        XCTAssertTrue(screen.contains("L(\"続ける\", \"Continue\")"))
        XCTAssertFalse(screen.contains("写真へのアクセスを許可"))
        XCTAssertTrue(screen.contains("旅を探すのに読むのは撮影日時と場所だけです"))
    }

    func testRoundingKeepsFourDecimals() {
        XCTAssertEqual(DeviceTrips.rounded(35.123456), 35.1235)
        XCTAssertNil(DeviceTrips.rounded(nil))
    }

    // MARK: - 棚の店（サインアウトで消す）

    @MainActor
    func testForgetRemovesTheStoredSummary() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        DeviceTripIndexFile.save(completeIndex(shots: 2), to: url)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceTripsTests-\(UUID().uuidString)"))
        let store = DeviceTripShelfStore(defaults: defaults, url: url)
        store.forget()
        await store.waitForRemoval()
        XCTAssertNil(DeviceTripIndexFile.load(from: url), "写真の位置の控えが次の人に残った")
        XCTAssertTrue(store.books(posted: [], isMine: true).isEmpty)
    }

    @MainActor
    func testIntroDismissalIsRemembered() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeviceTripsTests-\(UUID().uuidString)"))
        let store = DeviceTripShelfStore(defaults: defaults, url: nil)
        XCTAssertFalse(store.introDismissed)
        store.dismissIntro()
        XCTAssertTrue(DeviceTripShelfStore(defaults: defaults, url: nil).introDismissed)
    }

    // MARK: - 許可の前に言うこと

    /// 🔴 **何に使うかを許可の前に言い、「端末の中だけで読み、どこにも送らない」と書く**（owner の条件 6）。
    /// 札と Info.plist の利用目的の両方
    func testPermissionTextsPromiseNothingIsUploaded() throws {
        let promise = DeviceTripText.introPrivacy
        XCTAssertTrue(promise.contains("どこにも送りません") || promise.contains("uploaded"))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ja = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/ja.lproj/InfoPlist.strings"),
                            encoding: .utf8)
        let line = try XCTUnwrap(ja.split(separator: "\n").first { $0.hasPrefix("\"NSPhotoLibraryUsageDescription\"") })
        XCTAssertTrue(line.contains("端末の中だけ"))
        XCTAssertTrue(line.contains("どこにも送りません"))
        XCTAssertTrue(line.contains("旅の記録に並べる"))
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("写真も位置もどこにも送りません"), "project.yml と InfoPlist.strings の文が食い違う")
        let en = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/en.lproj/InfoPlist.strings"),
                            encoding: .utf8)
        XCTAssertTrue(en.contains("neither photos nor locations are uploaded"))
    }
}
