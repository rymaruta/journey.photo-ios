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

    /// 🔴 **一部だけ上がった回は、上がった分を選択から外す。** 外さないと、
    /// 失敗の1枚を × で外した／「追加」を開いて閉じた瞬間の選び直しで、
    /// 上がった写真が「足した分」として読み直され、二重に投稿される
    func testPostedPhotosAreNotReloadedAfterPartialFailure() {
        // a・b・c を選び、a と c は上がって b だけ失敗した
        let picked = ["a", "b", "c"]
        let remainingQueue: [String?] = ["b"]
        let selection = PickerReconcile.dropping(posted: ["a", "c"], from: picked)
        XCTAssertEqual(selection, ["b"])

        // × で b を外す（`remove` は選択から b を落とす）→ 選び直しが走る
        let afterRemove = selection.filter { $0 != "b" }
        let r1 = PickerReconcile.reconcile(existing: [String?](), picked: afterRemove)
        XCTAssertEqual(r1.added, [], "上がった写真をもう一度読んでいる（二重投稿）")

        // 「追加」を開いて何も変えずに閉じる → 同じ選択で選び直しが走る
        let r2 = PickerReconcile.reconcile(existing: remainingQueue, picked: selection)
        XCTAssertEqual(r2.keep, [true])
        XCTAssertEqual(r2.added, [], "上がった写真をもう一度読んでいる（二重投稿）")
    }

    /// 上がった分が無ければ選択はそのまま（カメラの分は印を持たない）
    func testNothingPostedKeepsSelection() {
        XCTAssertEqual(PickerReconcile.dropping(posted: [String](), from: ["a", "b"]), ["a", "b"])
    }
}
