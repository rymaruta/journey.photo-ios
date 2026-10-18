import Combine
import CoreMotion
import Foundation

/// 端末の動きの管理者（`LevelMotion.manager`）を、いま誰が使っているか（**2026-10-17**）。
///
/// 管理者はアプリに1つで、知らせの受け手も1つ。撮る画面の水準器（`LevelMotion`）と乗車券の券面の光
/// （`PassTiltMotion`）が取り合わないよう、**止めてよいのは今の持ち主だけ**にする:
/// - 水準器は取る（撮る画面が先）。券面は、水準器が持っている間は取らない
/// - 止めるときは `release` が true のときだけ止める（後から取った側の知らせを止めない・間隔も変えない）
@MainActor
enum DeviceMotionOwner {
    private(set) static var current: ObjectIdentifier?

    /// 取る（前の持ち主から受け手を替える）
    static func claim(_ owner: AnyObject) { current = ObjectIdentifier(owner) }

    /// 空いているか、自分が持っているか
    static func isFree(for owner: AnyObject) -> Bool { current == nil || current == ObjectIdentifier(owner) }

    /// 手放す。**自分が持っていたときだけ** true（そのときだけ管理者を止めてよい）
    static func release(_ owner: AnyObject) -> Bool {
        guard current == ObjectIdentifier(owner) else { return false }
        current = nil
        return true
    }
}

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

    /// 2026-10-17: 乗車券の券面の光（`PassTiltMotion`）もこの1つを使う（アプリに1つ・撮る画面と券面は同時に出ない）
    static let manager = CMMotionManager()

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
        // 撮る画面が先（券面の光が持っていても取る・`DeviceMotionOwner`）
        DeviceMotionOwner.claim(self)
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
        // 自分が持っていたときだけ止める
        if DeviceMotionOwner.release(self) { Self.manager.stopDeviceMotionUpdates() }
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
