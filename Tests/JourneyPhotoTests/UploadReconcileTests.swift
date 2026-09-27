import XCTest
@testable import JourneyPhoto

/// 新規投稿の「追加」（ライブラリの選び直し）の差分（`PickerReconcile.reconcile`）。
final class UploadReconcileTests: XCTestCase {

    /// 🔴 **前に選んだ分は読み直さずに残す。** 丸ごと入れ替えていた頃は、
    /// 「追加」を押すと打った題・説明・撮影地まで消えていた
    func testKeepsPreviousAndLoadsOnlyAdded() {
        let r = PickerReconcile.reconcile(existing: ["a", "b"], picked: ["a", "b", "c"])
        XCTAssertEqual(r.keep, [true, true])
        XCTAssertEqual(r.added, ["c"])
    }

    /// ライブラリで外した分だけ落とす
    func testDropsDeselected() {
        let r = PickerReconcile.reconcile(existing: ["a", "b"], picked: ["b"])
        XCTAssertEqual(r.keep, [false, true])
        XCTAssertEqual(r.added, [])
    }

    /// カメラで撮った分（印なし）は選び直しで消さない
    func testCameraShotsSurvive() {
        let r = PickerReconcile.reconcile(existing: [nil, "a"], picked: ["b"])
        XCTAssertEqual(r.keep, [true, false])
        XCTAssertEqual(r.added, ["b"])
    }

    /// 同じ印が2度来ても1枚だけ読む
    func testDuplicatesInPickedLoadOnce() {
        let r = PickerReconcile.reconcile(existing: [String?](), picked: ["a", "a"])
        XCTAssertEqual(r.added, ["a"])
    }
}
