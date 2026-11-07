import XCTest
import UIKit
#if canImport(SceneKit)
import SceneKit
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif
@testable import JourneyPhoto

#if canImport(SceneKit) || canImport(SceneKitShim)

/// 外観の毎秒の枚数（2026-11-06・札 #430）。夜の炎が揺れている間、操作が止まっていれば 60 → 30 に下げる。
/// 数の根拠は `CamperFrameRate` の注記（Mac run 42257294870: 夜の止まっている間 毎秒 61.9 コマ・CPU 28.9%）
@MainActor
final class CamperFrameRateTests: XCTestCase {

    func testPolicy() async {
        XCTAssertEqual(CamperFrameRate.active, 60)
        XCTAssertEqual(CamperFrameRate.idle, 30)
        // 操作の直後は 60。揺れていなければ、止まっていても 60（描き続けないので下げる必要が無い）
        XCTAssertEqual(CamperFrameRate.target(flickering: true, idleFor: 0), 60)
        XCTAssertEqual(CamperFrameRate.target(flickering: true, idleFor: CamperFrameRate.idleDelay - 0.01), 60)
        XCTAssertEqual(CamperFrameRate.target(flickering: false, idleFor: 60), 60)
        // 止まって、炎が揺れているときだけ 30
        XCTAssertEqual(CamperFrameRate.target(flickering: true, idleFor: CamperFrameRate.idleDelay), 30)
        XCTAssertEqual(CamperFrameRate.target(flickering: true, idleFor: 60), 30)
        // 待つ秒を変えた場面（試験）では、その秒を基準にする（固定の2秒と比べない）
        XCTAssertEqual(CamperFrameRate.target(flickering: true, idleFor: 0.05, after: 0.05), 30)
        XCTAssertEqual(CamperFrameRate.target(flickering: true, idleFor: 0.04, after: 0.05), 60)
        XCTAssertEqual(CamperFrameRate.target(flickering: false, idleFor: 0.05, after: 0.05), 60)
    }

    /// 炎が揺れるほど（炎のランタンを置いた）夜の場面
    private func nightScene() -> CamperScene {
        let scene = CamperScene()
        var l = CamperLoadout.standard
        l.picks[CamperCategory.outdoorLight.rawValue] = "brass_lantern"
        scene.installNow(CamperConfig(stage: .camper, mood: .night, loadout: l))
        return scene
    }

    private func wait(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testNightIdleDropsTo30AndActivityRestores60() async {
        let scene = nightScene()
        XCTAssertTrue(scene.isFlickering)
        scene.idleDelay = 0.05
        let view = SCNView(frame: .zero)
        scene.noteActivity(view)
        // 操作の瞬間は 60（切り替えの瞬間には触らない）
        XCTAssertEqual(view.preferredFramesPerSecond, 60)
        await wait(0.3)
        XCTAssertEqual(view.preferredFramesPerSecond, 30, "止まって夜の炎が揺れていれば下げる")
        // 次の操作ですぐ 60 に戻る
        scene.noteActivity(view)
        XCTAssertEqual(view.preferredFramesPerSecond, 60)
    }

    func testActivityBeforeDelayKeeps60() async {
        let scene = nightScene()
        scene.idleDelay = 0.2
        let view = SCNView(frame: .zero)
        scene.noteActivity(view)
        await wait(0.1)
        scene.noteActivity(view)       // 下げる前にまた操作 → 待ち直し
        await wait(0.12)
        XCTAssertEqual(view.preferredFramesPerSecond, 60, "最後の操作からまだ idleDelay たっていない")
        await wait(0.3)
        XCTAssertEqual(view.preferredFramesPerSecond, 30)
    }

    func testDayStaysAt60() async {
        let scene = CamperScene()
        scene.installNow(CamperConfig(stage: .camper, mood: .day))
        XCTAssertFalse(scene.isFlickering)
        scene.idleDelay = 0.05
        let view = SCNView(frame: .zero)
        scene.noteActivity(view)
        await wait(0.3)
        XCTAssertEqual(view.preferredFramesPerSecond, 60, "昼は止まっている間は描かないので、下げる理由が無い")
    }

    func testNightWithReducedMotionStaysAt60() async {
        let scene = nightScene()
        scene.setFlicker(allowed: false)
        XCTAssertFalse(scene.isFlickering)
        scene.idleDelay = 0.05
        let view = SCNView(frame: .zero)
        scene.noteActivity(view)
        await wait(0.3)
        XCTAssertEqual(view.preferredFramesPerSecond, 60)
    }

    /// 夜から昼に替わったあとに、前の予約で下げない（昼は 60 のまま）
    func testSwitchingToDayCancelsPendingDrop() async {
        let scene = nightScene()
        scene.idleDelay = 0.1
        let view = SCNView(frame: .zero)
        scene.noteActivity(view)
        var day = scene.config ?? CamperConfig(stage: .camper, mood: .day)
        day.mood = .day
        scene.show(day)
        scene.noteActivity(view)       // 画面の更新（updateUIView）が来る
        await wait(0.4)
        XCTAssertFalse(scene.isFlickering)
        XCTAssertEqual(view.preferredFramesPerSecond, 60)
    }

    // MARK: 低電力モード・熱でも止める(2026-11-07)

    /// 条件は「視差効果を減らす」・低電力モード・熱(serious 以上)のどれか1つでも当たれば止める。
    /// 通常時(どれも無し)は揺らす。`allowed` が `!reduceMotion` だけに戻ると落ちる
    func testFlickerPolicy() {
        XCTAssertTrue(CamperFlicker.allowed(reduceMotion: false, lowPower: false, thermalSerious: false), "通常時に止めた")
        XCTAssertFalse(CamperFlicker.allowed(reduceMotion: true, lowPower: false, thermalSerious: false))
        XCTAssertFalse(CamperFlicker.allowed(reduceMotion: false, lowPower: true, thermalSerious: false), "低電力モードで止まらない")
        XCTAssertFalse(CamperFlicker.allowed(reduceMotion: false, lowPower: false, thermalSerious: true), "熱で止まらない")
        XCTAssertFalse(CamperFlicker.allowed(reduceMotion: true, lowPower: true, thermalSerious: true))
    }

    /// 低電力モードで止まり、戻れば揺れ直す。止まっている間は描き続けない(30 に下げる必要も無く 60 のまま)
    func testLowPowerStopsAndResumesFlicker() async {
        let scene = nightScene()
        XCTAssertTrue(scene.isFlickering)
        scene.setPowerState(lowPower: true, thermalSerious: false)
        XCTAssertFalse(scene.isFlickering, "低電力モードでも揺れている")
        XCTAssertFalse(scene.flickerAllowed)
        scene.idleDelay = 0.05
        let view = SCNView(frame: .zero)
        scene.noteActivity(view)
        await wait(0.3)
        XCTAssertEqual(view.preferredFramesPerSecond, 60)
        scene.setPowerState(lowPower: false, thermalSerious: false)
        XCTAssertTrue(scene.isFlickering, "戻っても揺れ直さない")
    }

    /// 熱は「視差効果を減らす」と独立: 視差効果が許していても熱で止まり、熱が引いても視差効果が止めていれば止まったまま
    func testThermalAndReduceMotionAreIndependent() {
        let scene = nightScene()
        scene.setPowerState(lowPower: false, thermalSerious: true)
        XCTAssertFalse(scene.isFlickering)
        scene.setFlicker(allowed: false)
        scene.setPowerState(lowPower: false, thermalSerious: false)
        XCTAssertFalse(scene.isFlickering, "熱が引いたら視差効果の指定まで外れた")
        scene.setFlicker(allowed: true)
        XCTAssertTrue(scene.isFlickering)
    }
}
#endif
