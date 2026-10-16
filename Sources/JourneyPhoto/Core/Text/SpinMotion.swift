import Foundation

/// **指で回すときの手触り**（メダルの棚の「手に取って回す」・`MedalCoinCoordinator`）を、数だけで持つ。
///
/// 2026-10-16 判断（owner「このカードも回転できるようにしたい」）: メダルを回したときと同じ手触りを
/// すれちがいのきっぷ（`PassViewerView`）にも付ける。メダルは SceneKit で描くが、きっぷは写真を含む
/// SwiftUI の札（写真の上に光を乗せない・真鍮は黒地の上だけ）なので描き方は分け、**指の量・惰性・裏返しの
/// 決め方はここ1つを両方が使う**（写しを作らない）。
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
enum SpinMotion {

    /// 幅いっぱい払うと何ラジアン回るか（メダルと同じ: 幅で 1.5π）
    static let turnPerWidth = Double.pi * 1.5
    /// 離したときの惰性の上限（ラジアン/秒）。「視差効果を減らす」では弱く
    static let velocityLimit = 14.0
    static let reducedVelocityLimit = 3.0
    /// 吸い付く先を決めるとき、惰性で先に進むと見込む長さ（秒）
    static let snapLookahead = 0.12

    /// 指が動いた分の回り
    static func yawDelta(dx: Double, width: Double) -> Double {
        dx / max(1, width) * turnPerWidth
    }

    /// 離したときの回りの速さ（指の速さから・上限つき）
    static func releaseVelocity(vx: Double, width: Double, reduceMotion: Bool) -> Double {
        let speed = vx / max(1, width) * turnPerWidth
        let limit = reduceMotion ? reducedVelocityLimit : velocityLimit
        return min(limit, max(-limit, speed))
    }

    /// 裏返す（読み上げの操作・押して裏返す）: いまの向きから半周先の、表か裏の正面
    static func flipTarget(from yaw: Double) -> Double {
        (yaw / .pi).rounded() * .pi + .pi
    }

    /// 寄せていく1コマの割合（「視差効果を減らす」では一息に）
    static func approachStep(dt: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : min(1, dt * 7)
    }

    /// いちばん近い面（表か裏の正面）
    static func nearestFace(_ yaw: Double) -> Double {
        (yaw / .pi).rounded() * .pi
    }

    /// 離したときに吸い付く先: 惰性で少し先へ進んだ所から、いちばん近い面
    static func snapTarget(yaw: Double, velocity: Double) -> Double {
        nearestFace(yaw + velocity * snapLookahead)
    }

    /// その向きで裏（「ご案内」）が見えているか。**90° を越えたら裏**
    static func showsBack(_ yaw: Double) -> Bool {
        let turn = 2 * Double.pi
        var a = yaw.truncatingRemainder(dividingBy: turn)
        if a < 0 { a += turn }
        return a > .pi / 2 && a < 3 * .pi / 2
    }

    /// 縁と破線に流れる光の位置（0〜1 の外にあれば見えない）。正面で止まっているときは端の外
    static func shine(_ yaw: Double) -> Double {
        var f = (yaw / .pi).truncatingRemainder(dividingBy: 1)
        if f < 0 { f += 1 }
        return f * 1.6 - 0.3
    }
}

/// 束の画面できっぷに指を置いて動かしたとき、何をするか（**2026-10-16 判断**）。
///
/// 前は「左右に払って次のカード」だけだった。回すのと競るので、こう分ける:
/// - **きっぷの上で指を置いて動かす → 回す**（ゆっくりでも速くても指に付いてくる。離すと近い面に吸い付く）
/// - **きっぷの上で素早く短く払う → 次／前のカード**（`flickDuration` 以内・惰性の見込みが `flickDistance` 以上・
///   動いた量が `flickTravel` 未満）
/// - **きっぷの外（上下の余白）で払う → 次／前のカード**（前と同じ・`PassViewerView.swipeDistance`）
/// - 「視差効果を減らす」では回さない: きっぷの上でも払えば次／前（前と同じ）、押すと裏返る
///
/// 読み上げの操作（裏返す・次・前・写真を全面）は前と同じに残す
enum PassSpinGesture {

    enum Outcome: Equatable {
        case rotate
        case next
        case previous
        /// 何もしない（外で払ったが短かった）
        case none
    }

    static let flickDuration = 0.25
    static let flickDistance = 200.0
    static let flickTravel = 120.0

    static func classify(translation: Double, predicted: Double, duration: Double,
                         onCard: Bool, reduceMotion: Bool, swipeDistance: Double) -> Outcome {
        func page(_ width: Double) -> Outcome {
            if width <= -swipeDistance { return .next }
            if width >= swipeDistance { return .previous }
            return .none
        }
        guard onCard, !reduceMotion else { return page(abs(predicted) > abs(translation) ? predicted : translation) }
        let isFlick = duration <= flickDuration && abs(predicted) >= flickDistance && abs(translation) < flickTravel
        guard isFlick else { return .rotate }
        return predicted < 0 ? .next : .previous
    }
}
