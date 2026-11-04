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

    /// SNSでは撮影地点をそのまま描かず、約50km単位の概略ピンにする。
    /// 位置が不正な場合は地図を表示しない。
    static func approximateShareCoordinate(_ coords: Photo.Coords?) -> CLLocationCoordinate2D? {
        guard let coords, coords.lat.isFinite, coords.lng.isFinite,
              (-90...90).contains(coords.lat), (-180...180).contains(coords.lng) else { return nil }
        let step = 0.5
        return CLLocationCoordinate2D(
            latitude: (coords.lat / step).rounded() * step,
            longitude: (coords.lng / step).rounded() * step)
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
        // SNS地図は概略位置の周辺を描画する。道路・施設名は描画しない。
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
            // 下の段の位置は ShareCardMap.Layout に1か所で持つ（地図の枠の計算とテストが同じ数を使う）
            let layout = ShareCardMap.Layout(ratio: ratio)
            let margin = ShareCardMap.Layout.margin
            let photoBottom = layout.photoBottom
            let photoRect = layout.photoRect
            let scale = max(photoRect.width / photo.size.width,
                            photoRect.height / photo.size.height)
            let fitted = CGRect(x: photoRect.midX - photo.size.width * scale / 2,
                                y: photoRect.midY - photo.size.height * scale / 2,
                                width: photo.size.width * scale,
                                height: photo.size.height * scale)
            cg.saveGState()
            cg.clip(to: photoRect)
            photo.draw(in: fitted)
            // 写真は一度だけ描画する。従来の背景拡大＋中央Fit重ね描きは
            // 9:16で同じ被写体が二重に見える原因だったため廃止。
            cg.restoreGState()

            let fade = layout.fadeRect
            let stops = ShareCardMap.Layout.fadeStops
            let colors = stops.map { stop in
                stop.alpha == 0 ? UIColor.black.withAlphaComponent(0).cgColor
                    : surface.withAlphaComponent(stop.alpha).cgColor
            } as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: stops.map { $0.location }) {
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
                mark.withTintColor(.white).draw(in: CGRect(x: 95, y: 49, width: 45, height: 45))
            }
            draw("Journey Photo", at: CGPoint(x: 157, y: 51), maxWidth: 365,
                 size: 39, color: .white, serif: true)
            cg.setStrokeColor(brass.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(2)
            cg.move(to: CGPoint(x: 550, y: 46))
            cg.addLine(to: CGPoint(x: 550, y: 103))
            cg.strokePath()
            draw("旅の一瞬を、誰かの次の旅へ。", at: CGPoint(x: 565, y: 66),
                  maxWidth: 410, size: 25, color: .white, alignment: .right)

            // 写真境界からの距離と下段との余白を両立する。
            // 行内の要素は左揃えを維持し、情報ブロックだけを余白の中心へ寄せる。
            let rowY = layout.rowY
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
            // マークが3つ以上ある場合は名前の横に押し込まず、2段に分ける。
            // これにより長い撮影者名の過度な縮小を避ける。
            let knownBadge = credit.badge.map { BadgeCatalog.isKnown($0.key) } ?? false
            let markCount = (credit.verified ? 1 : 0) + (credit.proStyle == nil ? 0 : 1)
                + (credit.early ? 1 : 0) + (knownBadge ? 1 : 0)
            let markWidth = CGFloat(markCount * 30 + (credit.proStyle == .plate ? 16 : 0))
            let stackedMarks = markCount >= 3
            let nameWidth = stackedMarks ? CGFloat(255) : max(90, 255 - markWidth)
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
            if stackedMarks {
                drawNameMarks(credit, at: CGPoint(x: 220, y: rowY + 45))
            } else {
                drawNameMarks(credit, at: CGPoint(x: 220 + actualNameWidth + 5, y: rowY + 7))
            }
            if let username = credit.username?.trimmingCharacters(in: .whitespacesAndNewlines),
               !username.isEmpty {
                // 複数マークとユーザー名を同じ行に置くと短い幅で文字が欠ける。
                // マークが多い場合はユーザー名を上段の右側に置かず、
                // 下段をマーク専用にしてユーザー名を表示可能な幅で確保する。
                let usernameX: CGFloat = 220
                let usernameWidth: CGFloat = 245
                let usernameY: CGFloat = stackedMarks ? rowY + 82 : rowY + 53
                draw("@" + username.trimmingCharacters(in: CharacterSet(charactersIn: "@")),
                     at: CGPoint(x: usernameX, y: usernameY), maxWidth: usernameWidth,
                     size: stackedMarks ? 18 : 25, color: secondary)
            }
            cg.setStrokeColor(brass.withAlphaComponent(0.4).cgColor)
            cg.move(to: CGPoint(x: 493, y: rowY - 4))
            cg.addLine(to: CGPoint(x: 493, y: rowY + 105))
            cg.strokePath()

            if let place = credit.location?.trimmingCharacters(in: .whitespacesAndNewlines),
               !place.isEmpty {
                drawSymbol("mappin.circle", at: CGPoint(x: 520, y: rowY + 21),
                           size: 37, color: brass)
                // 語の途中では折らない（ShareCardText・2026-11-04 owner）。
                // 地図があるときは 140 幅（案A-3: 155 → 140 に詰めて地図の枠を広げた）
                drawWrapped(place, at: CGPoint(x: ShareCardMap.Layout.placeX, y: rowY + 22),
                            maxWidth: credit.coords == nil
                                ? ShareCardMap.Layout.placeWidthWithoutMap
                                : ShareCardMap.Layout.placeWidthWithMap,
                            size: 26, lines: 3, color: .white)
            }
            if let coordinate = credit.coords {
                // 案A-3（2026-11-04 owner 了承）: 290×250。写真の裾の黒 86% の所から区切り線の 9px 上まで
                CountryOutline.drawAtLocation(pin: coordinate, place: credit.location,
                                              in: layout.mapRect, color: brass, context: cg)
            }

            let separatorY = layout.separatorY
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
            // UIKit lays out the symbol and text together, using the symbol's
            // native baseline metrics instead of a hard-coded pixel offset.
            if !camera.isEmpty {
                drawMetadataRow("camera", text: camera, at: CGPoint(x: 98, y: infoY + 3),
                                textX: 157, textWidth: 235, fontSize: 22,
                                symbolSize: 40, color: brass, context: cg)
            }
            if !lens.isEmpty {
                drawMetadataRow("camera.aperture", text: lens, at: CGPoint(x: 410, y: infoY + 3),
                                textX: 463, textWidth: 246, fontSize: 22,
                                symbolSize: 40, color: brass, context: cg)
            }
            if !exposure.isEmpty {
                drawMetadataRow("timer", text: exposure, at: CGPoint(x: 731, y: infoY + 3),
                                textX: 786, textWidth: 195, fontSize: 20,
                                symbolSize: 38, color: brass, context: cg)
            }

            // 真鍮色の矩形フレームは画像境界から8px内側へ。
            // SNS側で端が切り取られても線が消えにくく、外側も黒背景で統一する。
            // 角丸・透明余白は作らず、共有/保存するJPEG自体に描き込む。
            let frameInset: CGFloat = 8
            let frameWidth: CGFloat = 4
            cg.setStrokeColor(brass.withAlphaComponent(0.9).cgColor)
            cg.setLineWidth(frameWidth)
            cg.stroke(CGRect(x: frameInset + frameWidth / 2,
                           y: frameInset + frameWidth / 2,
                           width: width - 2 * frameInset - frameWidth,
                           height: height - 2 * frameInset - frameWidth))
        }
    }

    // Natural Earth admin-0 countries由来の輪郭をJSONとして同梱する。
    // 解像度は同梱リソースに依存し、ここでは固定しない。
    private enum CountryOutline {
        typealias Shape = ShareCardMap.Shape
        static let shapes: [Shape] = ShareCardMap.loadShapes(resource: "country-outlines")
        /// 日本の47都道府県（Tools/generate-japan-prefectures.py）。日本の写真で撮った県を塗る
        static let prefectures: [Shape] = ShareCardMap.loadShapes(resource: "japan-prefectures")

        static func contains(_ point: CLLocationCoordinate2D, ring: [[Double]]) -> Bool {
            guard ring.count >= 3 else { return false }
            // Unwrap each segment around the query longitude. A polygon that
            // crosses ±180° must not become a 360-degree-wide polygon.
            var vertices: [(x: Double, y: Double)] = []
            vertices.reserveCapacity(ring.count)
            for vertex in ring where vertex.count == 2 {
                let longitude = vertex[0]
                let x: Double
                if let previous = vertices.last {
                    x = longitude + 360 * round((previous.x - longitude) / 360)
                } else {
                    x = longitude + 360 * round((point.longitude - longitude) / 360)
                }
                vertices.append((x, vertex[1]))
            }
            guard vertices.count >= 3 else { return false }
            var west = Double.infinity
            var east = -Double.infinity
            var south = Double.infinity
            var north = -Double.infinity
            for vertex in vertices {
                west = min(west, vertex.x)
                east = max(east, vertex.x)
                south = min(south, vertex.y)
                north = max(north, vertex.y)
            }
            let queryLongitude = point.longitude +
                360 * round(((west + east) / 2 - point.longitude) / 360)
            guard (west...east).contains(queryLongitude),
                  (south...north).contains(point.latitude) else { return false }
            var inside = false
            var previous = vertices.count - 1
            for index in vertices.indices {
                let a = vertices[index], b = vertices[previous]
                if (a.y > point.latitude) != (b.y > point.latitude) {
                    let intersection = (b.x - a.x) *
                        (point.latitude - a.y) / (b.y - a.y) + a.x
                    if queryLongitude < intersection { inside.toggle() }
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
                // Match the renderer's even-odd fill: holes are water, not land.
                shape.r.reduce(false) { inside, ring in
                    inside != contains(coordinate, ring: ring)
                }
            }
        }

        /// 海上や小島でも近隣の実際の国境・海岸線を表示する。
        /// Natural Earth の輪郭が範囲内にない場合だけ地点の目盛りを表示する。
        static func drawNearby(pin: CLLocationCoordinate2D, in rect: CGRect,
                               color: UIColor, context: CGContext) {
            let span: Double = 3.5
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
                    // 頂点が範囲外でも線分が表示領域を横切る場合がある。
                    // 輪郭の外接矩形が表示領域と交差するものを描画対象にする。
                    let points = ring.filter { $0.count == 2 }
                    guard let west = points.map({ $0[0] }).min(),
                          let east = points.map({ $0[0] }).max(),
                          let south = points.map({ $0[1] }).min(),
                          let north = points.map({ $0[1] }).max(),
                          east >= minLon, west <= maxLon,
                          north >= minLat, south <= maxLat else { continue }
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

        /// Use the complete country silhouette. If coarse coordinates land just offshore,
        /// use the nearest country within a conservative geographic threshold.
        static func shapeForDisplay(at pin: CLLocationCoordinate2D) -> Shape? {
            if let contained = find(at: pin) { return contained }
            let longitudeWeight = max(0.2, cos(pin.latitude * .pi / 180))
            var closest: Shape?
            var bestDistance = Double.greatestFiniteMagnitude
            for shape in shapes {
                for ring in shape.r {
                    for point in ring where point.count == 2 {
                        let dx = (point[0] - pin.longitude) * longitudeWeight
                        let dy = point[1] - pin.latitude
                        let distance = dx * dx + dy * dy
                        if distance < bestDistance {
                            bestDistance = distance
                            closest = shape
                        }
                    }
                }
            }
            // 0.5-degree rounding can move a coastal pin offshore; never infer
            // a distant country for a point in open water.
            return bestDistance <= 0.15 * 0.15 ? closest : nil
        }

        static func drawAtLocation(pin: CLLocationCoordinate2D, place: String?, in rect: CGRect,
                                   color: UIColor, context: CGContext) {
            guard pin.latitude.isFinite, pin.longitude.isFinite,
                  (-90...90).contains(pin.latitude),
                  (-180...180).contains(pin.longitude) else { return }
            guard let shape = shapeForDisplay(at: pin) else {
                // Tiny islands and open-water locations are absent from the
                // bundled coastline data. Never leave the map slot blank.
                SignatureShareCardRenderer.drawLocationFallback(
                    in: rect, color: color, context: context)
                return
            }
            // 日本だけ、撮影地の文字の県を塗る（海外は国の輪郭だけ）
            let prefecture = shape.n == "Japan"
                ? ShareCardMap.prefectureShape(named: ShareCardMap.prefectureName(in: place),
                                               among: prefectures,
                                               latitude: pin.latitude, longitude: pin.longitude)
                : nil
            draw(shape, prefecture: prefecture, pin: pin, in: rect, color: color, context: context)
        }

        static func draw(_ shape: Shape, prefecture: Shape?, pin: CLLocationCoordinate2D,
                         in rect: CGRect, color: UIColor, context: CGContext) {
            // 案A-3（2026-11-04 owner 了承）: 国の全体ではなく、撮った場所の島と一番大きい陸から
            // 60km 以内でつながる島だけを枠に収める（ShareCardMap.focusRingIndices）。
            // 経度は撮った場所の側へ開く（±180° をまたぐ国が 360° 幅にならない）。
            // 収めた範囲の外の島も同じ国なら描く（枠で切れるだけ）。
            guard let focused = ShareCardMap.focus(shape, latitude: pin.latitude,
                                                   longitude: pin.longitude, in: rect) else { return }
            let rings = focused.rings
            let projection = focused.projection
            func project(_ p: [Double]) -> CGPoint {
                projection.point(longitude: p[0], latitude: p[1])
            }
            context.saveGState()
            context.clip(to: rect)
            context.setShouldAntialias(true)
            context.setAllowsAntialiasing(true)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            // Reference card: a fine gold country silhouette with a single
            // restrained luminous location dot. Avoid thick strokes at 195x128.
            context.beginPath()
            for ring in rings where ring.count >= 3 {
                context.move(to: project(ring[0]))
                for point in ring.dropFirst() where point.count == 2 {
                    context.addLine(to: project(point))
                }
                context.closePath()
            }
            if let silhouette = context.path {
                context.addPath(silhouette)
                context.setFillColor(color.withAlphaComponent(0.045).cgColor)
                context.drawPath(using: .eoFill)
                // 撮った県を真鍮 75% で塗る（板 MapA3）。輪郭の線はその上に引く
                if let prefecture {
                    context.beginPath()
                    for ring in ShareCardMap.unwrap(prefecture.r, aroundLongitude: pin.longitude)
                    where ring.count >= 3 {
                        context.move(to: project(ring[0]))
                        for point in ring.dropFirst() where point.count == 2 {
                            context.addLine(to: project(point))
                        }
                        context.closePath()
                    }
                    context.setFillColor(color.withAlphaComponent(0.75).cgColor)
                    context.drawPath(using: .eoFill)
                }
                // Subtle halo and crisp hairline keep small islands legible.
                context.addPath(silhouette)
                context.setStrokeColor(color.withAlphaComponent(0.22).cgColor)
                context.setLineWidth(2.1)
                context.strokePath()
                context.addPath(silhouette)
                context.setStrokeColor(color.withAlphaComponent(0.94).cgColor)
                context.setLineWidth(0.95)
                context.strokePath()
            }
            let center = project([pin.longitude, pin.latitude])
            // The point should glow gently rather than obscure nearby coastline.
            context.setFillColor(color.withAlphaComponent(0.18).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - 5, y: center.y - 5,
                                           width: 10, height: 10))
            context.setFillColor(color.withAlphaComponent(0.95).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - 2.2, y: center.y - 2.2,
                                           width: 4.4, height: 4.4))
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

    /// 字の幅を測る（ShareCardText に渡す）
    static func measuredWidth(_ text: String, size: CGFloat, weight: UIFont.Weight = .semibold) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: weight)]).width)
    }

    /// 撮影情報の列の行。高さ 72 に入る行数で、語の途中では折らない（2026-11-04 owner）。
    /// 収まらなければ 0.5 ずつ小さくする（下限 7 は従来どおり）。
    static func equipmentLayout(_ value: String, maxWidth: CGFloat,
                                preferredSize: CGFloat = 22,
                                availableHeight: CGFloat = 72) -> ShareCardText.Fitted {
        ShareCardText.fit(value, maxWidth: maxWidth, preferredSize: preferredSize,
                          minimumSize: 7, step: 0.5,
                          maxLines: { size in
                              // 行の高さ＋行間 1 で、何行まで高さに入るか
                              let line = UIFont.systemFont(ofSize: size, weight: .semibold).lineHeight
                              return max(1, Int((availableHeight + 1) / (line + 1)))
                          },
                          measure: { measuredWidth($0, size: $1) })
    }

    /// 撮影情報の列幅と高さに合わせて、全文を表示できる最大フォントサイズを求める。
    static func equipmentFontSize(_ value: String, maxWidth: CGFloat,
                                  preferredSize: CGFloat = 22,
                                  availableHeight: CGFloat = 72) -> CGFloat {
        equipmentLayout(value, maxWidth: maxWidth, preferredSize: preferredSize,
                        availableHeight: availableHeight).size
    }

    /// 撮影地の行。撮影者名と同じ縮め方（1 ずつ・下限は 16 と 72% の大きい方）
    static func placeLayout(_ value: String, maxWidth: CGFloat, size: CGFloat = 26,
                            lines: Int = 3) -> ShareCardText.Fitted {
        ShareCardText.fit(value, maxWidth: maxWidth, preferredSize: size,
                          minimumSize: max(16, size * 0.72),
                          maxLines: { _ in lines },
                          measure: { measuredWidth($0, size: $1) })
    }

    /// 区切りの所でだけ折った行を、そのまま描く（UIKit に折り返させない）
    private static func drawWrapped(_ value: String, at origin: CGPoint, maxWidth: CGFloat,
                                    size: CGFloat, lines: Int, color: UIColor) {
        let fitted = placeLayout(value, maxWidth: maxWidth, size: size, lines: lines)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        let font = UIFont.systemFont(ofSize: fitted.size, weight: .semibold)
        (fitted.lines.joined(separator: "\n") as NSString).draw(
            in: CGRect(x: origin.x, y: origin.y, width: maxWidth,
                       height: size * CGFloat(lines) * 1.35),
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    /// 撮影情報の1列（記号＋字）。記号は字の1行目のベースラインにそろえる。
    ///
    /// 2026-11-04 判断: UIView と Auto Layout（UILabel・UIImageView・制約）で組むのをやめた。
    /// `render` は画面の処理（メインスレッド）の外で走るので、Auto Layout を触ると
    /// 「Modifications to the layout engine must not be performed from a background thread」で
    /// 落ちる（Mac の単体テストで実測: #476 の PR の検証 run 41679775959 と、この枝の run 832。
    /// 落ちた所は drawMetadataRow → -[UIView layoutBelowIfNeeded]）。
    /// 同じそろえ方（UIImageView の firstBaseline＝記号の baselineOffsetFromBottom を表示の大きさへ縮めた所）を
    /// 数で出して、UIImage と NSString で直に描く（どちらも描画の文脈の中ならメインの外で使える）。
    /// 字は ShareCardText で語の切れ目でだけ折った行（語の途中で折らない）。
    private static func drawMetadataRow(_ symbolName: String, text: String,
                                        at origin: CGPoint, textX: CGFloat,
                                        textWidth: CGFloat, fontSize: CGFloat,
                                        symbolSize: CGFloat, color: UIColor,
                                        context: CGContext) {
        let fitted = equipmentLayout(text, maxWidth: textWidth, preferredSize: fontSize)
        let font = UIFont.systemFont(ofSize: fitted.size, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1
        paragraph.lineBreakMode = .byClipping
        // 字の上端は origin.y（前の UILabel の topAnchor と同じ）。1行目のベースラインは上端＋ascender
        (fitted.lines.joined(separator: "\n") as NSString).draw(
            with: CGRect(x: textX, y: origin.y, width: textWidth, height: 72),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph],
            context: nil)
        let textBaseline = origin.y + font.ascender
        guard let symbol = UIImage(systemName: symbolName,
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: symbolSize,
                                                                                  weight: .regular))?
            .withTintColor(color, renderingMode: .alwaysOriginal),
              symbol.size.width > 0, symbol.size.height > 0 else { return }
        // symbolSize の正方形に縦横比を保って収める（前の scaleAspectFit と同じ）
        let scale = min(symbolSize / symbol.size.width, symbolSize / symbol.size.height)
        let drawn = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let inBox = CGRect(x: (symbolSize - drawn.width) / 2, y: (symbolSize - drawn.height) / 2,
                           width: drawn.width, height: drawn.height)
        // 正方形の上端から記号のベースラインまで（ベースラインの無い記号は下端）
        let baselineInBox = inBox.maxY - (symbol.baselineOffsetFromBottom ?? 0) * scale
        let boxTop = textBaseline - baselineInBox
        symbol.draw(in: inBox.offsetBy(dx: origin.x, dy: boxTop))
    }

    private static func drawSymbol(_ name: String, at origin: CGPoint,
                                   size: CGFloat, color: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        // SF Symbols have different intrinsic aspect ratios (e.g. camera is wider
        // than it is tall). Fit the symbol inside the square slot without stretching.
        let intrinsicSize = symbol.size
        guard intrinsicSize.width > 0, intrinsicSize.height > 0 else { return }
        let scale = min(size / intrinsicSize.width, size / intrinsicSize.height)
        let fittedSize = CGSize(width: intrinsicSize.width * scale,
                                height: intrinsicSize.height * scale)
        let fittedOrigin = CGPoint(x: origin.x + (size - fittedSize.width) / 2,
                                   y: origin.y + (size - fittedSize.height) / 2)
        symbol.draw(in: CGRect(origin: fittedOrigin, size: fittedSize))
    }

    private static func draw(_ value: String, at origin: CGPoint, maxWidth: CGFloat,
                             size: CGFloat, color: UIColor, bold: Bool = false,
                             serif: Bool = false, alignment: NSTextAlignment = .left) {
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let font = serif ? (base.fontDescriptor.withDesign(.serif).map {
            UIFont(descriptor: $0, size: size)
        } ?? base) : base
        // 1行だけ。長い名前は可能な範囲で縮小し、最後だけ省略する（語の途中で折らない）。
        // 折り返す撮影地・撮影情報は ShareCardText で区切りの所だけで折る。
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
                             width: maxWidth, height: size * 1.35),
                  withAttributes: [.font: fittedFont, .foregroundColor: color,
                                   .paragraphStyle: paragraph])
    }
    #endif
}
