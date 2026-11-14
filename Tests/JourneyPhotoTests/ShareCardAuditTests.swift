import XCTest
import UIKit
import CoreLocation
@testable import JourneyPhoto

#if !os(Linux)
/// SNS 共有カードの厳しい点検（2026-11-14 owner「SNS に載せる、はちゃんとデザイン壊れてないか厳しく確認して」）。
///
/// すべての型 × すべての比 × 難しい中身（長い名前・長い撮影地・英語・絵文字・中身なし）× 写真（白・黒・パノラマ・縦長・空）で
/// **書き出した画像そのもの**を作り、画素で測る:
/// - 部品を描いた絵と、部品を描かない絵（写真・影・黒い面・額縁だけ・`ShareCardProbe.skipContent`）の画素の差＝部品の所。
///   その外枠と画像の端の距離（短い辺に対する %）が `ShareCardSafeArea` の枠に収まるか。9:16 の上 14%・下 20% に部品が無いか
/// - 字の下の背景（部品を描かない絵の、字の画素の所）の一番明るい所と字の色の明暗の比が 4.5:1 以上か。地図の線は 3:1 以上
/// - 字が切れていないか（「…」）・部品の枠が重なっていないか（記録した枠で）
/// - SNS ごとの切り取り（フィードの 4:5・3:4、プロフィールの格子の 3:4・`ShareCardSafeArea.PlatformCrop`）の内側に、
///   切り取った画像の端から 6% 以上離れて部品が残るか（2026-11-14 owner「別の SNS に投稿しようとしたら変になる、みたいなことないよね？」）
/// 数は `measured [sharecard] …`・`measured [sharecard-crop] …` の行でログに出す（Mac の `xcodebuild-full.log`）。
final class ShareCardAuditTests: XCTestCase {
    typealias R = SignatureShareCardRenderer

    // MARK: - 中身

    struct Content {
        let name: String
        let credit: R.Credit
        /// 長さの限界を試す中身（字が「…」で切れるのは設計どおりの逃げ）。それ以外は切れてはいけない
        let allowsTruncation: Bool
    }

    static let kyoto = CLLocationCoordinate2D(latitude: 35.0, longitude: 135.5)
    static let paris = CLLocationCoordinate2D(latitude: 49.0, longitude: 2.5)

    static let contents: [Content] = [
        Content(name: "ふつう", credit: R.Credit(
            name: "旅灯", username: "tabi_akari", location: "京都府（京都市東山区）", coords: kyoto,
            camera: "Sony α7 IV", lens: "FE 24-70mm F2.8 GM II", exposure: "1/250s", aperture: "f/8", iso: 100,
            verified: true, proStyle: nil, early: false, badge: nil), allowsTruncation: false),
        Content(name: "長い", credit: R.Credit(
            name: "写真と旅とコーヒーを愛する週末フォトグラファー山田太郎", username: "weekend_photographer_yamada_taro",
            location: "和歌山県（東牟婁郡那智勝浦町）", coords: kyoto,
            camera: "Hasselblad X2D II 100C Earth Explorer", lens: "XCD 2,8-4/35-100E Zoom Lens Ultra Wide",
            exposure: "1/4000s", aperture: "f/2.8", iso: 12800,
            verified: true, proStyle: .plate, early: true, badge: nil), allowsTruncation: true),
        Content(name: "英語", credit: R.Credit(
            name: "Emily Carter", username: "emily.travels", location: "Saint-Germain-en-Laye, Île-de-France, France",
            coords: paris, camera: "FUJIFILM X100VI", lens: "23mm F2", exposure: "1/500s", aperture: "f/5.6", iso: 160,
            verified: false, proStyle: nil, early: false, badge: nil), allowsTruncation: false),
        Content(name: "絵文字", credit: R.Credit(
            name: "🌸さくら🌸旅人📷", username: "sakura_tabi", location: "東京都（台東区）", coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil), allowsTruncation: false),
        Content(name: "中身なし", credit: R.Credit(
            name: "J", username: nil, location: nil, coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil), allowsTruncation: false)
    ]

    // MARK: - 写真

    static func photo(_ kind: String) -> Data {
        let size: CGSize
        switch kind {
        case "パノラマ": size = CGSize(width: 4000, height: 1000)
        case "縦長": size = CGSize(width: 1000, height: 2400)
        default: size = CGSize(width: 1600, height: 1200)
        }
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.95) { context in
            let cg = context.cgContext
            switch kind {
            case "白": UIColor.white.setFill(); cg.fill(CGRect(origin: .zero, size: size))
            case "黒": UIColor.black.setFill(); cg.fill(CGRect(origin: .zero, size: size))
            default:
                // 明るい空 → 白い雲 → 明るい地面（明るい写真の典型。字の下が明るくなりやすい）
                let colors = [UIColor(red: 0.62, green: 0.80, blue: 0.98, alpha: 1).cgColor,
                              UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1).cgColor,
                              UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 1).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                             locations: [0, 0.55, 1]) {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                }
            }
        }
    }

    // MARK: - 測る

    struct Bitmap {
        let width: Int, height: Int
        let pixels: [UInt8]
        init?(_ data: Data) {
            guard let image = UIImage(data: data)?.cgImage else { return nil }
            let w = image.width, h = image.height
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data: raw.baseAddress, width: w, height: h,
                                              bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            width = w; height = h
            pixels = buffer
        }
    }

    struct Measure {
        var box: CGRect?
        var unsafePixels = 0
        var unsafeBox: CGRect?
        var minTextContrast = Double.infinity
        var minTextItem = ""
        var minMapContrast = Double.infinity  // 地図・印（部品）
        var truncated: [String] = []
        /// 明暗の比が 7 を下回った部品（名前:比）。直す所を数で見るため
        var lowContrast: [String] = []
        var overlaps: [String] = []
        var items: [ShareCardProbe.Item] = []
    }

    /// 1つの組み合わせを書き出して測る
    func measure(_ photo: Data, credit: R.Credit, ratio: R.Ratio, style: R.Style) async throws -> (Measure, Data) {
        let probe = ShareCardProbe(skipContent: false)
        let full = await ShareCardProbe.$current.withValue(probe) {
            await R.render(photo, credit: credit, ratio: ratio, style: style)
        }
        let bare = await ShareCardProbe.$current.withValue(ShareCardProbe(skipContent: true)) {
            await R.render(photo, credit: credit, ratio: ratio, style: style)
        }
        let fullData = try XCTUnwrap(full), bareData = try XCTUnwrap(bare)
        let a = try XCTUnwrap(Bitmap(fullData)), b = try XCTUnwrap(Bitmap(bareData))
        XCTAssertEqual(a.width, b.width); XCTAssertEqual(a.height, b.height)
        let width = a.width, height = a.height
        let safe = ShareCardSafeArea.rect(ratio: ratio, width: CGFloat(width))
        // 部品の所（JPEG のにじみを拾わないよう、どれかの色で 48 以上の差）
        var mask = [Bool](repeating: false, count: width * height)
        var minX = width, minY = height, maxX = -1, maxY = -1
        var uMinX = width, uMinY = height, uMaxX = -1, uMaxY = -1
        var m = Measure()
        a.pixels.withUnsafeBufferPointer { pa in
            b.pixels.withUnsafeBufferPointer { pb in
                for y in 0..<height {
                    let inY = CGFloat(y) >= safe.minY && CGFloat(y) < safe.maxY
                    for x in 0..<width {
                        let i = (y * width + x) * 4
                        let d = max(abs(Int(pa[i]) - Int(pb[i])), abs(Int(pa[i + 1]) - Int(pb[i + 1])),
                                    abs(Int(pa[i + 2]) - Int(pb[i + 2])))
                        guard d >= 48 else { continue }
                        mask[y * width + x] = true
                        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                        if !(inY && CGFloat(x) >= safe.minX && CGFloat(x) < safe.maxX) {
                            m.unsafePixels += 1
                            uMinX = min(uMinX, x); uMaxX = max(uMaxX, x); uMinY = min(uMinY, y); uMaxY = max(uMaxY, y)
                        }
                    }
                }
            }
        }
        if maxX >= 0 { m.box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1) }
        if uMaxX >= 0 { m.unsafeBox = CGRect(x: uMinX, y: uMinY, width: uMaxX - uMinX + 1, height: uMaxY - uMinY + 1) }

        // 明暗の比: 部品の画素の所の背景（部品を描かない絵）の一番明るい所と、部品の色
        func backdropMaxLuminance(_ rect: CGRect) -> Double? {
            let x0 = max(0, Int(rect.minX.rounded(.down))), x1 = min(width, Int(rect.maxX.rounded(.up)))
            let y0 = max(0, Int(rect.minY.rounded(.down))), y1 = min(height, Int(rect.maxY.rounded(.up)))
            guard x0 < x1, y0 < y1 else { return nil }
            var best: Double?
            for y in y0..<y1 {
                for x in x0..<x1 where mask[y * width + x] {
                    let i = (y * width + x) * 4
                    let l = ShareCardSafeArea.luminance(red: Double(b.pixels[i]), green: Double(b.pixels[i + 1]),
                                                        blue: Double(b.pixels[i + 2]))
                    best = max(best ?? 0, l)
                }
            }
            return best
        }
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, al: CGFloat = 0
            color.getRed(&r, green: &g, blue: &bl, alpha: &al)
            return ShareCardSafeArea.luminance(red: Double(r * 255), green: Double(g * 255), blue: Double(bl * 255))
        }
        m.items = probe.items
        for item in probe.items {
            switch item.kind {
            case .text:
                guard let bg = backdropMaxLuminance(item.rect) else { continue }
                let c = ShareCardSafeArea.contrast(luminance(item.color), bg)
                if c < m.minTextContrast { m.minTextContrast = c; m.minTextItem = item.text }
                if c < 7 { m.lowContrast.append("\(item.text.prefix(10))@\(Int(item.rect.minY)):\(String(format: "%.2f", c))") }
                if item.truncated { m.truncated.append(item.text) }
            case .logo:
                guard let bg = backdropMaxLuminance(item.rect) else { continue }
                let c = ShareCardSafeArea.contrast(luminance(item.color), bg)
                if c < m.minTextContrast { m.minTextContrast = c; m.minTextItem = "ロゴ" }
            case .map, .symbol, .marks:
                if let bg = backdropMaxLuminance(item.rect) {
                    let c = ShareCardSafeArea.contrast(luminance(item.color), bg)
                    m.minMapContrast = min(m.minMapContrast, c)
                    if c < 4 { m.lowContrast.append("\(item.kind.rawValue)@\(Int(item.rect.minY)):\(String(format: "%.2f", c))") }
                }
            default: break
            }
        }
        // 重なり（記録した枠どうし。1px は丸めの誤差として見ない）
        let boxes = probe.items
        for i in boxes.indices {
            for j in boxes.indices where j > i {
                // アバターの中の頭文字（写真の無いときの代わり）は重なりではない
                let pair = [boxes[i], boxes[j]]
                if let avatar = pair.first(where: { $0.kind == .avatar }),
                   let other = pair.first(where: { $0.kind != .avatar }),
                   avatar.rect.insetBy(dx: -1, dy: -1).contains(other.rect) { continue }
                let overlap = boxes[i].rect.insetBy(dx: 1, dy: 1).intersection(boxes[j].rect.insetBy(dx: 1, dy: 1))
                if !overlap.isNull, overlap.width > 0, overlap.height > 0 {
                    m.overlaps.append("\(boxes[i].kind.rawValue):\(boxes[i].text.prefix(12))×\(boxes[j].kind.rawValue):\(boxes[j].text.prefix(12))")
                }
            }
        }
        return (m, fullData)
    }

    static func percent(_ value: CGFloat) -> String { String(format: "%.2f%%", Double(value * 100)) }

    // MARK: - 全部の組み合わせ

    /// 1つの型 × 比を、全部の中身 × 写真で測る。Xcode の試験は1本 1 分で打ち切られる
    /// （run 1287: 全部を1本にしたら 164 件目で止まった）ので、型 × 比ごとに1本にする
    func audit(_ style: R.Style, _ ratio: R.Ratio) async throws {
        var cases: [(String, R.Credit, Bool, String)] = []
        for content in Self.contents {
            for photo in ["白", "黒"] { cases.append((content.name, content.credit, content.allowsTruncation, photo)) }
        }
        let typical = Self.contents[0]
        for photo in ["パノラマ", "縦長", "空"] { cases.append((typical.name, typical.credit, false, photo)) }
        var photos: [String: Data] = [:]
        var failures: [String] = []
        var count = 0
        do {
            do {
                for (contentName, credit, allowsTruncation, photoName) in cases {
                    let photo = photos[photoName] ?? Self.photo(photoName)
                    photos[photoName] = photo
                    let (m, _) = try await measure(photo, credit: credit, ratio: ratio, style: style)
                    count += 1
                    let width: CGFloat = 1080, height = 1080 / CGFloat(ratio.rawValue)
                    let label = "\(style.rawValue) \(ratio) \(contentName) \(photoName)"
                    let edges = m.box.map { ShareCardSafeArea.edgeDistances(of: $0, width: width, height: height) } ?? []
                    let edgeText = edges.map(Self.percent).joined(separator: " ")
                    print("measured [sharecard] \(label) edges(L T R B)=\(edgeText) unsafePx=\(m.unsafePixels)"
                          + " unsafeBox=\(m.unsafeBox.map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.maxX)),\(Int($0.maxY))" } ?? "-")"
                          + " textContrast=\(String(format: "%.2f", m.minTextContrast))(\(m.minTextItem.prefix(16)))"
                          + " mapContrast=\(String(format: "%.2f", m.minMapContrast))"
                          + " truncated=\(m.truncated.map { String($0.prefix(16)) })"
                          + " overlaps=\(m.overlaps) low=\(m.lowContrast)")
                    // SNS ごとの切り取り（2026-11-14 判断・`ShareCardSafeArea.PlatformCrop`）。部品の外枠が、切り取った画像の端から
                    // その短い辺の 6% 以上内側にあるか。フィードは投稿そのものなので落とす。格子（小さな見本）は数を出すだけ
                    if let box = m.box {
                        for crop in ShareCardSafeArea.PlatformCrop.allCases {
                            guard let cropRect = crop.rect(width: width, height: height) else { continue }
                            let margin = min(cropRect.width, cropRect.height) * ShareCardSafeArea.edgeFraction
                            let gaps = [box.minX - cropRect.minX, box.minY - cropRect.minY,
                                        cropRect.maxX - box.maxX, cropRect.maxY - box.maxY]
                            let worst = gaps.min() ?? 0
                            let verdict = worst < 0 ? "切れる" : (worst < margin - 0.5 ? "端に近い" : "内側")
                            print("measured [sharecard-crop] \(label) \(crop.rawValue) gaps(L T R B)="
                                  + gaps.map { String(format: "%.0f", Double($0)) }.joined(separator: " ")
                                  + " margin=\(String(format: "%.1f", Double(margin))) \(verdict)")
                            if crop.mustKeepText, worst < margin - 0.5 {
                                failures.append("\(label): \(crop.rawValue) の切り取りで部品が\(verdict)（端からの距離 L T R B "
                                                + gaps.map { String(format: "%.0f", Double($0)) }.joined(separator: " ") + "px）")
                            }
                        }
                    }
                    if m.unsafePixels > 0 {
                        failures.append("\(label): 安全域の外に部品 \(m.unsafePixels)px（端からの距離 \(edgeText)）")
                    }
                    if m.minTextContrast < ShareCardSafeArea.minimumTextContrast {
                        failures.append("\(label): 字の明暗の比 \(String(format: "%.2f", m.minTextContrast))（\(m.minTextItem.prefix(16))）")
                    }
                    if m.minMapContrast < ShareCardSafeArea.minimumGraphicContrast {
                        failures.append("\(label): 地図の線の明暗の比 \(String(format: "%.2f", m.minMapContrast))")
                    }
                    if !allowsTruncation, !m.truncated.isEmpty {
                        failures.append("\(label): 字が切れた \(m.truncated.map { String($0.prefix(16)) })")
                    }
                    if !m.overlaps.isEmpty {
                        failures.append("\(label): 部品が重なった \(m.overlaps)")
                    }
                }
            }
        }
        print("measured [sharecard] \(style.rawValue) \(ratio) 組み合わせ \(count) 件 崩れ \(failures.count) 件")
        XCTAssertTrue(failures.isEmpty, "共有カードの崩れ \(failures.count) 件 / \(count) 件:\n" + failures.joined(separator: "\n"))
    }

    /// 全部の型が下の試験に並んでいるか（型を足したら試験も足す）
    func testEveryStyleHasAnAudit() {
        XCTAssertEqual(R.Style.allCases.count, 7)
    }

    func testBandPortrait() async throws { try await audit(.band, .portrait) }
    func testBandStory() async throws { try await audit(.band, .story) }
    func testBandSquare() async throws { try await audit(.band, .square) }
    func testFadePortrait() async throws { try await audit(.fade, .portrait) }
    func testFadeStory() async throws { try await audit(.fade, .story) }
    func testFadeSquare() async throws { try await audit(.fade, .square) }
    func testLabelPortrait() async throws { try await audit(.label, .portrait) }
    func testLabelStory() async throws { try await audit(.label, .story) }
    func testLabelSquare() async throws { try await audit(.label, .square) }
    func testCoverPortrait() async throws { try await audit(.cover, .portrait) }
    func testCoverStory() async throws { try await audit(.cover, .story) }
    func testCoverSquare() async throws { try await audit(.cover, .square) }
    func testPrintedPortrait() async throws { try await audit(.printed, .portrait) }
    func testPrintedStory() async throws { try await audit(.printed, .story) }
    func testPrintedSquare() async throws { try await audit(.printed, .square) }
    func testTicketPortrait() async throws { try await audit(.ticket, .portrait) }
    func testTicketStory() async throws { try await audit(.ticket, .story) }
    func testTicketSquare() async throws { try await audit(.ticket, .square) }
    func testCinemaPortrait() async throws { try await audit(.cinema, .portrait) }
    func testCinemaStory() async throws { try await audit(.cinema, .story) }
    func testCinemaSquare() async throws { try await audit(.cinema, .square) }
}
#endif
