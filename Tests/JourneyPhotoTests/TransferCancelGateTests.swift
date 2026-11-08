import XCTest
@testable import JourneyPhoto

/// 転送の取り消しの順序(`TransferCancelGate`・2026-11-07)。クラスは MainActor ではない・同期でよい。
/// 作る前に取り消された回は、待つ人を書く前に完了通知が来て、待ち手が永久に待っていた。
/// 取り消しは、待つ人を書いた後(`arm()` の後)にだけ走る。
final class TransferCancelGateTests: XCTestCase {

    /// 🔴 `arm()` より前の取り消しの要求は、その場では走らない(待つ人を書く前に完了通知を起こさない)。
    /// `requestCancel` が直に `cancel` を呼ぶ作りに戻すと、ここで走って落ちる
    func testCancelBeforeArmDoesNotRunUntilArmed() {
        let gate = TransferCancelGate()
        var ran = 0
        gate.requestCancel { ran += 1 }
        XCTAssertEqual(ran, 0, "待つ人を書く前に取り消した")
        XCTAssertTrue(gate.arm(), "先に取り消されていたことが伝わらない(呼び手が取り消せない)")
    }

    /// `arm()` の後の要求は、その場で1回走る
    func testCancelAfterArmRunsOnce() {
        let gate = TransferCancelGate()
        XCTAssertFalse(gate.arm())
        var ran = 0
        gate.requestCancel { ran += 1 }
        XCTAssertEqual(ran, 1)
    }

    /// 取り消しの要求が無ければ、`arm()` は false(取り消さない)
    func testNoCancelMeansNoCancelAtArm() {
        let gate = TransferCancelGate()
        XCTAssertFalse(gate.arm())
    }
}
