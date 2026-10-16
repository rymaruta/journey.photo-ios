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

    /// 縦に動かして明るさを変えるか（ピントの枠が出ているとき・縦が横より大きく、タップの幅を越えた）
    static func isExposureDrag(dx: Double, dy: Double, focusShown: Bool) -> Bool {
        focusShown && dx.isFinite && dy.isFinite && abs(dy) > tapSlop && abs(dy) > abs(dx)
    }

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
