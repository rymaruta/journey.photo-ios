import XCTest
@testable import JourneyPhoto

/// 使い方の入口（2026-11-12 札 #517・owner「使い方を優先的に作りたいな」）。
///
/// - 行き先は Web の `/help`（中身は Web の頁。機能ごとに絵1枚と3行）
/// - 入口は **設定 → ヘルプと規約 のいちばん上の1か所だけ**（ほかの画面に入口を増やさない・資料「説明なしで分かるアプリ」）
/// - 押すとアプリの中の Safari（`SFSafariViewController`）で開き、「閉じる」で設定へ戻る
final class HelpEntryTests: XCTestCase {

    /// Info.plist を持たない環境（Linux の模型）でも動くように、サイトの URL を明示する（`ProfileAssetURLTests` と同じ）
    override func setUp() {
        super.setUp()
        AppConfig.testOverrides = ["JPSiteBaseURL": "https://example.test"]
    }

    override func tearDown() {
        AppConfig.testOverrides = nil
        super.tearDown()
    }

    private func sourcesRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
    }

    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: sourcesRoot().appendingPathComponent(path), encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testOpensTheWebHelpPage() {
        XCTAssertEqual(HelpLink.url.host, AppConfig.siteBaseURL.host)
        XCTAssertEqual(HelpLink.url.path, "/help")
    }

    /// 行の言葉。画面の文を「・」「·」で区切らない（2026-11-12 owner の好み）
    func testRowWording() {
        XCTAssertEqual(HelpLink.title, L("使い方", "How to use"))
        XCTAssertFalse(HelpLink.title.isEmpty)
        for text in [HelpLink.title, HelpLink.detail] {
            XCTAssertFalse(text.contains("・") || text.contains("·"), "中黒で区切っている: \(text)")
        }
    }

    /// ヘルプと規約の節のいちばん上の行で、押すとアプリの中の Safari で /help を開く
    func testRowIsFirstInHelpSectionAndOpensInAppSafari() throws {
        XCTAssertEqual(SettingsOutline.Part.help.items.first, "settings.help")
        let view = try source("Features/Settings/SettingsView.swift")
        guard let start = view.range(of: "private var helpSection: some View {"),
              let end = view.range(of: "private var accountSection", range: start.upperBound..<view.endIndex) else {
            return XCTFail("ヘルプと規約の節が無い")
        }
        let help = String(view[start.upperBound..<end.lowerBound])
        let row = try XCTUnwrap(help.range(of: "Button { showHelp = true }"), "使い方の行が無い")
        let whatsNew = try XCTUnwrap(help.range(of: "Button { showWhatsNew = true }"))
        XCTAssertLessThan(row.lowerBound, whatsNew.lowerBound, "使い方の行が節のいちばん上に無い")
        XCTAssertTrue(help.contains("JPRowLabel(title: HelpLink.title, detail: HelpLink.detail)"))
        XCTAssertTrue(help.contains(".accessibilityIdentifier(\"settings.help\")"))
        // 未ログインでも出す（ログインの出し分けの中に置かない）
        let beforeRow = String(help[help.startIndex..<row.lowerBound])
        XCTAssertFalse(beforeRow.contains("auth.userId"), "使い方をログインしている人だけにしている")
        // 開き方: アプリの中の Safari
        XCTAssertTrue(view.contains(".fullScreenCover(isPresented: $showHelp) {\n            InAppSafariView(url: HelpLink.url)"),
                      "使い方をアプリの中の Safari で開いていない")
    }

    /// アプリの中の Safari は「閉じる」で呼び手を閉じる（閉じても設定に戻れないと迷う）
    func testInAppSafariDismissesOnClose() throws {
        let link = try source("Features/Settings/HelpLink.swift")
        XCTAssertTrue(link.contains("SFSafariViewController(url: url)"))
        XCTAssertTrue(link.contains("controller.delegate = context.coordinator"))
        XCTAssertTrue(link.contains("func safariViewControllerDidFinish(_ controller: SFSafariViewController) {\n            dismiss()"))
    }

    /// 入口は設定の1か所だけ（ほかの画面から /help を開かない）
    func testNoOtherEntryPoints() throws {
        let root = sourcesRoot()
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty)
        var users: [String] = []
        for file in files {
            let rel = String(file.path.dropFirst(root.path.count + 1))
            guard rel != "Features/Settings/HelpLink.swift" else { continue }
            let text = try source(rel)
            if text.contains("HelpLink.url") || text.contains("\"help\")") || text.contains("/help\"") {
                users.append(rel)
            }
        }
        XCTAssertEqual(users, ["Features/Settings/SettingsView.swift"])
    }
}
