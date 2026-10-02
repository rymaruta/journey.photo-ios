import XCTest
@testable import JourneyPhoto

/// 写真の編集シートの見本（`EditPreview`）。
final class EditPreviewTests: XCTestCase {

    /// 🔴 **差し替えた後は、送った画像を見本に出す。** 開いたときの URL（前の写真）のままだと、
    /// 差し替えたのか分からない
    func testReplacedImageWinsOverTheOpenedURL() {
        let old = URL(string: "https://x/old.jpg")
        switch EditPreview.source(replaced: "送った画像", original: old) {
        case .replaced(let local):
            XCTAssertEqual(local, "送った画像")
        case .original:
            XCTFail("差し替えた後も、開いたときの写真（前の写真）を見本に出している")
        }
    }

    /// 差し替えていなければ開いたときの写真
    func testOpenedURLBeforeReplacing() {
        let old = URL(string: "https://x/old.jpg")
        switch EditPreview.source(replaced: String?.none, original: old) {
        case .replaced:
            XCTFail("差し替えていないのに差し替えた画像を出している")
        case .original(let url):
            XCTAssertEqual(url, old)
        }
    }
}
