import XCTest
@testable import JourneyPhoto

/// 全画面の点検（2026-10-21・Mac run 609・main 1093ef46）で見つかった使いにくさの直し（その A の束）。
///
/// 画面の部品は Linux で動かせないので、決まりは値で、配線は元のコードを読んで確かめる
/// （`UXDeadEndsTests` と同じやり方）。各試験は直しを戻すと落ちる
@MainActor
final class UXAuditFixesATests: XCTestCase {

    // MARK: - 道具

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let head = text.range(of: start) else { return "" }
        let rest = text[head.lowerBound...]
        guard let tail = rest.range(of: end, range: rest.index(after: rest.startIndex)..<rest.endIndex) else {
            return String(rest)
        }
        return String(rest[..<tail.lowerBound])
    }

    private func photo(_ id: String, user: String = "u1", location: String? = nil,
                       createdAt: String = "2026-10-01T00:00:00Z") throws -> Photo {
        var json = "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"userId\":\"\(user)\",\"createdAt\":\"\(createdAt)\""
        if let location { json += ",\"location\":\"\(location)\"" }
        return try JSONDecoder.api.decode(Photo.self, from: Data((json + "}").utf8))
    }

    // MARK: - 1・11. 上の帯の当たりと、どのタブでも同じ中身

    /// 右の3つは1つの枠に、44×44 の当たりで並ぶ（前は1つずつの枠で、当たりが 25〜27pt だった）
    func testHeaderButtonsHave44ptHitAreasInOneItem() async throws {
        let header = try source("Features/Common/AppHeader.swift")
        let trailing = header.components(separatedBy: "ToolbarItem(placement: .topBarTrailing)").count - 1
        XCTAssertEqual(trailing, 1, "右の3つが別々の枠に戻っている（当たりを広げると帯が太る）")
        XCTAssertEqual(header.components(separatedBy: ".appHeaderHitArea()").count - 1, 3,
                       "探す・お知らせ・メニューのどれかの当たりが 44 になっていない")
        let hit = slice(header, from: "func appHeaderHitArea()", to: "\n}\n")
        XCTAssertTrue(hit.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"))
        XCTAssertTrue(hit.contains(".contentShape(Rectangle())"))
        XCTAssertGreaterThanOrEqual(WebTheme.minTapTarget, 44)
        // 見た目（絵の大きさ・箱の幅）は前のまま
        XCTAssertEqual(header.components(separatedBy: ".webToolbarIcon()").count - 1, 3)
    }

    /// 探すはどのタブにも出す（前はホームだけで、右の枠の幅がタブごとに違い、ロゴの位置がずれた）
    func testHeaderIsTheSameOnEveryTab() async throws {
        let header = try source("Features/Common/AppHeader.swift")
        XCTAssertFalse(header.contains("showsSearch"), "探すをホームだけに出す切り替えが戻った")
        XCTAssertFalse(header.contains("if showsSearch"))
        for file in ["Features/Gallery/GalleryView.swift", "Features/Search/SearchView.swift",
                     "Features/Map/PhotoMapView.swift"] {
            let text = try source(file)
            XCTAssertTrue(text.contains(".toolbar { AppHeaderItems(unread: unread, onOpenNotifications: onOpenNotifications) }"),
                          "\(file): 見出しの中身がほかのタブと違う")
        }
    }

    /// 探すのタブで見出しの「探す」を押したら、探す口に焦点を当てる（何も起きないボタンにしない）
    func testHeaderSearchFocusesTheFieldOnTheSearchTab() async throws {
        let search = try source("Features/Search/SearchView.swift")
        XCTAssertTrue(search.contains("@FocusState private var fieldFocused: Bool"))
        XCTAssertTrue(search.contains(".focused($fieldFocused)"))
        let hook = slice(search, from: ".onChange(of: tabRouter.searchRequests)", to: "}\n")
        XCTAssertTrue(hook.contains("if isOnScreen { fieldFocused = true"),
                      "ほかの札から来た回までキーボードを出す／探すの札で押しても何も起きない")
    }

    // MARK: - 2. 開発の言葉

    func testVisitTileSaysWhoCollectedTheParts() async {
        XCTAssertEqual(CamperText.visitPartsTitle(owner: "mio"), L("mio が集めた部品", "Parts mio collected"))
        XCTAssertEqual(CamperText.visitPartsTitle(owner: "  "), L("友達が集めた部品", "Parts your friend collected"))
        XCTAssertEqual(CamperText.visitPartsTitle(owner: nil), L("友達が集めた部品", "Parts your friend collected"))
        XCTAssertFalse(CamperText.visitPartsTitle(owner: "mio").contains("サーバー"))
    }

    /// 画面の言葉に開発の言葉（要サーバー・Server parts）を出さない
    func testNoDeveloperWordsOnScreen() async throws {
        let files = ["Features/Camper/CamperVisitView.swift", "Features/Profile/FavoritesView.swift",
                     "Core/Storage/WishlistSync.swift", "Core/Store/StoreService.swift"]
        for file in files {
            let text = try source(file)
            for line in text.components(separatedBy: "\n") where line.contains("L(\"") {
                XCTAssertFalse(line.contains("要サーバー"), "\(file): \(line)")
                XCTAssertFalse(line.contains("Server parts"), "\(file): \(line)")
                XCTAssertFalse(line.contains("サーバーで外せず"), "\(file): \(line)")
                XCTAssertFalse(line.contains("サーバーのいいね"), "\(file): \(line)")
                XCTAssertFalse(line.contains("購入をサーバーに"), "\(file): \(line)")
            }
        }
        XCTAssertTrue(try source("Features/Camper/CamperVisitView.swift")
            .contains("tile(CamperText.visitPartsTitle(owner: ownerName)"))
    }

    // MARK: - 3. ストーリーの「ひとことを書く」

    func testStoryCaptionHintIsWhiteOnAFaintBand() async throws {
        XCTAssertGreaterThanOrEqual(StoryComposerView.captionHintOpacity, 0.85, "案内の字が薄く、写真に溶ける")
        XCTAssertGreaterThan(StoryComposerView.captionHintScrim, 0.2, "帯が薄すぎる")
        XCTAssertLessThanOrEqual(StoryComposerView.captionHintScrim, 0.5, "帯が濃すぎて写真を隠す")
        let composer = try source("Features/Stories/StoryComposerView.swift")
        let block = slice(composer, from: "private var captionBlock: some View", to: "if !place.location.isEmpty")
        XCTAssertTrue(block.contains("prompt: Text(L(\"ひとことを書く\""), "案内の字を自分で組んでいない（既定の灰のまま）")
        XCTAssertTrue(block.contains("Color.white.opacity(Self.captionHintOpacity)"), "写真の上の案内が白でない")
        XCTAssertTrue(block.contains("if caption.isEmpty"))
        XCTAssertTrue(block.contains("Color.black.opacity(Self.captionHintScrim)"))
        XCTAssertFalse(block.contains("WebTheme.accent"), "写真の上に真鍮を置いた（写真の上は白だけ）")
    }

    // MARK: - 4. 投稿の「撮影地」の枠

    func testUploadPlaceFieldHasTheSameBoxAsTitle() async throws {
        let parts = try source("Core/Design/FormParts.swift")
        let field = slice(parts, from: "struct JPField<Content: View>: View {", to: "extension View {")
        XCTAssertTrue(field.contains(".jpFieldBox(multiline: multiline)"), "タイトル・説明の枠が共通の部品を通らない")
        let place = try source("Features/Upload/PlaceSearchField.swift")
        let body = slice(place, from: "private var placeField: some View", to: "/// **打つたびに投げない。**")
        XCTAssertTrue(body.contains("if boxed"))
        XCTAssertTrue(body.contains(".jpFieldBox()"), "撮影地の欄に枠が無い")
        let upload = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("pickedSpot: $item.pickedSpot, boxed: true)"), "投稿の撮影地に枠を付けていない")
        XCTAssertTrue(upload.contains("JPFieldTitle(L(\"撮影地\", \"Place\"))"), "見出しがタイトル・説明と違う形")
        // 写真の編集（Form の行）は枠を付けない
        let edit = try source("Features/Profile/EditPhotoView.swift")
        XCTAssertFalse(edit.contains("boxed: true"))
    }

    // MARK: - 5. 探すの0件

    func testZeroHitMovesAboveFilters() async {
        let zero = SearchView.zeroHitOnTop(discovering: false, showsPhotos: true, hasLoaded: true,
                                           photosEmpty: true, spotsEmpty: true, usersEmpty: true, loadFailed: false)
        XCTAssertTrue(zero)
        // 発見の顔・読み込み中・失敗・何か当たっているときは上へ出さない
        XCTAssertFalse(SearchView.zeroHitOnTop(discovering: true, showsPhotos: true, hasLoaded: true,
                                               photosEmpty: true, spotsEmpty: true, usersEmpty: true, loadFailed: false))
        XCTAssertFalse(SearchView.zeroHitOnTop(discovering: false, showsPhotos: true, hasLoaded: false,
                                               photosEmpty: true, spotsEmpty: true, usersEmpty: true, loadFailed: false))
        XCTAssertFalse(SearchView.zeroHitOnTop(discovering: false, showsPhotos: true, hasLoaded: true,
                                               photosEmpty: true, spotsEmpty: true, usersEmpty: true, loadFailed: true))
        XCTAssertFalse(SearchView.zeroHitOnTop(discovering: false, showsPhotos: true, hasLoaded: true,
                                               photosEmpty: true, spotsEmpty: false, usersEmpty: true, loadFailed: false))
        XCTAssertFalse(SearchView.zeroHitOnTop(discovering: false, showsPhotos: true, hasLoaded: true,
                                               photosEmpty: true, spotsEmpty: true, usersEmpty: false, loadFailed: false))
        XCTAssertFalse(SearchView.zeroHitOnTop(discovering: false, showsPhotos: true, hasLoaded: true,
                                               photosEmpty: false, spotsEmpty: true, usersEmpty: true, loadFailed: false))
    }

    /// 0件の間は季節・時間帯のチップを畳む。選んでいれば外せるよう残す
    func testTimeChipsFoldOnlyWhenNothingIsChosen() async {
        XCTAssertFalse(SearchView.showsTimeChips(zeroHit: true, timeFilterEmpty: true))
        XCTAssertTrue(SearchView.showsTimeChips(zeroHit: true, timeFilterEmpty: false), "選んだ季節を外す手立てが消える")
        XCTAssertTrue(SearchView.showsTimeChips(zeroHit: false, timeFilterEmpty: true))
    }

    /// 0件の文と地図への出口は、絞り込みの段より前に置く（キーボードの裏に隠れない）
    func testZeroHitBlockIsPlacedBeforeTheChips() async throws {
        let search = try source("Features/Search/SearchView.swift")
        let body = slice(search, from: "let zeroHit = zeroHitOnTop", to: "results\n")
        let empty = try XCTUnwrap(body.range(of: "emptyPhotoResults"))
        let chips = try XCTUnwrap(body.range(of: "categoryChips"))
        XCTAssertLessThan(empty.lowerBound, chips.lowerBound)
        XCTAssertTrue(body.contains("Self.showsTimeChips(zeroHit: zeroHit"))
        let results = slice(search, from: "private var photoResults: some View", to: "private var photoResultsBody")
        XCTAssertTrue(results.contains("if !zeroHitOnTop"), "0件の文を二度出す")
        XCTAssertTrue(search.contains("accessibilityIdentifier(\"search.emptyMap\")"))
    }

    // MARK: - 6. 同意画面の写真と見出し

    func testLegalGateUsesBundledExamplePhotos() async throws {
        XCTAssertGreaterThanOrEqual(LegalGateLayout.heroAssets.count, 3)
        // 同梱の構図の作例写真（CC0・表記の要らない実写真）から選ぶ
        let sources = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tools/composition-examples/photo-sources.json"), encoding: .utf8)
        let ledger = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(sources.utf8)) as? [String: Any])
        let records = try XCTUnwrap(ledger["photos"] as? [String: [String: Any]])
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Assets.xcassets")
        for asset in LegalGateLayout.heroAssets {
            XCTAssertTrue(asset.hasPrefix("composition-ai-"), "\(asset): 作例写真でない")
            XCTAssertTrue(FileManager.default.fileExists(atPath: catalog.appendingPathComponent("\(asset).imageset/\(asset).jpg").path),
                          "\(asset): アプリに入っていない")
            let kind = String(asset.dropFirst("composition-ai-".count))
            XCTAssertEqual(records[kind]?["license"] as? String, "CC0", "\(asset): 表記の要る許諾の写真を出典なしで敷いた")
        }
        // 日ごとに選ぶ（同じ日は同じ写真）。候補の外を返さない
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(LegalGateLayout.heroAsset(day: day), LegalGateLayout.heroAsset(day: day))
        for offset in 0..<10 {
            let picked = LegalGateLayout.heroAsset(day: day.addingTimeInterval(Double(offset) * 86_400))
            XCTAssertTrue(LegalGateLayout.heroAssets.contains(picked))
        }
        let gate = try source("Features/Legal/LegalGateView.swift")
        XCTAssertFalse(gate.contains("PhotoSnapshotStore"), "公開一覧の控えの先頭を借りている（袋入りのぶどうが出た）")
        XCTAssertTrue(gate.contains("Image(heroAsset)"))
    }

    func testLegalGateHeadingBreaksAfterTheComma() async {
        XCTAssertEqual(Labels.Brand.taglineLines.replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "、 ", with: "、"),
                       Labels.Brand.tagline, "改行を抜くと一言と同じ文にならない")
        XCTAssertEqual(Labels.Brand.taglineLines.components(separatedBy: "\n").count, 2)
        if Labels.Brand.tagline == "写真から、次の旅が始まる。" {
            XCTAssertEqual(Labels.Brand.taglineLines, "写真から、\n次の旅が始まる。")
        }
    }

    // MARK: - 7. 0 の数

    func testZeroCountsBecomeAnInvite() async {
        XCTAssertFalse(SpotScreen.firstPhotoInvite.contains("0"))
        XCTAssertFalse(SpotScreen.subtitle(region: "熊本県", photoCount: 0).contains("0枚"))
        XCTAssertTrue(SpotScreen.subtitle(region: "熊本県", photoCount: 0).contains(SpotScreen.firstPhotoInvite))
        XCTAssertEqual(OfficialSpotView.postLabel(hasLinked: false), L("最初の1枚を投稿", "Post the first photo"))
        XCTAssertEqual(OfficialSpotView.postLabel(hasLinked: true),
                       L("この撮影スポットの写真を投稿", "Post a photo of this spot"))
    }

    func testEmptySpotCardDoesNotSayZero() async throws {
        let spot = try source("Features/Spots/OfficialSpotView.swift")
        let card = slice(spot, from: "if showsEmptyPhotosCard {", to: "postButton")
        XCTAssertFalse(card.contains("\\(linked.count)"), "0枚の札の見出しが「（0）」と言う")
        XCTAssertTrue(spot.contains("Label(Self.postLabel(hasLinked: !linked.isEmpty), systemImage: \"camera\")"))
    }

    func testHomeShelfCreditIsGentleButStillSaysSource() async {
        XCTAssertFalse(HomeSpotShelf.note.contains("利用者ではありません"))
        XCTAssertTrue(HomeSpotShelf.note.contains("出典"))
    }

    // MARK: - 8. 空の画面の次の一手

    func testLightForecastEmptyHasAFindSpotsButton() async throws {
        XCTAssertEqual(LightForecastText.findSpotsAction, L("撮影スポットを探す", "Find photo spots"))
        let view = try source("Features/Pro/LightForecastView.swift")
        let empty = slice(view, from: "private func emptyView(", to: "private func failureView(")
        XCTAssertTrue(empty.contains("actionTitle: LightForecastText.findSpotsAction"))
        XCTAssertTrue(empty.contains("TabRouter.shared.openMap()"))
        // お知らせのシートから来ても地図が見えるように、地図へ移るときはシートを下ろす
        let root = try source("App/RootView.swift")
        let hook = slice(root, from: ".onChange(of: tabRouter.mapRequests) { _, _ in\n            showMenu = false", to: "}")
        XCTAssertTrue(hook.contains("showNotifications = false"))
    }

    /// 元の写真を選ぶ: 保存も行きたいも空なら、みんなの写真へ移る一手を出す
    func testInspiredPickerEmptyShelvesLeadToEveryone() async throws {
        XCTAssertEqual(InspiredBy.Shelf.saved.emptyNextShelf, .everyone)
        XCTAssertEqual(InspiredBy.Shelf.wishlist.emptyNextShelf, .everyone)
        XCTAssertNil(InspiredBy.Shelf.everyone.emptyNextShelf)
        XCTAssertEqual(InspiredBy.Shelf.everyone.chooseLabel, L("みんなの写真から選ぶ", "Choose from Everyone"))
        let picker = try source("Features/Upload/InspiredPickerView.swift")
        XCTAssertTrue(picker.contains("if pools?.feed != nil, let next = shelf.emptyNextShelf"))
        XCTAssertTrue(picker.contains("Text(next.chooseLabel).jpPillButton(.main(onPhoto: false))"),
                      "写真の無い画面の主ボタン（真鍮の塗り）でない")
    }

    /// みんなの写真: 自分の写真を除き、いま書いている撮影地の写真を先に
    func testEveryoneCandidatesSkipMineAndPutTheSamePlaceFirst() async throws {
        let feed = [try photo("a", user: "me", location: "京都", createdAt: "2026-10-05T00:00:00Z"),
                    try photo("b", user: "u2", location: "大阪", createdAt: "2026-10-04T00:00:00Z"),
                    try photo("c", user: "u3", location: "京都", createdAt: "2026-10-03T00:00:00Z")]
        let picked = InspiredBy.everyoneCandidates(feed: feed, viewerId: "me", currentLocation: "京都")
        XCTAssertEqual(picked.map(\.id), ["c", "b"])
        XCTAssertEqual(InspiredBy.everyoneCandidates(feed: nil, viewerId: nil), [])
    }

    /// 人のトランクの0枚のラベル: 「· 0 枚」と言わず、地図でその土地を開く一手を出す
    func testTheirTrunkZeroLabelLeadsToTheMap() async throws {
        XCTAssertFalse(TheirTrunkText.sheetSubtitle(place: "京都", owner: "丸田", count: 0).contains("0"))
        XCTAssertEqual(TheirTrunkText.mapAction(place: "京都"), L("京都を地図で見る", "See 京都 on the map"))
        let view = try source("Features/Trunk/TheirTrunkView.swift")
        let empty = slice(view, from: "} else if matched.isEmpty {", to: "} else {")
        XCTAssertTrue(empty.contains("TabRouter.shared.openMap(query: place)"), "0枚のラベルが行き止まり")
        XCTAssertTrue(empty.contains(".jpPillButton(.main(onPhoto: false)"))
    }

    // MARK: - 9. 自分と人のページの数

    func testProfileCountsMatchMyPage() async throws {
        let counts = ProfileLine.counts(followers: .loaded(2), following: .loaded(1), photos: .loaded(38))
        XCTAssertEqual(counts.map(\.label), ["投稿", "フォロワー", "フォロー中"])
        let mine = try source("Features/Profile/MyPageView.swift")
        let stats = slice(mine, from: "private var stats: some View", to: "private func statCell")
        let order = ["L(\"投稿\"", "L(\"フォロワー\"", "L(\"フォロー中\""].compactMap { stats.range(of: $0)?.lowerBound }
        XCTAssertEqual(order.count, 3)
        XCTAssertEqual(order, order.sorted(), "マイページの並びが変わった")
    }

    // MARK: - 10. 人のトランクの眉ラベル

    func testTheirTrunkEyebrowIsNotMine() async throws {
        let model = TrunkModel.allCases[0]
        XCTAssertTrue(TrunkText.eyebrow(model).hasPrefix("MY TRUNK · "))
        XCTAssertTrue(TrunkText.eyebrow(model, theirs: true).hasPrefix("TRUNK · "))
        XCTAssertFalse(TrunkText.eyebrow(model, theirs: true).contains("MY"))
        let open = try source("Features/Trunk/TrunkOpenView.swift")
        XCTAssertEqual(open.components(separatedBy: "TrunkText.eyebrow(model, theirs: theirs != nil)").count - 1, 2)
        XCTAssertFalse(open.contains("Text(TrunkText.eyebrow(model))"))
    }

    // MARK: - 12. 時計の下・作りかけの欄

    func testProfilePagesPaintBlackUnderTheClock() async throws {
        let solid = TopBarScrim.stops(topInset: 62, solid: true)
        XCTAssertEqual(solid.first?.opacity, 1)
        // 時計の帯の下端まで黒 100%
        let bandEnd = 62 / (62 + TopBarScrim.fade)
        XCTAssertTrue(solid.contains { abs($0.location - bandEnd) < 0.001 && $0.opacity == 1 })
        XCTAssertEqual(solid.last?.opacity, 0)
        // 写真の詳細はこれまでどおりのぼかし
        XCTAssertEqual(TopBarScrim.stops(topInset: 62, solid: false).first?.opacity, 0.7)
        for file in ["Features/Profile/MyPageView.swift", "Features/Profile/UserProfileView.swift"] {
            XCTAssertTrue(try source(file).contains("TopBarScrim(topInset: geo.safeAreaInsets.top, solid: true)"), file)
        }
    }

    func testTripBookHidesZeroOrUnknownDistance() async throws {
        XCTAssertFalse(TripBook.showsDistance(nil), "「—」だけの欄を出す")
        XCTAssertFalse(TripBook.showsDistance(0), "「0 km」の欄を出す")
        XCTAssertFalse(TripBook.showsDistance(0.3), "丸めて 0 km の欄を出す")
        XCTAssertTrue(TripBook.showsDistance(12))
        let view = try source("Features/Trips/TripBookView.swift")
        XCTAssertTrue(view.contains("if TripBook.showsDistance(distance) {"))
    }

    func testPassTicketHidesBlankFields() async throws {
        let front = PassTicket.frontFields(date: "10.21 4時", distance: nil, count: "はじめて")
        XCTAssertEqual(front.count, 3, "番号で欄を引く券面のため、欄そのものは抜かない")
        XCTAssertEqual(PassTicket.shown(front).map(\.label), [PassTicket.dateTitle, PassTicket.countTitle])
        let back = PassTicket.backFields(issuer: "mio", section: "", count: "")
        XCTAssertFalse(PassTicket.shown(back).contains { $0.value == PassTicket.blank })
        let cards = try source("Features/Pass/PassCards.swift")
        XCTAssertTrue(cards.contains("ForEach(Array(PassTicket.shown(face.fields).enumerated())"), "表の格子が「—」を出す")
        XCTAssertTrue(cards.contains("let fields = PassTicket.shown(face.fields)"), "裏の格子が「—」を出す")
        XCTAssertTrue(cards.contains("if !PassTicket.shown(face.fields).isEmpty {\n                    fieldGrid"),
                      "値のある欄が無いのに、細い線だけの空の段を置く")
    }
}
