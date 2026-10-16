import Foundation

/// プロフィールの色。Web の `lib/utils/color.ts` / `app/user/profile/page.tsx` と対。
///
/// **保存の形は `#rrggbb` に限る。** Web の `themeRingGradient` は
/// `/^#[0-9a-fA-F]{6}$/` に合わない値を無視するので、別の形で保存すると
/// **アプリでだけ色が付く**（見え方が割れる）。
enum ThemeColor {

    /// 見本の8色（Web の `THEME_COLOR_PRESETS` と同じ並び）。
    static let presets = ["#38bdf8", "#34d399", "#f472b6", "#a78bfa",
                          "#fb7185", "#fbbf24", "#f97316", "#22d3ee"]

    /// 保存してよい形か。
    static func isValid(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard v.count == 7, v.hasPrefix("#") else { return false }
        return v.dropFirst().allSatisfy { $0.isHexDigit }
    }

    /// `#rrggbb` を 0〜1 の三色に。読めなければ nil。
    static func rgb(_ value: String) -> (red: Double, green: Double, blue: Double)? {
        guard isValid(value) else { return nil }
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()
        guard let number = UInt32(hex, radix: 16) else { return nil }
        return (Double((number >> 16) & 0xff) / 255,
                Double((number >> 8) & 0xff) / 255,
                Double(number & 0xff) / 255)
    }

    // MARK: パレットから自由に選んだ色（Web の `input type="color"`・`isCustomTheme` と対）

    /// 0〜1 の赤緑青を、保存の形 `#rrggbb`（**小文字**）に。
    ///
    /// 端末の色選びは Display P3 の色を拡張 sRGB で返すので、0 未満・1 超えの値が来る。
    /// **sRGB に収めて（0〜1 に詰めて）から 255 段に丸める**——丸めと詰めは
    /// ストーリーの文字の「好きな色」と同じ `TextOverlay.hex`（写しを作らない）。
    /// 大文字で保存しても サーバーは小文字にするが、アプリの手元の比べ
    /// （見本と同じ色か）が割れないよう、ここで小文字にそろえる
    static func hex(red: Double, green: Double, blue: Double) -> String {
        hex(TextOverlay.hex(red: red, green: green, blue: blue))
    }

    /// 0xRRGGBB を `#rrggbb`（小文字）に
    static func hex(_ rgb: UInt32) -> String {
        let value = rgb & 0xFFFFFF
        let digits = String(value, radix: 16)
        return "#" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    /// 見本に無い色が入っているか（**Web で選んだ色も含む**）。
    /// 入っていれば「自由に選ぶ」の丸をその色で塗り、選んでいる印を付ける
    /// （以前は見本のどれにも当たらず、何も選んでいないように見えた）
    static func isCustom(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return isValid(v) && !presets.contains(v)
    }

    /// 黒い地の上で見分けにくい色か（WCAG の部品の線 3:1 を下回る）。
    ///
    /// **2026-10-16 判断: 選べるまま・色は変えずに保存し、選んだときに知らせるだけ。**
    /// Web はどんな色でもそのまま保存し、何も知らせない。プロフィールの色は本人の好みで、
    /// 黙って明るく寄せると Web と色が割れ、選んだ色が保存されないように見える。
    /// かといって黙って通すと、黒い地の上で輪が消えたことに気づけない。
    /// だから値には触らず、欄の下に一言出す（線は板の「部品 3:1」・`TextOverlay.minContrastOnBlack`）
    static func isHardToSeeOnBlack(_ value: String) -> Bool {
        guard let rgb = rgb(value) else { return false }
        let packed = TextOverlay.hex(red: rgb.red, green: rgb.green, blue: rgb.blue)
        return BrandPalette.contrast(packed, 0x000000) < TextOverlay.minContrastOnBlack
    }
}
