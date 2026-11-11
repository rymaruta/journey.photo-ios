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

    /// 失敗は見出しを必ず出す。渡さない呼び手は「読み込めませんでした」、説明が見出しと同じなら決まった一文
    func testErrorBannerAlwaysHasATitle() {
        let fallbackTitle = "読み込めませんでした"
        let fallbackMessage = "通信が途切れたようです"
        let plain = ErrorBanner.resolvedText(title: nil, message: "撮影スポットを読み込めませんでした",
                                             fallbackTitle: fallbackTitle, fallbackMessage: fallbackMessage)
        XCTAssertEqual(plain.title, fallbackTitle)
        XCTAssertEqual(plain.message, "撮影スポットを読み込めませんでした")
        // 見出しと同じ字を2度並べない
        let same = ErrorBanner.resolvedText(title: nil, message: fallbackTitle,
                                            fallbackTitle: fallbackTitle, fallbackMessage: fallbackMessage)
        XCTAssertEqual(same.title, fallbackTitle)
        XCTAssertEqual(same.message, fallbackMessage)
        // 渡された見出しはそのまま
        let given = ErrorBanner.resolvedText(title: "会話を読み込めませんでした", message: "電波を確かめてください",
                                             fallbackTitle: fallbackTitle, fallbackMessage: fallbackMessage)
        XCTAssertEqual(given.title, "会話を読み込めませんでした")
        XCTAssertEqual(given.message, "電波を確かめてください")
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
        assertInOrder(["case .card:", ".fill(WebTheme.card)", "WebTheme.hairline",
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
        assertInOrder(["if connectivity.isOffline, model.loaded {", "JPStateBand(kind: .offline",
                       "skin: .glass", "} else if let message = emptyMessage {",
                       "JPStateBand(kind: .partial, title: message", "skin: .glass",
                       "} else if model.areaFrame != nil {", "actionTitle: L(\"写真全体を見る\"",
                       "model.clearArea()"], in: line, "地図の上の帯")
        // 右の操作列に重ねない
        XCTAssertTrue(map.contains(".padding(.trailing, JPSpace.m + WebTheme.minTapTarget + JPSpace.xs)"))
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

    /// 人のページ: 開き始めは頭の骨格、空は見出し＋説明＋ボタン1つ（下線の字の一手をやめた）
    func testUserProfileStates() throws {
        let user = try source("Features/Profile/UserProfileView.swift")
        assertInOrder(["if model.profile == nil && model.isLoading && model.errorMessage == nil {",
                       "JPLoadingState(kind: .profile)", "} else {", "header"], in: user, "頭の骨格")
        assertInOrder(["EmptyState(title: L(\"まだ写真がありません\"", "actionTitle: L(\"ほかの人の写真を探す\"",
                       "TabRouter.shared.openSearch()"], in: user, "空の一手")
        XCTAssertFalse(user.contains("findOthersLink"), "下線の字の一手が残っている")
        XCTAssertTrue(user.contains("JPLoadingState(kind: .photoGrid(count: 9))"))
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
