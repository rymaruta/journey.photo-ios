import XCTest
import UIKit
@testable import JourneyPhoto

#if !os(Linux)
/// 旅の一冊の共有の絵（`TripBookCardRenderer`）を**実際に描いて**画素を見る（iOS の Xcode だけ）。
///
/// 🔴 2026-11-26 owner（実機の画面写真）: 下の4割が白→灰→黒の帯になり、写真が消えていた（キツネの耳の先しか
/// 見えない）。48 段の帯を `UIRectFill`（置き換えで塗る）で塗っていたため。
/// ここで固定するのは「暗くした所にも写真の色が残る」こと。前の塗り方（置き換え）では色が消えることも
/// 同じ画素で確かめ、直す前と直した後の絵を添付に残す（`Tools/fetch-shots.sh` で見る）。
/// 写真は人の写真を使わず、ここで描いた絵（空・地面・橙の丸）を使う
final class TripBookCardRendererTests: XCTestCase {

    /// 明るい写真（昼の空と雪・下の方に橙の動物の形）。4:5 なので切り抜かずに枠にそのまま入る
    private func brightPhoto() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 2000)).jpegData(withCompressionQuality: 0.95) { ctx in
            UIColor(red: 0.62, green: 0.80, blue: 0.95, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1100))
            UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 1100, width: 1600, height: 900))
            UIColor(red: 0.90, green: 0.47, blue: 0.16, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 500, y: 1300, width: 900, height: 620)).fill()
            UIBezierPath(ovalIn: CGRect(x: 640, y: 1000, width: 380, height: 380)).fill()
        }
    }

    /// 暗い写真（夜の街の灯り）
    private func darkPhoto() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1500)).jpegData(withCompressionQuality: 0.95) { ctx in
            UIColor(red: 0.04, green: 0.06, blue: 0.14, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2000, height: 1500))
            UIColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 1).setFill()
            for i in 0..<24 {
                let x = Double((i * 157) % 1900), y = 700 + Double((i * 83) % 700)
                UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 40, height: 40)).fill()
            }
        }
    }

    private func lines(place: String) throws -> TripBookCard.Lines {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"a","src":"https://x/a.jpg","location":"x"}"#.utf8))
        let start = Date(timeIntervalSince1970: 1_789_171_200)
        let trip = TripBook.Trip(id: "t", place: place, start: start, end: start.addingTimeInterval(2 * 86_400),
                                 photos: [photo, photo, photo])
        return TripBookCard.lines(of: trip, distance: 12.4)
    }

    private func rgb(_ image: UIImage, _ x: Int, _ y: Int) throws -> [Int] {
        let bitmap = try XCTUnwrap(image.cgImage)
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cropped = try XCTUnwrap(bitmap.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return rgba.prefix(3).map(Int.init)
    }

    private func attach(_ data: Data, _ name: String) throws -> UIImage {
        let image = try XCTUnwrap(UIImage(data: data))
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    /// 暗くした下の方（文字の無い右側）にも、写真の橙が残る。前の塗り方では同じ画素で色が消える
    func testShadedAreaKeepsThePhoto() throws {
        let zao = try lines(place: "蔵王キツネ村, 白石市, 宮城県, 989-0733, 日本")
        let after = try attach(TripBookCardRenderer.render(zao, cover: brightPhoto(), focal: nil), "旅の一冊の共有_明るい写真_直した後")
        XCTAssertEqual(after.size, TripBookCard.size)
        let before = try attach(LegacyTripBookCard.render(zao, cover: brightPhoto()), "旅の一冊の共有_明るい写真_直す前")

        // 橙の動物の胴（絵の 1600×2000 を 0.675 倍した y 945〜1282・x 337〜877）。右側の文字の無い所
        let fox = try rgb(after, 800, 1180)
        XCTAssertGreaterThan(fox[0], fox[2] + 25, "暗くした所で写真の橙が消えた \(fox)")
        XCTAssertLessThan(fox[0], 200, "下が暗くなっていない \(fox)")
        let old = try rgb(before, 800, 1180)
        XCTAssertLessThan(abs(old[0] - old[2]), 15, "前の塗り方（置き換え）で写真が残っている——比べる前提が崩れた \(old)")
        // 上の空は元の写真の明るさのまま（暗くし始めるのは下の半分から）
        let sky = try rgb(after, 1000, 200)
        XCTAssertGreaterThan(sky[2], 200, "上の空まで暗くなった \(sky)")
        // 下の端は黒に近い（白い字が読める）
        let bottom = try rgb(after, 1070, 1340)
        XCTAssertLessThan(bottom.max() ?? 255, 70, "下の端が暗くない \(bottom)")
    }

    /// 暗い写真・表紙の無い旅・長い題も、描けて大きさが合う（絵は添付で見る）
    func testOtherCardsRender() throws {
        let kanazawa = try lines(place: "金沢")
        let dark = try attach(TripBookCardRenderer.render(kanazawa, cover: darkPhoto(), focal: nil), "旅の一冊の共有_暗い写真_直した後")
        XCTAssertEqual(dark.size, TripBookCard.size)
        _ = try attach(LegacyTripBookCard.render(kanazawa, cover: darkPhoto()), "旅の一冊の共有_暗い写真_直す前")

        let none = try attach(TripBookCardRenderer.render(kanazawa, cover: nil, focal: nil), "旅の一冊の共有_表紙なし_直した後")
        let corner = try rgb(none, 1070, 10)
        XCTAssertLessThan(corner.max() ?? 255, 12, "表紙なしは黒地 \(corner)")
        _ = try attach(LegacyTripBookCard.render(kanazawa, cover: nil), "旅の一冊の共有_表紙なし_直す前")

        let long = try lines(place: "白川郷合掌造り集落展望台, 荻町, 白川村, 大野郡, 岐阜県, 501-5627, 日本")
        _ = try attach(TripBookCardRenderer.render(long, cover: brightPhoto(), focal: nil), "旅の一冊の共有_長い題_直した後")
        _ = try attach(LegacyTripBookCard.render(long, cover: brightPhoto()), "旅の一冊の共有_長い題_直す前")
    }
}

/// **比べるためだけの、前の描き方の写し**（2026-11-26 まで出ていた 1.2.x の `TripBookCardRenderer`）。
/// 置き換えで塗る 48 段の帯と、括弧つきの題を UIKit に折らせる形。アプリでは使わない
private enum LegacyTripBookCard {
    static func render(_ lines: TripBookCard.Lines, cover: Data?) -> Data {
        let size = TripBookCard.size
        let margin = TripBookCard.margin
        let width = size.width - margin * 2
        let display = UIFont(name: JPFont.displayName, size: 84) ?? .systemFont(ofSize: 84, weight: .bold)
        let mono = UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .medium)
        let eyebrow = UIFont.monospacedDigitSystemFont(ofSize: 26, weight: .medium)
        let body = UIFont.systemFont(ofSize: 32, weight: .medium)
        // 前の題は括弧の地域を含んでいた（`TripBook.tripTitle`）
        let title = lines.region.isEmpty ? lines.title
            : lines.title.replacingOccurrences(of: L("の旅", ""), with: "") + L("（\(lines.region)）の旅", " (\(lines.region))")
        func height(_ text: String, _ font: UIFont, _ maxLines: Int) -> Double {
            let limit = font.lineHeight * Double(maxLines) + 1
            let bounds = NSAttributedString(string: text, attributes: [.font: font])
                .boundingRect(with: CGSize(width: width, height: limit),
                              options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            return min(bounds.height.rounded(.up), limit.rounded(.up))
        }
        let heights = [height(lines.eyebrow, eyebrow, 1), height(title, display, 2),
                       height(lines.period, mono, 2), height(lines.stats, body, 2)]
        let gaps: [Double] = [20, 22, 18]
        let top = max(margin, size.height - margin - heights.reduce(0, +) - gaps.reduce(0, +))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.88) { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            if let cover, let image = UIImage(data: cover) {
                image.draw(in: TripBookCard.coverRect(image: image.size, in: size, focal: nil))
                let shadeTop = max(0, min(size.height * 0.6, top - 220))
                for i in 0..<48 {
                    let y0 = (shadeTop + (size.height - shadeTop) * Double(i) / 48).rounded()
                    let y1 = (shadeTop + (size.height - shadeTop) * Double(i + 1) / 48).rounded()
                    guard y1 > y0 else { continue }
                    UIColor.black.withAlphaComponent(0.85 * Double(i + 1) / 48).setFill()
                    UIRectFill(CGRect(x: 0, y: y0, width: size.width, height: y1 - y0))
                }
            }
            let soft = UIColor(white: 1, alpha: 0.82)
            var y = top
            for (text, font, color, h, gap) in [(lines.eyebrow, eyebrow, soft, heights[0], gaps[0]),
                                                (title, display, UIColor.white, heights[1], gaps[1]),
                                                (lines.period, mono, soft, heights[2], gaps[2]),
                                                (lines.stats, body, soft, heights[3], 0)] {
                NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
                    .draw(with: CGRect(x: margin, y: y, width: width, height: h),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
                y += h + gap
            }
            let footer = lines.footer as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: eyebrow, .foregroundColor: soft]
            let footerSize = footer.size(withAttributes: attributes)
            footer.draw(at: CGPoint(x: size.width - margin - footerSize.width, y: margin * 0.8), withAttributes: attributes)
        }
    }
}
#endif
