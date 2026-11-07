import XCTest
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif
@testable import JourneyPhoto

#if canImport(SceneKit) || canImport(SceneKitShim)

/// 部屋の最初のコマの見張り（`CamperFirstFrame`）。2026-11-07: `onDrawn` が見張り自身を強く掴んで
/// 循環し、部屋の画面を外しても解放されなかった。解放されること・最初のコマの知らせが来ることの両方を見る
final class CamperFirstFrameTests: XCTestCase {

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var _renders = 0
        private var _drawn = 0
        var renders: Int { lock.lock(); defer { lock.unlock() }; return _renders }
        var drawn: Int { lock.lock(); defer { lock.unlock() }; return _drawn }
        func render() { lock.lock(); _renders += 1; lock.unlock() }
        func done() { lock.lock(); _drawn += 1; lock.unlock() }
    }

    /// 主キューの仕事が一巡するまで待つ
    private func drainMain() {
        let exp = expectation(description: "main")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 2)
    }

    /// 🔴 配線しても見張りは解放される(`connect` の中で `self` を強く掴むと残って落ちる)
    func testWatcherIsReleasedAfterConnecting() {
        weak var weakWatcher: CamperFirstFrame?
        autoreleasepool {
            let watcher = CamperFirstFrame()
            weakWatcher = watcher
            watcher.connect(isShowing: { true }, requestRender: {}, onDrawn: {})
            watcher.arm()
        }
        XCTAssertNil(weakWatcher, "見張りが onDrawn と循環して解放されない")
    }

    /// 🔴 解放されても最初のコマの知らせは来る(持ち主が見張りを持っている間は、組み上がり後の2コマで知らせる)
    func testFirstFrameIsReportedAfterTwoShownFrames() {
        let watcher = CamperFirstFrame()
        let box = Box()
        watcher.connect(isShowing: { true }, requestRender: { box.render() }, onDrawn: { box.done() })
        watcher.arm()
        watcher.fireIfArmed()
        drainMain()
        XCTAssertEqual(box.drawn, 0, "1コマ目で知らせた")
        XCTAssertEqual(box.renders, 1, "次のコマを描かせていない")
        watcher.fireIfArmed()   // 1コマ目で見張りを張り直してある
        drainMain()
        XCTAssertEqual(box.drawn, 1, "最初のコマが知らされない")
    }

    /// 部屋がまだ画面に載っていないコマは数えない(張り直して待つ)
    func testFramesBeforeTheRoomIsShownAreNotCounted() {
        let watcher = CamperFirstFrame()
        let box = Box()
        watcher.connect(isShowing: { false }, requestRender: { box.render() }, onDrawn: { box.done() })
        for _ in 0..<3 {
            watcher.arm()
            watcher.fireIfArmed()
            drainMain()
        }
        XCTAssertEqual(box.drawn, 0)
        XCTAssertEqual(box.renders, 3)
    }

    /// 切った(`dismantleUIView`)あとは知らせない
    func testDisconnectStopsReporting() {
        let watcher = CamperFirstFrame()
        let box = Box()
        watcher.connect(framesNeeded: 1, isShowing: { true }, requestRender: {}, onDrawn: { box.done() })
        watcher.disconnect()
        watcher.arm()
        watcher.fireIfArmed()
        drainMain()
        XCTAssertEqual(box.drawn, 0)
    }
}

#endif
