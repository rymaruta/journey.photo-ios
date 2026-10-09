import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// バッジと Pro マークの受け取り（第1段階・2026-10-09）。
///
/// **サーバーは並行して作っている途中。** 古いサーバーは項目を返さず、新しい項目は
/// 型が揺れうる。どちらでもプロフィール全体の復号を落とさないことを見張る。
final class BadgeDecodingTests: XCTestCase {

    private func profile(_ json: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
    }

    /// 古いサーバー（項目が無い）: バッジ無し・Pro でない・印の形は既定の絞り羽根
    func testOldServerWithoutBadgeFields() throws {
        let p = try profile(#"{"userId":"u1","displayName":"丸田"}"#)
        XCTAssertTrue(p.earnedBadges.isEmpty)
        XCTAssertNil(p.shownBadge)
        XCTAssertNil(p.chosenBadgeKey)
        XCTAssertFalse(p.isPro)
        XCTAssertEqual(p.markStyle, .iris)
    }

    func testReadsBadgesChosenBadgeAndPro() throws {
        let p = try profile("""
        {"userId":"u1","badges":{"prefectures":{"tier":2,"at":"2026-10-01T09:00:00Z"},
         "earlyUser":{"tier":1,"at":"2026-09-01T00:00:00.000Z"}},
         "displayBadge":"prefectures","pro":true,"proMarkStyle":"plate"}
        """)
        XCTAssertEqual(p.earnedBadges["prefectures"], EarnedBadge(key: "prefectures", tier: 2, at: "2026-10-01T09:00:00Z"))
        XCTAssertEqual(p.shownBadge?.key, "prefectures")
        XCTAssertEqual(p.shownBadge?.tier, 2)
        XCTAssertTrue(p.isPro)
        XCTAssertEqual(p.markStyle, .plate)
    }

    /// **型の揺れで全体を落とさない。** 壊れたバッジ1つだけ落とし、ほかは読む
    func testBrokenFieldsDoNotBreakTheProfile() throws {
        let p = try profile("""
        {"userId":"u1","displayName":"丸田",
         "badges":{"first":{"tier":"1"},"night":{"tier":"x"},"wish":{"tier":0},"books":"bad","seasons":{"tier":3.0}},
         "displayBadge":42,"pro":"yes","proMarkStyle":"rainbow"}
        """)
        XCTAssertEqual(p.displayName, "丸田")
        XCTAssertEqual(p.earnedBadges["first"]?.tier, 1, "数の文字列も段として読む")
        XCTAssertEqual(p.earnedBadges["seasons"]?.tier, 3)
        XCTAssertNil(p.earnedBadges["night"])
        XCTAssertNil(p.earnedBadges["wish"], "0段は持っていない")
        XCTAssertNil(p.earnedBadges["books"])
        XCTAssertNil(p.chosenBadgeKey, "文字でない選択は「選んでいない」")
        XCTAssertFalse(p.isPro)
        XCTAssertEqual(p.markStyle, .iris, "知らない形は既定")
    }

    /// `badges` 自体が配列などで壊れていても、プロフィールは読める
    func testBadgesOfWrongShapeAreEmpty() throws {
        let p = try profile(#"{"userId":"u1","badges":[1,2,3],"displayBadge":"first"}"#)
        XCTAssertTrue(p.earnedBadges.isEmpty)
        XCTAssertEqual(p.chosenBadgeKey, "first")
        XCTAssertNil(p.shownBadge, "持っていない鍵を選んでいても名前の横には出さない")
    }

    func testNullValuesAreAbsent() throws {
        let p = try profile(#"{"userId":"u1","badges":null,"displayBadge":null,"pro":null,"proMarkStyle":null}"#)
        XCTAssertTrue(p.earnedBadges.isEmpty)
        XCTAssertNil(p.chosenBadgeKey)
        XCTAssertFalse(p.isPro)
    }

    // MARK: - GET /user/badges

    func testBadgeStatusReadsProgress() throws {
        let status = try JSONDecoder.api.decode(BadgeStatus.self, from: Data("""
        {"badges":{"prefectures":{"tier":1,"at":"2026-10-01T00:00:00Z"}},
         "progress":{"prefectures":{"count":13,"tier":1,"next":30},
                     "first":{"count":1,"tier":1,"next":null},
                     "night":{"count":"2","tier":0,"next":5},
                     "broken":{"tier":1}}}
        """.utf8))
        XCTAssertEqual(status.badges["prefectures"]?.tier, 1)
        XCTAssertEqual(status.progress["prefectures"], BadgeProgress(count: 13, tier: 1, next: 30))
        XCTAssertEqual(status.progress["first"], BadgeProgress(count: 1, tier: 1, next: nil))
        XCTAssertEqual(status.progress["night"], BadgeProgress(count: 2, tier: 0, next: 5))
        XCTAssertNil(status.progress["broken"], "数の無い項目は落とす")
    }

    /// **`badges` の無い応答は投げる**（形の違う応答を「何も持っていない」と混ぜない）
    func testBadgeStatusWithoutBadgesThrows() {
        XCTAssertThrowsError(try JSONDecoder.api.decode(BadgeStatus.self, from: Data(#"{"progress":{}}"#.utf8)))
    }

    func testBadgeStatusWithoutProgressStillReads() throws {
        let status = try JSONDecoder.api.decode(BadgeStatus.self, from: Data(#"{"badges":{}}"#.utf8))
        XCTAssertTrue(status.badges.isEmpty)
        XCTAssertTrue(status.progress.isEmpty)
    }
}

// MARK: - 送る形

final class BadgePatchTests: XCTestCase {

    private func json(_ patch: ProfilePatch) throws -> [String: Any] {
        let data = try JSONEncoder().encode(patch)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func profile(_ json: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
    }

    /// **外すときは null を送る。** nil は「触らない」で、JSON に載せない
    func testClearSendsNullAndUntouchedIsOmitted() throws {
        var patch = ProfilePatch()
        XCTAssertNil(try json(patch)["displayBadge"])

        patch.displayBadge = Clearable(nil)
        let cleared = try json(patch)
        XCTAssertTrue(cleared.keys.contains("displayBadge"))
        XCTAssertTrue(cleared["displayBadge"] is NSNull)

        patch.displayBadge = Clearable("first")
        patch.proMarkStyle = "plate"
        let set = try json(patch)
        XCTAssertEqual(set["displayBadge"] as? String, "first")
        XCTAssertEqual(set["proMarkStyle"] as? String, "plate")
    }

    /// 決めたときに送るものは**変わったものだけ**。何も変えなければ送らない
    func testNameSidePatchSendsOnlyChanges() throws {
        let p = try profile(#"{"userId":"u1","badges":{"first":{"tier":1},"night":{"tier":2}},"displayBadge":"first"}"#)
        XCTAssertEqual(NameSideChoice.initialSelection(p), "first")
        XCTAssertNil(NameSideChoice.patch(profile: p, selected: "first", style: .iris))

        let changed = try XCTUnwrap(NameSideChoice.patch(profile: p, selected: "night", style: .plate))
        XCTAssertEqual(changed.displayBadge, Clearable("night"))
        XCTAssertNil(changed.proMarkStyle, "Pro でない人は形を送らない")

        let cleared = try XCTUnwrap(NameSideChoice.patch(profile: p, selected: nil, style: .iris))
        XCTAssertEqual(cleared.displayBadge, Clearable(nil))
    }

    /// 🔴 **持っているがアプリの知らない鍵を飾っている人が「決める」だけ押しても外さない**（バグ調査 低-1）。
    /// 持っていない鍵（取り消された・古い値）は今までどおり消す
    func testNameSideKeepsUnknownOwnedBadge() throws {
        let unknown = try profile(#"{"userId":"u1","badges":{"supporter":{"tier":1},"first":{"tier":1}},"displayBadge":"supporter"}"#)
        XCTAssertNil(NameSideChoice.initialSelection(unknown))
        XCTAssertNil(NameSideChoice.patch(profile: unknown, selected: nil, style: .iris))
        // 選び直したら送る
        XCTAssertEqual(NameSideChoice.patch(profile: unknown, selected: "first", style: .iris)?.displayBadge, Clearable("first"))

        let revoked = try profile(#"{"userId":"u1","badges":{"first":{"tier":1}},"displayBadge":"night"}"#)
        XCTAssertEqual(NameSideChoice.patch(profile: revoked, selected: nil, style: .iris)?.displayBadge, Clearable(nil))
    }

    func testNameSidePatchSendsMarkStyleForPro() throws {
        let p = try profile(#"{"userId":"u1","pro":true,"proMarkStyle":"iris"}"#)
        let patch = try XCTUnwrap(NameSideChoice.patch(profile: p, selected: nil, style: .plate))
        XCTAssertEqual(patch.proMarkStyle, "plate")
        XCTAssertNil(patch.displayBadge)
    }

    /// 持っていない鍵を指していた人は「なし」で開き、決めると古い値を消す
    func testStaleChoiceOpensAsNoneAndIsClearedOnSave() throws {
        let p = try profile(#"{"userId":"u1","badges":{"first":{"tier":1}},"displayBadge":"gone"}"#)
        XCTAssertNil(NameSideChoice.initialSelection(p))
        let patch = try XCTUnwrap(NameSideChoice.patch(profile: p, selected: nil, style: .iris))
        XCTAssertEqual(patch.displayBadge, Clearable(nil))
    }
}

// MARK: - 大きさ

final class BadgeSizeTests: XCTestCase {

    /// **円の部分を公式の封印と同じ 22pt に**（明朝 26）。絵は余白の分だけ大きく、はみ出しは負の余白で消す
    func testNameSideBadgeSizesAtName26() {
        XCTAssertEqual(BadgeFit.circle(nameSize: 26), 22, accuracy: 0.0001)
        XCTAssertEqual(BadgeFit.imageSide("prefectures", nameSize: 26), 22.4, accuracy: 0.0001)
        XCTAssertEqual(BadgeFit.overhang("prefectures", nameSize: 26), 0.2, accuracy: 0.0001)
        XCTAssertEqual(BadgeFit.imageSide("earlyUser", nameSize: 26), 30.8, accuracy: 0.0001)
        XCTAssertEqual(BadgeFit.overhang("earlyUser", nameSize: 26), 4.4, accuracy: 0.0001)
    }

    /// 名前の字に比例する（文字サイズの設定で伸ばした値を渡しても同じ割合）
    func testBadgeScalesWithName() {
        XCTAssertEqual(BadgeFit.circle(nameSize: 13), 11, accuracy: 0.0001)
        XCTAssertEqual(BadgeFit.circle(nameSize: 39), 33, accuracy: 0.0001)
        XCTAssertEqual(BadgeFit.imageSide("earlyUser", nameSize: 39) / BadgeFit.imageSide("earlyUser", nameSize: 26),
                       1.5, accuracy: 0.01)
    }

    /// Pro マーク: 明朝 26 で 21.7（公式の封印と同じ）、写真の詳細の作者 13 で 11.5（板）
    func testProMarkSizes() {
        XCTAssertEqual(ProMarkFit.side(nameSize: 26, mincho: true), 21.7, accuracy: 0.0001)
        XCTAssertEqual(ProMarkFit.side(nameSize: 13, mincho: false), 11.5, accuracy: 0.0001)
        XCTAssertFalse(ProMarkFit.isSmall(side: 21.7))
        XCTAssertTrue(ProMarkFit.isSmall(side: 11.5), "15pt を切ったら線の太い小さい版")
        // 札は横長（大 42:24 → 名前 26 の横で 38.0・板 UserProfile）
        XCTAssertEqual(ProMarkFit.width(side: 21.7, style: .plate), 37.975, accuracy: 0.001)
        XCTAssertEqual(ProMarkFit.width(side: 12, style: .plate), 18, accuracy: 0.001)
        XCTAssertEqual(ProMarkFit.width(side: 21.7, style: .iris), 21.7, accuracy: 0.001)
    }

    /// 絞り羽根の形は素材の SVG のまま（羽根の外の端は丸の縁に乗る）
    func testIrisGeometryMatchesTheKit() {
        XCTAssertEqual(ProMarkGeometry.aperture(small: false).count, 6)
        XCTAssertEqual(ProMarkGeometry.aperture(small: true).count, 6)
        XCTAssertEqual(ProMarkGeometry.bladeEnds.count, 6)
        for end in ProMarkGeometry.bladeEnds {
            let r = hypot(Double(end.x) - 12, Double(end.y) - 12)
            XCTAssertEqual(r, ProMarkGeometry.discRadius, accuracy: 0.05)
        }
        // 小さい版は穴が大きく、線が太い
        XCTAssertLessThan(Double(ProMarkGeometry.aperture(small: true)[0].y),
                          Double(ProMarkGeometry.aperture(small: false)[0].y))
        XCTAssertGreaterThan(ProMarkGeometry.bladeWidth(small: true), ProMarkGeometry.bladeWidth(small: false))
    }
}

// MARK: - 台帳

final class BadgeCatalogTests: XCTestCase {

    private func badges(_ json: String) throws -> BadgeSet {
        try JSONDecoder.api.decode(BadgeSet.self, from: Data(json.utf8))
    }

    func testNamesTiersAndImages() {
        XCTAssertEqual(BadgeCatalog.kinds.map(\.key),
                       ["earlyUser", "first", "prefectures", "countries", "seasons", "morning", "night", "books", "wish"])
        XCTAssertEqual(BadgeCatalog.kind("wish")?.ja, "行けた場所")
        XCTAssertEqual(BadgeCatalog.kind("first")?.maxTier, 1)
        XCTAssertEqual(BadgeCatalog.smallImage("morning", tier: 2), "medal-morning-2-s")
        XCTAssertEqual(BadgeCatalog.largeImage("morning", tier: 3), "medal-morning-3")
        XCTAssertEqual(BadgeCatalog.smallImage("earlyUser", tier: 1), "medal-earlyUser-s")
        // 台帳より上の段は、絵のある段に収める
        XCTAssertEqual(BadgeCatalog.largeImage("first", tier: 3), "medal-first-1")
        XCTAssertEqual(BadgeCatalog.largeImage("night", tier: 9), "medal-night-3")
        XCTAssertFalse(BadgeCatalog.isKnown("springChapter"))
    }

    /// 段ごとの金属（裏と縁）。初期ユーザーは真鍮
    func testMetals() {
        XCTAssertEqual(BadgeCatalog.metal("books", tier: 1), .bronze)
        XCTAssertEqual(BadgeCatalog.metal("books", tier: 2), .silver)
        XCTAssertEqual(BadgeCatalog.metal("books", tier: 3), .platinum)
        XCTAssertEqual(BadgeCatalog.metal("earlyUser", tier: 1), .brass)
        XCTAssertEqual(BadgeCatalog.Metal.silver.reverseImage, "reverse-silver")
        XCTAssertEqual(BadgeCatalog.Metal.brass.edgeImage, "edge-brass")
    }

    /// 自分の棚: 持っているもの＋まだのもの。**後から取れない初期ユーザーは持っているときだけ。知らない鍵は出さない**
    func testOwnShelfShowsLockedButNotClosedOrUnknown() throws {
        let set = try badges(#"{"prefectures":{"tier":2},"springChapter":{"tier":1}}"#)
        let items = BadgeCatalog.shelf(badges: set, progress: [
            "prefectures": BadgeProgress(count: 30, tier: 2, next: 47),
            "night": BadgeProgress(count: 0, tier: 0, next: 5),
        ])
        XCTAssertEqual(items.map(\.key), ["first", "prefectures", "countries", "seasons", "morning", "night", "books", "wish"])
        XCTAssertEqual(items.first { $0.key == "prefectures" }?.isEarned, true)
        XCTAssertEqual(items.first { $0.key == "prefectures" }?.tier, 2)
        XCTAssertEqual(items.first { $0.key == "night" }?.isEarned, false)
        XCTAssertEqual(items.first { $0.key == "night" }?.tier, 1, "まだのものは1段の絵を暗く")
        XCTAssertEqual(BadgeCatalog.shelfCount(items).earned, 1)
        XCTAssertEqual(BadgeCatalog.shelfCount(items).total, 8)

        let withEarly = BadgeCatalog.shelf(badges: try badges(#"{"earlyUser":{"tier":1}}"#), progress: [:])
        XCTAssertEqual(withEarly.first?.key, "earlyUser")
    }

    /// 人の棚: **持っているものだけ**・進み具合なし
    func testOtherShelfShowsOnlyEarned() throws {
        let set = try badges(#"{"night":{"tier":1},"earlyUser":{"tier":1}}"#)
        let items = BadgeCatalog.shelf(badges: set, progress: nil)
        XCTAssertEqual(items.map(\.key), ["earlyUser", "night"])
        XCTAssertTrue(items.allSatisfy { $0.progress == nil })
    }

    /// 「あと◯で次」「達成」「あと◯枚」（板 Shelf）
    func testProgressTexts() {
        XCTAssertEqual(BadgeCatalog.progressText("prefectures", progress: BadgeProgress(count: 30, tier: 2, next: 47), earned: true),
                       L("あと17で次", "17 more to next"))
        XCTAssertEqual(BadgeCatalog.progressText("morning", progress: BadgeProgress(count: 25, tier: 1, next: 50), earned: true),
                       L("あと25枚で次", "25 more photos to next"))
        XCTAssertEqual(BadgeCatalog.progressText("books", progress: BadgeProgress(count: 7, tier: 1, next: 10), earned: true),
                       L("あと3冊で次", "3 more books to next"))
        XCTAssertEqual(BadgeCatalog.progressText("night", progress: BadgeProgress(count: 0, tier: 0, next: 5), earned: false),
                       L("あと5枚", "5 more photos to earn"))
        XCTAssertEqual(BadgeCatalog.progressText("first", progress: BadgeProgress(count: 1, tier: 1, next: nil), earned: true),
                       L("達成", "Complete"))
        XCTAssertEqual(BadgeCatalog.progressText("wish", progress: BadgeProgress(count: 40, tier: 3, next: nil), earned: true),
                       L("達成", "Complete"))
        // 進み具合の無い古いサーバー: 段のあるものは何も言わない・段の無いものは達成
        XCTAssertNil(BadgeCatalog.progressText("wish", progress: nil, earned: true))
        XCTAssertEqual(BadgeCatalog.progressText("first", progress: nil, earned: true), L("達成", "Complete"))
        XCTAssertNil(BadgeCatalog.progressText("night", progress: nil, earned: false))
        XCTAssertNil(BadgeCatalog.progressText("unknown", progress: BadgeProgress(count: 1, tier: 0, next: 2), earned: false))
    }

    func testFullNamesAndOwnedOrder() throws {
        XCTAssertEqual(BadgeCatalog.fullName("countries", tier: 3), L("国・地域 · 白金", "Countries · Platinum"))
        XCTAssertEqual(BadgeCatalog.fullName("earlyUser", tier: 1), L("初期ユーザー", "Early user"))
        let owned = BadgeCatalog.owned(try badges(#"{"wish":{"tier":1},"zzz":{"tier":1},"first":{"tier":1}}"#))
        XCTAssertEqual(owned.map(\.key), ["first", "wish"])
    }

    /// 裏に刻む日付（「2026.10.09」）。端末の時刻帯で日を決める
    func testAwardDate() throws {
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(BadgeCatalog.awardDate("2026-10-08T20:00:00Z", timeZone: tokyo), "2026.10.09")
        XCTAssertEqual(BadgeCatalog.awardDate("2026-10-08T20:00:00.123Z", timeZone: utc), "2026.10.08")
        XCTAssertEqual(BadgeCatalog.awardDate("2026-10-09", timeZone: utc), "2026.10.09")
        XCTAssertNil(BadgeCatalog.awardDate("きのう"))
        XCTAssertNil(BadgeCatalog.awardDate(nil))
    }

    /// 棚の読み上げ
    func testShelfLabels() {
        let earned = BadgeCatalog.ShelfItem(key: "prefectures", tier: 2,
                                            earned: EarnedBadge(key: "prefectures", tier: 2, at: nil),
                                            progress: L("あと17で次", "17 more to next"))
        XCTAssertEqual(BadgeShelfRules.label(earned),
                       L("都道府県 · 銀、あと17で次", "Prefectures · Silver, 17 more to next"))
        let locked = BadgeCatalog.ShelfItem(key: "night", tier: 1, earned: nil, progress: nil)
        XCTAssertEqual(BadgeShelfRules.label(locked), L("夜の光、まだ持っていません", "Night light, not earned yet"))
    }
}

// MARK: - 手に取って回す画面の貼り絵

final class MedalTextureLayoutTests: XCTestCase {

    /// **絵の円が貼り絵いっぱいに**なるよう拡大する（余白・後光は外へ落ちる）
    func testFillRectMakesTheDiscFillTheTexture() {
        let side = MedalTextureLayout.textureSide
        let free = MedalTextureLayout.fillRect(discRatio: BadgeCatalog.discRatio("night"))
        XCTAssertEqual(Double(free.width) * 0.984, side, accuracy: 0.01)
        XCTAssertEqual(Double(free.midX), side / 2, accuracy: 0.01)
        let early = MedalTextureLayout.fillRect(discRatio: BadgeCatalog.discRatio("earlyUser"))
        XCTAssertEqual(Double(early.width) * 0.715, side, accuracy: 0.01)
        XCTAssertLessThan(Double(early.minX), Double(free.minX), "後光の分だけ大きく描く")
    }

    /// 裏の名前と日付は板の位置（300pt の面で中心から +86 / +102）
    func testBackTextPositions() {
        let side = 295.2  // 半径 147.6 の面と同じ大きさ（板の pt のまま比べる）
        XCTAssertEqual(MedalTextureLayout.nameCenterY(side: side), 147.6 + 86, accuracy: 0.001)
        XCTAssertEqual(MedalTextureLayout.dateCenterY(side: side), 147.6 + 102, accuracy: 0.001)
        XCTAssertEqual(MedalTextureLayout.boardToTexture(16, side: side), 16, accuracy: 0.001)
    }

    /// 長い名前は縮める（板の 7 割まで）。短い名前はそのまま
    func testLongNamesShrink() {
        let side = MedalTextureLayout.textureSide
        let base = MedalTextureLayout.boardToTexture(MedalTextureLayout.nameFont)
        XCTAssertEqual(MedalTextureLayout.nameFontSize(textWidthAtBase: 100), base, accuracy: 0.001)
        let limit = side * MedalTextureLayout.nameMaxWidth
        XCTAssertEqual(MedalTextureLayout.nameFontSize(textWidthAtBase: limit * 1.25), base / 1.25, accuracy: 0.001)
        XCTAssertEqual(MedalTextureLayout.nameFontSize(textWidthAtBase: limit * 5), base * 0.7, accuracy: 0.001)
    }

    /// 縁の帯は円周に合わせて繰り返す（858pt の帯・半径 147.6 で約 1.08 回）。厚みは板の 18pt
    func testEdgeRepeatAndThickness() {
        XCTAssertEqual(MedalTextureLayout.edgeRepeat(), 2 * Double.pi * 147.6 / 858, accuracy: 0.0001)
        XCTAssertEqual(MedalTextureLayout.edgeRepeat(discRadius: 136.5), 1, accuracy: 0.001)
        XCTAssertEqual(MedalTextureLayout.thicknessPerRadius, 18 / 147.6, accuracy: 0.0001)
    }

    func testCoinSideFitsTheScreen() {
        XCTAssertEqual(MedalTextureLayout.coinSide(screenWidth: 390), 350)
        XCTAssertEqual(MedalTextureLayout.coinSide(screenWidth: 440), 360)
        XCTAssertEqual(MedalTextureLayout.coinSide(screenWidth: 100), 160)
    }
}

// MARK: - お知らせ

final class BadgeNotificationTests: XCTestCase {

    private func notification(_ json: String) throws -> AppNotification {
        try JSONDecoder.api.decode(AppNotification.self, from: Data(json.utf8))
    }

    func testDecodesBadgeNotification() throws {
        let n = try notification(#"{"type":"badge","key":"morning","tier":1,"t":"2026-10-09T08:00:00Z"}"#)
        XCTAssertEqual(n.kind, .badge)
        XCTAssertEqual(n.key, "morning")
        XCTAssertEqual(n.tier, 1)
        // 同じ時刻の2つのメダルを別の行にする
        let other = try notification(#"{"type":"badge","key":"night","tier":1,"t":"2026-10-09T08:00:00Z"}"#)
        XCTAssertNotEqual(n.id, other.id)
    }

    /// 板 15: 「**朝の光**のメダルを手に入れました · 銅」
    func testBadgeLine() throws {
        let n = try notification(#"{"type":"badge","key":"morning","tier":1}"#)
        let line = try XCTUnwrap(NotificationText.line(for: NotificationText.Entry(lead: n, others: 0, unread: false)))
        XCTAssertEqual(line.who, L("朝の光", "Morning light"))
        XCTAssertEqual(line.plain, L("朝の光のメダルを手に入れました · 銅", "Morning light medal earned · Bronze"))
        let early = try notification(#"{"type":"badge","key":"earlyUser","tier":1}"#)
        XCTAssertEqual(NotificationText.badgeLine(early)?.plain,
                       L("初期ユーザーのメダルを手に入れました", "Early user medal earned"))
        XCTAssertNil(NotificationText.thumbnailURL(n))
    }

    /// 知らない鍵・鍵の無いメダルは**出さない**（既定の文言で嘘を出さない）
    func testUnknownBadgeIsNotShown() throws {
        let unknown = try notification(#"{"type":"badge","key":"springChapter","tier":1}"#)
        XCTAssertNil(NotificationText.line(for: NotificationText.Entry(lead: unknown, others: 0, unread: false)))
        let keyless = try notification(#"{"type":"badge"}"#)
        XCTAssertNil(NotificationText.badgeLine(keyless))
    }

    /// メダルは「すべて」にだけ出す
    func testBadgeAppearsOnlyUnderAll() {
        XCTAssertTrue(NotificationFilter.all.matches(.badge))
        XCTAssertFalse(NotificationFilter.like.matches(.badge))
        XCTAssertFalse(NotificationFilter.comment.matches(.badge))
        XCTAssertFalse(NotificationFilter.follow.matches(.badge))
    }

    /// プッシュの中身: 段は数で届いても読む
    func testFromPushReadsKeyAndNumericTier() {
        let n = AppNotification.fromPush(["type": "badge", "key": "books", "tier": 2, "aps": ["alert": "x"]])
        XCTAssertEqual(n?.kind, .badge)
        XCTAssertEqual(n?.key, "books")
        XCTAssertEqual(n?.tier, 2)
        let s = AppNotification.fromPush(["type": "badge", "key": "books", "tier": "3"])
        XCTAssertEqual(s?.tier, 3)
    }
}

@MainActor
final class BadgeNotificationDestinationTests: XCTestCase {

    private func notification(_ json: String) throws -> AppNotification {
        try JSONDecoder.api.decode(AppNotification.self, from: Data(json.utf8))
    }

    /// 新しいメダルを押すと自分のバッジの棚
    func testBadgeOpensTheShelf() async throws {
        let model = NotificationsViewModel()
        let n = try notification(#"{"type":"badge","key":"night","tier":2}"#)
        XCTAssertEqual(model.route(for: n), .shelf)
        let unknown = try notification(#"{"type":"badge","key":"springChapter","tier":1}"#)
        XCTAssertNil(model.route(for: unknown))
    }
}

// MARK: - 読み込み（通信を差し替えて走らせる）

final class BadgeServiceTests: XCTestCase {

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

    private func service() -> ProfileService {
        ProfileService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                      tokenProvider: StubTokenProvider(token: "ID-TOKEN"),
                                      session: session))
    }

    /// `GET /user/badges` を鍵つきで叩く
    func testMyBadgesHitsTheAuthorizedEndpoint() async throws {
        StubProtocol.respond(status: 200, body: #"{"badges":{"first":{"tier":1,"at":"2026-10-01T00:00:00Z"}},"progress":{"first":{"count":1,"tier":1,"next":null}}}"#)
        let status = try await service().myBadges()
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/badges")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer ID-TOKEN")
        XCTAssertEqual(status.badges["first"]?.tier, 1)
    }

    /// 名前の横の保存は今のプロフィールの更新の口（PUT /user/profile）に、外すなら null で載る
    func testSavingTheChoiceSendsNullThroughProfileUpdate() async throws {
        StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
        var patch = ProfilePatch()
        patch.displayBadge = Clearable(nil)
        try await service().update(patch)
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/profile")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertTrue(json["displayBadge"] is NSNull)
    }
}
