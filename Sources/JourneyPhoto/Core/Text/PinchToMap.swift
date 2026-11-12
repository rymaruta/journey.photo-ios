import Foundation

/// **つまむと、地図になる**（2026-11-12・札 #543・資料第6章 段1「写真の詳細」）。
///
/// 写真の詳細の大きな写真を2本指でつまんで縮めると、写真が小さくなりながら撮影地の地図が引いてくる。
/// 離すと撮影地の地図（今の「地図で見る ›」の行き先 `NearbyMapScreen`）。押す回数は 2回＋送る → 0回。
///
/// - **段**: 等倍の下で一度止まり、軽く振動。ここで離すと元に戻る（誤操作の歯止め）。「さらに縮めると地図」と出る
/// - **撮影地の無い写真**では段で止まるだけ（地図へは行かない）
/// - 「地図で見る ›」は残す（指を使わない人・読み上げの道）
enum PinchToMap {

    /// 段（ここまでは離すと戻る）。指の倍率がこれを下回ると振動して「さらに縮めると地図」
    static let stepScale = 0.85
    /// ここまで縮めて離すと地図へ
    static let openScale = 0.6
    /// 写真の縮みの下限（見た目。章の模型は 0.1 まで）
    static let minDisplayScale = 0.35

    /// 縮めた量（0 = 等倍・1 = 地図へ行ける所）。地図の濃さと写真の縮みに使う
    static func progress(scale: Double) -> Double {
        max(0, min(1, (1 - scale) / (1 - openScale)))
    }

    /// 段を越えたか（振動と「さらに縮めると地図」）
    static func passedStep(scale: Double) -> Bool {
        scale < stepScale
    }

    /// 見た目の写真の倍率。**撮影地が無ければ段で止める**（それより縮まない）。広げる向き（1 より大）は扱わない
    static func displayScale(scale: Double, hasPlace: Bool) -> Double {
        let lower = hasPlace ? minDisplayScale : stepScale
        return max(lower, min(1, scale))
    }

    /// 地図の札を出す濃さ（地図が半分まで引いてきたら）
    static let placeLabelProgress = 0.5

    /// 地図が引いてきたときの下の札（撮影地の名前と「広げると写真へ」）。撮影地が無い・まだ浅いときは nil
    static func placeLabel(location: String?, scale: Double, hasPlace: Bool) -> (place: String, back: String)? {
        guard hasPlace, progress(scale: scale) >= placeLabelProgress else { return nil }
        let place = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (place, L("広げると写真へ", "Spread to go back to the photo"))
    }

    /// 段の振動を鳴らすか。**段を越えて進んだときだけ**（広げて戻すときは鳴らさない・2026-11-12 確かめ役）
    static func buzzes(wasPast: Bool, isPast: Bool) -> Bool {
        !wasPast && isPast
    }

    /// 写真の詳細の「地図で見る ›」を出すか。**撮影地があれば出す**（近くの写真が0枚でも・2026-11-12 確かめ役）。
    /// つまむと地図に気づく口と、指を使わない人の道を兼ねる
    static func showsMapLink(hasPlace: Bool, nearbyCount: Int) -> Bool {
        hasPlace
    }

    /// 離したときに地図へ行くか
    static func opensMap(endScale: Double, hasPlace: Bool) -> Bool {
        hasPlace && endScale <= openScale
    }
}
