#if !os(Linux)
import UIKit
import CoreText

/// 共有の絵「雑誌」を描く（寸法・置き方・字の中身は `MagazineCard`）。ストーリーと投稿の両方から呼ぶ。
///
/// - 全面に敷く（切れる量 8% 以下）: 写真で覆い、題を上か下の静かな端に。面は暗くしない
/// - それ以外: 余白をぼかした同じ写真（黒 32%）で埋め、写真を切らずに置き、字はすべて余白に（写真の上に字を載せない）
/// - 字ごとに、字の画素の下の地のいちばん明るい所を測り、明暗の比（本文 4.5:1・見出し 7:1）に届くまで
///   字の形を太らせた薄い影を重ねる（`MagazineCard.Shadow`）。暗い地では影を置かない
/// - 字は白と、不透明の灰（`MagazineCard.Ink`）。真鍮は使わない（写真・ぼかした写真の上・板「黒塗りの真鍮」）。区切りに「・」を使わない
///
/// 地の画素を描きながら読むので、`UIGraphicsImageRenderer` ではなく自前の sRGB のビットマップに描く（上下を返して UIKit の座標）。
/// 書き出しは描き直した画素だけなので、元の写真の EXIF（位置）は引き継がない。倍率は 1
enum MagazineCardRenderer {
    typealias M = MagazineCard

    /// 1本の字
    struct Item {
        let text: String
        let font: UIFont
        /// 灰（0〜1）。`MagazineCard.Ink`
        let ink: Double
        /// 字間（字の大きさに対する倍率）
        var kern: CGFloat = 0
        let x: CGFloat
        let y: CGFloat
        /// 描く幅（最後の字の後ろの字間を除く）
        let width: CGFloat
        /// 幅に入らず末尾を「…」にした
        var truncated = false
        /// 点検に記録する枠の高さ（字の大きさに対する倍率の上限）。題の2行は行の間 1.25 より低く
        var boxFactor: CGFloat = 1.3

        var color: UIColor { UIColor(red: CGFloat(ink), green: CGFloat(ink), blue: CGFloat(ink), alpha: 1) }
        var kernPoints: CGFloat { kern * font.pointSize }
        var box: CGRect {
            CGRect(x: x, y: y, width: width, height: min(font.lineHeight, font.pointSize * boxFactor))
        }
    }

    /// 描いている絵の画素（RGBA・行の 0 が上）
    struct Pixels {
        let base: UnsafeMutablePointer<UInt8>
        let width: Int
        let height: Int
        let bytesPerRow: Int

        func luminance(x: Int, y: Int) -> Double {
            let i = y * bytesPerRow + x * 4
            return MagazineCardRenderer.luminance(base[i], base[i + 1], base[i + 2])
        }
    }

    /// sRGB 0〜255 → 線形（WCAG の式・`ShareCardSafeArea.luminance` と同じ）
    static let linear: [Double] = (0..<256).map { value in
        let c = Double(value) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        0.2126 * linear[Int(r)] + 0.7152 * linear[Int(g)] + 0.0722 * linear[Int(b)]
    }

    // MARK: - 描く

    /// 1枚の JPEG を描く
    static func render(photo: UIImage, texts: M.Texts, frame: M.Frame) -> Data? {
        let width = Int(M.width), height = Int(frame.height)
        guard photo.size.width > 0, photo.size.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                 space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = cg.data else { return nil }
        let pixels = Pixels(base: raw.bindMemory(to: UInt8.self, capacity: cg.bytesPerRow * height),
                            width: width, height: height, bytesPerRow: cg.bytesPerRow)
        // UIKit の座標（左上が原点）にそろえる
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: 1, y: -1)
        cg.interpolationQuality = .high
        UIGraphicsPushContext(cg)
        defer { UIGraphicsPopContext() }
        let canvas = CGRect(x: 0, y: 0, width: M.width, height: frame.height)

        let aspect = photo.size.width / photo.size.height
        let full = M.isFullBleed(aspect: aspect, in: frame)
        let head = headParts(texts, full: full, frame: frame)
        var layout = M.layout(aspect: aspect, in: frame, head: head.metrics, hasExif: texts.hasExif)

        // 地と写真
        UIColor.black.setFill()
        cg.fill(canvas)
        if !layout.full {
            if let soft = softened(photo) {
                let scale = max(M.width / photo.size.width, frame.height / photo.size.height) * M.Backdrop.overscan
                let w = photo.size.width * scale, h = photo.size.height * scale
                UIImage(cgImage: soft).draw(in: CGRect(x: (M.width - w) / 2, y: (frame.height - h) / 2, width: w, height: h))
            }
            UIColor(white: 0, alpha: CGFloat(M.Backdrop.dim)).setFill()
            cg.fill(canvas)
        }
        photo.draw(in: layout.photo)

        // 全面のときだけ、上と下の端の静かなほうに題（利用者は選ばない）
        if layout.full {
            let top = sample(M.edgeSample(.top, in: frame), pixels)
            let bottom = sample(M.edgeSample(.bottom, in: frame), pixels)
            let edge = M.quieterEdge(top: top, bottom: bottom)
            layout = M.layout(aspect: aspect, in: frame, head: head.metrics, hasExif: texts.hasExif, edge: edge)
        }

        let band = bandParts(texts.volume, top: layout.bandTop)
        var items = band.items
        items += head.items(titleTop: layout.titleTop, subTop: layout.subTop)
        if let exifTop = layout.exifTop {
            items += exifItems(texts, top: exifTop)
        }

        // 字の形の影（明暗の比が届くまで）。点検の「部品を描かない絵」にも同じ影を置く（影は地の一部）
        for item in items {
            let mask = glyphMask(item, pixels)
            let target = M.targetContrast(fontSize: item.font.pointSize)
            var pass = 0
            while pass < M.Shadow.maximumPasses,
                  M.contrast(ink: item.ink, background: maxLuminance(mask, pixels)) < target {
                drawShadow(item, pass: pass, cg: cg)
                pass += 1
            }
        }

        // 帯の細い線（飾り）と字
        if let rule = band.rule, ShareCardProbe.drawsContent {
            UIColor(white: 1, alpha: CGFloat(M.Ink.rule)).setFill()
            cg.fill(rule)
        }
        for item in items where ShareCardProbe.note(.text, item.text, rect: item.box, color: item.color,
                                                    fontSize: item.font.pointSize, truncated: item.truncated) {
            draw(item, color: item.color, dx: 0)
        }

        guard let image = cg.makeImage() else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.93)
    }

    // MARK: - 帯

    static func bandParts(_ volume: Int?, top: CGFloat) -> (items: [Item], rule: CGRect?) {
        typealias B = M.Band
        let eyebrowFont = sans(B.eyebrowSize, .medium)
        let eyebrowWidth = measure(B.eyebrow, font: eyebrowFont, kern: B.eyebrowKern)
        var items = [Item(text: B.eyebrow, font: eyebrowFont, ink: M.Ink.text, kern: B.eyebrowKern,
                          x: M.margin, y: top + B.eyebrowY, width: eyebrowWidth)]
        var volLeft = M.right
        if let volume {
            let number = "\(volume)"
            let numberFont = KoyomiCardRenderer.mincho(B.numberSize, for: number)
            let numberWidth = measure(number, font: numberFont, kern: 0)
            let volFont = UIFont.italicSystemFont(ofSize: B.volSize)
            let volWidth = measure(B.vol, font: volFont, kern: 0)
            let volX = M.right - numberWidth - B.volGap - volWidth
            items.append(Item(text: B.vol, font: volFont, ink: M.Ink.vol, x: volX, y: top + B.volY, width: volWidth))
            items.append(Item(text: number, font: numberFont, ink: M.Ink.text, x: M.right - numberWidth,
                              y: top + B.numberY, width: numberWidth))
            volLeft = volX
        }
        let ruleX = M.margin + eyebrowWidth + B.ruleGap
        let ruleWidth = min(B.ruleWidth, volLeft - B.ruleGap - ruleX)
        let rule = ruleWidth >= B.ruleMinimumWidth
            ? CGRect(x: ruleX, y: top + B.ruleY, width: ruleWidth, height: B.ruleHeight) : nil
        return (items, rule)
    }

    // MARK: - 題と撮影地の行

    struct HeadParts {
        let metrics: M.Head
        let title: M.FittedTitle?
        let titleFont: UIFont?
        let place: (text: String, width: CGFloat, truncated: Bool)?
        let date: (text: String, width: CGFloat)?
        let subSize: CGFloat

        func items(titleTop: CGFloat, subTop: CGFloat) -> [Item] {
            var items: [Item] = []
            if let title, let titleFont {
                for (index, line) in title.lines.enumerated() {
                    let last = index == title.lines.count - 1
                    let width = min(M.contentWidth, MagazineCardRenderer.measure(line, font: titleFont, kern: M.Title.kern))
                    items.append(Item(text: line, font: titleFont, ink: M.Ink.text, kern: M.Title.kern, x: M.margin,
                                      y: titleTop + CGFloat(index) * title.size * M.Title.lineHeight, width: width,
                                      truncated: last && title.truncated, boxFactor: 1.2))
                }
            }
            var x = M.margin
            if let place {
                items.append(Item(text: place.text, font: MagazineCardRenderer.sans(subSize, .semibold), ink: M.Ink.text,
                                  x: x, y: subTop, width: place.width, truncated: place.truncated))
                x += place.width + M.Sub.dateGap
            }
            if let date {
                items.append(Item(text: date.text, font: MagazineCardRenderer.sans(subSize, .light), ink: M.Ink.date,
                                  x: x, y: subTop, width: date.width))
            }
            return items
        }
    }

    /// 題を幅に入れ（縮める・2行・最後は「…」）、撮影地と日付の行を幅に入れる（33 まで縮める・大きい単位だけにする・「…」）
    static func headParts(_ texts: M.Texts, full: Bool, frame: M.Frame) -> HeadParts {
        var fitted: M.FittedTitle?
        var titleFont: UIFont?
        if let title = texts.title {
            let fit = M.fitTitle(title, base: M.titleSize(full: full, frame: frame)) { text, size in
                measure(text, font: KoyomiCardRenderer.mincho(size, for: title), kern: M.Title.kern)
            }
            fitted = fit
            titleFont = KoyomiCardRenderer.mincho(fit.size, for: title)
        }
        // 撮影地と日付の1行
        func widths(_ place: String?, size: CGFloat) -> (CGFloat, CGFloat) {
            let p = place.map { measure($0, font: sans(size, .semibold), kern: 0) } ?? 0
            let d = texts.date.map { measure($0, font: sans(size, .light), kern: 0) } ?? 0
            return (p, d)
        }
        func total(_ w: (CGFloat, CGFloat), hasPlace: Bool) -> CGFloat {
            w.0 + w.1 + (hasPlace && texts.date != nil ? M.Sub.dateGap : 0)
        }
        var subSize = M.Sub.size
        var placeText = texts.place
        var fits = false
        for candidate in [texts.place, texts.placeFallback].compactMap({ $0 }) {
            var size = M.Sub.size
            while size >= M.Sub.minimumSize {
                if total(widths(candidate, size: size), hasPlace: true) <= M.contentWidth {
                    fits = true
                    break
                }
                size -= 1
            }
            if fits { subSize = size; placeText = candidate; break }
        }
        if texts.place == nil { fits = true }
        if !fits { subSize = M.Sub.minimumSize; placeText = texts.place }
        let w = widths(placeText, size: subSize)
        var place: (String, CGFloat, Bool)?
        if let placeText {
            let room = M.contentWidth - (texts.date != nil ? w.1 + M.Sub.dateGap : 0)
            place = (placeText, min(w.0, room), w.0 > room)
        }
        let date = texts.date.map { ($0, w.1) }
        let metrics = M.Head(titleSize: fitted?.size ?? 0, titleLines: fitted?.lines.count ?? 0,
                             hasSub: place != nil || date != nil)
        return HeadParts(metrics: metrics, title: fitted, titleFont: titleFont,
                         place: place.map { (text: $0.0, width: $0.1, truncated: $0.2) },
                         date: date.map { (text: $0.0, width: $0.1) }, subSize: subSize)
    }

    /// 撮影の値の行。入らなければカメラを落とし、それでも入らなければ後ろの値から落とす（33px より小さくしない）
    static func exifItems(_ texts: M.Texts, top: CGFloat) -> [Item] {
        var parts: [(String, UIFont)] = texts.values.map { ($0, sans(M.Exif.size, .regular)) }
        if let camera = texts.camera { parts.insert((camera, sans(M.Exif.size, .medium)), at: 0) }
        func width(_ list: [(String, UIFont)]) -> CGFloat {
            list.map { measure($0.0, font: $0.1, kern: 0) }.reduce(0, +) + CGFloat(max(0, list.count - 1)) * M.Exif.gap
        }
        if width(parts) > M.contentWidth, texts.camera != nil { parts.removeFirst() }
        while width(parts) > M.contentWidth, !parts.isEmpty { parts.removeLast() }
        var x = M.margin
        return parts.map { text, font in
            let w = measure(text, font: font, kern: 0)
            defer { x += w + M.Exif.gap }
            return Item(text: text, font: font, ink: M.Ink.exif, x: x, y: top, width: w)
        }
    }

    // MARK: - 字の下回り

    static func sans(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    static func attributes(_ font: UIFont, color: UIColor, kern: CGFloat,
                           truncating: Bool = false) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        if truncating {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            attributes[.paragraphStyle] = paragraph
        }
        return attributes
    }

    /// 字の幅（最後の字の後ろの字間を除く）
    static func measure(_ text: String, font: UIFont, kern: CGFloat) -> CGFloat {
        let points = kern * font.pointSize
        let width = (text as NSString).size(withAttributes: [.font: font, .kern: points]).width
        return ceil(width - (points > 0 && !text.isEmpty ? points : 0))
    }

    /// 字を描く（`dx` は影の絵を外へ出して描くときのずらし）。切り詰めた字は幅の中で「…」
    static func draw(_ item: Item, color: UIColor, dx: CGFloat, extra: [NSAttributedString.Key: Any] = [:]) {
        var attrs = attributes(item.font, color: color, kern: item.kernPoints, truncating: item.truncated)
        attrs.merge(extra) { _, new in new }
        let text = item.text as NSString
        if item.truncated {
            text.draw(in: CGRect(x: item.x + dx, y: item.y, width: item.width + item.kernPoints + 1,
                                 height: item.font.lineHeight + 2), withAttributes: attrs)
        } else {
            text.draw(at: CGPoint(x: item.x + dx, y: item.y), withAttributes: attrs)
        }
    }

    /// 字の形を太らせた薄い影を1回。字そのものは絵の外（左へ 4000）に描き、影だけを右へ 4000 ずらして字の所に落とす
    static let shadowShift: CGFloat = 4000

    static func drawShadow(_ item: Item, pass: Int, cg: CGContext) {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: shadowShift, height: 0),
                     blur: M.Shadow.blur(size: item.font.pointSize, pass: pass),
                     color: UIColor(white: 0, alpha: CGFloat(M.Shadow.alpha)).cgColor)
        // 線の幅は字の大きさの %（負は塗りと線の両方）。字を字の 10% 太らせた形
        draw(item, color: .black, dx: -shadowShift,
             extra: [.strokeColor: UIColor.black, .strokeWidth: -M.Shadow.spread * 100])
        cg.restoreGState()
    }

    /// 字の画素の所（絵の画素の番号）。字だけを小さな絵に描き、少しでも塗られた画素
    static func glyphMask(_ item: Item, _ pixels: Pixels) -> [Int] {
        let pad: CGFloat = 4
        let originX = floor(item.x) - pad, originY = floor(item.y) - pad
        let w = Int(ceil(item.width + item.kernPoints + pad * 2 + 2))
        let h = Int(ceil(item.font.lineHeight + pad * 2 + 2))
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let mask = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = mask.data else { return [] }
        mask.translateBy(x: 0, y: CGFloat(h))
        mask.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(mask)
        let local = Item(text: item.text, font: item.font, ink: 1, kern: item.kern, x: item.x - originX,
                         y: item.y - originY, width: item.width, truncated: item.truncated)
        draw(local, color: .white, dx: 0)
        UIGraphicsPopContext()
        let bytes = raw.bindMemory(to: UInt8.self, capacity: mask.bytesPerRow * h)
        var indices: [Int] = []
        let x0 = Int(originX), y0 = Int(originY)
        for y in 0..<h {
            let py = y0 + y
            guard py >= 0, py < pixels.height else { continue }
            for x in 0..<w where bytes[y * mask.bytesPerRow + x * 4 + 3] > 0 {
                let px = x0 + x
                guard px >= 0, px < pixels.width else { continue }
                indices.append(py * pixels.width + px)
            }
        }
        return indices
    }

    /// 字の画素の下の地のいちばん明るい所（相対輝度）。点検 `ShareCardAuditTests` と同じく最大で見る
    static func maxLuminance(_ mask: [Int], _ pixels: Pixels) -> Double {
        var best = 0.0
        for index in mask {
            best = max(best, pixels.luminance(x: index % pixels.width, y: index / pixels.width))
        }
        return best
    }

    /// 所の明るさ（4画素おき）
    static func sample(_ rect: CGRect, _ pixels: Pixels) -> [Double] {
        let x0 = max(0, Int(rect.minX)), x1 = min(pixels.width, Int(rect.maxX))
        let y0 = max(0, Int(rect.minY)), y1 = min(pixels.height, Int(rect.maxY))
        guard x0 < x1, y0 < y1 else { return [] }
        var values: [Double] = []
        values.reserveCapacity((x1 - x0) * (y1 - y0) / 16 + 1)
        for y in stride(from: y0, to: y1, by: 4) {
            for x in stride(from: x0, to: x1, by: 4) { values.append(pixels.luminance(x: x, y: y)) }
        }
        return values
    }

    /// ぼかした写真（縮めて広げる・模型の `softCopy`。18 → 72 幅）
    static func softened(_ photo: UIImage) -> CGImage? {
        var current = photo
        for step in M.Backdrop.steps {
            let source = current
            let size = CGSize(width: step, height: max(2, (step * source.size.height / source.size.width).rounded()))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            current = UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.interpolationQuality = .high
                source.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        return current.cgImage
    }
}
#endif
