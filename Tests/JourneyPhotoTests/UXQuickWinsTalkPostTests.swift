import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 使い勝手の見直し 2026-11-16 の「すぐ作る」案のうち A3・A8・A11（owner「使い勝手にフォーカスして最高の UI にしたい」）。
///
/// - A3 マイページの表紙の右上に、ほかのタブと同じ吹き出しとベル（DM・お知らせ 2回 → 1回）
/// - A8 リクエストを承認したら、そのまま会話を開いて書く欄にキーボード（一覧から 承認 → メッセージを見る → 欄 → 送る の4回 → 承認 → 送る の2回）
/// - A11 投稿を書く画面: 編集の入口は写真の札1つ、「地図に位置を載せる」は欄の下の1行、撮影地の状態の一言と候補のチップ
///
/// 画面の部品は Linux で動かせないので、決まりは値で、配線は元のコードを読んで確かめる
@MainActor
final class UXQuickWinsTalkPostTests: XCTestCase {

    // MARK: - 道具

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `start` から次の `end` の手前まで
    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let head = text.range(of: start) else { return "" }
        let rest = text[head.upperBound...]
        guard let tail = rest.range(of: end) else { return String(rest) }
        return String(rest[..<tail.lowerBound])
    }

    private func spot(_ slug: String, name: String, lat: Double, lng: Double) throws -> OfficialSpot {
        let json = "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name)\",\"stage\":\"published\","
            + "\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}}"
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private func freshDefaults() -> UserDefaults {
        let name = "UXQuickWinsTalkPostTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - A3 マイページの吹き出しとベル

    /// 表紙の右上は 吹き出し → ベル → 歯車 の順。歯車はそのまま、左に足す
    func testMyPageTopButtonsOrder() async throws {
        let page = try source("Features/Profile/MyPageView.swift")
        let top = slice(page, from: "private var topButtons: some View {", to: "private var settingsButton")
        XCTAssertTrue(top.contains("HStack(spacing: AppHeaderGlassInbox.gap)"))
        let inbox = try XCTUnwrap(top.range(of: "AppHeaderGlassInbox(")?.lowerBound, "吹き出しとベルが無い")
        let gear = try XCTUnwrap(top.range(of: "settingsButton")?.lowerBound, "歯車が無い")
        XCTAssertLessThan(inbox, gear, "吹き出しとベルが歯車の左に無い")
        // 表紙の上に置くのはこの並び（歯車だけを置く形に戻さない）
        XCTAssertTrue(page.contains("topButtons\n                            .padding(.top, hasCover ? topInset : 0)"))
        XCTAssertFalse(page.contains("settingsButton\n                            .padding(.top, hasCover ? topInset : 0)"))
    }

    /// 中身（押した先・読み上げ・未読の点）は見出しと同じもの。写しを作らない
    func testMyPageInboxSharesTheHeader() async throws {
        let header = try source("Features/Common/AppHeader.swift")
        let glass = slice(header, from: "struct AppHeaderGlassInbox: View {", to: "\nextension View {")
        XCTAssertTrue(glass.contains("AppHeaderInbox.openMessages()"), "吹き出しが受信箱を開かない")
        XCTAssertTrue(glass.contains("Button(action: onOpenNotifications)"), "ベルがお知らせを開かない")
        XCTAssertTrue(glass.contains("AppHeaderInbox.messagesLabel(unread: messagesUnread)"))
        XCTAssertTrue(glass.contains("AppHeaderInbox.bellLabel(unread: unread > 0)"))
        XCTAssertTrue(glass.contains("circle(AppHeaderInbox.messagesSymbol, dot: messagesUnread)"))
        XCTAssertTrue(glass.contains("circle(AppHeaderInbox.bellSymbol, dot: unread > 0)"))
        // 未読は真鍮の点、丸は歯車と同じガラス 44
        // 点の色（2026-11-16 判断）: カバー写真の上は白、黒地は真鍮。縁は黒 2pt
        XCTAssertEqual(AppHeaderGlassInbox.dotTone(onPhoto: true), .white, "写真の上の点が真鍮（読めない）")
        XCTAssertEqual(AppHeaderGlassInbox.dotTone(onPhoto: false), .brass, "黒地の点が真鍮でない")
        let tone = slice(header, from: "static func dotColor(onPhoto: Bool) -> Color {", to: "/// 点の色の種類")
        XCTAssertTrue(tone.contains("case .white: return Color.white"))
        XCTAssertTrue(tone.contains("case .brass: return WebTheme.accent"))
        XCTAssertTrue(glass.contains("Self.dotColor(onPhoto: onPhoto)"))
        XCTAssertTrue(glass.contains(".strokeBorder(WebTheme.background, lineWidth: 2)"))
        let page = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(page.contains("onPhoto: hasCover,"), "マイページがカバーの有無を点に渡していない")
        XCTAssertTrue(glass.contains(".jpGlass(in: Circle())"))
        XCTAssertTrue(glass.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"))
        XCTAssertEqual(AppHeaderGlassInbox.gap, 8)
        // 見出しの読み上げも同じ口から
        XCTAssertTrue(header.contains(".accessibilityLabel(AppHeaderInbox.messagesLabel(unread: messagesUnread))"))
        XCTAssertTrue(header.contains(".accessibilityLabel(AppHeaderInbox.bellLabel(unread: unread > 0))"))
        XCTAssertEqual(AppHeaderInbox.messagesLabel(unread: true), L("メッセージ（未読あり）", "Messages, unread"))
        XCTAssertEqual(AppHeaderInbox.bellLabel(unread: false), L("お知らせ", "Activity"))
    }

    /// 値はほかのタブと同じものを配る（未読の数・受信箱の未読・ベルを押したとき）
    func testRootPassesUnreadToMyPage() async throws {
        let root = try source("App/RootView.swift")
        let page = slice(root, from: "MyPageView(", to: ".perfMark(\"tab.mypage.appear\")")
        XCTAssertTrue(page.contains("unread: unread, onOpenNotifications: { openNotificationsFromBell() },"),
                      "マイページにお知らせの未読とベルの処理が届いていない")
        XCTAssertTrue(page.contains("messagesUnread: messagesUnread"), "マイページに受信箱の未読が届いていない")
    }

    // MARK: - A8 承認したら、そのまま会話へ

    func testRequestBandHidesOnceAcceptedHere() async throws {
        XCTAssertTrue(DMAcceptArrival.showsRequestBand(state: .request, acceptedHere: false))
        XCTAssertFalse(DMAcceptArrival.showsRequestBand(state: .request, acceptedHere: true),
                       "承認したのに、読み直しが古い request を返して帯が戻る")
        XCTAssertFalse(DMAcceptArrival.showsRequestBand(state: .inbox, acceptedHere: false))
        XCTAssertFalse(DMAcceptArrival.showsRequestBand(state: nil, acceptedHere: false))
    }

    /// 一覧の「承認」から開いた直後（会話を読み終える前・`acceptedHere` はまだ false）も帯を出さない
    func testRequestBandHiddenRightAfterOpeningFromListAccept() async throws {
        XCTAssertFalse(DMAcceptArrival.showsRequestBand(state: .request, acceptedHere: false, openedAfterAccept: true),
                       "一覧で承認して開いた直後に、古い request のまま帯が出る")
        XCTAssertTrue(DMAcceptArrival.showsRequestBand(state: .request, acceptedHere: false, openedAfterAccept: false))
        let view = try source("Features/Messages/DMConversationView.swift")
        let band = slice(view, from: "private var isIncomingRequest: Bool {", to: "\n    }\n")
        XCTAssertTrue(band.contains("openedAfterAccept: openedAfterAccept"), "会話の画面が「一覧から承認して開いた」を帯に渡していない")
        XCTAssertTrue(band.contains("acceptedHere: acceptedHere"))
    }

    func testFocusOnlyOnceAfterLoad() async throws {
        XCTAssertTrue(DMAcceptArrival.focusesOnOpen(openedAfterAccept: true, done: false, loaded: true))
        XCTAssertFalse(DMAcceptArrival.focusesOnOpen(openedAfterAccept: true, done: true, loaded: true), "戻ってきた回にまた出す")
        XCTAssertFalse(DMAcceptArrival.focusesOnOpen(openedAfterAccept: true, done: false, loaded: false), "読めていないのに当てる")
        XCTAssertFalse(DMAcceptArrival.focusesOnOpen(openedAfterAccept: false, done: false, loaded: true))
    }

    /// 一覧の「承認」は会話を積む（知らせの「メッセージを見る」で開かせない）
    func testListAcceptOpensTheConversation() async throws {
        let list = try source("Features/Messages/DMRequestsView.swift")
        let accept = slice(list, from: "private func accept(_ request: DMThread) async {", to: "private func decline(")
        XCTAssertTrue(accept.contains("route = Route(id: request.id, accepted: true)"), "承認しても会話を開かない")
        XCTAssertFalse(list.contains("メッセージを見る"), "承認の知らせから会話を開く2手目が残っている")
        XCTAssertTrue(list.contains("DMConversationView(conversationId: route.id, openedAfterAccept: route.accepted)"))
    }

    /// 会話の画面: 承認したら欄にキーボードと知らせ。「返信すると承認されます」は帯の1か所だけ
    func testConversationFocusesAfterAccept() async throws {
        let view = try source("Features/Messages/DMConversationView.swift")
        XCTAssertFalse(view.contains("返信すると承認されます"), "帯と欄の上で同じ説明が2回出る")
        XCTAssertTrue(view.contains("返信すると承認したことになり"), "帯の説明が消えた")
        let arrive = slice(view, from: "private func arriveAccepted() {", to: "private func declineRequest()")
        XCTAssertTrue(arrive.contains("acceptedHere = true"))
        XCTAssertTrue(arrive.contains("acceptedNotice = UUID()"))
        XCTAssertTrue(arrive.contains("fieldFocused = true"), "承認しても欄にキーボードが出ない")
        let accept = slice(view, from: "private func accept() async {", to: "private func arriveAccepted()")
        XCTAssertTrue(accept.contains("arriveAccepted()"), "帯の承認のあと欄に当てない")
        XCTAssertTrue(view.contains("DMAcceptArrival.focusesOnOpen(openedAfterAccept: openedAfterAccept"))
        XCTAssertTrue(view.contains("DMActionToast(text: DMText.acceptedNotice)"))
        XCTAssertEqual(DMText.acceptedNotice, L("承認しました。受信箱に移りました", "Accepted. Moved to your inbox."))
    }

    // MARK: - A11 投稿を書く画面

    func testStatusFromPhoto() async throws {
        XCTAssertEqual(UploadPlaceStatus.of(location: "蔵王キツネ村", photoPlaceName: "蔵王キツネ村", photoHasCoords: true,
                                            attaches: true, clearedByUser: false), .fromPhoto)
        XCTAssertEqual(UploadPlaceStatus.fromPhoto.line, L("写真の位置から入れました", "Filled in from the photo's location"))
        XCTAssertTrue(UploadPlaceStatus.fromPhoto.offersChange)
        XCTAssertFalse(UploadPlaceStatus.fromPhoto.showsChips)
        // 本人が書き換えたら何も言わない（写真の位置から入れた、と嘘をつかない）
        XCTAssertEqual(UploadPlaceStatus.of(location: "蔵王キツネ村の入口", photoPlaceName: "蔵王キツネ村", photoHasCoords: true,
                                            attaches: true, clearedByUser: false), .none)
        XCTAssertEqual(UploadPlaceStatus.of(location: "白石城", photoPlaceName: nil, photoHasCoords: false,
                                            attaches: true, clearedByUser: false), .none)
    }

    func testStatusNeedsPlaceWithoutLocation() async throws {
        let status = UploadPlaceStatus.of(location: "  ", photoPlaceName: nil, photoHasCoords: false,
                                          attaches: true, clearedByUser: false)
        XCTAssertEqual(status, .needsPlace)
        XCTAssertEqual(status.line, L("写真に位置情報が無いので、入れてください", "This photo has no location. Please add the place."))
        XCTAssertTrue(status.showsChips)
        XCTAssertFalse(status.offersChange)
    }

    func testStatusChooseWhenNotFilled() async throws {
        // オフ・本人が空にした（「変える」を含む）: 一言なしで候補だけ
        XCTAssertEqual(UploadPlaceStatus.of(location: "", photoPlaceName: nil, photoHasCoords: true,
                                            attaches: false, clearedByUser: false), .choose)
        XCTAssertEqual(UploadPlaceStatus.of(location: "", photoPlaceName: "蔵王", photoHasCoords: true,
                                            attaches: true, clearedByUser: true), .choose)
        XCTAssertNil(UploadPlaceStatus.choose.line)
        XCTAssertTrue(UploadPlaceStatus.choose.showsChips)
        // オンで写真の位置から引いている途中は出さない（数秒で入る。チップを出してすぐ消さない）
        XCTAssertEqual(UploadPlaceStatus.of(location: "", photoPlaceName: nil, photoHasCoords: true,
                                            attaches: true, clearedByUser: false), .none)
    }

    func testChipsSpotsFirstThenRecentDeduped() async throws {
        let a = try spot("a", name: "蔵王キツネ村", lat: 38.0, lng: 140.6)
        let b = try spot("b", name: "白石城", lat: 38.0, lng: 140.6)
        let chips = UploadPlaceStatus.chips(nearSpots: [a, b], recent: ["白石城", " 鍋ヶ滝 ", "", "阿蘇"])
        XCTAssertEqual(chips.map(\.name), ["蔵王キツネ村", "白石城", "鍋ヶ滝"], "観光スポットが先・同じ名前は1つ・3つまで")
        XCTAssertEqual(chips.first, .spot(a))
        XCTAssertEqual(chips.last, .recent("鍋ヶ滝"))
        XCTAssertEqual(UploadPlaceStatus.chips(nearSpots: [], recent: []), [])
    }

    /// 近くを探す位置: この写真 → ほかの写真。オフなら写真の位置を使わない（プライバシー）
    func testChipCenterRespectsLocationSwitch() async throws {
        let mine = Photo.Coords(lat: 38.1, lng: 140.6)
        let other = Photo.Coords(lat: 35.0, lng: 135.0)
        XCTAssertEqual(UploadPlaceStatus.chipCenter(own: mine, others: [nil, other], attaches: true), mine)
        XCTAssertEqual(UploadPlaceStatus.chipCenter(own: nil, others: [nil, other], attaches: true), other)
        XCTAssertNil(UploadPlaceStatus.chipCenter(own: mine, others: [other], attaches: false), "オフなのに写真の位置で候補を探す")
        XCTAssertNil(UploadPlaceStatus.chipCenter(own: nil, others: [nil], attaches: true))
    }

    /// 最近使った撮影地は、探すの言葉とは別の鍵・アカウントごと・新しい順
    func testRecentPlacesStoreIsSeparate() async throws {
        let defaults = freshDefaults()
        let places = RecentSearchesStore.places(defaults: defaults)
        let searches = RecentSearchesStore(defaults: defaults)
        places.remember("鍋ヶ滝", userId: "u1")
        places.remember("白石城", userId: "u1")
        XCTAssertEqual(places.words(userId: "u1"), ["白石城", "鍋ヶ滝"])
        XCTAssertEqual(searches.words(userId: "u1"), [], "探すの最近の検索に撮影地が混ざる")
        XCTAssertEqual(places.words(userId: "u2"), [], "別の人の撮影地が並ぶ")
        XCTAssertNotNil(defaults.stringArray(forKey: "journey-photo-recent-places:u1"))
        // 退会で消える
        AccountLocalData.remove(userId: "u1", username: nil, defaults: defaults)
        XCTAssertEqual(places.words(userId: "u1"), [], "退会しても撮影地が残る")
    }

    /// 投稿できた写真の撮影地を覚える（先頭の写真がいちばん新しい）。持ち主が分からなければ覚えない
    func testModelRemembersPostedPlaces() async throws {
        // 通信はしない。背景の転送（`BackgroundTransfer.shared`）に触れないよう、使い捨ての通信を渡す（`UploadPhotoBindingTests`）
        let session = URLSession(configuration: .ephemeral)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.recentPlaces = RecentSearchesStore.places(defaults: freshDefaults())
        model.rememberPlaces(["鍋ヶ滝", "白石城", ""], userId: "u1")
        XCTAssertEqual(model.recentPlaces.words(userId: "u1"), ["鍋ヶ滝", "白石城"])
        model.rememberPlaces(["阿蘇"], userId: Optional<String>.none)
        XCTAssertEqual(model.recentPlaces.words(userId: "u1"), ["鍋ヶ滝", "白石城"])
        // 送り終わりで呼んでいる（上がった写真だけ）
        let text = (try? source("Features/Upload/UploadViewModel.swift")) ?? ""
        XCTAssertTrue(text.contains("rememberPlaces(items.filter { done.contains($0.id) }.map(\\.location)"))
    }

    /// 「地図に位置を載せる」は欄の下の1行（3行の札をやめた）。切り替えと識別子は残す
    func testLocationSwitchIsOneLineUnderTheField() async throws {
        let upload = try source("Features/Upload/UploadView.swift")
        let toggle = slice(upload, from: "private var locationToggle: some View {", to: "private func placeStatus(")
        XCTAssertFalse(toggle.contains("JPCard"), "3行の札に戻っている")
        XCTAssertTrue(toggle.contains("Text(UploadDetails.uploadLocationLineTitle)"))
        XCTAssertFalse(toggle.contains("Text(UploadDetails.uploadLocationToggleNote"), "2行の説明を画面に出している")
        XCTAssertTrue(toggle.contains(".accessibilityHint(UploadDetails.uploadLocationToggleNote(attaches: model.attachesLocation))"))
        XCTAssertTrue(toggle.contains("accessibilityIdentifier(\"upload.attachLocation\")"))
        XCTAssertTrue(UploadDetails.uploadLocationLineTitle.contains(L("約1km", "1 km")), "何が送られるかが1行から消えた")
        // 置き場: 1枚目の撮影地の欄の下。写真がまだ無いときは欄の代わりの所
        let detail = slice(upload, from: "private var detailSection: some View {", to: "private var suggestLayoutKey")
        let field = try XCTUnwrap(detail.range(of: "PlaceSearchField(")?.lowerBound)
        let status = try XCTUnwrap(detail.range(of: "placeStatus(item)")?.lowerBound)
        let line = try XCTUnwrap(detail.range(of: "if item.id == model.items.first?.id { locationToggle }")?.lowerBound)
        XCTAssertLessThan(field, status)
        XCTAssertLessThan(status, line)
        XCTAssertTrue(upload.contains("if model.items.isEmpty { locationToggle }"))
        // 既定はオンのまま（プライバシーにかかわるので変えない）
        XCTAssertTrue(UploadLocationPreference.defaultValue)
    }

    /// チップは欄と同じ道で入れる（欄の外で `location` だけ書き換えると座標を捨てる）
    func testChipsGoThroughThePlaceField() async throws {
        let field = try source("Features/Upload/PlaceSearchField.swift")
        XCTAssertTrue(field.contains("case .spot(let spot): pick(spot: spot)"))
        XCTAssertTrue(field.contains("case .recent(let name): pick(name: name)"))
        let pickName = slice(field, from: "private func pick(name: String) {", to: "\n    }\n")
        XCTAssertTrue(pickName.contains("coords = nil"), "最近の撮影地に前の座標を付ける")
        XCTAssertTrue(pickName.contains("pickedLabel = name"))
        let upload = try source("Features/Upload/UploadView.swift")
        let chip = slice(upload, from: "private func placeChip(", to: "\n    }\n")
        XCTAssertTrue(chip.contains("placeChipPicks[itemId] = chip"))
        XCTAssertFalse(chip.contains(".location ="), "チップが欄を通らずに字を書き換える")
        XCTAssertEqual(UploadPlaceChipLayout.height, 36)
        XCTAssertEqual(UploadPlaceChipLayout.fillOpacity, 0.14, accuracy: 0.0001)
        XCTAssertTrue(chip.contains(".frame(minHeight: WebTheme.minTapTarget)"), "チップの当たりが 44 未満")
    }
}
