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
        // 共有JPEGの四隅は黒背景。真鍮フレームは画像境界から8px内側にあり、
        // 線幅4pxの中心が10pxなので、(10,10)は真鍮色になる。
        // (0,0)に金色を要求すると、意図した8pxの余白を不具合と誤判定する。
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
        let frame = try pixel(at: 10, 10)
        XCTAssertGreaterThan(Int(frame[0]), 60, "8px内側の真鍮フレームが描かれていない")
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
        // 地図があるときの撮影地の幅（140）。決まった2行で、行の中では折らない（2026-11-04 owner）
        let width = ShareCardMap.Layout.placeWidthWithMap
        let cases: [(String, [String])] = [
            ("千葉県（市原市）", ["千葉県", "（市原市）"]),
            ("山中湖村, 山梨県, 日本", ["山梨県", "（山中湖村）"]),
            ("札幌市時計台, 中央区, 札幌市, 北海道, 060-0001, 日本", ["北海道", "（札幌市）"]),
            ("ヴェルサイユ, Versailles, Yvelines, イル＝ド＝フランス地域圏, フランス・メトロポリテーヌ, 78000, フランス",
             ["フランス", "（ヴェルサイユ）"]),
            ("Paris, Île-de-France, France", ["France", "(Paris)"])
        ]
        for (raw, expected) in cases {
            let lines = LocationMatch.shareCardPlace(raw)?.lines ?? []
            XCTAssertEqual(lines, expected, raw)
            let fitted = SignatureShareCardRenderer.placeLayout(lines, maxWidth: width)
            XCTAssertEqual(fitted.lines, expected, "\(raw) が切れた（大きさ \(fitted.size)）")
            XCTAssertFalse(fitted.truncated, raw)
            XCTAssertGreaterThanOrEqual(fitted.size, 26 * 0.72, "撮影者名と同じ下限")
            let font = UIFont.systemFont(ofSize: fitted.size, weight: .semibold)
            for line in fitted.lines {
                XCTAssertLessThanOrEqual((line as NSString).size(withAttributes: [.font: font]).width,
                                         width, "\(line) が 140 からはみ出す")
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
        // 甲府の北西（山梨県の中・ピンの点から 6px 以上離れた所）
        let probe = focused.projection.point(longitude: 138.4, latitude: 35.8)
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
        XCTAssertGreaterThan(filled, 120, "山梨県が塗られていない（\(probe)）")
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

}

#endif
