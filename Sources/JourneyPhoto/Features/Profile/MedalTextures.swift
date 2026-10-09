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
                   edgeRepeat: MedalTextureLayout.edgeRepeat())
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
