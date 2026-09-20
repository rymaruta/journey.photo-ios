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
}
