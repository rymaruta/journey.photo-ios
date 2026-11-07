import XCTest
@testable import JourneyPhoto

/// 時間切れつきの待ち(`FirstResult`・すれちがいの地名引き)。クラスは MainActor ではない。
final class FirstResultTests: XCTestCase {

    /// 仕事が返らない(背面で止められた地名引き)ときは、時間切れで fallback を返す。
    /// 時間切れを外して work を待つ作りに戻すと、ここは3秒かかって "late" が返り落ちる
    func testFallbackWinsWhenTheWorkDoesNotReturnInTime() async {
        let result: String? = await FirstResult.run(timeout: 0, fallback: nil, pause: { _ in }) {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            return "late"
        }
        XCTAssertNil(result, "時間切れでも地名を待っている")
    }

    /// 仕事が先に返れば、その答え(時間切れの fallback で上書きしない)
    func testWorkWinsWhenItReturnsFirst() async {
        let result: String? = await FirstResult.run(timeout: 60, fallback: nil, pause: { _ in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }) { "京都市" }
        XCTAssertEqual(result, "京都市")
    }

    /// 受け取りの配線: 時間切れつきで引き、待った後で人が替わっていたら綴じない(読んで確かめる)
    func testReceiveUsesTimeoutAndChecksTheOwner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Services/PassRadio.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("FirstResult.run(timeout: Self.placeLookupTimeout"))
        XCTAssertTrue(source.contains("guard store.userId == owner else { return }"))
        XCTAssertGreaterThan(PassCoordinator.placeLookupTimeout, 0)
        XCTAssertLessThanOrEqual(PassCoordinator.placeLookupTimeout, 10)
    }
}
