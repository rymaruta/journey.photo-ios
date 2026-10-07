import XCTest

/// マイページの「旅の記録」のタブに、共同アルバムと旅行プランの入口があること（2026-10-07）。
///
/// アルバムは設定の奥、旅行プランはメニューの奥にしか入口が無く、見つけてもらえなかった。
/// 画面は模型で動かせないので、書いてあることを見る
final class MyPageTripToolsTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testTripsTabHasAlbumAndPlanEntries() throws {
        let view = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(view.contains("tripToolsCard"), "旅の記録のタブに入口の札が無い")
        XCTAssertTrue(view.contains("NavigationLink { AlbumsView() }"), "共同アルバムの入口が無い")
        XCTAssertTrue(view.contains("NavigationLink { TripPlansView() }"), "旅行プランの入口が無い")
        XCTAssertTrue(view.contains("\"trips.albums\""), "画面写真で探す名前が無い")
    }

    /// 札を置いたのは旅の記録のタブの中（`tripsArea`）。上の見出しの所に戻すと、
    /// 板 05c で外したボタンの列が戻ってしまう
    func testEntriesLiveInsideTripsArea() throws {
        let view = try source("Features/Profile/MyPageView.swift")
        guard let area = view.range(of: "private var tripsArea: some View {"),
              let card = view.range(of: "tripToolsCard", range: area.upperBound..<view.endIndex),
              let next = view.range(of: "nonisolated static func wishlistPool", range: area.upperBound..<view.endIndex)
        else { return XCTFail("tripsArea・tripToolsCard・wishlistPool のどれかが見つからない") }
        XCTAssertLessThan(card.lowerBound, next.lowerBound, "入口の札が旅の記録のタブの中に無い")
    }

    /// 最初の読み込みに失敗して知らせ（`ErrorBanner`）が旅の記録を差し替えても、札は残す
    /// （アルバム・旅行プランは自分の写真の読み込みと無関係・2026-10-07）
    func testEntriesSurviveFirstLoadFailure() throws {
        let view = try source("Features/Profile/MyPageView.swift")
        guard let area = view.range(of: "private var photoArea: some View {"),
              let failure = view.range(of: "} else if let error = model.errorMessage {",
                                       range: area.upperBound..<view.endIndex),
              let next = view.range(of: "} else if tab == .trips {", range: failure.upperBound..<view.endIndex)
        else { return XCTFail("photoArea の読み込み失敗の枝が見つからない") }
        let branch = view[failure.upperBound..<next.lowerBound]
        XCTAssertTrue(branch.contains("ErrorBanner"), "読み込み失敗の知らせが無い")
        XCTAssertTrue(branch.contains("if tab == .trips") && branch.contains("tripToolsCard"),
                      "読み込みに失敗すると旅の記録の札まで消える")
    }
}
