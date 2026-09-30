import Foundation
import UIKit

// Linux では URLSession が別モジュールに居る（`PublicGalleryService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 旅の一冊の1枚（`TripBookCard`）を JPEG に描く。
///
/// 表紙の写真を枠いっぱいに敷き、**下だけ暗くして**白の文字を載せる（一冊の画面の表紙と同じ
/// 見せ方・写真の上には白しか置かない）。表紙の写真が無い・読めないときは黒地に文字だけ。
///
/// **EXIF は持たない**（`UIGraphicsImageRenderer` は元の付帯情報を引き継がない・
/// `TextOverlayRenderer` と同じ）。倍率は 1 に固定する（端末の 3x で9倍の画素にしない）
enum TripBookCardRenderer {

    /// 表紙の写真を読む。**読めなければ nil**（黒地に文字だけの1枚にする）。
    /// 待たせすぎない（共有の準備で画面を止めない）
    static func coverData(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return data
    }

    static func render(_ lines: TripBookCard.Lines, cover: Data?, focal: Photo.FocalPoint?,
                       quality: Double = 0.88) -> Data {
        let size = TripBookCard.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.jpegData(withCompressionQuality: quality) { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            if let cover, let image = UIImage(data: cover) {
                image.draw(in: TripBookCard.coverRect(image: image.size, in: size, focal: focal))
                shadeBottom(size)
            }
            drawText(lines, size: size)
        }
    }

    /// 下の4割を段々に暗くする（全面に膜を掛けると写真が濁る）。最後は地の黒につなげる
    private static func shadeBottom(_ size: CGSize) {
        let top = size.height * 0.55
        let steps = 24
        let band = (size.height - top) / Double(steps)
        for i in 0..<steps {
            let alpha = 0.85 * Double(i + 1) / Double(steps)
            UIColor.black.withAlphaComponent(alpha).setFill()
            UIRectFill(CGRect(x: 0, y: top + band * Double(i), width: size.width, height: band + 1))
        }
    }

    private static func drawText(_ lines: TripBookCard.Lines, size: CGSize) {
        let margin = 72.0
        let white = UIColor.white
        let soft = UIColor(white: 1, alpha: 0.82)
        let display = UIFont(name: JPFont.displayName, size: 84) ?? UIFont.systemFont(ofSize: 84, weight: .bold)
        let mono = UIFont(name: JPFont.monoMediumName, size: 30) ?? UIFont.monospacedSystemFont(ofSize: 30, weight: .medium)
        let eyebrowFont = UIFont(name: JPFont.monoMediumName, size: 26) ?? UIFont.monospacedSystemFont(ofSize: 26, weight: .medium)
        let body = UIFont.systemFont(ofSize: 32, weight: .medium)

        // 下から積む: 数字 → 期間 → 題 → 眉ラベル
        var y = size.height - margin
        let statsHeight = draw(lines.stats, font: body, color: soft, bottom: y, x: margin, width: size.width - margin * 2)
        y -= statsHeight + 18
        let periodHeight = draw(lines.period, font: mono, color: soft, bottom: y, x: margin, width: size.width - margin * 2)
        y -= periodHeight + 22
        let titleHeight = draw(lines.title, font: display, color: white, bottom: y, x: margin, width: size.width - margin * 2)
        y -= titleHeight + 20
        _ = draw(lines.eyebrow, font: eyebrowFont, color: soft, bottom: y, x: margin, width: size.width - margin * 2)

        // 右上に名前（写真の上なので白・控えめに）
        let footer = lines.footer as NSString
        let footerAttributes: [NSAttributedString.Key: Any] = [.font: eyebrowFont, .foregroundColor: soft]
        let footerSize = footer.size(withAttributes: footerAttributes)
        footer.draw(at: CGPoint(x: size.width - margin - footerSize.width, y: margin * 0.8), withAttributes: footerAttributes)
    }

    /// 下端を `bottom` に揃えて、幅の中で折り返して描く。描いた高さを返す
    @discardableResult
    private static func draw(_ text: String, font: UIFont, color: UIColor,
                             bottom: Double, x: Double, width: Double) -> Double {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.boundingRect(with: CGSize(width: width, height: 10_000),
                                         options: .usesLineFragmentOrigin, context: nil)
        let height = bounds.height.rounded(.up)
        string.draw(with: CGRect(x: x, y: bottom - height, width: width, height: height),
                    options: .usesLineFragmentOrigin, context: nil)
        return height
    }
}
