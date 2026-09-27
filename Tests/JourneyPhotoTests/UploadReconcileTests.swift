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

    /// 🔴 **投稿済みの写真は選択から外す。** 残すと、残った1枚を外したときや
    /// 「追加」で選び足したときの差分が、投稿済みの写真を新しく選ばれた分と読み、
    /// 同じ写真をもう一度上げていた
    func testPostedItemsLeaveTheSelection() {
        let picked = PickerReconcile.dropPosted(picked: ["a", "b"], posted: ["a", nil])
        XCTAssertEqual(picked, ["b"])
        // 「追加」で c を選び足しても、a は新しく選ばれた分に入らない
        let r = PickerReconcile.reconcile(existing: ["b"], picked: picked + ["c"])
        XCTAssertEqual(r.added, ["c"])
    }

    /// 読めなかった写真だけなら読まない（写真を外したとき・投稿の後始末）
    func testUnreadableAloneIsNotReloaded() {
        let plan = PickerReconcile.toLoad(added: ["c"], picked: ["b", "c"], unreadable: ["c"])
        XCTAssertEqual(plan.load, [])
        XCTAssertEqual(plan.unreadable, ["c"])
    }

    /// 選び足したときは、読めなかった分も一緒に読み直す
    func testAddingRetriesUnreadable() {
        let plan = PickerReconcile.toLoad(added: ["c", "d"], picked: ["c", "d"], unreadable: ["c"])
        XCTAssertEqual(plan.load, ["c", "d"])
        XCTAssertEqual(plan.unreadable, [], "読んでいる分は控えから外す")
    }

    /// 🔴 **途中で取り消された回の写真は、次の回で読む。** d が読めた後、c を待つ間に
    /// 取り消されると、次の回の差分は c だけ。控えに c が残っていると「新しい写真なし」で
    /// 帰り、知らせも無いまま c が落ちていた
    func testRoundCancelledMidwayRereadsNextTime() {
        let first = PickerReconcile.toLoad(added: ["c", "d"], picked: ["c", "d"], unreadable: ["c"])
        // 取り消された回は失敗を戻さない
        let next = PickerReconcile.toLoad(added: ["c"], picked: ["c", "d"], unreadable: first.unreadable)
        XCTAssertEqual(next.load, ["c"])
    }

    /// ライブラリで外した写真は控えから忘れる
    func testDeselectedLeavesUnreadable() {
        let plan = PickerReconcile.toLoad(added: [String](), picked: ["b"], unreadable: ["c"])
        XCTAssertEqual(plan.unreadable, [])
    }
}
