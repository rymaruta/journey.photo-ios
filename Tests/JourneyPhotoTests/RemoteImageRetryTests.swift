import XCTest
@testable import JourneyPhoto

/// 読めなかった写真の読み直し（`RemoteImageRetry`）。
///
/// **通信を増やしすぎない。** 一覧で圏外になると全部のマスが一斉に失敗する——自動は1回だけ、
/// その先は押したときだけ、押せる回数にも上限がある
final class RemoteImageRetryTests: XCTestCase {

    func testFirstFailureRetriesAutomaticallyOnceAfterAShortWait() {
        guard case .retryAutomatically(let seconds) = RemoteImageRetry.step(automaticDone: 0, manualDone: 0) else {
            return XCTFail("最初の失敗は自動で読み直す")
        }
        XCTAssertGreaterThan(seconds, 0, "すぐには叩かない（少し待つ）")
        XCTAssertLessThanOrEqual(seconds, 3, "待たせすぎない")
    }

    func testAfterTheAutomaticRetryItWaitsForATap() {
        XCTAssertEqual(RemoteImageRetry.step(automaticDone: 1, manualDone: 0, allowsManualRetry: true), .offerTap,
                       "自動は1回だけ。2回目の失敗は押して読み直す")
        XCTAssertEqual(RemoteImageRetry.step(automaticDone: 1, manualDone: 2, allowsManualRetry: true), .offerTap)
    }

    /// 押して読み直したあとの失敗で、**自動の読み直しが戻ってこない**
    func testManualRetryDoesNotRestartAutomaticRetries() {
        for manual in 0...5 {
            if case .retryAutomatically = RemoteImageRetry.step(automaticDone: 1, manualDone: manual, allowsManualRetry: true) {
                XCTFail("押したあとに自動で読み直している（manual=\(manual)）")
            }
        }
    }

    /// 🔴 **既定では押して読み直す記号を出さない**（ストーリーの左右送り・一覧の NavigationLink を奪う）
    func testManualRetryIsOffByDefault() {
        XCTAssertEqual(RemoteImageRetry.step(automaticDone: 1, manualDone: 0), .giveUp,
                       "既定は自動の1回だけ")
        XCTAssertEqual(RemoteImageRetry.step(automaticDone: 1, manualDone: 0, allowsManualRetry: false), .giveUp)
    }

    /// 押して読み直せるのは、周りに押す操作の無い所だけ（今は写真の編集の1枚）。
    /// ストーリー・一覧（NavigationLink の中）・旅の本では出さない
    func testOnlyCallersWithoutSurroundingTapsAllowManualRetry() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var allowing: [String] = []
        for file in files where file.lastPathComponent != "RemoteImage.swift" {
            if try String(contentsOf: file, encoding: .utf8).contains("allowsManualRetry: true") {
                allowing.append(file.lastPathComponent)
            }
        }
        XCTAssertEqual(allowing.sorted(), ["EditPhotoView.swift"])
    }

    func testGivesUpAfterTheManualLimit() {
        XCTAssertEqual(RemoteImageRetry.step(automaticDone: 1, manualDone: RemoteImageRetry.manualLimit, allowsManualRetry: true), .giveUp)
    }

    /// 失敗し続ける写真を、押し続けたときに**何回読みに行くか**。上限で止まる
    func testTotalLoadsPerImageAreBounded() {
        var automatic = 0, manual = 0, loads = 1
        loop: while true {
            switch RemoteImageRetry.step(automaticDone: automatic, manualDone: manual, allowsManualRetry: true) {
            case .retryAutomatically: automatic += 1; loads += 1
            case .offerTap: manual += 1; loads += 1
            case .giveUp: break loop
            }
            if loads > 100 { return XCTFail("止まらない") }
        }
        XCTAssertEqual(automatic, 1, "自動は1回だけ")
        XCTAssertEqual(loads, RemoteImageRetry.maxLoads)
        XCTAssertLessThanOrEqual(loads, 5, "1枚につき最初＋自動1＋押して3 まで")
    }

    /// 🔴 **読み直しは `AsyncImage` を作り直して起こす**（`.id(attempt)`）。画面は Linux で
    /// 描けないので配線だけ文で見る——外すと、数だけ増えて読み直さない
    func testRemoteImageIsWiredToReload() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Common/RemoteImage.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains(".id(attempt)"))
        XCTAssertTrue(source.contains("allowsManualRetry: allowsManualRetry)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(L(\"画像を読み込めませんでした。読み直す\""),
                      "読み直しのボタンに読み上げのラベル")
    }
}
