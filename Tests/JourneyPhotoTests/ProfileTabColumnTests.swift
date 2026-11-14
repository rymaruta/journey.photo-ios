import XCTest
@testable import JourneyPhoto

/// プロフィールの札の行「絵と字」（2026-11-13 owner 承認 #187・Artifact「マイページのタブの案」の案 B）。
/// 4つ（人のページは2つ）の幅が等しい・高さ 56・選んだ色・払いの進み具合に線が付いてくる・大きい字で字が切れない・
/// マイページと人のページだけが使う、を見張る。画面は Linux の模型では描けないので、**値と計算**と**書いてあること**を見る
final class ProfileTabColumnTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/" + path),
                          encoding: .utf8)
    }

    // MARK: - 寸法

    /// 高さ 56（当たりも 56）・印 20・名前と印の間 3・線は列から左右 8 を引いた長さ・2pt・角丸 1
    func testMetricsMatchPlanB() throws {
        XCTAssertEqual(ProfileTabColumnStyle.height, 56, "札の行の高さは 56（今の字の札は 48）")
        XCTAssertGreaterThanOrEqual(ProfileTabColumnStyle.height, WebTheme.minTapTarget)
        XCTAssertEqual(ProfileTabColumnStyle.iconSize, 20)
        XCTAssertEqual(ProfileTabColumnStyle.iconLabelSpacing, 3)
        XCTAssertEqual(ProfileTabColumnStyle.underlineInset, 8)
        XCTAssertEqual(JPStroke.emphasis, 2)
        XCTAssertEqual(ProfileTabStyle.underlineRadius, 1)
        // 字の札（ホームなど）は 48 のまま
        XCTAssertEqual(ProfileTabStyle.height, 48)
        let row = try source("Profile/ProfileTabColumns.swift")
        XCTAssertTrue(row.contains("minHeight: ProfileTabColumnStyle.height"), "列の高さが 56 になっていない")
        XCTAssertTrue(row.contains("max(height, ProfileTabColumnStyle.height)"), "並びの高さが 56 を下回れる")
        XCTAssertTrue(row.contains(".font(.system(size: ProfileTabColumnStyle.iconSize))"))
        XCTAssertTrue(row.contains("JPFont.caption.weight(selected ? .semibold : .medium)"), "名前が 12（caption）の 600 / 500 でない")
    }

    /// 🔴 4つの幅が等しい（390 で 97.5・320 で 80）。人のページの2つも半分ずつ
    func testColumnsAreEqualWidths() {
        let four = ProfileTabColumnStyle.columnWidths(count: 4, available: 390, narrowest: 60)
        XCTAssertEqual(four.count, 4)
        XCTAssertEqual(Set(four), [97.5], "4つの幅が等しくない")
        XCTAssertEqual(four.reduce(0, +), 390, accuracy: 0.001, "幅いっぱいに割っていない")
        XCTAssertEqual(ProfileTabColumnStyle.columnWidths(count: 4, available: 320, narrowest: 60), [80, 80, 80, 80])
        XCTAssertEqual(ProfileTabColumnStyle.columnWidths(count: 2, available: 390, narrowest: 60), [195, 195])
        XCTAssertEqual(ProfileTabColumnStyle.columnWidths(count: 0, available: 390, narrowest: 60), [])
    }

    /// 🔴 大きい字でも字を切らない: 等しく割る並びの理想の幅は「いちばん狭くなれる札（2行に折った名前）× 数」。
    /// `ViewThatFits` はこれが入るときだけ等しく割る並びを選び、入らなければ横に送る並びにする（縮めない・「…」にしない）
    func testLargeTextNeverTruncates() throws {
        // 標準の字: 2行に折った「行きたい／場所」が約 50 → 4 × 54 = 216 は 320 に入る
        let ideal = ProfileTabColumnStyle.columnWidths(count: 4, available: nil, narrowest: 54)
        XCTAssertEqual(ideal, [54, 54, 54, 54])
        XCTAssertLessThanOrEqual(ideal.reduce(0, +), 320)
        // とても大きい字: 2行でも 1 列 90 要る → 4 × 90 = 360 は 320 に入らない（横に送る並びへ）
        XCTAssertGreaterThan(ProfileTabColumnStyle.columnWidths(count: 4, available: nil, narrowest: 90).reduce(0, +), 320)

        let row = try source("Profile/ProfileTabColumns.swift")
        XCTAssertFalse(row.contains(".lineLimit("), "名前の行数を絞っている（大きい字で「…」になる）")
        XCTAssertFalse(row.contains("minimumScaleFactor"), "名前を縮めている（案 B は 12 から伸びる・縮めない）")
        XCTAssertTrue(row.contains(".fixedSize()"), "名前が理想の幅より狭く押し込まれて切れる")
        XCTAssertTrue(row.contains("ScrollView(.horizontal, showsIndicators: false)"), "入らないときの横に送る並びが無い")
        XCTAssertTrue(row.contains("$0.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width"),
                      "いちばん狭くなれる札（2行に折った形）で理想の幅を出していない")
        // 2行の名前は言葉の切れ目で折る
        XCTAssertEqual(ProfileTab.wishlist.tabTitleWrapped?.components(separatedBy: "\n").count, 2)
        XCTAssertEqual(ProfileTab.trips.tabTitleWrapped?.components(separatedBy: "\n").count, 2)
        XCTAssertEqual(ProfileTab.wishlist.tabTitleWrapped?.replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: " ", with: ""),
                       ProfileTab.wishlist.tabTitle.replacingOccurrences(of: " ", with: ""),
                       "2行の名前が1行の名前と違う")
        XCTAssertNil(ProfileTab.posts.tabTitleWrapped)
    }

    // MARK: - 色と印

    /// 🔴 選んだ札は真鍮（印と字）、ほかは text-3。押している間は白 95%（今の札と同じ部品）。選んだ印は塗り
    func testSelectedColorIsBrass() throws {
        XCTAssertEqual(BrandPalette.accent, 0xC9A66B)
        XCTAssertEqual(BrandPalette.text3, 0x9A9A9A)
        let bar = try source("Profile/ProfileTabBar.swift")
        XCTAssertTrue(bar.contains("selected ? WebTheme.accent : WebTheme.text3"), "選んだ札が真鍮でない")
        let row = try source("Profile/ProfileTabColumns.swift")
        XCTAssertTrue(row.contains(".buttonStyle(ProfileTabPressStyle(selected: selected))"), "印と字の色を今の札の部品で付けていない")
        XCTAssertTrue(row.contains(".fill(WebTheme.accent)"), "線が真鍮でない")
        XCTAssertEqual(ProfileTabColumnStyle.symbol("flag", selected: true), "flag.fill")
        XCTAssertEqual(ProfileTabColumnStyle.symbol("flag", selected: false), "flag")
    }

    /// 印: 格子・本・旗・しおり（人のページは格子・地図）。行きたい場所はハートでなく旗（ハートはいいね）
    func testIconsMatchPlanB() {
        XCTAssertEqual(ProfileTab.tabs(isMe: true).map(\.tabSymbol),
                       ["square.grid.2x2", "book.closed", "flag", "bookmark"])
        XCTAssertEqual(ProfileTab.tabs(isMe: false).map(\.tabSymbol), ["square.grid.2x2", "map"])
        XCTAssertNotEqual(ProfileTab.wishlist.systemImage, "heart", "行きたい場所がいいねのハートと同じ印")
        // 印を持たない区分（すれちがい帳の並びなど）は nil のまま。
        // 2026-11-14 判断（統合 1.1.87）: ホームのフィードの区分は #595 で無くなった（`HomeFeed` は並べ方だけ）ので、残る区分で見る
        XCTAssertNil(PassBook.Order.allCases.first?.tabSymbol)
    }

    // MARK: - 払いに付いてくる線

    private let four = (0..<4).map { CGRect(x: CGFloat($0) * 97.5, y: 0, width: 97.5, height: 56) }

    /// 🔴 払いの進み具合に線の位置が付いてくる。指を左へ払う（中身が左へ）と右隣の列へ寄る
    func testUnderlineFollowsSwipeProgress() {
        // 進み具合: 中身の横の量 ÷ 幅（左へ払うと正）。幅の外は ±1 で止める
        XCTAssertEqual(ProfileTabColumnStyle.progress(offset: -195, pageWidth: 390), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ProfileTabColumnStyle.progress(offset: 97.5, pageWidth: 390), -0.25, accuracy: 0.0001)
        XCTAssertEqual(ProfileTabColumnStyle.progress(offset: -800, pageWidth: 390), 1)
        XCTAssertEqual(ProfileTabColumnStyle.progress(offset: -100, pageWidth: 0), 0)

        let rest = ProfileTabColumnStyle.underlineRect(columns: four, selected: 1, progress: 0)
        XCTAssertEqual(rest.minX, 97.5 + 8, accuracy: 0.001)
        XCTAssertEqual(rest.width, 97.5 - 16, accuracy: 0.001, "線が列の幅から左右 8 を引いた長さでない")
        XCTAssertEqual(rest.maxY, 56, accuracy: 0.001, "線が札の下端に無い")
        XCTAssertEqual(rest.height, 2)

        let half = ProfileTabColumnStyle.underlineRect(columns: four, selected: 1, progress: 0.5)
        XCTAssertEqual(half.minX, 97.5 + 8 + 48.75, accuracy: 0.001, "半分払っても線が半列ぶん動かない")
        let back = ProfileTabColumnStyle.underlineRect(columns: four, selected: 1, progress: -0.25)
        XCTAssertEqual(back.minX, 97.5 + 8 - 24.375, accuracy: 0.001, "右へ払っても線が左隣へ寄らない")
        let whole = ProfileTabColumnStyle.underlineRect(columns: four, selected: 1, progress: 1)
        XCTAssertEqual(whole.minX, 195 + 8, accuracy: 0.001, "払いきったのに線が隣の列に着かない")
        // 進み具合の分だけ単調に右へ
        var last = -CGFloat.infinity
        for step in 0...10 {
            let x = ProfileTabColumnStyle.underlineRect(columns: four, selected: 0, progress: CGFloat(step) / 10).minX
            XCTAssertGreaterThan(x, last)
            last = x
        }
    }

    /// 隣の無い向き（いちばん左で右へ払う）では動かない。横に送る並び（幅の違う列）では長さも隣の列へ伸び縮みする
    func testUnderlineEdgesAndUnequalColumns() {
        let first = ProfileTabColumnStyle.underlineRect(columns: four, selected: 0, progress: -0.5)
        XCTAssertEqual(first, ProfileTabColumnStyle.underlineRect(columns: four, selected: 0, progress: 0))
        let last = ProfileTabColumnStyle.underlineRect(columns: four, selected: 3, progress: 0.5)
        XCTAssertEqual(last, ProfileTabColumnStyle.underlineRect(columns: four, selected: 3, progress: 0))
        XCTAssertEqual(ProfileTabColumnStyle.underlineRect(columns: four, selected: 9, progress: 0), .zero)

        let uneven = [CGRect(x: 0, y: 0, width: 100, height: 56), CGRect(x: 100, y: 0, width: 140, height: 56)]
        let mid = ProfileTabColumnStyle.underlineRect(columns: uneven, selected: 0, progress: 0.5)
        XCTAssertEqual(mid.minX, 8 + 50, accuracy: 0.001)
        XCTAssertEqual(mid.width, (84 + 124) / 2, accuracy: 0.001)
    }

    /// 🔴 線は中身の横の量（分け合う箱）を見て寄る。「視差効果を減らす」では指に付けない。払いは幅を量より先に書く
    func testRowReadsTheSharedDragAndRespectsReduceMotion() throws {
        let row = try source("Profile/ProfileTabColumns.swift")
        XCTAssertTrue(row.contains("@ObservedObject var drag: ProfileTabDrag"))
        XCTAssertTrue(row.contains("guard !reduceMotion else { return 0 }"), "視差効果を減らすでも線が指に付いてくる")
        XCTAssertTrue(row.contains("ProfileTabColumnsLayout(selected: selectedIndex, progress: progress,"))
        XCTAssertTrue(row.contains("withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion))"),
                      "押したときに線がばねで滑らない")
        // 識別子は今の札と同じ（UI テストを変えない）
        XCTAssertTrue(row.contains(".accessibilityIdentifier(option.tabIdentifier)"))
        XCTAssertTrue(row.contains(".accessibilityAddTraits(selected ? .isSelected : [])"))

        let pager = try source("Profile/ProfileTabPager.swift")
        let width = try XCTUnwrap(pager.range(of: "follow?.width = CGFloat(width)"), "払いが中身の幅を書いていない")
        let offset = try XCTUnwrap(pager.range(of: "follow?.offset = CGFloat(Tab.followOffset"))
        XCTAssertLessThan(width.lowerBound, offset.lowerBound, "幅を量より後に書いている（線が前の幅で寄る）")
        let bar = try source("Profile/ProfileTabBar.swift")
        XCTAssertTrue(bar.contains("control.drag.width = width"), "留まった札の払いが中身の幅を書いていない")
    }

    // MARK: - 使う画面

    /// 🔴 マイページと人のページは同じ「絵と字」（画面ごとに割らない）で、札の行の払いも中身と線を指に付ける。
    /// ホーム・フォロー一覧（`ProfileTabSection`）などは字の札のまま
    func testOnlyProfilesUseIconColumns() throws {
        let myPage = try source("Profile/MyPageView.swift")
        XCTAssertTrue(myPage.contains("iconColumns: true, follow: tabPager.drag"), "マイページが案 B でない")
        XCTAssertEqual(myPage.components(separatedBy: "follow: tabPager.drag").count - 1, 2,
                       "マイページの札の行の払いで線が付いてこない（札の行と払いの両方に箱を渡す）")
        XCTAssertTrue(myPage.contains("willShow: { next in tabPager.willShow?(next) }"))
        let user = try source("Profile/UserProfileView.swift")
        XCTAssertTrue(user.contains("iconColumns: true, follow: tabPager.drag"), "人のページがマイページと違う札")
        XCTAssertTrue(user.contains("control: tabPager"), "人のページの中身の横の量を札の行と分け合っていない")

        for other in ["Gallery/GalleryView.swift", "Profile/ProfileTabPager.swift", "Search/SearchSpotIndexSection.swift",
                      "Upload/PhotoEditView.swift", "Map/PhotoMapView.swift"] {
            XCTAssertFalse(try source(other).contains("iconColumns: true"), "\(other) まで絵と字に広げている")
        }
    }
}
