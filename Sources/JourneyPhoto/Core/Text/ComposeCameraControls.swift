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
        /// 効き始めた向き（+1 右回り・-1 左回り）。2026-10-16（見直しの指摘）: ずらす 15° の向きを
        /// その時の指の正負で決めると、効いた後に 0° をまたいだとき線が 30° 跳んだ。効き始めに覚えて離すまで変えない
        var direction = 0.0
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
            next.direction = rotation < 0 ? -1 : 1
        }
        return next
    }

    /// 描くときに足すひねりの角度。効かせ始めた所から数える（越えた瞬間に 15° 跳ねない）
    static func effectiveTwist(rotation: Double, state: Twist) -> Double {
        guard state.engaged, rotation.isFinite else { return 0 }
        return rotation - state.direction * twistThreshold
    }

    /// 吸い付いた合図の値（0〜3）。ひねりが効いていて 0/90/180/270 ちょうどに乗ったときだけ。それ以外は -1
    /// （振動は新しい値が 0 以上のときだけ鳴らす・`sensoryFeedback(_:trigger:condition:)`）。
    /// 2026-10-16（見直しの指摘）: もとの角度（`baseRotation`・ひねる前に決まっていた角度）のままのときは -1。
    /// 効いた瞬間は足す角度が 0 で、もとの角度に乗ったまま 1 回鳴っていた
    static func snapSignal(shownRotation: Double, baseRotation: Double, twisting: Bool) -> Int {
        guard twisting, CompositionGuide.isQuarterRotation(shownRotation),
              abs(shownRotation - snappedCumulative(baseRotation)) > 1e-9 else { return -1 }
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

    // MARK: - 開いたときの向き（2026-10-18 owner「縦空くのは嫌」・勝手に拡大はしない）

    /// 縦横の差がこの割合より小さい作例は正方形とみなす（ほぼ正方形を回しても空きはほとんど減らず、
    /// 回った絵に戸惑うだけ）
    static let squareTolerance = 0.02

    /// 参考写真（作例・ライブラリの写真）に合わせて、最初に回しておく角度（0 / 90 / 270・時計回りの度）。
    ///
    /// **2026-10-18 判断（owner 了承済み）**: 横長の作例を縦の枠（撮れる範囲 3:4）に重ねると上下が空く。
    /// 拡大・切り取りはしない（写真は表示で回すだけ・`rotatedReference` が縦横を入れ替えた枠に収める）。
    /// 代わりに**最初から 90° 回した向きで重ねる**。縦長・正方形・枠が横長なら 0°。
    ///
    /// **回す向き**: 画面上で写真の「上」が向く側に、端末の上を倒して持てば写真が正しく立つ。
    /// - 既定は **90°（時計回り・写真の上が画面の右）**。端末を左へ倒して（反時計回り）横に持つ向き
    ///   ＝ダイナミックアイランド（ホームボタンの機種はその反対側のホームボタン）が左、
    ///   右上にカメラコントロール・音量ボタンが下。標準のカメラ App の横持ちの基本の向きで、
    ///   カメラの撮像素子の素の向き（`UIDeviceOrientation.landscapeLeft`）とも合う
    /// - いま端末を逆の横向き（上を右に倒した `heldQuarterTurns == 1`）で持っていれば **270°**
    ///   （写真の上が画面の左）。縦持ち・逆さま・平置きのときは既定の 90°
    /// - **左右反転（ライブラリの写真の `mirrored`）は角度を変えない**。反転は写真の中の左右だけを入れ替え
    ///   （`rotatedReference` の中で回す前にかける）、上下は動かない——回した後も写真の上は同じ側にある
    static func autoRotation(referenceWidth: Double, referenceHeight: Double, frameAspect: Double,
                             heldQuarterTurns: Int, mirrored: Bool = false) -> Double {
        guard referenceWidth.isFinite, referenceHeight.isFinite, frameAspect.isFinite,
              referenceWidth > 0, referenceHeight > 0, frameAspect > 0 else { return 0 }
        let aspect = referenceWidth / referenceHeight
        // 枠が縦長で、作例がはっきり横長のときだけ回す
        guard frameAspect < 1, aspect > 1 + squareTolerance else { return 0 }
        _ = mirrored // 反転は上下を変えない（上の注記）。呼ぶ側が渡し忘れても同じ答え
        return ((heldQuarterTurns % 4) + 4) % 4 == 1 ? 270 : 90
    }

    /// 回す角度を決め直すきっかけ
    enum RotationTrigger: Equatable {
        /// 画面を開いた
        case opened
        /// 重ねる参考写真が替わった（作例を送った・ライブラリから選んだ・「作例」と「写真ライブラリ」を切り替えた）
        case referenceChanged
        /// 構図をシートで選び直した
        case compositionChosen
        /// 持った向き（縦・横）が変わった
        case heldTurned
    }

    /// きっかけごとの角度の決め直し。返すのは**累積の角度**（いまの角度からいちばん短く回る値）、
    /// nil は「今のまま」。
    ///
    /// **2026-10-18 判断（人が回した角度と自動の兼ね合い）**:
    /// - 参考写真があるとき（`auto` が nil でない）は、**開いたとき・参考写真が替わったとき・構図を選び直したときは
    ///   自動の向き**。覚えた角度（`CompositionPreferences.rotation(for:)`）は前に重ねた別の写真のために
    ///   選んだ向きなので、新しく重ねる写真には使わない（作例が変わったら自動に戻す）
    /// - 人が回すボタン・ひねりで回した後（`manual`）は、その向きを尊重する——持った向きが変わっても
    ///   自動で回し直さない。参考写真か構図が替わるまで保つ
    /// - 参考写真が無いとき（作例なしの入口・ライブラリの写真を選ぶ前）は今まで通り: 開いたら覚えた角度、
    ///   構図を選び直したら 0°（`CompositionPreferences.select` と同じ）
    /// - 自動の向きは覚えない（覚えるのは人が回した角度だけ・`setRotation`）
    /// - **縦持ち・逆さまに戻したとき（`held` が 0・2）は、横向き（90°・270°）をそのまま保つ**
    ///   （2026-10-18 確かめ役の指摘）。270° で横に持ってから縦に戻すと、既定の 90° へ戻して作例が
    ///   180° ひっくり返っていた。縦持ちではどちらの横向きでも同じだけ収まるので、動かさない
    static func decidedRotation(_ trigger: RotationTrigger, current: Double, manual: Bool,
                                auto: Double?, remembered: Double, held: Int = 0) -> Double? {
        let target: Double?
        switch trigger {
        case .opened: target = auto ?? remembered
        case .referenceChanged: target = auto
        case .compositionChosen: target = auto ?? 0
        case .heldTurned:
            let sideways = CompositionGuide.normalizedRotation(current) == 90
                || CompositionGuide.normalizedRotation(current) == 270
            target = manual || (held % 2 == 0 && sideways) ? nil : auto
        }
        guard let target else { return nil }
        // 開いたときは回る前の角度が無いので 0〜360 のまま（覚えた 270° を -90° にしない）
        if trigger == .opened { return CompositionGuide.normalizedRotation(target) }
        return nearestCumulative(to: target, from: current)
    }

    /// 開いてからこの秒数の内に持った向きで回し直すときは、動きを付けない（2026-10-18 確かめ役の指摘）。
    /// 時計回りの横持ちで開くと、最初の傾きの値が届くまでは既定の 90° で描き、届いたら 270° へ回し直す——
    /// 動きを付けると、開いた直後に作例が 180° 回って見えた。傾きは 10 回/秒で読む（`LevelMotion`）ので、
    /// 最初の値は 1 秒より十分前に届く
    static let openingSettle = 1.0

    /// 持った向きで回し直すときに動きを付けるか（開いた直後は付けない）
    static func animatesHeldTurn(secondsSinceAppear: Double) -> Bool {
        guard secondsSinceAppear.isFinite else { return true }
        return secondsSinceAppear >= openingSettle
    }

    /// 構図の線に渡す「持った向き」（`CompositionGuide.screenMarks` の `quarterTurns`）。
    ///
    /// **2026-10-18 判断（横持ちで線だけが回り、作例とずれる）**: 参考写真は画面に貼り付いた向き
    /// （`rotation` だけ）で描くのに、線は持った向きのぶんも回していた。横長の作例を 90° 回して開き、
    /// 端末を横にする——この直しのいちばんの使い方で、作例は正しく立つのに、黄金螺旋・対角・L字・
    /// 比率の枠などの向きのある線が作例から 90° ずれた（三分割は形が同じなので目立たない）。
    /// そこで**参考写真を重ねている間は、線も持った向きでは回さず作例と同じ向きにそろえる**（0 を返す）。
    /// 作例を 90° 回して横に持てば、線は横の写真の向きでちょうど立つ（回した角度が持った向きを打ち消す）。
    /// `referenceShown` には**隠しているかを含めない**（`hasReference`）——作例を一時的に隠しても、
    /// 作例の向きに合わせた線の向きは保つ（隠すたびに線が 90° 回らない・2026-10-18 確かめ役の指摘）。
    /// - 参考写真が無いとき（線だけ）は今まで通り、持った向きに合わせる（撮れる写真の向きの線）
    /// - 水準器はいつも持った向き（傾きは重さの向きが基準・回しもしない）
    static func linesQuarterTurns(held: Int, kind: CompositionKind?, referenceShown: Bool) -> Int {
        if kind == .level { return held }
        return referenceShown ? 0 : held
    }

    /// 0〜360 の角度 `target` を、累積の角度 `current` からいちばん短く回る累積の値にする
    /// （90° から 270° へは +180°・0° へは 360° の倍数の近いほう）
    static func nearestCumulative(to target: Double, from current: Double) -> Double {
        guard target.isFinite else { return current.isFinite ? current : 0 }
        guard current.isFinite else { return CompositionGuide.normalizedRotation(target) }
        var delta = (CompositionGuide.normalizedRotation(target) - CompositionGuide.normalizedRotation(current))
            .truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return current + delta
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
