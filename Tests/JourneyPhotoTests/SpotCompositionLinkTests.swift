import XCTest
@testable import JourneyPhoto

/// 撮影スポットの頁の「構図一覧を見る ›」（札 #519・提案「旅の道具の置き場」第5版の仕様 4）。
/// 構図のヒントがある撮影スポットだけに出る・字と識別子・公式サイトのリンクと同じ形・設定の行は残す。
final class SpotCompositionLinkTests: XCTestCase {

    func testShowsOnlyWithTips() {
        XCTAssertFalse(SpotCompositionLink.shows(tips: []))
        XCTAssertTrue(SpotCompositionLink.shows(tips: ["朝の逆光で、天守を山の稜線に重ねる"]))
    }

    func testTextsAndIdentifier() {
        XCTAssertEqual(SpotCompositionLink.title, "構図一覧を見る ›")
        // 読み上げは「›」を読ませない
        XCTAssertEqual(SpotCompositionLink.spokenLabel, "構図一覧を見る")
        XCTAssertEqual(SpotCompositionLink.identifier, "spot.compositionCatalog")
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    func testWiring() throws {
        let spot = try source("Features/Spots/OfficialSpotView.swift")
        // ヒントの箇条の下（同じ「構図のヒント」のかたまりの中）・箇条との間 4pt
        let tips = try XCTUnwrap(spot.range(of: "guideLabel(L(\"構図のヒント\", \"Composition\"))"))
        let link = try XCTUnwrap(spot.range(of: "if SpotCompositionLink.shows(tips: body.compositionTips) {\n                                compositionCatalogLink"))
        let site = try XCTUnwrap(spot.range(of: "if let site = spotBody?.officialWebsite {"))
        XCTAssertLessThan(tips.lowerBound, link.lowerBound)
        XCTAssertLessThan(link.lowerBound, site.lowerBound, "公式サイトのリンクより下に置いた")
        XCTAssertTrue(spot.contains("VStack(alignment: .leading, spacing: JPSpace.xxs) {\n                            VStack(alignment: .leading, spacing: JPSpace.xs) {\n                                guideLabel(L(\"構図のヒント\""))
        // 公式サイトと同じ形（15 の 600・下線・真鍮・当たり 44・左右 16）。押すと構図一覧を積む
        let body = try XCTUnwrap(spot.components(separatedBy: "private var compositionCatalogLink: some View {").dropFirst().first)
            .components(separatedBy: "private func guideLabel").first ?? ""
        for piece in ["NavigationLink { CompositionCatalogView() }", ".font(JPFont.bodyEmphasis)", ".underline()",
                      ".frame(minHeight: WebTheme.minTapTarget)", ".foregroundStyle(WebTheme.accent)",
                      ".padding(.horizontal, JPSpace.m)", ".accessibilityLabel(SpotCompositionLink.spokenLabel)",
                      ".accessibilityIdentifier(SpotCompositionLink.identifier)"] {
            XCTAssertTrue(body.contains(piece), "リンクに \(piece) が無い")
        }
        XCTAssertFalse(body.contains("arrow.up.right"), "外へ出ないのに ↗ を付けた")
        // 設定の構図一覧の行は残す（ヒントの無い撮影スポットもある）
        let settings = try source("Features/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains(".accessibilityIdentifier(\"settings.compositionCatalog\")"))
    }
}
