import Foundation

/// 共有カードの新しい3つの型の寸法（2026-11-14 owner「もっとデザイン増やしたいね」）。
///
/// どれも字は `ShareCardSafeArea` の枠の中に、下から数えて置く（`textBase` が字の下端）。
/// 4:5・1:1 は端から 72（短い辺の 6.7%）、9:16 はストーリーの下の帯（20%）の上。写真は安全域の外にはみ出してよい（字ではない）。
/// - プリント: 白い紙の焼き増し。写真の周りに白いフチ、下の広いフチに明朝の撮影地と撮影者（墨の字。真鍮は使わない＝黒地の上だけの決まり）
/// - 切符: 黒地に札（surface-1）の切符。写真の下にミシン目と左右の切り欠き、半券に眉ラベル（真鍮）と撮影地・撮影者・機材・地図
/// - シネマ: 写真を左右の端まで敷き、上下を黒い帯に。下の帯に明朝の撮影地、右にロゴの字
/// 描く処理（`SignatureShareCardNewStyles.swift`）と単体テストが同じ数を使う。
extension ShareCardMap {
    /// 新しい型の字の左右・上下の余白（短い辺の 6.7%。安全域 6% に字の形の張り出しの余りを足す）
    static let newStyleMargin: CGFloat = 72

    /// 字を置く下端。4:5・1:1 は下から 72、9:16 は安全域の下端（ストーリーの返信欄の上）
    static func textBase(ratio: SignatureShareCardRenderer.Ratio, bottomMargin: CGFloat = newStyleMargin) -> CGFloat {
        let height = 1080 / CGFloat(ratio.rawValue)
        return min(height - bottomMargin, ShareCardSafeArea.rect(ratio: ratio).maxY.rounded(.down))
    }

    // MARK: - プリント

    struct PrintLayout {
        static let width: CGFloat = 1080
        static let margin: CGFloat = ShareCardMap.newStyleMargin
        static var contentLeft: CGFloat { margin }
        static var contentRight: CGFloat { width - margin }
        static var contentWidth: CGFloat { contentRight - contentLeft }
        /// 撮影地（明朝）の大きさ
        static let placeFontSize: CGFloat = 60
        static let placeMinimumFontSize: CGFloat = 36
        static let subFontSize: CGFloat = 26
        static let nameFontSize: CGFloat = 26
        static let infoFontSize: CGFloat = 20
        /// 右の列（ロゴの字と Web の住所）の幅。撮影者と撮影情報はその手前まで
        static let brandColumnWidth: CGFloat = 300

        let height: CGFloat
        let base: CGFloat
        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Self.width / CGFloat(ratio.rawValue)
            base = ShareCardMap.textBase(ratio: ratio)
        }
        var infoTop: CGFloat { base - 26 }
        var authorTop: CGFloat { base - 71 }
        var subPlaceTop: CGFloat { base - 114 }
        var placeTop: CGFloat { base - 198 }
        var photoBottom: CGFloat { placeTop - 40 }
        var photoRect: CGRect {
            CGRect(x: Self.margin, y: Self.margin, width: Self.contentWidth, height: photoBottom - Self.margin)
        }
        /// 撮影者・撮影情報の幅（右の列の 24 手前まで）
        static var leftColumnWidth: CGFloat { contentWidth - brandColumnWidth - 24 }
    }

    // MARK: - 切符

    struct TicketLayout {
        static let width: CGFloat = 1080
        /// 切符の外形（端から 40・真鍮の細線。飾りの線なので安全域の外でよい）
        static let ticketInset: CGFloat = 40
        static let cornerRadius: CGFloat = 28
        /// 切符の内側の余白（写真と半券の字の左右）。字の左端は 40 + 32 = 72
        static let padding: CGFloat = 32
        static var contentLeft: CGFloat { ticketInset + padding }
        static var contentRight: CGFloat { width - ticketInset - padding }
        static var contentWidth: CGFloat { contentRight - contentLeft }
        /// 半券（ミシン目の下）の字の高さ
        static let stubHeight: CGFloat = 200
        static let perforationGap: CGFloat = 36
        static let notchRadius: CGFloat = 20
        static let placeFontSize: CGFloat = 54
        static let placeMinimumFontSize: CGFloat = 32
        static let eyebrowSize: CGFloat = 15
        static let valueFontSize: CGFloat = 24
        /// 右の列（ロゴの字・住所・地図）
        static let rightColumnWidth: CGFloat = 220
        static var leftColumnWidth: CGFloat { contentWidth - rightColumnWidth - 32 }
        /// 半券の2段目の2列（撮影者・機材）
        static var secondColumnX: CGFloat { contentLeft + 300 }

        let height: CGFloat
        /// 字の下端
        let base: CGFloat
        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Self.width / CGFloat(ratio.rawValue)
            base = ShareCardMap.textBase(ratio: ratio, bottomMargin: Self.ticketInset + 44)
        }
        var ticketRect: CGRect {
            CGRect(x: Self.ticketInset, y: Self.ticketInset, width: Self.width - Self.ticketInset * 2,
                   height: base + 44 - Self.ticketInset)
        }
        var stubTop: CGFloat { base - Self.stubHeight }
        var perforationY: CGFloat { stubTop - Self.perforationGap }
        var photoRect: CGRect {
            let top = Self.ticketInset + Self.padding
            return CGRect(x: Self.contentLeft, y: top, width: Self.contentWidth,
                          height: perforationY - Self.perforationGap - top)
        }
        var placeEyebrowTop: CGFloat { stubTop }
        var placeTop: CGFloat { stubTop + 24 }
        var secondRowTop: CGFloat { stubTop + 122 }
        var mapRect: CGRect {
            CGRect(x: Self.contentRight - Self.rightColumnWidth, y: stubTop + 74,
                   width: Self.rightColumnWidth, height: base - stubTop - 74)
        }
    }

    // MARK: - シネマ

    struct CinemaLayout {
        static let width: CGFloat = 1080
        static let margin: CGFloat = ShareCardMap.newStyleMargin
        static var contentLeft: CGFloat { margin }
        static var contentRight: CGFloat { width - margin }
        /// 上の黒い帯（字は置かない）
        static let topBar: CGFloat = 96
        static let placeFontSize: CGFloat = 52
        static let placeMinimumFontSize: CGFloat = 32
        static let nameFontSize: CGFloat = 24
        static let infoFontSize: CGFloat = 20
        static let brandColumnWidth: CGFloat = 330
        static var leftColumnWidth: CGFloat { contentRight - contentLeft - brandColumnWidth - 24 }

        let height: CGFloat
        let base: CGFloat
        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Self.width / CGFloat(ratio.rawValue)
            base = ShareCardMap.textBase(ratio: ratio)
        }
        var photoBottom: CGFloat { base - 192 }
        var photoRect: CGRect { CGRect(x: 0, y: Self.topBar, width: Self.width, height: photoBottom - Self.topBar) }
        var placeTop: CGFloat { photoBottom + 44 }
        var authorTop: CGFloat { photoBottom + 128 }
        var infoTop: CGFloat { photoBottom + 168 }
    }
}
