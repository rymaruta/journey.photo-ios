import Foundation

/// 色の値そのもの（`0xRRGGBB`）。**画面の部品は `WebTheme` から使う。**
///
/// **出どころはデザインシステム「黒塗りの真鍮」（2026-09-25）。**
/// アーティファクト「journey.photo iOS」の「00 デザインシステム」が見本。
/// 決めた理由は「0から」6案を出し、反証と審査を通して選んだ
/// （青は空・海の写真と同じ色、橙は夕日そのもの。真鍮は青の対極で、
/// 暖色でも彩度が半分なので写真と競わない）。
///
/// **規則は1行: 白＝位置と選択、真鍮＝合図と手がかり。
/// 写真の上には白しか置かない。**
///
/// SwiftUI に触らない形で持つのは、**比をテストで見張るため**
/// （`BrandPaletteTests`）。`Color` の模型は値を持たないので、そちらでは
/// 測れない。値を変えたらテストが比を計算し直す。
enum BrandPalette {

    // MARK: 中立

    static let background: UInt32 = 0x000000
    /// カード・チップの面（白 7% を黒に重ねた値）
    static let surface: UInt32 = 0x121212
    /// 入力欄・副ボタンの面（白 10%）
    static let surface2: UInt32 = 0x1A1A1A
    /// 入力欄・枠線ボタンの境界（白 40%）。**部品の縁は 3:1 が要る**
    static let outline: UInt32 = 0x666666
    /// 未選択チップの文字（白 82% を surface に重ねた値）
    static let chipText: UInt32 = 0xD4D4D4
    /// 主ボタン・選択中チップの塗り（白 92%）
    static let primary: UInt32 = 0xEBEBEB
    /// 白・真鍮の塗りに載せる文字（墨）
    static let ink: UInt32 = 0x07090A

    // MARK: 真鍮

    /// 文字・アイコン・点・輪・リンク・眉ラベル。**黒か面の上だけ**
    static let accent: UInt32 = 0xC9A66B
    /// リンクを押している間
    static let accentStrong: UInt32 = 0xE3C98F
    /// **写真の無い画面の主ボタンの塗り。** 上の文字は墨（白は 2.81 で読めない）
    static let accentFill: UInt32 = 0xB8955A
    /// **白を載せる暗い真鍮。** トグルの軌道・地図の印
    static let accentDeep: UInt32 = 0x796440
    /// 案内の帯（真鍮 16%）。**選択状態は担わない**
    static let accentSoft: UInt32 = 0x201B11

    // MARK: 意味の色

    /// 削除・通報・エラーの文字とアイコン
    static let danger: UInt32 = 0xF0565A
    /// 「アカウントを削除」の確定ボタンの塗り（白文字）
    static let dangerFill: UInt32 = 0xC8323A
    /// 成功のアイコン（文字は白のまま）
    static let success: UInt32 = 0x7FC489
    /// 地図の現在地だけ（黒 2pt の縁と組む）
    static let location: UInt32 = 0x9CC3E6

    // MARK: 比

    /// WCAG 2.x の相対輝度。サイトの `textContrast.test.ts` と同じ式
    static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let v = Double((rgb >> shift) & 0xFF) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

