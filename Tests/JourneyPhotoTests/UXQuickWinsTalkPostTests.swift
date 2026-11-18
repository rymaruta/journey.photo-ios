import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 使い勝手の見直し 2026-11-16 の「すぐ作る」案のうち A3・A8・A11（owner「使い勝手にフォーカスして最高の UI にしたい」）。
///
/// - A3 マイページの表紙の右上に吹き出しとベル（1.1.101）→ 2026-11-18 owner 判断で外した（右上は歯車だけ）
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

    // MARK: - A3 マイページの吹き出しとベル（2026-11-18 owner 判断で外した）

    /// 2026-11-18 owner「マイページにそれは入れなくていいと思う」: 表紙の右上は歯車だけ（板 MyPage どおり）。
    /// 吹き出しとベルの丸の並びに戻さない
    func testMyPageTopRightIsGearOnly() async throws {
        let page = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(page.contains("settingsButton\n                            .padding(.top, hasCover ? topInset : 0)"),
                      "表紙の右上に歯車だけを置いていない")
        XCTAssertFalse(page.contains("AppHeaderGlassInbox"), "マイページに吹き出しとベルが戻っている")
        XCTAssertFalse(page.contains("topButtons"), "マイページの右上が丸の並びに戻っている")
        XCTAssertFalse(page.contains("onOpenNotifications"), "マイページがベルの処理を受け取っている")
        let header = try source("Features/Common/AppHeader.swift")
        XCTAssertFalse(header.contains("struct AppHeaderGlassInbox"), "マイページ用のガラスの丸が残っている")
    }

    /// マイページは親から値を受け取らない（未読・ベルの処理を渡さない）。比べる値が無いので `.equatable()` も付けない
    func testRootPassesNothingToMyPage() async throws {
        let root = try source("App/RootView.swift")
        let call = slice(root, from: "NavigationStack {\n                MyPageView", to: ".perfMark(\"tab.mypage.appear\")")
        XCTAssertEqual(call.trimmingCharacters(in: .whitespacesAndNewlines), "()",
                       "RootView がマイページに値を渡している・.equatable() で包んでいる")
        let file = try source("Features/Profile/MyPageView.swift")
        guard let head = file.range(of: "struct MyPageView: View {") else { return XCTFail("MyPageView が無い") }
        let page = file[head.upperBound...].components(separatedBy: "\n}\n").first ?? ""
        let passed = page.components(separatedBy: "\n").filter { line in
            (line.hasPrefix("    var ") || line.hasPrefix("    let ")) && !line.contains("{") || line.hasPrefix("    var ") && line.contains("= {")
        }
        XCTAssertEqual(passed, [], "MyPageView が親から値を受け取っている")
        // 見出し（ほかのタブ）の吹き出しとベルは今までどおり同じ口（`AppHeaderInbox`）
        let header = try source("Features/Common/AppHeader.swift")
        XCTAssertTrue(header.contains(".accessibilityLabel(AppHeaderInbox.messagesLabel(unread: messagesUnread))"))
        XCTAssertTrue(header.contains(".accessibilityLabel(AppHeaderInbox.bellLabel(unread: unread > 0))"))
        XCTAssertEqual(AppHeaderInbox.messagesLabel(unread: true), L("メッセージ（未読あり）", "Messages, unread"))
        XCTAssertEqual(AppHeaderInbox.bellLabel(unread: false), L("お知らせ", "Activity"))
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

    /// 見本の通信（UI テストの DM）で取り消した通は、会話を読み直しても戻ってこない（2026-11-16・86m5b が4回中2回落ちた件。
    /// run 1430 の記録で、取り消した `preview-dm-0-2` が読み直しで戻っていた: `readded=1 count=10`）
    func testPreviewDMUnsentMessageDoesNotComeBack() async throws {
        let store = PreviewBackend.Store()
        let id = DMRules.conversationId("me", PreviewBackend.dmPeers[0].id)
        func call(_ method: String, _ route: [String], _ body: [String: Any]? = nil) async -> PreviewBackend.Reply {
            await PreviewBackend.reply(method: method, route: route,
                                       body: body.flatMap { try? JSONSerialization.data(withJSONObject: $0) },
                                       userId: "me", store: store, dm: true, publicFeed: { [] }, publicLikes: { _ in nil })
        }
        let before = try JSONDecoder.api.decode(DMConversation.self, from: await call("GET", ["dm", id]).body)
        XCTAssertTrue(before.items.contains { $0.id == "preview-dm-0-2" })
        XCTAssertFalse(before.full)
        let unsend = await call("POST", ["dm", id, "messages"], ["unsend": "preview-dm-0-2"])
        XCTAssertEqual(unsend.status, 200)
        let after = try JSONDecoder.api.decode(DMConversation.self, from: await call("GET", ["dm", id]).body)
        XCTAssertFalse(after.items.contains { $0.id == "preview-dm-0-2" }, "取り消した通が読み直しで戻ってくる")
        XCTAssertTrue(after.full, "全部を返したのに full が無い（画面が差分として足してしまう）")
        XCTAssertEqual(after.items.count, before.items.count - 1)
        // 画面の読み直しの扱い（`refreshSince`）: full なら置き換える
        var log = DMThreadLog()
        log.replace(with: before.items)
        _ = log.unsend("preview-dm-0-2")
        log.replace(with: after.items)
        XCTAssertFalse(log.messages.contains { $0.id == "preview-dm-0-2" })
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
