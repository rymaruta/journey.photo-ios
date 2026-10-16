import XCTest
@testable import JourneyPhoto

/// 人のページの「旅の記録」（2026-10-16 owner「他人のプロフィールでも旅の記録を」）。
///
/// 🔴 人のページは**その人の公開写真だけ**から作る（`ProfileTravelRecord.othersPhotos`）。
/// 人のページの写真は公開一覧から選り分けたもので、フォロワーには限定の写真も混ざる
/// （`RestrictedFeed.merge`）。それを数に入れない・ブロックなら出さない・空なら節ごと出さない・
/// マイページは今までどおり自分の写真すべてから作る、を見張る
final class ProfileTravelRecordTests: XCTestCase {

    private func photo(_ id: String, date: String?, lat: Double? = nil, lng: Double? = nil,
                       location: String? = nil, published: Bool? = nil,
                       audience: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"u1\""]
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        if let location { fields.append("\"location\":\"\(location)\"") }
        if let published { fields.append("\"published\":\(published)") }
        if let audience { fields.append("\"audience\":\"\(audience)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 公開の2枚（東京→大阪・日本）と、限定・下書きの写真（パリ・台北）
    private func mixed() throws -> [Photo] {
        [
            try photo("tokyo", date: "2026-05-01", lat: 35.68, lng: 139.76, location: "日本 東京"),
            try photo("osaka", date: "2026-05-02", lat: 34.69, lng: 135.50, location: "日本 大阪",
                      audience: "everyone"),
            try photo("paris", date: "2026-05-03", lat: 48.86, lng: 2.35, location: "フランス パリ",
                      audience: "followers"),
            try photo("close", date: "2026-05-03", lat: 25.03, lng: 121.56, location: "台湾 台北",
                      audience: "closeFriends"),
            try photo("draft", date: "2026-05-02", lat: 21.31, lng: -157.86, location: "アメリカ ホノルル",
                      published: false),
        ]
    }

    // MARK: - 公開写真だけ

    /// 🔴 限定公開（フォロワー・親しい友達・知らない値）と下書きは、人のページの記録に入らない
    func testOthersUsesOnlyPublicPhotos() throws {
        var photos = try mixed()
        photos.append(try photo("future", date: "2026-05-04", lat: 1, lng: 1, audience: "someNewAudience"))
        XCTAssertEqual(ProfileTravelRecord.othersPhotos(photos, blocked: false).map(\.id), ["tokyo", "osaka"])
    }

    /// 🔴 距離・国・線・年は公開の2枚だけで数える（限定の写真のパリ・台北が数に入らない）
    func testOthersSummaryIgnoresRestrictedPhotos() throws {
        let photos = try mixed()
        let summary = ProfileTravelRecord.othersSummary(photos, blocked: false)
        let publicOnly = try [mixed()[0], mixed()[1]]
        XCTAssertEqual(summary, ProfileTravelRecord.Summary(photos: publicOnly))
        XCTAssertEqual(summary.countries, ["日本"])
        XCTAssertFalse(summary.countries.contains("フランス"), "フォロワー限定の写真の国が入った")
        XCTAssertFalse(summary.countries.contains("台湾"), "親しい友達の写真の国が入った")
        XCTAssertEqual(summary.kilometers,
                       TravelDistance.kilometers(from: Photo.Coords(lat: 35.68, lng: 139.76),
                                                 to: Photo.Coords(lat: 34.69, lng: 135.50)),
                       accuracy: 1e-9)
        XCTAssertEqual(summary.coordinates.count, 2)
        XCTAssertFalse(summary.isEmpty)
    }

    /// 🔴 旅の一冊も公開写真だけで束ねる（限定・下書きの写真が一冊のページ・枚数に入らない）
    func testOthersTripsUseOnlyPublicPhotos() throws {
        let trips = ProfileTravelRecord.othersTrips(try mixed(), blocked: false, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(Set(trips[0].photos.map(\.id)), ["tokyo", "osaka"])
        XCTAssertFalse(trips[0].isPrivate)
    }

    // MARK: - ブロック

    /// 🔴 ブロックの関係なら、写真が手元に残っていても何も作らない
    func testBlockedShowsNothing() throws {
        let photos = try mixed()
        XCTAssertTrue(ProfileTravelRecord.othersPhotos(photos, blocked: true).isEmpty)
        XCTAssertTrue(ProfileTravelRecord.othersSummary(photos, blocked: true).isEmpty)
        XCTAssertTrue(ProfileTravelRecord.othersTrips(photos, blocked: true).isEmpty)
    }

    // MARK: - 空の形

    /// 記録が無い人（写真0・撮影地も国名も無い・1枚だけ）は節ごと出さない
    func testEmptyPersonHasNoRecord() throws {
        XCTAssertTrue(ProfileTravelRecord.othersSummary([], blocked: false).isEmpty)
        XCTAssertTrue(ProfileTravelRecord.othersTrips([], blocked: false).isEmpty)
        let plain = [try photo("a", date: "2026-05-01"), try photo("b", date: nil)]
        XCTAssertTrue(ProfileTravelRecord.othersSummary(plain, blocked: false).isEmpty)
        let one = [try photo("a", date: "2026-05-01", lat: 35.68, lng: 139.76)]
        XCTAssertTrue(ProfileTravelRecord.othersSummary(one, blocked: false).isEmpty, "1点では距離も線も出ない")
        XCTAssertTrue(ProfileTravelRecord.othersTrips(one, blocked: false).isEmpty, "1枚は旅ではない")
        // 限定の写真しか無い人も「記録が無い人」の形
        let restrictedOnly = try mixed().filter { $0.audience == "followers" || $0.audience == "closeFriends" }
        XCTAssertTrue(ProfileTravelRecord.othersSummary(restrictedOnly, blocked: false).isEmpty)
    }

    /// 国名だけある人は国だけ出す（0 の距離は出さない・空ではない）
    func testCountriesWithoutDistanceIsNotEmpty() throws {
        let summary = ProfileTravelRecord.othersSummary([try photo("a", date: "2026-05-01", location: "台湾 台北")],
                                                        blocked: false)
        XCTAssertEqual(summary.countries, ["台湾"])
        XCTAssertEqual(summary.kilometers, 0)
        XCTAssertFalse(summary.isEmpty)
    }

    // MARK: - マイページは変わらない

    /// 🔴 マイページは**自分の写真すべて**（下書き・限定を含む）から、今までと同じ計算で作る
    func testMyPageSummaryIsUnchanged() throws {
        let photos = try mixed()
        let summary = ProfileTravelRecord.Summary(photos: photos)
        XCTAssertEqual(summary.kilometers, TravelDistance.total(of: photos))
        XCTAssertEqual(summary.countries, TravelRoute.countriesInOrder(photos))
        XCTAssertEqual(summary.coordinates, TravelRoute.coordinates(of: photos))
        XCTAssertEqual(summary.firstYear, TravelRoute.firstYear(of: photos))
        XCTAssertEqual(summary.countries.count, 4, "自分のページでは限定・下書きの写真の国も数える（今までどおり）")
    }

    /// マイページの説明の文は今までのまま（人のページの文とは分ける）
    func testMyPageNotesAreUnchanged() {
        XCTAssertEqual(ProfileTravelRecord.countriesNote(isMine: true),
                       L("撮影地に国・地域の名前が書かれている写真だけを数えています。地名から国を推測はしません。撮影地に国名を足すと、この数もサイトの地名ページも増えます。",
                         "Counts only photos whose location text names a country or region. We don't guess a country from a place name. Adding the country to your location text raises this number."))
        XCTAssertEqual(ProfileTravelRecord.distanceNote(isMine: true),
                       L("撮影地の分かる写真を、古い順に直線で結んだ合計です。実際に歩いた・乗った距離ではありません（道のりではなく直線で、撮っていない区間は飛び、座標は約1kmに丸めてあります）。",
                         "The straight-line total between photos that have coordinates, oldest first. Not the distance you actually travelled."))
        XCTAssertNotEqual(ProfileTravelRecord.countriesNote(isMine: false), ProfileTravelRecord.countriesNote(isMine: true))
        XCTAssertTrue(ProfileTravelRecord.countriesNote(isMine: false).contains(L("公開", "public")))
        XCTAssertTrue(ProfileTravelRecord.distanceNote(isMine: false).contains(L("公開", "public")))
    }

    // MARK: - 画面の配線（Linux では描けないので、書いてあることを見る）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 人のページは公開写真だけの口（`othersSummary`・`othersTrips`）を、ブロックの印つきで通す。
    /// 写真の一覧（`model.photos`）から直に作らない
    func testUserProfileWiresPublicOnlyRecord() throws {
        let user = try source("Features/Profile/UserProfileView.swift")
        XCTAssertTrue(user.contains("ProfileTravelRecord.othersSummary(shownPhotos, blocked: isBlocked)"))
        XCTAssertTrue(user.contains("ProfileTravelRecord.othersTrips(shownPhotos, blocked: isBlocked)"))
        XCTAssertTrue(user.contains("TravelRecordSection(summary: summary, isMine: false)"))
        XCTAssertTrue(user.contains("ProfileTripsLine(trips: trips"))
        XCTAssertFalse(user.contains("TravelDistance.total(of: model.photos)"), "限定の写真まで数える")
        XCTAssertFalse(user.contains("TripBook.shelfTrips(from: model.photos)"), "限定の写真まで束ねる")
        // 板 F33 の並び: 数 → 旅の記録 → 旅 → ハイライト
        let counts = try XCTUnwrap(user.range(of: "                        counts\n"))
        let record = try XCTUnwrap(user.range(of: "                        travelRecord\n"))
        let trips = try XCTUnwrap(user.range(of: "                        tripsLine\n"))
        let highlights = try XCTUnwrap(user.range(of: "HighlightsRow(userId: userId, isMine: false)"))
        XCTAssertTrue(counts.upperBound <= record.lowerBound && record.upperBound <= trips.lowerBound
                      && trips.upperBound <= highlights.lowerBound)
    }

    /// マイページは同じ部品を、自分の写真すべてで使う（見た目と動きは変えない）
    func testMyPageUsesSameSectionWithAllOwnPhotos() throws {
        let mine = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(mine.contains("ProfileTravelRecord.Summary(photos: model.photos)"))
        XCTAssertTrue(mine.contains("TravelRecordSection(summary: summary, isMine: true)"))
        XCTAssertFalse(mine.contains("othersSummary"), "マイページが公開写真だけに絞られた")
        XCTAssertFalse(mine.contains("TravelRecordView("), "旅の記録の部品の写しを残している")
        // 余白は今までの値（端 16・上 8）を部品が持つ
        let section = try source("Features/Profile/TravelRecordSection.swift")
        XCTAssertTrue(section.contains(".padding(.horizontal, ProfileV2.gutter)\n        .padding(.top, JPSpace.xs)"))
    }
}
