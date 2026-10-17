import Combine
import CoreMotion
import Foundation

/// 乗車券の券面の光を動かす端末の傾き（CoreMotion・**2026-10-17**）。
///
/// - **表示中だけ**読む: 光が動く券面（`PassTicketFaceStyle.followsTilt`）が画面に出ている間だけ、見ている数
///   （`hold`）で始めて止める。アプリが前面でないとき・「視差効果を減らす」のときは持たない（`PassSpecialFace`）
/// - 電池: 30 回/秒の知らせのうち、光が `PassFaceLight.minStep` 以上動いたときだけ描き直す
/// - 動きの管理者は撮る画面の水準器（`LevelMotion.manager`）と同じ1つ（Apple の注記: アプリに1つ）。
///   撮る画面と券面は同時に出ないので取り合わない
/// - 傾きが取れない端末（シミュレータ）では光は正面のまま（指で回したときは回りに合わせて動く・`PassFaceLight.resolved`）
///
/// **実機では確かめていない**（Linux の模型でビルドを通しただけ）。
@MainActor
final class PassTiltMotion: ObservableObject {

    static let shared = PassTiltMotion()

    /// 光の位置（0〜1・正面 0.5）
    @Published private(set) var light = PassFaceLight.Point.center

    /// 見ている券面の数（0 になったら止める）
    private(set) var holders = 0
    private var baselineY: Double?
    private var manager: CMMotionManager { LevelMotion.manager }

    /// 30 回/秒
    static let updateInterval = 1.0 / 30

    /// 券面が出た（前面・「視差効果を減らす」でないとき）
    func hold() {
        holders += 1
        if holders == 1 { start() }
    }

    /// 券面が消えた・背面に回った
    func release() {
        guard holders > 0 else { return }
        holders -= 1
        if holders == 0 { stop() }
    }

    private func start() {
        guard manager.isDeviceMotionAvailable else { return }
        // 撮る画面の水準器が持っている間は取らない（`DeviceMotionOwner`）
        guard DeviceMotionOwner.isFree(for: self) else { return }
        DeviceMotionOwner.claim(self)
        baselineY = nil
        manager.deviceMotionUpdateInterval = Self.updateInterval
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity else { return }
            MainActor.assumeIsolated {
                self?.receive(x: gravity.x, y: gravity.y)
            }
        }
    }

    private func stop() {
        // 自分が持っていたときだけ止める（水準器が後から取っていたら、その知らせと間隔を壊さない）
        if DeviceMotionOwner.release(self) { manager.stopDeviceMotionUpdates() }
        baselineY = nil
        light = .center
    }

    private func receive(x: Double, y: Double) {
        // 見始めた時の持ち方を正面にする
        let base = baselineY ?? y
        baselineY = base
        let next = PassFaceLight.point(gravityX: x, gravityY: y, baselineY: base)
        guard PassFaceLight.needsUpdate(from: light, to: next) else { return }
        light = next
    }
}
