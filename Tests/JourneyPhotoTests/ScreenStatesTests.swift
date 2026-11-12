import XCTest
@testable import JourneyPhoto

/// デザインの案 第2章「画面の状態とそろえ」（1.1.83・2026-11-12）。
///
/// 読み込み中・失敗・空・電波なしを、どの画面も同じ5つの部品（失敗・空・骨格・中央の電波なし・状態の帯）で出す。
/// 部品は Linux では描けないので、**値は数で**、**画面のつなぎは元のファイルを読んで**見張る
/// （`DesignFoundationTests` と同じやり方）。直しを戻すとどれかが落ちる
final class ScreenStatesTests: XCTestCase {

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

    /// `from` から `to` までを切り出す
    private func slice(_ text: String, from: String, to: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = text.range(of: from) else {
            XCTFail("「\(from)」が無い", file: file, line: line)
            return ""
        }
        let rest = text[start.lowerBound...]
        let end = rest.range(of: to, range: rest.index(after: rest.startIndex)..<rest.endIndex)?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

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

    // MARK: - 01 共通の部品

    /// 失敗は見出しを必ず出す。渡されなければ説明の最初の一文が見出し、残りが説明（一律の「読み込めませんでした」にしない）
    func testErrorBannerTitleComesFromTheMessage() {
        let fallback = "通信が途切れたようです"
        // 二文: 最初の一文が見出し
        let two = ErrorBanner.resolvedText(title: nil, message: "写真を読み込めませんでした。つながる所で、もう一度お試しください。",
                                           fallbackMessage: fallback)
        XCTAssertEqual(two.title, "写真を読み込めませんでした")
        XCTAssertEqual(two.message, "つながる所で、もう一度お試しください。")
        // 一文だけ: その一文が見出し（句点を落とす）、説明は決まった一文。同じ言葉を2度並べない
        let one = ErrorBanner.resolvedText(title: nil, message: "旅行プランを読み込めませんでした。", fallbackMessage: fallback)
        XCTAssertEqual(one.title, "旅行プランを読み込めませんでした")
        XCTAssertEqual(one.message, fallback)
        let plain = ErrorBanner.resolvedText(title: nil, message: "プランが見つかりません", fallbackMessage: fallback)
        XCTAssertEqual(plain.title, "プランが見つかりません", "意味の違う見出し（読み込めませんでした）を被せている")
        // 英語も同じ
        let english = ErrorBanner.resolvedText(title: nil, message: "Couldn't load your trips.", fallbackMessage: fallback)
        XCTAssertEqual(english.title, "Couldn't load your trips")
        let dash = ErrorBanner.resolvedText(title: nil, message: "Couldn't load your likes — showing what's on this device",
                                            fallbackMessage: fallback)
        XCTAssertEqual(dash.title, "Couldn't load your likes")
        XCTAssertEqual(dash.message, "showing what's on this device")
        // 渡された見出しはそのまま。説明が見出しと同じなら決まった一文
        let given = ErrorBanner.resolvedText(title: "会話を読み込めませんでした", message: "電波を確かめてください",
                                             fallbackMessage: fallback)
        XCTAssertEqual(given.title, "会話を読み込めませんでした")
        XCTAssertEqual(given.message, "電波を確かめてください")
        XCTAssertEqual(ErrorBanner.resolvedText(title: "A", message: "A", fallbackMessage: fallback).message, fallback)
    }

    /// 意味の違う所・同じ言葉が重なっていた所は、見出し（何が起きたか）と説明（どうなっているか）を分けて渡す
    func testListedErrorSitesPassTheirOwnTitle() throws {
        let expected: [(String, String)] = [
            ("Features/Trips/TripPlanDetailView.swift", "ErrorBanner(title: L(\"プランが見つかりません\""),
            ("Features/Albums/InviteView.swift", ": L(\"この招待リンクは使えません\""),
            ("Features/Gallery/GalleryView.swift", "ErrorBanner(title: L(\"フォロー中の人を読み込めませんでした\""),
            ("Features/Pass/PassCardPickView.swift", "ErrorBanner(title: L(\"写真を読み込めませんでした\""),
            ("Features/Profile/FavoritesView.swift", "ErrorBanner(title: L(\"いいねした写真を読み込めませんでした\""),
            ("Features/Map/PhotoMapView.swift", "ErrorBanner(title: L(\"撮影スポットを読み込めませんでした\""),
            ("Features/Map/PhotoMapView.swift", "ErrorBanner(title: Self.loadFailedText, message: ErrorBanner.defaultMessage"),
            ("Features/Trips/TripPlansView.swift", "ErrorBanner(title: L(\"旅行プランを読み込めませんでした\""),
            ("Features/Trips/TripAddSheet.swift", "ErrorBanner(title: L(\"旅行プランを読み込めませんでした\""),
            ("Features/Trips/TripCreateView.swift", "ErrorBanner(title: L(\"行きたい場所を読み込めませんでした\""),
            ("Features/Trips/TripPlanPickSheet.swift", "ErrorBanner(title: L(\"行きたい場所を読み込めませんでした\""),
            ("Features/Camper/CamperGarageLoader.swift", "ErrorBanner(title: L(\"写真を読み込めませんでした\""),
        ]
        for (path, call) in expected {
            XCTAssertTrue(try source(path).contains(call), "\(path) の見出しが「\(call)」でない")
        }
        XCTAssertFalse(try source("Features/Trips/TripPlanDetailView.swift")
            .contains("ErrorBanner(message: L(\"プランが見つかりません\""))
    }

    /// マイページは見た目を変えない（owner）。空は印なし、失敗は前の形（三角・見出しは渡したときだけ）
    func testMyPageKeepsItsLook() throws {
        let mine = try source("Features/Profile/MyPageView.swift")
        let empties = mine.components(separatedBy: "EmptyState(").dropFirst()
        XCTAssertEqual(empties.count, 4)
        for call in empties {
            XCTAssertTrue(call.hasPrefix("icon: nil,"), "マイページの空に印が付いている: \(call.prefix(60))")
        }
        let errors = mine.components(separatedBy: "ErrorBanner(").dropFirst()
        XCTAssertEqual(errors.count, 4)
        for call in errors {
            let args = call.components(separatedBy: ") {").first ?? ""
            XCTAssertTrue(args.contains("look: .classic"), "マイページの失敗が前の形でない: \(call.prefix(60))")
            XCTAssertFalse(args.hasPrefix("title:"), "マイページの失敗に見出しを足している")
        }
        XCTAssertTrue(try source("Features/Trips/TripShelf.swift").contains("EmptyState(icon: nil, title: L(\"まだ旅はありません\""))
        // 前の形は三角・見出しは渡したときだけ
        let states = try source("Features/Common/ErrorBanner.swift")
        let classic = slice(states, from: "case .classic:", to: "private var retryButton")
        assertInOrder(["Image(systemName: \"exclamationmark.triangle\")", ".font(.title2)", ".foregroundStyle(WebTheme.faint)",
                       "if let title { StateTitle(text: title) }", "StateMessage(text: message)"], in: classic, "前の形")
    }

    /// 空の印: 失敗・開けない・狭い所は印なし、合う所は合う印
    func testEmptyIconsFitTheirPlace() throws {
        let none: [(String, String)] = [
            ("Features/Profile/SavedSpotsMapView.swift", "EmptyState(icon: nil, message: L(\"この撮影スポットは開けません\""),
            ("Features/Profile/SavedSpotsMapView.swift", "EmptyState(icon: nil, message: L(\"この撮影地は開けません\""),
            ("Features/Profile/SavedSpotsMapView.swift", "EmptyState(icon: nil, message: L(\"行きたい場所はまだありません。"),
            ("Features/Messages/DMConversationView.swift", "EmptyState(icon: nil, title: L(\"ブロック中です\""),
            ("Features/Messages/DMConversationView.swift", "EmptyState(icon: nil, title: L(\"メッセージを送れません\""),
            ("Features/Messages/DMConversationView.swift", "EmptyState(icon: nil, title: L(\"この会話は表示できません\""),
            ("Features/Trunk/TrunkRerollView.swift", "EmptyState(icon: nil, message: L(\"ラベルが見つかりませんでした。"),
            ("Features/Map/NearbyPhotosSheet.swift", "EmptyState(icon: nil, title: L(\"この範囲には、まだ写真がありません\""),
            ("Features/Trips/TripPlanPickSheet.swift", "EmptyState(icon: nil, title: L(\"行きたい場所はまだありません\""),
            ("Features/Profile/BadgeShelfView.swift", "EmptyState(icon: nil, message: L(\"まだメダルはありません。"),
            ("Features/Profile/MyPhotosMap.swift", "EmptyState(icon: nil, message: Self.emptyMessage(isMine: isMine))"),
            ("Features/Notifications/NotificationsView.swift", "EmptyState(icon: \"bell\""),
            ("Features/Profile/FollowListView.swift", "EmptyState(icon: \"person.2\""),
            ("Features/Messages/DMInboxView.swift", "EmptyState(icon: \"bubble.left.and.bubble.right\""),
            ("Features/Messages/DMRequestsView.swift", "EmptyState(icon: \"person.2\""),
            ("Features/Messages/DMNewMessageView.swift", "EmptyState(icon: \"person.2\""),
            ("Features/Albums/AlbumsView.swift", "EmptyState(icon: \"rectangle.stack\""),
            ("Features/Spots/OfficialSpotIndexView.swift", "EmptyState(icon: \"mappin\", message: L(\"見つかりませんでした\""),
        ]
        for (path, call) in none {
            XCTAssertTrue(try source(path).contains(call), "\(path) の空の印が「\(call)」でない")
        }
        let light = try source("Features/Pro/LightForecastView.swift")
        XCTAssertEqual(light.components(separatedBy: "EmptyState(icon: nil, title: LightForecastText.failureTitle(failure)").count - 1, 2,
                       "光の予報の失敗に印が付いている")
        XCTAssertEqual(try source("Features/Map/PhotoMapView.swift").components(separatedBy: "EmptyState(icon: \"mappin\"").count - 1, 3)
    }

    /// 印は線画 44・#6E6E6E。失敗は丸に「!」、空は写真、電波なしは消えた電波
    func testStateIconTokens() throws {
        XCTAssertEqual(JPStateIcon.size, 44)
        XCTAssertEqual(JPStateIcon.gray, 0x6E6E6E)
        XCTAssertEqual(JPStateIcon.failed, "exclamationmark.circle")
        XCTAssertEqual(JPStateIcon.empty, "photo")
        XCTAssertEqual(JPStateIcon.offline, "wifi.slash")
        let states = try source("Features/Common/ErrorBanner.swift")
        // 空の印は既定で出る（呼び手が何もしなくても同じ形）
        XCTAssertTrue(states.contains("init(icon: String? = JPStateIcon.empty, title: String? = nil, message: String"))
    }

    /// 状態の帯: 印 → 見出しと説明 → 白い小ボタン（見た目 36・当たり 44）。札の角 16・ガラスの角 22
    func testStateBandShape() throws {
        XCTAssertEqual(JPStateBand.cardCorner, 16)
        XCTAssertEqual(JPStateBand.glassCorner, 22)
        XCTAssertEqual(JPStateBand.Kind.offline.symbol, JPStateIcon.offline)
        XCTAssertEqual(JPStateBand.Kind.partial.symbol, JPStateIcon.failed)
        XCTAssertEqual(JPStateBand.Kind.empty(symbol: "mappin").symbol, "mappin")
        let states = try source("Features/Common/ErrorBanner.swift")
        let band = slice(states, from: "struct JPStateBand", to: "\nstruct JPLoadingState")
        assertInOrder(["Image(systemName: kind.symbol)", "Text(title)", ".font(JPFont.bodyEmphasis)",
                       "if let message {", ".font(JPFont.caption)",
                       "if let action {", ".frame(minHeight: JPHeight.inlineButton)",
                       ".frame(minHeight: WebTheme.minTapTarget)", ".disabled(isBusy)"], in: band, "状態の帯の並び")
        XCTAssertEqual(JPStateBand.cardCorner, JPRadius.l, "札の角が土台の札（jpCardFace）と違う")
        assertInOrder(["case .card:", "Color.clear.jpCardFace()",
                       "case .glass:", ".jpGlass(in: RoundedRectangle(cornerRadius: Self.glassCorner))"], in: band, "帯の皮")
        // 帯の印も赤にしない
        XCTAssertFalse(band.contains("WebTheme.danger"))
    }

    /// 骨格は中身と同じ形（格子・人の行・場所の行・札・コメント・アルバム・人のページの頭）
    func testSkeletonKindsMatchTheContent() throws {
        let states = try source("Features/Common/ErrorBanner.swift")
        let loading = slice(states, from: "struct JPLoadingState", to: "\n}\n")
        for part in ["case .photoGrid(let count):", "case .personRows(let trailing):", "case .places:",
                     "case .cards(let width, let height):", "case .comments:", "case .albums:", "case .profile:",
                     "GridItem(.flexible(), spacing: 2), count: 3"] {
            XCTAssertTrue(loading.contains(part), "骨格の形「\(part)」が無い")
        }
        XCTAssertFalse(loading.contains("ProgressView("), "骨格に回る輪を使っている")
    }

    // MARK: - 03 ホームの電波なし

    /// 電波が無くても一覧は消さず、上に帯。控えが1枚も無いときだけ中央の状態
    func testHomeKeepsPhotosWhenOffline() throws {
        let home = try source("Features/Gallery/GalleryView.swift")
        let states = slice(home, from: "switch model.state {", to: ".webScreen()")
        assertInOrder(["case .failed(let message):", "if connectivity.isOffline {", "HomeOfflineState(",
                       "} else {", "ErrorBanner(message: message"], in: states, "読めなかった回")
        assertInOrder(["case .loaded(let photos):", "if connectivity.isOffline {", "HomeOfflineBand(", "feed(photos)"],
                      in: states, "前に見た写真の上に帯")
        XCTAssertTrue(home.contains(".onChange(of: connectivity.isOffline)"), "電波が戻っても読み直さない")
        let parts = try source("Features/Gallery/HomeOfflineState.swift")
        XCTAssertTrue(parts.contains("JPStateBand(kind: .offline, title: JPStateBand.offlineTitle"))
        XCTAssertTrue(parts.contains("RetryButton(isBusy: isBusy, action: retry)"))
        XCTAssertTrue(parts.contains("JPStateIcon(symbol: JPStateIcon.offline)"))
    }

    /// 別の画面にいる間に電波が戻ったら、印を立てて戻ったときに読み直す
    func testHomeReloadsAfterReconnectWhenBack() throws {
        XCTAssertEqual(HomeReconnect.onConnectivityChange(offline: false, isOnScreen: true), .reloadNow)
        XCTAssertEqual(HomeReconnect.onConnectivityChange(offline: false, isOnScreen: false), .reloadWhenBack)
        XCTAssertEqual(HomeReconnect.onConnectivityChange(offline: true, isOnScreen: true), .nothing)
        XCTAssertEqual(HomeReconnect.onConnectivityChange(offline: true, isOnScreen: false), .nothing)
        XCTAssertTrue(HomeReconnect.reloadOnLanding(pending: true, offline: false))
        XCTAssertFalse(HomeReconnect.reloadOnLanding(pending: true, offline: true))
        XCTAssertFalse(HomeReconnect.reloadOnLanding(pending: false, offline: false))
        let home = try source("Features/Gallery/GalleryView.swift")
        let change = slice(home, from: ".onChange(of: connectivity.isOffline)", to: ".onChange(of: tabRouter.postSheetsClosed)")
        assertInOrder(["HomeReconnect.onConnectivityChange(offline: offline, isOnScreen: isOnScreen)",
                       "case .reloadNow:", "retryHome()", "case .reloadWhenBack: reloadAfterReconnect = true"],
                      in: change, "電波が戻ったとき")
        let land = slice(home, from: "private func landOnScreen(", to: "private func reloadMyPhotos()")
        assertInOrder(["HomeReconnect.reloadOnLanding(pending: reloadAfterReconnect, offline: connectivity.isOffline)",
                       "reloadAfterReconnect = false", "retryHome()"], in: land, "戻ったときの読み直し")
    }

    /// 電波なしの絵の口は Debug だけ。Release では必ず false、強制した回は見張りを始めない
    func testPreviewOfflineIsDebugOnly() throws {
        let preview = try source("Core/Auth/PreviewSession.swift")
        let forced = slice(preview, from: "static var forcesOffline: Bool {", to: "static var userId")
        assertInOrder(["#if DEBUG", "UserDefaults.standard.bool(forKey: offlineKey)", "#else", "return false", "#endif"],
                      in: forced, "電波なしの絵の口")
        let connectivity = try source("Core/Networking/Connectivity.swift")
        let start = slice(connectivity, from: "func start() {", to: "deinit")
        assertInOrder(["started = true", "if PreviewSession.forcesOffline {", "isOffline = true", "return", "}",
                       "monitor.pathUpdateHandler"], in: start, "強制した回の戻り")
    }

    // MARK: - 04 タグ・色・機材の格子

    /// TagPhotos v2: 3 列・すき間 2・正方形・先頭 300 を端まで
    func testTagPhotosGridIsV2() throws {
        XCTAssertEqual(TagPhotoGridMetrics.leadHeight, 300)
        XCTAssertEqual(TagPhotoGridMetrics.columnCount, 3)
        XCTAssertEqual(TagPhotoGridMetrics.spacing, 2)
        let screen = try source("Features/Gallery/CollectionPhotosScreen.swift")
        XCTAssertTrue(screen.contains("TagPhotoGrid(photos: list)"), "タグの写真が v2 の格子でない")
        XCTAssertFalse(screen.contains("PhotoGrid(photos: list, captionsLead: true)"), "2 列の強弱の組みに戻っている")
        XCTAssertTrue(screen.contains("JPLoadingState(kind: .photoGrid(count: 9))"), "読み込み中が格子の骨格でない")
        let tag = slice(try source("Features/Common/TagPhotoGrid.swift"), from: "struct TagPhotoGrid",
                        to: "\nenum TagPhotoGridMetrics")
        assertInOrder([".frame(height: Self.leadHeight)", ".overlay(alignment: .bottom) { LeadCaption(photo: lead) }",
                       "count: Self.columnCount", "PhotoFrame(photo: photo, aspect: 1, corner: 0)"], in: tag, "先頭 → 格子")
    }

    // MARK: - 02 主要画面

    /// 探す: 撮影スポットの節は札の形の骨格・失敗は帯。電波が無いときは上に帯
    func testSearchStates() throws {
        let section = try source("Features/Search/SearchSpotIndexSection.swift")
        assertInOrder(["case .loading:", "JPLoadingState(kind: .cards(width: Self.cardWidth, height: Self.cardHeight))",
                       "case .failed:", "JPStateBand(kind: .partial, title: Self.failedTitle"], in: section, "節の状態")
        XCTAssertFalse(section.contains("ErrorBanner("), "節の失敗が大きな中央の失敗に戻っている")
        let search = try source("Features/Search/SearchView.swift")
        XCTAssertTrue(search.contains("if connectivity.isOffline {\n                    JPStateBand(kind: .offline"),
                      "探すの電波なしの帯が無い")
    }

    /// 地図: 読み込み中はピンの形の灰、失敗・空・電波なしはガラスの帯
    func testMapStates() throws {
        XCTAssertEqual(MapPinSkeleton.size, 44)
        XCTAssertEqual(MapPinSkeleton.corner, 12)
        XCTAssertEqual(MapPinSkeleton.spots.count, 6)
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertTrue(map.contains("if !model.loaded { MapPinSkeleton() }"), "地図の読み込み中の骨格が無い")
        let line = slice(map, from: "private var statusLine: some View", to: "/// 「無い」と「見つからない」を分ける")
        assertInOrder(["let choice = Self.stateBand(offline: connectivity.isOffline",
                       "areaOnly: model.areaFrame != nil && MapSearch.fold(model.query).isEmpty",
                       "&& model.category == nil",
                       "if choice == .offlineNothing {", "skin: .glass",
                       "} else if choice == .failed {", "skin: .glass",
                       "} else if choice == .areaEmpty {", "actionTitle: L(\"写真全体を見る\"", "model.clearArea()",
                       "} else if choice == .empty", "} else if choice == .location",
                       "} else if choice == .offlinePinsAndLocation, let note = locationNote {",
                       "JPStateBand(kind: .offline", "statusCapsule(note, retry: false)",
                       "} else if choice == .offlinePins {", "前に見たピンだけを出しています"], in: line, "地図の上の帯")
        // 右の操作列に重ねない
        XCTAssertTrue(map.contains(".padding(.trailing, JPSpace.m + WebTheme.minTapTarget + JPSpace.xs)"))
    }

    /// 地図の帯の選び方: 空・見つからない・現在地を電波なしで隠さない。「前に見たピンだけ」はピンがあるときだけ。
    /// 範囲の出口は範囲だけで絞った回に限る
    func testMapStateBandChoice() {
        typealias V = PhotoMapView
        XCTAssertEqual(V.stateBand(offline: true, loaded: true, empty: .failed, areaOnly: false,
                                   hasLocationNote: false, photosFailed: false), .offlineNothing)
        XCTAssertEqual(V.stateBand(offline: false, loaded: true, empty: .failed, areaOnly: false,
                                   hasLocationNote: false, photosFailed: false), .failed)
        XCTAssertEqual(V.stateBand(offline: true, loaded: true, empty: .noResults, areaOnly: false,
                                   hasLocationNote: false, photosFailed: false), .empty, "見つからないを電波なしで隠した")
        XCTAssertEqual(V.stateBand(offline: false, loaded: true, empty: .noResults, areaOnly: true,
                                   hasLocationNote: false, photosFailed: false), .areaEmpty)
        XCTAssertEqual(V.stateBand(offline: false, loaded: true, empty: .noResults, areaOnly: false,
                                   hasLocationNote: false, photosFailed: false), .empty, "語・カテゴリでも絞っているのに範囲の出口")
        XCTAssertEqual(V.stateBand(offline: false, loaded: true, empty: .noPlaces, areaOnly: true,
                                   hasLocationNote: false, photosFailed: false), .empty)
        // run 1132 の記録: 電波なし・ピン 16 本・現在地の許可を待つ間、現在地の札だけで電波なしを知らせていなかった。
        // 両方を出す（どちらも隠さない）
        XCTAssertEqual(V.stateBand(offline: true, loaded: true, empty: nil, areaOnly: false,
                                   hasLocationNote: true, photosFailed: false), .offlinePinsAndLocation,
                       "電波なしか現在地の様子のどちらかを隠した")
        XCTAssertEqual(V.stateBand(offline: false, loaded: true, empty: nil, areaOnly: false,
                                   hasLocationNote: true, photosFailed: true), .location)
        XCTAssertEqual(V.stateBand(offline: true, loaded: true, empty: nil, areaOnly: false,
                                   hasLocationNote: false, photosFailed: true), .offlinePins)
        XCTAssertEqual(V.stateBand(offline: false, loaded: true, empty: nil, areaOnly: false,
                                   hasLocationNote: false, photosFailed: true), .photosFailed)
        XCTAssertEqual(V.stateBand(offline: false, loaded: true, empty: nil, areaOnly: false,
                                   hasLocationNote: false, photosFailed: false), .none)
    }

    /// 探す: 圏外で索引が読めなかった回は節ごと出さない（上の電波なしの帯と2本重ねない）
    func testSearchDoesNotStackTwoBands() throws {
        XCTAssertFalse(SearchSpotIndexSection.shows(load: .failed, offline: true))
        XCTAssertTrue(SearchSpotIndexSection.shows(load: .failed, offline: false))
        XCTAssertTrue(SearchSpotIndexSection.shows(load: .ready, offline: true))
        XCTAssertTrue(SearchSpotIndexSection.shows(load: .loading, offline: true))
        let search = try source("Features/Search/SearchView.swift")
        XCTAssertTrue(search.contains("if SearchSpotIndexSection.shows(load: spotIndexLoad, offline: connectivity.isOffline) {"))
    }

    /// 一覧の読み込み中は中身と同じ形（お知らせ・フォロー一覧・地図のリスト・コメント・アルバム）。回る輪を外す
    func testListsLoadInTheirOwnShape() throws {
        let notes = try source("Features/Notifications/NotificationsView.swift")
        XCTAssertFalse(notes.contains("JPLoadingState(kind: .rows)"))
        XCTAssertTrue(notes.contains("JPLoadingState(kind: .personRows(trailing: .thumb))"))
        let follow = try source("Features/Profile/FollowListView.swift")
        XCTAssertTrue(follow.contains("JPLoadingState(kind: .personRows(trailing: .pill))"))
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertTrue(slice(map, from: "private var listArea: some View", to: "} else if sections.isEmpty {")
            .contains("JPLoadingState(kind: .places)"))
        let albums = try source("Features/Albums/AlbumsView.swift")
        let albumsBody = slice(albums, from: "var body: some View", to: ".navigationTitle(")
        XCTAssertFalse(albumsBody.contains("ProgressView()"), "アルバムの開き始めが回る輪のまま")
        XCTAssertTrue(albums.contains("JPLoadingState(kind: .albums)"))
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        let comments = slice(detail, from: "private var commentSection: some View", to: "VStack(alignment: .leading, spacing: 0) {")
        assertInOrder(["if model.commentsUnavailable {", "JPStateBand(kind: .partial",
                       "JPLoadingState(kind: .comments)"], in: comments, "コメントの失敗と読み込み中")
        XCTAssertFalse(comments.contains("ProgressView()"), "コメントの読み込み中が回る輪のまま")
        XCTAssertFalse(comments.contains(".buttonStyle(.bordered)"), "系統の枠のボタンが残っている")
    }

    /// 人のページ: 開き始めは頭の骨格、空は見出し＋説明＋ボタン1つ。見出しは「公開された写真」、自分のページなら自分向け
    func testUserProfileStates() throws {
        let user = try source("Features/Profile/UserProfileView.swift")
        assertInOrder(["if model.profile == nil && model.isLoading && model.errorMessage == nil {",
                       "JPLoadingState(kind: .profile)", "} else {", "header"], in: user, "頭の骨格")
        assertInOrder(["let empty = UserProfileEmpty(isSelf: userId == auth.userId)",
                       "EmptyState(title: UserProfileEmpty.title, message: empty.message,",
                       "if empty.isSelf { TabRouter.shared.openPost(.photo) } else { TabRouter.shared.openSearch() }"],
                      in: user, "空の一手")
        XCTAssertFalse(user.contains("findOthersLink"), "下線の字の一手が残っている")
        XCTAssertTrue(user.contains("JPLoadingState(kind: .photoGrid(count: 9))"))
    }

    func testUserProfileEmptyTexts() {
        XCTAssertTrue(UserProfileEmpty.title.contains("公開") || UserProfileEmpty.title.lowercased().contains("public"))
        let mine = UserProfileEmpty(isSelf: true)
        let theirs = UserProfileEmpty(isSelf: false)
        XCTAssertNotEqual(mine.message, theirs.message)
        XCTAssertNotEqual(mine.actionTitle, theirs.actionTitle)
        XCTAssertEqual(mine.actionIdentifier, "userProfile.emptyPost")
        XCTAssertEqual(theirs.actionIdentifier, "userProfile.emptyFindOthers")
    }

    /// いいねした写真: 一部だけは帯（写真を押し下げない）、読み込み中は格子 12、空はハートの印＋見出し＋一手
    func testFavoritesStates() throws {
        let fav = try source("Features/Profile/FavoritesView.swift")
        assertInOrder(["if screen.shown.partial {", "JPStateBand(kind: .partial", "Task { await load(force: true) }"],
                      in: fav, "一部だけの帯")
        XCTAssertFalse(fav.contains("いいねを読み込めませんでした。この端末に覚えているぶんだけ出しています"),
                       "一部だけの回が大きな失敗に戻っている")
        XCTAssertTrue(fav.contains("JPLoadingState(kind: .photoGrid(count: 12))"))
        assertInOrder(["EmptyState(icon: \"heart\", title: L(\"まだいいねした写真がありません\"",
                       "actionTitle: MyPageEmpty.browseTitle"], in: fav, "空")
    }
}
