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

    /// カードの型（2026-11-05 owner「ユーザが選べるように」）。
    /// - `band`: 写真の下に黒い帯（いまの型・既定）
    /// - `fade`: 写真を全面に敷き、下を黒へ溶かす（見本 F2）
    enum Style: String, CaseIterable {
        case band
        case fade
        /// 地名を明朝の主役に、ラベルつきの撮影情報の表を下に置く（見本 S2）
        case label
        /// 地名を大きな明朝で、写真と黒のあいだにまたがらせる（見本 F5）
        case cover
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
        /// 撮影地の2行（大きい単位／（小さい単位））。無ければ `location` から分ける
        /// （`LocationMatch.shareCardPlace`・2026-11-04 owner）
        var place: LocationMatch.ShareCardPlace? = nil

        var placeLines: [String] {
            (place ?? LocationMatch.shareCardPlace(location))?.lines ?? []
        }
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

    static let surface = UIColor(red: 14/255, green: 14/255, blue: 15/255, alpha: 1)
    static let brass = UIColor(red: 201/255, green: 166/255, blue: 107/255, alpha: 1)
    static let secondary = UIColor(red: 184/255, green: 184/255, blue: 184/255, alpha: 1)

    #if os(Linux)
    // LinuxのSDK模型にはCoreGraphics/MapKit描画APIがない。実描画はiOSのXcodeで検証する。
    static func render(_ data: Data, credit: Credit, ratio: Ratio = .portrait, style: Style = .band, avatarData: Data? = nil) async -> Data? { nil }
    #else
    static func render(_ data: Data, credit: Credit, ratio: Ratio = .portrait, style: Style = .band, avatarData: Data? = nil) async -> Data? {
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
        switch style {
        case .fade: return renderFade(photo: photo, credit: credit, ratio: ratio, avatarData: avatarData)
        case .label: return renderLabel(photo: photo, credit: credit, ratio: ratio, avatarData: avatarData)
        case .cover: return renderCover(photo: photo, credit: credit, ratio: ratio, avatarData: avatarData)
        case .band: break   // 帯の型
        }
        typealias L = ShareCardMap.Layout
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
            // 撮影情報が1つも無ければ、下の段（区切り線・間・撮影情報の行）の分だけ帯を縮めて写真を伸ばす（2026-11-13・owner 承認）
            let exif = exifValues(credit)
            let camera = exif.camera, lens = exif.lens, exposure = exif.exposure
            let filled = [!camera.isEmpty, !lens.isEmpty, !exposure.isEmpty]
            let layout = ShareCardMap.Layout(ratio: ratio, hasShotInfo: filled.contains(true))
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

            // 2026-11-04 owner「フェードする境界線いらない」: 写真は帯の開始位置できれいに終わり、
            // その下は黒い面（surface）。写真の裾に黒を重ねない
            surface.setFill()
            cg.fill(layout.bandRect)

            // 上の帯。字の大文字の高さの中心を、マークの中心にそろえる（2026-11-04 owner）
            let markY = L.headerMarkY
            let markMidY = markY + L.headerMarkSize / 2
            if let mark = UIImage(named: "BrandMark")?.withRenderingMode(.alwaysTemplate) {
                mark.withTintColor(.white).draw(in: CGRect(x: L.contentLeft, y: markY,
                                                           width: L.headerMarkSize, height: L.headerMarkSize))
            }
            draw("Journey Photo",
                 at: CGPoint(x: L.contentLeft + L.headerMarkSize + 17, y: wordmarkTop(markMidY: markMidY)),
                 maxWidth: 365, size: 39, color: .white, serif: true)
            let lineColor = brass.withAlphaComponent(L.lineAlpha).cgColor
            cg.setStrokeColor(lineColor)
            cg.setLineWidth(L.lineWidth)
            cg.move(to: CGPoint(x: L.width / 2, y: L.headerCenter - 29))
            cg.addLine(to: CGPoint(x: L.width / 2, y: L.headerCenter + 28))
            cg.strokePath()
            // 一文と Web の住所の2行の塊は、帯の縦の中心にそろえる。右端は本文の右端
            drawTaglineAndAddress(centerY: L.headerCenter, right: L.contentRight, taglineSize: 25,
                                  addressColor: brass)

            // 撮影者の段。要素はアバターの縦の中心にそろえる
            let rowTop = layout.rowTop
            let avatarSize = L.avatarSize
            // アバター未取得の場合はブランド色の円形モノグラムで代替。
            let avatarRect = CGRect(x: L.contentLeft, y: rowTop, width: avatarSize, height: avatarSize)
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
                let initialFont = UIFont.systemFont(ofSize: 34)
                draw(initial.isEmpty ? "J" : initial,
                     at: CGPoint(x: avatarRect.minX + 20, y: avatarRect.midY - initialFont.lineHeight / 2),
                     maxWidth: 44, size: 34, color: .white, serif: true)
            }
            let authorName = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            // マークが3つ以上ある場合は名前の横に押し込まず、2段に分ける。
            // これにより長い撮影者名の過度な縮小を避ける。
            let knownBadge = credit.badge.map { BadgeCatalog.isKnown($0.key) } ?? false
            let markCount = (credit.verified ? 1 : 0) + (credit.proStyle == nil ? 0 : 1)
                + (credit.early ? 1 : 0) + (knownBadge ? 1 : 0)
            let markWidth = CGFloat(markCount * 30 + (credit.proStyle == .plate ? 16 : 0))
            let stackedMarks = markCount >= 3
            let columnWidth = L.nameColumnWidth
            let nameWidth = stackedMarks ? columnWidth : max(90, columnWidth - markWidth)
            let nameSize: CGFloat = 26
            let nameFont = UIFont.systemFont(ofSize: nameSize, weight: .semibold)
            var fittedNameFont = nameFont
            let minimumNameSize: CGFloat = max(16, nameSize * 0.72)
            let nameText = authorName as NSString
            while fittedNameFont.pointSize > minimumNameSize,
                  nameText.size(withAttributes: [.font: fittedNameFont]).width > nameWidth {
                fittedNameFont = UIFont(descriptor: nameFont.fontDescriptor,
                                        size: max(minimumNameSize, fittedNameFont.pointSize - 1))
            }
            let actualNameWidth = min(nameWidth,
                ceil(nameText.size(withAttributes: [.font: fittedNameFont]).width))
            // 名前（26）と @ユーザー名（21）の塊を（2026-11-05 owner: 30/24 から小さく）、アバターの縦の中心に置く。
            // マーク3つ以上の2段は、名前・マーク・ユーザー名（18）の3段の塊
            let usernameSize: CGFloat = stackedMarks ? 16 : 21
            let nameLine = UIFont.systemFont(ofSize: nameSize, weight: .semibold).lineHeight
            let userLine = UIFont.systemFont(ofSize: usernameSize).lineHeight
            let hasUsername = !(credit.username?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let markLine: CGFloat = stackedMarks ? 28 : 0
            let blockHeight = nameLine + (stackedMarks ? markLine : 0)
                + (hasUsername ? userLine + 4 : 0)
            let nameY = rowTop + (avatarSize - blockHeight) / 2
            draw(authorName, at: CGPoint(x: L.nameX, y: nameY), maxWidth: nameWidth,
                 size: nameSize, color: .white, bold: true)
            if stackedMarks {
                drawNameMarks(credit, at: CGPoint(x: L.nameX, y: nameY + nameLine))
            } else {
                drawNameMarks(credit, at: CGPoint(x: L.nameX + actualNameWidth + 5,
                                                  y: nameY + (nameLine - 27) / 2))
            }
            if let username = credit.username?.trimmingCharacters(in: .whitespacesAndNewlines),
               !username.isEmpty {
                // 複数マークとユーザー名を同じ行に置くと短い幅で文字が欠ける。
                // マークが多い場合はユーザー名を下段にして、表示可能な幅で確保する。
                draw("@" + username.trimmingCharacters(in: CharacterSet(charactersIn: "@")),
                     at: CGPoint(x: L.nameX, y: nameY + nameLine + markLine + 4),
                     maxWidth: columnWidth, size: usernameSize, color: secondary)
            }
            // 縦の区切りは、撮影情報の左の縦線と同じ x（撮影者の段の上端から下端まで）
            cg.setStrokeColor(lineColor)
            cg.setLineWidth(L.lineWidth)
            cg.move(to: CGPoint(x: L.rowDividerX, y: rowTop))
            cg.addLine(to: CGPoint(x: L.rowDividerX, y: rowTop + avatarSize))
            cg.strokePath()

            let placeLines = credit.placeLines
            if !placeLines.isEmpty {
                let pinSize: CGFloat = 37
                drawSymbol("mappin.circle", at: CGPoint(x: L.pinX, y: layout.rowCenterY - pinSize / 2),
                           size: pinSize, color: brass)
                // 決まった2行（「山梨県」「（山中湖村）」）。行の中では折らない（2026-11-04 owner）。
                // 2行の塊をアバターの縦の中心に置く
                drawPlaceLines(placeLines,
                               at: CGPoint(x: L.placeX, y: layout.rowCenterY - L.placeHeight / 2),
                               maxWidth: layout.placeWidth(hasMap: credit.coords != nil),
                               color: .white)
            }
            if let coordinate = credit.coords {
                // 地図8（2026-11-04 owner 採用）: 264×296。帯が黒 70% になる所から撮影情報の 8 上まで。
                // 塗る県は、撮影地の1行目（県）と元の文字の両方から引く（英語の "Kyoto" も表で和文へ）
                let placeText = (placeLines + [credit.location ?? ""]).joined(separator: ", ")
                CountryOutline.drawAtLocation(pin: coordinate, place: placeText,
                                              in: layout.mapRect, color: brass, context: cg)
            }

            // 区切り線（地図があるときは地図の手前で止める）。撮影情報が1つも無ければ、下の段ごと描かない
            // （2026-11-13: そのときは帯もその分低い・`ShareCardMap.Layout.hasShotInfo`）
            if layout.hasShotInfo {
                let separatorY = layout.separatorY
                cg.setStrokeColor(lineColor)
                cg.setLineWidth(L.lineWidth)
                cg.move(to: CGPoint(x: L.contentLeft, y: separatorY + L.lineWidth / 2))
                cg.addLine(to: CGPoint(x: layout.separatorEndX(hasMap: credit.coords != nil),
                                       y: separatorY + L.lineWidth / 2))
                cg.strokePath()
            }
            // 撮影情報は個別の箱ではなく細い縦罫線で区切る。3列の左端は上の段の縦の線にそろえる
            // （1列目＝アバターの左端・2列目＝縦線の右の印と同じ x・3列目＝地図の左端）。
            // 縦罫は 40 の高さで、行の縦の中心に置く。両側の列に字があるときだけ描く
            let infoCenterY = layout.infoCenterY
            cg.setStrokeColor(lineColor)
            cg.setLineWidth(L.lineWidth)
            for index in ShareCardMap.infoDividerIndices(filled: filled) {
                let dividerX = L.infoDividerXs[index]
                cg.move(to: CGPoint(x: dividerX, y: infoCenterY - 20))
                cg.addLine(to: CGPoint(x: dividerX, y: infoCenterY + 20))
                cg.strokePath()
            }
            // 値のない撮影項目はアイコンだけ残さない。
            let symbolSize: CGFloat = 30
            let textGap: CGFloat = 10
            let cameraX = L.contentLeft
            let lensX = L.pinX
            let exposureX = L.exposureX
            let cameraWidth = L.rowDividerX - 24 - cameraX
            let lensWidth = L.lensColumnWidth
            let exposureWidth = L.mapX - 24 - exposureX
            if !camera.isEmpty {
                drawMetadataRow("camera", text: camera,
                                x: cameraX, centerY: infoCenterY,
                                textWidth: cameraWidth - symbolSize - textGap, fontSize: 17,
                                symbolSize: symbolSize, textGap: textGap, color: brass, context: cg)
            }
            if !lens.isEmpty {
                drawMetadataRow("camera.aperture", text: lens,
                                x: lensX, centerY: infoCenterY,
                                textWidth: lensWidth - symbolSize - textGap, fontSize: 17,
                                symbolSize: symbolSize, textGap: textGap, color: brass, context: cg)
            }
            if !exposure.isEmpty {
                drawMetadataRow("timer", text: exposure,
                                x: exposureX, centerY: infoCenterY,
                                textWidth: exposureWidth - symbolSize - textGap, fontSize: 17,
                                symbolSize: symbolSize, textGap: textGap, color: brass, context: cg)
            }

            // 真鍮色の矩形フレームは画像境界から12px内側へ。
            // SNS側で端が切り取られても線が消えにくく、外側も黒背景で統一する。
            // 角丸・透明余白は作らず、共有/保存するJPEG自体に描き込む。
            let frameInset = L.frameInset
            let frameWidth = L.frameWidth
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
    enum CountryOutline {
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
            // 2026-11-04 owner「地図の点もうちょい大きくていい」: 点は半径 4・光の輪は半径 10。
            // 地図が黒い帯の中（200×146）になって縮尺が小さくなったので、以前の 8/18 では県の塗りが点に隠れた。
            // 約50km に丸めた位置なので、輪を点より大きく取り「この辺り」と見せる
            // 2026-11-05 owner「地図の点少し小さい」: 地図が 236×244 に広がって点が相対的に小さく見えたので、
            // 点は半径 4 → 6、光の輪は半径 10 → 14
            context.setFillColor(color.withAlphaComponent(0.22).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - 14, y: center.y - 14,
                                           width: 28, height: 28))
            context.setFillColor(color.withAlphaComponent(0.95).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - 6, y: center.y - 6,
                                           width: 12, height: 12))
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

    // MARK: - フェード型（2026-11-05・見本 F2）

    /// 写真を全面に敷き、下を長いグラデーションで黒へ溶かす型。寸法は `ShareCardMap.FadeLayout`。
    /// 帯の型の `render` とは別の関数にして、帯の型の描き方（テストが固定している数）に触れない。
    private static func renderFade(photo: UIImage, credit: Credit, ratio: Ratio, avatarData: Data?) -> Data? {
        typealias F = ShareCardMap.FadeLayout
        let layout = F(ratio: ratio)
        let canvas = CGSize(width: F.width, height: layout.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: canvas, format: format).jpegData(withCompressionQuality: 0.93) { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))
            // 写真は全面（縦横比を保って埋める）
            let scale = max(canvas.width / photo.size.width, canvas.height / photo.size.height)
            photo.draw(in: CGRect(x: (canvas.width - photo.size.width * scale) / 2,
                                  y: (canvas.height - photo.size.height * scale) / 2,
                                  width: photo.size.width * scale, height: photo.size.height * scale))
            // 上の影（ロゴと一文を空の上でも読めるように）。下のグラデーション（長く滑らか・境目を見せない）
            func shade(from y0: CGFloat, to y1: CGFloat, stops: [(location: CGFloat, alpha: CGFloat)]) {
                let colors = stops.map { UIColor.black.withAlphaComponent($0.alpha).cgColor } as CFArray
                let locations = stops.map { $0.location }
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                colors: colors, locations: locations) else { return }
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [])
            }
            shade(from: 0, to: F.topShadeHeight, stops: [
                (0, F.topShadeAlpha), (0.45, F.topShadeAlpha * 0.5), (1, 0)])
            // 下の空き（9:16）は黒一色。グラデーションは基準線で 1 に着き、その下は 1 のまま
            var bottomStops = F.fadeStops.map { stop in
                (location: stop.location * layout.fadeLength / (layout.height - layout.fadeTop), alpha: stop.alpha)
            }
            if let last = bottomStops.last, last.location < 1 { bottomStops.append((location: 1, alpha: 1)) }
            shade(from: layout.fadeTop, to: layout.height, stops: bottomStops)

            // 上: ロゴ（マーク＋字）と一文
            let markY = ShareCardMap.Layout.headerMarkY // 帯の型の見出しと同じ中心
            let markMidY = markY + ShareCardMap.Layout.headerMarkSize / 2
            if let mark = UIImage(named: "BrandMark")?.withRenderingMode(.alwaysTemplate) {
                mark.withTintColor(.white).draw(in: CGRect(x: F.contentLeft, y: markY,
                    width: ShareCardMap.Layout.headerMarkSize, height: ShareCardMap.Layout.headerMarkSize))
            }
            draw("Journey Photo",
                 at: CGPoint(x: F.contentLeft + ShareCardMap.Layout.headerMarkSize + 17, y: wordmarkTop(markMidY: markMidY)),
                 maxWidth: 365, size: 39, color: .white, serif: true)
            // 写真の上なので、住所も白（真鍮は黒い地の上だけ）
            drawTaglineAndAddress(centerY: markMidY, right: F.contentRight, taglineSize: 24,
                                  addressColor: .white)

            // 右: 地図（真鍮の細線・黒に溶けた所に置く）
            if let coordinate = credit.coords {
                let placeText = (credit.placeLines + [credit.location ?? ""]).joined(separator: ", ")
                CountryOutline.drawAtLocation(pin: coordinate, place: placeText,
                                              in: layout.mapRect, color: brass, context: cg)
            }

            // 左: 地名（明朝）・市区町村（真鍮）
            let lines = credit.placeLines
            if let first = lines.first {
                drawFittedSerif(first, at: CGPoint(x: F.contentLeft, y: layout.placeTop),
                                maxWidth: F.leftColumnWidth, size: F.placeFontSize,
                                minimumSize: F.placeMinimumFontSize, color: .white)
                if lines.count > 1 {
                    let sub = lines[1].trimmingCharacters(in: CharacterSet(charactersIn: "（）()"))
                    let pin = F.subPlaceFontSize
                    drawSymbol("mappin.circle", at: CGPoint(x: F.contentLeft, y: layout.subPlaceTop + 2),
                               size: pin, color: brass)
                    draw(sub, at: CGPoint(x: F.contentLeft + pin + 12, y: layout.subPlaceTop),
                         maxWidth: F.leftColumnWidth - pin - 12, size: F.subPlaceFontSize, color: brass, bold: true)
                }
            }

            // 撮影者（アバター・名前・ユーザー名）
            drawFadeAuthor(credit, avatarData: avatarData, top: layout.authorTop, context: cg)

            // 撮影情報は1行（地図の下端より下・幅いっぱいを3つに分ける）
            let camera = credit.camera?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lens = credit.lens?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let exposure = [credit.aperture, credit.exposure, credit.iso.map { "ISO\($0)" }]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: "  ")
            let cells: [(String, String, CGFloat, CGFloat)] = [
                ("camera", camera, F.contentLeft, 320),
                ("camera.aperture", lens, F.contentLeft + 340, 340),
                ("timer", exposure, F.contentLeft + 700, 260)
            ]
            for (symbol, text, x, width) in cells where !text.isEmpty {
                drawMetadataRow(symbol, text: text, x: x, centerY: layout.exifCenterY,
                                textWidth: width - F.exifSymbolSize - 10, fontSize: F.exifFontSize,
                                symbolSize: F.exifSymbolSize, textGap: 10, color: brass, context: cg)
            }
        }
    }

    /// 一文と Web の住所（右揃え）。2行の塊の縦の中心が centerY（両方の型の見出しで同じ形）
    static func drawTaglineAndAddress(centerY: CGFloat, right: CGFloat, taglineSize: CGFloat,
                                              addressColor: UIColor) {
        let taglineLine = UIFont.systemFont(ofSize: taglineSize).lineHeight
        let addressSize = ShareCardMap.Layout.siteAddressFontSize
        let addressLine = UIFont.systemFont(ofSize: addressSize).lineHeight
        let gap = ShareCardMap.Layout.taglineAddressGap
        let top = centerY - (taglineLine + gap + addressLine) / 2
        draw("旅の一瞬を、誰かの次の旅へ。", at: CGPoint(x: right - 410, y: top),
             maxWidth: 410, size: taglineSize, color: .white, alignment: .right)
        draw(ShareCardMap.Layout.siteAddress, at: CGPoint(x: right - 410, y: top + taglineLine + gap),
             maxWidth: 410, size: addressSize, color: addressColor, alignment: .right)
    }

    /// 明朝の1行。幅に入るまで 1 ずつ縮める（下限まで。最後だけ省略）
    static func drawFittedSerif(_ value: String, at origin: CGPoint, maxWidth: CGFloat,
                                        size: CGFloat, minimumSize: CGFloat, color: UIColor) {
        func serif(_ s: CGFloat) -> UIFont {
            let base = UIFont.systemFont(ofSize: s, weight: .bold)
            return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: s) } ?? base
        }
        var fitted = size
        while fitted > minimumSize,
              (value as NSString).size(withAttributes: [.font: serif(fitted)]).width > maxWidth {
            fitted -= 1
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: CGRect(x: origin.x, y: origin.y, width: maxWidth, height: fitted * 1.3),
                                 withAttributes: [.font: serif(fitted), .foregroundColor: color,
                                                  .paragraphStyle: paragraph])
    }

    /// フェード型の撮影者の行。帯の型と同じ見た目（真鍮の輪のアバター・名前・マーク・ユーザー名）を、
    /// 小さめの大きさで1行に描く。マークが3つ以上でも2段にしない（左の列に幅がある）
    static func drawFadeAuthor(_ credit: Credit, avatarData: Data?, top: CGFloat, columnWidth: CGFloat = 480, context cg: CGContext) {
        typealias F = ShareCardMap.FadeLayout
        let size = F.avatarSize
        let avatarRect = CGRect(x: F.contentLeft, y: top, width: size, height: size)
        if let avatarData, let avatar = UIImage(data: avatarData) {
            cg.saveGState()
            cg.addEllipse(in: avatarRect)
            cg.clip()
            let factor = max(size / avatar.size.width, size / avatar.size.height)
            avatar.draw(in: CGRect(x: avatarRect.midX - avatar.size.width * factor / 2,
                                   y: avatarRect.midY - avatar.size.height * factor / 2,
                                   width: avatar.size.width * factor, height: avatar.size.height * factor))
            cg.restoreGState()
        } else {
            cg.setFillColor(brass.withAlphaComponent(0.15).cgColor)
            cg.fillEllipse(in: avatarRect)
            let initial = String(credit.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
            let font = UIFont.systemFont(ofSize: 28)
            draw(initial.isEmpty ? "J" : initial,
                 at: CGPoint(x: avatarRect.minX + 18, y: avatarRect.midY - font.lineHeight / 2),
                 maxWidth: 40, size: 28, color: .white, serif: true)
        }
        cg.setStrokeColor(brass.cgColor)
        cg.setLineWidth(2)
        cg.strokeEllipse(in: avatarRect)

        let name = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let markCount = (credit.verified ? 1 : 0) + (credit.proStyle == nil ? 0 : 1)
            + (credit.early ? 1 : 0) + ((credit.badge.map { BadgeCatalog.isKnown($0.key) } ?? false) ? 1 : 0)
        let markWidth = CGFloat(markCount * 30 + (credit.proStyle == .plate ? 16 : 0))
        let x = F.contentLeft + size + 16
        let nameWidth = max(120, columnWidth - markWidth)
        let username = credit.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")) ?? ""
        let nameLine = UIFont.systemFont(ofSize: F.nameFontSize, weight: .semibold).lineHeight
        let userLine = UIFont.systemFont(ofSize: F.usernameFontSize).lineHeight
        let block = nameLine + (username.isEmpty ? 0 : userLine + 2)
        let nameY = top + (size - block) / 2
        draw(name, at: CGPoint(x: x, y: nameY), maxWidth: nameWidth, size: F.nameFontSize, color: .white, bold: true)
        if markCount > 0 {
            let nameFont = UIFont.systemFont(ofSize: F.nameFontSize, weight: .semibold)
            let actual = min(nameWidth, ceil((name as NSString).size(withAttributes: [.font: nameFont]).width))
            drawNameMarks(credit, at: CGPoint(x: x + actual + 5, y: nameY + (nameLine - 27) / 2))
        }
        if !username.isEmpty {
            draw("@" + username, at: CGPoint(x: x, y: nameY + nameLine + 2),
                 maxWidth: columnWidth, size: F.usernameFontSize, color: secondary)
        }
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

    /// 撮影地の2行。2行とも同じ大きさで、1 ずつ縮める。
    /// 下限は 15（2026-11-04）: 日本語の市区町村名は括弧つきで最長10字（「（かすみがうら市）」）まで
    /// 152 幅に切らずに入れたい（10 × 15 = 150）。撮影者名より低いのは、2行目が短い補足だから。
    static let placeFontSize: CGFloat = ShareCardMap.Layout.placeFontSize
    static let placeMinimumFontSize: CGFloat = 15
    static func placeLayout(_ lines: [String], maxWidth: CGFloat) -> ShareCardText.Fitted {
        ShareCardText.fitLines(lines, maxWidth: maxWidth, preferredSize: placeFontSize,
                               minimumSize: placeMinimumFontSize,
                               measure: { measuredWidth($0, size: $1) })
    }

    /// 撮影地の行をそのまま描く（UIKit に折り返させない）
    private static func drawPlaceLines(_ lines: [String], at origin: CGPoint, maxWidth: CGFloat,
                                       color: UIColor) {
        let fitted = placeLayout(lines, maxWidth: maxWidth)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        let font = UIFont.systemFont(ofSize: fitted.size, weight: .semibold)
        (fitted.lines.joined(separator: "\n") as NSString).draw(
            in: CGRect(x: origin.x, y: origin.y, width: maxWidth,
                       height: ShareCardMap.Layout.placeHeight),
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    /// 撮影情報の1列（記号＋字）。記号と字の塊を、行の縦の中心（centerY）にそろえる。
    ///
    /// 2026-11-04 owner 採用（地図8）: 記号は、字（1行でも2行でも）の塊の縦の中心に置く。
    /// 以前は記号を字の1行目のベースラインにそろえていたので、2行のレンズ名では記号が上に寄った。
    ///
    /// 2026-11-04 判断: UIView と Auto Layout（UILabel・UIImageView・制約）で組むのをやめた。
    /// `render` は画面の処理（メインスレッド）の外で走るので、Auto Layout を触ると
    /// 「Modifications to the layout engine must not be performed from a background thread」で落ちる。
    /// UIImage と NSString で直に描く（どちらも描画の文脈の中ならメインの外で使える）。
    /// 字は ShareCardText で語の切れ目でだけ折った行（語の途中で折らない）。
    private static func drawMetadataRow(_ symbolName: String, text: String,
                                        x: CGFloat, centerY: CGFloat,
                                        textWidth: CGFloat, fontSize: CGFloat,
                                        symbolSize: CGFloat, textGap: CGFloat,
                                        color: UIColor, context: CGContext) {
        let blockLimit = ShareCardMap.Layout.infoHeight
        let fitted = equipmentLayout(text, maxWidth: textWidth, preferredSize: fontSize,
                                     availableHeight: blockLimit)
        let font = UIFont.systemFont(ofSize: fitted.size, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1
        paragraph.lineBreakMode = .byClipping
        let lineHeight = font.lineHeight
        let blockHeight = CGFloat(fitted.lines.count) * lineHeight
            + CGFloat(max(0, fitted.lines.count - 1))
        (fitted.lines.joined(separator: "\n") as NSString).draw(
            with: CGRect(x: x + symbolSize + textGap, y: centerY - blockHeight / 2,
                         width: textWidth, height: blockHeight + 2),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph],
            context: nil)
        guard let symbol = UIImage(systemName: symbolName,
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: symbolSize,
                                                                                  weight: .regular))?
            .withTintColor(color, renderingMode: .alwaysOriginal),
              symbol.size.width > 0, symbol.size.height > 0 else { return }
        // symbolSize の正方形に縦横比を保って収め、その正方形の中心を行の中心に置く
        let scale = min(symbolSize / symbol.size.width, symbolSize / symbol.size.height)
        let drawn = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        symbol.draw(in: CGRect(x: x + (symbolSize - drawn.width) / 2,
                               y: centerY - drawn.height / 2,
                               width: drawn.width, height: drawn.height))
    }

    static func drawSymbol(_ name: String, at origin: CGPoint,
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

    /// 「Journey Photo」の字（39pt・セリフ）。draw(serif: true) と同じ作り
    static func wordmarkFont() -> UIFont {
        let base = UIFont.systemFont(ofSize: 39, weight: .regular)
        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 39) } ?? base
    }

    /// 大文字の高さの中心が markMidY に来る、字の上端。ベースライン＝上端＋ascender
    static func wordmarkTop(markMidY: CGFloat) -> CGFloat {
        let font = wordmarkFont()
        return markMidY - (font.ascender - font.capHeight / 2)
    }

    static func draw(_ value: String, at origin: CGPoint, maxWidth: CGFloat,
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
