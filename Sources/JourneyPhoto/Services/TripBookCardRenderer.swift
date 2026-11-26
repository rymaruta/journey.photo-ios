import Foundation
import UIKit

// Linux では URLSession が別モジュールに居る（`PublicGalleryService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 旅の一冊の1枚（`TripBookCard`）を JPEG に描く。
///
/// 表紙の写真を枠いっぱいに敷き、**文字の上から下だけを、写真の上に重ねたグラデーションで暗くして**
/// 白の文字を載せる（板「TripBookShare」B の表紙カード・写真の上には白しか置かない）。
/// 表紙の写真が無い・読めないときは黒地に文字だけ。
///
/// 上から: 眉ラベル「TRIP BOOK」→ 題（明朝・1行に入るまで縮める）→ 地域（「宮城県白石市」）→
/// 期間 → 数字 → サイトの名前。サイトの名前は前は右上に置いていたが、明るい空の上では読めなかったので、
/// 暗くした下の端へ移した（板の表紙カードと同じ所・2026-11-26 判断）。
///
/// **EXIF は持たない**（`UIGraphicsImageRenderer` は元の付帯情報を引き継がない・
/// `TextOverlayRenderer` と同じ）。倍率は 1 に固定する（端末の 3x で9倍の画素にしない）。
/// **不透明の絵として描く**（`opaque`）——透明を持たないので、JPEG にしたときに白の地に重ならない。
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
        let layout = Layout(lines, width: size.width - TripBookCard.margin * 2, canvasHeight: size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.jpegData(withCompressionQuality: quality) { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let image = coverImage(cover, filling: size) {
                image.draw(in: TripBookCard.coverRect(image: image.size, in: size, focal: focal))
                shade(context.cgContext, top: TripBookCard.shadeTop(textTop: layout.top, canvasHeight: size.height),
                      textTop: layout.top, size: size)
            }
            drawText(lines, layout: layout)
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

    /// `top` から下を、写真の上に**重ねて**ひと続きに暗くする（止めは `TripBookCard.shadeStops`）。
    /// 🔴 `UIRectFill` では塗らない——置き換え（copy）で塗るので、写真が消えて白→灰の帯になった（2026-11-26）
    private static func shade(_ cg: CGContext, top: Double, textTop: Double, size: CGSize) {
        #if !os(Linux)
        // Linux の SDK 模型には CoreGraphics のグラデーションが無い。描くのは iOS の Xcode で確かめる
        // （`TripBookCardRendererTests`・`SignatureShareCardRenderer` と同じ）
        let stops = TripBookCard.shadeStops(top: top, textTop: textTop, bottom: size.height)
        let colors = stops.map { UIColor.black.withAlphaComponent($0.alpha).cgColor } as CFArray
        let locations = stops.map { CGFloat($0.location) }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: locations) else { return }
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: size.height), options: [])
        #endif
    }

    // MARK: - 文字

    private enum Fonts {
        static func display(_ size: Double) -> UIFont {
            UIFont(name: JPFont.displayName, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
        }
        /// 数字と眉ラベルは SF Pro の等幅数字（画面の `JPFont.mono` と同じ・2026-10-02）。
        /// 焼き込む絵は大きさが決まっているので Dynamic Type には追従させない
        /// 字は描く処理の中で作る（`UIFont` は Sendable ではないので static let に置かない）
        static var eyebrow: UIFont { .monospacedDigitSystemFont(ofSize: TripBookCard.Font.eyebrow, weight: .semibold) }
        static var period: UIFont { .monospacedDigitSystemFont(ofSize: TripBookCard.Font.period, weight: .medium) }
        static var stats: UIFont { .systemFont(ofSize: TripBookCard.Font.stats, weight: .medium) }
        static var footer: UIFont { .systemFont(ofSize: TripBookCard.Font.footer, weight: .semibold) }
        static func region(_ size: Double) -> UIFont { UIFont.systemFont(ofSize: size, weight: .medium) }
    }

    /// 眉ラベルの字の間（板の letter-spacing .14em）
    private static let eyebrowKern = TripBookCard.Font.eyebrow * 0.14

    /// 置き方を先に決める（暗くし始める高さは文字の上端から決まる）
    private struct Layout {
        let width: Double
        let title: ShareCardText.Fitted
        let region: ShareCardText.Fitted
        let periodHeight: Double
        let statsHeight: Double
        let top: Double

        init(_ lines: TripBookCard.Lines, width: Double, canvasHeight: Double) {
            self.width = width
            title = TripBookCard.titleFit(lines.title, width: width) { text, size in
                TripBookCardRenderer.width(text, font: Fonts.display(size))
            }
            region = TripBookCard.regionFit(lines.region, width: width) { text, size in
                TripBookCardRenderer.width(text, font: Fonts.region(size))
            }
            periodHeight = TripBookCardRenderer.height(lines.period, font: Fonts.period, width: width, maxLines: 2)
            statsHeight = TripBookCardRenderer.height(lines.stats, font: Fonts.stats, width: width, maxLines: 2)
            let regionHeight = region.lines.isEmpty ? 0 : Fonts.region(region.size).lineHeight
            top = TripBookCard.textTop(
                canvasHeight: canvasHeight,
                heights: [Fonts.eyebrow.lineHeight, Self.titleHeight(title), regionHeight,
                          periodHeight, statsHeight, Fonts.footer.lineHeight],
                gaps: [TripBookCard.gapAfterEyebrow, region.lines.isEmpty ? 0 : TripBookCard.gapAfterTitle,
                       TripBookCard.gapBeforePeriod, TripBookCard.gapAfterPeriod, TripBookCard.gapBeforeFooter])
        }

        static func titleHeight(_ fitted: ShareCardText.Fitted) -> Double {
            Fonts.display(fitted.size).lineHeight * Double(max(1, fitted.lines.count))
        }
    }

    private static func width(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func height(_ text: String, font: UIFont, width: Double, maxLines: Int) -> Double {
        let string = NSAttributedString(string: text, attributes: [.font: font])
        let limit = font.lineHeight * Double(maxLines) + 1
        let bounds = string.boundingRect(with: CGSize(width: width, height: limit),
                                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        return min(bounds.height.rounded(.up), limit.rounded(.up))
    }

    private static func drawText(_ lines: TripBookCard.Lines, layout: Layout) {
        let x = TripBookCard.margin
        let white = UIColor.white
        // 板の表紙カード: 眉ラベル .88・期間 .85・サイト名 .7（写真の上は白だけ）
        let eyebrowColor = UIColor(white: 1, alpha: 0.88)
        let soft = UIColor(white: 1, alpha: 0.86)
        let faint = UIColor(white: 1, alpha: 0.72)
        var y = layout.top
        (lines.eyebrow as NSString).draw(at: CGPoint(x: x, y: y),
                                         withAttributes: [.font: Fonts.eyebrow, .foregroundColor: eyebrowColor,
                                                          .kern: eyebrowKern])
        y += Fonts.eyebrow.lineHeight + TripBookCard.gapAfterEyebrow
        // 題は**折った行を1行ずつ**描く（UIKit に折らせると和文を字の間で折る・`ShareCardText`）
        let titleFont = Fonts.display(layout.title.size)
        for line in layout.title.lines {
            (line as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: titleFont, .foregroundColor: white])
            y += titleFont.lineHeight
        }
        if let region = layout.region.lines.first {
            y += TripBookCard.gapAfterTitle
            let font = Fonts.region(layout.region.size)
            (region as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: soft])
            y += font.lineHeight
        }
        y += TripBookCard.gapBeforePeriod
        draw(lines.period, font: Fonts.period, color: soft, x: x, y: y, width: layout.width, height: layout.periodHeight)
        y += layout.periodHeight + TripBookCard.gapAfterPeriod
        draw(lines.stats, font: Fonts.stats, color: soft, x: x, y: y, width: layout.width, height: layout.statsHeight)
        y += layout.statsHeight + TripBookCard.gapBeforeFooter
        (lines.footer as NSString).draw(at: CGPoint(x: x, y: y),
                                        withAttributes: [.font: Fonts.footer, .foregroundColor: faint])
    }

    /// 枠の中に折り返して描く。収まらない最後の行は「…」で切る
    private static func draw(_ text: String, font: UIFont, color: UIColor,
                             x: Double, y: Double, width: Double, height: Double) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        string.draw(with: CGRect(x: x, y: y, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
}
