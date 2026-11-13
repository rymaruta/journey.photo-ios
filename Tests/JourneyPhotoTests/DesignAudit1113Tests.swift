import Foundation
import XCTest
@testable import JourneyPhoto

/// 画面デザインの点検（2026-11-13・1.1.85 の画面写真とコードを板に突き合わせた）で「直すべき」とされたうち7件。
///
/// 1 観光スポットの一覧の丸が真鍮の塗り / 2 写真の詳細「次の旅へ」で「旅行プラ…」と切れる /
/// 3 現像の上の札と × が状態バーの中 / 4 大きい文字でマイページの名前が2字で切れる /
/// 5 お知らせの題が標準の大きい見出し / 7 DM の観光スポットの札でボタンの上が空く /
/// 8 顔写真の無い人の印が画面で違う。
/// 画面の部品は Linux で動かせないので、決まりは値で、配線は元のコードを読んで確かめる
/// （大きさを実際に測る分は `DMSpotCardBoxTests`（iOS だけ）と ScreenshotTests）
@MainActor
final class DesignAudit1113Tests: XCTestCase {

    // MARK: - 道具

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
    }

    /// 元のコード（注記の行 `//` は数えない）
    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
        return Self.dropComments(text)
    }

    private static func dropComments(_ text: String) -> String {
        text.components(separatedBy: "\n")
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

    private func assertInOrder(_ parts: [String], in text: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: cursor..<text.endIndex) else {
                XCTFail("\(what): 「\(part)」が順に無い", file: file, line: line)
                return
            }
            cursor = found.upperBound
        }
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - 1 観光スポットの一覧の丸

    /// 板 04「10px 以上の塗りの丸に真鍮を使わない」。地は surface-3、写真の無い丸のカメラは text-3、縁だけ真鍮
    func testSpotListMarkIsNotABrassFilledCircle() async throws {
        let row = slice(try source("Features/Spots/OfficialSpotRow.swift"), from: "var body: some View {",
                        to: "nonisolated static func subline")
        XCTAssertFalse(row.contains(".background(WebTheme.accent"), "40pt の丸を真鍮で塗っている")
        XCTAssertFalse(row.contains("WebTheme.accentText"), "墨のカメラ（真鍮の塗りの上の色）が残っている")
        assertInOrder(["SpotThumbImage(image: photo)", ".background(Self.markFill)",
                       ".overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: JPStroke.emphasis))",
                       "Image(systemName: \"camera.fill\")", ".foregroundStyle(WebTheme.text3)",
                       ".background(Self.markFill, in: Circle())",
                       ".overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: JPStroke.emphasis))"],
                      in: row, "写真の丸と写真の無い丸")
        XCTAssertTrue(try source("Features/Spots/OfficialSpotRow.swift").contains("static let markFill = WebTheme.surface3"))
        XCTAssertEqual(OfficialSpotRow.markSize, 40)
        XCTAssertEqual(BrandPalette.surface3, 0x1A1A1C)
    }

    // MARK: - 2 写真の詳細「次の旅へ」

    /// 観光スポットの頁と同じ部品・同じ1段の並び。前の横の札（左右 16 の余白・印の横に字）は残さない
    func testPhotoTripActionsUseTheSpotPageParts() async throws {
        let section = try source("Features/PhotoDetail/PhotoTripSection.swift")
        let body = slice(section, from: "var body: some View {", to: ".tripAddSheet($tripAdd)")
        assertInOrder(["HStack(spacing: JPSpace.xs) {", "wishButton", "tripButton",
                       "if PhotoTrip.offersDirections(destination) {", "directionsButton"], in: body, "札の並び")
        XCTAssertFalse(body.contains("ViewThatFits"), "2段の並びが残っている（観光スポットの頁と形が割れる）")
        XCTAssertFalse(section.contains("private func chip("), "前の横の札が残っている")
        XCTAssertEqual(count("SpotDetailParts.actionLabel(", in: section), 3)
        assertInOrder(["SpotDetailParts.actionLabel(icon: wanted ? \"flag.fill\" : \"flag\"", "filled: wanted)",
                       "SpotDetailParts.actionLabel(icon: \"calendar.badge.plus\", title: L(\"旅行プランに入れる\"",
                       "SpotDetailParts.actionLabel(icon: \"arrow.triangle.turn.up.right.diamond\"",
                       "busy: openingDirections)"], in: section, "3つの札")
        // 合わせる先（観光スポットの頁）も同じ部品・同じすき間
        let spot = try source("Features/Spots/OfficialSpotView.swift")
        let actions = slice(spot, from: "private var actions: some View {", to: ".tripAddSheet($tripAdd)")
        XCTAssertTrue(actions.contains("HStack(spacing: JPSpace.xs) {"))
        XCTAssertTrue(spot.contains("SpotDetailParts.actionLabel(icon: \"calendar.badge.plus\", title: L(\"旅行プランに入れる\""))
        // 部品は字を切らずに縮める（0.8 まで）・押せる高さは 44 以上
        let parts = try source("Features/Spots/SpotDetailParts.swift")
        XCTAssertTrue(parts.contains(".minimumScaleFactor(WebTheme.minimumScale(forTextSize: JPTypeScale.footnote))"))
        XCTAssertGreaterThanOrEqual(SpotDetailParts.actionHeight, WebTheme.minTapTarget)
    }

    // MARK: - 3 現像の上の札

    /// 上へ広げた（`ignoresSafeArea`）**後に**上の札を重ねる。先に重ねると札まで状態バーの中へ広がる
    func testDevelopTopBarIsOverlaidAfterExtendingThePhoto() async throws {
        let view = try source("Features/Trips/DevelopView.swift")
        let deck = slice(view, from: "private var deckScreen: some View {", to: "strip\n")
        assertInOrder([".frame(maxWidth: .infinity, maxHeight: .infinity)", ".ignoresSafeArea(edges: .top)",
                       ".overlay(alignment: .top) { topBar }"], in: deck, "払う画面の上")
        let top = slice(view, from: "private var topBar: some View {", to: "private func frameCard(")
        XCTAssertFalse(top.contains(".safeAreaPadding("), "安全な範囲に既定の余白を足す（状態バーの高さではない）")
        XCTAssertTrue(top.contains(".padding(.top, JPSpace.xxs)"))
    }

    // MARK: - 4 マイページの名前

    /// 板 06「名前は3行まで折り返す（切らない）」
    func testMyPageNameWrapsUpToThreeLines() async throws {
        XCTAssertEqual(MyPageNameLine.maxLines, 3)
        let view = try source("Features/Profile/MyPageView.swift")
        let line = slice(view, from: "private func nameLine(_ profile: UserProfile) -> some View {",
                         to: "NameMarks(profile: profile")
        assertInOrder(["Text(profile.name)", ".font(JPFont.screenTitle)", ".lineLimit(MyPageNameLine.maxLines)"],
                      in: line, "名前の行")
        XCTAssertFalse(line.contains(".lineLimit(1)"), "名前を1行で切っている")
    }

    // MARK: - 5 お知らせの題

    /// 板 Notifications: 上のバーの真ん中に 17 の太字（Headline）。標準の大きい見出しにしない
    func testNotificationsTitleIsTheInlineHeadline() async throws {
        let view = try source("Features/Notifications/NotificationsView.swift")
        let body = slice(view, from: "var body: some View {", to: ".toolbar {")
        assertInOrder([".navigationTitle(L(\"お知らせ\", \"Activity\"))", ".navigationBarTitleDisplayMode(.inline)"],
                      in: body, "お知らせの題")
        // 同じくシートで開くメッセージの一覧と同じ形
        XCTAssertTrue(try source("Features/Messages/DMInboxView.swift")
            .contains(".navigationTitle(DMText.title)\n        .navigationBarTitleDisplayMode(.inline)"))
    }

    // MARK: - 7 DM の観光スポットの札

    /// 枠の余りは写真に回す（ボタンの上に空きを置かない）。枠の見本は 130 のまま
    func testDMSpotCardGivesTheSlackToThePhoto() async throws {
        let file = try source("Features/Messages/DMSpotCard.swift")
        let card = slice(file, from: "private func card(_ spot: OfficialSpot, index: [OfficialSpot]) -> some View {",
                         to: "private var missingCard: some View {")
        XCTAssertFalse(card.contains("Spacer("), "余りをボタンの上に置いている")
        assertInOrder([".frame(minHeight: Self.photoHeight, maxHeight: .infinity)", "DMSpotCardPhotoPlaceholder(grows: true)",
                       "DMSpotCardText(name: spot.name", "DMSpotCardWishLabel(wanted: wanted)", "DMSpotCardCredit("],
                      in: card, "読めた札の並び")
        let skeleton = slice(file, from: "struct DMSpotCardSkeleton: View {", to: "private struct DMSpotCardSurface")
        XCTAssertTrue(skeleton.contains("DMSpotCardPhotoPlaceholder()\n"), "枠の見本の写真が伸びる（枠の高さが決まらない）")
        XCTAssertFalse(skeleton.contains("grows"))
        let placeholder = slice(file, from: "struct DMSpotCardPhotoPlaceholder: View {", to: "struct DMSpotCardText")
        XCTAssertTrue(placeholder.contains("var grows = false"))
        XCTAssertTrue(placeholder.contains(
            ".frame(minHeight: DMSpotCard.photoHeight, maxHeight: grows ? .infinity : DMSpotCard.photoHeight)"))
    }

    // MARK: - 8 顔写真の無い人の印

    /// 顔はどこも `FaceImage`（人の影 `person.fill`）。風景の「写真」の印・丸の人の印を顔に出さない
    func testFacesShowOnePersonSilhouette() async throws {
        XCTAssertEqual(RemoteImage.personSymbol, "person.fill")
        let face = slice(try source("Features/Common/RemoteImage.swift"), from: "struct FaceImage: View {",
                         to: "enum RemoteImageRetry")
        XCTAssertTrue(face.contains("RemoteImage(url: url, placeholderSymbol: RemoteImage.personSymbol)"))

        // 顔の URL（アバター・プロフィールの顔）を `RemoteImage` に直に渡している所が無い
        let faceURL = try NSRegularExpression(
            pattern: #"RemoteImage\(url:[^)]{0,80}?(avatarURL\(|profileAssetURL\(userId: [^,]+, suffix: nil)"#,
            options: [.dotMatchesLineSeparators])
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: Self.root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = Self.dropComments(try String(contentsOf: url, encoding: .utf8))
            let name = url.lastPathComponent
            if text.contains("placeholderSymbol: \"person") { offenders.append("\(name): 人の印を個別に渡している") }
            if text.contains("Image(systemName: \"person.crop.circle.fill\")") { offenders.append("\(name): 丸の人の印") }
            let range = NSRange(text.startIndex..., in: text)
            if faceURL.firstMatch(in: text, range: range) != nil { offenders.append("\(name): 顔を RemoteImage に直に") }
        }
        XCTAssertEqual(offenders, [], "顔は FaceImage に")

        // 点検で「写真」の印が出ていた画面（人のページ・マイページ・お知らせ・フォロー一覧）と DM
        for path in ["Features/Profile/UserProfileView.swift", "Features/Profile/MyPageView.swift",
                     "Features/Notifications/NotificationsView.swift", "Features/Profile/FollowListView.swift",
                     "Features/Messages/DMParts.swift", "Features/PhotoDetail/PhotoDetailView.swift"] {
            XCTAssertTrue(try source(path).contains("FaceImage(url:"), "\(path) の顔が FaceImage でない")
        }
    }
}
