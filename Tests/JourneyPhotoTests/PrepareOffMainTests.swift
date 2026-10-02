import XCTest

/// 🔴 **画像を整える（`ImagePreparer.prepare`）のは画面の処理の外で。**
///
/// 縮小・JPEG への焼き直し・読み直しての確認・代表色で、1枚に数百ミリ秒かかる。
/// プロフィールのアイコン・カバー（`ProfileEditView`）とストーリー（`StoryComposerView`）は
/// 画面の処理の上で呼んでいて、選ぶたびに画面が止まっていた。
///
/// 画面のコードは Linux では走らせられないので、**呼び出しの形**を見る:
/// 呼ぶ行のすぐ上（3行以内）に `Task.detached` があること。例外は投稿のモデルの
/// 差し替え口（`prepareData`・呼ぶのは `Task.detached` の中）だけ
final class PrepareOffMainTests: XCTestCase {

    func testEveryPrepareCallRunsInADetachedTask() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/JourneyPhoto")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "ImagePreparer.swift" }
        var calls = 0
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("ImagePreparer.prepare(data:") {
                // 注記の中の言及は数えない
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                calls += 1
                let above = lines[max(0, index - 3)..<index].joined(separator: "\n")
                XCTAssertTrue(above.contains("Task.detached") || above.contains("var prepareData"),
                              "\(file.lastPathComponent):\(index + 1) が画面の処理の上で画像を整えている")
            }
        }
        XCTAssertGreaterThanOrEqual(calls, 4, "呼び出しを見つけられていない（探し方が古い）")
    }
}
