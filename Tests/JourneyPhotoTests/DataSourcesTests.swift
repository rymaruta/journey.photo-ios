import XCTest
@testable import JourneyPhoto

/// 設定 → 利用規約、プライバシーポリシー の「データの出典」（2026-11-19・`DataSources`・`LegalLinksView`）
final class DataSourcesTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 同梱したデータの3つを並べる。国土数値情報は決まり（CC BY 4.0）が求める「〜を加工して作成」の形
    func testListsTheBundledDataSources() {
        XCTAssertEqual(DataSources.all.map(\.id), ["ksj", "soumu", "naturalEarth"])
        let ksj = DataSources.all[0]
        XCTAssertEqual(ksj.title, "国土数値情報（国土交通省）")
        // 加工したのはデータ（規約ではない）と読める形（2026-11-19 確かめ役の指摘）
        XCTAssertEqual(ksj.detail,
                       "市区町村役場の位置: 「国土数値情報（市町村役場等及び公的集会施設データ）」（国土交通省）を加工して作成（CC BY 4.0）")
        XCTAssertEqual(ksj.url.host, "nlftp.mlit.go.jp")
        // CC BY 4.0 の本文へのリンク（押せる形・`LegalLicenseRow`）
        XCTAssertEqual(ksj.license?.url.absoluteString, "https://creativecommons.org/licenses/by/4.0/deed.ja")
        XCTAssertEqual(ksj.license?.label, "CC BY 4.0 の本文")
        let soumu = DataSources.all[1]
        XCTAssertEqual(soumu.title, "総務省「全国地方公共団体コード」")
        XCTAssertEqual(soumu.detail,
                       "市区町村の名前と都道府県: 「全国地方公共団体コード」（総務省、令和6年1月1日現在）を加工して作成（公共データ利用規約 第1.0版）")
        XCTAssertNil(soumu.license)
        XCTAssertEqual(soumu.url.absoluteString, "https://www.soumu.go.jp/denshijiti/code.html")
        let ne = DataSources.all[2]
        XCTAssertEqual(ne.title, "Natural Earth")
        XCTAssertTrue(ne.detail.contains("パブリックドメイン"), ne.detail)
        for source in DataSources.all {
            XCTAssertEqual(source.url.scheme, "https", source.id)
            // 中黒で区切らない（owner の好み・2026-11-12）
            XCTAssertFalse(source.title.contains("・") || source.detail.contains("・"), source.id)
            XCTAssertFalse(source.title.contains("·") || source.detail.contains("·"), source.id)
        }
    }

    /// 同梱のファイルの作り方（Tools）と、コードの注記が同じ出典を書いている
    func testToolsAndCodeNameTheSameSources() throws {
        let tool = try String(contentsOf: Self.root.appendingPathComponent("Tools/generate-municipal-offices.py"), encoding: .utf8)
        XCTAssertTrue(tool.contains("KsjTmplt-P05-2022.html"))
        XCTAssertTrue(tool.contains("https://www.soumu.go.jp/denshijiti/code.html"))
        XCTAssertTrue(tool.contains("CC BY 4.0"))
    }

    /// 画面: 設定の下の画面と同じ形（`SettingsPage`・`SettingsGroup`）で、規約2行の下に「データの出典」の節。
    /// 行は外へ出るリンク（`Link`）で、字は真鍮
    func testLegalScreenShowsTheSourcesSection() throws {
        let view = try String(contentsOf: Self.root.appendingPathComponent("Sources/JourneyPhoto/Features/Settings/LegalLinksView.swift"),
                              encoding: .utf8)
        XCTAssertTrue(view.contains("SettingsPage(L(\"利用規約、プライバシーポリシー\""))
        XCTAssertTrue(view.contains("SettingsGroup(L(\"データの出典\", \"Data sources\"))"))
        XCTAssertTrue(view.contains("ForEach(Array(DataSources.all.enumerated())"))
        XCTAssertTrue(view.contains("Link(destination: source.url)"))
        XCTAssertTrue(view.contains(".foregroundStyle(WebTheme.accent)"), "リンクの字は真鍮")
        XCTAssertTrue(view.contains(".font(.caption)"), "説明は 12pt（caption）")
        XCTAssertTrue(view.contains(".frame(minHeight: 54)"), "行は 44pt 以上")
        // 決まりの本文は出典の行とは別に押せるリンク（行の中に入れ子にしない）。当たりは 44pt
        XCTAssertTrue(view.contains("if let license = source.license {"))
        XCTAssertTrue(view.contains("Link(destination: license.url)"))
        XCTAssertTrue(view.contains(".accessibilityIdentifier(\"legal.license.\\(source.id)\")"))
        XCTAssertTrue(view.contains(".frame(minHeight: 44)"), "決まりの本文のリンクの当たりは 44pt")
        let terms = try XCTUnwrap(view.range(of: "legal.terms"))
        let sources = try XCTUnwrap(view.range(of: "SettingsGroup(L(\"データの出典\""))
        XCTAssertLessThan(terms.lowerBound, sources.lowerBound, "規約が上、出典が下")
    }
}
