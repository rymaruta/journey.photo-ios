import XCTest
@testable import JourneyPhoto

/// マイページ・人のページで、自分（その人）の写真の格子を最初の画面に上げる（2026-10-21・全画面の点検）。
///
/// 🔴 カバー・数・旅の記録の線（高さ 100）・BGM の札・ハイライトの下に格子があり、写真が最初の画面の
/// 一番下にしか出なかった。旅の記録の線は初めは畳み（眉ラベルの右の「線を見る」で開く・両方のページで
/// 同じ部品）、BGM は見出しの中の1行に畳んだ
final class ProfileGridFirstTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 🔴 旅の記録の線は初めは畳む（マイページと人のページで同じ部品）
    func testTravelRouteStartsFolded() throws {
        XCTAssertTrue(TravelRecordSection.routeStartsFolded)
        let section = try source("Sources/JourneyPhoto/Features/Profile/TravelRecordSection.swift")
        XCTAssertTrue(section.contains("routeShown: routeOpen"), "線の開け閉めを部品に渡していない")
        XCTAssertTrue(section.contains("onRouteToggle:"), "線を開く手が無い（畳んだまま開けない）")
        let view = try source("Sources/JourneyPhoto/Features/Profile/TravelRecordView.swift")
        XCTAssertTrue(view.contains("if routeShown, let shape"), "畳んでいても線を描いている")
        // 両方のページが同じ部品を使う
        for page in ["MyPageView", "UserProfileView"] {
            let text = try source("Sources/JourneyPhoto/Features/Profile/\(page).swift")
            XCTAssertTrue(text.contains("TravelRecordSection(summary: summary"), "\(page) が旅の記録の部品を使っていない")
        }
    }

    /// 🔴 BGM は見出しの中の1行（数の下の札にしない）。格子の札より上に札の BGM を置かない
    func testBgmIsALineInTheHeader() throws {
        let page = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        let header = try XCTUnwrap(page.range(of: "private func header(_ profile: UserProfile)"))
        let headerEnd = try XCTUnwrap(page.range(of: "private func avatar(", range: header.upperBound..<page.endIndex))
        XCTAssertTrue(page[header.upperBound..<headerEnd.lowerBound].contains("bgmLine(profile)"),
                      "BGM が見出しの中に無い")
        let scroll = try XCTUnwrap(page.range(of: "private func scroll(topInset: CGFloat)"))
        let scrollEnd = try XCTUnwrap(page.range(of: "private func reloadAll()", range: scroll.upperBound..<page.endIndex))
        let body = String(page[scroll.upperBound..<scrollEnd.lowerBound])
        XCTAssertFalse(body.contains("bgmCard("), "BGM の札が数の下に残っている")
        XCTAssertFalse(body.contains("bgmLine("), "BGM が見出しの外（格子の上）に出ている")
        // 1行の見た目（2026-10-24 owner の要望でジャケットの行に）: ジャケット 48・再生の丸 44
        // ＝行の高さが 44 を越えるので、押せる範囲を広げる必要が無い
        XCTAssertEqual(ProfileBgmCard.artworkSide, 48)
        XCTAssertEqual(ProfileBgmCard.playSide, WebTheme.minTapTarget)
        XCTAssertGreaterThanOrEqual(ProfileBgmCard.artworkSide, WebTheme.minTapTarget)
    }

    /// 🔴 押せる範囲は**範囲の形だけ**広げる（負の余白で張り出さない）。字を大きくして行が伸びたとき、
    /// 張り出した分が上下の行に重なる（2026-10-21・確かめ役の見直し）
    func testTapAreasGrowWithoutNegativePadding() throws {
        let bgm = try source("Sources/JourneyPhoto/Features/Profile/ProfileBgmCard.swift")
        XCTAssertFalse(bgm.contains("padding(.vertical, -"), "BGM の行が負の余白で張り出している")
        XCTAssertTrue(bgm.contains(".frame(minHeight: Self.artworkSide)\n            .contentShape(Rectangle())"),
                      "曲の行ぜんぶが押せる範囲になっていない")
        let record = try source("Sources/JourneyPhoto/Features/Profile/TravelRecordView.swift")
        let toggle = try XCTUnwrap(record.range(of: "private func routeToggle("))
        let end = try XCTUnwrap(record.range(of: "toggleTapSlack: CGFloat", range: toggle.upperBound..<record.endIndex))
        let body = String(record[toggle.upperBound..<end.lowerBound])
        XCTAssertFalse(body.contains("padding(.vertical, -"), "「線を見る」が負の余白で張り出している")
        XCTAssertTrue(body.contains(".contentShape(Rectangle().inset(by: -Self.toggleTapSlack))"))
        // 線そのものが読み上げに乗らないので、開け閉めも読ませない
        // （矢印の絵にも同じ修飾があるので、ボタンに付いていることを目印の直前で見る）
        XCTAssertTrue(body.contains(".accessibilityHidden(true)\n        .accessibilityIdentifier(\"profile.travelRecord.routeToggle\")"),
                      "「線を見る」が読み上げに出ている")
    }
}
