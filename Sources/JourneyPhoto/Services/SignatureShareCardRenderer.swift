import UIKit
import MapKit
import AVFoundation

/// SNS向けの1枚画像。写真と帰属情報を画素に焼き込み、元画像のEXIFを引き継がない。
/// デザイン: docs/design/ios-artifact/DesignSystem.dc.html（黒塗りの真鍮）
enum SignatureShareCardRenderer {
    enum Ratio: CGFloat {
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

    static func render(_ data: Data, credit: Credit, ratio: Ratio = .portrait) async -> Data? {
        guard let photo = UIImage(data: data) else { return nil }
        let width: CGFloat = 1080
        let height = width / ratio.rawValue
        let canvas = CGSize(width: width, height: height)
        // MapKitの写真位置は公開用に丸められた座標だけを使う。
        let map: UIImage?
        if let coordinate = credit.coords, CLLocationCoordinate2DIsValid(coordinate) {
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4))
            options.size = CGSize(width: 180, height: 120)
            options.mapType = .mutedStandard
            map = try? await MKMapSnapshotter(options: options).start().image
        } else {
            map = nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))
            let header: CGFloat = 120
            let footer: CGFloat = ratio == .story ? 380 : 315
            let photoRect = CGRect(x: 0, y: header, width: width, height: height - header - footer + 125)
            // 元画像を欠けさせない。写真の周囲は黒で埋める。
            let fitted = AVMakeRect(aspectRatio: photo.size, insideRect: photoRect)
            photo.draw(in: fitted)
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

            let rowY = height - footer + 70
            draw(credit.name, at: CGPoint(x: 58, y: rowY), maxWidth: 400,
                 size: 38, color: .white, bold: true)
            if let username = credit.username, !username.isEmpty {
                draw("@"+username.trimmingCharacters(in: CharacterSet(charactersIn: "@")),
                     at: CGPoint(x: 58, y: rowY + 53), maxWidth: 420, size: 27, color: secondary)
            }
            if let place = credit.location, !place.isEmpty {
                draw("⌖ " + place, at: CGPoint(x: 470, y: rowY + 20),
                     maxWidth: map == nil ? 540 : 335, size: 30, color: .white)
            }
            if let map {
                let mapRect = CGRect(x: width - 235, y: rowY - 25, width: 180, height: 120)
                cg.saveGState()
                let path = UIBezierPath(roundedRect: mapRect, cornerRadius: 9)
                path.addClip()
                map.draw(in: mapRect)
                // 二重の点（中心点と輪）で撮影位置を示す。座標は地図の中心。
                let pin = CGPoint(x: mapRect.midX, y: mapRect.midY)
                brass.setStroke()
                cg.setLineWidth(4)
                cg.strokeEllipse(in: CGRect(x: pin.x - 14, y: pin.y - 14, width: 28, height: 28))
                brass.setFill()
                cg.fillEllipse(in: CGRect(x: pin.x - 5, y: pin.y - 5, width: 10, height: 10))
                cg.restoreGState()
                draw("© Apple Maps", at: CGPoint(x: width - 232, y: rowY + 99),
                     maxWidth: 170, size: 15, color: .white)
            }
            let lineY = rowY + 143
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.16).cgColor)
            cg.setLineWidth(1)
            cg.move(to: CGPoint(x: 55, y: lineY))
            cg.addLine(to: CGPoint(x: width - 55, y: lineY))
            cg.strokePath()

            let settings = [
                credit.camera, credit.lens, credit.aperture, credit.exposure,
                credit.iso.map { "ISO\($0)" }
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
             .filter { !$0.isEmpty }
            if !settings.isEmpty {
                draw(settings.joined(separator: "   ·   "), at: CGPoint(x: 58, y: lineY + 28),
                     maxWidth: width - 116, size: 27, color: secondary)
            }
        }
    }

    private static func draw(_ value: String, at origin: CGPoint, maxWidth: CGFloat,
                             size: CGFloat, color: UIColor, bold: Bool = false,
                             serif: Bool = false, alignment: NSTextAlignment = .left) {
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let font = serif ? (base.fontDescriptor.withDesign(.serif).map {
            UIFont(descriptor: $0, size: size)
        } ?? base) : base
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: CGRect(x: origin.x, y: origin.y, width: maxWidth, height: size * 1.6),
                                 withAttributes: [.font: font, .foregroundColor: color,
                                                  .paragraphStyle: paragraph])
    }
}
