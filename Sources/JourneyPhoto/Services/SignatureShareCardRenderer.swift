import UIKit
import MapKit
import ImageIO

/// SNS向けの1枚画像。写真と帰属情報を画素に焼き込み、元画像のEXIFを引き継がない。
/// デザイン: docs/design/ios-artifact/DesignSystem.dc.html（黒塗りの真鍮）
enum SignatureShareCardRenderer {
    enum Ratio: Double {
        case portrait = 0.8
        case story = 0.5625
        case square = 1
    }

    struct Credit {
        let name: String
        let username: String?
        let location: String?
        let coords: CLLocationCoordinate2D?
        let camera: String?
        let lens: String?
        let exposure: String?
        let aperture: String?
        let iso: Int?
        let verified: Bool
        let proStyle: ProMarkStyle?
        let early: Bool
        let badge: EarnedBadge?
    }

    private static let surface = UIColor(red: 14/255, green: 14/255, blue: 15/255, alpha: 1)
    private static let brass = UIColor(red: 201/255, green: 166/255, blue: 107/255, alpha: 1)
    private static let secondary = UIColor(red: 184/255, green: 184/255, blue: 184/255, alpha: 1)

    #if os(Linux)
    // LinuxのSDK模型にはCoreGraphics/MapKit描画APIがない。実描画はiOSのXcodeで検証する。
    static func render(_ data: Data, credit: Credit, ratio: Ratio = .portrait, avatarData: Data? = nil) async -> Data? { nil }
    #else
    static func render(_ data: Data, credit: Credit, ratio: Ratio = .portrait, avatarData: Data? = nil) async -> Data? {
        // 1080px幅のSNSカードに原本の全画素を展開しない。
        // 画質の余裕を持たせて最大3072pxへ縮小デコードし、失敗時は従来方式へ戻す。
        let photo: UIImage?
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3072,
                kCGImageSourceShouldCacheImmediately: true
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                photo = UIImage(cgImage: thumbnail)
            } else {
                photo = UIImage(data: data)
            }
        } else {
            photo = UIImage(data: data)
        }
        guard let photo, photo.size.width > 0, photo.size.height > 0 else { return nil }
        let width: CGFloat = 1080
        let height = width / CGFloat(ratio.rawValue)
        let canvas = CGSize(width: width, height: height)
        // 国境線はアプリ同梱のNatural Earth簡略データから描画する。
        // 道路や施設名を含む地図画像は使わない。
        let outline = credit.coords.flatMap { CountryOutline.find(at: $0) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))
            // JPEG の画像境界をそのままカード境界とする。
            // 角丸で切り抜くと四隅に黒い余白が焼き込まれるため、
            // SNS保存用の画像では矩形のまま描画する。
            // 参考デザイン: 真鍮色の外枠、上部ブランド帯、大きな写真、
            // 下部に撮影者・撮影地・輪郭地図、その下に3列の撮影情報。
            let margin: CGFloat = 48
            let header: CGFloat = 142
            let footer: CGFloat = ratio == .story ? 430 : 355
            let photoBottom = height - footer + 78
            let photoRect = CGRect(x: margin, y: header,
                                   width: width - margin * 2,
                                   height: photoBottom - header)
            let scale = max(photoRect.width / photo.size.width,
                            photoRect.height / photo.size.height)
            let fitted = CGRect(x: photoRect.midX - photo.size.width * scale / 2,
                                y: photoRect.midY - photo.size.height * scale / 2,
                                width: photo.size.width * scale,
                                height: photo.size.height * scale)
            cg.saveGState()
            cg.clip(to: photoRect)
            photo.draw(in: fitted)
            // 横長の写真を縦型カードへ無理に拡大すると被写体が大幅に切れる。
            // 背景は余白なく敷き、元写真は全体が見える比率で中央に重ねる。
            let photoAspect = photo.size.width / photo.size.height
            let cardAspect = photoRect.width / photoRect.height
            if photoAspect > cardAspect * 1.35 {
                let fitScale = min(photoRect.width / photo.size.width,
                                   photoRect.height / photo.size.height)
                let fitSize = CGSize(width: photo.size.width * fitScale,
                                     height: photo.size.height * fitScale)
                let fitRect = CGRect(x: photoRect.midX - fitSize.width / 2,
                                     y: photoRect.midY - fitSize.height / 2,
                                     width: fitSize.width, height: fitSize.height)
                cg.setFillColor(UIColor.black.withAlphaComponent(0.35).cgColor)
                cg.fill(photoRect)
                photo.draw(in: fitRect)
            }
            cg.restoreGState()

            let fade = CGRect(x: margin, y: photoBottom - 195,
                              width: width - margin * 2, height: 210)
            let colors = [UIColor.black.withAlphaComponent(0).cgColor,
                          surface.withAlphaComponent(0.86).cgColor,
                          surface.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 0.66, 1]) {
                cg.saveGState()
                cg.clip(to: fade)
                cg.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: fade.minY),
                    end: CGPoint(x: 0, y: fade.maxY), options: [])
                cg.restoreGState()
            }
            surface.setFill()
            cg.fill(CGRect(x: margin, y: photoBottom,
                           width: width - margin * 2,
                           height: height - margin - photoBottom))

            if let mark = UIImage(named: "BrandMark")?.withRenderingMode(.alwaysTemplate) {
                mark.withTintColor(.white).draw(in: CGRect(x: 95, y: 62, width: 45, height: 45))
            }
            draw("Journey Photo", at: CGPoint(x: 157, y: 64), maxWidth: 365,
                 size: 39, color: .white, serif: true)
            cg.setStrokeColor(brass.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(2)
            cg.move(to: CGPoint(x: 550, y: 59))
            cg.addLine(to: CGPoint(x: 550, y: 116))
            cg.strokePath()
            draw("旅の一瞬を、誰かの次の旅へ。", at: CGPoint(x: 565, y: 79),
                  maxWidth: 410, size: 25, color: .white, alignment: .right)

            let rowY = height - footer + 76
            // アバター未取得の場合はブランド色の円形モノグラムで代替。
            let avatarRect = CGRect(x: 96, y: rowY - 4, width: 100, height: 100)
            if let avatarData, let avatar = UIImage(data: avatarData) {
                cg.saveGState()
                cg.addEllipse(in: avatarRect)
                cg.clip()
                let factor = max(avatarRect.width / avatar.size.width,
                                 avatarRect.height / avatar.size.height)
                avatar.draw(in: CGRect(x: avatarRect.midX - avatar.size.width * factor / 2,
                                       y: avatarRect.midY - avatar.size.height * factor / 2,
                                       width: avatar.size.width * factor,
                                       height: avatar.size.height * factor))
                cg.restoreGState()
            } else {
                cg.setFillColor(brass.withAlphaComponent(0.15).cgColor)
                cg.fillEllipse(in: avatarRect)
            }
            cg.setStrokeColor(brass.cgColor)
            cg.setLineWidth(2)
            cg.strokeEllipse(in: avatarRect)
            let initial = String(credit.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
            if avatarData.flatMap(UIImage.init(data:)) == nil {
                draw(initial.isEmpty ? "J" : initial,
                     at: CGPoint(x: 128, y: rowY + 17), maxWidth: 50,
                     size: 45, color: .white, serif: true)
            }
            let authorName = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let markCount = (credit.verified ? 1 : 0) + (credit.proStyle == nil ? 0 : 1)
                + (credit.early ? 1 : 0) + (credit.badge == nil ? 0 : 1)
            let markWidth = CGFloat(markCount * 30 + (credit.proStyle == .plate ? 16 : 0))
            let nameWidth = max(90, 255 - markWidth)
            // マークは名前の固定幅の末尾ではなく、実際に描画する文字の直後に置く。
            // 長い名前は draw() と同じ縮小ルールで測定し、地点欄との境界を守る。
            let nameFont = UIFont.systemFont(ofSize: 32, weight: .semibold)
            var fittedNameFont = nameFont
            let minimumNameSize: CGFloat = max(16, 32 * 0.72)
            let nameText = authorName as NSString
            while fittedNameFont.pointSize > minimumNameSize,
                  nameText.size(withAttributes: [.font: fittedNameFont]).width > nameWidth {
                fittedNameFont = UIFont(descriptor: nameFont.fontDescriptor,
                                        size: max(minimumNameSize, fittedNameFont.pointSize - 1))
            }
            let actualNameWidth = min(nameWidth,
                ceil(nameText.size(withAttributes: [.font: fittedNameFont]).width))
            draw(authorName, at: CGPoint(x: 220, y: rowY), maxWidth: nameWidth,
                 size: 32, color: .white, bold: true)
            drawNameMarks(credit, at: CGPoint(x: 220 + actualNameWidth + 5, y: rowY + 7))
            if let username = credit.username?.trimmingCharacters(in: .whitespacesAndNewlines),
               !username.isEmpty {
                draw("@" + username.trimmingCharacters(in: CharacterSet(charactersIn: "@")),
                     at: CGPoint(x: 220, y: rowY + 53), maxWidth: 245,
                     size: 25, color: secondary)
            }
            cg.setStrokeColor(brass.withAlphaComponent(0.4).cgColor)
            cg.move(to: CGPoint(x: 493, y: rowY - 4))
            cg.addLine(to: CGPoint(x: 493, y: rowY + 105))
            cg.strokePath()

            if let place = credit.location?.trimmingCharacters(in: .whitespacesAndNewlines),
               !place.isEmpty {
                drawSymbol("mappin.circle", at: CGPoint(x: 520, y: rowY + 21),
                           size: 37, color: brass)
                draw(place, at: CGPoint(x: 570, y: rowY + 22),
                     maxWidth: credit.coords == nil ? 385 : 205,
                     size: 26, color: .white, bold: true, lines: 3)
            }
            if credit.coords != nil {
                let mapRect = CGRect(x: 785, y: rowY - 18, width: 195, height: 128)
                if let outline, let coordinate = credit.coords {
                    CountryOutline.draw(outline, pin: coordinate, in: mapRect, color: brass, context: cg)
                } else if let coordinate = credit.coords {
                    CountryOutline.drawNearby(pin: coordinate, in: mapRect, color: brass, context: cg)
                }
            }

            let separatorY = rowY + 132
            cg.setStrokeColor(brass.withAlphaComponent(0.5).cgColor)
            cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: 96, y: separatorY))
            cg.addLine(to: CGPoint(x: width - 96, y: separatorY))
            cg.strokePath()

            let infoY = separatorY + 31
            let camera = credit.camera?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lens = credit.lens?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let exposure = [credit.aperture, credit.exposure,
                            credit.iso.map { "ISO\($0)" }]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: "  ")
            // 参考デザインどおり、撮影情報は個別の箱ではなく細い縦罫線で区切る。
            cg.setStrokeColor(brass.withAlphaComponent(0.4).cgColor)
            cg.setLineWidth(1.5)
            for dividerX in [CGFloat(399), CGFloat(721)] {
                cg.move(to: CGPoint(x: dividerX, y: infoY - 6))
                cg.addLine(to: CGPoint(x: dividerX, y: infoY + 62))
                cg.strokePath()
            }
            // 値のない撮影項目はアイコンだけ残さない。
            if !camera.isEmpty {
                drawSymbol("camera", at: CGPoint(x: 98, y: infoY), size: 40, color: brass)
                drawInfo(camera, at: CGPoint(x: 157, y: infoY + 3), maxWidth: 235, size: 22, color: .white)
            }
            if !lens.isEmpty {
                drawSymbol("camera.aperture", at: CGPoint(x: 410, y: infoY), size: 40, color: brass)
                drawInfo(lens, at: CGPoint(x: 463, y: infoY + 3), maxWidth: 246, size: 22, color: .white)
            }
            if !exposure.isEmpty {
                drawSymbol("timer", at: CGPoint(x: 731, y: infoY), size: 38, color: brass)
                drawInfo(exposure, at: CGPoint(x: 786, y: infoY + 3), maxWidth: 195, size: 20, color: .white)
            }

            // 画像の端に沿う真鍮色の矩形フレーム。保存画像に角丸の外側余白を作らない。
            cg.setStrokeColor(brass.withAlphaComponent(0.9).cgColor)
            cg.setLineWidth(3)
            cg.stroke(CGRect(x: 1.5, y: 1.5, width: width - 3, height: height - 3))
        }
    }

    // GeoJSON由来の低解像度輪郭を軽量JSONとして同梱する。
    // 出典: Natural Earth 1:110m admin-0 countries (public domain)。
    private enum CountryOutline {
        struct Shape: Decodable {
            let n: String
            let r: [[[Double]]]
        }
        static let shapes: [Shape] = {
            guard let url = Bundle.main.url(forResource: "country-outlines", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let result = try? JSONDecoder().decode([Shape].self, from: data) else { return [] }
            return result
        }()

        static func contains(_ point: CLLocationCoordinate2D, ring: [[Double]]) -> Bool {
            guard ring.count >= 3 else { return false }
            var inside = false
            var previous = ring.count - 1
            for index in ring.indices {
                let a = ring[index], b = ring[previous]
                if a.count == 2, b.count == 2,
                   (a[1] > point.latitude) != (b[1] > point.latitude) {
                    let intersection = (b[0] - a[0]) *
                        (point.latitude - a[1]) / (b[1] - a[1]) + a[0]
                    if point.longitude < intersection { inside.toggle() }
                }
                previous = index
            }
            return inside
        }

        static func find(at coordinate: CLLocationCoordinate2D) -> Shape? {
            guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
                  (-90...90).contains(coordinate.latitude),
                  (-180...180).contains(coordinate.longitude) else { return nil }
            return shapes.first { shape in
                shape.r.contains { contains(coordinate, ring: $0) }
            }
        }

        /// 海上や小島でも近隣の実際の国境・海岸線を表示する。
        /// Natural Earth の輪郭が範囲内にない場合だけ地点の目盛りを表示する。
        static func drawNearby(pin: CLLocationCoordinate2D, in rect: CGRect,
                               color: UIColor, context: CGContext) {
            let span: Double = 18
            let lonScale = max(0.2, cos(pin.latitude * .pi / 180))
            let minLon = pin.longitude - span / lonScale
            let maxLon = pin.longitude + span / lonScale
            let minLat = pin.latitude - span * Double(rect.height / rect.width)
            let maxLat = pin.latitude + span * Double(rect.height / rect.width)
            func project(_ p: [Double]) -> CGPoint {
                CGPoint(x: rect.minX + CGFloat((p[0] - minLon) / (maxLon - minLon)) * rect.width,
                        y: rect.maxY - CGFloat((p[1] - minLat) / (maxLat - minLat)) * rect.height)
            }
            context.saveGState()
            context.clip(to: rect)
            context.setStrokeColor(color.withAlphaComponent(0.75).cgColor)
            context.setLineWidth(1.4)
            var drewCoast = false
            for shape in shapes {
                for ring in shape.r where ring.count >= 3 {
                    guard ring.contains(where: { $0.count == 2 &&
                        $0[0] >= minLon && $0[0] <= maxLon &&
                        $0[1] >= minLat && $0[1] <= maxLat }) else { continue }
                    context.beginPath()
                    context.move(to: project(ring[0]))
                    for point in ring.dropFirst() where point.count == 2 {
                        context.addLine(to: project(point))
                    }
                    context.closePath()
                    context.strokePath()
                    drewCoast = true
                }
            }
            if !drewCoast {
                context.setStrokeColor(color.withAlphaComponent(0.25).cgColor)
                for i in 1...3 {
                    let x = rect.minX + rect.width * CGFloat(i) / 4
                    let y = rect.minY + rect.height * CGFloat(i) / 4
                    context.move(to: CGPoint(x: x, y: rect.minY))
                    context.addLine(to: CGPoint(x: x, y: rect.maxY))
                    context.move(to: CGPoint(x: rect.minX, y: y))
                    context.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
                context.strokePath()
            }
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: rect.midX - 5, y: rect.midY - 5, width: 10, height: 10))
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: rect.midX - 12, y: rect.midY - 12,
                                             width: 24, height: 24))
            context.restoreGState()
        }

        static func draw(_ shape: Shape, pin: CLLocationCoordinate2D,
                         in rect: CGRect, color: UIColor, context: CGContext) {
            let points = shape.r.flatMap { $0 }.filter { $0.count == 2 }
            guard let minX = points.map({ $0[0] }).min(),
                  let maxX = points.map({ $0[0] }).max(),
                  let minY = points.map({ $0[1] }).min(),
                  let maxY = points.map({ $0[1] }).max() else { return }
            let spanX = max(maxX - minX, 0.01)
            let spanY = max(maxY - minY, 0.01)
            let scale = min((rect.width - 20) / spanX, (rect.height - 20) / spanY)
            let offsetX = rect.midX - (minX + maxX) * scale / 2
            let offsetY = rect.midY + (minY + maxY) * scale / 2
            func project(_ p: [Double]) -> CGPoint {
                CGPoint(x: p[0] * scale + offsetX, y: offsetY - p[1] * scale)
            }
            context.saveGState()
            context.clip(to: rect)
            context.setStrokeColor(color.withAlphaComponent(0.75).cgColor)
            context.setLineWidth(1.8)
            for ring in shape.r where ring.count >= 3 {
                context.beginPath()
                context.move(to: project(ring[0]))
                for point in ring.dropFirst() { context.addLine(to: project(point)) }
                context.closePath()
                context.strokePath()
            }
            let center = project([pin.longitude, pin.latitude])
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: center.x - 5, y: center.y - 5,
                                           width: 10, height: 10))
            context.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: center.x - 12, y: center.y - 12,
                                             width: 24, height: 24))
            context.restoreGState()
        }
    }

    private static func drawLocationFallback(in rect: CGRect, color: UIColor, context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        context.setStrokeColor(color.withAlphaComponent(0.32).cgColor)
        context.setLineWidth(1)
        for fraction in [CGFloat(0.25), 0.5, 0.75] {
            let x = rect.minX + rect.width * fraction
            let y = rect.minY + rect.height * fraction
            context.move(to: CGPoint(x: x, y: rect.minY + 8))
            context.addLine(to: CGPoint(x: x, y: rect.maxY - 8))
            context.move(to: CGPoint(x: rect.minX + 8, y: y))
            context.addLine(to: CGPoint(x: rect.maxX - 8, y: y))
        }
        context.strokePath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26))
        context.restoreGState()
    }

    /// 既存の ProMarkGeometry / EarlyMemberMarkGeometry を使い、画面と同じ輪郭を描く。
    private static func drawNameMarks(_ credit: Credit, at origin: CGPoint) {
        var x = origin.x
        func advance(_ width: CGFloat = 30) { x += width }
        if credit.verified {
            // VerifiedBadge と同じ2色の封印（チェック＝墨、封印＝真鍮）。
            // 単色 SF Symbol では公式マークの意匠が失われる。
            let palette = UIImage.SymbolConfiguration(pointSize: 25, weight: .regular)
                .applying(UIImage.SymbolConfiguration(paletteColors: [
                    UIColor(red: 26/255, green: 20/255, blue: 10/255, alpha: 1), brass
                ]))
            if let symbol = UIImage(systemName: "checkmark.seal.fill", withConfiguration: palette) {
                symbol.draw(in: CGRect(x: x, y: origin.y, width: 27, height: 27))
            }
            advance()
        }
        if let style = credit.proStyle {
            let rect = CGRect(x: x, y: origin.y, width: style == .plate ? 43 : 27, height: 27)
            drawProMark(style, in: rect)
            advance(style == .plate ? 46 : 30)
        }
        if credit.early {
            let rect = CGRect(x: x, y: origin.y, width: 27, height: 27)
            let shield = EarlyMemberMarkShape(part: .shield).path(in: rect)
            let star = EarlyMemberMarkShape(part: .star).path(in: rect)
            brass.setFill()
            UIBezierPath(cgPath: shield.cgPath).fill()
            UIColor(red: 26/255, green: 20/255, blue: 10/255, alpha: 1).setFill()
            UIBezierPath(cgPath: star.cgPath).fill()
            advance()
        }
        if let badge = credit.badge, BadgeCatalog.isKnown(badge.key),
           let image = UIImage(named: BadgeCatalog.nameSideImage(badge.key, tier: badge.tier)) {
            image.draw(in: CGRect(x: x, y: origin.y - 2, width: 30, height: 30))
        }
    }

    private static func drawProMark(_ style: ProMarkStyle, in rect: CGRect) {
        let gold = brass
        let ink = UIColor(red: 26/255, green: 20/255, blue: 10/255, alpha: 1)
        if style == .plate {
            let pill = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 3), cornerRadius: 10)
            UIColor(red: 12/255, green: 12/255, blue: 13/255, alpha: 1).setFill()
            pill.fill()
            gold.setStroke()
            pill.lineWidth = 1.8
            pill.stroke()
            let font = UIFont.systemFont(ofSize: 13, weight: .heavy)
            let label = "PRO" as NSString
            let size = label.size(withAttributes: [.font: font])
            label.draw(at: CGPoint(x: rect.midX - size.width / 2,
                                   y: rect.midY - size.height / 2),
                       withAttributes: [.font: font, .foregroundColor: gold])
            return
        }
        let k = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * k, oy = rect.midY - 12 * k
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: ox + p.x * k, y: oy + p.y * k)
        }
        let disc = CGRect(x: ox + 0.8 * k, y: oy + 0.8 * k,
                          width: 22.4 * k, height: 22.4 * k)
        gold.setFill()
        UIBezierPath(ovalIn: disc).fill()
        let aperture = ProMarkGeometry.aperture(small: false)
        ink.setStroke()
        for (start, end) in zip(aperture, ProMarkGeometry.bladeEnds) {
            let line = UIBezierPath()
            line.move(to: point(start))
            line.addLine(to: point(end))
            line.lineWidth = 1.05 * k
            line.stroke()
        }
        let hole = UIBezierPath()
        if let first = aperture.first {
            hole.move(to: point(first))
            for p in aperture.dropFirst() { hole.addLine(to: point(p)) }
            hole.close()
            ink.setFill()
            hole.fill()
        }
    }

    /// 撮影情報の列幅と高さに合わせて、全文を表示できる最大フォントサイズを求める。
    /// 描画とテストで同じ計測を使い、3行相当の高さからはみ出さないようにする。
    static func equipmentFontSize(_ value: String, maxWidth: CGFloat,
                                  preferredSize: CGFloat = 22,
                                  availableHeight: CGFloat = 72) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.lineSpacing = 1
        let text = value as NSString
        var lower: CGFloat = 7
        var upper = preferredSize
        for _ in 0..<12 {
            let middle = (lower + upper) / 2
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: middle, weight: .semibold),
                .paragraphStyle: paragraph
            ]
            let measured = text.boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes, context: nil)
            if measured.height <= availableHeight { lower = middle }
            else { upper = middle }
        }
        return lower
    }

    /// 列内に全文を収める。短い機材名は従来の大きさを維持する。
    private static func drawInfo(_ value: String, at origin: CGPoint,
                                 maxWidth: CGFloat, size: CGFloat, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.lineSpacing = 1
        let fittedSize = equipmentFontSize(value, maxWidth: maxWidth, preferredSize: size)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fittedSize, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (value as NSString).draw(
            with: CGRect(x: origin.x, y: origin.y, width: maxWidth, height: 72),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes, context: nil)
    }

    private static func drawSymbol(_ name: String, at origin: CGPoint,
                                   size: CGFloat, color: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        symbol.draw(in: CGRect(origin: origin, size: CGSize(width: size, height: size)))
    }

    private static func draw(_ value: String, at origin: CGPoint, maxWidth: CGFloat,
                             size: CGFloat, color: UIColor, bold: Bool = false,
                             serif: Bool = false, alignment: NSTextAlignment = .left,
                             lines: Int = 1) {
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let font = serif ? (base.fontDescriptor.withDesign(.serif).map {
            UIFont(descriptor: $0, size: size)
        } ?? base) : base
        // 長い撮影地・カメラ名は可能な範囲で縮小し、最後だけ省略する。
        let text = value as NSString
        var fittedFont = font
        let minimumSize = max(16, size * 0.72)
        while fittedFont.pointSize > minimumSize,
              text.size(withAttributes: [.font: fittedFont]).width > maxWidth {
            fittedFont = UIFont(descriptor: font.fontDescriptor,
                                size: max(minimumSize, fittedFont.pointSize - 1))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lines > 1 ? .byCharWrapping : .byTruncatingTail
        text.draw(in: CGRect(x: origin.x, y: origin.y,
                             width: maxWidth, height: size * CGFloat(lines) * 1.35),
                  withAttributes: [.font: fittedFont, .foregroundColor: color,
                                   .paragraphStyle: paragraph])
    }
    #endif
}
