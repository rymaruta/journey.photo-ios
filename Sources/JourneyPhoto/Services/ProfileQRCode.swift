import CoreImage
import ImageIO
import Foundation
import UIKit

/// プロフィールの QR の絵（札 #545・2026-11-11）。
///
/// - `image(for:)`: 端末の Core Image（`CIQRCodeGenerator`）で作る。**1画素＝1マス**の白黒で、周りの静かな余白
///   （4マス）を含む。画面では補わずに（`interpolation(.none)`）広げて角を立てる
/// - `card(...)`: 「保存」で写真に足す1枚（PNG・1080×1350）。黒地に白の板の QR、真鍮の角の飾り、名前と @名、
///   下に小さくワードマーク。QR は角をにじませないよう補わずに広げる。**付帯情報（位置など）は持たない**
///
/// 誤り訂正は M（15%）。中身は短い URL だけなので M で十分に粗く、離れても読みやすい
enum ProfileQRCode {

    static let correctionLevel = "M"

    static func image(for text: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    // MARK: - 保存する1枚

    /// 縦長 4:5（写真の一覧で切れにくい・インスタの縦の投稿と同じ形）
    static let cardSize = CGSize(width: 1080, height: 1350)
    /// 白の板の一辺と、板の内側の余白（QR の静かな余白とは別に、白の縁を少し足す）
    static let plateSide: Double = 720
    static let plateInset: Double = 36
    static let plateTop: Double = 210

    static func card(qr: CGImage, name: String?, handle: String?, link: String) -> Data {
        let size = cardSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.pngData { context in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let plate = CGRect(x: (size.width - plateSide) / 2, y: plateTop, width: plateSide, height: plateSide)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: plate, cornerRadius: 40).fill()
            // 補わずに広げる（ぼかすと読み取りが落ちる）
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: qr).draw(in: plate.insetBy(dx: plateInset, dy: plateInset))
            drawCorners(around: plate.insetBy(dx: -28, dy: -28))
            var y = plate.maxY + 72
            if let name, !name.isEmpty {
                let font = UIFont(name: JPFont.displayName, size: 60) ?? UIFont.systemFont(ofSize: 60, weight: .bold)
                y += drawCentered(name, font: font, color: .white, y: y, width: size.width) + 12
            }
            if let handle, !handle.isEmpty {
                y += drawCentered(handle, font: UIFont.systemFont(ofSize: 34, weight: .medium),
                                  color: UIColor(white: 1, alpha: 0.6), y: y, width: size.width) + 8
            }
            _ = drawCentered(link, font: UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium),
                             color: brass, y: y, width: size.width)
            _ = drawCentered("Journey Photo", font: wordmarkFont, color: .white, y: size.height - 120, width: size.width)
        }
    }

    /// 真鍮（#C9A66B）。**黒地の上だけ**（板の決まり）——飾りと URL は白の板の外の黒地に置く
    private static var brass: UIColor { UIColor(red: 201 / 255, green: 166 / 255, blue: 107 / 255, alpha: 1) }

    /// ワードマーク（New York Bold・白1色・板の決まり）
    private static var wordmarkFont: UIFont {
        let base = UIFont.systemFont(ofSize: 40, weight: .bold)
        guard let serif = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: serif, size: 40)
    }

    /// 板の外の四隅に真鍮の L 字（ファインダーの角の形）。線の太さ 6・腕の長さ 64
    private static func drawCorners(around rect: CGRect) {
        let arm: Double = 64, line: Double = 6
        brass.setFill()
        for (x, y, dx, dy) in [(rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0),
                               (rect.minX, rect.maxY, 1.0, -1.0), (rect.maxX, rect.maxY, -1.0, -1.0)] {
            UIRectFill(CGRect(x: dx > 0 ? x : x - arm, y: dy > 0 ? y : y - line, width: arm, height: line))
            UIRectFill(CGRect(x: dx > 0 ? x : x - line, y: dy > 0 ? y : y - arm, width: line, height: arm))
        }
    }

    /// 1行を真ん中に描いて、その高さを返す（長い名前は「…」で切る）
    private static func drawCentered(_ text: String, font: UIFont, color: UIColor, y: Double, width: Double) -> Double {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color,
                                                                   .paragraphStyle: style])
        let height = font.lineHeight.rounded(.up) + 4
        string.draw(with: CGRect(x: 80, y: y, width: width - 160, height: height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        return height
    }
}
