import UIKit
import MapKit

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
    }

    private static let surface = UIColor(red: 14/255, green: 14/255, blue: 15/255, alpha: 1)
    private static let brass = UIColor(red: 201/255, green: 166/255, blue: 107/255, alpha: 1)
    private static let secondary = UIColor(red: 184/255, green: 184/255, blue: 184/255, alpha: 1)

    #if os(Linux)
    // LinuxのSDK模型にはCoreGraphics/MapKit描画APIがない。実描画はiOSのXcodeで検証する。
    static func render(_ data: Data, credit: Credit, ratio: Ratio = .portrait, avatarData: Data? = nil) async -> Data? { nil }
    #else
    static func render(_ data: Data, credit: Credit, ratio: Ratio = .portrait, avatarData: Data? = nil) async -> Data? {
        guard let photo = UIImage(data: data),
              photo.size.width > 0, photo.size.height > 0 else { return nil }
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
            // 外枠の外に写真がはみ出さないよう、カード全体を角丸でクリップ。
            // 枠線は最後に重ねて描く。
            let cardBounds = CGRect(x: 50, y: 14,
                                    width: width - 100, height: height - 28)
            let cardPath = UIBezierPath(roundedRect: cardBounds, cornerRadius: 55)
            cg.addPath(cardPath.cgPath)
            cg.clip()
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
                mark.withTintColor(.white).draw(in: CGRect(x: 95, y: 62, width: 55, height: 55))
            }
            draw("Journey Photo", at: CGPoint(x: 163, y: 57), maxWidth: 365,
                 size: 43, color: .white, serif: true)
            cg.setStrokeColor(brass.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(2)
            cg.move(to: CGPoint(x: 550, y: 59))
            cg.addLine(to: CGPoint(x: 550, y: 116))
            cg.strokePath()
            draw("旅の一瞬を、誰かの次の旅へ。", at: CGPoint(x: 585, y: 77),
                 maxWidth: 390, size: 23, color: .white, alignment: .right)

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
            draw(credit.name.trimmingCharacters(in: .whitespacesAndNewlines),
                 at: CGPoint(x: 220, y: rowY), maxWidth: 250,
                 size: 38, color: .white, bold: true)
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
                     maxWidth: outline == nil ? 385 : 225,
                     size: 29, color: .white, bold: true)
            }
            if let outline, let coordinate = credit.coords {
                CountryOutline.draw(outline, pin: coordinate,
                                    in: CGRect(x: 830, y: rowY - 15,
                                             width: 140, height: 123),
                                    color: brass, context: cg)
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
            // 値のない撮影項目はアイコンだけ残さない。
            if !camera.isEmpty {
                drawSymbol("camera", at: CGPoint(x: 98, y: infoY), size: 40, color: brass)
                draw(camera, at: CGPoint(x: 157, y: infoY + 5), maxWidth: 235,
                     size: 26, color: .white, bold: true)
            }
            if !lens.isEmpty {
                drawSymbol("camera.aperture", at: CGPoint(x: 410, y: infoY), size: 40, color: brass)
                draw(lens, at: CGPoint(x: 463, y: infoY + 5), maxWidth: 246,
                     size: 26, color: .white, bold: true)
            }
            if !exposure.isEmpty {
                drawSymbol("mountain.2", at: CGPoint(x: 731, y: infoY), size: 38, color: brass)
                draw(exposure, at: CGPoint(x: 786, y: infoY + 5), maxWidth: 195,
                     size: 24, color: .white, bold: true)
            }

            // 全体の細い真鍮色角丸フレーム。写真や情報の個別ガラス枠は付けない。
            cg.setStrokeColor(brass.withAlphaComponent(0.9).cgColor)
            cg.setLineWidth(3)
            cg.addPath(cardPath.cgPath)
            cg.strokePath()
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

    private static func drawSymbol(_ name: String, at origin: CGPoint,
                                   size: CGFloat, color: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        symbol.draw(in: CGRect(origin: origin, size: CGSize(width: size, height: size)))
    }

    private static func draw(_ value: String, at origin: CGPoint, maxWidth: CGFloat,
                             size: CGFloat, color: UIColor, bold: Bool = false,
                             serif: Bool = false, alignment: NSTextAlignment = .left) {
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
        paragraph.lineBreakMode = .byTruncatingTail
        text.draw(in: CGRect(x: origin.x, y: origin.y,
                             width: maxWidth, height: size * 1.6),
                  withAttributes: [.font: fittedFont, .foregroundColor: color,
                                   .paragraphStyle: paragraph])
    }
    #endif
}
