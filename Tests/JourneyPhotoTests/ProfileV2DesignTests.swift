import XCTest
@testable import JourneyPhoto

/// デザイン v2 の第5段（マイページ・人のページ・プロフィールの編集・フォローの一覧・お気に入り・
/// 行きたい場所・アルバム・招待・バッジの棚・名前の横）の見た目の決まりを見張る（2026-10-14）。
///
/// 画面は Linux の模型では描けないので、**値**と**書いてあること**を見る。直しを戻すと落ちる。
/// owner の好み（CLAUDE.md）が板より優先する所は、その旨をメッセージに書いてある。
final class ProfileV2DesignTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    private func slice(_ text: String, from start: String, to end: String) throws -> String {
        let lower = try XCTUnwrap(text.range(of: start), "「\(start)」が見つからない")
        let upper = try XCTUnwrap(text.range(of: end, range: lower.upperBound..<text.endIndex), "「\(end)」が見つからない")
        return String(text[lower.lowerBound..<upper.lowerBound])
    }

    // MARK: - 物差し

    /// 写真の格子（板 v2 MyPage・UserProfile の `.g3`: 3 列・すき間 2・縦長 4:5）と画面の端 16
    func testProfileGridAndGutter() {
        XCTAssertEqual(ProfileV2.gridColumns, 3)
        XCTAssertEqual(ProfileV2.gridSpacing, 2, "v1 の 4 に戻っている")
        XCTAssertEqual(ProfileV2.gridAspect, 0.8, accuracy: 0.0001, "板 v2 は縦長 4:5")
        XCTAssertEqual(ProfileV2.gutter, JPSpace.gutter)
        XCTAssertEqual(ProfileV2.gutter, 16, "v1 の 20 に戻っている")
        XCTAssertEqual(ProfileV2.tabGap, 22)
    }

    /// カバーとアイコン（板 v2: 帯 196・アイコン 88 を 44 重ねる・黒 4 の縁。カバーの無い人は 72）
    func testCoverMetrics() {
        XCTAssertEqual(ProfileCover.height, 196)
        XCTAssertEqual(ProfileCover.avatarSize, 88)
        XCTAssertEqual(ProfileCover.avatarOverlap, 44)
        XCTAssertEqual(ProfileCover.compactAvatarSize, 72)
        XCTAssertEqual(ProfileCover.cutoutWidth, 4)
    }

    /// 押せるもの 44（見た目が小さくても当たりは 44）
    func testTapTargetsReach44() {
        XCTAssertEqual(ProfileV2.headerButtonHeight + 2 * ProfileV2.tapSlack(visible: ProfileV2.headerButtonHeight),
                       WebTheme.minTapTarget)
        XCTAssertEqual(ProfileV2.followButtonHeight + 2 * ProfileV2.tapSlack(visible: ProfileV2.followButtonHeight),
                       WebTheme.minTapTarget)
        XCTAssertEqual(JPHeight.inlineButton + 2 * ProfileV2.tapSlack(visible: JPHeight.inlineButton),
                       WebTheme.minTapTarget)
        XCTAssertEqual(ProfileV2.tapSlack(visible: 60), 0, "大きいものは広げない")
        XCTAssertGreaterThanOrEqual(HighlightsRow.ringSide, WebTheme.minTapTarget)
        XCTAssertEqual(HighlightsRow.ringSide, 64)
        XCTAssertEqual(FollowListView.followButtonMinWidth, 96)
    }

    // MARK: - 選んでいるタブは真鍮（owner の好み）

    func testProfileTabsSelectBrass() throws {
        let bar = try source("Features/Profile/ProfileTabBar.swift")
        XCTAssertTrue(bar.contains("selected ? WebTheme.accent : WebTheme.text3"), "選んでいる札の字が真鍮でない")
        XCTAssertTrue(bar.contains(".fill(selected ? WebTheme.accent : Color.clear)"), "下線が真鍮でない")
        XCTAssertTrue(bar.contains(".frame(height: JPStroke.emphasis)"), "下線は 2pt")
        XCTAssertFalse(bar.contains("selected ? Color.white : WebTheme.faint"), "v1 の白い選択に戻っている")
        XCTAssertTrue(bar.contains("Rectangle().fill(WebTheme.hairline)"), "区切り線は v2 の白 8%")
        XCTAssertTrue(bar.contains("accessibilityAddTraits(selected ? .isSelected : [])"), "色だけで選択を言っている")
        XCTAssertTrue(bar.contains("\"profile.tab.\\(option.rawValue)\""), "画面写真の目印を落とした")

        let follow = try source("Features/Profile/FollowListView.swift")
        let tabs = try slice(follow, from: "private var tabs: some View", to: "@ViewBuilder\n    private func row")
        XCTAssertTrue(tabs.contains("ProfileTabBar.color(selected: selected)"), "フォロー一覧の切り替えが真鍮でない")
        XCTAssertTrue(tabs.contains(".fill(selected ? WebTheme.accent : Color.clear)"))
        XCTAssertFalse(tabs.contains("WebTheme.foreground : WebTheme.muted2"), "v1 の白い選択に戻っている")
    }

    /// 「行きたい場所」のタブ名はマイページのタブ名（owner の決め）。4 つ目は「お気に入り」のまま
    /// （板 v2 の「保存」にすると、プロフィールの編集の「保存」と同じ字になる）
    func testMyPageTabNames() {
        XCTAssertEqual(ProfileTab.tabs(isMe: true).map(\.label), ["投稿", "旅の記録", "行きたい場所", "お気に入り"])
        XCTAssertEqual(ProfileTab.tabs(isMe: false).map(\.label), ["投稿", "マップ"])
    }

    // MARK: - マイページ・人のページ

    func testGridsUseTheV2Grid() throws {
        for path in ["Features/Profile/MyPageView.swift", "Features/Profile/UserProfileView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("private let columns = ProfileV2.gridItems"), path)
            XCTAssertTrue(text.contains("aspect: ProfileV2.gridAspect"), "\(path) の格子が縦長 4:5 でない")
            XCTAssertTrue(text.contains("spacing: ProfileV2.gridSpacing"), path)
            XCTAssertFalse(text.contains("GridItem(.flexible(), spacing: 4)"), "\(path) が v1 の 4pt に戻っている")
        }
    }

    /// 数の札は同じ部品（数字は owner の好みの `statNumber`・名前は 12 の text-3）
    func testStatsShareOnePart() throws {
        let parts = try source("Features/Profile/ProfileV2Parts.swift")
        let stat = try slice(parts, from: "struct ProfileStat", to: "struct ProfileOutlinePill")
        XCTAssertTrue(stat.contains(".font(JPFont.statNumber)"), "数字は owner の好み（2026-10-02）の SF semibold")
        XCTAssertTrue(stat.contains(".foregroundStyle(WebTheme.foreground)"), "数は白（合図ではない）")
        XCTAssertFalse(stat.contains("WebTheme.accent"), "数を真鍮にしない")
        XCTAssertTrue(stat.contains(".font(JPFont.caption)") && stat.contains("WebTheme.text3"))

        let mine = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(mine.contains("ProfileStat(value: value, label: label)"))
        let user = try source("Features/Profile/UserProfileView.swift")
        let countText = try slice(user, from: "private func countText", to: "private static let countTapSlack")
        XCTAssertTrue(countText.contains("ProfileStat(value: item.value, label: item.label)"), "人のページの数が v1 の1行に戻っている")
    }

    /// 人のページのフォロー: 白の塗り（写真のある画面の主ボタン）／フォロー中は線＋▾（形で分ける）
    func testUserProfileFollowButtonShapes() throws {
        let parts = try source("Features/Profile/ProfileV2Parts.swift")
        let label = try slice(parts, from: "struct ProfileFollowButtonLabel", to: "\n}\n")
        XCTAssertTrue(label.contains("isFollowing ? Color.clear : WebTheme.accentBackground"))
        XCTAssertTrue(label.contains("isFollowing ? WebTheme.line : Color.clear"), "フォロー中の線が無い")
        XCTAssertTrue(label.contains("chevron.down"), "フォロー中の ▾ が無い（色だけで状態を言う）")
        let user = try source("Features/Profile/UserProfileView.swift")
        XCTAssertTrue(user.contains("ProfileFollowButtonLabel(isFollowing: model.isFollowing)"))
        XCTAssertFalse(user.contains("FollowPill("), "v1 の札に戻っている")
        XCTAssertTrue(user.contains(".unfollowConfirmation(isPresented: $showUnfollowConfirm)"), "外す確認を落とした")
    }

    /// 「プロフィールを編集」の縁は v2 の白 14%（v1 の 28% に戻さない）。目印は1つ
    func testEditButtonIsV2Outline() throws {
        let parts = try source("Features/Profile/ProfileV2Parts.swift")
        let pill = try slice(parts, from: "struct ProfileOutlinePill", to: "struct ProfileFollowButtonLabel")
        XCTAssertTrue(pill.contains("strokeBorder(WebTheme.line"))
        let mine = try source("Features/Profile/MyPageView.swift")
        XCTAssertFalse(mine.contains("Color.white.opacity(0.28)"))
        XCTAssertEqual(mine.components(separatedBy: ".accessibilityIdentifier(\"mypage.edit\")").count - 1, 1,
                       "編集の目印は1か所（カバーの有無で置き場だけ替わる）")
        XCTAssertTrue(mine.contains("editLink(short: true)"), "カバーの無い人の「編集」（板 MyPageNoCover）")
    }

    /// 旅の記録の眉ラベルは土台の部品（同じ形を画面に書かない）
    func testTravelRecordUsesFoundationEyebrow() throws {
        let view = try source("Features/Profile/TravelRecordView.swift")
        XCTAssertTrue(view.contains("JPEyebrowLine(L(\"旅の記録\""), "土台の JPEyebrowLine を使っていない")
        XCTAssertFalse(view.contains(".tracking(2)"), "眉ラベルを画面に書き直している")
        XCTAssertFalse(view.contains("LinearGradient(colors: [WebTheme.accent.opacity(0.6)"), "消える線を画面に書き直している")
        XCTAssertTrue(view.contains(".font(JPFont.figureLarge)"), "距離は字の段の Figure L")
    }

    /// 行きたい場所: 外すのは真鍮の旗（いいねの白いハートと分ける）・名前は明朝の下限 18
    func testWishlistRowsUseBrassFlag() throws {
        let mine = try source("Features/Profile/MyPageView.swift")
        let official = try slice(mine, from: "private func officialWishlistRow", to: "private func wishlistRow")
        let derived = try slice(mine, from: "private func wishlistRow", to: "private var wishlistDivider")
        for row in [official, derived] {
            XCTAssertTrue(row.contains("Image(systemName: \"flag.fill\")"))
            XCTAssertTrue(row.contains(".foregroundStyle(WebTheme.accent)"))
            XCTAssertFalse(row.contains("heart.fill"), "v1 のハートに戻っている")
            XCTAssertTrue(row.contains(".font(JPFont.rowTitle)"), "名前は明朝（下限 18）")
            XCTAssertTrue(row.contains("を「行きたい」から外す"), "外すボタンの読み上げを落とした")
        }
        XCTAssertTrue(mine.contains("JPEyebrowLine(L(\"すべての行きたい場所"), "節の見出しが眉でない")
        XCTAssertTrue(mine.contains("EmptyState(title: L(\"行きたい場所はまだありません\""))
    }

    // MARK: - プロフィールの編集

    func testProfileEditIsTwoColumnTable() throws {
        XCTAssertEqual(ProfileEditView.labelColumn, 104)
        XCTAssertEqual(ProfileEditView.coverHeight, 150)
        XCTAssertEqual(ProfileEditView.avatarSide, 84)
        let edit = try source("Features/Profile/ProfileEditView.swift")
        let labeled = try slice(edit, from: "private func labeled<Field: View>", to: "private func linkRow")
        XCTAssertTrue(labeled.contains(".frame(width: Self.labelColumn, alignment: .leading)"))
        XCTAssertTrue(labeled.contains(".frame(minHeight: JPHeight.row)"))
        XCTAssertFalse(labeled.contains("strokeBorder(WebTheme.outline"), "板 v2 は欄の縁を消した")
        XCTAssertTrue(labeled.contains(".accessibilityLabel(title)"), "欄の読み上げの名前を落とした")
        XCTAssertTrue(labeled.contains("WebTheme.danger"), "上限を超えた知らせを落とした")
        let link = try slice(edit, from: "private func linkRow", to: "/// 名前の横のバッジ")
        XCTAssertTrue(link.contains(".foregroundStyle(WebTheme.accent)"), "BGM の行の印は真鍮（黒地の上）")
    }

    // MARK: - フォロー一覧

    func testFollowListRowsAndButton() throws {
        let follow = try source("Features/Profile/FollowListView.swift")
        let button = try slice(follow, from: "private func followButton", to: "nonisolated static let followButtonMinWidth")
        XCTAssertTrue(button.contains("minHeight: JPHeight.inlineButton"))
        XCTAssertTrue(button.contains("isFollowing ? WebTheme.line : Color.clear"), "フォロー中の線は v2 の白 14%")
        XCTAssertFalse(button.contains("0.28"))
        XCTAssertTrue(follow.contains(".frame(minHeight: JPHeight.tallRow)"), "人の行は 64")
        XCTAssertTrue(follow.contains("ErrorBanner(message: errorMessage"), "失敗が共通の並びでない")
        XCTAssertFalse(follow.contains(".foregroundStyle(.secondary)"), "系統の灰を使っている")
    }

    // MARK: - 主ボタンの色（owner の好み: 写真の無い画面は真鍮・写真のある画面は白）

    func testPrimaryButtonColors() throws {
        let albums = try source("Features/Albums/AlbumsView.swift")
        XCTAssertTrue(albums.contains(".jpPillButton(.main(onPhoto: false))"), "アルバムの一覧は写真の無い画面＝真鍮")
        XCTAssertTrue(albums.contains("private func openInvite()"))
        XCTAssertEqual(albums.components(separatedBy: "InviteLink.token(from: inviteText)").count - 1, 1,
                       "招待を開く処理が2か所にある")
        XCTAssertTrue(albums.contains(".accessibilityLabel(L(\"アルバムの操作\""))

        let invite = try source("Features/Albums/InviteView.swift")
        XCTAssertTrue(invite.contains(".jpPillButton(.main(onPhoto: true))"), "招待は写真のある画面＝白")
        XCTAssertTrue(invite.contains("PhotoDetailView(photo: photo, fromPublicFeed: false, context: photos)"),
                      "写真を開く口を落とした")
        XCTAssertTrue(invite.contains("ForEach(Array(photos.enumerated()), id: \\.element.id)"),
                      "格子を畳むと5枚目からが開けない（全部の写真を並べる）")
        XCTAssertFalse(invite.contains("photos.prefix("), "格子を畳むと5枚目からが開けない")

        let nameSide = try source("Features/Profile/NameSideBadgeView.swift")
        XCTAssertTrue(nameSide.contains(".jpPillButton(.main(onPhoto: false))"), "決めるは真鍮の塗り＋墨")
        XCTAssertTrue(nameSide.contains("JPEyebrowLine(L(\"持っているバッジ\""))
        XCTAssertTrue(nameSide.contains(".background(WebTheme.background, in: RoundedRectangle(cornerRadius: JPRadius.l))"),
                      "見え方の下見は黒地の札（マイページと同じ地）")
    }

    // MARK: - お気に入り（いいねした写真）

    func testFavoritesHeaderAndHero() throws {
        XCTAssertEqual(FavoritesView.heroHeight, 280)
        let fav = try source("Features/Profile/FavoritesView.swift")
        XCTAssertTrue(fav.contains(".jpEyebrow()") && fav.contains(".foregroundStyle(WebTheme.accent)"), "眉が無い")
        XCTAssertTrue(fav.contains(".font(JPFont.screenTitle)"), "題が明朝でない")
        let hero = try slice(fav, from: "private func hero", to: "private func refilter")
        XCTAssertTrue(hero.contains(".foregroundStyle(Color.white)"), "写真の上は白だけ")
        XCTAssertFalse(hero.contains("WebTheme.accent"), "写真の上に真鍮を置いている")
    }

    // MARK: - バッジの棚

    func testShelfProgressAndMedals() throws {
        XCTAssertEqual(BadgeShelfRules.medalSide, 84)
        XCTAssertEqual(BadgeShelfRules.progress(earned: 7, total: 12), 7.0 / 12.0, accuracy: 0.0001)
        XCTAssertEqual(BadgeShelfRules.progress(earned: 0, total: 0), 0)
        XCTAssertEqual(BadgeShelfRules.progress(earned: 13, total: 12), 1, "持っている数が多くても線ははみ出さない")
        let shelf = try source("Features/Profile/BadgeShelfView.swift")
        XCTAssertTrue(shelf.contains("NameSideChoice.patch(profile: profile, selected: nil, style: profile.chosenProMark)"),
                      "「外す」は名前の横の画面の「なし」と同じ部分更新")
        XCTAssertTrue(shelf.contains("\"shelf.medal.\\(item.key)\""), "メダルの目印を落とした")
        XCTAssertFalse(shelf.contains("ProMarkColors.color(0x0B0B0B)"), "v1 の札の地に戻っている")
    }
}
