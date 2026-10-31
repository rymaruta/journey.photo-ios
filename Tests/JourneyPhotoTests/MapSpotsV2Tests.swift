import XCTest
@testable import JourneyPhoto

/// v2 の第4段: 地図・撮影スポットの画面（Artifact「デザインシステム v2」の Map・MapPlace・MapList・
/// OfficialSpotMap・SpotDetail・SpotPinOptions・2026-10-14）。
///
/// 画面の部品は Linux では描けないので、**値は数で**、**部品の作りは元のファイルを読んで**見張る
/// （`DesignFoundationTests` と同じやり方）。ソースは関数・型の範囲に絞り、呼び出しの**順**まで見る。
/// owner の決まり（板より優先・CLAUDE.md）——真鍮は黒地の上だけ・地図の札（ガラス）の中は白・
/// ピンは 40 のまま——もここで見張る
final class MapSpotsV2Tests: XCTestCase {

    // MARK: - 読む口

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

    /// `start` から、同じ深さの次の宣言（`\n    private func ` など）までを切り出す
    private func segment(_ text: String, from start: String,
                         file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let range = text.range(of: start) else {
            XCTFail("「\(start)」が無い", file: file, line: line)
            return ""
        }
        let rest = text[range.upperBound...]
        let ends = ["\n    private func ", "\n    private var ", "\n    @ViewBuilder", "\n    nonisolated static ",
                    "\n    static func ", "\n    var body", "\n    /// ", "\n}\n"]
            .compactMap { rest.range(of: $0)?.lowerBound }
        return String(rest[..<(ends.min() ?? rest.endIndex)])
    }

    /// `parts` がこの順に `text` に現れる（並びの入れ替え・呼び出しの削除で落ちる）
    private func assertInOrder(_ parts: [String], in text: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: cursor..<text.endIndex) else {
                XCTFail("\(what): 「\(part)」が無いか、順が違う", file: file, line: line)
                return
            }
            cursor = found.upperBound
        }
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private let map = "Features/Map/PhotoMapView.swift"
    private let official = "Features/Spots/OfficialSpotView.swift"

    // MARK: - 地図の上の欄・チップ・切り替え（板 MapList）

    /// 検索欄は 44 の丸・surface-2 に白 8% の縁（v1 は 52・白 7%）
    func testSearchFieldIsV2() throws {
        XCTAssertEqual(PhotoMapView.searchFieldHeight, 44)
        let field = segment(try source(map), from: "private var searchField: some View {")
        assertInOrder([".frame(height: Self.searchFieldHeight)",
                       ".background(WebTheme.sheet, in: Capsule())",
                       ".overlay(Capsule().strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))"],
                      in: field, "検索欄")
        XCTAssertFalse(field.contains(".frame(height: 52)"), "v1 の 52 が残っている")
    }

    /// チップは見た目 34・押せる 44（上下 5）・13pt。選んだ札は白 94% に墨＋チェック（色だけで伝えない）
    func testCategoryChipsAreV2() throws {
        XCTAssertEqual(PhotoMapView.chipHeight, 34)
        XCTAssertEqual(PhotoMapView.chipHeight + PhotoMapView.chipTapSlack * 2, WebTheme.minTapTarget)
        let chip = segment(try source(map), from: "private func chip(")
        assertInOrder(["if selected {", "Image(systemName: \"checkmark\")",
                       ".font(.footnote.weight(selected ? .semibold : .regular))",
                       ".frame(minHeight: Self.chipHeight)",
                       "AnyShapeStyle(WebTheme.accentBackground)",
                       ".overlay(Capsule().strokeBorder(selected ? Color.clear : WebTheme.hairline",
                       ".padding(.vertical, Self.chipTapSlack)",
                       ".frame(minHeight: WebTheme.minTapTarget)"], in: chip, "カテゴリのチップ")
    }

    /// 「地図 / スポット / リスト」は角 14 の帯（白 7%）、選んだ札は白 16% の面に白の字（v1 は白 92% に墨）。
    /// 札 38 ＋ 内側 3 × 2 ＝ 押せる 44
    func testModePickerIsV2() throws {
        // 2026-10-31 判断（#426）: 帯の切り替えから、マイページ・ホームと同じ下線の札（`ProfileTabBar`）へ。
        // 中身は横にめくらない（地図を横に動かす操作とぶつかる）
        let picker = segment(try source(map), from: "private var modePicker: some View {")
        XCTAssertTrue(picker.contains("ProfileTabBar(tabs: PhotoMapViewModel.Mode.allCases, selection: $model.mode)"),
                      "地図の切り替えが共通の札でない")
        XCTAssertFalse(picker.contains("ProfileTabPager("), "地図の札を横にめくっている（地図の操作とぶつかる）")
        XCTAssertFalse(picker.contains("ProfileTabSwipe("))
        XCTAssertEqual(PhotoMapViewModel.Mode.spots.tabIdentifier, "map.mode.spots", "UI テストの道しるべが変わった")
        XCTAssertFalse(picker.contains("Color.white.opacity(0.92)"), "v1 の白の塗りが残っている")
        XCTAssertFalse(picker.contains("WebTheme.accentText"), "選んだ札が墨の字のまま")
    }

    // MARK: - ピン（板 Map・SpotPinOptions）

    /// みんなの写真のピンは 44 の白い札に 2 の余白で写真（角 12 / 10）・影なし。束も同じ枠を使う。
    /// 件数バッジは板の位置（真鍮の丸の角が top -6・right -8）に黒の縁 2 を足した所
    func testPhotoPinsHaveWhiteFrame() throws {
        XCTAssertEqual(PhotoMapView.photoPinSize, 44)
        XCTAssertEqual(PhotoMapView.photoPinRadius, 12)
        XCTAssertEqual(PhotoMapView.photoPinInset, 2)
        XCTAssertEqual(PhotoMapView.badgeOffset.x, 10)
        XCTAssertEqual(PhotoMapView.badgeOffset.y, -8)
        let text = try source(map)
        let frame = segment(text, from: "private static func photoPinFrame<")
        assertInOrder([".frame(width: photoPinSize - photoPinInset * 2, height: photoPinSize - photoPinInset * 2)",
                       ".clipShape(RoundedRectangle(cornerRadius: photoPinRadius - photoPinInset))",
                       ".padding(photoPinInset)",
                       ".background(Color.white, in: RoundedRectangle(cornerRadius: photoPinRadius))"], in: frame, "写真のピンの枠")
        // 2026-10-28: 影は外した（重さの直し・`PerfBatch2Tests.testMapPinsHaveNoShadow`）
        // 1つの撮影地のピンと束の両方が同じ枠を通る
        XCTAssertEqual(count("Self.photoPinFrame(RemoteImage(", in: text), 2)
        XCTAssertEqual(count(".offset(x: Self.badgeOffset.x, y: Self.badgeOffset.y)", in: text), 2)
        XCTAssertFalse(text.contains(".clipShape(RoundedRectangle(cornerRadius: 8))"), "v1 の角 8 のピンが残っている")
    }

    /// 撮影スポットのピンは **40 のまま**（owner の決まり・板 v2 の 44 案は取らない）。
    /// 選んだときは 1.27 倍＋真鍮 16% の光の輪（外へ 10）・ばね 0.3 秒・触覚1回
    func testSpotMarkerKeepsFortyAndGrowsWhenSelected() throws {
        XCTAssertEqual(SpotMapMarker.photoSize, 40)
        XCTAssertEqual(SpotMapMarker.plainSize, 32)
        XCTAssertEqual(SpotMapMarker.selectedScale, 1.27)
        XCTAssertEqual(SpotMapMarker.haloWidth, 10)
        XCTAssertEqual(SpotMapMarker.haloOpacity, 0.16)
        let marker = try source("Features/Map/SpotMapMarker.swift")
        assertInOrder(["if isSelected {", ".fill(WebTheme.accent.opacity(Self.haloOpacity))",
                       ".padding(-Self.haloWidth)", ".scaleEffect(isSelected ? Self.selectedScale : 1)"],
                      in: marker, "選んだときのピン")
        assertInOrder([".frame(width: Self.photoSize, height: Self.photoSize)",
                       ".overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: JPStroke.ringGap))"],
                      in: marker, "写真の丸（真鍮の縁 3）")
        let text = try source(map)
        assertInOrder(["if selectedOfficial?.id != pin.id { spotSelectTicks += 1 }",
                       "withAnimation(reduceMotion ? nil : Self.pinSelectAnimation)",
                       "officialMarker(pin, selected: selectedOfficial?.id == pin.id)"],
                      in: text, "撮影スポットのピンを選ぶ")
        XCTAssertTrue(text.contains(".sensoryFeedback(.selection, trigger: spotSelectTicks)"), "触覚の合図が無い")
        // スポットの地図の画面は開いているスポットなので選んだ形
        XCTAssertTrue(try source("Features/Spots/OfficialSpotMapView.swift").contains(".selected(true)"))
        XCTAssertTrue(text.contains("SpotMapMarker(photoURL: pin.photo?.smallURL, fallbackURL: pin.photo?.smallFallbackURL)\n            .selected(selected)"))
    }

    // MARK: - 地図の操作・帯（板 Map の右の列）

    /// 現在地は1つのガラスの丸、拡大・縮小は1本のガラスの帯（間に線）。印は 17pt regular。
    /// 帯の中の線は地図へ素通しさせない（−を狙った2回が地図の拡大にならない）
    func testMapControlsAreGlassGroups() throws {
        XCTAssertEqual(PhotoMapView.controlDividerInset, 10)
        let text = try source(map)
        let controls = segment(text, from: "private var mapControls: some View {")
        assertInOrder(["MapCompass(scope: mapScope)", "locateButton", ".jpGlass(in: Capsule())",
                       "zoomButton(systemImage: \"plus\"", "Rectangle()", ".fill(WebTheme.border)",
                       "zoomButton(systemImage: \"minus\"", ".jpGlass(in: Capsule())",
                       ".contentShape(Rectangle())", ".onTapGesture {}"], in: controls, "地図の操作の列")
        let zoom = segment(text, from: "private func zoomButton(")
        XCTAssertTrue(zoom.contains(".font(.system(size: WebTheme.toolbarIconSize, weight: .regular))"))
        XCTAssertTrue(zoom.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"))
        XCTAssertTrue(segment(text, from: "private var locateButton: some View {")
            .contains(".font(.system(size: WebTheme.toolbarIconSize, weight: .regular))"))
        // 地図の上の札・丸は全部ガラス（v1 の黒 70% は残さない）
        XCTAssertFalse(text.contains("Color.black.opacity(0.7)"), "v1 の黒 70% の札が残っている")
    }

    // MARK: - 地図の上の札（ピン・撮影スポット・地点）

    /// 3枚の札は同じ形（ガラス・角 24・内側 16）、閉じるは 36 の丸（当たり 44）、
    /// 主（経路・白）と線（撮影スポットを見る・場所の詳細）は共通のカプセルで 44 にそろえる
    func testMapCardsShareTheV2Parts() throws {
        XCTAssertEqual(PhotoMapView.cardButtonHeight, 44)
        XCTAssertEqual(PhotoMapView.cardCloseSize, 36)
        let text = try source(map)
        XCTAssertEqual(count(".modifier(MapCardStyle())", in: text), 3, "札の地が1つの形を通っていない")
        XCTAssertEqual(count("cardCloseButton {", in: text), 3)
        XCTAssertEqual(count(".jpPillButton(.primary, height: Self.cardButtonHeight)", in: text), 2)
        XCTAssertEqual(count(".jpPillButton(.outline, height: Self.cardButtonHeight)", in: text), 2)
        XCTAssertFalse(text.contains("cornerRadius: 18"), "v1 の角 18 の札が残っている")
        let card = segment(text, from: "struct MapCardStyle: ViewModifier {")
        assertInOrder([".padding(JPSpace.m)", ".jpGlass(in: RoundedRectangle(cornerRadius: JPRadius.xl)"],
                      in: card, "札の地")
        let close = segment(text, from: "private func cardCloseButton(")
        assertInOrder([".frame(width: Self.cardCloseSize, height: Self.cardCloseSize)",
                       ".background(Color.white.opacity(0.08), in: Circle())", ".webTappable()",
                       ".accessibilityLabel(Labels.Common.close)"], in: close, "札の閉じる")
        // 「撮影スポットを見る」は1行に収めて 0.8 まで縮める（`PlaceTermWordingTests` と同じ決まり）
        assertInOrder(["L(\"撮影スポットを見る\"", ".lineLimit(1)", ".minimumScaleFactor(0.8)",
                       ".jpPillButton(.outline"], in: text, "撮影スポットを見る")
    }

    /// **札はガラス（地図が透ける）なので真鍮を置かない**（CLAUDE.md の owner の決まり）。
    /// 撮影スポットの札の眉は白、地点の札の電話・Webサイトのリンクは白
    func testNoBrassInsideMapCards() throws {
        let text = try source(map)
        for name in ["private func pinCard(", "private func officialCard(", "private func placeCard(",
                     "private func placeInfo(", "private func placePhotos("] {
            XCTAssertFalse(segment(text, from: name).contains("WebTheme.accent)"), "\(name) の中に真鍮がある")
        }
        let officialCard = segment(text, from: "private func officialCard(")
        assertInOrder(["Text(SpotScreen.eyebrow(review: pin.isDraft))", ".jpEyebrow()",
                       ".foregroundStyle(WebTheme.muted)", "Text(pin.name)", ".font(JPFont.cardTitle)"],
                      in: officialCard, "撮影スポットの札の眉と題")
        let info = segment(text, from: "private func placeInfo(")
        assertInOrder(["Link(destination: tel)", "Link(destination: site)", ".foregroundStyle(WebTheme.foreground)"],
                      in: info, "電話・Webサイトのリンクは白")
    }

    /// 地点の札の写真は正方形・すき間 2・外枠だけ角 12（板 MapPlace の格子）。全部の写真へ横に送れる
    func testPlacePhotosStripIsSquare() throws {
        XCTAssertEqual(PhotoMapView.photoStripSpacing, 2)
        XCTAssertEqual(PhotoMapView.placePhotoSize, 76)
        let strip = segment(try source(map), from: "private func placePhotos(")
        assertInOrder(["LazyHStack(spacing: Self.photoStripSpacing)", "ForEach(photos)",
                       ".frame(width: Self.placePhotoSize, height: Self.placePhotoSize)",
                       ".frame(height: Self.placePhotoSize)",
                       ".clipShape(RoundedRectangle(cornerRadius: JPRadius.field))"], in: strip, "地点の札の写真")
        XCTAssertTrue(strip.contains("RetryButton(isBusy: model.isLoading, compact: true)"))
    }

    // MARK: - 「スポット」「リスト」（板 MapList）

    /// 行は札に入れず黒地に直に・明朝 18 の名前・12 の等幅の text-3・高さ 64・下に白 8% の線
    func testSpotRowsAreFlatV2Rows() throws {
        let text = try source(map)
        let row = segment(text, from: "private func spotRow(")
        assertInOrder(["SpotThumbImage(image: photo)", "Text(row.spot.name)", ".font(JPFont.rowTitle)",
                       ".font(JPFont.meta)", ".foregroundStyle(WebTheme.text3)",
                       ".frame(minHeight: JPHeight.tallRow)", ".overlay(alignment: .bottom)",
                       "Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)"], in: row, "スポットの行")
        XCTAssertFalse(text.contains("Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16)"),
                       "v1 の白 7% の札が残っている")
        XCTAssertEqual(count("spotRow(row)", in: text), 2, "「スポット」「リスト」の両方が同じ行を使う")
    }

    /// 「スポット」の札の見出しは真鍮の眉と消える線。読み込み・失敗・空は v2 の共通の部品
    func testSpotsAreaUsesSharedStates() throws {
        let area = segment(try source(map), from: "private var spotsArea: some View {")
        assertInOrder(["JPEyebrowLine(spotsHeading(", "if model.officialIndexState == .loading {",
                       "JPLoadingState(kind: .rows)", "ErrorBanner(message: L(\"撮影スポットを読み込めませんでした\"",
                       "EmptyState(message: MapSearch.fold(model.query).isEmpty"], in: area, "「スポット」の札の状態")
        XCTAssertFalse(area.contains("ProgressView()"), "手書きの輪が残っている")
        let list = segment(try source(map), from: "private var listArea: some View {")
        XCTAssertTrue(list.contains("JPLoadingState(kind: .grid)"))
        XCTAssertFalse(list.contains("ProgressView()"))
    }

    /// 県の見出しは明朝 20・高さ 56・下に線。いまいる県は真鍮の字と真鍮 50% の縁の札（黒地の上）。
    /// 県の写真は 4:3
    func testRegionHeaderIsV2() throws {
        XCTAssertEqual(PhotoMapView.regionHeaderHeight, 56)
        XCTAssertEqual(PhotoMapView.regionPhotoSize.width / PhotoMapView.regionPhotoSize.height, 4.0 / 3.0, accuracy: 0.01)
        let text = try source(map)
        XCTAssertTrue(text.contains("static let regionTitleFont = JPFont.display(JPTypeScale.stateTitle, relativeTo: .title3)"))
        let section = segment(text, from: "private func regionSection(")
        assertInOrder([".font(Self.regionTitleFont)", "regionCurrentTag(", "RegionList.countLabel(section)",
                       ".frame(minHeight: Self.regionHeaderHeight)", ".overlay(alignment: .bottom)",
                       ".accessibilityIdentifier(\"map.region\")"], in: section, "県の見出し")
        let tag = segment(text, from: "private func regionCurrentTag(")
        assertInOrder([".foregroundStyle(WebTheme.accent)",
                       ".strokeBorder(WebTheme.accent.opacity(0.5), lineWidth: JPStroke.hairline)"], in: tag, "いまいる県の札")
        let photos = segment(text, from: "private func regionPhotos(")
        assertInOrder(["LazyHStack(spacing: Self.photoStripSpacing)",
                       ".frame(width: Self.regionPhotoSize.width, height: Self.regionPhotoSize.height)",
                       ".clipShape(RoundedRectangle(cornerRadius: JPRadius.field))"], in: photos, "県の写真")
    }

    // MARK: - 撮影スポットの地図（板 OfficialSpotMap）

    /// 下の帯は黒地（上の角 24）に真鍮の眉 → 明朝の名前 → text-2 の地域 → 真鍮の塗りの「経路 ↗」→ 断り書き。
    /// 座標の行は出さない（約1km に丸めた値を小数4桁で出さない）
    func testOfficialSpotMapBottomBar() throws {
        let view = try source("Features/Spots/OfficialSpotMapView.swift")
        let bar = segment(view, from: "private func bottomBar(")
        assertInOrder(["Text(SpotScreen.eyebrow(review: spot.isDraft))", ".jpEyebrow()",
                       "spot.isDraft ? WebTheme.muted : WebTheme.accent",
                       ".font(JPFont.cardTitle)", ".foregroundStyle(WebTheme.text2)",
                       "Text(\"↗\")", ".jpPillButton(.main(onPhoto: false))",
                       ".accessibilityIdentifier(\"spot.official.mapScreen.directions\")",
                       "L(\"経路だけ Apple のマップで開きます。", ".foregroundStyle(WebTheme.text3)",
                       ".background(Color.black, in: UnevenRoundedRectangle(topLeadingRadius: JPRadius.xl"],
                      in: bar, "スポットの地図の下の帯")
        XCTAssertFalse(view.contains(".jpBottomBar()"), "v1 のぼかしの帯が残っている")
        XCTAssertFalse(view.contains("° N"), "丸めた座標を出している")
    }

    // MARK: - 撮影スポットの頁（板 SpotDetail）

    /// 写真は 460pt の主役。下端を黒へ溶かし、題（眉は白 88%・明朝 32・白 82%）を写真の上に白で載せる。
    /// 写真が無ければ地図の下の黒地に題（眉は真鍮）
    func testSpotPageHeroCarriesTheTitle() throws {
        XCTAssertEqual(OfficialSpotView.heroHeight, 460)
        XCTAssertEqual(OfficialSpotView.heroFadeHeight, 220)
        let text = try source(official)
        let hero = segment(text, from: "private func heroPhoto(")
        assertInOrder([".frame(height: Self.heroHeight)", ".overlay(RemoteImage(url: photo.url))",
                       "LinearGradient(colors: [Color.black.opacity(0), Color.black]",
                       ".frame(height: Self.heroFadeHeight)", "header(onPhoto: true)",
                       "CreditLinksMenu(", ".accessibilityIdentifier(\"spot.official.photoCredit\")"],
                      in: hero, "頭の写真")
        let header = segment(text, from: "private func header(onPhoto: Bool)")
        assertInOrder(["onPhoto ? Color.white.opacity(0.88) : (spot.isDraft ? WebTheme.muted : WebTheme.accent)",
                       ".font(JPFont.photoTitle)", "onPhoto ? WebTheme.muted : WebTheme.text2",
                       ".shadow(color: Color.black.opacity(onPhoto ? 0.6 : 0)"], in: header, "頁の頭")
        assertInOrder(["heroPhoto(photo)", "} else {", "heroMap", "header(onPhoto: false)"],
                      in: text, "写真が無いときの頭")
    }

    /// 地図のピンは真鍮（owner の好み）。頁の頭の地図・撮影地の頁の地図も地図のタブと同じ印
    func testSpotPageMapPinsAreBrass() throws {
        for path in [official, "Features/Spots/SpotDetailView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("SpotMapMarker(photoURL: nil)"), "\(path) の地図のピンが真鍮の印でない")
            XCTAssertFalse(text.contains("mappin.circle.fill"), "\(path) に白のピンが残っている")
        }
    }

    /// 行動の札は同じ幅の大きな札（高さ 64・角 14・印 18 と 13 の太字を縦に）。押した状態は白 94% に墨
    func testActionTilesAreV2() throws {
        XCTAssertEqual(SpotDetailParts.actionHeight, 64)
        XCTAssertEqual(SpotDetailParts.actionIconSize, 18)
        let parts = try source("Features/Spots/SpotDetailParts.swift")
        let label = segment(parts, from: "static func actionLabel(")
        assertInOrder(["VStack(spacing: JPSpace.xxs)", ".font(.system(size: actionIconSize))",
                       ".font(.footnote.weight(.semibold))", ".frame(minHeight: actionHeight)",
                       "AnyShapeStyle(WebTheme.accentBackground)", "RoundedRectangle(cornerRadius: JPRadius.m)"],
                      in: label, "行動の札")
        XCTAssertFalse(label.contains(".frame(height: 48)"), "v1 の 48 が残っている")
    }

    /// 節の見出しは真鍮の眉と消える線（`JPEyebrowLine`）→ 明朝 22。頁の4つの節が眉を持つ
    func testSectionHeadersCarryEyebrows() throws {
        let parts = try source("Features/Spots/SpotDetailParts.swift")
        let header = segment(parts, from: "static func sectionHeader(")
        // 形は共通の節の見出し（2026-10-14: 撮影スポットだけ眉と題の間が 12 だった）
        XCTAssertTrue(header.contains("JPSectionHeading(eyebrow: eyebrow, spoken: spoken, title: title, titleLineLimit: nil)"),
                      "撮影スポットの節の見出しが共通の JPSectionHeading を通っていない")
        let text = try source(official)
        for eyebrow in ["\"ABOUT\"", "\"GUIDE\"", "\"LIGHT\"", "\"EXAMPLES\""] {
            XCTAssertTrue(text.contains("eyebrow: \(eyebrow)"), "\(eyebrow) の眉が無い")
        }
    }

    /// 見どころは真鍮の等幅番号「01」と線の行。今の季節は札に「NOW」
    func testHighlightsAndSeasonAreV2() throws {
        XCTAssertEqual(OfficialSpotView.highlightNumber(0), "01")
        XCTAssertEqual(OfficialSpotView.highlightNumber(9), "10")
        XCTAssertTrue(OfficialSpotView.isCurrentSeason("autumn", current: "autumn"))
        XCTAssertFalse(OfficialSpotView.isCurrentSeason("winter", current: "autumn"))
        let text = try source(official)
        XCTAssertTrue(text.contains("highlightList(body.highlights)"))
        XCTAssertFalse(text.contains("bullet(line)"), "見どころが「—」の行頭のまま")
        let list = segment(text, from: "private func highlightList(")
        assertInOrder(["Text(Self.highlightNumber(index))", ".font(JPFont.mono(JPTypeScale.footnote",
                       ".foregroundStyle(WebTheme.accent)", "JPCardDivider()"], in: list, "見どころ")
        let seasons = segment(text, from: "private func seasonGroup(")
        assertInOrder(["Self.isCurrentSeason(season.season, current: current)", "JPCard {", "Text(\"NOW\")",
                       ".background(WebTheme.accent, in: RoundedRectangle(cornerRadius: 4))"], in: seasons, "季節")
        // 光の時刻は v2 の札（JPCard）
        XCTAssertTrue(segment(text, from: "private var lightSection: some View {").contains("JPCard {"))
    }

    /// 写真0枚は破線の札（明朝 18 の見出し・13 の text-2・投稿のボタン）。投稿のボタンは1つの口
    func testEmptyPhotosCardIsDashed() throws {
        XCTAssertEqual(OfficialSpotView.emptyDashOpacity, 0.2)
        let text = try source(official)
        let photos = segment(text, from: "private var spotPhotos: some View {")
        assertInOrder(["if showsEmptyPhotosCard {", ".font(JPFont.rowTitle)", ".foregroundStyle(WebTheme.text2)",
                       "postButton", "StrokeStyle(lineWidth: JPStroke.hairline, dash: [4, 4])",
                       "} else {", "PhotoGrid(photos: linked)", "postButton"], in: photos, "この撮影スポットの写真")
        XCTAssertEqual(count(".accessibilityIdentifier(\"spot.official.post\")", in: text), 1)
        // 主ボタンの色は共通の決まりのまま（写真があれば白・無ければ真鍮）
        XCTAssertTrue(segment(text, from: "private var postButton: some View {")
            .contains(".jpPillButton(Self.postButtonStyle(hasCover: shown.photo != nil,"))
    }

    /// 近くの撮影スポットは線で区切った行（明朝の名前・等幅の距離・高さ 56）。公式サイトは真鍮のまま
    func testNearbyRowsAndOfficialSite() throws {
        XCTAssertEqual(OfficialSpotView.nearbyRowHeight, 56)
        let text = try source(official)
        let row = segment(text, from: "private func nearbyRow(")
        assertInOrder([".font(JPFont.rowTitle)", "NearbyPhotos.label(km: km)",
                       ".font(JPFont.mono(JPTypeScale.footnote, relativeTo: .footnote))",
                       ".frame(minHeight: Self.nearbyRowHeight)"], in: row, "近くの行")
        XCTAssertFalse(row.contains("mappin.circle"))
        // 外へ出る「公式サイト」は真鍮（owner の決まり 2026-10-02）
        assertInOrder(["L(\"公式サイト\"", ".frame(minHeight: WebTheme.minTapTarget)",
                       ".foregroundStyle(WebTheme.accent)"], in: text, "公式サイト")
    }

    // MARK: - 識別子（UI テスト・画面写真が使う）

    /// 作り替えで UI テストの目印を落とさない
    func testUITestIdentifiersSurvive() throws {
        let expected: [(String, [String])] = [
            (map, ["map.search", "map.photoPin", "map.photoCluster", "map.showAll", "map.pinCard",
                   "map.officialCard", "map.officialCard.open", "map.placeCard", "map.spotRow", "map.region",
                   "map.regionSpotRow", "map.list.categoryNote"]),
            (official, ["spot.official", "spot.official.photoCredit", "spot.official.draftNotice",
                        "spot.official.wish", "spot.official.map", "spot.official.directions",
                        "spot.official.journeyCue", "spot.official.samples", "spot.official.composeGuide",
                        "spot.official.sampleCard", "spot.official.sampleCredit", "spot.official.light",
                        "spot.official.light.date", "spot.official.light.prev", "spot.official.light.next",
                        "spot.official.light.today", "spot.official.check", "spot.official.post",
                        "spot.official.share"]),
            ("Features/Spots/OfficialSpotMapView.swift", ["spot.official.mapScreen", "spot.official.mapScreen.directions"]),
            // 見せ方の札の目印は区分の型が持つ（#426・`PagedTab.tabIdentifier`）
            ("Features/Map/PhotoMapViewModel.swift", ["map.mode."]),
        ]
        for (path, ids) in expected {
            let text = try source(path)
            for id in ids {
                XCTAssertTrue(text.contains("\"\(id)"), "\(path) から「\(id)」が消えた")
            }
        }
    }
}
