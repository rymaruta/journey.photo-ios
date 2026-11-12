#if !os(Linux)
import UIKit
import CoreLocation
import CoreImage

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
        if let mark = UIImage(named: "BrandMark")?.withRenderingMode(.alwaysTemplate) {
            mark.withTintColor(.white).draw(in: CGRect(x: left, y: centerY - markSize / 2,
                                                       width: markSize, height: markSize))
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

    static func newCanvas(_ size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = cardScale
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    // MARK: - 展示札

    /// 小さな見出し（真鍮・字間を空けた大文字）。「PLACE」「CAMERA」など
    private static func drawEyebrow(_ text: String, at origin: CGPoint, size: CGFloat) {
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
            drawBrandHeader(centerY: L.headerCenter, left: L.contentLeft, right: L.contentRight,
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
            cg.setStrokeColor(brass.withAlphaComponent(ShareCardMap.Layout.lineAlpha).cgColor)
            cg.setLineWidth(ShareCardMap.Layout.lineWidth)
            cg.move(to: CGPoint(x: L.contentLeft, y: layout.ruleY))
            cg.addLine(to: CGPoint(x: L.contentLeft + L.leftColumnWidth, y: layout.ruleY))
            cg.strokePath()
            drawFadeAuthor(credit, avatarData: avatarData, top: layout.authorTop,
                           columnWidth: L.leftColumnWidth - 80, context: cg)

            // 撮影情報の表（ラベルつき）
            let exif = exifValues(credit)
            let entries: [(String, String)] = [("CAMERA", exif.camera), ("LENS", exif.lens), ("EXPOSURE", exif.exposure)]
            for (index, entry) in entries.enumerated() where !entry.1.isEmpty {
                let column = L.tableColumns[index]
                drawLabeledValue(label: entry.0, value: entry.1, x: column.x, top: layout.tableTop, width: column.width)
            }
            cg.setStrokeColor(brass.withAlphaComponent(0.3).cgColor)
            for x in [CGFloat(248), 456] {
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
            drawShade(cg, from: 0, to: F.topShadeHeight, stops: [
                (0, F.topShadeAlpha), (0.45, F.topShadeAlpha * 0.5), (1, 0)])
            drawShade(cg, from: layout.fadeTop, to: layout.photoBottom, stops: F.fadeStops)
            UIColor.black.setFill()
            cg.fill(CGRect(x: 0, y: layout.photoBottom, width: C.width, height: layout.height - layout.photoBottom))

            // 写真の上なので、字も住所も白（真鍮は黒い地の上だけ）
            drawBrandHeader(centerY: ShareCardMap.Layout.headerCenter, left: C.contentLeft, right: C.contentRight,
                            taglineSize: 24, addressColor: .white)

            // 右: 地図
            if let coordinate = credit.coords {
                let placeText = (credit.placeLines + [credit.location ?? ""]).joined(separator: ", ")
                CountryOutline.drawAtLocation(pin: coordinate, place: placeText,
                                              in: layout.mapRect, color: brass, context: cg)
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
            let exifLine = [exif.camera, exif.lens].filter { !$0.isEmpty }.joined(separator: " · ")
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

    // MARK: - 縦書き（2026-11-12・第8章）

    /// 縦書きの明朝（同梱の Shippori Mincho B1 Bold）。無い字は端末の字へ落ちる（`JPFont` の注記）
    static func tateFont(_ size: CGFloat) -> UIFont {
        if let font = UIFont(name: JPFont.displayName, size: size) { return font }
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    /// 縦の列の長さ。和文は字数×送り、欧文だけの字は横に倒した字の幅
    static func verticalLength(_ text: String, size: CGFloat, step: CGFloat) -> CGFloat {
        if ShareCardMap.isUprightVertical(text) { return CGFloat(text.count) * size * step }
        return (text as NSString).size(withAttributes: [.font: tateFont(size)]).width
    }

    /// 縦の列を描く。和文は1字ずつ立てて（長音・括弧は倒す）、欧文だけの字は行ごと右へ倒す。描いた長さを返す
    @discardableResult
    static func drawVertical(_ text: String, centerX: CGFloat, top: CGFloat, size: CGFloat, step: CGFloat,
                             color: UIColor, context cg: CGContext) -> CGFloat {
        let font = tateFont(size)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        guard ShareCardMap.isUprightVertical(text) else {
            cg.saveGState()
            cg.translateBy(x: centerX, y: top)
            cg.rotate(by: .pi / 2)
            (text as NSString).draw(at: CGPoint(x: 0, y: -font.lineHeight / 2), withAttributes: attributes)
            cg.restoreGState()
            return verticalLength(text, size: size, step: step)
        }
        for (index, character) in text.enumerated() {
            let glyph = String(character) as NSString
            let measured = glyph.size(withAttributes: attributes)
            cg.saveGState()
            cg.translateBy(x: centerX, y: top + CGFloat(index) * size * step + size / 2)
            if ShareCardMap.rotatesInVertical(character) { cg.rotate(by: .pi / 2) }
            glyph.draw(at: CGPoint(x: -measured.width / 2, y: -font.lineHeight / 2), withAttributes: attributes)
            cg.restoreGState()
        }
        return CGFloat(text.count) * size * step
    }

    /// 横の影（x0 から x1 へ・`stops` は 0〜1 の位置と黒の濃さ）
    static func drawSideShade(_ cg: CGContext, fromX x0: CGFloat, toX x1: CGFloat, height: CGFloat,
                              stops: [(location: CGFloat, alpha: CGFloat)]) {
        let colors = stops.map { UIColor.black.withAlphaComponent($0.alpha).cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                        locations: stops.map { $0.location }) else { return }
        cg.saveGState()
        cg.clip(to: CGRect(x: min(x0, x1), y: 0, width: abs(x1 - x0), height: height))
        cg.drawLinearGradient(gradient, start: CGPoint(x: x0, y: 0), end: CGPoint(x: x1, y: 0), options: [])
        cg.restoreGState()
    }

    private static func brandWordFont(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    /// ロゴの1行（マーク＋「Journey Photo」）の幅
    static func brandRowWidth(markSize: CGFloat, wordSize: CGFloat) -> CGFloat {
        markSize * 1.38 + ("Journey Photo" as NSString).size(withAttributes: [.font: brandWordFont(wordSize)]).width
    }

    /// ロゴの1行（マーク＋「Journey Photo」）。縦の中心が centerY
    static func drawBrandRow(left: CGFloat, centerY: CGFloat, markSize: CGFloat, wordSize: CGFloat,
                             color: UIColor) {
        if let mark = UIImage(named: "BrandMark")?.withRenderingMode(.alwaysTemplate) {
            mark.withTintColor(color).draw(in: CGRect(x: left, y: centerY - markSize / 2,
                                                      width: markSize, height: markSize))
        }
        let font = brandWordFont(wordSize)
        ("Journey Photo" as NSString).draw(at: CGPoint(x: left + markSize * 1.38, y: centerY - font.lineHeight / 2),
                                           withAttributes: [.font: font, .foregroundColor: color])
    }

    /// 撮影者の頭文字（落款の字）。欧文は大文字
    static func authorInitial(_ credit: Credit) -> String {
        let initial = String(credit.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
        return initial.isEmpty ? "J" : initial
    }

    /// @名（無ければ名前）
    static func handle(_ credit: Credit) -> String {
        let username = credit.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")) ?? ""
        return username.isEmpty ? "" : "@" + username
    }

    /// 縦書き型。写真を全面に敷き、右の縦の帯だけ暗くして（雪・青空でも白い字が立つ）、地名を縦の明朝で置く。
    /// 地名の下に白い落款（撮影者の頭文字）。左下は @名とロゴだけ。真鍮は使わない（字はすべて写真の上）
    static func renderTate(photo: UIImage, credit: Credit, ratio: Ratio) -> Data? {
        typealias T = ShareCardMap.TateLayout
        let layout = T(ratio: ratio)
        let canvas = CGSize(width: T.width, height: layout.height)
        return newCanvas(canvas).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))
            drawPhotoFill(photo, in: CGRect(origin: .zero, size: canvas), context: cg)
            drawSideShade(cg, fromX: T.sideShadeFrom, toX: T.sideShadeTo, height: layout.height,
                          stops: T.sideShadeStops)
            drawShade(cg, from: layout.bottomShadeTop, to: layout.height, stops: T.bottomShadeStops)

            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 18, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            let lines = credit.placeLines
            var sealTop = layout.placeTop
            var placeSize = layout.placeFontSize
            if let first = lines.first {
                // 縦の列が下の余白に届くなら縮める（下限 72）。下限でも届くなら末尾を「…」で切る
                let room = layout.columnBottom - layout.placeTop - T.sealGap - layout.sealSize
                if ShareCardMap.isUprightVertical(first) {
                    placeSize = layout.fittedPlaceSize(count: first.count)
                } else {
                    while placeSize > T.placeMinimumFontSize,
                          verticalLength(first, size: placeSize, step: T.placeStep) > room { placeSize -= 2 }
                }
                var place = first
                while place.count > 1, verticalLength(place, size: placeSize, step: T.placeStep) > room {
                    place = String(place.dropLast(place.hasSuffix("…") ? 2 : 1)) + "…"
                }
                let used = drawVertical(place, centerX: layout.placeCenterX(size: placeSize), top: layout.placeTop,
                                        size: placeSize, step: T.placeStep, color: .white, context: cg)
                sealTop = layout.placeTop + used + T.sealGap

                // 左の列: 市区町村と、撮った年月（年月は 90%）
                let subX = layout.subCenterX(placeSize: placeSize)
                var y = layout.subTop(placeSize: placeSize)
                if lines.count > 1 {
                    let sub = lines[1].trimmingCharacters(in: CharacterSet(charactersIn: "（）()"))
                    var subSize = T.subFontSize
                    while subSize > 32,
                          y + verticalLength(sub, size: subSize, step: T.subStep) > layout.columnBottom {
                        subSize -= 2
                    }
                    y += drawVertical(sub, centerX: subX, top: y, size: subSize, step: T.subStep,
                                      color: .white, context: cg) + subSize * 0.8
                }
                if let taken = credit.taken {
                    let text = ShareCardMap.isUprightVertical(first)
                        ? ShareCardMap.TakenDate.kanjiYearMonth(taken)
                        : ShareCardMap.TakenDate.englishMonthYear(taken)
                    if y + verticalLength(text, size: T.dateFontSize, step: T.dateStep) <= layout.columnBottom {
                        drawVertical(text, centerX: subX, top: y, size: T.dateFontSize, step: T.dateStep,
                                     color: UIColor.white.withAlphaComponent(0.9), context: cg)
                    }
                }
            }
            // 落款（白い角印。撮影者の頭文字）。わずかに傾けて押した形
            let seal = layout.sealSize
            cg.saveGState()
            cg.translateBy(x: layout.placeCenterX(size: placeSize), y: sealTop + seal / 2)
            cg.rotate(by: -0.04)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
            cg.setLineWidth(5)
            cg.addPath(UIBezierPath(roundedRect: CGRect(x: -seal / 2, y: -seal / 2, width: seal, height: seal),
                                    cornerRadius: 6).cgPath)
            cg.strokePath()
            let initialFont = tateFont(seal * 0.6)
            let initialAttributes: [NSAttributedString.Key: Any] = [
                .font: initialFont, .foregroundColor: UIColor.white.withAlphaComponent(0.95)]
            let initial = authorInitial(credit) as NSString
            let initialWidth = initial.size(withAttributes: initialAttributes).width
            initial.draw(at: CGPoint(x: -initialWidth / 2, y: -initialFont.lineHeight / 2 + 3),
                         withAttributes: initialAttributes)
            cg.restoreGState()
            cg.restoreGState()

            // 左下: @名（無ければ名前）とロゴ。機材の行と URL は置かない（見える字を増やさない）
            let who = handle(credit).isEmpty ? credit.name.trimmingCharacters(in: .whitespacesAndNewlines) : handle(credit)
            if !who.isEmpty {
                draw(who, at: CGPoint(x: T.margin, y: layout.usernameTop), maxWidth: T.leftColumnWidth,
                     size: T.usernameFontSize, color: .white, bold: true)
            }
            drawBrandRow(left: T.margin, centerY: layout.brandCenterY, markSize: T.brandMarkSize,
                         wordSize: T.brandWordSize, color: .white)
        }
    }

    // MARK: - インスタント（2026-11-12・第8章）

    /// 紙の色（生成り）と墨。共有の絵の中だけで使い、アプリの画面には使わない
    static let paper = UIColor(red: 243/255, green: 238/255, blue: 227/255, alpha: 1)
    static let ink = UIColor(red: 7/255, green: 9/255, blue: 10/255, alpha: 1)
    private static let tape = UIColor(red: 232/255, green: 222/255, blue: 196/255, alpha: 0.7)

    /// 紙の粒（180×180 の決まった乱数の点。毎回同じ絵になる）
    private static let grain: UIImage = {
        let side = 180
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            var seed: UInt32 = 42
            func next() -> CGFloat {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return CGFloat(seed) / 4_294_967_296
            }
            for y in 0..<side {
                for x in 0..<side {
                    let value: CGFloat = next() < 0.5 ? 60 / 255 : 1
                    UIColor(white: value, alpha: next() * 16 / 255).setFill()
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// 同じ写真をぼかして暗く敷く（黒一色より、格子の中で色が出る）。4 分の 1 に縮めてからぼかすので軽い
    static func drawBlurredBackdrop(_ photo: UIImage, size: CGSize, context cg: CGContext) {
        let bleed: CGFloat = 120
        let target = CGRect(x: -bleed, y: -bleed, width: size.width + bleed * 2, height: size.height + bleed * 2)
        let small = CGSize(width: (target.width / 4).rounded(), height: (target.height / 4).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let reduced = UIGraphicsImageRenderer(size: small, format: format).image { inner in
            drawPhotoFill(photo, in: CGRect(origin: .zero, size: small), context: inner.cgContext)
        }
        if let cgImage = reduced.cgImage {
            let input = CIImage(cgImage: cgImage)
            let blurred = input.clampedToExtent()
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.15])
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 10])
                .cropped(to: input.extent)
            if let output = ciContext.createCGImage(blurred, from: input.extent) {
                UIImage(cgImage: output).draw(in: target)
            }
        }
        UIColor.black.withAlphaComponent(1 - ShareCardMap.InstantLayout.backdropBrightness).setFill()
        cg.fill(CGRect(origin: .zero, size: size))
    }

    /// テープの形（幅 300・高さ 64、上下の端はぎざぎざ）。真ん中が原点
    private static func tapePath() -> UIBezierPath {
        typealias I = ShareCardMap.InstantLayout
        let w = I.tapeSize.width, h = I.tapeSize.height
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -w / 2, y: -h / 2))
        for i in 0...6 {
            path.addLine(to: CGPoint(x: -w / 2 + w * CGFloat(i) / 6, y: -h / 2 + (i % 2 == 1 ? 3 : -2)))
        }
        for i in 0...6 {
            path.addLine(to: CGPoint(x: w / 2 - w * CGFloat(i) / 6, y: h / 2 + (i % 2 == 1 ? -3 : 2)))
        }
        path.close()
        return path
    }

    /// インスタント型。生成りの紙（粒・左上の光・上にテープ）に写真を貼り、下の余白に地名を墨で書く。
    /// 周りは同じ写真をぼかして暗く敷く。紙の下にロゴと Web の住所
    static func renderInstant(photo: UIImage, credit: Credit, ratio: Ratio) -> Data? {
        typealias I = ShareCardMap.InstantLayout
        let layout = I(ratio: ratio)
        let canvas = CGSize(width: I.width, height: layout.height)
        return newCanvas(canvas).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))
            drawBlurredBackdrop(photo, size: canvas, context: cg)

            let paperRect = layout.paperRect
            cg.saveGState()
            cg.translateBy(x: paperRect.midX, y: paperRect.midY)
            cg.rotate(by: I.paperTiltDegrees * .pi / 180)
            cg.translateBy(x: -paperRect.midX, y: -paperRect.midY)

            // 紙: 影・生成り・左上の光・粒
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 16), blur: 44,
                         color: UIColor.black.withAlphaComponent(0.7).cgColor)
            paper.setFill()
            cg.fill(paperRect)
            cg.restoreGState()
            let lightColors = [UIColor.white.withAlphaComponent(0.35).cgColor,
                               UIColor(red: 120/255, green: 100/255, blue: 70/255, alpha: 0.10).cgColor] as CFArray
            if let light = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: lightColors,
                                      locations: [0, 1]) {
                cg.saveGState()
                cg.clip(to: paperRect)
                cg.drawLinearGradient(light, start: paperRect.origin,
                                      end: CGPoint(x: paperRect.maxX, y: paperRect.maxY), options: [])
                cg.restoreGState()
            }
            UIColor(patternImage: grain).setFill()
            cg.fill(paperRect)

            // 写真と、写真の縁の細い影
            drawPhotoFill(photo, in: layout.photoRect, context: cg)
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.22).cgColor)
            cg.setLineWidth(2)
            cg.stroke(layout.photoRect.insetBy(dx: 1, dy: 1))

            // 下の余白: 地名（明朝・墨）と、撮った日と @名（墨 62%）。右に小さな地図（墨の細線）
            let place = placeOneLine(credit)
            if !place.isEmpty {
                drawFittedSerif(place, at: CGPoint(x: layout.photoRect.minX, y: layout.placeTop),
                                maxWidth: layout.textWidth, size: layout.placeFontSize,
                                minimumSize: I.placeMinimumFontSize, color: ink)
            }
            let meta = [credit.taken.map { ShareCardMap.TakenDate.dotted($0) } ?? "", handle(credit)]
                .filter { !$0.isEmpty }.joined(separator: "  ")
            if !meta.isEmpty {
                draw(meta, at: CGPoint(x: layout.photoRect.minX, y: layout.metaTop), maxWidth: layout.textWidth,
                     size: I.metaFontSize, color: ink.withAlphaComponent(0.62))
            }
            if let coordinate = credit.coords {
                // 県は塗らない（小さな地図で墨の塊にしない）
                CountryOutline.drawAtLocation(pin: coordinate, place: nil, in: layout.mapRect, color: ink, context: cg)
            }

            // 貼ったテープ（紙の上端の真ん中・4° 傾ける）
            cg.saveGState()
            cg.translateBy(x: paperRect.midX, y: paperRect.minY + 4)
            cg.rotate(by: I.tapeTiltDegrees * .pi / 180)
            cg.addPath(tapePath().cgPath)
            cg.clip()
            let tapeBox = CGRect(x: -I.tapeSize.width / 2 - 4, y: -I.tapeSize.height / 2 - 4,
                                 width: I.tapeSize.width + 8, height: I.tapeSize.height + 8)
            tape.setFill()
            cg.fill(tapeBox)
            UIColor(patternImage: grain).setFill()
            cg.fill(tapeBox)
            cg.restoreGState()
            cg.restoreGState()

            // 紙の下: ロゴ（真ん中）と Web の住所
            let rowWidth = brandRowWidth(markSize: I.brandMarkSize, wordSize: I.brandWordSize)
            drawBrandRow(left: I.width / 2 - rowWidth / 2, centerY: layout.brandCenterY,
                         markSize: I.brandMarkSize, wordSize: I.brandWordSize, color: .white)
            draw(ShareCardMap.Layout.siteAddress, at: CGPoint(x: 0, y: layout.addressTop), maxWidth: I.width,
                 size: I.addressFontSize, color: UIColor.white.withAlphaComponent(0.8), alignment: .center)
        }
    }
}
#endif
