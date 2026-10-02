import Foundation

/// レシピ →「Core Image のフィルター名と引数の並び」。**純関数**（Core Image に触らない）。
/// 実際にフィルターを組むのは `PhotoRenderer`。ここを分けてあるのは、並びと数値の対応を
/// Linux のテストで確かめるため（本物の Core Image の見た目は Mac でしか見られない）。
///
/// **並び（2026-10-02 判断）**
/// 1. `CITemperatureAndTint` — 白の基準（ホワイトバランス）。カメラの現像と同じく最初に置く。
///    あとの露出・コントラストは「正しい白」を前提にした方が破綻しにくい
/// 2. `CIExposureAdjust` — 露出。Core Image の作業色空間（リニア）で掛け算するので、
///    カメラの露出と同じ効き方になる。明るさの土台なので、階調をいじる前に決める
/// 3. `CIHighlightShadowAdjust` — 明るい所を抑える・暗い所を起こす。露出を決めたあとの
///    明るさを見て効くものなので露出の後
/// 4. `CIColorControls` — コントラストと彩度。階調を整えたあとに全体の強さを決める
/// 5. `CIToneCurve` — プリセットの「見た目」（色あせた黒・S 字）。**最後に置く**——
///    コントラストのあとに置かないと、持ち上げた黒がコントラストで沈み、色あせが消える
///
/// **無変更の項目はフィルターを足さない。** 無編集のレシピなら空の並び（描く側は元の画像の
/// まま返す）。0 の調整でも Core Image は1段ぶんの計算と丸めをするため
enum PhotoRecipePlan {

    /// フィルターの引数の値。`CIVector` は `.vector` で表す
    enum Value: Equatable {
        case number(Double)
        case vector([Double])
    }

    struct Step: Equatable {
        let filter: String
        let parameters: [String: Value]
    }

    /// これより小さいずれは「無変更」と見る（足し引きの丸めの誤差で 1 段足さない）
    static let epsilon = 1e-6

    // MARK: - 数値の対応（控えめに。写真が壊れない幅）

    /// 白の基準（K）。Core Image の `CITemperatureAndTint` の既定と同じ
    static let neutralKelvin = 6500.0
    /// 色温度の振れ幅（ミレッド）。±1 で 6500K から ±40 ミレッド
    /// （約 8800K / 約 5200K）。ケルビンは見た目に対して非線形なので、ミレッド（1e6/K）で
    /// 等しく振ると、暖・寒の効き方がそろう
    static let temperatureMireds = 40.0

    /// `CITemperatureAndTint` の inputNeutral（K）。**＋（暖かく）は高い K を申告する**——
    /// このフィルターは「写真は inputNeutral の光で撮られた」として inputTargetNeutral へ
    /// 直すので、青い光（高い K）で撮ったと言えば黄の側へ補正される。
    /// 向きは Apple の説明と一般の使われ方からの判断で、**実機の見た目では確かめていない**
    static func neutralKelvin(temperature t: Double) -> Double {
        let mired = 1e6 / neutralKelvin - t * temperatureMireds
        return 1e6 / mired
    }

    /// `CIColorControls` の inputContrast。±1 → 0.75…1.25（既定 1）
    static func contrastAmount(_ c: Double) -> Double { 1 + 0.25 * c }

    /// `CIColorControls` の inputSaturation。−1 → 0（白黒）、0 → 1、＋1 → 1.5。
    /// 下げる側は白黒まで届かせ、上げる側は肌が赤く転ばない 1.5 で止める
    static func saturationAmount(_ s: Double) -> Double { s >= 0 ? 1 + 0.5 * s : 1 + s }

    /// `CIHighlightShadowAdjust` の inputHighlightAmount（既定 1・下げると明るい所が抑えられる）。
    /// −1 → 0.3（Apple のつまみの下限）。**このフィルターは明るい所を上げられない**ので、
    /// ＋の側は色の曲線の上の方を持ち上げて作る（`highlightLift`）
    static func highlightAmount(_ h: Double) -> Double { h < 0 ? 1 + 0.7 * h : 1 }

    /// `CIHighlightShadowAdjust` の inputShadowAmount（既定 0・幅 −1…1）。
    /// 全幅は使わず ±0.6 に止める（影を起こし過ぎると灰色に浮く）
    static func shadowAmount(_ s: Double) -> Double { 0.6 * s }

    /// 明るい所を上げる（＋の highlights）ための曲線のずれ。0.75 の点を最大 +0.06、
    /// 0.5 の点を +0.02。白（1）は動かさない（白飛びを増やさない）
    static func highlightLift(_ h: Double) -> PhotoToneCurve {
        guard h > 0 else { return .identity }
        return PhotoToneCurve(ys: [0, 0.25, 0.5 + 0.02 * h, 0.75 + 0.06 * h, 1])
    }

    // MARK: - 解く

    /// レシピを最終の調整に解く: **プリセット（強さで薄めたもの）＋つまみの値**を足し、幅に収める
    static func resolve(_ recipe: PhotoRecipe) -> PhotoAdjustments {
        let r = recipe.sanitized
        var base = PhotoAdjustments.identity
        if let choice = r.preset, let preset = PhotoPresets.preset(id: choice.id) {
            base = preset.adjustments.scaled(by: choice.strength)
        }
        let unit = PhotoRecipe.unitRange
        return PhotoAdjustments(
            exposure: PhotoRecipe.clamp(base.exposure + r.exposure, PhotoRecipe.exposureRange),
            contrast: PhotoRecipe.clamp(base.contrast + r.contrast, unit),
            saturation: PhotoRecipe.clamp(base.saturation + r.saturation, unit),
            temperature: PhotoRecipe.clamp(base.temperature + r.temperature, unit),
            highlights: PhotoRecipe.clamp(base.highlights + r.highlights, unit),
            shadows: PhotoRecipe.clamp(base.shadows + r.shadows, unit),
            curve: base.curve)
    }

    /// フィルターの並び。無編集なら空
    static func steps(for recipe: PhotoRecipe) -> [Step] {
        let a = resolve(recipe)
        func changed(_ v: Double) -> Bool { abs(v) > epsilon }
        var steps: [Step] = []

        if changed(a.temperature) {
            steps.append(Step(filter: "CITemperatureAndTint", parameters: [
                "inputNeutral": .vector([neutralKelvin(temperature: a.temperature), 0]),
                "inputTargetNeutral": .vector([neutralKelvin, 0]),
            ]))
        }
        if changed(a.exposure) {
            steps.append(Step(filter: "CIExposureAdjust", parameters: ["inputEV": .number(a.exposure)]))
        }
        if a.highlights < -epsilon || changed(a.shadows) {
            steps.append(Step(filter: "CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": .number(highlightAmount(a.highlights)),
                "inputShadowAmount": .number(shadowAmount(a.shadows)),
            ]))
        }
        if changed(a.contrast) || changed(a.saturation) {
            steps.append(Step(filter: "CIColorControls", parameters: [
                "inputContrast": .number(contrastAmount(a.contrast)),
                "inputSaturation": .number(saturationAmount(a.saturation)),
                "inputBrightness": .number(0),
            ]))
        }
        let curve = a.curve.adding(highlightLift(a.highlights))
        if zip(curve.ys, PhotoToneCurve.xs).contains(where: { changed($0 - $1) }) {
            var parameters: [String: Value] = [:]
            for (i, (x, y)) in zip(PhotoToneCurve.xs, curve.ys).enumerated() {
                parameters["inputPoint\(i)"] = .vector([x, y])
            }
            steps.append(Step(filter: "CIToneCurve", parameters: parameters))
        }
        return steps
    }
}
