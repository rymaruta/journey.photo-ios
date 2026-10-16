import Foundation

/// 「構図を重ねて撮る」の撮影画面を**標準のカメラ App と遜色なく**するための、画面を持たない決まり
/// （2026-10-16 owner「イメージはデフォルトの iPhone の撮影と遜色ないようにしたい」）。
///
/// 画面は `Features/Spots/ComposeGuideView.swift`、カメラの操作は `ComposeCamera.swift`。ここは Linux の
/// 試験で見張れる計算だけを置く: 拡大の段（0.5×/1×/2×/望遠）・ピンチ・指の動きの読み分け
/// （タップ＝ピント、長押し＝固定、縦に動かす＝明るさ、横に払う＝作例）・ピントの座標・UI を隠したときのシャッター。
///
/// **実機では確かめていない**（Linux の模型で型と計算を通しただけ）。レンズの切り替わりの倍率・
/// ピントの座標の向きは端末で見ること（報告の「確かめていないこと」）。
enum ComposeControls {

    // MARK: - 拡大

    /// 拡大の段。`divisor` はカメラの倍率（`videoZoomFactor`）を画面の倍率（0.5×・1× …）に直す割る数
    struct ZoomLevels: Equatable {
        /// カメラの倍率 ÷ これ ＝ 画面の倍率。超広角があれば 1× のレンズへ切り替わる倍率（ふつう 2）
        let divisor: Double
        /// 押して選べる段（画面の倍率・小さい順）
        let presets: [Double]
        /// カメラの倍率の下と上（ピンチで動かせる範囲）
        let minFactor: Double
        let maxFactor: Double

        /// 画面の倍率 → カメラの倍率（範囲の内へ）
        func factor(display: Double) -> Double {
            guard display.isFinite else { return minFactor }
            return min(max(display * divisor, minFactor), maxFactor)
        }

        /// カメラの倍率 → 画面の倍率
        func display(factor: Double) -> Double {
            guard factor.isFinite, divisor > 0 else { return 1 }
            return factor / divisor
        }
    }

    /// ピンチで寄れる上限（画面の倍率）。標準のカメラ App の最大（Pro 機の 15〜25×）より控えめにし、
    /// デジタルで荒れすぎる所までは行かせない
    static let maxDisplayZoom = 10.0

    /// 端末のレンズから拡大の段を決める。
    /// - Parameters:
    ///   - hasUltraWide: 超広角を含む仮想カメラ（三眼・二眼の広角）か
    ///   - switchOver: レンズが切り替わるカメラの倍率（`virtualDeviceSwitchOverVideoZoomFactors`）
    ///   - minFactor/maxFactor: カメラの倍率の範囲（`minAvailableVideoZoomFactor` など）
    ///
    /// 2026-10-16 判断: 段は標準のカメラ App にそろえる——超広角があれば 0.5×、いつも 1× と 2×（1× のレンズの
    /// 切り出し）、望遠があればその倍率（3×・5× など）。端末に無い段は出さない
    static func zoomLevels(hasUltraWide: Bool, switchOver: [Double], minFactor: Double, maxFactor: Double) -> ZoomLevels {
        let factors = switchOver.filter { $0.isFinite && $0 > 1 }.sorted()
        let lo = minFactor.isFinite && minFactor > 0 ? minFactor : 1
        let hiRaw = maxFactor.isFinite && maxFactor >= lo ? maxFactor : lo
        let divisor = hasUltraWide ? (factors.first ?? 2) : 1
        let hi = min(hiRaw, maxDisplayZoom * divisor)
        var presets: [Double] = []
        if hasUltraWide { presets.append(lo / divisor) }
        presets.append(1)
        presets.append(2)
        // 望遠（超広角があれば 2 つ目からの切り替わり、無ければ 1 つ目から）
        for f in factors.dropFirst(hasUltraWide ? 1 : 0) { presets.append(f / divisor) }
        let rounded = presets.map { ($0 * 10).rounded() / 10 }
        var seen: [Double] = []
        for p in rounded.sorted() where !seen.contains(p) && p * divisor >= lo - 1e-9 && p * divisor <= hi + 1e-9 {
            seen.append(p)
        }
        return ZoomLevels(divisor: divisor, presets: seen, minFactor: lo, maxFactor: hi)
    }

    /// ピンチの後のカメラの倍率（始めた倍率 × 指の開き・範囲の内）
    static func pinchedFactor(start: Double, magnification: Double, levels: ZoomLevels) -> Double {
        guard start.isFinite, magnification.isFinite, magnification > 0 else { return levels.minFactor }
        return min(max(start * magnification, levels.minFactor), levels.maxFactor)
    }

    /// いまの倍率に当たる段（その段以上・次の段未満）。標準のカメラ App と同じく、その段の丸に
    /// いまの倍率を出す
    static func activePreset(display: Double, presets: [Double]) -> Double? {
        presets.last { display >= $0 - 0.05 }
    }

    /// 段の丸の字。選んでいる段は「1×」「1.4×」、ほかは「.5」「2」（標準のカメラ App と同じ書き方）
    static func zoomLabel(_ value: Double, active: Bool) -> String {
        let v = (value * 10).rounded() / 10
        var text = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
        if !active, text.hasPrefix("0.") { text = String(text.dropFirst()) }
        return active ? text + "×" : text
    }

    /// 段ごとの識別子（「composeGuide.zoom.0_5」「composeGuide.zoom.2」）。画面の試験で段を押し分ける
    static func zoomIdentifier(_ value: Double) -> String {
        let v = (value * 10).rounded() / 10
        let text = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: "_")
        return "composeGuide.zoom.\(text)"
    }

    /// 拡大の段の読み上げ（「2倍」）
    static func zoomAccessibility(_ value: Double) -> String {
        let text = zoomLabel(value, active: false).replacingOccurrences(of: "×", with: "")
        let shown = text.hasPrefix(".") ? "0" + text : text
        return L("\(shown)倍", "\(shown)×")
    }

    // MARK: - 指の動きの読み分け（映像の枠の上）

    /// タップとみなす動きの上限（pt）
    static let tapSlop = 10.0
    /// 長押し（ピントと明るさを固定）の長さ（秒）。標準のカメラ App とほぼ同じ
    static let longPressSeconds = 0.6
    /// 明るさを 1 段（EV）動かす縦の長さ（pt）
    static let pointsPerEV = 120.0
    /// 2本指（ひねる・つまむ）の直後に、1本指のタップ・払いとみなさない間（秒）
    static let multiTouchQuiet = 0.4

    /// 指を離したときに何をするか
    enum TouchEnd: Equatable {
        /// その場所にピント（UI を隠しているときは UI を戻す）
        case tap
        /// 左右に払った（作例を替える・横の長さ）
        case swipe(Double)
        /// 何もしない（明るさを動かした・長押しで固定した・2本指の直後・短い払い）
        case none
    }

    /// 指を離したときの読み分け。`adjustedExposure` は縦に動かして明るさを変えた・`locked` は長押しで固定した
    static func touchEnd(dx: Double, dy: Double, seconds: Double, adjustedExposure: Bool, locked: Bool,
                         afterMultiTouch: Bool) -> TouchEnd {
        guard !afterMultiTouch, !adjustedExposure, !locked, dx.isFinite, dy.isFinite else { return .none }
        if abs(dx) <= tapSlop, abs(dy) <= tapSlop { return seconds < longPressSeconds ? .tap : .none }
        if abs(dx) > abs(dy), abs(dx) >= ComposeGuide.swipeThreshold { return .swipe(dx) }
        return .none
    }

    /// 縦に動かして明るさを変えるか（ピントの枠が出ているとき・縦が横より大きく、タップの幅を越えた）。
    /// 2026-10-16（確かめ役の指摘）: 2本指の最中・直後（`afterMultiTouch`）は読まない——つまむ・ひねる指の
    /// 1本目が縦に動いて明るさが変わっていた
    static func isExposureDrag(dx: Double, dy: Double, focusShown: Bool, afterMultiTouch: Bool = false) -> Bool {
        !afterMultiTouch && focusShown && dx.isFinite && dy.isFinite && abs(dy) > tapSlop && abs(dy) > abs(dx)
    }

    // MARK: - 2本指でひねる（2026-10-16・確かめ役の指摘「つまむたびに構図が回る」）

    /// ひねりを効かせ始める角度（度）。つまむ指は少しひねれるので、これを越えるまでは回さない
    static let twistThreshold = 15.0
    /// つまむ量がこれを越えたら（1.15 倍・0.87 倍）、その指ではひねりを読まない＝拡大の指とみなす
    static let pinchDominance = 0.15

    /// ひねりの指の状態（2本指を置いてから離すまで）
    struct Twist: Equatable {
        /// ひねりとして効いている
        var engaged = false
        /// 拡大の指とみなした（離すまで回さない）
        var blocked = false
    }

    /// ひねりの指の次の状態。拡大の量（`magnification`・1 が無し）が先に大きくなったら回さない。
    /// ひねりが `twistThreshold` を越えたら効かせる。一度決まったら離すまで変えない
    static func nextTwist(_ state: Twist, rotation: Double, magnification: Double) -> Twist {
        guard !state.engaged, !state.blocked else { return state }
        var next = state
        if magnification.isFinite, magnification > 0, abs(magnification - 1) > pinchDominance {
            next.blocked = true
        } else if rotation.isFinite, abs(rotation) >= twistThreshold {
            next.engaged = true
        }
        return next
    }

    /// 描くときに足すひねりの角度。効かせ始めた所から数える（越えた瞬間に 15° 跳ねない）
    static func effectiveTwist(rotation: Double, state: Twist) -> Double {
        guard state.engaged, rotation.isFinite else { return 0 }
        return rotation - (rotation < 0 ? -twistThreshold : twistThreshold)
    }

    /// 吸い付いた合図の値（0〜3）。ひねりが効いていて 0/90/180/270 ちょうどに乗ったときだけ。それ以外は -1
    /// （振動は新しい値が 0 以上のときだけ鳴らす・`sensoryFeedback(_:trigger:condition:)`）
    static func snapSignal(shownRotation: Double, twisting: Bool) -> Int {
        guard twisting, CompositionGuide.isQuarterRotation(shownRotation) else { return -1 }
        return CompositionGuide.rotationParts(shownRotation).quarters
    }

    /// 振動を鳴らすか（吸い付いたときだけ）
    static func snapFeedbackFires(old: Int, new: Int) -> Bool { new >= 0 && new != old }

    // MARK: - 回した角度（累積・2026-10-16 確かめ役の指摘「270°→0° で写真が逆に 270° 回る」）

    /// 「右に90度回す」: 累積の角度のまま次の 90° の倍数へ（270 → 360）。表示・線は 0〜360 に戻して使う
    /// （`CompositionGuide.normalizedRotation`）ので、絵の回る向きはいつも右へ 90°
    static func rotatedRightCumulative(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 90 }
        return (floor(degrees / 90 + 1e-9) + 1) * 90
    }

    /// 累積の角度のまま、0/90/180/270 の近くなら吸い付かせる
    static func snappedCumulative(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let nearest = (degrees / 90).rounded() * 90
        return abs(degrees - nearest) <= CompositionGuide.rotationSnap ? nearest : degrees
    }

    /// 真っ直ぐに戻す先（いちばん近い 360° の倍数・逆回りに大きく回らない）
    static func straightened(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        return (degrees / 360).rounded() * 360
    }

    /// 参考写真の枠の縦横を入れ替えるか。**決まった角度（ひねっている途中は含めない）で決める**——
    /// 途中の 45° で入れ替えると写真の大きさが跳ねる。離したあと、動きを付けて入れ替える
    static func referenceSwapsAxes(committedRotation: Double) -> Bool {
        CompositionGuide.rotationParts(committedRotation).quarters % 2 == 1
    }

    // MARK: - シャッターの暗転

    /// 押した瞬間の暗転を見せておく長さ（秒）。黒を一度描かせてから戻す（同じ処理で戻すと描かれない）
    static let shutterFlashHold = 0.06

    /// 明るさ（露出の補正・EV）。上へ動かすと明るく。範囲の内へ
    static func exposureBias(start: Double, dy: Double, min lo: Double, max hi: Double) -> Double {
        guard start.isFinite, dy.isFinite, lo <= hi else { return 0 }
        return Swift.min(Swift.max(start - dy / pointsPerEV, lo), hi)
    }

    /// 2本指の直後か（タップ・払いを止める）
    static func isAfterMultiTouch(last: Date?, now: Date) -> Bool {
        guard let last else { return false }
        return now.timeIntervalSince(last) < multiTouchQuiet
    }

    /// 映像の枠の上の点（左上 0,0・pt）を、カメラのピントの点（0〜1）に直す。
    ///
    /// カメラの座標は**端末を横（ホームボタンが右）にした向き**が基準（Apple の注記）。画面は縦持ちだけで、
    /// 映像は 3:4 の枠に切らずに敷いている（`CameraPreview.gravity`）ので、枠の上の割合をそのまま回せばよい:
    /// 縦の画面の (x, y) → カメラの (y, 1 − x)。2026-10-16 判断: 映像の層の変換（`captureDevicePointConverted`）
    /// を使わないのは、指の位置を SwiftUI で受けて試験で見張るため。**実機で確かめていない**
    static func devicePoint(x: Double, y: Double, width: Double, height: Double) -> (x: Double, y: Double) {
        guard width > 0, height > 0, x.isFinite, y.isFinite else { return (0.5, 0.5) }
        let u = min(max(x / width, 0), 1), v = min(max(y / height, 0), 1)
        return (v, 1 - u)
    }

    // MARK: - UI を隠したとき

    /// UI を隠している間、枠の下の黒い余りにシャッターを置けるか（枠に重ねない）。
    /// 置けない（余りが狭い）ときは置かず、音量ボタン・読み上げの「撮影」で撮る
    static func hiddenShutterFits(containerHeight: Double, frameHeight: Double, shutter: Double) -> Bool {
        guard containerHeight.isFinite, frameHeight.isFinite else { return false }
        return (containerHeight - frameHeight) / 2 >= shutter + 8
    }

    /// 撮れるか（映像が出ている・撮っている最中でない・構図のシートが開いていない）。
    /// 画面のシャッター・音量ボタン・読み上げの「撮影」が同じ決まりを通る
    static func canShoot(ready: Bool, capturing: Bool, sheetOpen: Bool) -> Bool {
        ready && !capturing && !sheetOpen
    }
}
