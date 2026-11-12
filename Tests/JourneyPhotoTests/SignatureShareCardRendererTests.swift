import XCTest
import UIKit
import ImageIO
import CoreLocation
@testable import JourneyPhoto

#if !os(Linux)
final class SignatureShareCardRendererTests: XCTestCase {
    func testPortraitCardRendersExpectedDimensionsAndRemovesMetadata() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).jpegData(
            withCompressionQuality: 0.95) { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: "photographer", location: "Kyoto",
            coords: nil, camera: "Camera", lens: "35mm", exposure: "1/125s",
            aperture: "f/2", iso: 100, verified: false, proStyle: nil,
            early: false, badge: nil)
        let result = await SignatureShareCardRenderer.render(source, credit: credit)
        let data = try XCTUnwrap(result)
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.size.width, 1080)
        XCTAssertEqual(image.size.height, 1350)
        // JPEGの画素を書き直しており、元のGPS/EXIFを受け渡さない。
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        let properties = imageSource.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }
        XCTAssertNil(properties?[kCGImagePropertyGPSDictionary as String])
    }

    func testExportedCardBorderReachesImageCorners() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
            .jpegData(withCompressionQuality: 0.95) { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Creator", username: nil, location: nil, coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil)
        let rendered = await SignatureShareCardRenderer.render(source, credit: credit)
        let data = try XCTUnwrap(rendered)
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.size, CGSize(width: 1080, height: 1350))
        // 共有JPEGの四隅は黒背景。真鍮フレームは画像境界から12px内側にあり（2026-11-04 地図8）、
        // 線幅3pxの中心が13.5pxなので、(13,13)は真鍮色になる。
        // (0,0)に金色を要求すると、意図した12pxの余白を不具合と誤判定する。
        let bitmap = try XCTUnwrap(image.cgImage)
        func pixel(at x: Int, _ y: Int) throws -> [UInt8] {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var rgba = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(
                data: &rgba, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let cropped = try XCTUnwrap(bitmap.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return rgba
        }
        let corner = try pixel(at: 0, 0)
        XCTAssertLessThan(Int(corner[0]), 30, "画像の四隅は黒い背景で統一する")
        let frame = try pixel(at: 13, 13)
        XCTAssertGreaterThan(Int(frame[0]), 60, "12px内側の真鍮フレームが描かれていない")
    }

    func testSquareCardRenders() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).jpegData(
            withCompressionQuality: 0.9) { context in
                UIColor.gray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Creator", username: nil, location: nil, coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil, verified: false, proStyle: nil,
            early: false, badge: nil)
        let result = await SignatureShareCardRenderer.render(source, credit: credit, ratio: .square)
        XCTAssertEqual(UIImage(data: try XCTUnwrap(result))?.size, CGSize(width: 1080, height: 1080))
    }
    func testStoryCardRendersExpectedDimensions() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Long Photographer Name", username: "journey_photo",
            location: "Florence, Italy", coords: nil,
            camera: "Hasselblad X2D II 100C", lens: "XCD 35-100mm f/2.8-4 E",
            exposure: "1/125s", aperture: "f/4", iso: 200, verified: false, proStyle: nil,
            early: false, badge: nil)
        let result = await SignatureShareCardRenderer.render(
            source, credit: credit, ratio: .story)
        let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(result)))
        XCTAssertEqual(image.size, CGSize(width: 1080, height: 1920))
    }

    func testWideLandscapePhotoCanBeExportedInAllRatios() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1800, height: 650))
            .jpegData(withCompressionQuality: 0.85) { context in
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1800, height: 650))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: "photo", location: "Venice",
            coords: nil, camera: nil, lens: nil, exposure: nil,
            aperture: nil, iso: nil, verified: false, proStyle: nil,
            early: false, badge: nil)
        for (ratio, height) in [
            (SignatureShareCardRenderer.Ratio.portrait, CGFloat(1350)),
            (.story, CGFloat(1920)),
            (.square, CGFloat(1080))
        ] {
            let rendered = await SignatureShareCardRenderer.render(
                source, credit: credit, ratio: ratio)
            let data = try XCTUnwrap(rendered)
            XCTAssertEqual(UIImage(data: data)?.size,
                           CGSize(width: 1080, height: height))
        }
    }

    func testLongCameraLensAndVisibleMarksRenderForAllRatios() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.darkGray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: "journey",
            location: "月崎, 大多喜里見線, 市原市, 千葉県",
            coords: CLLocationCoordinate2D(latitude: 35.34, longitude: 140.14),
            camera: "Hasselblad X2D II 100C Medium Format Camera",
            lens: "Hasselblad XCD 35-100E f/2.8-4 Zoom Lens",
            exposure: "1/125s", aperture: "f/4.8", iso: 200,
            verified: true, proStyle: .iris, early: true, badge: nil)
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let result = await SignatureShareCardRenderer.render(source, credit: credit, ratio: ratio)
            let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(result)))
            XCTAssertEqual(image.size.width, 1080)
        }
    }

    func testLongEquipmentNamesWrapOnlyBetweenWords() {
        // 2026-11-04 owner「文章の変な改行はいやです」: 機材名は語の途中で折らない
        let camera = "Hasselblad X2D II 100C Medium Format Camera"
        let lens = "Hasselblad XCD 35-100E f/2.8-4 Zoom Lens"
        // 「/」の後ろでは折らない（「f/｜2.8」にしない・2026-11-04 確かめ役の指摘）
        let nikkor = "NIKKOR Z 24-70mm f/2.8 S"
        for (name, width) in [(camera, CGFloat(235)), (lens, CGFloat(246)), (nikkor, CGFloat(120))] {
            let fitted = SignatureShareCardRenderer.equipmentLayout(name, maxWidth: width)
            XCTAssertLessThanOrEqual(fitted.size, 22)
            XCTAssertFalse(fitted.truncated, "\(name) は全文が入る")
            // 行をつなぐと元の語の並びに戻る＝語の途中で切っていない
            XCTAssertEqual(fitted.lines.joined(separator: " ").split(separator: " "),
                           name.split(separator: " "), "\(name): \(fitted.lines)")
            let font = UIFont.systemFont(ofSize: fitted.size, weight: .semibold)
            for line in fitted.lines {
                XCTAssertLessThanOrEqual((line as NSString).size(withAttributes: [.font: font]).width,
                                         width, "\(line) が列からはみ出す")
            }
            let height = CGFloat(fitted.lines.count) * font.lineHeight + CGFloat(fitted.lines.count - 1)
            XCTAssertLessThanOrEqual(height, 72.5, "\(name) must fit without clipping")
        }
    }

    func testPlaceTwoLinesWithRealFont() {
        // 地図があるときの撮影地の幅（152）。決まった2行で、行の中では折らない（2026-11-04 owner）
        let width = ShareCardMap.Layout.placeWidthWithMap
        let cases: [(String, [String])] = [
            ("千葉県（市原市）", ["千葉県", "（市原市）"]),
            ("山中湖村, 山梨県, 日本", ["山梨県", "（山中湖村）"]),
            ("札幌市時計台, 中央区, 札幌市, 北海道, 060-0001, 日本", ["北海道", "（札幌市）"]),
            ("ヴェルサイユ, Versailles, Yvelines, イル＝ド＝フランス地域圏, フランス・メトロポリテーヌ, 78000, フランス",
             ["フランス", "（ヴェルサイユ）"]),
            ("Paris, Île-de-France, France", ["France", "(Paris)"]),
            // 括弧つき最長の市区町村名（10字）も切らない（下限 15 で 150 ≤ 152）
            ("かすみがうら市, 茨城県, 日本", ["茨城県", "（かすみがうら市）"])
        ]
        for (raw, expected) in cases {
            let lines = LocationMatch.shareCardPlace(raw)?.lines ?? []
            XCTAssertEqual(lines, expected, raw)
            let fitted = SignatureShareCardRenderer.placeLayout(lines, maxWidth: width)
            XCTAssertEqual(fitted.lines, expected, "\(raw) が切れた（大きさ \(fitted.size)）")
            XCTAssertFalse(fitted.truncated, raw)
            XCTAssertGreaterThanOrEqual(fitted.size, SignatureShareCardRenderer.placeMinimumFontSize, "撮影地の下限")
            let font = UIFont.systemFont(ofSize: fitted.size, weight: .semibold)
            for line in fitted.lines {
                XCTAssertLessThanOrEqual((line as NSString).size(withAttributes: [.font: font]).width,
                                         width, "\(line) が \(width) からはみ出す")
            }
        }
    }

    /// 日本の長い市区町村名（全 1709 件のうち 6〜7 字の全部と、5 字の代表）を本物の字で測り、
    /// Mac の記録に出す（2026-11-04 確かめ役の指摘: 「（南アルプス市）」は 18.72pt でも 140 を超えうる）。
    /// 一覧は code4fukui/localgovjp の市区町村名から字数で選んだ
    func testMeasureLongMunicipalityNames() {
        let names = ["つくばみらい市", "いちき串木野市", "かすみがうら市", "山陽小野田市", "富士河口湖町",
                     "ひたちなか市", "南アルプス市", "東松島市", "伊豆の国市", "大和郡山市", "四国中央市",
                     "世田谷区", "山中湖村", "市原市"]
        let minimum = CGFloat(26 * 0.72)
        let semibold = UIFont.systemFont(ofSize: minimum, weight: .semibold)
        // 和文の詰め（palt: kTextSpacingType=22・kAltProportionalTextSelector=5）
        let paltDescriptor = semibold.fontDescriptor.addingAttributes([
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: 22,
                                UIFontDescriptor.FeatureKey.selector: 5]]
        ])
        let palt = UIFont(descriptor: paltDescriptor, size: minimum)
        for name in names {
            let line = "（\(name)）"
            let plain = (line as NSString).size(withAttributes: [.font: semibold]).width
            let packed = (line as NSString).size(withAttributes: [.font: palt]).width
            print("SHARECARD-MEASURE \(line) plain=\(String(format: "%.1f", plain)) palt=\(String(format: "%.1f", packed)) fitSize140=\(String(format: "%.2f", 140 / plain * minimum))")
        }
        for character in ["（", "）", "あ", "市"] {
            let plain = (character as NSString).size(withAttributes: [.font: semibold]).width
            let packed = (character as NSString).size(withAttributes: [.font: palt]).width
            print("SHARECARD-MEASURE char \(character) plain=\(String(format: "%.2f", plain)) palt=\(String(format: "%.2f", packed))")
        }
        let pin = UIImage(systemName: "mappin.circle",
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 37, weight: .regular))
        print("SHARECARD-MEASURE pin size=\(pin.map { "\($0.size)" } ?? "nil")")
        XCTAssertFalse(names.isEmpty)
    }

    /// 2026-11-05 フェード型: 3 比率とも大きさが正しく、写真は全面・下は黒へ溶け、地図の線（真鍮）が出る
    func testFadeStyleRendersAllRatios() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1200))
            .jpegData(withCompressionQuality: 0.95) { context in
                UIColor(red: 0.5, green: 0.7, blue: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1200))
            }
        let pin = try XCTUnwrap(SignatureShareCardRenderer.approximateShareCoordinate(
            Photo.Coords(lat: 35.41, lng: 138.86)))
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: "photographer", location: "山梨県（山中湖村）", coords: pin,
            camera: "Hasselblad X2D II 100C", lens: "XCD 35-100E", exposure: "1/100s",
            aperture: "f/4", iso: 50, verified: false, proStyle: nil, early: false, badge: nil)
        func rgb(_ image: CGImage, _ x: Int, _ y: Int) throws -> [Int] {
            var rgba = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let cropped = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return rgba.prefix(3).map(Int.init)
        }
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.FadeLayout(ratio: ratio)
            // `XCTUnwrap` の引数は autoclosure で `await` が使えないので、先に待つ
            let rendered = await SignatureShareCardRenderer.render(
                source, credit: credit, ratio: ratio, style: .fade)
            let data = try XCTUnwrap(rendered)
            let image = try XCTUnwrap(UIImage(data: data))
            let attachment = XCTAttachment(image: image)
            attachment.name = "フェード_\(ratio)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(image.size, CGSize(width: 1080, height: layout.height), "\(ratio)")
            let bitmap = try XCTUnwrap(image.cgImage)
            // 写真は全面: グラデーションの上・ロゴの影の下（真ん中の左端）は元の写真の色のまま（青い）
            let mid = try rgb(bitmap, 30, Int((layout.fadeTop + 260) / 2))
            XCTAssertGreaterThan(mid[2], mid[0] + 40, "\(ratio) 写真の青が残っていない \(mid)")
            XCTAssertGreaterThan(mid[2], 150, "\(ratio) 写真が暗くなっている \(mid)")
            // 下は黒へ溶ける: 左下の隅（文字の無い所）は黒に近い
            let bottom = try rgb(bitmap, 6, Int(layout.height) - 6)
            XCTAssertLessThan(bottom.max() ?? 255, 24, "\(ratio) 下が黒に着いていない \(bottom)")
            // 写真の上に真鍮の額縁を載せない（左上の隅 (13,13) は写真の色）
            let corner = try rgb(bitmap, 13, 300)
            XCTAssertGreaterThan(corner[2], 120, "\(ratio) 左の端に額縁が載っている \(corner)")
            // 地図の枠の中に、真鍮の線（赤が青より明るい色）がある
            let map = layout.mapRect
            var brassPixels = 0
            for yy in stride(from: Int(map.minY), to: Int(map.maxY), by: 4) {
                for xx in stride(from: Int(map.minX), to: Int(map.maxX), by: 4) {
                    let p = try rgb(bitmap, xx, yy)
                    if p[0] > 150, p[0] > p[2] + 40 { brassPixels += 1 }
                }
            }
            XCTAssertGreaterThan(brassPixels, 20, "\(ratio) 地図の線が見えない（\(brassPixels)）")
        }
    }

    /// 2026-11-06 展示札・表紙: 3 比率とも大きさが正しく、写真が出て、黒い面があり、地図の線（真鍮）が出る
    func testNewStylesRenderAllRatios() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1200))
            .jpegData(withCompressionQuality: 0.95) { context in
                UIColor(red: 0.5, green: 0.7, blue: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1200))
            }
        let pin = try XCTUnwrap(SignatureShareCardRenderer.approximateShareCoordinate(
            Photo.Coords(lat: 35.41, lng: 138.86)))
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: "photographer", location: "山梨県（山中湖村）", coords: pin,
            camera: "Hasselblad X2D II 100C", lens: "XCD 35-100E", exposure: "1/100s",
            aperture: "f/4", iso: 50, verified: false, proStyle: nil, early: false, badge: nil)
        func rgb(_ image: CGImage, _ x: Int, _ y: Int) throws -> [Int] {
            var rgba = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let cropped = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return rgba.prefix(3).map(Int.init)
        }
        func isPhotoBlue(_ p: [Int]) -> Bool { p[2] > 150 && p[2] > p[0] + 40 }
        func isDark(_ p: [Int]) -> Bool { (p.max() ?? 255) < 40 }
        func brassCount(_ image: CGImage, in rect: CGRect) throws -> Int {
            var n = 0
            for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 4) {
                for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 4) {
                    let p = try rgb(image, x, y)
                    if p[0] > 150, p[0] > p[2] + 40 { n += 1 }
                }
            }
            return n
        }
        for style in [SignatureShareCardRenderer.Style.label, .cover] {
            for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
                let rendered = await SignatureShareCardRenderer.render(
                    source, credit: credit, ratio: ratio, style: style)
                let data = try XCTUnwrap(rendered)
                let image = try XCTUnwrap(UIImage(data: data))
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(style.rawValue)_\(ratio)"
                attachment.lifetime = .keepAlways
                add(attachment)
                let name = "\(style.rawValue) \(ratio)"
                let bitmap = try XCTUnwrap(image.cgImage)
                let height = Int(image.size.height)
                XCTAssertEqual(image.size.width, 1080, name)
                XCTAssertEqual(image.size.height, 1080 / CGFloat(ratio.rawValue), name)
                switch style {
                case .label:
                    let layout = ShareCardMap.LabelLayout(ratio: ratio)
                    XCTAssertTrue(isPhotoBlue(try rgb(bitmap, 540, Int(layout.photoBottom) - 100)), name)
                    XCTAssertTrue(isDark(try rgb(bitmap, 6, height - 6)), name)
                    // 写真の下（札）は黒い面
                    XCTAssertTrue(isDark(try rgb(bitmap, 600, Int(layout.photoBottom) + 20)), "\(name) 札が黒くない")
                    XCTAssertGreaterThan(try brassCount(bitmap, in: layout.mapRect), 20, "\(name) 地図の線が見えない")
                case .cover:
                    let layout = ShareCardMap.CoverLayout(ratio: ratio)
                    // 写真は全面（左の端まで・額縁なし）。下は黒へ溶ける
                    XCTAssertTrue(isPhotoBlue(try rgb(bitmap, 13, Int(layout.fadeTop) / 2 + 100)), "\(name) 左の端が写真でない")
                    XCTAssertTrue(isDark(try rgb(bitmap, 6, height - 6)), name)
                    XCTAssertTrue(isDark(try rgb(bitmap, 300, Int(layout.photoBottom) + 6)), "\(name) 写真の下端が黒くない")
                    XCTAssertGreaterThan(try brassCount(bitmap, in: layout.mapRect), 20, "\(name) 地図の線が見えない")
                default: break
                }
            }
        }
    }

    /// 日本の写真は、撮影地の文字の県を真鍮 75% で塗る（案A-3）。海外の写真・県名の無い文字は塗らない
    func testJapanCardFillsPrefectureNamedInPlace() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
            .jpegData(withCompressionQuality: 0.95) { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
        let pin = try XCTUnwrap(SignatureShareCardRenderer.approximateShareCoordinate(
            Photo.Coords(lat: 35.41, lng: 138.86)))   // 山中湖 → 35.5, 139.0
        func card(_ place: String) async throws -> CGImage {
            let credit = SignatureShareCardRenderer.Credit(
                name: "Photographer", username: "photographer", location: place, coords: pin,
                camera: "Hasselblad X2D II 100C", lens: "XCD 35-100E", exposure: "1/100s",
                aperture: "f/4", iso: 50, verified: false, proStyle: nil, early: false, badge: nil)
            let rendered = await SignatureShareCardRenderer.render(source, credit: credit)
            let data = try XCTUnwrap(rendered)
            let image = try XCTUnwrap(UIImage(data: data))
            let attachment = XCTAttachment(image: image)
            attachment.name = "共有カード_\(place)"
            attachment.lifetime = .keepAlways
            add(attachment)
            return try XCTUnwrap(image.cgImage)
        }
        let japan = try XCTUnwrap(ShareCardMap.loadShapes(resource: "country-outlines")
            .first(where: { $0.n == "Japan" }))
        let rect = ShareCardMap.Layout(ratio: .portrait).mapRect
        let focused = try XCTUnwrap(ShareCardMap.focus(japan, latitude: pin.latitude,
                                                       longitude: pin.longitude, in: rect))
        // 山梨県の中で、ピンの点から最も離れた所（点の半径 6 の外・光の輪の半径 14 の内側）。
        // 2026-11-04: 地図が黒い帯の中（200×146）になり縮尺が小さくなったので、固定の座標でなく、
        // 山梨県の輪の中の点を 0.05° 刻みで探し、ピンからの距離が最大の点を選ぶ
        let yamanashi = try XCTUnwrap(ShareCardMap.loadShapes(resource: "japan-prefectures")
            .first(where: { $0.n == "山梨県" }))
        let pinPoint = focused.projection.point(longitude: pin.longitude, latitude: pin.latitude)
        var found: CGPoint?
        var foundDistance: CGFloat = 0
        for latStep in 0..<30 {
            for lonStep in 0..<30 {
                let lon = 138.1 + Double(lonStep) * 0.05, lat = 35.2 + Double(latStep) * 0.05
                guard yamanashi.r.contains(where: { ShareCardMap.ringContains($0, longitude: lon, latitude: lat) }) else { continue }
                let candidate = focused.projection.point(longitude: lon, latitude: lat)
                let distance = hypot(candidate.x - pinPoint.x, candidate.y - pinPoint.y)
                if distance > foundDistance, distance <= 13.5 { found = candidate; foundDistance = distance }
            }
        }
        XCTAssertGreaterThanOrEqual(foundDistance, 6.6, "山梨県の中に、点（半径 6）の外の所が無い（地図の縮尺を確かめる）")
        let probe = try XCTUnwrap(found)
        func red(_ image: CGImage) throws -> Int {
            var rgba = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let cropped = try XCTUnwrap(image.cropping(to: CGRect(x: Int(probe.x), y: Int(probe.y),
                                                                  width: 1, height: 1)))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return Int(rgba[0])
        }
        let filledCard = try await card("山梨県（山中湖村）")
        let plainCard = try await card("Mount Fuji")
        let filled = try red(filledCard)
        let plain = try red(plainCard)
        // 県の端に近い点を見るので、縁の薄まり（アンチエイリアス）を見込んで、塗りあり／なしの差で比べる
        // （2026-11-04 Mac の実測: 塗りあり 96・塗りなしは光の輪だけで 60 未満）
        XCTAssertGreaterThan(filled, plain + 30, "山梨県が塗られていない（塗りあり \(filled)・なし \(plain)・\(probe)）")
        XCTAssertLessThan(plain, 60, "県名が無いのに塗っている")
    }

    func testOverseasCardRenders() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
            .jpegData(withCompressionQuality: 0.95) { context in
                UIColor.darkGray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: "photographer",
            location: "Versailles, Île-de-France, フランス",
            coords: CLLocationCoordinate2D(latitude: 49.0, longitude: 2.0),
            camera: "Hasselblad X2D II 100C Medium Format Camera",
            lens: "Hasselblad XCD 35-100E f/2.8-4 Zoom Lens",
            exposure: "1/125s", aperture: "f/4", iso: 200,
            verified: false, proStyle: nil, early: false, badge: nil)
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let rendered = await SignatureShareCardRenderer.render(source, credit: credit, ratio: ratio)
            let data = try XCTUnwrap(rendered)
            let image = try XCTUnwrap(UIImage(data: data))
            let attachment = XCTAttachment(image: image)
            attachment.name = "共有カード_フランス_\(ratio)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testMultiplePhotographerMarksRenderWithLongNameAcrossRatios() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.darkGray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Long Photographer Display Name", username: "long_photographer_username",
            location: "神奈川県（横浜市）", coords: nil,
            camera: "Hasselblad X2D II 100C", lens: "XCD 35-100E",
            exposure: "1/125s", aperture: "f/4", iso: 200,
            verified: true, proStyle: .plate, early: true, badge: nil)
        for (ratio, height) in [
            (SignatureShareCardRenderer.Ratio.portrait, CGFloat(1350)),
            (.square, CGFloat(1080)), (.story, CGFloat(1920))
        ] {
            let rendered = await SignatureShareCardRenderer.render(source, credit: credit, ratio: ratio)
            let data = try XCTUnwrap(rendered)
            let image = try XCTUnwrap(UIImage(data: data))
            XCTAssertEqual(image.size, CGSize(width: 1080, height: height))
        }
    }

    func testRegionalMapWithCoarsePinRendersAcrossAllRatios() async throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.gray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
        let coords = SignatureShareCardRenderer.approximateShareCoordinate(
            Photo.Coords(lat: 35.6812, lng: 139.7671))
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: "photographer",
            location: "東京都（千代田区）", coords: coords,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil)
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .square, .story] {
            let result = await SignatureShareCardRenderer.render(photo, credit: credit, ratio: ratio)
            XCTAssertNotNil(result, "Regional map must render for \\(ratio)")
        }
    }

    func testShareMapRendersCoastalAndIslandLocationsInAllRatios() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.gray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
        let locations: [(String, Double, Double)] = [
            ("Tokyo", 35.6812, 139.7671),
            ("Venice", 45.4408, 12.3155),
            ("Okinawa", 26.2124, 127.6809),
            ("Sapporo", 43.0618, 141.3545)
        ]
        for (name, latitude, longitude) in locations {
            let coords = SignatureShareCardRenderer.approximateShareCoordinate(
                Photo.Coords(lat: latitude, lng: longitude))
            let credit = SignatureShareCardRenderer.Credit(
                name: "Photographer", username: nil, location: name,
                coords: coords, camera: nil, lens: nil, exposure: nil,
                aperture: nil, iso: nil, verified: false, proStyle: nil,
                early: false, badge: nil)
            for ratio in [SignatureShareCardRenderer.Ratio.portrait, .square, .story] {
                let result = await SignatureShareCardRenderer.render(source, credit: credit, ratio: ratio)
                XCTAssertNotNil(result, "\\(name) / \\(ratio) must export")
            }
        }
    }

    func testWorldwideMapExportAcrossAllRatios() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300))
            .jpegData(withCompressionQuality: 0.8) { context in
                UIColor.gray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            }
        // Include northern/southern hemispheres, islands, coastal cities and the dateline.
        let locations: [(String, Double, Double)] = [
            ("Helsinki", 60.17, 24.94),
            ("Oslo", 59.91, 10.75),
            ("Reykjavik", 64.15, -21.94),
            ("London", 51.51, -0.13),
            ("Cairo", 30.04, 31.24),
            ("Nairobi", -1.29, 36.82),
            ("Cape Town", -33.92, 18.42),
            ("Mumbai", 19.08, 72.88),
            ("Singapore", 1.35, 103.82),
            ("Manila", 14.60, 120.98),
            ("Jakarta", -6.21, 106.85),
            ("Sydney", -33.87, 151.21),
            ("Auckland", -36.85, 174.76),
            ("Suva", -18.14, 178.44),
            ("Fiji dateline", -16.5, 179.8),
            ("Chukotka", 66.0, -179.0),
            ("New York", 40.71, -74.01),
            ("Vancouver", 49.28, -123.12),
            ("Rio de Janeiro", -22.91, -43.20),
            ("Santiago", -33.45, -70.67)
        ]
        for (name, latitude, longitude) in locations {
            let credit = SignatureShareCardRenderer.Credit(
                name: "Photographer", username: nil, location: name,
                coords: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
                verified: false, proStyle: nil, early: false, badge: nil)
            for ratio in [SignatureShareCardRenderer.Ratio.portrait, .square, .story] {
                let rendered = await SignatureShareCardRenderer.render(
                    source, credit: credit, ratio: ratio)
                let data = try XCTUnwrap(rendered, "\(name) / \(ratio) must export")
                XCTAssertNotNil(UIImage(data: data), "\(name) / \(ratio) must decode")
            }
        }
    }

    func testStoryLandscapePhotoRendersWithoutInsetComposite() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 600))
            .jpegData(withCompressionQuality: 0.95) { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Photographer", username: nil, location: nil, coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil)
        let result = await SignatureShareCardRenderer.render(source, credit: credit, ratio: .story)
        let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(result)))
        XCTAssertEqual(image.size, CGSize(width: 1080, height: 1920))
    }

    func testShareMapPinUsesCoarseCoordinateAndRejectsInvalidValues() {
        let original = Photo.Coords(lat: 35.6812, lng: 139.7671)
        let approximate = SignatureShareCardRenderer.approximateShareCoordinate(original)
        XCTAssertEqual(approximate?.latitude, 35.5)
        XCTAssertEqual(approximate?.longitude, 140.0)
        XCTAssertNil(SignatureShareCardRenderer.approximateShareCoordinate(nil))
        XCTAssertNil(SignatureShareCardRenderer.approximateShareCoordinate(
            Photo.Coords(lat: .nan, lng: 139)))
        XCTAssertNil(SignatureShareCardRenderer.approximateShareCoordinate(
            Photo.Coords(lat: 91, lng: 139)))
    }

    func testInvalidPhotoDataReturnsNil() async {
        let credit = SignatureShareCardRenderer.Credit(
            name: "Creator", username: nil, location: nil, coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil, verified: false, proStyle: nil,
            early: false, badge: nil)
        let result = await SignatureShareCardRenderer.render(
            Data("not a photo".utf8), credit: credit)
        XCTAssertNil(result)
    }

    func testAvatarImageCanBeRendered() async throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000))
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.gray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
            }
        let avatar = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
            .pngData { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            }
        let credit = SignatureShareCardRenderer.Credit(
            name: "Creator", username: "creator", location: "Tokyo",
            coords: nil, camera: nil, lens: nil, exposure: nil,
            aperture: nil, iso: nil, verified: false, proStyle: nil,
            early: false, badge: nil)
        let rendered = await SignatureShareCardRenderer.render(
            photo, credit: credit, avatarData: avatar)
        XCTAssertNotNil(UIImage(data: try XCTUnwrap(rendered)))
    }


    // MARK: - 撮影情報が無いとき（2026-11-12）

    /// 描いたカードの、ある範囲の中でいちばん明るい赤の値（線があれば真鍮で明るくなる）
    private func maxRed(_ data: Data, in rect: CGRect) throws -> Int {
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        let cropped = try XCTUnwrap(image.cropping(to: rect.integral))
        let width = cropped.width, height = cropped.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: rgba.count, by: 4).map { Int(rgba[$0]) }.max() ?? 0
    }

    /// 描いたカード（XCTUnwrap の autoclosure に await を入れられないので、いったん受けてから）
    private func renderCard(_ data: Data, credit: SignatureShareCardRenderer.Credit,
                            ratio: SignatureShareCardRenderer.Ratio,
                            style: SignatureShareCardRenderer.Style) async throws -> Data {
        let rendered = await SignatureShareCardRenderer.render(data, credit: credit, ratio: ratio, style: style)
        return try XCTUnwrap(rendered)
    }

    private func grayPhoto() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000)).jpegData(withCompressionQuality: 0.95) { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
        }
    }

    private func credit(camera: String?, lens: String?, exposure: String?) -> SignatureShareCardRenderer.Credit {
        SignatureShareCardRenderer.Credit(
            name: "Creator", username: "creator", location: nil, coords: nil,
            camera: camera, lens: lens, exposure: exposure, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil)
    }

    /// 帯の型（4:5）: 撮影情報が無ければ、下の段の区切り線と縦罫を描かない（run 1194 で縦の線だけ残っていた）。
    /// 一部だけ空なら、空の欄に掛かる縦罫を描かない。線は真鍮 45%（赤 ≈ 98）、帯の地は赤 14
    func testBandCardDrawsNoInfoLinesWithoutExif() async throws {
        typealias L = ShareCardMap.Layout
        let layout = L(ratio: .portrait)
        let separator = CGRect(x: L.contentLeft + 20, y: layout.separatorY - 2, width: 200, height: 6)
        let dividers = L.infoDividerXs.map {
            CGRect(x: $0 - 3, y: layout.infoCenterY - 15, width: 6, height: 30)
        }
        let threshold = 55

        let empty = try await renderCard(
            grayPhoto(), credit: credit(camera: nil, lens: " ", exposure: nil), ratio: .portrait, style: .band)
        XCTAssertLessThan(try maxRed(empty, in: separator), threshold, "撮影情報が無いのに区切り線を描いた")
        for (index, rect) in dividers.enumerated() {
            XCTAssertLessThan(try maxRed(empty, in: rect), threshold, "撮影情報が無いのに縦罫 \(index) を描いた")
        }

        let full = try await renderCard(
            grayPhoto(), credit: credit(camera: "Camera", lens: "35mm", exposure: "1/125s"),
            ratio: .portrait, style: .band)
        XCTAssertGreaterThan(try maxRed(full, in: separator), threshold, "撮影情報があるのに区切り線が無い")
        for (index, rect) in dividers.enumerated() {
            XCTAssertGreaterThan(try maxRed(full, in: rect), threshold, "撮影情報があるのに縦罫 \(index) が無い")
        }

        // カメラだけ: 区切り線は描き、縦罫は描かない
        let cameraOnly = try await renderCard(
            grayPhoto(), credit: credit(camera: "Camera", lens: nil, exposure: nil), ratio: .portrait, style: .band)
        XCTAssertGreaterThan(try maxRed(cameraOnly, in: separator), threshold)
        for (index, rect) in dividers.enumerated() {
            XCTAssertLessThan(try maxRed(cameraOnly, in: rect), threshold, "空の欄に縦罫 \(index) を描いた")
        }
    }

    /// 展示札の型（4:5）: 表の列の間の縦罫（真鍮 30%・赤 ≈ 60）も、両側に字があるときだけ
    func testLabelCardDrawsNoTableDividersWithoutExif() async throws {
        let layout = ShareCardMap.LabelLayout(ratio: .portrait)
        let dividers = [CGFloat(248), 456].map {
            CGRect(x: $0 - 3, y: layout.tableTop + 30, width: 6, height: 30)
        }
        let threshold = 35
        let empty = try await renderCard(
            grayPhoto(), credit: credit(camera: nil, lens: nil, exposure: nil), ratio: .portrait, style: .label)
        for (index, rect) in dividers.enumerated() {
            XCTAssertLessThan(try maxRed(empty, in: rect), threshold, "撮影情報が無いのに縦罫 \(index) を描いた")
        }
        let full = try await renderCard(
            grayPhoto(), credit: credit(camera: "Camera", lens: "35mm", exposure: "1/125s"),
            ratio: .portrait, style: .label)
        for (index, rect) in dividers.enumerated() {
            XCTAssertGreaterThan(try maxRed(full, in: rect), threshold, "撮影情報があるのに縦罫 \(index) が無い")
        }
    }

}

#endif
