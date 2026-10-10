import Combine
import CoreMotion
import Foundation

/// 撮る画面の端末の傾き（CoreMotion・2026-10-10）。2つの役目:
/// - **水準器**: 水準器を選んでいる間だけ、画面の上の水平線の角度（`degrees`）を 30 回/秒で出す。
///   0.1° 未満の変化は代入しない（`CompositionGuide.levelNeedsUpdate`）——描き直しを減らす
/// - **持った向き**（縦・横）: 撮る画面が出ている間ずっと、10 回/秒で 90° 単位の向き（`quarterTurns`）を見て、
///   変わったときだけ `onQuarterChange` で知らせる（構図の線を写真の向きに回す・`CompositionGuide.screenMarks`）
///
/// 🔴 **撮る画面（`ComposeGuideView`）はこれを見張らない**（`@State` で持つだけ）。見張ると角度が変わるたびに
/// 画面全体が描き直される（確かめ役の指摘）。角度を見るのは線だけの子の View（`CompositionLines`）。
///
/// 端末の動きの読み取りは許可の問い合わせが要らない。傾きが取れない端末（シミュレータ）では角度は 0・縦持ちのまま
/// ——**取れないことを隠さないよう、水準器では案内の札に「この端末では傾きを読めません」を出す**（`available`）。
/// `CMMotionManager` はアプリに1つ（Apple の注記）なので、型で1つだけ持つ。
///
/// **実機では確かめていない**（Linux の模型でビルドを通しただけ）。
@MainActor
final class LevelMotion: ObservableObject {

    /// 画面の上で水平線を回す角度（度・時計回りが正）。水準器を選んでいる間だけ動く
    @Published private(set) var degrees: Double = 0
    /// 持った向き（0〜3・`CompositionGuide.quarterTurns`）
    private(set) var quarterTurns = 0
    /// 持った向きが変わった
    var onQuarterChange: ((Int) -> Void)?

    private static let manager = CMMotionManager()

    /// 傾きを読める端末か
    var available: Bool { Self.manager.isDeviceMotionAvailable }

    private var running = false
    /// 水準器の角度を出すか
    private var tracksLevel = false
    private var lastDegrees: Double?

    /// 見張りを始める（撮る画面が出たとき・前に戻ったとき）。`level` は水準器を選んでいるか
    func start(level: Bool) {
        tracksLevel = level
        guard available else { return }
        Self.manager.deviceMotionUpdateInterval = level ? 1.0 / 30 : 1.0 / 10
        guard !running else { return }
        running = true
        Self.manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity else { return }
            let angle = CompositionGuide.levelAngle(gravityX: gravity.x, gravityY: gravity.y)
            MainActor.assumeIsolated {
                self?.receive(angle)
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        Self.manager.stopDeviceMotionUpdates()
    }

    private func receive(_ angle: Double?) {
        let quarter = CompositionGuide.quarterTurns(levelDegrees: angle, previous: quarterTurns)
        if quarter != quarterTurns {
            quarterTurns = quarter
            onQuarterChange?(quarter)
        }
        guard tracksLevel, let angle, CompositionGuide.levelNeedsUpdate(from: lastDegrees, to: angle) else { return }
        lastDegrees = angle
        degrees = angle
    }
}
