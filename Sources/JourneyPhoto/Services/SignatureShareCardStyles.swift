#if !os(Linux)
import UIKit
import CoreLocation

/// SNS 共有カードの型（2026-11-06 owner「iOS の SNS に載せるデザインの種類が2つしかないので、めっちゃいいのを考えて増やして」）。
///
/// 帯（既定）・フェードに、**展示札・表紙**を足す。見本は Artifact「SNS 共有カード 新デザイン5案」（S2 展示札・F5 表紙）。
/// 寸法は `ShareCardMap` の `LabelLayout` / `CoverLayout` に1か所で持つ。帯の型の描き方（テストが固定している数）には触れない。
///
/// 2026-11-06 判断: 一度「切り欠き」（帯の右端が写真へ食い込む型）を作ったが、owner「写真の雰囲気を壊している」で外した。
/// 写真の上に黒い面を重ねる型は作らない（写真は壊さない・黒い面は写真の外に置く）。
extension SignatureShareCardRenderer {
    // MARK: - 部品

    /// 縦のグラデーション（黒・上から下）。`stops` は 0〜1 の位置と黒の濃さ。範囲の外には描かない
    static func drawShade(_ cg: CGContext, from y0: CGFloat, to y1: CGFloat,
                          stops: [(location: CGFloat, alpha: CGFloat)]) {
        let colors = stops.map { UIColor.black.withAlphaComponent($0.alpha).cgColor } as CFArray
        let locations = stops.map { $0.location }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: locations) else { return }
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [])
    }

    /// 写真を、縦横比を保って枠いっぱいに敷く（はみ出しは枠で切る）
    static func drawPhotoFill(_ photo: UIImage, in rect: CGRect, context cg: CGContext) {
        let scale = max(rect.width / photo.size.width, rect.height / photo.size.height)
        cg.saveGState()
        cg.clip(to: rect)
        photo.draw(in: CGRect(x: rect.midX - photo.size.width * scale / 2,
                              y: rect.midY - photo.size.height * scale / 2,
                              width: photo.size.width * scale, height: photo.size.height * scale))
        cg.restoreGState()
    }

    /// 上の見出し（ロゴのマークと字・右の一文と Web の住所）。縦の中心は centerY
    static func drawBrandHeader(centerY: CGFloat, left: CGFloat, right: CGFloat, taglineSize: CGFloat,
                                addressColor: UIColor) {
        let markSize = ShareCardMap.Layout.headerMarkSize
        let markRect = CGRect(x: left, y: centerY - markSize / 2, width: markSize, height: markSize)
        if ShareCardProbe.note(.logo, "BrandMark", rect: markRect),
           let mark = UIImage(named: "BrandMark")?.withRenderingMode(.alwaysTemplate) {
            mark.withTintColor(.white).draw(in: markRect)
        }
        draw("Journey Photo",
             at: CGPoint(x: left + markSize + 17, y: wordmarkTop(markMidY: centerY)),
             maxWidth: 365, size: 39, color: .white, serif: true)
        drawTaglineAndAddress(centerY: centerY, right: right, taglineSize: taglineSize, addressColor: addressColor)
    }

    /// 真鍮の額縁（画像の端から 12 内側・3px）。黒い地の上だけに置く型で使う
    static func drawBrassFrame(size: CGSize, context cg: CGContext) {
        let inset = ShareCardMap.Layout.frameInset
        let width = ShareCardMap.Layout.frameWidth
        cg.setStrokeColor(brass.withAlphaComponent(0.9).cgColor)
        cg.setLineWidth(width)
        cg.stroke(CGRect(x: inset + width / 2, y: inset + width / 2,
                         width: size.width - 2 * inset - width, height: size.height - 2 * inset - width))
    }

    /// 撮影情報の字（カメラ・レンズ・撮影値）。空の項目は空文字
    static func exifValues(_ credit: Credit) -> (camera: String, lens: String, exposure: String) {
        let camera = credit.camera?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lens = credit.lens?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let exposure = [credit.aperture, credit.exposure, credit.iso.map { "ISO\($0)" }]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "  ")
        return (camera, lens, exposure)
    }

    /// 地名を1行にしたもの（「滋賀県 高島市」）。市区町村の括弧は外す。無ければ空文字
    static func placeOneLine(_ credit: Credit) -> String {
        let lines = credit.placeLines
        guard let first = lines.first else { return "" }
        guard lines.count > 1 else { return first }
        return first + " " + lines[1].trimmingCharacters(in: CharacterSet(charactersIn: "（）()"))
    }

    private static func newCanvas(_ size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    // MARK: - 展示札

    /// 小さな見出し（真鍮・字間を空けた大文字）。「PLACE」「CAMERA」など
    private static func drawEyebrow(_ text: String, at origin: CGPoint, size: CGFloat) {
        let font = UIFont.systemFont(ofSize: size, weight: .semibold)
        let measured = (text as NSString).size(withAttributes: [.font: font, .kern: size * 0.16])
        guard ShareCardProbe.note(.text, text, rect: CGRect(origin: origin, size: measured),
                                  color: brass, fontSize: size) else { return }
        (text as NSString).draw(at: origin, withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: brass, .kern: size * 0.16])
    }

    /// 表の1列（ラベル＋値）。値は語の切れ目だけで折り、2行まで
    private static func drawLabeledValue(label: String, value: String, x: CGFloat, top: CGFloat, width: CGFloat) {
        typealias L = ShareCardMap.LabelLayout
        drawEyebrow(label, at: CGPoint(x: x, y: top), size: 15)
        let fitted = equipmentLayout(value, maxWidth: width, preferredSize: 22, availableHeight: L.tableValueHeight)
        let font = UIFont.systemFont(ofSize: fitted.size, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1
        paragraph.lineBreakMode = .byClipping
        let widest = fitted.lines.map { measuredWidth($0, size: fitted.size) }.max() ?? 0
        guard ShareCardProbe.note(.text, fitted.lines.joined(separator: " / "),
                                  rect: CGRect(x: x, y: top + 26, width: min(width, widest),
                                               height: CGFloat(fitted.lines.count) * (font.lineHeight + 1) - 1),
                                  color: .white, fontSize: fitted.size, truncated: fitted.truncated) else { return }
        (fitted.lines.joined(separator: "\n") as NSString).draw(
            with: CGRect(x: x, y: top + 26, width: width, height: L.tableValueHeight + 2),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph],
            context: nil)
    }

    /// 展示札型。上に写真（余白 60）、下に作品札のような札。真鍮の額縁は黒い地の上（写真の外）に置く
    static func renderLabel(photo: UIImage, credit: Credit, ratio: Ratio, avatarData: Data?) -> Data? {
        typealias L = ShareCardMap.LabelLayout
        let layout = L(ratio: ratio)
        let canvas = CGSize(width: L.width, height: layout.height)
        return newCanvas(canvas).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))
            drawPhotoFill(photo, in: layout.photoRect, context: cg)
            drawBrandHeader(centerY: layout.headerCenterY, left: L.contentLeft, right: L.contentRight,
                            taglineSize: 24, addressColor: brass)

            // 地名（明朝）
            let place = placeOneLine(credit)
            if !place.isEmpty {
                drawEyebrow("PLACE", at: CGPoint(x: L.contentLeft, y: layout.eyebrowTop), size: 16)
                drawFittedSerif(place, at: CGPoint(x: L.contentLeft, y: layout.placeTop),
                                maxWidth: L.leftColumnWidth, size: L.placeFontSize,
                                minimumSize: L.placeMinimumFontSize, color: .white)
            }
            // 罫線と撮影者
            if ShareCardProbe.drawsContent {
            cg.setStrokeColor(brass.withAlphaComponent(ShareCardMap.Layout.lineAlpha).cgColor)
            cg.setLineWidth(ShareCardMap.Layout.lineWidth)
            cg.move(to: CGPoint(x: L.contentLeft, y: layout.ruleY))
            cg.addLine(to: CGPoint(x: L.contentLeft + L.leftColumnWidth, y: layout.ruleY))
            cg.strokePath()
            }
            drawFadeAuthor(credit, avatarData: avatarData, top: layout.authorTop,
                           columnWidth: L.leftColumnWidth - 80, context: cg)

            // 撮影情報の表（ラベルつき）
            let exif = exifValues(credit)
            let entries: [(String, String)] = [("CAMERA", exif.camera), ("LENS", exif.lens), ("EXPOSURE", exif.exposure)]
            for (index, entry) in entries.enumerated() where !entry.1.isEmpty {
                let column = L.tableColumns[index]
                drawLabeledValue(label: entry.0, value: entry.1, x: column.x, top: layout.tableTop, width: column.width)
            }
            // 列の間の縦罫は、両側の列に字があるときだけ（2026-11-12・`ShareCardMap.infoDividerIndices`）
            cg.setStrokeColor(brass.withAlphaComponent(0.3).cgColor)
            let dividerXs = L.tableDividerXs
            for index in ShareCardMap.infoDividerIndices(filled: entries.map { !$0.1.isEmpty }) where ShareCardProbe.drawsContent {
                let x = dividerXs[index]
                cg.move(to: CGPoint(x: x, y: layout.tableTop))
                cg.addLine(to: CGPoint(x: x, y: layout.tableBottom))
                cg.strokePath()
            }

            // 右: 地図
            if let coordinate = credit.coords {
                let placeText = (credit.placeLines + [credit.location ?? ""]).joined(separator: ", ")
                CountryOutline.drawAtLocation(pin: coordinate, place: placeText,
                                              in: layout.mapRect, color: brass, context: cg)
            }
            drawBrassFrame(size: canvas, context: cg)
        }
    }

    // MARK: - 表紙

    /// 表紙型。写真を上から全面に敷き、下の 250 は黒一色。その上 340 を黒へ溶かし、地名（大きな明朝）をまたがせる。
    /// 写真の上には額縁を載せない
    static func renderCover(photo: UIImage, credit: Credit, ratio: Ratio, avatarData: Data?) -> Data? {
        typealias C = ShareCardMap.CoverLayout
        typealias F = ShareCardMap.FadeLayout
        let layout = C(ratio: ratio)
        let canvas = CGSize(width: C.width, height: layout.height)
        return newCanvas(canvas).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))
            drawPhotoFill(photo, in: CGRect(x: 0, y: 0, width: C.width, height: layout.photoBottom), context: cg)
            // 上の影・下のグラデーション（長く滑らか・境目を見せない）。その下は黒一色
            let shade = F(ratio: ratio)
            drawShade(cg, from: 0, to: shade.topShadeHeight, stops: shade.topShadeStops)
            drawShade(cg, from: layout.fadeTop, to: layout.photoBottom, stops: C.fadeStops)
            UIColor.black.setFill()
            cg.fill(CGRect(x: 0, y: layout.photoBottom, width: C.width, height: layout.height - layout.photoBottom))

            // 写真の上なので、字も住所も白（真鍮は黒い地の上だけ）
            drawBrandHeader(centerY: layout.headerCenterY, left: C.contentLeft, right: C.contentRight,
                            taglineSize: 24, addressColor: .white)

            // 右: 地図。上は写真の上（黒 69% から）なので白で描く（2026-11-14・真鍮は黒地の上だけ）
            if let coordinate = credit.coords {
                let placeText = (credit.placeLines + [credit.location ?? ""]).joined(separator: ", ")
                CountryOutline.drawAtLocation(pin: coordinate, place: placeText,
                                              in: layout.mapRect, color: .white, context: cg)
            }
            // 左: 地名（大きな明朝）と市区町村（真鍮）
            let lines = credit.placeLines
            if let first = lines.first {
                drawFittedSerif(first, at: CGPoint(x: C.contentLeft, y: layout.placeTop),
                                maxWidth: C.leftColumnWidth, size: C.placeFontSize,
                                minimumSize: C.placeMinimumFontSize, color: .white)
                if lines.count > 1 {
                    let sub = lines[1].trimmingCharacters(in: CharacterSet(charactersIn: "（）()"))
                    let pin = C.subPlaceFontSize
                    drawSymbol("mappin.circle", at: CGPoint(x: C.contentLeft, y: layout.subPlaceTop + 2),
                               size: pin, color: brass)
                    draw(sub, at: CGPoint(x: C.contentLeft + pin + 12, y: layout.subPlaceTop),
                         maxWidth: C.leftColumnWidth - pin - 12, size: pin, color: brass, bold: true)
                }
            }
            // 撮影者と、撮影情報の2行
            drawFadeAuthor(credit, avatarData: avatarData, top: layout.authorTop,
                           columnWidth: C.exifX - C.contentLeft - 64 - 16 - 20, context: cg)
            let exif = exifValues(credit)
            let exifLine = [exif.camera, exif.lens].filter { !$0.isEmpty }.joined(separator: "\u{2002}")
            if !exifLine.isEmpty {
                draw(exifLine, at: CGPoint(x: C.exifX, y: layout.exifTop), maxWidth: C.exifWidth,
                     size: 20, color: .white, bold: true)
            }
            if !exif.exposure.isEmpty {
                draw(exif.exposure, at: CGPoint(x: C.exifX, y: layout.exifTop + 30), maxWidth: C.exifWidth,
                     size: 20, color: .white, bold: true)
            }
        }
    }
}
#endif
