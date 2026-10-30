import XCTest
@testable import JourneyPhoto

/// ストーリーを作る画面は端末の画面いっぱいで出す（2026-10-30 判断 #406）。
/// シートで出すと、上の隙間（時計の帯〜✕ の上）に下の画面（開いた元の画面のカバー写真など）が透けた
final class StoryComposerPresentationTests: XCTestCase {

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
    }

    /// 注記（`//`・`///`）を除いた中身
    private func source(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 作る画面を出している所（`StoryComposerView(` を呼ぶ所）と、その直前の出し方の修飾子
    private func presenters() throws -> [(file: String, modifier: String)] {
        let walker = FileManager.default.enumerator(at: Self.root, includingPropertiesForKeys: nil)
        var out: [(String, String)] = []
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift", url.lastPathComponent != "StoryComposerView.swift" else { continue }
            let text = try source(url)
            var searchFrom = text.startIndex
            while let call = text.range(of: "StoryComposerView(", range: searchFrom..<text.endIndex) {
                let before = text[text.startIndex..<call.lowerBound]
                let sheet = before.range(of: ".sheet(", options: .backwards)?.lowerBound
                let cover = before.range(of: ".fullScreenCover(", options: .backwards)?.lowerBound
                let modifier: String
                switch (sheet, cover) {
                case let (s?, c?): modifier = s > c ? "sheet" : "fullScreenCover"
                case (_?, nil): modifier = "sheet"
                case (nil, _?): modifier = "fullScreenCover"
                default: modifier = "none"
                }
                out.append((url.lastPathComponent, modifier))
                searchFrom = call.upperBound
            }
        }
        return out
    }

    /// 🔴 どの入口からでも `fullScreenCover`（シートのカードだと上に下の画面が透ける）
    func testEveryEntryPresentsComposerFullScreen() throws {
        let found = try presenters()
        let files = Set(found.map(\.file))
        // 入口が見つからないまま緑にならないように（ホームの「＋」・投稿の選択・下書き＝RootView、輪＝StoriesRow）
        XCTAssertTrue(files.contains("RootView.swift"), "RootView の入口が見つからない: \(found)")
        XCTAssertTrue(files.contains("StoriesRow.swift"), "StoriesRow の入口が見つからない: \(found)")
        for entry in found {
            XCTAssertEqual(entry.modifier, "fullScreenCover",
                           "\(entry.file) が作る画面を \(entry.modifier) で出している（上の端に下の画面が透ける・#406）")
        }
    }

    /// 画面いっぱいでは下へ払って閉じられない。ログインを確かめている間の段にも閉じる口がある
    /// （写真を選ぶ段・仕上げる段は ✕、ログインの段は見出しの「閉じる」）
    func testResolvingStageHasCloseButton() throws {
        let text = try source(Self.root.appendingPathComponent("Features/Stories/StoryComposerView.swift"))
        guard let start = text.range(of: "case .resolving:"),
              let end = text.range(of: "case .signIn:", range: start.upperBound..<text.endIndex) else {
            return XCTFail("body の段の分け方が見つからない")
        }
        let resolving = text[start.upperBound..<end.lowerBound]
        XCTAssertTrue(resolving.contains("Labels.Common.close") && resolving.contains("dismiss()"),
                      "ログインを確かめている間の段に閉じる口が無い（画面いっぱいでは出られなくなる）")
    }
}
