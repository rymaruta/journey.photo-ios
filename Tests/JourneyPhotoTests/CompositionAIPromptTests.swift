import XCTest
@testable import JourneyPhoto

/// 構図の作例写真（AI で作ったもの）の、作る前と見せる所の見張り（2026-10-14）。
/// - 全 `CompositionKind` に指示文（`Tools/composition-examples/prompts.json`）があり、3枚ぶんの場面がある
/// - 絵の入れ物の名前が構図の名前と食い違わない
/// - 画面に「AI で作った」と分かる表記がある（実写の SNS なので本物と誤解させない）
/// 台帳と絵の突き合わせは `CompositionAIExampleTests`。
final class CompositionAIPromptTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func prompts() throws -> [String: Any] {
        let url = root.appendingPathComponent("Tools/composition-examples/prompts.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(object as? [String: Any])
    }

    func testEveryCompositionHasPromptWithThreeScenes() throws {
        let spec = try prompts()
        XCTAssertEqual(spec["aspectRatio"] as? String, "3:4", "アプリの作例の枠は縦 3:4")
        XCTAssertEqual(spec["candidates"] as? Int, 3)
        let kinds = try XCTUnwrap(spec["kinds"] as? [String: [String: Any]])
        XCTAssertEqual(Set(kinds.keys), Set(CompositionKind.allCases.map(\.rawValue)),
                       "指示文と CompositionKind が食い違っている")
        for (kind, entry) in kinds {
            XCTAssertFalse((entry["placement"] as? String ?? "").isEmpty, "\(kind) に置き場所が無い")
            XCTAssertFalse((entry["lines"] as? String ?? "").isEmpty, "\(kind) に線の位置が無い")
            let scenes = try XCTUnwrap(entry["scenes"] as? [[String: String]], kind)
            XCTAssertEqual(scenes.count, 3, "\(kind) の場面は3つ（候補3枚）")
            for scene in scenes {
                for field in ["where", "subject", "light", "lens"] {
                    XCTAssertFalse((scene[field] ?? "").isEmpty, "\(kind) の場面に \(field) が無い")
                }
            }
        }
    }

    func testCommonRulesForbidFacesTextAndOverprocessing() throws {
        let common = try XCTUnwrap(try prompts()["common"] as? [String: Any])
        let rules = (common["rules"] as? [String] ?? []).joined(separator: " ").lowercased()
        XCTAssertTrue(rules.contains("face"), "人の顔を主役にしない決まりが無い")
        XCTAssertTrue(rules.contains("watermark") && rules.contains("text"), "文字・透かしを入れない決まりが無い")
        XCTAssertTrue(rules.contains("hdr") || rules.contains("oversaturation"), "過度な加工を避ける決まりが無い")
        XCTAssertTrue(rules.contains("landmark") && rules.contains("brand"), "実在の名所・商標を避ける決まりが無い")
    }

    func testBundledExamplesAreKnownCompositions() throws {
        let assets = root.appendingPathComponent("Sources/JourneyPhoto/Assets.xcassets")
        let names = try FileManager.default.contentsOfDirectory(atPath: assets.path)
            .filter { $0.hasPrefix("composition-ai-") && $0.hasSuffix(".imageset") }
        let known = Set(CompositionKind.allCases.map { CompositionAIExample.assetName($0) })
        var total = 0
        for name in names {
            let asset = String(name.dropLast(".imageset".count))
            XCTAssertTrue(known.contains(asset), "\(asset) は構図の名前と合わない")
            let contents = try JSONSerialization.jsonObject(
                with: Data(contentsOf: assets.appendingPathComponent(name).appendingPathComponent("Contents.json")))
            let images = (contents as? [String: Any])?["images"] as? [[String: Any]] ?? []
            XCTAssertEqual(images.first?["filename"] as? String, "\(asset).jpg", "\(asset) の Contents.json")
            let file = assets.appendingPathComponent(name).appendingPathComponent("\(asset).jpg")
            total += (try? Data(contentsOf: file).count) ?? 0
        }
        // 全部で 15 MB まで（37枚が今の 864×1152 で収まる上限。install.mjs は1枚 250 KB を目安に縮める）
        XCTAssertLessThan(total, 15 * 1024 * 1024, "作例写真が大きすぎる。install.mjs --recompress-all で縮める")
    }

    func testAIDisclosureLabels() {
        XCTAssertEqual(CompositionAIExample.assetName(.thirds), "composition-ai-thirds")
        XCTAssertTrue(CompositionAIExample.label.contains("AI"))
        XCTAssertTrue(CompositionAIExample.sheetNote.contains("AI"))
        XCTAssertEqual(CompositionAIExample.badge, "AI")
        XCTAssertTrue(CompositionAIExample.accessibilitySuffix(hasExample: true).contains(CompositionAIExample.label))
        XCTAssertEqual(CompositionAIExample.accessibilitySuffix(hasExample: false), "")
    }

    /// 作例を出す画面が、AI の表記を必ず添えている（作例の絵を出す所と表記が同じファイルにある）
    func testScreensShowingExamplesCarryAIDisclosure() throws {
        let files = ["Sources/JourneyPhoto/Features/Spots/CompositionOverlay.swift": "CompositionAIExample.badge",
                     "Sources/JourneyPhoto/Features/Spots/CompositionPicker.swift": "CompositionAIExample.sheetNote",
                     "Sources/JourneyPhoto/Features/Settings/CompositionCatalogView.swift": "CompositionAIExample.label"]
        for (path, disclosure) in files {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains(disclosure), "\(path) に AI の表記（\(disclosure)）が無い")
        }
        // 作例の絵を名前で引く所は、上の3つのファイルだけ
        let sources = root.appendingPathComponent("Sources/JourneyPhoto")
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("CompositionAIExample.assetName") else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            XCTAssertNotNil(files[relative], "\(relative) が作例の絵を出しているが、AI の表記の見張りに入っていない")
        }
    }

    /// 生成の道具はキーを環境変数から読み、見出しに載せるだけ
    func testGeneratorReadsKeyFromEnvironmentOnly() throws {
        let source = try String(contentsOf: root.appendingPathComponent("Tools/composition-examples/generate.mjs"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("process.env.GEMINI_API_KEY"))
        XCTAssertTrue(source.contains("\"x-goog-api-key\": key"))
        XCTAssertFalse(source.contains("${key}"), "キーを文字列に埋め込んでいる")
        // 伏せてから出す所（redact(…, key)）を除いて、表示にキーを渡していない
        let shown = source.replacingOccurrences(of: #"redact\([^)]*\)"#, with: "", options: .regularExpression)
        XCTAssertNil(shown.range(of: #"console\.\w+\([^)]*(?<![-\w])key\b"#, options: .regularExpression), "キーを表示している")
    }
}
