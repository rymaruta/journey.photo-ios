#if !os(Linux)
import UIKit

/// 共有カードの次の3つの型（2026-11-14 owner「この SNS に共有のやつ、新しいデザイン加えつつ、更にブラッシュアップさせたいな」）。
/// 寸法は `ShareCardMap` の `MatLayout` / `FilmLayout` / `TanzakuLayout`（`ShareCardMoreLayouts.swift`）。
/// 部品（明朝の撮影地・撮影者の印・ロゴの字）は前の型と同じ関数を使う。
///
/// 2026-11-14 判断（板「黒塗りの真鍮」）:
/// - 額装の額は写真の色の暗い色。黒い地ではないので真鍮は使わず、字は白と灰（#B8B8B8）だけ
/// - フィルムと縦書きは黒い地なので、住所・印の枠は真鍮
/// - 写真の上には字を置かない（3つとも字は写真の外）
/// - 区切りに「・」を使わない（撮影値・機材は全角の空き）
extension SignatureShareCardRenderer {

    // MARK: - 共通

    /// 写真の平均の色（sRGB 0〜255）。16×16 に縮めて平均する
    static func averageColor(_ photo: UIImage) -> (red: Double, green: Double, blue: Double) {
        guard let image = photo.cgImage else { return (0, 0, 0) }
        let side = 16
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return (0, 0, 0) }
        var red = 0.0, green = 0.0, blue = 0.0
        for index in stride(from: 0, to: buffer.count, by: 4) {
            red += Double(buffer[index])
            green += Double(buffer[index + 1])
            blue += Double(buffer[index + 2])
        }
        let count = Double(side * side)
        return (red / count, green / count, blue / count)
    }

    /// 明朝の1行を真ん中にそろえて描く（幅に入るまで縮める・`drawFittedSerif` と同じ縮め方）
    static func drawCenteredSerif(_ value: String, centerX: CGFloat, top: CGFloat, maxWidth: CGFloat,
                                  size: CGFloat, minimumSize: CGFloat, color: UIColor) {
        let shown = min(maxWidth, serifWidth(value, size: size, minimum: minimumSize, maxWidth: maxWidth))
        drawFittedSerif(value, at: CGPoint(x: centerX - shown / 2, y: top), maxWidth: maxWidth,
                        size: size, minimumSize: minimumSize, color: color)
    }

    /// 撮影者の名前と印の1行の幅（`drawNameLine` と同じ縮め方）
    static func nameLineWidth(_ credit: Credit, maxWidth: CGFloat, size: CGFloat) -> CGFloat {
        let name = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let markCount = (credit.verified ? 1 : 0) + (credit.proStyle == nil ? 0 : 1)
            + (credit.early ? 1 : 0) + ((credit.badge.map { BadgeCatalog.isKnown($0.key) } ?? false) ? 1 : 0)
        let markWidth = CGFloat(markCount * 30 + (credit.proStyle == .plate ? 16 : 0))
        let nameWidth = max(120, maxWidth - markWidth - (markCount > 0 ? 5 : 0))
        let font = UIFont.systemFont(ofSize: size, weight: .semibold)
        var fitted = font
        let minimum = max(16, size * 0.72)
        while fitted.pointSize > minimum, (name as NSString).size(withAttributes: [.font: fitted]).width > nameWidth {
            fitted = UIFont(descriptor: font.fontDescriptor, size: max(minimum, fitted.pointSize - 1))
        }
        let actual = min(nameWidth, ceil((name as NSString).size(withAttributes: [.font: fitted]).width))
        return actual + (markCount > 0 ? 5 + markWidth : 0)
    }

    /// ロゴのマークと字を真ん中にそろえて
    static func drawWordmarkCentered(centerX: CGFloat, centerY: CGFloat, size: CGFloat, color: UIColor) {
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        let width = ceil(("Journey Photo" as NSString).size(withAttributes: [.font: font]).width)
        let total = width + 12 + size * 1.15
        drawWordmarkRight(right: centerX + total / 2, centerY: centerY, size: size, color: color)
    }

    /// SF の等幅数字の1行（撮影値）。幅に入るまで縮める
    static func drawMono(_ value: String, at origin: CGPoint, maxWidth: CGFloat, size: CGFloat,
                         minimumSize: CGFloat, color: UIColor) {
        func font(_ s: CGFloat) -> UIFont { UIFont.monospacedDigitSystemFont(ofSize: s, weight: .semibold) }
        var fitted = size
        while fitted > minimumSize, (value as NSString).size(withAttributes: [.font: font(fitted)]).width > maxWidth {
            fitted -= 1
        }
        let fittedFont = font(fitted)
        let full = ceil((value as NSString).size(withAttributes: [.font: fittedFont]).width)
        guard ShareCardProbe.note(.text, value, rect: CGRect(x: origin.x, y: origin.y, width: min(full, maxWidth),
                                                              height: fittedFont.lineHeight),
                                  color: color, fontSize: fitted, truncated: full > maxWidth) else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: CGRect(x: origin.x, y: origin.y, width: maxWidth, height: fittedFont.lineHeight * 1.1),
                                 withAttributes: [.font: fittedFont, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    /// 明朝の縦書き。和文は1字ずつ積み（長音などは 90° 回す）、英字の混じる字は行ごと 90° 回す（`ShareCardMap.VerticalText`）。
    /// 描いた字の大きさを返す
    @discardableResult
    static func drawVertical(_ value: String, centerX: CGFloat, top: CGFloat, maxHeight: CGFloat, size: CGFloat,
                             minimumSize: CGFloat, color: UIColor, bold: Bool = true, context cg: CGContext) -> CGFloat {
        func font(_ s: CGFloat) -> UIFont {
            let base = UIFont.systemFont(ofSize: s, weight: bold ? .bold : .regular)
            return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: s) } ?? base
        }
        typealias V = ShareCardMap.VerticalText
        guard maxHeight > 0 else { return size }
        if V.stacks(value) {
            let characters = Array(value)
            let fit = V.fit(count: characters.count, maxHeight: maxHeight, size: size, minimumSize: minimumSize)
            let advance = fit.size * ShareCardMap.TanzakuLayout.verticalAdvance
            let shown: [Character] = fit.truncated
                ? Array(characters.prefix(max(0, fit.shown - 1))) + ["\u{FE19}"] : characters
            let rect = CGRect(x: centerX - fit.size / 2 - 2, y: top, width: fit.size + 4,
                              height: CGFloat(shown.count) * advance)
            guard ShareCardProbe.note(.text, value, rect: rect, color: color, fontSize: fit.size,
                                      truncated: fit.truncated) else { return fit.size }
            let attributes: [NSAttributedString.Key: Any] = [.font: font(fit.size), .foregroundColor: color]
            for (index, character) in shown.enumerated() {
                let glyph = String(character) as NSString
                let measured = glyph.size(withAttributes: attributes)
                let cellMidY = top + (CGFloat(index) + 0.5) * advance
                if V.rotatesInColumn(character) {
                    cg.saveGState()
                    cg.translateBy(x: centerX, y: cellMidY)
                    cg.rotate(by: .pi / 2)
                    glyph.draw(at: CGPoint(x: -measured.width / 2, y: -measured.height / 2), withAttributes: attributes)
                    cg.restoreGState()
                } else {
                    glyph.draw(at: CGPoint(x: centerX - measured.width / 2, y: cellMidY - measured.height / 2),
                               withAttributes: attributes)
                }
            }
            return fit.size
        }
        // 英字など: 行ごと時計回りに 90° 回す（字の頭が右を向き、上から下へ読む）
        var fitted = size
        while fitted > minimumSize, (value as NSString).size(withAttributes: [.font: font(fitted)]).width > maxHeight {
            fitted -= 1
        }
        let fittedFont = font(fitted)
        let full = ceil((value as NSString).size(withAttributes: [.font: fittedFont]).width)
        let lineHeight = fittedFont.lineHeight
        let rect = CGRect(x: centerX - lineHeight / 2, y: top, width: lineHeight, height: min(full, maxHeight))
        guard ShareCardProbe.note(.text, value, rect: rect, color: color, fontSize: fitted,
                                  truncated: full > maxHeight) else { return fitted }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        cg.saveGState()
        cg.translateBy(x: centerX + lineHeight / 2, y: top)
        cg.rotate(by: .pi / 2)
        (value as NSString).draw(in: CGRect(x: 0, y: 0, width: maxHeight, height: lineHeight),
                                 withAttributes: [.font: fittedFont, .foregroundColor: color, .paragraphStyle: paragraph])
        cg.restoreGState()
        return fitted
    }

    // MARK: - 額装

    /// 額装型。写真の色の暗い額に写真を入れ、上にロゴ、下に明朝の撮影地・市区町村・撮影者・住所を真ん中にそろえる
    static func renderMat(photo: UIImage, credit: Credit, ratio: Ratio) -> Data? {
        typealias M = ShareCardMap.MatLayout
        let layout = M(ratio: ratio)
        let size = CGSize(width: M.width, height: layout.height)
        let average = averageColor(photo)
        let matRGB = ShareCardMap.MatColor.color(red: average.red, green: average.green, blue: average.blue)
        let mat = UIColor(red: matRGB.red / 255, green: matRGB.green / 255, blue: matRGB.blue / 255, alpha: 1)
        return canvas(size).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            mat.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            let photoRect = layout.photoRect
            // 額の段（写真の 14 外に白 10% の髪線）と、写真の縁（白 22% の髪線）。飾りの線
            cg.setLineWidth(1)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
            cg.stroke(photoRect.insetBy(dx: -14.5, dy: -14.5))
            drawPhotoFill(photo, in: photoRect, context: cg)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.22).cgColor)
            cg.stroke(photoRect.insetBy(dx: 0.5, dy: 0.5))

            let centerX = M.width / 2
            drawWordmarkCentered(centerX: centerX, centerY: layout.brandCenterY, size: M.brandFontSize, color: .white)
            let lines = credit.placeLines
            if let first = lines.first {
                drawCenteredSerif(first, centerX: centerX, top: layout.placeTop, maxWidth: M.contentWidth,
                                  size: M.placeFontSize, minimumSize: M.placeMinimumFontSize, color: .white)
            }
            if lines.count > 1 {
                let sub = lines[1].trimmingCharacters(in: CharacterSet(charactersIn: "（）()"))
                draw(sub, at: CGPoint(x: M.contentLeft, y: layout.subPlaceTop), maxWidth: M.contentWidth,
                     size: M.subFontSize, color: secondary, bold: true, alignment: .center)
            }
            let nameWidth = nameLineWidth(credit, maxWidth: M.contentWidth, size: M.nameFontSize)
            drawNameLine(credit, at: CGPoint(x: centerX - nameWidth / 2, y: layout.authorTop), maxWidth: M.contentWidth,
                         size: M.nameFontSize, color: .white)
            draw(ShareCardMap.Layout.siteAddress, at: CGPoint(x: M.contentLeft, y: layout.addressTop),
                 maxWidth: M.contentWidth, size: M.addressFontSize, color: secondary, alignment: .center)
        }
    }

    // MARK: - フィルム

    /// フィルムの地（黒より少し明るい暖かい墨）
    static let filmBase = UIColor(red: 24/255, green: 22/255, blue: 20/255, alpha: 1)

    /// 撮影値の1行（絞り、シャッター、ISO を全角の空きで）
    static func heroExposure(_ credit: Credit) -> String {
        [credit.aperture, credit.exposure, credit.iso.map { "ISO \($0)" }]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\u{2003}")
    }

    /// フィルム型。左右の端まで渡したフィルムの地に送り穴と写真。下に撮影地（明朝）、撮影値（等幅数字・主役）、機材、撮影者
    static func renderFilm(photo: UIImage, credit: Credit, ratio: Ratio) -> Data? {
        typealias F = ShareCardMap.FilmLayout
        let layout = F(ratio: ratio)
        let size = CGSize(width: F.width, height: layout.height)
        return canvas(size).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            filmBase.setFill()
            cg.fill(layout.stripRect)
            UIColor.black.setFill()
            for hole in layout.holeRects {
                UIBezierPath(roundedRect: hole, cornerRadius: 5).fill()
            }
            drawPhotoFill(photo, in: layout.photoRect, context: cg)

            let place = placeOneLine(credit)
            let hero = heroExposure(credit)
            if hero.isEmpty {
                // 撮影値が無いときは、撮影地を主役の行に大きく
                if !place.isEmpty {
                    drawFittedSerif(place, at: CGPoint(x: F.contentLeft, y: layout.heroTop), maxWidth: F.leftColumnWidth,
                                    size: F.heroFontSize, minimumSize: F.heroMinimumFontSize, color: .white)
                }
            } else {
                if !place.isEmpty {
                    drawFittedSerif(place, at: CGPoint(x: F.contentLeft, y: layout.placeTop), maxWidth: F.leftColumnWidth,
                                    size: F.placeFontSize, minimumSize: F.placeMinimumFontSize, color: .white)
                }
                drawMono(hero, at: CGPoint(x: F.contentLeft, y: layout.heroTop), maxWidth: F.contentWidth,
                         size: F.heroFontSize, minimumSize: F.heroMinimumFontSize, color: .white)
            }
            let exif = exifValues(credit)
            let gear = [exif.camera, exif.lens].filter { !$0.isEmpty }.joined(separator: "\u{2003}")
            if !gear.isEmpty {
                draw(gear, at: CGPoint(x: F.contentLeft, y: layout.gearTop), maxWidth: F.leftColumnWidth,
                     size: F.gearFontSize, color: secondary)
            }
            drawNameLine(credit, at: CGPoint(x: F.contentLeft, y: layout.authorTop), maxWidth: F.leftColumnWidth,
                         size: F.nameFontSize, color: .white)
            // 右: ロゴの字（撮影地の行）と Web の住所（撮影者の行・黒地の上なので真鍮）
            drawWordmarkRight(right: F.contentRight, centerY: layout.placeTop + 22, size: 26, color: .white)
            draw(ShareCardMap.Layout.siteAddress, at: CGPoint(x: F.contentRight - F.brandColumnWidth, y: layout.authorTop + 2),
                 maxWidth: F.brandColumnWidth, size: F.addressFontSize, color: brass, alignment: .right)
        }
    }

    // MARK: - 縦書き（短冊）

    /// 縦書き型。写真の右の黒い列に、撮影地（明朝・縦書き）、その左に市区町村と縦のロゴの字、下に真鍮の角の枠の印。
    /// 撮影者と住所は写真の下の1行
    static func renderTanzaku(photo: UIImage, credit: Credit, ratio: Ratio) -> Data? {
        typealias T = ShareCardMap.TanzakuLayout
        let layout = T(ratio: ratio)
        let size = CGSize(width: T.width, height: layout.height)
        return canvas(size).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            drawPhotoFill(photo, in: layout.photoRect, context: cg)

            // 印: 真鍮の角の枠（飾りの線）と、中のロゴのマーク（真鍮・黒地の上）
            let seal = layout.sealRect
            cg.setStrokeColor(brass.cgColor)
            cg.setLineWidth(2)
            cg.stroke(seal.insetBy(dx: 1, dy: 1))
            let markRect = seal.insetBy(dx: 18, dy: 18)
            if ShareCardProbe.note(.logo, "BrandMark", rect: markRect, color: brass),
               let mark = UIImage(named: "BrandMark")?.withRenderingMode(.alwaysTemplate) {
                mark.withTintColor(brass).draw(in: markRect)
            }

            var placeSize = T.placeFontSize
            let lines = credit.placeLines
            if let first = lines.first {
                placeSize = drawVertical(first, centerX: T.placeColumnX, top: layout.placeTop,
                                         maxHeight: layout.placeBottom - layout.placeTop, size: T.placeFontSize,
                                         minimumSize: T.placeMinimumFontSize, color: .white, context: cg)
            }
            // 左の列の下: ロゴの字（縦）。上: 市区町村（縦）
            let wordmarkTop = layout.photoBottom - 160
            drawVertical("Journey Photo", centerX: T.subColumnX, top: wordmarkTop, maxHeight: 160, size: 22,
                         minimumSize: 18, color: .white, bold: false, context: cg)
            if lines.count > 1 {
                let sub = lines[1].trimmingCharacters(in: CharacterSet(charactersIn: "（）()"))
                let top = layout.subTop(placeSize: placeSize)
                drawVertical(sub, centerX: T.subColumnX, top: top, maxHeight: wordmarkTop - 24 - top,
                             size: T.subFontSize, minimumSize: T.subMinimumFontSize, color: secondary, context: cg)
            }
            drawNameLine(credit, at: CGPoint(x: T.margin, y: layout.authorTop), maxWidth: T.authorWidth,
                         size: T.nameFontSize, color: .white)
            draw(ShareCardMap.Layout.siteAddress,
                 at: CGPoint(x: T.width - T.margin - T.addressColumnWidth, y: layout.authorTop + 2),
                 maxWidth: T.addressColumnWidth, size: T.addressFontSize, color: brass, alignment: .right)
        }
    }
}
#endif
