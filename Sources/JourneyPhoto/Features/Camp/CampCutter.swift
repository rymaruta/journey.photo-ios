import Foundation
import SwiftUI
import UIKit
#if canImport(Vision)
import CoreGraphics
import CoreVideo
import ImageIO
import Vision
#endif

/// 切り出した結果（板 CampCapture の 2 切り出す）
struct CampCutResult {
    /// 3 枚の切り絵（奥・中・手前）
    let layers: CampCutLayers
    /// 紙の表の絵（3 枚・札の座標 376 × (高さ + 16) を 2 倍の画素で）
    let cards: [UIImage]
    /// 向きを直した写真全体と、切り抜いた範囲（写真の画素）
    let photo: UIImage
    let cropRect: CGRect
    let subjects: [CampSubject]
    /// 人が写っていた（切り絵にしない）
    let hasPeople: Bool
    /// 写真の上の方から取った空の色（上・中・下）
    let sky: [UInt32]?
    let title: String
}

/// 撮った写真を 3 枚の切り絵にする（端末の中だけ）。
///
/// 1. 向きを直し、長い辺 1600 に縮める
/// 2. 撮る画面の四隅の枠の範囲を切り抜く（`CampCrop`）
/// 3. 前景の型（iOS 17 の `VNGenerateForegroundInstanceMaskRequest`）を取る。取れなければ（シミュレータ・失敗）型なし
/// 4. 明るさの段で 3 枚に分ける（`CampLayerSplit`・型があれば手前の 1 枚は型の縁）
/// 5. 人（`VNDetectHumanRectanglesRequest`）と写った物（`VNClassifyImageRequest`）を見る
/// 6. 紙の表の絵を描く（板の `cutF`: 縁の影 #cfc8b8 → 紙のフチ #f7f4ec → 写真を稜線で切ったもの）
enum CampCutter {

    /// 縮める長い辺
    static let maxSide: CGFloat = 1600
    /// 明るさを数える列の数（稜線の 61 点より細かく）
    static let lumaColumns = 120
    /// 紙の表の絵の画素（札の単位あたり）
    static let cardScale: CGFloat = 2

    #if canImport(Vision)

    /// 切り出す。`frame` は撮る画面の枠（画面の座標）・`viewSize` は映像を敷いた枠の大きさ
    static func cut(_ source: UIImage, frame: CGRect, viewSize: CGSize) async -> CampCutResult {
        let photo = normalized(source)
        let size = photo.size
        let r = CampCrop.photoRect(frame: (Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)),
                                   view: (Double(viewSize.width), Double(viewSize.height)),
                                   photo: (Double(size.width), Double(size.height)))
        let cropRect = CGRect(x: r.x, y: r.y, width: r.w, height: r.h).integral
        return await Task.detached(priority: .userInitiated) {
            await analyze(photo: photo, cropRect: cropRect)
        }.value
    }

    private static func analyze(photo: UIImage, cropRect: CGRect) async -> CampCutResult {
        guard let cg = photo.cgImage, let crop = cg.cropping(to: cropRect) else {
            let layers = CampLayerSplit.fallback(unitHeight: 480)
            return CampCutResult(layers: layers, cards: cards(layers, crop: nil), photo: photo, cropRect: cropRect, subjects: [],
                                 hasPeople: false, sky: nil, title: CampSubjectRule.title([], season: CampClock.season(of: Date())))
        }
        let w = lumaColumns
        let h = max(8, Int((CGFloat(w) * CGFloat(crop.height) / CGFloat(max(1, crop.width))).rounded()))
        let rgba = pixels(crop, width: w, height: h)
        var luma = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            luma[i] = CampLayerSplit.luminance(r: rgba[i * 4], g: rgba[i * 4 + 1], b: rgba[i * 4 + 2])
        }
        let mask = foregroundMask(crop, width: w, height: h)
        let layers = CampLayerSplit.split(luma: luma, width: w, height: h, foreground: mask)
        let labels = classify(cg)
        let people = hasPeople(cg) || CampSubjectRule.showsPeople(labels: labels)
        let subjects = CampSubjectRule.subjects(labels: labels)
        let season = CampClock.season(of: Date())
        return CampCutResult(layers: layers, cards: people ? [] : cards(layers, crop: UIImage(cgImage: crop)), photo: photo,
                             cropRect: cropRect, subjects: subjects, hasPeople: people, sky: skyColors(cg),
                             title: CampSubjectRule.title(subjects, season: season))
    }

    /// 写真の向きを直して縮める
    static func normalized(_ image: UIImage) -> UIImage {
        let s = image.size
        let k = min(1, maxSide / max(s.width, s.height, 1))
        let size = CGSize(width: (s.width * k).rounded(), height: (s.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 縮めた RGBA（上の行から）
    static func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    /// 前景の型（`width` × `height` に縮めた 0/1）。取れなければ nil
    static func foregroundMask(_ image: CGImage, width: Int, height: Int) -> [Bool]? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
            return downsample(buffer, width: width, height: height)
        } catch {
            return nil
        }
    }

    private static func downsample(_ buffer: CVPixelBuffer, width: Int, height: Int) -> [Bool]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bw = CVPixelBufferGetWidth(buffer), bh = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        var out = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            let sy = min(bh - 1, y * bh / height)
            for x in 0..<width {
                let sx = min(bw - 1, x * bw / width)
                let value: Float
                if format == kCVPixelFormatType_OneComponent32Float {
                    value = base.advanced(by: sy * row + sx * 4).assumingMemoryBound(to: Float.self).pointee
                } else {
                    value = Float(base.advanced(by: sy * row + sx).assumingMemoryBound(to: UInt8.self).pointee) / 255
                }
                out[y * width + x] = value > 0.5
            }
        }
        return out
    }

    /// 人が写っているか（信頼度 0.6 以上）
    static func hasPeople(_ image: CGImage) -> Bool {
        let request = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return false }
        return (request.results ?? []).contains { $0.confidence >= 0.6 }
    }

    /// 写った物の分類（名前と信頼度）
    static func classify(_ image: CGImage) -> [(String, Float)] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).prefix(40).map { ($0.identifier, $0.confidence) }
    }

    /// 写真の上の方の 3 つの帯の平均の色（空・板 Main「空の色は、その時刻に撮った写真から」）
    static func skyColors(_ image: CGImage) -> [UInt32]? {
        let w = 24, h = 40
        let rgba = pixels(image, width: w, height: h)
        func average(_ rows: Range<Int>) -> UInt32 {
            var r = 0, g = 0, b = 0, n = 0
            for y in rows { for x in 0..<w {
                let i = (y * w + x) * 4
                r += Int(rgba[i]); g += Int(rgba[i + 1]); b += Int(rgba[i + 2]); n += 1
            } }
            guard n > 0 else { return 0 }
            return UInt32(r / n) << 16 | UInt32(g / n) << 8 | UInt32(b / n)
        }
        return [average(0..<4), average(4..<9), average(9..<14)]
    }

    /// 紙の表の絵（板の `cutF`: 縁の影 15 → 紙のフチ 12 → 写真を稜線で切ったもの）
    static func cards(_ cut: CampCutLayers, crop: UIImage?) -> [UIImage] {
        cut.layers.map { layer in
            let iw = CampCutLayers.cardWidth, ih = layer.height + 2 * CampCutLayers.margin
            let k = cardScale
            let size = CGSize(width: CGFloat(iw) * k, height: CGFloat(ih) * k)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let g = ctx.cgContext
                let outline = CampCutLayers.photoOutline(layer)
                let path = CGMutablePath()
                for (i, p) in outline.enumerated() {
                    let pt = CGPoint(x: CGFloat(p.x) * k, y: CGFloat(p.y) * k)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                path.closeSubpath()
                g.setLineJoin(.round)
                for (hex, width) in [(UInt32(0xCFC8B8), CGFloat(15)), (UInt32(0xF7F4EC), CGFloat(12))] {
                    g.addPath(path)
                    g.setFillColor(CampTexturePainter.color(hex).cgColor)
                    g.setStrokeColor(CampTexturePainter.color(hex).cgColor)
                    g.setLineWidth(width * k)
                    g.drawPath(using: .fillStroke)
                }
                guard let crop else { return }
                g.saveGState()
                g.addPath(path)
                g.clip()
                // 範囲の左上を札の (8, 8 − 層の上の端) に
                let unit = CGFloat(cut.width) / max(1, crop.size.width)
                let drawW = crop.size.width * unit * k, drawH = crop.size.height * unit * k
                crop.draw(in: CGRect(x: CGFloat(CampCutLayers.margin) * k,
                                     y: CGFloat(CampCutLayers.margin - layer.top) * k, width: drawW, height: drawH))
                g.restoreGState()
            }
        }
    }

    /// 撮影情報（撮った日時・位置・標高）。写真から選んだときに使う
    static func metadata(_ data: Data) -> (date: Date?, latitude: Double?, longitude: Double?, altitude: Double?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return (nil, nil, nil, nil) }
        var date: Date?
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = f.date(from: text)
        }
        guard let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] else { return (date, nil, nil, nil) }
        var lat = gps[kCGImagePropertyGPSLatitude] as? Double
        var lon = gps[kCGImagePropertyGPSLongitude] as? Double
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S", let v = lat { lat = -v }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W", let v = lon { lon = -v }
        var alt = gps[kCGImagePropertyGPSAltitude] as? Double
        if let ref = gps[kCGImagePropertyGPSAltitudeRef] as? Int, ref == 1, let v = alt { alt = -v }
        return (date, lat, lon, alt)
    }

    static func png(_ image: UIImage) -> Data? { image.pngData() }

    /// 切り抜いた範囲の写真（写真から選ぶの小さな絵）
    static func cropJPEG(_ result: CampCutResult) -> Data? {
        guard let crop = result.photo.cgImage?.cropping(to: result.cropRect) else { return nil }
        return UIImage(cgImage: crop).jpegData(compressionQuality: 0.8)
    }
    static func jpeg(_ image: UIImage) -> Data? { image.jpegData(compressionQuality: 0.85) }

    /// 見本の写真（霧の針葉樹林を描いたもの・シミュレータと画面写真の試験）。
    /// 遠い木ほど白く霞み、近い木ほど黒い（濃さの段で 3 枚に切れる）
    static func samplePhoto() -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let g = ctx.cgContext
            let sky = [CampTexturePainter.color(0xD9E0DC).cgColor, CampTexturePainter.color(0xEEEEE6).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky, locations: [0, 1]) {
                g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: 900), options: [.drawsAfterEndLocation])
            }
            var rnd = CampRandom(5)
            // 奥（白く霞む）・中・手前（黒い）の木の並び。稜線の高さ・木の高さ・色
            // 霧の針葉樹林（板の見本の写真に近づける: 遠くは淡い緑灰・近くは深い緑。梢の高さはそろえ気味）
            for (base, height, color, spacing) in [(860.0, 230.0, UInt32(0xB4C0B6), 70.0), (1080.0, 300.0, UInt32(0x6B8070), 92.0),
                                                   (1320.0, 420.0, UInt32(0x24352A), 130.0)] {
                g.setFillColor(CampTexturePainter.color(color).cgColor)
                g.fill(CGRect(x: 0, y: base, width: size.width, height: size.height - base))
                var x = -40.0
                while x < Double(size.width) + 60 {
                    let h = height * (0.78 + rnd.next() * 0.3), w = spacing * (1.1 + rnd.next() * 0.4)
                    let top = base - h
                    let tree = CGMutablePath()
                    tree.move(to: CGPoint(x: x, y: top))
                    // 段の付いた針葉樹の影（左右 5 段）
                    for k in 1...5 {
                        let t = Double(k) / 5
                        tree.addLine(to: CGPoint(x: x + w / 2 * t, y: top + h * t * 0.92))
                        tree.addLine(to: CGPoint(x: x + w / 2 * t * 0.55, y: top + h * t * 0.92 + 4))
                    }
                    tree.addLine(to: CGPoint(x: x + w * 0.3, y: base + 4))
                    tree.addLine(to: CGPoint(x: x - w * 0.3, y: base + 4))
                    for k in (1...5).reversed() {
                        let t = Double(k) / 5
                        tree.addLine(to: CGPoint(x: x - w / 2 * t * 0.55, y: top + h * t * 0.92 + 4))
                        tree.addLine(to: CGPoint(x: x - w / 2 * t, y: top + h * t * 0.92))
                    }
                    tree.closeSubpath()
                    g.addPath(tree)
                    g.fillPath()
                    x += spacing * (0.45 + rnd.next() * 0.3)
                }
                // 霧（下ほど濃い）
                let fog = [CampTexturePainter.color(0xE4E6E1, 0).cgColor, CampTexturePainter.color(0xE4E6E1, 0.35).cgColor] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: fog, locations: [0, 1]) {
                    g.drawLinearGradient(grad, start: CGPoint(x: 0, y: base - height), end: CGPoint(x: 0, y: base), options: [])
                }
            }
        }
    }

    /// 見本の中身（切り絵 2 つを立てたテント場・写真 12 枚）。Debug の起動の鍵だけ
    @MainActor
    static func preparePreview(_ store: CampStore) async {
        let photo = samplePhoto()
        let screen = CGSize(width: 390, height: 724)
        let frame = CampCrop.frame(width: 390, height: 844)
        let result = await cut(photo, frame: CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h), viewSize: screen)
        var snapshot = CampStore.Snapshot()
        snapshot.name = L("ひかり野営地", "Hikari Camp")
        snapshot.shots = CampPreview.sampleShots()
        let now = Date()
        for (i, spot) in [0, 2].enumerated() {
            let id = "preview-\(i)"
            snapshot.cutouts.append(CampCutoutRecord(id: id, shotId: "sample-\(i)", layers: result.layers, spot: spot,
                                                     title: L("霧の針葉樹林", "Misty conifers"), place: L("富士河口湖町", "Fujikawaguchiko"),
                                                     takenAt: now, createdAt: now.addingTimeInterval(Double(i))))
            try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            for (k, card) in result.cards.enumerated() {
                try? png(card)?.write(to: store.imageURL(cutout: id, layer: k))
            }
        }
        snapshot.skies[CampTime.morning.rawValue] = result.sky.map { CampSkySample(colors: $0, takenAt: now) }
        store.replaceForPreview(snapshot)
    }

    #else

    // Linux の模型（Vision も画像の画素も無い）。実機では使わない
    static func cut(_ source: UIImage, frame: CGRect, viewSize: CGSize) async -> CampCutResult {
        let layers = CampLayerSplit.fallback(unitHeight: 480)
        return CampCutResult(layers: layers, cards: [], photo: source, cropRect: .zero, subjects: [], hasPeople: false,
                             sky: nil, title: CampSubjectRule.title([], season: .summer))
    }

    static func cards(_ cut: CampCutLayers, crop: UIImage?) -> [UIImage] { [] }
    static func metadata(_ data: Data) -> (date: Date?, latitude: Double?, longitude: Double?, altitude: Double?) { (nil, nil, nil, nil) }
    static func png(_ image: UIImage) -> Data? { nil }
    static func cropJPEG(_ result: CampCutResult) -> Data? { nil }
    static func jpeg(_ image: UIImage) -> Data? { image.jpegData(compressionQuality: 0.85) }
    static func samplePhoto() -> UIImage { UIImage() }
    @MainActor static func preparePreview(_ store: CampStore) async {}

    #endif
}
