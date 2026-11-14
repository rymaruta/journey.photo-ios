import Foundation

/// 共有カードの次の3つの型の寸法（2026-11-14 owner「この SNS に共有のやつ、新しいデザイン加えつつ、更にブラッシュアップさせたいな」）。
///
/// 2026-11-14 判断（今の7つと被らない方向で、写真が主役のもの）:
/// - 額装: 写真の色を引いた額（マット）に写真を入れ、字を真ん中にそろえる（ほかの型はすべて左にそろえる）
/// - フィルム: 35mm のフィルムの1コマ。撮影値（絞り・シャッター・ISO）を SF の等幅数字で主役に
/// - 縦書き（短冊）: 写真の右の黒い列に、撮影地を明朝の縦書きで
///
/// 字は `ShareCardSafeArea` の枠の中（下は `ShareCardMap.textBase`、上は 4:5・1:1 で 72、9:16 で安全域の上端の 4 下）。
/// 描く処理（`SignatureShareCardMoreStyles.swift`）と単体テストが同じ数を使う。
extension ShareCardMap {

    // MARK: - 額装

    /// 写真の色を引いた額（マット）に、写真を真ん中に入れる。字はすべて真ん中にそろえる。
    /// 額の色は写真の平均の色の色相のまま暗くした色（`MatColor`）。真鍮は使わない（黒い地ではない・板）
    struct MatLayout {
        static let width: CGFloat = 1080
        static let margin: CGFloat = ShareCardMap.newStyleMargin
        static var contentLeft: CGFloat { margin }
        static var contentWidth: CGFloat { width - margin * 2 }
        /// 写真の左右のマット。字の余白（72）より広く取り、額に入れた形にする
        static let matSide: CGFloat = 96
        static var photoWidth: CGFloat { width - matSide * 2 }
        static let brandFontSize: CGFloat = 24
        static let placeFontSize: CGFloat = 54
        static let placeMinimumFontSize: CGFloat = 32
        static let subFontSize: CGFloat = 24
        static let nameFontSize: CGFloat = 24
        static let addressFontSize: CGFloat = 20

        let height: CGFloat
        let base: CGFloat
        /// 上のロゴの行の上端（4:5・1:1 は 72、9:16 は安全域の上端の 4 下）
        let brandTop: CGFloat
        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Self.width / CGFloat(ratio.rawValue)
            base = ShareCardMap.textBase(ratio: ratio)
            brandTop = max(Self.margin, (ShareCardSafeArea.rect(ratio: ratio).minY + 4).rounded(.up))
        }
        /// ロゴの行（マーク 28・字 24）の縦の中心
        var brandCenterY: CGFloat { brandTop + 16 }
        var photoTop: CGFloat { brandTop + 68 }
        var addressTop: CGFloat { base - 24 }
        var authorTop: CGFloat { base - 72 }
        var subPlaceTop: CGFloat { base - 114 }
        var placeTop: CGFloat { base - 190 }
        var photoBottom: CGFloat { placeTop - 40 }
        var photoRect: CGRect {
            CGRect(x: Self.matSide, y: photoTop, width: Self.photoWidth, height: photoBottom - photoTop)
        }
    }

    /// 額の色（写真の平均の色から）。Linux でも確かめられるように数だけで持つ
    enum MatColor {
        /// 額の地の相対輝度。白の字が 12:1、灰（#B8B8B8）の字が 6:1 になる暗さ
        static let targetLuminance = 0.035
        /// 彩度の上限（派手な写真でも額が色で騒がない）
        static let maximumSaturation = 0.5

        /// 写真の平均の色（sRGB 0〜255）から、額の色（sRGB 0〜255）。色相は写真のまま
        static func color(red: Double, green: Double, blue: Double) -> (red: Double, green: Double, blue: Double) {
            let r = red / 255, g = green / 255, b = blue / 255
            let maxV = max(r, g, b), minV = min(r, g, b), delta = maxV - minV
            var hue = 0.0
            if delta > 0 {
                if maxV == r {
                    hue = (g - b) / delta
                } else if maxV == g {
                    hue = (b - r) / delta + 2
                } else {
                    hue = (r - g) / delta + 4
                }
                hue /= 6
                if hue < 0 { hue += 1 }
            }
            let saturation = min(maxV == 0 ? 0 : delta / maxV, maximumSaturation)
            var low = 0.0, high = 1.0
            for _ in 0..<32 {
                let mid = (low + high) / 2
                let c = hsb(hue, saturation, mid)
                if ShareCardSafeArea.luminance(red: c.red, green: c.green, blue: c.blue) > targetLuminance {
                    high = mid
                } else {
                    low = mid
                }
            }
            return hsb(hue, saturation, low)
        }

        /// 色相・彩度・明るさ（0〜1）から sRGB（0〜255）
        static func hsb(_ hue: Double, _ saturation: Double, _ brightness: Double)
            -> (red: Double, green: Double, blue: Double) {
            let h = (hue * 6).truncatingRemainder(dividingBy: 6)
            let c = brightness * saturation
            let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
            let m = brightness - c
            let rgb: (Double, Double, Double)
            switch h {
            case ..<1: rgb = (c, x, 0)
            case ..<2: rgb = (x, c, 0)
            case ..<3: rgb = (0, c, x)
            case ..<4: rgb = (0, x, c)
            case ..<5: rgb = (x, 0, c)
            default: rgb = (c, 0, x)
            }
            return ((rgb.0 + m) * 255, (rgb.1 + m) * 255, (rgb.2 + m) * 255)
        }
    }

    // MARK: - フィルム

    /// 35mm のフィルムの1コマ。左右の端まで渡したフィルムの地に、上下の送り穴と写真。
    /// 下に撮影値（絞り・シャッター・ISO）を SF の等幅数字で大きく、その上に明朝の撮影地、下に機材と撮影者
    struct FilmLayout {
        static let width: CGFloat = 1080
        static let margin: CGFloat = ShareCardMap.newStyleMargin
        static var contentLeft: CGFloat { margin }
        static var contentRight: CGFloat { width - margin }
        static var contentWidth: CGFloat { contentRight - contentLeft }
        /// 送り穴（角丸の長方形）の大きさ・間隔・フィルムの縁からの距離
        static let holeWidth: CGFloat = 26
        static let holeHeight: CGFloat = 36
        static let holePitch: CGFloat = 60
        static let holeInset: CGFloat = 16
        /// 穴の列と写真の間
        static let frameGap: CGFloat = 20
        /// 写真の左右（フィルムの地の上の余白）
        static let photoInset: CGFloat = 40
        static let heroFontSize: CGFloat = 50
        static let heroMinimumFontSize: CGFloat = 30
        static let placeFontSize: CGFloat = 34
        static let placeMinimumFontSize: CGFloat = 24
        static let gearFontSize: CGFloat = 22
        static let nameFontSize: CGFloat = 24
        static let addressFontSize: CGFloat = 20
        /// 右の列（ロゴの字・住所）
        static let brandColumnWidth: CGFloat = 300
        static var leftColumnWidth: CGFloat { contentWidth - brandColumnWidth - 24 }

        let height: CGFloat
        let base: CGFloat
        /// フィルムの上端。9:16 はフィードの 4:5 の切り取りの上端にそろえる（上の穴の列が切られない）
        let stripTop: CGFloat
        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Self.width / CGFloat(ratio.rawValue)
            base = ShareCardMap.textBase(ratio: ratio)
            stripTop = max(56, ShareCardSafeArea.feedCropInset(width: Self.width, height: height).rounded(.up))
        }
        var authorTop: CGFloat { base - 30 }
        var gearTop: CGFloat { base - 71 }
        var heroTop: CGFloat { base - 147 }
        var placeTop: CGFloat { base - 201 }
        var stripBottom: CGFloat { placeTop - 36 }
        var stripRect: CGRect { CGRect(x: 0, y: stripTop, width: Self.width, height: stripBottom - stripTop) }
        var photoRect: CGRect {
            let top = stripTop + Self.holeInset + Self.holeHeight + Self.frameGap
            let bottom = stripBottom - Self.holeInset - Self.holeHeight - Self.frameGap
            return CGRect(x: Self.photoInset, y: top, width: Self.width - Self.photoInset * 2, height: bottom - top)
        }
        /// 送り穴の枠（上の列と下の列）
        var holeRects: [CGRect] {
            let count = Int(Self.width / Self.holePitch)
            let start = (Self.width - CGFloat(count) * Self.holePitch) / 2 + (Self.holePitch - Self.holeWidth) / 2
            let rows = [stripTop + Self.holeInset, stripBottom - Self.holeInset - Self.holeHeight]
            return rows.flatMap { y in
                (0..<count).map {
                    CGRect(x: start + CGFloat($0) * Self.holePitch, y: y, width: Self.holeWidth, height: Self.holeHeight)
                }
            }
        }
    }

    // MARK: - 縦書き（短冊）

    /// 写真の右に黒い短冊の列。撮影地を明朝の縦書きで大きく、その左に市区町村を小さく、下にロゴの印（真鍮の角の枠）。
    /// 撮影者と住所は写真の下の1行
    struct TanzakuLayout {
        static let width: CGFloat = 1080
        static let margin: CGFloat = ShareCardMap.newStyleMargin
        static let columnWidth: CGFloat = 176
        static var columnRight: CGFloat { width - margin }
        static var columnLeft: CGFloat { columnRight - columnWidth }
        static let photoGap: CGFloat = 28
        static var photoLeft: CGFloat { margin }
        static var photoRight: CGFloat { columnLeft - photoGap }
        static let placeFontSize: CGFloat = 76
        static let placeMinimumFontSize: CGFloat = 40
        static let subFontSize: CGFloat = 30
        static let subMinimumFontSize: CGFloat = 22
        static let sealSize: CGFloat = 84
        static let nameFontSize: CGFloat = 24
        static let addressFontSize: CGFloat = 20
        /// 縦の字の1字の送り（字の大きさの 1.08 倍）
        static let verticalAdvance: CGFloat = 1.08
        /// 撮影地の列の中心（右）と、市区町村の列の中心（左）
        static var placeColumnX: CGFloat { columnRight - 50 }
        static var subColumnX: CGFloat { columnLeft + 34 }
        /// 下の行の住所の幅（右揃え）。撮影者はその手前まで
        static let addressColumnWidth: CGFloat = 260
        static var authorWidth: CGFloat { width - margin * 2 - addressColumnWidth - 24 }

        let height: CGFloat
        let base: CGFloat
        let top: CGFloat
        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Self.width / CGFloat(ratio.rawValue)
            base = ShareCardMap.textBase(ratio: ratio)
            top = max(Self.margin, (ShareCardSafeArea.rect(ratio: ratio).minY + 4).rounded(.up))
        }
        var authorTop: CGFloat { base - 30 }
        var photoBottom: CGFloat { authorTop - 32 }
        var photoRect: CGRect {
            CGRect(x: Self.photoLeft, y: top, width: Self.photoRight - Self.photoLeft, height: photoBottom - top)
        }
        var sealRect: CGRect {
            CGRect(x: Self.placeColumnX - Self.sealSize / 2, y: photoBottom - Self.sealSize,
                   width: Self.sealSize, height: Self.sealSize)
        }
        /// 縦の字を置ける上端と下端（印の 28 上まで）
        var placeTop: CGFloat { top + 4 }
        var placeBottom: CGFloat { sealRect.minY - 28 }
        /// 市区町村は撮影地の1字ぶん下から（縦書きの添え書きの位置）
        func subTop(placeSize: CGFloat) -> CGFloat { placeTop + placeSize * Self.verticalAdvance }
    }

    /// 縦書きの字の扱い（2026-11-14）。和文（漢字・かな・全角の記号）だけの字は1字ずつ縦に積み、
    /// 英字などが混じる字は行ごと 90° 回して縦に流す（縦書きの組版の慣わし）
    enum VerticalText {
        static func stacks(_ value: String) -> Bool {
            !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF01...0xFF60: return true
                default: return false
                }
            }
        }

        /// 縦に積むときに 90° 回す字（長音・波線・ダッシュ・三点）
        static func rotatesInColumn(_ character: Character) -> Bool {
            "ー〜～—―…‥-".contains(character)
        }

        /// 縦に積んだときの大きさ（下限まで 1 ずつ縮める）と、入る字の数。入りきらなければ最後を「︙」にする
        static func fit(count: Int, maxHeight: CGFloat, size: CGFloat, minimumSize: CGFloat)
            -> (size: CGFloat, shown: Int, truncated: Bool) {
            var fitted = size
            let advance = TanzakuLayout.verticalAdvance
            while fitted > minimumSize, CGFloat(count) * fitted * advance > maxHeight { fitted -= 1 }
            let room = max(1, Int((maxHeight / (fitted * advance)).rounded(.down)))
            return count > room ? (fitted, room, true) : (fitted, count, false)
        }
    }
}
