import Foundation
import UIKit

// サポーター証の絵（板 64・板 Badge3D・2026-10-09）。
//
// **SwiftUI を読まない**（`MedalTextures` と同じ理由）。表は素材の絵（`supporter-card-front`）に
// 名前・@ユーザー名・番号・MEMBER SINCE を重ねて1枚にする。画面の札も、手に取って回す
// 3D の表も**同じ1枚**を使う（2か所で重ね方がずれないように）。

/// サポーター証の寸法と、重ねる文字の置き場（板 64 の pt・342×216 の札の上で）
enum SupporterCardLayout {
    static let width: Double = 342
    static let height: Double = 216
    /// 角の丸み（板: 16）
    static let cornerRadius: Double = 16
    /// 厚み（板 Badge3D: 表と裏を 2px ずつ前後に出す＝4）
    static let thickness: Double = 4
    /// 絵の倍率（素材は 1026×648 ＝ 3倍）
    static let scale: Double = 3

    static var aspect: Double { width / height }

    /// 名前（板: 左 24・上 84・明朝 22・白・影 0 1 2 黒 60%）。羅針盤にかからない幅まで
    static let nameOrigin = CGPoint(x: 24, y: 84)
    static let nameFont: Double = 22
    static let nameMaxWidth: Double = 196
    /// @ユーザー名（板: 左 24・上 116・12・白 65%）
    static let handleOrigin = CGPoint(x: 24, y: 116)
    static let handleFont: Double = 12
    /// MEMBER SINCE（板: 左 24・上 168・12・白 72%、値は #E3C98F）
    static let sinceOrigin = CGPoint(x: 24, y: 168)
    static let sinceFont: Double = 12
    /// 番号（素材の右上「No. 0001」の位置: 右端 313.7・字の中心の高さ 34.6・明朝 13）。
    /// **素材の絵の番号は消してあり、ここで本人の番号を重ねる**（報告済み）
    static let numberRight: Double = 313.7
    static let numberCenterY: Double = 34.6
    static let numberFont: Double = 13

    /// 板 64 の値の色（MEMBER SINCE の日付）
    static let sinceValueRGB: (Double, Double, Double) = (0xE3, 0xC9, 0x8F)
    /// 素材の番号の色（淡い金）
    static let numberRGB: (Double, Double, Double) = (246, 232, 197)

    /// 画面の札の大きさ。左右 24 ずつ空け、板の 342 を超えない
    static func cardWidth(screenWidth: Double) -> Double {
        max(240, min(screenWidth - 48, width))
    }
}

/// サポーター証に重ねる中身
struct SupporterCardFace: Equatable {
    let name: String
    let handle: String?
    let number: Int
    let since: String?

    /// 読み上げ（「サポーター証 No. 0001、丸田、@maruta、MEMBER SINCE 2026.10」）
    var accessibilityLabel: String {
        var parts = [L("サポーター証", "Supporter card"), SupporterText.numberLabel(number)]
        if !name.isEmpty { parts.append(name) }
        if let handle { parts.append("@\(handle)") }
        if let since { parts.append("MEMBER SINCE \(since)") }
        return parts.joined(separator: L("、", ", "))
    }
}

enum SupporterCardTextures {

    /// 表（文字を重ねた1枚）と裏・金の小口の帯
    static func make(_ face: SupporterCardFace) -> MedalTextures.Faces {
        MedalTextures.Faces(front: front(face), back: UIImage(named: "supporter-card-back"),
                            edge: giltEdge(), edgeRepeat: 1)
    }

    private static func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private static func color(_ rgb: (Double, Double, Double), alpha: Double = 1) -> UIColor {
        UIColor(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: alpha)
    }

    /// 表。素材が読めなければ nil（画面は素材の絵だけを出す）
    static func front(_ face: SupporterCardFace) -> UIImage? {
        guard let base = UIImage(named: "supporter-card-front") else { return nil }
        let k = SupporterCardLayout.scale
        let size = CGSize(width: SupporterCardLayout.width * k, height: SupporterCardLayout.height * k)
        return renderer(size: size).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))

            // 名前（明朝・白・影）。長い名前は縮め、それでも長ければ末尾を「…」
            let name = face.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let shadow = NSShadow()
                shadow.shadowOffset = CGSize(width: 0, height: 1 * k)
                shadow.shadowBlurRadius = 2 * k
                shadow.shadowColor = UIColor(white: 0, alpha: 0.6)
                let maxWidth = SupporterCardLayout.nameMaxWidth * k
                var fontSize = SupporterCardLayout.nameFont * k
                var attributes: [NSAttributedString.Key: Any] = [.font: display(fontSize),
                                                                   .foregroundColor: UIColor.white, .shadow: shadow]
                let measured = Double((name as NSString).size(withAttributes: attributes).width)
                if measured > maxWidth {
                    fontSize = max(fontSize * 0.7, fontSize * maxWidth / measured)
                    attributes[.font] = display(fontSize)
                }
                draw(fitting(name, attributes: attributes, maxWidth: maxWidth), attributes: attributes,
                     at: CGPoint(x: SupporterCardLayout.nameOrigin.x * k, y: SupporterCardLayout.nameOrigin.y * k))
            }

            if let handle = face.handle, !handle.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: SupporterCardLayout.handleFont * k),
                    .foregroundColor: UIColor(white: 1, alpha: 0.65),
                ]
                draw(fitting("@\(handle)", attributes: attributes, maxWidth: SupporterCardLayout.nameMaxWidth * k),
                     attributes: attributes,
                     at: CGPoint(x: SupporterCardLayout.handleOrigin.x * k, y: SupporterCardLayout.handleOrigin.y * k))
            }

            if let since = face.since {
                let font = UIFont.monospacedDigitSystemFont(ofSize: SupporterCardLayout.sinceFont * k, weight: .regular)
                let text = NSMutableAttributedString(string: "MEMBER SINCE ", attributes: [
                    .font: font, .foregroundColor: UIColor(white: 1, alpha: 0.72),
                ])
                text.append(NSAttributedString(string: since, attributes: [
                    .font: font, .foregroundColor: color(SupporterCardLayout.sinceValueRGB),
                ]))
                text.draw(at: CGPoint(x: SupporterCardLayout.sinceOrigin.x * k, y: SupporterCardLayout.sinceOrigin.y * k))
            }

            // 番号（右寄せ）
            let numberAttributes: [NSAttributedString.Key: Any] = [
                .font: display(SupporterCardLayout.numberFont * k),
                .foregroundColor: color(SupporterCardLayout.numberRGB),
                .kern: 0.06 * SupporterCardLayout.numberFont * k,
            ]
            let number = SupporterText.numberLabel(face.number) as NSString
            let numberSize = number.size(withAttributes: numberAttributes)
            number.draw(at: CGPoint(x: SupporterCardLayout.numberRight * k - Double(numberSize.width),
                                    y: SupporterCardLayout.numberCenterY * k - Double(numberSize.height) / 2),
                        withAttributes: numberAttributes)
        }
    }

    /// 金の小口（板 Badge3D: 厚みの向きに #6E5632 → #F6E6BC 30% → #FFF3D2 50% → #B8955A 75% → #6E5632）
    static func giltEdge() -> UIImage {
        let stops: [(Double, (Double, Double, Double))] = [
            (0, (0x6E, 0x56, 0x32)), (0.3, (0xF6, 0xE6, 0xBC)), (0.5, (0xFF, 0xF3, 0xD2)),
            (0.75, (0xB8, 0x95, 0x5A)), (1, (0x6E, 0x56, 0x32)),
        ]
        let height = 64
        return renderer(size: CGSize(width: 4, height: height)).image { context in
            for row in 0..<height {
                let t = (Double(row) + 0.5) / Double(height)
                let rgb = interpolate(stops, at: t)
                color(rgb).setFill()
                context.fill(CGRect(x: 0, y: row, width: 4, height: 1))
            }
        }
    }

    /// 色の段の間を線形に
    static func interpolate(_ stops: [(Double, (Double, Double, Double))], at t: Double) -> (Double, Double, Double) {
        guard let first = stops.first, let last = stops.last else { return (0, 0, 0) }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for (a, b) in zip(stops, stops.dropFirst()) where t >= a.0 && t <= b.0 {
            let f = (t - a.0) / max(0.0001, b.0 - a.0)
            return (a.1.0 + (b.1.0 - a.1.0) * f, a.1.1 + (b.1.1 - a.1.1) * f, a.1.2 + (b.1.2 - a.1.2) * f)
        }
        return last.1
    }

    private static func display(_ size: Double) -> UIFont {
        UIFont(name: JPFont.displayName, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
    }

    private static func fitting(_ text: String, attributes: [NSAttributedString.Key: Any], maxWidth: Double) -> String {
        var shown = text
        while shown.count > 1, Double((shown as NSString).size(withAttributes: attributes).width) > maxWidth {
            shown = String(shown.dropLast(2)) + "…"
        }
        return shown
    }

    private static func draw(_ text: String, attributes: [NSAttributedString.Key: Any], at point: CGPoint) {
        (text as NSString).draw(at: point, withAttributes: attributes)
    }
}
