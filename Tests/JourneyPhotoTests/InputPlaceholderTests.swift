import XCTest
@testable import JourneyPhoto

/// 入力欄の見本の字（placeholder）は白 50%（`WebTheme.placeholder`）にそろえる（2026-11-14 判断・点検「画面と手ざわり」の直すべき）。
///
/// 前は `WebTheme.placeholder` を定義したまま、どの入力欄も使っておらず、iOS の既定の見本の色で
/// 入力欄の地 #161617 に対して 2.2〜2.5:1 しか無かった（字の線 4.5:1 に届かない）。
/// 入力欄は `JPTextField`・`JPSecureField`（`Core/Design/FormParts.swift`）だけで作り、見本の色を一か所から当てる。
/// 画面は Linux で描けないので、書いてあるもので固定する（`SheetClosePlacementTests` と同じ作り）
@MainActor
final class InputPlaceholderTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
    }

    private func allSources() throws -> [(name: String, text: String)] {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        return try files.map { ($0.path.replacingOccurrences(of: root.path + "/", with: ""),
                                try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// 直に `TextField(`・`SecureField(` を書いてよい所。**どれも見本の字を自分で決めている**
    private static let allowed: [String: String] = [
        // 部品そのもの
        "Core/Design/FormParts.swift": "JPTextField・JPSecureField の中身",
        // 写真の上のひとこと。写真の上は白だけ（CLAUDE.md）なので、案内の字は白 90% ＋影を `prompt:` で自分で持つ
        "Features/Stories/StoryComposerView.swift": "写真の上のひとこと（prompt: で白を渡す）",
        // ストーリーの画面に直に打つ字。見本は置いたあとと同じ書体・色・縁で描く（入力欄の地が無い）
        "Features/Stories/StoryTextTypingView.swift": "写真の上に直に打つ文字（欄の地が無い）",
    ]

    /// 🔴 入力欄を `TextField(`・`SecureField(` で直に作らない（見本の字が iOS の既定の色に戻る）
    func testEveryInputUsesThePlaceholderComponent() async throws {
        let raw = try NSRegularExpression(pattern: #"(?<![A-Za-z_.])(TextField|SecureField)\("#)
        var bad: [String] = []
        for (name, text) in try allSources() where Self.allowed[name] == nil {
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.components(separatedBy: "//").first ?? line
                let range = NSRange(code.startIndex..., in: code)
                if raw.firstMatch(in: code, range: range) != nil { bad.append("\(name):\(index + 1)") }
            }
        }
        XCTAssertEqual(bad, [], "入力欄は `JPTextField`・`JPSecureField` で作る（見本の字を白 50% にそろえる）")
    }

    /// 部品が見本の字を `WebTheme.placeholder` で組むこと（`prompt:` を渡さないと既定の色に戻る）
    func testComponentsPassThePlaceholderPrompt() async throws {
        let text = try String(contentsOf: root.appendingPathComponent("Core/Design/FormParts.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains("static let color = WebTheme.placeholder"))
        XCTAssertTrue(text.contains("TextField(title, text: $text, prompt: JPInputPrompt.text(title), axis: axis)"))
        XCTAssertTrue(text.contains("SecureField(title, text: $text, prompt: JPInputPrompt.text(title))"))
    }

    /// 白 50% は入力欄の地（surface-2 #161617）の上で字の線 4.5:1 を超える（板 01「35% は 3.0 で届かない」）
    func testPlaceholderContrastOnFieldSurface() async {
        // 白 50% を #161617 に重ねた色
        let bg = (r: 0x16, g: 0x16, b: 0x17)
        func mix(_ c: Int) -> Double { (255.0 * 0.5 + Double(c) * 0.5) / 255.0 }
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
        let fg = lum(mix(bg.r), mix(bg.g), mix(bg.b))
        let ground = lum(Double(bg.r) / 255, Double(bg.g) / 255, Double(bg.b) / 255)
        let ratio = (fg + 0.05) / (ground + 0.05)
        XCTAssertGreaterThan(ratio, 4.5)
        XCTAssertEqual(ratio, 5.24, accuracy: 0.05)
    }
}
