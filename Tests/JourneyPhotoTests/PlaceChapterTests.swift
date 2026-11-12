import XCTest
@testable import JourneyPhoto

/// デザインの案 第10章「どこに何を置くか」（2026-11-12）の置き場。札の並び（`HomeTopCardArrangeTests`）・
/// 設定（`SettingsOutlineTests`）・≡（`V2HomeSearchNotificationsTests`）・QR（`ProfileQRTests`）の外の分
final class PlaceChapterTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    // MARK: - マップ＝計画する

    /// 地図の下の「行きたい場所 N · 旅行プランを作る」は、地図を見ていて行きたい場所があり、札が出ていないときだけ
    func testMapWishlistLinkRule() {
        XCTAssertTrue(MapWishlistLink.shows(wishCount: 3, mode: .map, cardShown: false))
        XCTAssertFalse(MapWishlistLink.shows(wishCount: 0, mode: .map, cardShown: false), "行きたい場所が無いのに出す")
        XCTAssertFalse(MapWishlistLink.shows(wishCount: 3, mode: .list, cardShown: false))
        XCTAssertFalse(MapWishlistLink.shows(wishCount: 3, mode: .spots, cardShown: false))
        XCTAssertFalse(MapWishlistLink.shows(wishCount: 3, mode: .map, cardShown: true), "札と重なる")
        XCTAssertEqual(MapWishlistLink.title(count: 6), L("行きたい場所 6 · 旅行プランを作る", "Wishlist 6 · Plan a trip"))
    }

    /// 行き先は行きたい場所の地図（選んで旅行プランを作る）。並べ方はマイページの「地図で見る」と同じ
    func testMapWishlistOpensTheWishlistMap() throws {
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertTrue(map.contains("MapWishlistDestination(keys: wishlist.spotIds, photos: model.photos"))
        XCTAssertTrue(map.contains("SavedSpotsMapView(split: SavedSpotsMap.split(places: places, officialRows: rows)"))
        XCTAssertTrue(map.contains(".jpGlass(in: Capsule())"), "地図の上の口がガラスの地でない")
        XCTAssertTrue(map.contains(#".accessibilityIdentifier("map.wishlist")"#))
        // 地図の上は白（真鍮は黒地の上だけ）
        let link = try XCTUnwrap(map.range(of: "private var wishlistLink: some View {"))
        let body = String(map[link.upperBound...].prefix(1200))
        XCTAssertFalse(body.contains("WebTheme.accent)"), "地図の上に真鍮を置いている")
        // タブの名前は「マップ」のまま（owner の決定）
        XCTAssertEqual(Labels.Navigation.mapTab, L("マップ", "Map"))
    }

    // MARK: - 探す＝見つける

    /// 今日の一問は探すの段（取れた日だけ）。札の面はホームの上の札と同じ部品
    func testQuizLivesInSearch() throws {
        let search = try source("Features/Search/SearchView.swift")
        XCTAssertTrue(search.contains("model.discovery(spots: officialSpots, hasQuiz: quiz != nil)"))
        XCTAssertTrue(search.contains("case .quiz: quizSection"))
        XCTAssertTrue(search.contains("DailyQuizView(photos: model.everything)"))
        XCTAssertTrue(search.contains("TopCardFace(eyebrow: \"DAILY QUIZ\""))
        // 開いている間は差し替えない
        XCTAssertTrue(search.contains("guard !Task.isCancelled, quiz == nil || isOnScreen else { return }"))
        // 読むのは前面に出たとき（初めても戻りも）の1か所だけ（2026-11-12 確かめ役: 初めての表示で2回読んでいた）
        XCTAssertEqual(search.components(separatedBy: "await loadQuiz()").count - 1, 1, "一問を読む所が2か所ある")
        XCTAssertFalse(search.contains(".task { await loadQuiz() }"))
    }

    // MARK: - 見出し

    /// 見出しの「探す」は外した（下のタブと同じ所）。タブは5つのまま
    func testHeaderHasNoSearchAndTabsStayFive() throws {
        let header = try source("Features/Common/AppHeader.swift")
        XCTAssertFalse(header.contains("magnifyingglass"), "見出しに探すが戻った")
        XCTAssertFalse(header.contains("TabRouter.shared.openSearch()"))
    }

    // MARK: - 旅の仲間と話す場所は作らない

    /// グループの会話は作らない（点線の空きも出さない・DB の変更と見積もりが先）
    func testNoGroupChatPlaceholder() throws {
        for path in ["Features/Common/SiteMenuView.swift", "Features/Map/PhotoMapView.swift"] {
            let text = try source(path)
            XCTAssertFalse(text.contains("みんなで話す"), "\(path) にグループの会話の空きがある")
        }
    }
}
