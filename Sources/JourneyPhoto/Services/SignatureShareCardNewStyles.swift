#if !os(Linux)
import UIKit

/// 共有カードの新しい3つの型（2026-11-14 owner「もっとデザイン増やしたいね」）。寸法は `ShareCardMap` の
/// `PrintLayout` / `TicketLayout` / `CinemaLayout`、字の置き場は `ShareCardSafeArea` の枠の中。
/// 部品（明朝の撮影地・撮影者の印・地図・ロゴの字）は前の型と同じ関数を使う。
///
/// 2026-11-14 判断（板「黒塗りの真鍮」）:
/// - プリントは白い紙（白 94% `#F0F0F0`）に墨の字。真鍮は黒地の上だけなので、紙の上では使わない
/// - 切符は黒地の札（surface-1）。真鍮は細線・眉ラベル・住所・地図だけ（広い面を真鍮で塗らない）
/// - シネマは写真の上に字を置かない（字は下の黒い帯の上だけ）
extension SignatureShareCardRenderer {
    static let paper = UIColor(red: 240/255, green: 240/255, blue: 240/255, alpha: 1)
    static let ink = UIColor(red: 7/255, green: 9/255, blue: 10/255, alpha: 1)
    /// 紙の上の副文（白 94% の上で 5.9:1）
    static let paperSecondary = UIColor(white: 0.36, alpha: 1)

    private static func canvas(_ size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// 撮影者の名前と印（認証・Pro・初期・章）を1行に。名前は幅に入るまで縮める（`draw` と同じ）
    private static func drawNameLine(_ credit: Credit, at origin: CGPoint, maxWidth: CGFloat,
                                     size: CGFloat, color: UIColor, palette: MarkPalette = .onBlack) {
        let name = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let markCount = (credit.verified ? 1 : 0) + (credit.proStyle == nil ? 0 : 1)
            + (credit.early ? 1 : 0) + ((credit.badge.map { BadgeCatalog.isKnown($0.key) } ?? false) ? 1 : 0)
        let markWidth = CGFloat(markCount * 30 + (credit.proStyle == .plate ? 16 : 0))
        let nameWidth = max(120, maxWidth - markWidth - (markCount > 0 ? 5 : 0))
        draw(name, at: origin, maxWidth: nameWidth, size: size, color: color, bold: true)
        guard markCount > 0 else { return }
        let font = UIFont.systemFont(ofSize: size, weight: .semibold)
        var fitted = font
        while fitted.pointSize > max(16, size * 0.72),
              (name as NSString).size(withAttributes: [.font: fitted]).width > nameWidth {
            fitted = UIFont(descriptor: font.fontDescriptor, size: max(max(16, size * 0.72), fitted.pointSize - 1))
        }
        let actual = min(nameWidth, ceil((name as NSString).size(withAttributes: [.font: fitted]).width))
        drawNameMarks(credit, at: CGPoint(x: origin.x + actual + 5, y: origin.y + (fitted.lineHeight - 27) / 2),
                      palette: palette)
    }

    /// 撮影情報の1行（カメラ・レンズ・撮影値を空白2つで）
    private static func exifLine(_ credit: Credit) -> String {
        let exif = exifValues(credit)
        return [exif.camera, exif.lens, exif.exposure].filter { !$0.isEmpty }.joined(separator: "\u{2003}")
    }

    /// ロゴのマークと字（右揃え）。字の大文字の高さの中心を centerY に置く
    private static func drawWordmarkRight(right: CGFloat, centerY: CGFloat, size: CGFloat, color: UIColor) {
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        let text = "Journey Photo"
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let mark = size * 1.15
        let top = centerY - (font.ascender - font.capHeight / 2)
        draw(text, at: CGPoint(x: right - width, y: top), maxWidth: width, size: size, color: color, serif: true)
        let markRect = CGRect(x: right - width - 12 - mark, y: centerY - mark / 2, width: mark, height: mark)
        if ShareCardProbe.note(.logo, "BrandMark", rect: markRect, color: color),
           let image = UIImage(named: "BrandMark")?.withRenderingMode(.alwaysTemplate) {
            image.withTintColor(color).draw(in: markRect)
        }
    }

    // MARK: - プリント

    /// プリント型。白い紙に白いフチの写真、下の広いフチに明朝の撮影地・市区町村・撮影者・撮影情報（墨と灰）
    static func renderPrint(photo: UIImage, credit: Credit, ratio: Ratio) -> Data? {
        typealias P = ShareCardMap.PrintLayout
        let layout = P(ratio: ratio)
        let size = CGSize(width: P.width, height: layout.height)
        return canvas(size).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            paper.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            drawPhotoFill(photo, in: layout.photoRect, context: cg)
            // 写真の縁に墨 8% の髪線（紙と明るい写真の境を見せる）
            cg.setStrokeColor(ink.withAlphaComponent(0.08).cgColor)
            cg.setLineWidth(1)
            cg.stroke(layout.photoRect.insetBy(dx: 0.5, dy: 0.5))

            let lines = credit.placeLines
            if let first = lines.first {
                drawFittedSerif(first, at: CGPoint(x: P.contentLeft, y: layout.placeTop), maxWidth: P.contentWidth,
                                size: P.placeFontSize, minimumSize: P.placeMinimumFontSize, color: ink)
            }
            if lines.count > 1 {
                let sub = lines[1].trimmingCharacters(in: CharacterSet(charactersIn: "（）()"))
                draw(sub, at: CGPoint(x: P.contentLeft, y: layout.subPlaceTop), maxWidth: P.contentWidth,
                     size: P.subFontSize, color: paperSecondary, bold: true)
            }
            drawNameLine(credit, at: CGPoint(x: P.contentLeft, y: layout.authorTop),
                         maxWidth: P.leftColumnWidth, size: P.nameFontSize, color: ink, palette: .onPaper)
            let info = exifLine(credit)
            if !info.isEmpty {
                draw(info, at: CGPoint(x: P.contentLeft, y: layout.infoTop), maxWidth: P.leftColumnWidth,
                     size: P.infoFontSize, color: paperSecondary)
            }
            // 右: ロゴの字（撮影者の行）と Web の住所（撮影情報の行）
            let nameLine = UIFont.systemFont(ofSize: P.nameFontSize, weight: .semibold).lineHeight
            drawWordmarkRight(right: P.contentRight, centerY: layout.authorTop + nameLine / 2, size: 28, color: ink)
            draw(ShareCardMap.Layout.siteAddress, at: CGPoint(x: P.contentRight - P.brandColumnWidth, y: layout.infoTop),
                 maxWidth: P.brandColumnWidth, size: P.infoFontSize, color: paperSecondary, alignment: .right)
        }
    }

    // MARK: - 切符

    /// 切符型。黒地に札の切符（真鍮の細線の外形・角丸）。写真の下にミシン目と左右の切り欠き、
    /// 半券に眉ラベル（真鍮）つきの撮影地（明朝）・撮影者・機材、右にロゴの字・住所・地図
    static func renderTicket(photo: UIImage, credit: Credit, ratio: Ratio) -> Data? {
        typealias T = ShareCardMap.TicketLayout
        let layout = T(ratio: ratio)
        let size = CGSize(width: T.width, height: layout.height)
        return canvas(size).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            let ticket = UIBezierPath(roundedRect: layout.ticketRect, cornerRadius: T.cornerRadius)
            surface.setFill()
            ticket.fill()
            // 写真（角丸 14）
            cg.saveGState()
            cg.addPath(UIBezierPath(roundedRect: layout.photoRect, cornerRadius: 14).cgPath)
            cg.clip()
            drawPhotoFill(photo, in: layout.photoRect, context: cg)
            cg.restoreGState()
            // 外形の細線
            cg.setStrokeColor(brass.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(2)
            cg.addPath(UIBezierPath(roundedRect: layout.ticketRect.insetBy(dx: 1, dy: 1),
                                    cornerRadius: T.cornerRadius - 1).cgPath)
            cg.strokePath()
            // ミシン目（真鍮 45% の破線）と左右の切り欠き（黒い半円＋真鍮の弧）
            let y = layout.perforationY
            let left = layout.ticketRect.minX, right = layout.ticketRect.maxX
            cg.setLineDash(phase: 0, lengths: [10, 10])
            cg.setStrokeColor(brass.withAlphaComponent(0.45).cgColor)
            cg.move(to: CGPoint(x: left + T.notchRadius + 14, y: y))
            cg.addLine(to: CGPoint(x: right - T.notchRadius - 14, y: y))
            cg.strokePath()
            cg.setLineDash(phase: 0, lengths: [])
            for (cx, start, end) in [(left, -CGFloat.pi / 2, CGFloat.pi / 2), (right, CGFloat.pi / 2, CGFloat.pi * 1.5)] {
                let notch = CGRect(x: cx - T.notchRadius, y: y - T.notchRadius,
                                   width: T.notchRadius * 2, height: T.notchRadius * 2)
                UIColor.black.setFill()
                cg.fillEllipse(in: notch)
                cg.setStrokeColor(brass.withAlphaComponent(0.55).cgColor)
                cg.setLineWidth(2)
                cg.addArc(center: CGPoint(x: cx, y: y), radius: T.notchRadius - 1, startAngle: start, endAngle: end,
                          clockwise: false)
                cg.strokePath()
            }

            // 半券: 撮影地（眉ラベル＋明朝）
            let lines = credit.placeLines
            if let first = lines.first {
                drawTicketEyebrow("PLACE", at: CGPoint(x: T.contentLeft, y: layout.placeEyebrowTop))
                var place = first
                if lines.count > 1 {
                    place += " " + lines[1].trimmingCharacters(in: CharacterSet(charactersIn: "（）()"))
                }
                drawFittedSerif(place, at: CGPoint(x: T.contentLeft, y: layout.placeTop), maxWidth: T.leftColumnWidth,
                                size: T.placeFontSize, minimumSize: T.placeMinimumFontSize, color: .white)
            }
            // 2段目: 撮影者・機材
            drawTicketEyebrow("PHOTOGRAPHER", at: CGPoint(x: T.contentLeft, y: layout.secondRowTop))
            drawNameLine(credit, at: CGPoint(x: T.contentLeft, y: layout.secondRowTop + 24),
                         maxWidth: T.secondColumnX - T.contentLeft - 24, size: T.valueFontSize, color: .white)
            let exif = exifValues(credit)
            let gear = [exif.camera, exif.lens].filter { !$0.isEmpty }.joined(separator: "\u{2002}")
            let gearWidth = layout.mapRect.minX - 24 - T.secondColumnX
            if !gear.isEmpty || !exif.exposure.isEmpty {
                drawTicketEyebrow("CAMERA", at: CGPoint(x: T.secondColumnX, y: layout.secondRowTop))
                draw(gear.isEmpty ? exif.exposure : gear, at: CGPoint(x: T.secondColumnX, y: layout.secondRowTop + 24),
                     maxWidth: gearWidth, size: T.valueFontSize, color: .white, bold: true)
            }
            // 右: ロゴの字・住所・地図（黒地の上なので真鍮）
            drawWordmarkRight(right: T.contentRight, centerY: layout.stubTop + 16, size: 28, color: .white)
            draw(ShareCardMap.Layout.siteAddress, at: CGPoint(x: T.contentRight - T.rightColumnWidth, y: layout.stubTop + 38),
                 maxWidth: T.rightColumnWidth, size: 18, color: brass, alignment: .right)
            if let coordinate = credit.coords {
                let placeText = (credit.placeLines + [credit.location ?? ""]).joined(separator: ", ")
                CountryOutline.drawAtLocation(pin: coordinate, place: placeText, in: layout.mapRect,
                                              color: brass, context: cg)
            }
        }
    }

    private static func drawTicketEyebrow(_ text: String, at origin: CGPoint) {
        let size = ShareCardMap.TicketLayout.eyebrowSize
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: brass, .kern: size * 0.16]
        let measured = (text as NSString).size(withAttributes: attributes)
        guard ShareCardProbe.note(.text, text, rect: CGRect(origin: origin, size: measured),
                                  color: brass, fontSize: size) else { return }
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    // MARK: - シネマ

    /// シネマ型。写真を左右の端まで敷き、上下は黒い帯。下の帯に明朝の撮影地と市区町村、撮影者、撮影情報。
    /// 右にロゴの字と住所（真鍮・黒地の上）。写真の上には何も置かない
    static func renderCinema(photo: UIImage, credit: Credit, ratio: Ratio) -> Data? {
        typealias C = ShareCardMap.CinemaLayout
        let layout = C(ratio: ratio)
        let size = CGSize(width: C.width, height: layout.height)
        return canvas(size).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            drawPhotoFill(photo, in: layout.photoRect, context: cg)

            let lines = credit.placeLines
            var placeRight = C.contentLeft
            if let first = lines.first {
                drawFittedSerif(first, at: CGPoint(x: C.contentLeft, y: layout.placeTop), maxWidth: C.leftColumnWidth,
                                size: C.placeFontSize, minimumSize: C.placeMinimumFontSize, color: .white)
                placeRight = C.contentLeft + min(C.leftColumnWidth, serifWidth(first, size: C.placeFontSize,
                                                                                 minimum: C.placeMinimumFontSize,
                                                                                 maxWidth: C.leftColumnWidth))
            }
            if lines.count > 1 {
                // 市区町村は明朝の右に、同じ下の線で（入らなければ撮影者の行の上に回さず省く）
                let sub = lines[1].trimmingCharacters(in: CharacterSet(charactersIn: "（）()"))
                let room = C.contentLeft + C.leftColumnWidth - placeRight - 16
                if room >= 120 {
                    let font = UIFont.systemFont(ofSize: 24, weight: .semibold)
                    draw(sub, at: CGPoint(x: placeRight + 16, y: layout.placeTop + C.placeFontSize * 1.3 - font.lineHeight - 8),
                         maxWidth: room, size: 24, color: secondary, bold: true)
                }
            }
            drawNameLine(credit, at: CGPoint(x: C.contentLeft, y: layout.authorTop), maxWidth: C.leftColumnWidth,
                         size: C.nameFontSize, color: .white)
            let info = exifLine(credit)
            if !info.isEmpty {
                draw(info, at: CGPoint(x: C.contentLeft, y: layout.infoTop), maxWidth: C.leftColumnWidth,
                     size: C.infoFontSize, color: secondary)
            }
            drawWordmarkRight(right: C.contentRight, centerY: layout.placeTop + C.placeFontSize * 0.62,
                              size: 30, color: .white)
            draw(ShareCardMap.Layout.siteAddress, at: CGPoint(x: C.contentRight - C.brandColumnWidth, y: layout.infoTop),
                 maxWidth: C.brandColumnWidth, size: C.infoFontSize, color: brass, alignment: .right)
        }
    }

    /// 明朝の1行が `drawFittedSerif` で描かれる幅
    private static func serifWidth(_ value: String, size: CGFloat, minimum: CGFloat, maxWidth: CGFloat) -> CGFloat {
        func serif(_ s: CGFloat) -> UIFont {
            let base = UIFont.systemFont(ofSize: s, weight: .bold)
            return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: s) } ?? base
        }
        var fitted = size
        while fitted > minimum, (value as NSString).size(withAttributes: [.font: serif(fitted)]).width > maxWidth {
            fitted -= 1
        }
        return ceil((value as NSString).size(withAttributes: [.font: serif(fitted)]).width)
    }
}
#endif
