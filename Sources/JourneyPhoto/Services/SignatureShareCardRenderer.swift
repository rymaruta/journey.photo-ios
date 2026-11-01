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
    static func render(_ data: Data, credit: Credit, ratio: Ratio = .portrait) async -> Data? { nil }
    #else
    static func render(_ data: Data, credit: Credit, ratio: Ratio = .portrait) async -> Data? {
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
            let header: CGFloat = 120
            // 全比率で撮影者・地図・EXIFが収まる情報領域を確保する。
            // 1:1も縦長と同じ情報領域を使い、最下段の文字切れを防ぐ。
            let footer: CGFloat = ratio == .story ? 400 : 335
            let photoRect = CGRect(x: 0, y: header, width: width,
                                   height: height - header - footer + 125)
            // 余白を作らず写真を主役にする。カード枠からはみ出す部分のみ切り取る。
            let scale = max(photoRect.width / photo.size.width, photoRect.height / photo.size.height)
            let fitted = CGRect(x: photoRect.midX - photo.size.width * scale / 2,
                                y: photoRect.midY - photo.size.height * scale / 2,
                                width: photo.size.width * scale,
                                height: photo.size.height * scale)
            cg.saveGState()
            cg.clip(to: photoRect)
            photo.draw(in: fitted)
            cg.restoreGState()
            // 写真下端から黒い情報面へ自然につなぐ。個別のガラス枠は使わない。
            let fade = CGRect(x: 0, y: height - footer - 190, width: width, height: 245)
            let colors = [UIColor.black.withAlphaComponent(0).cgColor,
                          UIColor.black.withAlphaComponent(0.68).cgColor,
                          surface.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 0.5, 1]) {
                cg.saveGState()
                cg.clip(to: fade)
                cg.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: fade.minY),
                    end: CGPoint(x: 0, y: fade.maxY), options: [])
                cg.restoreGState()
            }
            surface.setFill()
            cg.fill(CGRect(x: 0, y: height - footer + 50, width: width, height: footer - 50))

            // ブランド: 写真上は白のみ。公式アセットを使用。
            if let mark = UIImage(named: "BrandMark")?.withRenderingMode(.alwaysTemplate) {
                cg.saveGState()
                mark.withTintColor(.white).draw(in: CGRect(x: 54, y: 39, width: 44, height: 44))
                cg.restoreGState()
            }
            draw("Journey Photo", at: CGPoint(x: 112, y: 35), maxWidth: 390,
                 size: 47, color: .white, serif: true)
            draw("旅の一瞬を、誰かの次の旅へ。", at: CGPoint(x: 585, y: 51),
                 maxWidth: 450, size: 25, color: .white, alignment: .right)

            let rowY = height - footer + 50
            draw(credit.name.trimmingCharacters(in: .whitespacesAndNewlines),
                 at: CGPoint(x: 58, y: rowY), maxWidth: 400,
                 size: 38, color: .white, bold: true)
            if let username = credit.username?.trimmingCharacters(in: .whitespacesAndNewlines),
               !username.isEmpty {
                draw("@"+username.trimmingCharacters(in: CharacterSet(charactersIn: "@")),
                     at: CGPoint(x: 58, y: rowY + 53), maxWidth: 420, size: 27, color: secondary)
            }
            if let place = credit.location?.trimmingCharacters(in: .whitespacesAndNewlines),
               !place.isEmpty {
                draw("⌖ " + place, at: CGPoint(x: 470, y: rowY + 20),
                     maxWidth: outline == nil ? 540 : 335, size: 30, color: .white)
            }
            if let outline, let coordinate = credit.coords {
                CountryOutline.draw(outline, pin: coordinate,
                                    in: CGRect(x: width - 240, y: rowY - 32,
                                             width: 190, height: 135),
                                    color: brass, context: cg)
            }
            let settings = [
                credit.camera, credit.lens, credit.aperture, credit.exposure,
                credit.iso.map { "ISO\($0)" }
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
             .filter { !$0.isEmpty }
            if !settings.isEmpty {
                let lineY = rowY + 143
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.16).cgColor)
                cg.setLineWidth(1)
                cg.move(to: CGPoint(x: 55, y: lineY))
                cg.addLine(to: CGPoint(x: width - 55, y: lineY))
                cg.strokePath()

                let firstLine = settings.prefix(2).joined(separator: "   ·   ")
                let secondLine = settings.dropFirst(2).joined(separator: "   ·   ")
                draw(firstLine, at: CGPoint(x: 58, y: lineY + 19),
                     maxWidth: width - 116, size: 26, color: secondary)
                if !secondLine.isEmpty {
                    draw(secondLine, at: CGPoint(x: 58, y: lineY + 57),
                         maxWidth: width - 116, size: 25, color: secondary)
                }
            }
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
