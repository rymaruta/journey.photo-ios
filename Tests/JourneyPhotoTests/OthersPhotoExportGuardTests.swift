import XCTest
@testable import JourneyPhoto

/// **人の写真の画像を手にできる道を増やさない**（2026-11-12 owner・#577・CLAUDE.md「他人の写真は、その人のもの」）。
///
/// 画像を端末に保存する・画像のファイルを外のアプリへ渡す・ドラッグで外へ出す口は、下の一覧のファイルにだけある
/// （どれも自分の写真・自分で撮った写真・自分の旅だけ）。新しい口を足すときは、人の写真で出ないことを確かめてから
/// この一覧に理由と一緒に足す。リンク（ページの URL）の共有・DM で写真を送るのはこの試験の外（持ち主の写真へ連れて行くだけ）
final class OthersPhotoExportGuardTests: XCTestCase {

    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
    }

    /// 画像を外へ出す API（保存・画像の共有シート・ドラッグ・画像のコピー・画像ファイルの共有）
    private static let exportPatterns = [
        "UIImageWriteToSavedPhotosAlbum", "PHAssetCreationRequest", "PHAssetChangeRequest",
        "ShareSheet(images:", "UIActivityViewController(", ".draggable(", ".onDrag", "UIDragInteraction",
        "UIPasteboard.general.image", "UIPasteboard.general.setData", "ShareLink(item: cardURL",
    ]

    /// 使ってよいファイルと理由
    private static let allowed: [String: String] = [
        "Features/Common/ShareSheet.swift": "共有シートの部品そのもの",
        "Features/Common/SignatureShareCardSheet.swift": "共有カード。開くのは自分の公開写真だけ（`PhotoDetailRules.showsSocialCard`）",
        "Features/Upload/UploadView.swift": "投稿した自分の写真を SNS へ",
        "Features/Upload/CameraPicker.swift": "自分で撮った写真を端末に残す",
        "Features/Spots/ComposeCamera.swift": "自分で撮った写真を端末に残す",
        "Features/Trips/TripBookView.swift": "自分の旅の一冊だけ（`TripBook.canShare(isMine:)`）",
        // 1.1.84 のまとめ（旅をストーリーに・第9章）: 開くのは写真の詳細の「SNS に載せる」（`SocialShareSheet`・
        // `PhotoDetailRules.showsSocialCard` で自分の公開写真だけ）と、自分の旅の一冊（`TripBook.canShare(isMine:)`）だけ
        "Features/Common/TravelStorySheet.swift": "旅をストーリーにの絵。自分の写真と自分の旅だけから開く",
        "Features/Trips/TripPlanDetailView.swift": "旅行プランの行の並べ替え（画像ではない）",
    ]

    func testImageExportOnlyInAllowedFiles() throws {
        var found: Set<String> = []
        let files = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if Self.exportPatterns.contains(where: text.contains) {
                found.insert(String(url.path.dropFirst(sourcesRoot.path.count + 1)))
            }
        }
        XCTAssertEqual(found.subtracting(Self.allowed.keys).sorted(), [],
                       "画像を外へ出す口が増えた。人の写真で出ないことを確かめてから一覧に足す（#577）")
        XCTAssertFalse(found.isEmpty, "Sources を読めていない")
    }

    /// 写真の詳細の「SNS に載せる」（共有カード）と「ストーリーに載せる」は、持ち主かを確かめてから作る
    func testPhotoDetailChecksOwnerBeforeMakingImages() throws {
        let text = try String(contentsOf: sourcesRoot.appendingPathComponent(
            "Features/PhotoDetail/PhotoDetailView.swift"), encoding: .utf8)
        func body(of name: String) -> Substring? {
            guard let start = text.range(of: "private func \(name)() async {") else { return nil }
            return text[start.upperBound...].prefix(900)
        }
        XCTAssertTrue(body(of: "prepareThreads")?.contains("PhotoDetailRules.showsSocialCard(") == true,
                      "共有カードの画像を、持ち主かを確かめずに作っている")
        XCTAssertTrue(body(of: "prepareStory")?.contains("SendSheetLayout.canShareToStory(") == true,
                      "ストーリーの絵を、持ち主かを確かめずに作っている")
    }
}
