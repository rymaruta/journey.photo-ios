import Combine
import CoreMotion
import Foundation

/// 構図の「水準器」の傾き（CoreMotion・2026-10-10）。
///
/// 水準器を選んでいる間だけ動かす（電池を守る）。重力の向きから画面の上の水平線の角度を出し
/// （`CompositionGuide.levelAngle`）、水平（1° 以内）なら線を太くする。
/// 端末の動きの読み取り（device motion）は許可の問い合わせが要らない。傾きが取れない端末
/// （シミュレータ）では角度は 0 のまま（水平に見える線）——**取れないことを隠さないよう、
/// 案内の札に「この端末では傾きを読めません」を出す**（`available`）。
///
/// **実機では確かめていない**（Linux の模型でビルドを通しただけ）。
@MainActor
final class LevelMotion: ObservableObject {

    /// 画面の上で水平線を回す角度（度・時計回りが正）
    @Published private(set) var degrees: Double = 0
    /// 傾きを読める端末か
    let available: Bool

    private let manager = CMMotionManager()
    private var running = false

    init() {
        available = manager.isDeviceMotionAvailable
    }

    func start() {
        guard available, !running else { return }
        running = true
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity,
                  let angle = CompositionGuide.levelAngle(gravityX: gravity.x, gravityY: gravity.y) else { return }
            MainActor.assumeIsolated {
                self?.degrees = angle
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopDeviceMotionUpdates()
    }
}
