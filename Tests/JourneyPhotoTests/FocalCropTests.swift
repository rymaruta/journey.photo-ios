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
    ///
    /// `currentVersion` が 1 のあいだ「古い版」は 0（＝既定値）としか
    /// 書けず、それだと `<` を `== 0` に変えても落ちない
    /// ——**何も検証していないテスト**になる（実際そう書いた）。
    /// 求める版を差し替えて、比較そのものを見る。
    func testOlderAcceptanceStillNeedsConsent() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(1, forKey: "legal.consent.version")   // 版1には同意済み

        XCTAssertFalse(LegalConsent(defaults: defaults, requiredVersion: 1).needsConsent,
                       "同じ版なのにもう一度聞いている")
        XCTAssertTrue(LegalConsent(defaults: defaults, requiredVersion: 2).needsConsent,
                      "版を上げたのに聞き直していない")
    }

    /// **先の版に同意している端末を、巻き戻して聞き直さない**
    /// （版を下げる操作は無いが、`<` を `!=` と書き間違えると起きる）。
    func testNewerAcceptanceDoesNotAskAgain() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(5, forKey: "legal.consent.version")
        XCTAssertFalse(LegalConsent(defaults: defaults, requiredVersion: 2).needsConsent)
    }
}
