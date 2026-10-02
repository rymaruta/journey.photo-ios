import Foundation

/// 色の曲線（`CIToneCurve` の5点）。x は 0・0.25・0.5・0.75・1 に固定し、y だけを持つ。
/// R・G・B に同じ曲線がかかる（明るさの曲線。色ごとの曲線は持たない）
struct PhotoToneCurve: Equatable {

    static let xs: [Double] = [0, 0.25, 0.5, 0.75, 1]
    static let identity = PhotoToneCurve(ys: xs)

    /// 5つの y（0…1）
    let ys: [Double]

    /// 5つでなければ無変更の曲線にする。幅に収め、**右上がりを保つ**——
    /// 下がる点があると `CIToneCurve` のスプラインが折り返し、階調が反転する
    init(ys: [Double]) {
        guard ys.count == Self.xs.count else {
            self.ys = Self.xs
            return
        }
        var fixed: [Double] = []
        for (i, y) in ys.enumerated() {
            var value = y.isFinite ? min(max(y, 0), 1) : Self.xs[i]
            if let last = fixed.last { value = max(value, last) }
            fixed.append(value)
        }
        self.ys = fixed
    }

    var isIdentity: Bool { ys == Self.xs }

    /// 無変更の曲線との線形補間（`strength` 0 で無変更、1 でこの曲線）
    func scaled(by strength: Double) -> PhotoToneCurve {
        let s = PhotoRecipe.clamp(strength, PhotoRecipe.strengthRange)
        return PhotoToneCurve(ys: zip(Self.xs, ys).map { x, y in x + (y - x) * s })
    }

    /// 点ごとのずれ（y − x）を足す。曲線どうしを重ねるのに使う
    func adding(_ other: PhotoToneCurve) -> PhotoToneCurve {
        PhotoToneCurve(ys: zip(Self.xs, zip(ys, other.ys)).map { x, pair in pair.0 + pair.1 - x })
    }
}

/// 基本の調整（レシピのつまみと同じ項目・同じ幅）＋色の曲線。
/// プリセットの定義にも、レシピを解いた結果（`PhotoRecipePlan.resolve`）にも使う
struct PhotoAdjustments: Equatable {
    var exposure: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var temperature: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var curve: PhotoToneCurve = .identity

    static let identity = PhotoAdjustments()

    /// 強さで薄める（無変更との線形補間）
    func scaled(by strength: Double) -> PhotoAdjustments {
        let s = PhotoRecipe.clamp(strength, PhotoRecipe.strengthRange)
        return PhotoAdjustments(exposure: exposure * s, contrast: contrast * s,
                                saturation: saturation * s, temperature: temperature * s,
                                highlights: highlights * s, shadows: shadows * s,
                                curve: curve.scaled(by: s))
    }
}

/// フィルム風のプリセット1つ。
struct PhotoPreset: Equatable, Identifiable {
    /// 保存する id（レシピに残る）。**名前を変えても id は変えない**
    let id: String
    let nameJa: String
    let nameEn: String
    /// 強さ 1 のときの調整
    let adjustments: PhotoAdjustments

    var name: String { L(nameJa, nameEn) }
}

/// **自作の**プリセット（2026-10-02）。
///
/// - 他社のアプリ（VSCO など）の名前・数値は写していない。名前は旅と光にちなむ独自のもの
/// - **LUT ファイルは使わない。** 基本の調整の組み合わせと、5点の色の曲線だけで表す
///   ——出どころの分からない LUT を抱えるライセンスの心配が無く、強さも線形補間で決まる
/// - 白黒は**彩度 −1**（`CIColorControls` の inputSaturation 0）で作る
/// - 並びは画面に出す順
enum PhotoPresets {

    static let all: [PhotoPreset] = [
        // やわらかい色あせ: 黒を持ち上げ白を少し下げ、彩度を落とす。少しだけ暖かく
        PhotoPreset(id: "haze", nameJa: "薄霞", nameEn: "Haze",
                    adjustments: PhotoAdjustments(contrast: -0.15, saturation: -0.25, temperature: 0.1,
                                                  curve: PhotoToneCurve(ys: [0.08, 0.30, 0.53, 0.76, 0.95]))),
        // 冷たい朝: 青寄りで少し明るく、影を起こして空気を軽く
        PhotoPreset(id: "morning", nameJa: "朝の青", nameEn: "Blue Morning",
                    adjustments: PhotoAdjustments(exposure: 0.15, saturation: -0.1, temperature: -0.45,
                                                  shadows: 0.2,
                                                  curve: PhotoToneCurve(ys: [0.04, 0.27, 0.52, 0.76, 1]))),
        // 温かい夕方: 黄寄り・少し鮮やか・明るい所を抑えて空の色を残す。ゆるい S 字
        PhotoPreset(id: "dusk", nameJa: "夕凪", nameEn: "Evening Calm",
                    adjustments: PhotoAdjustments(contrast: 0.1, saturation: 0.15, temperature: 0.55,
                                                  highlights: -0.2,
                                                  curve: PhotoToneCurve(ys: [0, 0.23, 0.5, 0.78, 1]))),
        // 澄んだ港: 少し冷たく、締まった影と鮮やかな青
        PhotoPreset(id: "harbor", nameJa: "港町", nameEn: "Harbor",
                    adjustments: PhotoAdjustments(contrast: 0.25, saturation: 0.2, temperature: -0.2,
                                                  highlights: -0.3,
                                                  curve: PhotoToneCurve(ys: [0, 0.24, 0.5, 0.76, 1]))),
        // 明るい夏: 明るく鮮やか、影を起こす
        PhotoPreset(id: "summer", nameJa: "夏草", nameEn: "Midsummer",
                    adjustments: PhotoAdjustments(exposure: 0.2, saturation: 0.3, temperature: 0.15,
                                                  shadows: 0.25)),
        // 古い絵葉書: 暖かく少し色あせ、黒と白の両端を寝かせる
        PhotoPreset(id: "postcard", nameJa: "旅の葉書", nameEn: "Postcard",
                    adjustments: PhotoAdjustments(contrast: 0.1, saturation: -0.15, temperature: 0.3,
                                                  curve: PhotoToneCurve(ys: [0.06, 0.28, 0.52, 0.74, 0.92]))),
        // 高コントラストの白黒: 強い S 字・影を締める
        PhotoPreset(id: "sumi", nameJa: "墨", nameEn: "Sumi",
                    adjustments: PhotoAdjustments(contrast: 0.5, saturation: -1, shadows: -0.1,
                                                  curve: PhotoToneCurve(ys: [0, 0.18, 0.5, 0.83, 1]))),
        // やわらかい白黒: 黒を持ち上げた銀塩の印画紙の風
        PhotoPreset(id: "silver", nameJa: "銀の朝", nameEn: "Silver",
                    adjustments: PhotoAdjustments(contrast: -0.1, saturation: -1,
                                                  curve: PhotoToneCurve(ys: [0.07, 0.29, 0.52, 0.76, 0.97]))),
    ]

    static func preset(id: String) -> PhotoPreset? {
        all.first { $0.id == id }
    }
}
