import Foundation
#if !os(Linux)
import UIKit
import CoreImage
import ImageIO
#endif

/// 旅をストーリーに（`TravelStory`）の絵を描く。9:16（1080 × 1920）の JPEG か、ステッカーの透明 PNG。
///
/// 章の模型（資料「画面デザインの案」第9章 `travel-story.html`）の寸法を cqw × 10.8 の画素で写した
/// （寸法は `TravelStory.Layout` に1か所）。紙の色（生成り `#F2EDE2`）は**共有の絵の中だけ**で、アプリの画面には使わない。
/// 真鍮は黒の上だけ（フィルムの帯の縁の番号）。
///
/// **EXIF の位置は残らない**——`UIGraphicsImageRenderer` で描き直すので、元の写真の付帯情報を引き継がない
/// （`TripBookCardRenderer` と同じ）。倍率は 1 に固定。重いので画面の処理の外で呼ぶ。
enum TravelStoryRenderer {

    /// 描いた絵。写真に重ねる回は JPEG、ステッカーは PNG
    struct Output: Equatable {
        let data: Data
        let isSticker: Bool
    }

    #if os(Linux)
    // Linux の SDK 模型には CoreGraphics の描画が無い。実描画は iOS の Xcode で確かめる（`SignatureShareCardRenderer` と同じ）
    static func render(_ photos: [Data], facts: TravelStory.Facts, choice: TravelStory.Choice,
                       now: Date = Date()) -> Output? { nil }
    #else
    static func render(_ photos: [Data], facts: TravelStory.Facts, choice: TravelStory.Choice,
                       now: Date = Date()) -> Output? {
        let images = photos.compactMap(decode)
        guard let lead = images.first else { return nil }
        let texts = TravelStory.texts(facts, choice: choice, now: now)
        let sticker = choice.effectiveMode == .sticker
        switch choice.kind {
        case .pass:
            let pass = TravelStory.pass(facts, choice: choice, texts: texts)
            return sticker ? passSticker(pass) : passOnPhoto(lead, pass: pass)
        case .stamp:
            return sticker ? stampSticker(lead, texts: texts) : stampOnPaper(lead, texts: texts)
        case .film:
            return film(Array(images.prefix(3)), texts: texts)
        }
    }
    #endif
}

#if !os(Linux)
extension TravelStoryRenderer {

    typealias Layout = TravelStory.Layout
    static func u(_ v: CGFloat) -> CGFloat { Layout.u(v) }

    static let paper = UIColor(red: 0xF2 / 255, green: 0xED / 255, blue: 0xE2 / 255, alpha: 1)
    static let stampPaper = UIColor(red: 0xFC / 255, green: 0xFB / 255, blue: 0xF7 / 255, alpha: 1)
    static let ink = UIColor(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255, alpha: 1)
    static let postInk = UIColor(red: 22 / 255, green: 22 / 255, blue: 26 / 255, alpha: 1)
    static let brass = SignatureShareCardRenderer.brass

    // MARK: - 写真を読む

    /// 1080 の絵に原本の全画素を展開しない（最大 2400px に縮めて読む・向きは直す）
    static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        let image = UIImage(cgImage: cg)
        return image.size.width > 0 && image.size.height > 0 ? image : nil
    }

    // MARK: - 下回り

    static func format(opaque: Bool) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        format.preferredRange = .standard
        return format
    }

    static func jpeg(_ draw: @escaping (CGContext) -> Void) -> Output {
        let renderer = UIGraphicsImageRenderer(size: Layout.canvas, format: format(opaque: true))
        let data = renderer.jpegData(withCompressionQuality: 0.92) { context in
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: Layout.canvas))
            draw(context.cgContext)
        }
        return Output(data: data, isSticker: false)
    }

    static func png(size: CGSize, _ draw: @escaping (CGContext) -> Void) -> Output {
        let renderer = UIGraphicsImageRenderer(size: size, format: format(opaque: false))
        return Output(data: renderer.pngData { draw($0.cgContext) }, isSticker: true)
    }

    static func sans(_ size: CGFloat, _ weight: UIFont.Weight = .regular, digits: Bool = false) -> UIFont {
        digits ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : UIFont.systemFont(ofSize: size, weight: weight)
    }

    /// 明朝（同梱の Shippori Mincho B1。無ければ端末の明朝）
    static func mincho(_ size: CGFloat) -> UIFont {
        if let font = UIFont(name: JPFont.displayName, size: size) { return font }
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    /// 1行の字。幅に入らなければ縮める（下限は 0.6 倍）。描いた幅を返す
    @discardableResult
    static func text(_ value: String, font: UIFont, color: UIColor, kern: CGFloat = 0,
                     at origin: CGPoint, maxWidth: CGFloat? = nil, align: NSTextAlignment = .left,
                     shadow: NSShadow? = nil) -> CGSize {
        var font = font
        func attrs(_ f: UIFont) -> [NSAttributedString.Key: Any] {
            var a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .kern: kern * f.pointSize]
            if let shadow { a[.shadow] = shadow }
            return a
        }
        var size = (value as NSString).size(withAttributes: attrs(font))
        if let maxWidth {
            let floor = font.pointSize * 0.6
            while size.width > maxWidth, font.pointSize > floor {
                font = font.withSize(font.pointSize - 1)
                size = (value as NSString).size(withAttributes: attrs(font))
            }
        }
        var x = origin.x
        if let maxWidth {
            switch align {
            case .center: x += (maxWidth - min(size.width, maxWidth)) / 2
            case .right: x += maxWidth - min(size.width, maxWidth)
            default: break
            }
        } else if align == .center {
            x -= size.width / 2
        } else if align == .right {
            x -= size.width
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var a = attrs(font)
        a[.paragraphStyle] = paragraph
        (value as NSString).draw(in: CGRect(x: x, y: origin.y, width: min(size.width, maxWidth ?? size.width) + 1,
                                            height: size.height), withAttributes: a)
        return size
    }

    /// 決まった並びの乱数（毎回同じ粒・掠れにする。絵が描くたびに替わらない）
    struct Seeded {
        var state: UInt64
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }
    }

    /// 紙の粒（模型の `--grain`: 茶の細かな点・30% ほど）
    static func grain(_ cg: CGContext, in rect: CGRect, seed: UInt64, density: CGFloat = 1) {
        var r = Seeded(state: seed)
        let count = Int(rect.width * rect.height / 260 * density)
        for _ in 0..<count {
            let x = rect.minX + r.next() * rect.width
            let y = rect.minY + r.next() * rect.height
            let size = 1 + r.next() * 2.2
            let alpha = 0.04 + r.next() * 0.1
            cg.setFillColor(UIColor(red: 0.32, green: 0.27, blue: 0.2, alpha: alpha).cgColor)
            cg.fill(CGRect(x: x, y: y, width: size, height: size))
        }
    }

    /// 写真を枠いっぱいに敷く（はみ出しは切る）
    static func fill(_ image: UIImage, in rect: CGRect, _ cg: CGContext) {
        SignatureShareCardRenderer.drawPhotoFill(image, in: rect, context: cg)
    }

    /// 縦の黒のぼかし（`SignatureShareCardRenderer.drawShade` と同じ）
    static func shade(_ cg: CGContext, from y0: CGFloat, to y1: CGFloat, alpha0: CGFloat, alpha1: CGFloat) {
        SignatureShareCardRenderer.drawShade(cg, from: y0, to: y1,
                                             stops: [(0, alpha0), (1, alpha1)])
    }

    /// 回して描く（中心で回す）
    static func rotated(_ cg: CGContext, around center: CGPoint, degrees: CGFloat, _ draw: () -> Void) {
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: degrees * .pi / 180)
        cg.translateBy(x: -center.x, y: -center.y)
        draw()
        cg.restoreGState()
    }

    // MARK: - 1 搭乗券（本体と半券。間はミシン目と両端の切り欠き・紙の粒）

    static func passOnPhoto(_ photo: UIImage, pass: TravelStory.PassTexts) -> Output {
        jpeg { cg in
            fill(photo, in: CGRect(origin: .zero, size: Layout.canvas), cg)
            // 下 62% を黒 66% へ（模型の .shade-b）
            shade(cg, from: Layout.canvas.height * 0.38, to: Layout.canvas.height, alpha0: 0, alpha1: 0.66)
            drawPass(pass, in: Layout.passRect, cg)
        }
    }

    static func passSticker(_ pass: TravelStory.PassTexts) -> Output {
        let width = Layout.passStickerWidth
        let ticket = CGRect(x: 0, y: 0, width: width, height: Layout.passHeight)
        let bounds = Layout.rotatedBounds(ticket, degrees: Layout.passStickerAngle)
        let margin = u(6)   // 影の分
        let size = CGSize(width: ceil(bounds.width + margin * 2), height: ceil(bounds.height + margin * 2))
        return png(size: size) { cg in
            let rect = CGRect(x: (size.width - width) / 2, y: (size.height - Layout.passHeight) / 2,
                              width: width, height: Layout.passHeight)
            rotated(cg, around: CGPoint(x: rect.midX, y: rect.midY), degrees: Layout.passStickerAngle) {
                drawPass(pass, in: rect, cg)
            }
        }
    }

    /// 券の形。角丸の四角から、本体と半券の境の両端を半円で抜く
    static func passShape(_ rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: Layout.passCorner, cornerHeight: Layout.passCorner)
        let y = rect.minY + Layout.passBodyHeight
        let n = Layout.passNotch
        path.addEllipse(in: CGRect(x: rect.minX - n, y: y - n, width: n * 2, height: n * 2))
        path.addEllipse(in: CGRect(x: rect.maxX - n, y: y - n, width: n * 2, height: n * 2))
        return path
    }

    static func drawPass(_ pass: TravelStory.PassTexts, in rect: CGRect, _ cg: CGContext) {
        let shape = passShape(rect)
        // 影（模型 drop-shadow 0 2cqw 3.5cqw 黒 42%）
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: u(2)), blur: u(3.5),
                     color: UIColor.black.withAlphaComponent(0.42).cgColor)
        cg.addPath(shape)
        cg.setFillColor(paper.cgColor)
        cg.fillPath(using: .evenOdd)
        cg.restoreGState()
        // 紙の粒は券の形の中だけ
        cg.saveGState()
        cg.addPath(shape)
        cg.clip(using: .evenOdd)
        grain(cg, in: rect, seed: 11)
        cg.restoreGState()

        // ミシン目（半券の上端に点の列）
        let perfY = rect.minY + Layout.passBodyHeight
        var x = rect.minX + u(4.2)
        cg.setFillColor(UIColor.black.withAlphaComponent(0.34).cgColor)
        while x < rect.maxX - u(4.2) {
            cg.fillEllipse(in: CGRect(x: x + u(0.95) - u(0.34), y: perfY - u(0.34), width: u(0.68), height: u(0.68)))
            x += u(1.9)
        }

        let left = rect.minX + u(5)
        let right = rect.maxX - u(5)
        let inner = right - left
        // 上の段: JOURNEY PASS と場面（明朝）
        var y = rect.minY + u(4.4)
        let top = sans(u(2.9), .heavy)
        let phase = mincho(u(4.8))
        let phaseWidth = (pass.phaseLabel as NSString).size(withAttributes: [.font: phase]).width
        let baselineGap = phase.ascender - top.ascender
        text("JOURNEY PASS", font: top, color: ink, kern: 0.22, at: CGPoint(x: left, y: y + baselineGap),
             maxWidth: inner - phaseWidth - u(3))
        text(pass.phaseLabel, font: phase, color: ink, kern: 0.04, at: CGPoint(x: right - phaseWidth, y: y))
        y += phase.lineHeight + u(3)

        // 真ん中: 小さな見出し・大きな字・明朝の地名、右に DAY
        let key = sans(u(2.8), .bold)
        let keyColor = ink.withAlphaComponent(0.62)
        let big = sans(u(9.4), .heavy, digits: true)
        var dayWidth: CGFloat = 0
        if let day = pass.day {
            let dayText = "\(day)"
            dayWidth = max((dayText as NSString).size(withAttributes: [.font: big]).width,
                           ("DAY" as NSString).size(withAttributes: [.font: key, .kern: key.pointSize * 0.18]).width)
            text("DAY", font: key, color: keyColor, kern: 0.18, at: CGPoint(x: right - dayWidth, y: y),
                 maxWidth: dayWidth, align: .right)
            text(dayText, font: big, color: ink, at: CGPoint(x: right - dayWidth, y: y + key.lineHeight),
                 maxWidth: dayWidth, align: .right)
        }
        let column = inner - (dayWidth > 0 ? dayWidth + u(3) : 0)
        text(pass.head, font: key, color: keyColor, kern: 0.18, at: CGPoint(x: left, y: y))
        text(pass.big, font: big, color: ink, kern: 0.01, at: CGPoint(x: left, y: y + key.lineHeight), maxWidth: column)
        text(pass.local, font: mincho(u(4.4)), color: ink,
             at: CGPoint(x: left, y: y + key.lineHeight + big.lineHeight * 0.92 + u(1)), maxWidth: column)

        // 半券: 欄と、右にバーコード（飾り）
        let stubTop = rect.minY + Layout.passBodyHeight + u(3.8)
        let value = sans(u(3.6), .bold, digits: true)
        let barcode = CGRect(x: right - u(19), y: rect.maxY - u(4.4) - u(8.4), width: u(19), height: u(8.4))
        var fx = left
        let fieldWidth = (barcode.minX - u(4) - left) / CGFloat(max(1, pass.foot.count))
        for field in pass.foot {
            text(field.key, font: key, color: keyColor, kern: 0.18, at: CGPoint(x: fx, y: stubTop + u(1.6)),
                 maxWidth: fieldWidth - u(2))
            text(field.value, font: value, color: ink, at: CGPoint(x: fx, y: stubTop + u(1.6) + key.lineHeight + u(0.6)),
                 maxWidth: fieldWidth - u(2))
            fx += fieldWidth
        }
        cg.setFillColor(ink.cgColor)
        var bx = barcode.minX
        while bx < barcode.maxX {
            for (start, end) in [(0.0, 0.5), (1.0, 1.9), (2.3, 2.6)] {
                let x0 = bx + u(CGFloat(start)), x1 = min(barcode.maxX, bx + u(CGFloat(end)))
                if x1 > x0 { cg.fill(CGRect(x: x0, y: barcode.minY, width: x1 - x0, height: barcode.height)) }
            }
            bx += u(3.3)
        }
    }

    // MARK: - 2 切手と消印

    static func stampOnPaper(_ photo: UIImage, texts: TravelStory.Texts) -> Output {
        jpeg { cg in
            let canvas = CGRect(origin: .zero, size: Layout.canvas)
            // 生成りの紙・左上の光・粒
            cg.setFillColor(paper.cgColor)
            cg.fill(canvas)
            if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [UIColor.white.withAlphaComponent(0.5).cgColor,
                                              UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                     locations: [0, 1]) {
                cg.drawRadialGradient(glow, startCenter: CGPoint(x: canvas.width * 0.3, y: canvas.height * 0.2),
                                      startRadius: 0,
                                      endCenter: CGPoint(x: canvas.width * 0.3, y: canvas.height * 0.2),
                                      endRadius: canvas.height * 0.6, options: [])
            }
            grain(cg, in: canvas, seed: 23, density: 0.6)
            // 上の縁の斜めの縞（封筒の縁）
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: 0, width: canvas.width, height: u(2.6)))
            cg.setFillColor(UIColor(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1).cgColor)
            var x = -u(8)
            while x < canvas.width + u(8) {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + u(4), y: 0))
                path.addLine(to: CGPoint(x: x + u(4) + u(2.6), y: u(2.6)))
                path.addLine(to: CGPoint(x: x + u(2.6), y: u(2.6)))
                path.closeSubpath()
                cg.addPath(path)
                cg.fillPath()
                x += u(8)
            }
            cg.restoreGState()

            let stamp = Layout.stampRect
            rotated(cg, around: CGPoint(x: stamp.midX, y: stamp.midY), degrees: Layout.stampAngle) {
                drawStamp(photo, texts: texts, at: stamp.origin, sticker: false, cg)
            }

            // 下の「石川県より」と日付
            let fromY = canvas.height - Layout.fromBottom
            let left = Layout.fromInset, right = canvas.width - Layout.fromInset
            let fromFont = mincho(u(5.6))
            let lineTop = fromY - fromFont.lineHeight - u(2.6)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.25).cgColor)
            cg.fill(CGRect(x: left, y: lineTop, width: right - left, height: u(0.3)))
            let dateFont = sans(u(3.2), .regular, digits: true)
            var dateWidth: CGFloat = 0
            if let date = texts.date {
                dateWidth = (date as NSString).size(withAttributes: [.font: dateFont]).width
                text(date, font: dateFont, color: UIColor(white: 0x55 / 255, alpha: 1),
                     at: CGPoint(x: right - dateWidth, y: fromY - fromFont.lineHeight + (fromFont.ascender - dateFont.ascender)))
            }
            text(TravelStory.from(texts), font: fromFont, color: ink,
                 at: CGPoint(x: left, y: fromY - fromFont.lineHeight), maxWidth: right - left - dateWidth - u(3))
        }
    }

    static func stampSticker(_ photo: UIImage, texts: TravelStory.Texts) -> Output {
        // 切手と、左下の消印・波線が入る大きさ（回しても切れない余白）
        let stamp = Layout.stampSize
        let pad = u(14)
        let size = CGSize(width: ceil(stamp.width + pad * 2), height: ceil(stamp.height + pad * 2))
        return png(size: size) { cg in
            let origin = CGPoint(x: pad, y: pad)
            rotated(cg, around: CGPoint(x: size.width / 2, y: size.height / 2), degrees: Layout.stampAngle) {
                drawStamp(photo, texts: texts, at: origin, sticker: true, cg)
            }
        }
    }

    /// 切手の形。四角から、縁に半分かかる丸（目打ち）を抜く
    static func stampShape(_ rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addRect(rect)
        let r = Layout.stampPerfRadius, step = Layout.stampPerfStep
        var centers: [CGPoint] = []
        var x: CGFloat = 0
        while x <= rect.width + 0.5 {
            centers.append(CGPoint(x: rect.minX + x, y: rect.minY))
            centers.append(CGPoint(x: rect.minX + x, y: rect.maxY))
            x += step
        }
        var y: CGFloat = step
        while y < rect.height - 0.5 {
            centers.append(CGPoint(x: rect.minX, y: rect.minY + y))
            centers.append(CGPoint(x: rect.maxX, y: rect.minY + y))
            y += step
        }
        for c in centers { path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
        return path
    }

    static func drawStamp(_ photo: UIImage, texts: TravelStory.Texts, at origin: CGPoint, sticker: Bool,
                          _ cg: CGContext) {
        let rect = CGRect(origin: origin, size: Layout.stampSize)
        let shape = stampShape(rect)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: u(1.6)), blur: u(3),
                     color: UIColor.black.withAlphaComponent(0.28).cgColor)
        cg.addPath(shape)
        cg.setFillColor(stampPaper.cgColor)
        cg.fillPath(using: .evenOdd)
        cg.restoreGState()
        cg.saveGState()
        cg.addPath(shape)
        cg.clip(using: .evenOdd)
        grain(cg, in: rect, seed: 31)
        cg.restoreGState()

        // 写真（切手の絵）と額面
        let pad = Layout.stampPad
        let photoRect = CGRect(x: rect.minX + pad, y: rect.minY + pad, width: rect.width - pad * 2,
                               height: rect.height - pad * 2 - Layout.stampCaptionHeight)
        fill(photo, in: photoRect, cg)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = u(2)
        text("110", font: sans(u(6.4), .heavy, digits: true), color: .white, kern: -0.02,
             at: CGPoint(x: photoRect.minX + u(2.6), y: photoRect.minY + u(2)), shadow: shadow)

        // 下の字: JOURNEY POST と何日目（明朝）
        let capTop = photoRect.maxY + u(2.6)
        let capFont = sans(u(2.9), .heavy)
        let dayFont = mincho(u(4.6))
        if let caption = TravelStory.stampCaption(texts) {
            let width = (caption as NSString).size(withAttributes: [.font: dayFont]).width
            text(caption, font: dayFont, color: ink, kern: 0.04, at: CGPoint(x: photoRect.maxX - width, y: capTop))
        }
        text("JOURNEY POST", font: capFont, color: ink, kern: 0.2,
             at: CGPoint(x: photoRect.minX, y: capTop + dayFont.ascender - capFont.ascender))

        // 消印と波線（掠れ）
        let pm = (sticker ? Layout.postmarkStickerRect : Layout.postmarkRect).offsetBy(dx: rect.minX, dy: rect.minY)
        let wave: CGRect
        let waveAngle: CGFloat
        if sticker {
            wave = CGRect(x: rect.minX + u(20), y: rect.maxY + u(7) - u(12), width: u(46), height: u(12))
            waveAngle = -6
        } else {
            wave = CGRect(x: rect.maxX - u(12) - u(46), y: rect.minY - u(4.6), width: u(46), height: u(12))
            waveAngle = -14
        }
        if sticker {
            // ステッカーの消印は紙の丸に押す（透明の地の上で読めるように）
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: u(1)), blur: u(3),
                         color: UIColor.black.withAlphaComponent(0.3).cgColor)
            cg.setFillColor(stampPaper.cgColor)
            cg.fillEllipse(in: pm)
            cg.restoreGState()
        }
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        rotated(cg, around: CGPoint(x: wave.midX, y: wave.midY), degrees: waveAngle) {
            drawWaves(in: wave, cg)
        }
        rotated(cg, around: CGPoint(x: pm.midX, y: pm.midY), degrees: -14) {
            drawPostmark(texts, in: pm, cg)
        }
        // 掠れ: インクの乗らない所を抜く（決まった並びの点）
        cg.setBlendMode(.destinationOut)
        var r = Seeded(state: 47)
        let wear = pm.union(wave).insetBy(dx: -u(2), dy: -u(2))
        for _ in 0..<Int(wear.width * wear.height / 900) {
            let size = u(0.4) + r.next() * u(1.6)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.35 + r.next() * 0.65).cgColor)
            cg.fillEllipse(in: CGRect(x: wear.minX + r.next() * wear.width, y: wear.minY + r.next() * wear.height,
                                      width: size, height: size * (0.6 + r.next() * 0.8)))
        }
        cg.setBlendMode(.normal)
        cg.endTransparencyLayer()
    }

    static func drawWaves(in rect: CGRect, _ cg: CGContext) {
        let sx = rect.width / 100, sy = rect.height / 26
        cg.setStrokeColor(postInk.withAlphaComponent(0.62).cgColor)
        cg.setLineWidth(0.9 * sx)
        for line in [4.0, 13.0, 22.0] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + CGFloat(line) * sy))
            for i in 0..<8 {
                let x0 = CGFloat(i) * 12.5
                let up: CGFloat = i % 2 == 0 ? -4 : 4
                path.addQuadCurve(to: CGPoint(x: rect.minX + (x0 + 12.5) * sx, y: rect.minY + CGFloat(line) * sy),
                                  control: CGPoint(x: rect.minX + (x0 + 6.25) * sx,
                                                   y: rect.minY + (CGFloat(line) + up) * sy))
            }
            cg.addPath(path)
        }
        cg.strokePath()
    }

    static func drawPostmark(_ texts: TravelStory.Texts, in rect: CGRect, _ cg: CGContext) {
        let color = postInk.withAlphaComponent(0.86)
        cg.setStrokeColor(postInk.withAlphaComponent(0.8).cgColor)
        cg.setLineWidth(u(0.7))
        cg.strokeEllipse(in: rect.insetBy(dx: u(0.35), dy: u(0.35)))
        cg.setStrokeColor(postInk.withAlphaComponent(0.6).cgColor)
        cg.setLineWidth(u(0.35))
        cg.strokeEllipse(in: rect.insetBy(dx: u(1.6) + u(0.7), dy: u(1.6) + u(0.7)))

        let top = sans(u(3), .heavy)
        let mid = sans(u(4.6), .bold, digits: true)
        let low = mincho(u(3.4))
        var lines: [(String, UIFont, CGFloat)] = [(texts.placeLatin ?? "JOURNEY", top, 0.16)]
        if let date = texts.postmark { lines.append((date, mid, 0)) }
        lines.append((texts.place ?? TravelStory.onTheRoad, low, 0))
        let gap = u(0.8)
        let total = lines.reduce(0) { $0 + $1.1.lineHeight } + gap * CGFloat(lines.count - 1)
        var y = rect.midY - total / 2
        let width = rect.width - u(7)
        for (value, font, kern) in lines {
            text(value, font: font, color: color, kern: kern, at: CGPoint(x: rect.minX + u(3.5), y: y),
                 maxWidth: width, align: .center)
            y += font.lineHeight + gap
        }
    }

    // MARK: - 3 フィルムの帯（穴は抜いて、後ろのぼかした写真が透ける。コマの間に縁の番号）

    static func film(_ photos: [UIImage], texts: TravelStory.Texts) -> Output {
        jpeg { cg in
            let canvas = CGRect(origin: .zero, size: Layout.canvas)
            // 後ろ: 同じ写真のぼかし（暗さ 42%・彩度 1.2）
            if let lead = photos.first {
                if let blurred = blurred(lead) {
                    fill(blurred, in: canvas.insetBy(dx: -u(10), dy: -u(10)), cg)
                } else {
                    fill(lead, in: canvas, cg)
                }
                cg.setFillColor(UIColor.black.withAlphaComponent(0.58).cgColor)
                cg.fill(canvas)
            }

            let frames = max(1, min(3, photos.count))
            let strip = Layout.filmRect(frames: frames)
            // 帯の地（横に暗い → 少し明るい → 暗い）。穴は抜く
            let shape = CGMutablePath()
            shape.addRect(strip)
            for holeX in [strip.minX + Layout.filmHoleX, strip.maxX - Layout.filmHoleX - Layout.filmHoleWidth] {
                var y = strip.minY + Layout.filmHoleStart
                while y + Layout.filmHoleHeight <= strip.maxY {
                    shape.addRoundedRect(in: CGRect(x: holeX, y: y, width: Layout.filmHoleWidth,
                                                    height: Layout.filmHoleHeight),
                                         cornerWidth: u(0.5), cornerHeight: u(0.5))
                    y += Layout.filmHoleStep
                }
            }
            cg.saveGState()
            cg.addPath(shape)
            cg.clip(using: .evenOdd)
            let dark = UIColor(red: 0x0D / 255, green: 0x0C / 255, blue: 0x0B / 255, alpha: 1).cgColor
            let mid = UIColor(red: 0x1A / 255, green: 0x17 / 255, blue: 0x14 / 255, alpha: 1).cgColor
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [dark, mid, dark] as CFArray,
                                         locations: [0, 0.5, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: strip.minX, y: 0), end: CGPoint(x: strip.maxX, y: 0),
                                      options: [])
            }
            cg.restoreGState()

            // コマと縁の番号（真鍮・帯の黒の上）
            let edge = sans(u(2.6), .bold, digits: true)
            let left = strip.minX + Layout.filmPadX
            let width = Layout.filmFrameWidth
            var y = strip.minY + Layout.filmPadY
            func edgeRow(_ l: String, _ r: String) {
                let top = y + (Layout.filmEdgeHeight - edge.lineHeight) / 2
                text(l, font: edge, color: brass, kern: 0.16, at: CGPoint(x: left, y: top))
                text(r, font: edge, color: brass, kern: 0.16, at: CGPoint(x: left, y: top), maxWidth: width, align: .right)
                y += Layout.filmEdgeHeight
            }
            edgeRow("JOURNEY 400", "▸ 22A")
            for i in 0..<frames {
                let frame = CGRect(x: left, y: y, width: width, height: Layout.filmFrameHeight)
                cg.saveGState()
                cg.addPath(CGPath(roundedRect: frame, cornerWidth: u(0.6), cornerHeight: u(0.6), transform: nil))
                cg.clip()
                fill(photos[i], in: frame, cg)
                cg.restoreGState()
                y += Layout.filmFrameHeight
                edgeRow("\(23 + i)", "▸ \(23 + i)A")
            }

            // 下の2行（題は明朝・日付と何日目）
            let caption = TravelStory.filmCaption(texts)
            let box = Layout.filmCaptionRect(frames: frames)
            let titleFont = mincho(u(7))
            text(caption.title, font: titleFont, color: .white, at: CGPoint(x: box.minX, y: box.minY),
                 maxWidth: box.width, align: .center)
            // 2行目: 日付（細め・白 80%）と何日目（太め・白）を、中黒でなく余白（3cqw）で分けて並べる（2026-11-12）
            if !caption.sub.isEmpty {
                let y = box.minY + titleFont.lineHeight + u(1.4)
                let gap = u(3)
                let styled: [(String, UIFont, UIColor)] = caption.sub.enumerated().map { index, value in
                    let last = index == caption.sub.count - 1 && caption.sub.count > 1
                    return (value, sans(u(3.4), last ? .semibold : .regular, digits: true),
                            last ? .white : UIColor.white.withAlphaComponent(0.8))
                }
                let widths = styled.map { value, font, _ in
                    (value as NSString).size(withAttributes: [.font: font, .kern: 0.08 * font.pointSize]).width
                }
                var x = box.midX - (widths.reduce(0, +) + gap * CGFloat(styled.count - 1)) / 2
                for (index, (value, font, color)) in styled.enumerated() {
                    text(value, font: font, color: color, kern: 0.08, at: CGPoint(x: x, y: y))
                    x += widths[index] + gap
                }
            }
        }
    }

    /// ぼかした写真（模型 blur 5cqw・彩度 1.2）。小さく縮めてからぼかす（重くしない）
    static func blurred(_ image: UIImage) -> UIImage? {
        // 絵の上で 5cqw（54px）。写真は高さ 1920＋はみ出し 2×10cqw に敷くので、縮めた写真の上の px に直す
        SignatureShareCardRenderer.blurredBackdrop(image, longEdge: 540,
                                                   radiusFraction: Double(u(5)) / Double(Layout.canvas.height + u(20)),
                                                   saturation: 1.2)
    }
}
#endif
