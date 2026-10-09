import Foundation
import UIKit

// メダルを手に取って回す画面（`MedalViewerView`）の貼り絵。
//
// **SwiftUI を読まない。** 描画の `UIColor` は UIKit の側を使う（SwiftUI と両方を読むと、
// Linux の模型では名前が割れる・`TripBookCardRenderer` と同じ形）

// MARK: - 貼り絵の寸法（画面に依らない・テストで見張る）

/// 硬貨の寸法と、表・裏・縁の貼り絵の置き方。
///
/// 円柱の面には四角い絵の内接円が貼られる（SceneKit の平面の角を半径いっぱいに丸めて円にする）。
/// だから**絵の円の部分が四角いっぱいになるよう拡大して描く**（円の外の余白・後光は切り落とす）
enum MedalTextureLayout {
    /// 貼り絵の一辺（px）。画面に出る硬貨は最大 360pt＝3倍で約 1080px
    static let textureSide: Double = 1024

    /// 裏の絵（`reverse-<metal>.png`）のうち、硬貨の円が占める割合（素材を測って 0.915）
    static let reverseDiscRatio: Double = 0.915

    /// 板の基準: 300pt の面で、無料のメダルの円の半径は 147.6
    static let boardDiscRadius: Double = 147.6
    /// 硬貨の厚み（板: 18pt）。半径に対する比で持つ
    static let thicknessPerRadius: Double = 18 / boardDiscRadius

    /// 裏に重ねる名前と日付の中心（板: 中心から下へ +86 / +102・300pt の面で）と字の大きさ（16 / 11）
    static let nameOffset: Double = 86
    static let dateOffset: Double = 102
    static let nameFont: Double = 16
    static let dateFont: Double = 11
    /// 名前に使える幅（円の直径に対する割合）。はみ出す名前は縮め、それでも長ければ切る
    static let nameMaxWidth: Double = 0.62

    /// 縁の帯（`edge-<metal>.png`）は 858pt 分の長さ。円周にこの回数だけ繰り返して巻く
    static let edgeStripLength: Double = 858

    /// 画面の硬貨の一辺（pt）。左右に 20pt ずつ空け、大きすぎない
    static func coinSide(screenWidth: Double) -> Double {
        max(160, min(screenWidth - 40, 360))
    }

    /// 初期ユーザーの後光の一辺（硬貨の 1.3 倍）。**画面の幅を超える**（430pt の画面で 468pt）ので、
    /// 組みの大きさに効かせない（`MedalViewerView` は硬貨の背景に置く）
    static func haloSide(coin: Double) -> Double { coin * 1.3 }

    /// 絵の円が `side` の四角いっぱいになる描き方（中心に置いて拡大する）
    static func fillRect(discRatio: Double, side: Double = textureSide) -> CGRect {
        let drawn = side / discRatio
        let origin = (side - drawn) / 2
        return CGRect(x: origin, y: origin, width: drawn, height: drawn)
    }

    /// 板の 300pt の面の長さを、貼り絵の px に（円の半径 147.6 が貼り絵の半分）
    static func boardToTexture(_ value: Double, side: Double = textureSide) -> Double {
        value * (side / 2) / boardDiscRadius
    }

    /// 名前・日付の中心の高さ（貼り絵の上から）
    static func nameCenterY(side: Double = textureSide) -> Double { side / 2 + boardToTexture(nameOffset, side: side) }
    static func dateCenterY(side: Double = textureSide) -> Double { side / 2 + boardToTexture(dateOffset, side: side) }

    /// 名前の字の大きさ。**幅に収まらなければ縮める**（板の 7 割まで）
    static func nameFontSize(textWidthAtBase: Double, side: Double = textureSide) -> Double {
        let base = boardToTexture(nameFont, side: side)
        let limit = side * nameMaxWidth
        guard textWidthAtBase > limit, textWidthAtBase > 0 else { return base }
        return max(base * 0.7, base * limit / textWidthAtBase)
    }

    /// 縁の帯の繰り返しの回数（円周 ÷ 帯の長さ）。半径は板の 300pt の面で
    static func edgeRepeat(discRadius: Double = boardDiscRadius) -> Double {
        2 * Double.pi * discRadius / edgeStripLength
    }
}

// MARK: - 貼り絵を描く

/// 表・裏・縁の貼り絵。**重くないので画面の処理で描く**（1024px を2枚・数十ms）
enum MedalTextures {

    struct Faces {
        let front: UIImage?
        let back: UIImage?
        let edge: UIImage?
        let edgeRepeat: Double
        /// 金属（光の映り込みの色を決める）
        var metal: BadgeCatalog.Metal = .silver
    }

    static func make(badge: EarnedBadge, ownerName: String) -> Faces {
        let metal = BadgeCatalog.metal(badge.key, tier: badge.tier)
        let front = UIImage(named: BadgeCatalog.largeImage(badge.key, tier: badge.tier)).map {
            disc($0, ratio: BadgeCatalog.discRatio(badge.key))
        }
        let back = UIImage(named: metal.reverseImage).map {
            reverse($0, name: ownerName, date: BadgeCatalog.awardDate(badge.at))
        }
        return Faces(front: front, back: back, edge: UIImage(named: metal.edgeImage),
                   edgeRepeat: MedalTextureLayout.edgeRepeat(), metal: metal)
    }

    private static func renderer() -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        // 倍率は 1（端末の 3x で9倍の画素にしない・`TripBookCardRenderer` と同じ）
        format.scale = 1
        let side = MedalTextureLayout.textureSide
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    }

    /// 表: 円の部分が四角いっぱいになるよう拡大（後光・余白は切り落とす）
    static func disc(_ image: UIImage, ratio: Double) -> UIImage {
        renderer().image { _ in
            image.draw(in: MedalTextureLayout.fillRect(discRatio: ratio))
        }
    }

    /// 裏: 金属の絞り羽根に、名前（明朝）と日付（等幅の数字）を重ねる
    static func reverse(_ image: UIImage, name: String, date: String?) -> UIImage {
        let side = MedalTextureLayout.textureSide
        // 板の文字の色（淡い真鍮）
        let gold = UIColor(red: 233 / 255, green: 207 / 255, blue: 150 / 255, alpha: 1)
        return renderer().image { _ in
            image.draw(in: MedalTextureLayout.fillRect(discRatio: MedalTextureLayout.reverseDiscRatio))

            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let base = MedalTextureLayout.boardToTexture(MedalTextureLayout.nameFont)
                let measure = font(display: base)
                let width = Double((trimmed as NSString).size(withAttributes: [.font: measure]).width)
                let size = MedalTextureLayout.nameFontSize(textWidthAtBase: width)
                drawCentered(trimmed, font: font(display: size), color: gold, kern: 0,
                             centerY: MedalTextureLayout.nameCenterY(), maxWidth: side * MedalTextureLayout.nameMaxWidth)
            }
            if let date {
                let size = MedalTextureLayout.boardToTexture(MedalTextureLayout.dateFont)
                drawCentered(date, font: UIFont.monospacedDigitSystemFont(ofSize: size, weight: .medium),
                             color: gold.withAlphaComponent(0.8), kern: size * 0.16,
                             centerY: MedalTextureLayout.dateCenterY(), maxWidth: side)
            }
        }
    }

    private static func font(display size: Double) -> UIFont {
        UIFont(name: JPFont.displayName, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
    }

    private static func drawCentered(_ text: String, font: UIFont, color: UIColor, kern: Double,
                                     centerY: Double, maxWidth: Double) {
        let side = MedalTextureLayout.textureSide
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        var shown = text
        // 縮めても収まらない名前は末尾を「…」にする（円の外へはみ出させない）
        while shown.count > 1,
              Double((shown as NSString).size(withAttributes: attributes).width) > maxWidth {
            shown = String(shown.dropLast(2)) + "…"
        }
        let size = (shown as NSString).size(withAttributes: attributes)
        let point = CGPoint(x: (side - Double(size.width)) / 2, y: centerY - Double(size.height) / 2)
        (shown as NSString).draw(at: point, withAttributes: attributes)
    }
}

// MARK: - 凹凸（法線の絵）

/// 硬貨の面の傾きを決める法線の絵（normal map）を作る（2026-10-09）。
///
/// 絵を平らな板に貼っただけだと、回しても光が面を流れず、のっぺり見える（owner:
/// 「3D回転させた時の立体感たりない・表も裏ものっぺりしてる」）。そこで**面を少しふくらませる**
/// （本物のメダルのように中心が高い）。回すと光が面を横切る。
///
/// **表と裏には絵の明るさから凹凸を起こさない。** 明るい所を高くする作りを試したが、文字や網目まで
/// 盛り上がってざらつき、owner が「凹凸の立体感が少し気持ち悪い」と言った。比べる試作
/// （https://claude.ai/artifact/C7gyZEE2VzgMqcMnZcQvvR）で owner が「B（凹凸なし・ふくらみ・
/// 映り込み）、ただし光の反射は控えめ」を選んだ。明るさの凹凸を使うのは縁のギザの帯だけ。
///
/// **画像の型を読まない**（数の配列だけ）ので Linux のテストで見張れる
enum MedalRelief {
    /// 法線の絵の一辺（px）。貼り絵（1024）の半分で足りる（光の具合はなめらかなので）
    static let side = 512
    /// 凹凸の強さ（大きいほど傾く）
    static let strength: Double = 1.1
    /// 面のふくらみ（中心と縁の高さの差・明るさ 0〜1 と同じ物差し）
    static let dome: Double = 0.22
    /// 縁の帯の凹凸の強さ（ギザの溝に光が乗る程度）
    static let edgeStrength: Double = 0.8
    /// 表と裏で明るさを高さに使う割合。**0＝凹凸を起こさない**（owner の選択）
    static let faceRelief: Double = 0
    /// ぼかしの半径（箱ぼかしを3回重ねて σ≈2.4px）
    static let blurRadius = 2
    static let blurPasses = 3

    /// 明るさ（0〜255・行ごと・上から）から、法線の絵（RGBA・1画素4バイト）を作る。
    /// `relief` は明るさを高さに使う割合（0 なら明るさは見ず、ふくらみだけ）。
    ///
    /// 法線は「右＝+x・上＝+y・手前＝+z」で、`色 = 法線 × 0.5 + 0.5`（緑が上向き）。
    /// `wrapsX` は縁の帯のように左右がつながる絵（端の傾きを向こう側の画素で計る）。
    /// `dome` を 0 にするとふくらみを付けない
    static func normalMap(luminance: [UInt8], width: Int, height: Int,
                          strength: Double, dome: Double, relief: Double = 1,
                          wrapsX: Bool = false) -> [UInt8] {
        guard width > 2, height > 2, luminance.count == width * height else { return [] }
        var h = luminance.map { Double($0) / 255 * relief }
        if relief != 0 {
            for _ in 0..<blurPasses {
                h = boxBlur(h, width: width, height: height, radius: blurRadius, wrapsX: wrapsX)
            }
        }
        if dome != 0 {
            let cx = Double(width - 1) / 2, cy = Double(height - 1) / 2
            let radius = Double(min(width, height)) / 2
            for y in 0..<height {
                for x in 0..<width {
                    let dx = (Double(x) - cx) / radius, dy = (Double(y) - cy) / radius
                    h[y * width + x] -= dome * (dx * dx + dy * dy)
                }
            }
        }
        // 傾きは画素の差 × 半分の幅（絵の大きさに依らない強さにする）
        let scale = strength * Double(min(width, height)) / 2
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let up = max(0, y - 1), down = min(height - 1, y + 1)
            for x in 0..<width {
                let left = wrapsX ? (x - 1 + width) % width : max(0, x - 1)
                let right = wrapsX ? (x + 1) % width : min(width - 1, x + 1)
                let gx = (h[y * width + right] - h[y * width + left]) / Double(right > left ? right - left : 2)
                let gy = (h[down * width + x] - h[up * width + x]) / Double(max(1, down - up))
                // 右へ高くなる＝面は左を向く（-x）。下へ高くなる＝面は上を向く（+y）
                var nx = -gx * scale, ny = gy * scale, nz = 1.0
                let length = (nx * nx + ny * ny + nz * nz).squareRoot()
                nx /= length; ny /= length; nz /= length
                let i = (y * width + x) * 4
                out[i] = encode(nx)
                out[i + 1] = encode(ny)
                out[i + 2] = encode(nz)
            }
        }
        return out
    }

    private static func encode(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 0.5 + 0.5) * 255).rounded()))
    }

    /// 縦横に分けた箱ぼかし（端は端の画素を伸ばす。`wrapsX` なら左右は向こう側へつなぐ）
    static func boxBlur(_ values: [Double], width: Int, height: Int, radius: Int, wrapsX: Bool) -> [Double] {
        guard radius > 0 else { return values }
        let count = Double(radius * 2 + 1)
        var horizontal = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var sum = 0.0
                for k in -radius...radius {
                    let sx = wrapsX ? ((x + k) % width + width) % width : min(width - 1, max(0, x + k))
                    sum += values[row + sx]
                }
                horizontal[row + x] = sum / count
            }
        }
        var out = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for k in -radius...radius {
                    sum += horizontal[min(height - 1, max(0, y + k)) * width + x]
                }
                out[y * width + x] = sum / count
            }
        }
        return out
    }
}
