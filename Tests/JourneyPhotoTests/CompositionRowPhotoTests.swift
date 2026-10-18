import XCTest
@testable import JourneyPhoto

/// 2026-10-17 owner「構図一覧の参考写真も右に写したい」: 構図のシート（撮る画面）と構図一覧（設定）の行の右に、
/// 詳細画面と同じ作例写真を出す。画面ごとに見た目を割らない（CLAUDE.md）ので、両方の行が同じ部品を使う。
final class CompositionRowPhotoTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 行の写真は詳細画面と同じ入れ物を読み、全37種類にその入れ物がある
    func testRowPhotoUsesTheSameExampleAssetForEveryKind() throws {
        let assets = root.appendingPathComponent("Sources/JourneyPhoto/Assets.xcassets")
        for kind in CompositionKind.allCases {
            let name = CompositionExampleThumbs.assetName(for: kind)
            XCTAssertEqual(name, "composition-ai-\(kind.rawValue)")
            let file = assets.appendingPathComponent("\(name).imageset/\(name).jpg")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "\(kind) の行に出す作例が無い")
        }
    }

    /// 構図のシートと構図一覧の両方の行に作例写真を置いている（片方だけにしない）
    func testBothRowsShowTheExamplePhoto() throws {
        let picker = try source("Sources/JourneyPhoto/Features/Spots/CompositionPicker.swift")
        let catalog = try source("Sources/JourneyPhoto/Features/Settings/CompositionCatalogView.swift")
        XCTAssertTrue(picker.contains("CompositionExampleThumb(kind: kind)"), "構図のシートの札に作例写真が無い")
        XCTAssertTrue(catalog.contains("CompositionExampleThumb(kind: kind)"), "構図一覧の行に作例写真が無い")
    }

    /// 行の写真は作例と同じ縦3:4。札は写真が収まる高さにする
    func testRowPhotoIsThreeByFourAndFitsTheCard() {
        let size = CompositionExampleThumb.size
        XCTAssertEqual(Double(size.width / size.height), 0.75, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(CompositionPicker.rowHeight, size.height)
    }

    /// 構図一覧の説明文は「実際の写真ではありません」と言い切らない（右に作例写真が出るので）
    func testCatalogIntroNoLongerSaysThereAreNoPhotos() throws {
        let catalog = try source("Sources/JourneyPhoto/Features/Settings/CompositionCatalogView.swift")
        XCTAssertFalse(catalog.contains("図はガイド線の例で、実際の写真ではありません。"))
    }
}
