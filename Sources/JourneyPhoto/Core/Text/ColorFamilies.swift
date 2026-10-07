import Foundation

/// 「色から探す」（モック9-5）。
///
/// 写真の代表色（`dominantColor`・`#rrggbb`）を**5つの色味**に振り分ける。
/// モックの並びは 青（空・海）/ 緑（森・自然）/ オレンジ（夕日）/
/// ピンク（桜・花）/ 白（雪・冬景色）。
///
/// **色を持たない写真は出さない。** 代表色はアップロードのときに計算して
/// 保存するもので、持っていない写真は「色が分からない」のであって
/// 「黒い」のではない。
enum ColorFamilies {

    enum Family: String, CaseIterable, Identifiable {
        case blue, green, orange, pink, white

        var id: String { rawValue }

        var label: String {
            switch self {
            case .blue: return L("青", "Blue")
            case .green: return L("緑", "Green")
            case .orange: return L("オレンジ", "Orange")
            case .pink: return L("ピンク", "Pink")
            case .white: return L("白", "White")
            }
        }

        /// 括弧の中（モックの「（空・海）」）
        var note: String {
            switch self {
            case .blue: return L("空・海", "Sky & sea")
            case .green: return L("森・自然", "Forest & nature")
            case .orange: return L("夕日", "Sunset")
            case .pink: return L("桜・花", "Blossom")
            case .white: return L("雪・冬景色", "Snow & winter")
            }
        }
    }

    /// 色の丸の読み上げ。**色の名前を先に言う**——丸の下の字は
    /// 括弧の中（「空・海」）だけなので、目で見ている人には写真の色で
    /// 分かっても、読み上げでは何色か分からない
    static func accessibilityLabel(_ family: Family, count: Int) -> String {
        L("\(family.label)（\(family.note)）・\(count)枚",
          "\(family.label) (\(family.note)), \(count) photos")
    }

    /// `#rrggbb` を 0...1 の3つに。読めなければ nil
    static func rgb(_ hex: String?) -> (r: Double, g: Double, b: Double)? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xff) / 255,
                Double((value >> 8) & 0xff) / 255,
                Double(value & 0xff) / 255)
    }

    /// その色はどの色味か。**決められなければ nil**（無理に振らない）。
    ///
    /// 先に「白っぽいか」を見る——桜の淡い色は色相だけ見るとピンクにも
    /// 赤にも転ぶが、**彩度が低ければ人は「白」と呼ぶ**。
    /// 暗すぎるものはどの札にも入れない（夜の写真を「青」に混ぜない）。
    static func family(ofHex hex: String?) -> Family? {
        guard let (r, g, b) = rgb(hex) else { return nil }
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))

        // **暗すぎる／明るすぎるは色味で呼ばない**
        if lightness < 0.12 { return nil }
        if saturation < 0.18 { return lightness >= 0.62 ? .white : nil }

        var hue: Double
        if delta == 0 {
            hue = 0
        } else if maxValue == r {
            hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxValue == g {
            hue = 60 * ((b - r) / delta + 2)
        } else {
            hue = 60 * ((r - g) / delta + 4)
        }
        if hue < 0 { hue += 360 }

        switch hue {
        case 20..<50: return .orange
        case 50..<75: return .orange     // 黄は夕日の側に寄せる（札を増やさない）
        case 75..<170: return .green
        case 170..<265: return .blue
        default: return .pink            // 赤〜紫は桜・花の側
        }
    }

    /// その写真を、この色味の札に入れてよいか（2026-10-07 判断）。
    ///
    /// **札は景色を約束している**（「雪・冬景色」「夕日」「桜・花」…）。色だけで振ると、
    /// 白い器の料理が「雪・冬景色」に、オレンジの料理が「夕日」に並んだ
    /// （owner の指摘: 「雪冬景色に料理の写真、お皿とか混ざってる」）。
    /// だから**外の景色の分類だけ**を入れる。分類の無い写真は何が写っているか分からないので入れない
    /// （「決められなければ出さない」——代表色を持たない写真と同じ扱い）。
    /// 白（雪・冬景色）は、建物・街の白い壁も雪ではないので、風景・自然だけにする
    static func allows(_ photo: Photo, in family: Family) -> Bool {
        guard let raw = photo.category?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return false }
        let key = CategoryChoices.key(raw)
        switch family {
        case .white: return natural.contains(key)
        default: return outdoor.contains(key)
        }
    }

    /// 外の景色の分類（`CategoryChoices.key` の鍵）
    private static let outdoor: Set<String> = ["landscape", "nature", "architecture", "street"]
    /// 雪・冬景色に入れてよい分類
    private static let natural: Set<String> = ["landscape", "nature"]

    struct Section: Identifiable, Equatable {
        let family: Family
        let photos: [Photo]
        var id: String { family.rawValue }
        var count: Int { photos.count }
    }

    /// 棚に並べる。**1枚も無い色味は出さない**（押しても空になる札を置かない）
    static func sections(in photos: [Photo], limit: Int = 12) -> [Section] {
        Family.allCases.compactMap { family in
            let matched = GallerySort.popular.apply(
                photos.filter { self.family(ofHex: $0.dominantColor) == family && allows($0, in: family) })
            guard !matched.isEmpty else { return nil }
            return Section(family: family, photos: Array(matched.prefix(limit)))
        }
    }
}
