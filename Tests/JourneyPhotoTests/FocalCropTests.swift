import XCTest
@testable import JourneyPhoto

/// 切り抜きの**境目**。
///
/// 方向そのものは `CollectionFilterTests` の `FocalCropTests` が見ている。
/// ここが見るのは3等分の線（0.34 と 0.67）で、`..<` と `...` を取り違えても
/// 中身のある写真では気づきにくい——ずれるのは真ん中に近い1枚だけなので、
/// 「なんとなく違う」で終わってしまう。
final class FocalCropBoundaryTests: XCTestCase {

    func testHorizontalBoundaries() {
        XCTAssertEqual(FocalCrop.bucket(x: 0.339, y: 0.5), .leading, "0.34 の手前は端に寄る")
        XCTAssertEqual(FocalCrop.bucket(x: 0.34, y: 0.5), .center, "0.34 ちょうどは中央")
        XCTAssertEqual(FocalCrop.bucket(x: 0.669, y: 0.5), .center, "0.67 の手前は中央")
        XCTAssertEqual(FocalCrop.bucket(x: 0.67, y: 0.5), .trailing, "0.67 ちょうどは端")
    }

    func testVerticalBoundaries() {
        XCTAssertEqual(FocalCrop.bucket(x: 0.5, y: 0.339), .top)
        XCTAssertEqual(FocalCrop.bucket(x: 0.5, y: 0.34), .center)
        XCTAssertEqual(FocalCrop.bucket(x: 0.5, y: 0.669), .center)
        XCTAssertEqual(FocalCrop.bucket(x: 0.5, y: 0.67), .bottom)
    }
}

/// 規約への同意。**審査要件（1.2 / UGC）** で、使う前に同意させる必要がある。
@MainActor
final class LegalConsentTests: XCTestCase {

    private func consent() -> LegalConsent {
        LegalConsent(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testAsksBeforeAnythingIsAccepted() async {
        XCTAssertTrue(consent().needsConsent, "同意を取らずに使わせている")
    }

    func testDoesNotAskAgainAfterAccepting() async {
        let c = consent()
        c.accept()
        XCTAssertFalse(c.needsConsent)
        XCTAssertEqual(c.acceptedVersion, LegalConsent.currentVersion)
    }

    /// **規約を変えたら、もう一度出す。**
    func testOlderAcceptanceStillNeedsConsent() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(LegalConsent.currentVersion - 1, forKey: "legal.consent.version")
        XCTAssertTrue(LegalConsent(defaults: defaults).needsConsent,
                      "古い版に同意しただけで通している")
    }
}
