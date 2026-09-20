import XCTest
@testable import JourneyPhoto

/// 題が無い写真の扱い。Web 側 2026-09-20 の変更と揃える。
///
/// **「無題」は表示の落とし先ではなく、サーバーが実際に保存していた文字列**
/// だった。保存はやめたが、既に上がっている写真には残るので出す側でも落とす。
final class PhotoTitleTests: XCTestCase {

    func testDropsServerPlaceholders() {
        XCTAssertEqual(PhotoTitle.display("無題"), "")
        XCTAssertEqual(PhotoTitle.display("Untitled"), "")
    }

    /// **前後の空白を落としてから見る。** サーバーが入れた値に空白が付いて
    /// いる回がある。
    func testTrimsBeforeComparing() {
        XCTAssertEqual(PhotoTitle.display("  無題 "), "")
    }

    /// **丸ごとその言葉のときだけ落とす。**
    /// 「無題の風景」は人が書いた題なので残す（前方一致にしない）。
    func testKeepsTitlesThatMerelyContainThePlaceholder() {
        XCTAssertEqual(PhotoTitle.display("無題の風景"), "無題の風景")
        XCTAssertEqual(PhotoTitle.display("Untitled #3"), "Untitled #3")
    }

    func testKeepsOrdinaryTitles() {
        XCTAssertEqual(PhotoTitle.display("高屋神社の雲海"), "高屋神社の雲海")
        XCTAssertEqual(PhotoTitle.display(nil), "")
    }

    /// 写真から読むときも通っていること（通し忘れがいちばん起きる）。
    func testPhotoDisplayTitleGoesThroughTheFilter() throws {
        let photo = try JSONDecoder.api.decode(
            Photo.self,
            from: Data(#"{"id":"a","src":"https://x/a.jpg","title":{"ja":"無題","en":"Untitled"}}"#.utf8)
        )
        XCTAssertEqual(photo.displayTitle, "")
    }

    /// 読み上げの代替文も「無題」と言わない。題が無ければ撮影地で補う。
    func testAccessibilityTextFallsBackToLocation() throws {
        let photo = try JSONDecoder.api.decode(
            Photo.self,
            from: Data(#"{"id":"a","src":"https://x/a.jpg","title":"無題","location":"高屋神社"}"#.utf8)
        )
        XCTAssertEqual(photo.accessibilityText, "高屋神社 の写真")
    }
}
