import Foundation

/// 色の値そのもの（`0xRRGGBB`）。**画面の部品は `WebTheme` から使う。**
///
/// **出どころはデザインシステム「黒塗りの真鍮」（2026-09-25）。**
/// アーティファクト「journey.photo iOS」の「00 デザインシステム」が見本。
/// 決めた理由は「0から」6案を出し、反証と審査を通して選んだ
/// （青は空・海の写真と同じ色、橙は夕日そのもの。真鍮は青の対極で、
/// 暖色でも彩度が半分なので写真と競わない）。
///
/// **v2（2026-10-14・Artifact「デザインシステム v2」）で面を一段沈め、文字の3段・金属の光を足した。**
/// v1 との違い: 札 #121212 → #0E0E0F・入力欄 #1A1A1A → #161617・案内の帯 #201B11 → #1C170E・
/// 白の主ボタン 92% → 94%。真鍮・危険・成功・現在地は v1 のまま。
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
    /// 札の面（v2 の surface-1。v1 の #121212 から一段沈めた——写真の縁が浮く）
    static let surface: UInt32 = 0x0E0E0F
    /// 札の中の入力欄・シートの地（v2 の surface-2。v1 は #1A1A1A）
    static let surface2: UInt32 = 0x161617

    // MARK: 面の段（surface-2 より上・2026-10-14）
    //
    // v2 の板が画面ごとに書いた一段上の灰。担当ごとに `Color(red: 0x1E …)` と直に書いて散らばっていたので、
    // **値は変えずに**ここへ名前を付けて集めた（2026-10-14 判断）。数が大きいほど明るい。
    // 新しい灰を足す前に、ここのどれかで足りないかを見る

    /// 一段浮かせた小さな面（板 PostSheet の印の札・StoryReplies の吹き出し・SongPicker の帯）
    static let surface3: UInt32 = 0x1A1A1C
    /// 読み込み中の骨格の灰・ストーリーの返信欄を書いている間の地（板 `#1C1C1E`）
    static let surface4: UInt32 = 0x1C1C1E
    /// ストーリーのメニューのシートの地（板 StoryViewerMenu `#1E1E20`）
    static let surface5: UInt32 = 0x1E1E20
    /// ストーリーの削除の確認の地（板 `rgba(40,40,42,.96)`）
    static let surface6: UInt32 = 0x28282A
    /// 投稿の写真の帯の「外す」の丸（板 `#2A2A2C`）
    static let surface7: UInt32 = 0x2A2A2C
    /// 投稿のつながったセグメントの選んだ側（板 `#2C2C2E`）
    static let surface8: UInt32 = 0x2C2C2E
    /// 面の段（暗い → 明るい）。テストが「段が明るさの順に並ぶ」ことを見張る
    static let surfaceSteps: [UInt32] = [background, surface, surface2, surface3, surface4, surface5,
                                         surface6, surface7, surface8]
    /// 入力欄・枠線ボタンの境界（白 40%）。**部品の縁は 3:1 が要る**
    static let outline: UInt32 = 0x666666
    /// 未選択チップの文字（白 82% を surface に重ねた値）
    static let chipText: UInt32 = 0xD4D4D4
    /// 副文の字（v2 の text-2・白 72% と同じ値）
    static let text2: UInt32 = 0xB8B8B8
    /// 注記・@名・日時の字（v2 の text-3・白 60% とほぼ同じ値）
    static let text3: UInt32 = 0x9A9A9A
    /// 主ボタン・選択中チップの塗り（v2: 白 94%。v1 は 92% の #EBEBEB）
    static let primary: UInt32 = 0xF0F0F0
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
    /// 案内の帯（v2: 真鍮 8% の #1C170E。v1 は 16% の #201B11）。**選択状態は担わない**
    static let accentSoft: UInt32 = 0x1C170E
    /// 金属の光の明るい端（v2 の brass-hi）。**輪・メダル・Pro の印の光だけ**。字には使わない
    static let accentHighlight: UInt32 = 0xF3DCA6
    /// 金属の光の暗い端（v2 の brass-hi → lo の lo）
    static let accentShadow: UInt32 = 0x9A7A45

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

