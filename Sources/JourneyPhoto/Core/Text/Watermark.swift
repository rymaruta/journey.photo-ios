import Foundation

/// SNS に渡す画像に入れる「Journey Photo」の透かし（owner 2026-10-02「Journey Photo の透かし入れたい」）。
///
/// **入れるのは SNS に渡す画像だけ。** サイト・アプリに載る写真には入れない（写真が主役）。
/// 右下に、白で控えめに。大きさは写真の短い辺に対する割合で決める（小さい写真でも読める下限つき）。
/// **形はロゴそのまま**（アパーチャのマーク＋New York Bold・字間 -0.025em・`docs/BRAND.md` §1）。
/// 最初は明朝で描いていたが、ロゴの書体は New York だった（2026-10-02 のレビュー・書体の案 A）
/// 描くのは `WatermarkRenderer`。ここは大きさと置き場所だけ（テストで確かめる）
enum Watermark {

    static let text = "Journey Photo"
    /// 字の大きさ＝短い辺 × この割合（1080px の写真で約 49px）。
    /// 3.2% から上げた（2026-10-02 owner「A だね、もう少し大きい方がいいのでは？」）
    static let scale = 0.045
    /// 小さすぎて読めなくならない下限（px）
    static let minFontSize = 14.0
    /// 白の濃さ。写真を邪魔しない程度に
    static let alpha = 0.78
    /// 書き出す長い辺の上限（px）。SNS 側で縮められる大きさを越えて重くしない
    static let maxLongSide = 2048.0

    /// 字の大きさ（px）
    static func fontSize(canvas: CGSize) -> Double {
        max(minFontSize, Double(min(canvas.width, canvas.height)) * scale)
    }

    /// マークの一辺（px）。ロゴと同じく字の大きさに対する割合（ヘッダーは 22pt の字に 19pt の枠）
    static func markSize(fontSize: Double) -> Double {
        fontSize * 19 / 22
    }

    /// マークと字の間（px）。ロゴと同じ割合（22pt に 8pt）
    static func markGap(fontSize: Double) -> Double {
        fontSize * 8 / 22
    }

    /// 字間（px）。ロゴと同じ -0.025em
    static func tracking(fontSize: Double) -> Double {
        -fontSize * 0.025
    }

    /// 端からの余白（px）。字の大きさに比例
    static func margin(fontSize: Double) -> Double {
        fontSize * 0.9
    }

    /// 書き出す大きさ。長い辺が `maxLongSide` を超えるときだけ縮める（縦横比は保つ）
    static func outputSize(image: CGSize) -> CGSize {
        let long = Double(max(image.width, image.height))
        guard long > maxLongSide, long > 0 else { return image }
        let ratio = maxLongSide / long
        return CGSize(width: (Double(image.width) * ratio).rounded(), height: (Double(image.height) * ratio).rounded())
    }

    /// 字の左上の位置（右下に寄せる）
    static func origin(text: CGSize, canvas: CGSize, margin: Double) -> CGPoint {
        CGPoint(x: Double(canvas.width) - margin - Double(text.width),
                y: Double(canvas.height) - margin - Double(text.height))
    }
}
