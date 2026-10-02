import Foundation
import UIKit

// Linux では URLSession が別モジュールに居る（`PublicGalleryService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 旅の一冊の1枚（`TripBookCard`）を JPEG に描く。
///
/// 表紙の写真を枠いっぱいに敷き、**文字の上から下だけを暗くして**白の文字を載せる（一冊の画面の
/// 表紙と同じ見せ方・写真の上には白しか置かない）。表紙の写真が無い・読めないときは黒地に文字だけ。
///
/// **EXIF は持たない**（`UIGraphicsImageRenderer` は元の付帯情報を引き継がない・
/// `TextOverlayRenderer` と同じ）。倍率は 1 に固定する（端末の 3x で9倍の画素にしない）。
/// 重いので**画面の処理の外で**呼ぶ（`TripBookView.makeCard`）
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
        let fonts = Fonts()
        let block = measure(lines, fonts: fonts, width: size.width - TripBookCard.margin * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.jpegData(withCompressionQuality: quality) { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            if let image = coverImage(cover, filling: size) {
                image.draw(in: TripBookCard.coverRect(image: image.size, in: size, focal: focal))
                shade(from: TripBookCard.shadeTop(textTop: block.top, canvasHeight: size.height), size: size)
            }
            drawText(lines, block: block, fonts: fonts, size: size)
        }
    }

    // MARK: - 表紙

    /// 枠を埋めるのに要る大きさまで**縮めて**展開する（元の大きさの写真を丸ごと展開しない）
    private static func coverImage(_ data: Data?, filling canvas: CGSize) -> UIImage? {
        guard let data, let image = UIImage(data: data) else { return nil }
        let target = TripBookCard.fillSize(image: image.size, canvas: canvas)
        guard target.width < image.size.width else { return image }
        return image.preparingThumbnail(of: target) ?? image
    }

    /// `top` から下を段々に暗くする。**帯は重ねない**（重なった行だけ2度塗られて縞になった）
    private static func shade(from top: Double, size: CGSize) {
        let steps = TripBookCard.shadeSteps
        for i in 0..<steps {
            let y0 = (top + (size.height - top) * Double(i) / Double(steps)).rounded()
            let y1 = (top + (size.height - top) * Double(i + 1) / Double(steps)).rounded()
            guard y1 > y0 else { continue }
            UIColor.black.withAlphaComponent(TripBookCard.shadeAlpha(step: i)).setFill()
            UIRectFill(CGRect(x: 0, y: y0, width: size.width, height: y1 - y0))
        }
    }

    // MARK: - 文字

    private struct Fonts {
        let display = UIFont(name: JPFont.displayName, size: 84) ?? UIFont.systemFont(ofSize: 84, weight: .bold)
        /// 数字と眉ラベルは SF Pro の等幅数字（画面の `JPFont.mono` と同じ・2026-10-02）。
        /// 焼き込む絵は大きさが決まっているので Dynamic Type には追従させない
        let mono = UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .medium)
        let eyebrow = UIFont.monospacedDigitSystemFont(ofSize: 26, weight: .medium)
        let body = UIFont.systemFont(ofSize: 32, weight: .medium)
    }

    /// 各行の高さと、文字のかたまりの上端。**題は2行まで**（長い撮影地名で上にはみ出さない）
    private struct Block {
        let eyebrow: Double
        let title: Double
        let period: Double
        let stats: Double
        let top: Double
    }

    private static func measure(_ lines: TripBookCard.Lines, fonts: Fonts, width: Double) -> Block {
        let eyebrow = height(lines.eyebrow, font: fonts.eyebrow, width: width, maxLines: 1)
        let title = height(lines.title, font: fonts.display, width: width, maxLines: TripBookCard.titleMaxLines)
        let period = height(lines.period, font: fonts.mono, width: width, maxLines: 2)
        let stats = height(lines.stats, font: fonts.body, width: width, maxLines: 2)
        let top = TripBookCard.textTop(canvasHeight: TripBookCard.size.height,
                                       heights: [eyebrow, title, period, stats])
        return Block(eyebrow: eyebrow, title: title, period: period, stats: stats, top: top)
    }

    private static func height(_ text: String, font: UIFont, width: Double, maxLines: Int) -> Double {
        let string = NSAttributedString(string: text, attributes: [.font: font])
        let limit = font.lineHeight * Double(maxLines) + 1
        let bounds = string.boundingRect(with: CGSize(width: width, height: limit),
                                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        return min(bounds.height.rounded(.up), limit.rounded(.up))
    }

    private static func drawText(_ lines: TripBookCard.Lines, block: Block, fonts: Fonts, size: CGSize) {
        let margin = TripBookCard.margin
        let width = size.width - margin * 2
        let white = UIColor.white
        let soft = UIColor(white: 1, alpha: 0.82)
        // 上から: 眉ラベル → 題 → 期間 → 数字（高さは測ったとおり・間は `TripBookCard.gaps`）
        var y = block.top
        draw(lines.eyebrow, font: fonts.eyebrow, color: soft, x: margin, y: y, width: width, height: block.eyebrow)
        y += block.eyebrow + TripBookCard.gaps[0]
        draw(lines.title, font: fonts.display, color: white, x: margin, y: y, width: width, height: block.title)
        y += block.title + TripBookCard.gaps[1]
        draw(lines.period, font: fonts.mono, color: soft, x: margin, y: y, width: width, height: block.period)
        y += block.period + TripBookCard.gaps[2]
        draw(lines.stats, font: fonts.body, color: soft, x: margin, y: y, width: width, height: block.stats)

        // 右上に名前（写真の上なので白・控えめに）
        let footer = lines.footer as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: fonts.eyebrow, .foregroundColor: soft]
        let footerSize = footer.size(withAttributes: attributes)
        footer.draw(at: CGPoint(x: size.width - margin - footerSize.width, y: margin * 0.8), withAttributes: attributes)
    }

    /// 枠の中に折り返して描く。収まらない最後の行は「…」で切る
    private static func draw(_ text: String, font: UIFont, color: UIColor,
                             x: Double, y: Double, width: Double, height: Double) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        string.draw(with: CGRect(x: x, y: y, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
}
