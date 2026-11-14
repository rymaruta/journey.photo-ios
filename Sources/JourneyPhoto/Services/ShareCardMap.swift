import Foundation

/// SNS 共有カード（`SignatureShareCardRenderer`）の地図の計算。
///
/// 描く処理（CoreGraphics）から切り出し、Linux でも枠の寸法・残す島・塗る県を試せるようにした。
/// 2026-11-04 判断（案A-3 → 地図8・owner 採用。見本は Artifact「SNS 共有カード」の `project/Card.dc.html`）:
/// - 枠は 264×296（4:5）。上端は写真の裾が黒へ溶ける帯の 70% の所、下端は撮影情報の 8 上。
///   どの比でも撮影者の段（rowTop）から測るので同じ大きさになる
/// - 国の全体ではなく「撮った場所の島」と「一番大きい陸」から 60km 以内でつながる島だけを収める
/// - 日本の写真は、撮影地の文字の県を真鍮 75% で塗る
enum ShareCardMap {
    /// Natural Earth 由来の輪郭（国: `country-outlines.json`、県: `japan-prefectures.json`）。
    /// `r` は輪の並び、輪は `[経度, 緯度]` の並び。
    struct Shape: Decodable {
        let n: String
        let r: [[[Double]]]
    }

    struct Bounds: Equatable {
        var west: Double
        var east: Double
        var south: Double
        var north: Double

        init(west: Double, east: Double, south: Double, north: Double) {
            self.west = west; self.east = east; self.south = south; self.north = north
        }

        init?(_ rings: [[[Double]]]) {
            var west = Double.infinity, east = -Double.infinity
            var south = Double.infinity, north = -Double.infinity
            for ring in rings {
                for point in ring where point.count == 2 {
                    west = min(west, point[0]); east = max(east, point[0])
                    south = min(south, point[1]); north = max(north, point[1])
                }
            }
            guard west.isFinite, south.isFinite else { return nil }
            self.init(west: west, east: east, south: south, north: north)
        }

        func contains(longitude: Double, latitude: Double, margin: Double = 0) -> Bool {
            (west - margin...east + margin).contains(longitude)
                && (south - margin...north + margin).contains(latitude)
        }
    }

    // MARK: - 枠の寸法

    /// カードの寸法。数は `SignatureShareCardRenderer.render` の描き方そのもの
    /// （描画とテストが同じ数を使う）。
    ///
    /// 2026-11-04 owner「地図8（整え版）を採用して、妥協なしでブラッシュアップ」。見本は Artifact
    /// 「SNS 共有カード 1.1.62」の `project/Map8.dc.html`（4:5・1080×1350）。決まり:
    /// - 外の余白 60・帯の中身は写真の左右の端にそろえる（内側に寄せない）・額縁は 12 内側に 3px
    /// - 段の間隔（撮影者の段 → 区切り線 → 撮影情報）は 32 にそろえる。帯の下の余白は 38
    /// - 区切り線・縦線は 2px・真鍮 45% の1種類
    /// - 2026-11-04 owner「フェードする境界線いらない」: 写真の裾を黒へ溶かす帯（フェード）はやめた。
    ///   写真は帯の開始位置できれいに終わり、その下は黒い面。地図は黒い帯の中だけに置く（写真に掛けない）
    ///   （以前は 15 下まで伸ばし、帯の開始位置で段が出ていた）
    /// - 撮影情報の3列の左端は、上の段（アバター・縦線の右・地図）の縦の線にそろえる
    struct Layout {
        static let width: CGFloat = 1080
        /// カードの上の隅に小さく入れる Web の住所（2026-11-05 owner「WEB版をもっと認知してもらいたい」）。
        /// Instagram の投稿は本文のリンクが押せず画像だけが回るので、画像に住所の字を焼き込む
        static let siteAddress = "journey-photo.com"
        /// 一文と住所の2行の塊（一文 25 の行 + 間 4 + 住所 20 の行）を、見出しの縦の中心にそろえる
        static let siteAddressFontSize: CGFloat = 20
        static let taglineAddressGap: CGFloat = 4
        /// 写真と黒い帯の左右の余白（外の余白）。
        /// 2026-11-14（owner「文字などがギリギリの端すぎて SNS で見にくい、みたいなことないように」）: 60 → 72。
        /// 書き出した画像の画素で測ると、字の左端が 59px（短い辺の 5.46%）・右端が 61px（5.65%）で、安全域（6%・`ShareCardSafeArea`）の外だった。
        /// 新しい型（`newStyleMargin`）と同じ 72 の線にそろえる
        static let margin: CGFloat = ShareCardMap.newStyleMargin
        /// 帯の端から中身（アバター・区切り線・地図）まで。
        /// 2026-11-04 owner「写真の角とアイコンの先頭の端が合うように」: 0。写真の左右の端（60・1020）に、
        /// ロゴのマーク・アバター・区切り線・撮影情報の左端、一文・地図の右端をそろえる（以前は 48 内側で、端が合っていなかった）
        static let contentInset: CGFloat = 0
        static var contentLeft: CGFloat { margin + contentInset }
        static var contentRight: CGFloat { width - margin - contentInset }
        /// 上の帯（ロゴと一文）の高さ。写真はこの下から始まる
        /// 2026-11-04 owner「上のヘッダーの余白の幅も短すぎる」: 100 → 124。中身（一番高い区切り線 57）の上は額縁の内側から、
        /// 下は写真まで、どちらも同じ 26 になる（中心は額縁の内側と写真の真ん中）
        ///
        /// 2026-11-14: 124 → 176。画素で測ると一文と住所の上端が画像の上端から 41px（短い辺の 3.8%）で、安全域（6%）の外だった。
        /// 字の塊（高さ約 58）を上端から 66 に下げ、額縁の内側（15）と写真の上端までの空きを上下とも約 51 にそろえる
        static let header: CGFloat = 176
        /// 見出しの字の塊（一文 25 と住所 20 の2行・約 58）の高さの半分。上端 = 見出しの中心 − これ
        static let headerTextHalfHeight: CGFloat = 29
        /// 9:16 で見出しを下げる量。ストーリーの上の帯（14%・`ShareCardSafeArea`）の 4 下に字の上端が来る（2026-11-14）
        static func topShift(_ ratio: SignatureShareCardRenderer.Ratio) -> CGFloat {
            guard ratio == .story else { return 0 }
            return (ShareCardSafeArea.rect(ratio: ratio).minY + 4 - (headerCenter - headerTextHalfHeight)).rounded(.up)
        }
        /// 9:16 の字の下端（ストーリーの下の帯 20% の 4 上）。型ごとの下の段は、ここから上に置く（2026-11-14）
        static var storyTextBottom: CGFloat {
            ShareCardSafeArea.rect(ratio: .story).maxY.rounded(.down) - 4
        }
        /// ロゴのマーク（45 角）の上端。字の中心はこのマークの中心にそろえる
        static var headerCenter: CGFloat { (frameInset + frameWidth + header) / 2 }
        static var headerMarkY: CGFloat { headerCenter - headerMarkSize / 2 }
        static let headerMarkSize: CGFloat = 45
        /// 額縁（画像の端から内側へ）
        static let frameInset: CGFloat = 12
        static let frameWidth: CGFloat = 3
        /// 区切り線・縦線（1種類）
        static let lineWidth: CGFloat = 2
        static let lineAlpha: CGFloat = 0.45

        /// 黒い帯の上の余白（帯の開始 → 撮影者の段）。上は黒へ溶けているので近くてよい
        static let bandTopPad: CGFloat = 16
        /// 2026-11-05 owner「プロフィールアイコンと名前とアカウント名をもう少し小さく、縦線を左へ寄せて地図を大きく」:
        /// 88 → 76。縦に空いた 12 は段の間隔（36 → 42 ずつ）に回し、帯の高さ・下の余白 38 は変えない
        static let avatarSize: CGFloat = 76
        /// 段の間隔（撮影者の段 → 区切り線 → 撮影情報）
        static let rowGap: CGFloat = 42
        /// 撮影情報の行の高さ。2026-11-04 owner「撮影情報さらに小さくして地図大きくしていい」: 60 → 52（字 21 → 17・記号 38 → 30）
        static let infoHeight: CGFloat = 52

        /// 撮影者の名前の列（アバターの 20 右）。区切りの縦線はその 165 幅の 16 右（名前 30 → 26・ユーザー名 24 → 21 に合わせて詰めた）
        static var nameX: CGFloat { contentLeft + avatarSize + 20 }
        /// 2026-11-14: 余白 60 → 72 の分（12）は、名前の列でなくレンズの列（215 → 203）で詰める。
        /// 一度 153 に詰めたら絵文字の名前（「🌸さくら🌸旅人📷」）が下限の大きさでも入らず「…」で切れた（run 1292・3 比とも）。165 では切れない（run 1287）
        static let nameColumnWidth: CGFloat = 165
        static var rowDividerX: CGFloat { nameX + nameColumnWidth + 16 }
        /// 撮影地の印（pin）と字
        static var pinX: CGFloat { rowDividerX + 24 }
        static var placeX: CGFloat { pinX + 50 }
        /// 地図の枠の幅。右端は本文の右端にそろえる
        /// 2026-11-14: 286 → 274（右の余白 72 の分。地図の左端 734 は変えない）
        static let mapWidth: CGFloat = 274
        static let mapGapToPlace: CGFloat = 8
        /// 地図の下端と撮影情報の上端の間（区切り線は地図の手前で止める）
        /// 地図は黒い帯の高さいっぱい（上下の余白 12）。撮影情報は地図の左へ詰める
        static let mapBandInset: CGFloat = 12
        /// 地図の高さ（4:5・1:1 の帯 268 から上下 12 ずつ）。9:16 は帯が高いが、地図は同じ大きさ（余りは下に空く）
        static let mapHeight: CGFloat = 244
        static let mapLineGap: CGFloat = 16
        /// 撮影情報の3列: カメラ（アバターの左端〜縦線）・レンズ（印の右・215 幅）・撮影値（レンズの 14 右〜地図の 24 手前）
        /// 2026-11-14: 215 → 203（余白 72 の分。撮影値の列の左端 590 は変えない）
        static let lensColumnWidth: CGFloat = 203
        static var exposureX: CGFloat { pinX + lensColumnWidth + 14 }
        static var mapX: CGFloat { contentRight - mapWidth }
        static var placeWidthWithMap: CGFloat { mapX - mapGapToPlace - placeX }
        static var placeWidthWithoutMap: CGFloat { contentRight - placeX }
        /// 撮影地の2行を描く枠の高さ（25pt × 1.35 × 2 行）
        static let placeFontSize: CGFloat = 25
        static let placeHeight: CGFloat = 25 * 1.35 * 2

        let height: CGFloat
        /// 写真の下端から画像の下端まで。9:16 だけ高い（下は Instagram の返信欄に隠れる）
        let footer: CGFloat
        /// 撮影情報（カメラ・レンズ・撮影値）が1つでもあるか。無いときは下の段（区切り線・間・撮影情報の行）を描かない
        let hasShotInfo: Bool
        /// 下の空き（帯の下端から上へ）。9:16 だけ。地図の下端（帯の下端の 12 上）がストーリーの下の帯（20%）の上に来る分
        /// （2026-11-14: 75 → 304。75 では撮影情報と地図が返信欄の帯に掛かっていた・画素で下端から 13.6%）
        let bottomInset: CGFloat
        /// 9:16 で見出しと写真を下げる量（`topShift`）
        let topShift: CGFloat

        /// 下の段（撮影者の段の下の間 → 区切り線 → 間 → 撮影情報の行）の高さ。42 + 2 + 42 + 52 = 138
        static var shotInfoBlockHeight: CGFloat { rowGap + lineWidth + rowGap + infoHeight }

        /// 2026-11-13 判断（owner 承認）: 撮影情報が1つも無いと、撮影者の段の下に 138 の黒い空きが残っていた
        /// （4:5 で撮影者の段の下端 1114 → 帯の下端 1290 が 176。撮影情報があるときの下の余白は 38）。
        /// 無いときは下の段の 138 だけ帯を縮め、その分写真を伸ばす。撮影情報があるときの寸法は変えない
        init(ratio: SignatureShareCardRenderer.Ratio, hasShotInfo: Bool = true) {
            height = Layout.width / CGFloat(ratio.rawValue)
            self.hasShotInfo = hasShotInfo
            bottomInset = ratio == .story
                ? max(0, height - Layout.margin - Layout.mapBandInset - Layout.storyTextBottom) : 0
            topShift = Layout.topShift(ratio)
            // 帯の高さ（268）は前のまま。外の余白が 72 になった分、footer も 12 増える（4:5 で 328 → 340）
            footer = Layout.bandHeight + Layout.margin + bottomInset - (hasShotInfo ? 0 : Self.shotInfoBlockHeight)
        }
        /// 黒い帯の高さ（撮影情報があるとき）。地図 244 と上下 12
        static var bandHeight: CGFloat { mapHeight + mapBandInset * 2 }

        /// 見出し（ロゴ・一文・住所）の縦の中心
        var headerCenterY: CGFloat { Layout.headerCenter + topShift }
        var headerMarkY: CGFloat { headerCenterY - Layout.headerMarkSize / 2 }
        var photoBottom: CGFloat { height - footer }
        var photoRect: CGRect {
            CGRect(x: Layout.margin, y: Layout.header + topShift,
                   width: Layout.width - Layout.margin * 2, height: photoBottom - Layout.header - topShift)
        }
        var bandRect: CGRect {
            CGRect(x: Layout.margin, y: photoBottom,
                   width: Layout.width - Layout.margin * 2, height: height - Layout.margin - photoBottom)
        }
        /// 撮影者の段の上端
        var rowTop: CGFloat { photoBottom + Layout.bandTopPad }
        var rowCenterY: CGFloat { rowTop + Layout.avatarSize / 2 }
        /// 区切り線の上端（線は 2px）
        var separatorY: CGFloat { rowTop + Layout.avatarSize + Layout.rowGap }
        /// 撮影情報の上端。区切り線（2px）の下も同じ 32
        var infoTop: CGFloat { separatorY + Layout.lineWidth + Layout.rowGap }
        var infoCenterY: CGFloat { infoTop + Layout.infoHeight / 2 }
        /// 撮影情報の3列の間の縦罫の x（カメラ|レンズ・レンズ|撮影値）。描くかどうかは `infoDividerIndices`
        static var infoDividerXs: [CGFloat] { [rowDividerX, exposureX - 12] }
        /// 区切り線の右端。地図があるときは地図の手前で止める
        func separatorEndX(hasMap: Bool) -> CGFloat {
            hasMap ? Layout.mapX - Layout.mapLineGap : Layout.contentRight
        }

        /// 地図の枠。**黒い帯の中だけ**で、帯の高さいっぱい（上下の余白 12）。右端は本文の右端（1020）。
        /// 写真には掛けない（フェードをやめたため）。
        /// 撮影情報が無く帯が低いときは、帯の高さ（上下 12・9:16 は下の返信欄 75 も除く）に収まるよう
        /// 286:244 の比のまま縮め、右端はそろえたまま。どの比でも地図は同じ大きさになる（4:5・1:1・9:16 とも 106 の高さ）
        var mapRect: CGRect {
            let fitHeight = min(Layout.mapHeight, bandRect.height - bottomInset - Layout.mapBandInset * 2)
            let width = Layout.mapWidth * fitHeight / Layout.mapHeight
            return CGRect(x: Layout.contentRight - width, y: photoBottom + Layout.mapBandInset,
                          width: width, height: fitHeight)
        }
        /// 撮影地の字が使える幅。地図があるときは地図の左端の 8 手前まで（地図が縮めばその分広い）
        func placeWidth(hasMap: Bool) -> CGFloat {
            hasMap ? mapRect.minX - Layout.mapGapToPlace - Layout.placeX : Layout.placeWidthWithoutMap
        }
    }

    // MARK: - 撮影情報の罫

    /// 撮影情報の列（カメラ・レンズ・撮影値）の間の縦罫のうち、描くものの番号（i は i 列目と i+1 列目の間）。
    /// 2026-11-12 判断: 罫は2つの字を分けるためのものなので、両側の列に字があるときだけ描く。
    /// 撮影情報の無い写真で、帯の型の一番下に中身の無い段が縦の線だけ残っていた（run 1194 の画面写真）。
    /// 字のある列の位置は変えない（板の決まり: 3列の左端は上の段の縦の線にそろえる）
    static func infoDividerIndices(filled: [Bool]) -> [Int] {
        guard filled.count >= 2 else { return [] }
        return (0..<(filled.count - 1)).filter { filled[$0] && filled[$0 + 1] }
    }

    // MARK: - フェード型の寸法

    /// 共有カードの「フェード」型（2026-11-05 owner「ユーザが選べるように・F2 が好き」）の寸法。
    /// 見本は Artifact「SNS 共有カード 新デザイン5案」の `project/F2.dc.html`（4:5・1080×1350）。
    ///
    /// 写真をカード全面に敷き、下を長いなめらかなグラデーションで黒へ溶かす。**黒の帯は無い。**
    /// 情報は黒に着いた所に、下から数えた位置で置く（9:16 は下の 75 を空ける＝Instagram の返信欄）。
    /// 2026-11-05 判断: 写真の上に真鍮の額縁は載せない（真鍮は黒い地の上だけ・写真の上は白だけ）。
    struct FadeLayout {
        static let width: CGFloat = 1080
        /// 2026-11-14: 60 → 72（`Layout.margin` と同じ）
        static let margin: CGFloat = Layout.margin
        static var contentLeft: CGFloat { margin }
        static var contentRight: CGFloat { width - margin }

        let height: CGFloat
        let isSquare: Bool
        /// 下の空き。9:16 だけ（2026-11-14: 75 → 字の下端がストーリーの下の帯 20% の上に来る分。75 では下端から 13.1% だった）
        let bottomInset: CGFloat
        /// 9:16 で見出しを下げる量（`Layout.topShift`）
        let topShift: CGFloat
        /// 基準線から一番下の字（撮影情報の行）の下端まで（画素で測った 66）
        static let contentBelowBase: CGFloat = 66

        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Self.width / CGFloat(ratio.rawValue)
            isSquare = ratio == .square
            bottomInset = ratio == .story ? height - (Layout.storyTextBottom + Self.contentBelowBase) : 0
            topShift = Layout.topShift(ratio)
        }
        var headerCenterY: CGFloat { Layout.headerCenter + topShift }

        /// 下の情報の基準線（これより下は「下の空き」）
        var base: CGFloat { height - bottomInset }
        /// グラデーションの長さ。1:1 は写真が低いので短い
        var fadeLength: CGFloat { isSquare ? 560 : 710 }
        var fadeTop: CGFloat { base - fadeLength }
        /// 上のロゴの下に敷く影（白い字を空の上でも読めるように）。
        /// 2026-11-14: 白い写真の上で一文と住所の明暗の比が 2.01（画素で測った値。黒 55% から下へ薄れる影で、字の所は 21〜37%）だった。
        /// 字の塊の下端の 8 下までは黒 62%（白い写真の上で約 6:1）、そこから 150 で消す
        static let topShadeAlpha: CGFloat = 0.62
        var topShadeHeight: CGFloat { headerCenterY + Layout.headerTextHalfHeight + 8 + 150 }
        var topShadeStops: [(location: CGFloat, alpha: CGFloat)] {
            let solid = (headerCenterY + Layout.headerTextHalfHeight + 8) / topShadeHeight
            return [(0, Self.topShadeAlpha), (solid, Self.topShadeAlpha),
                    (solid + (1 - solid) * 0.45, Self.topShadeAlpha * 0.45), (1, 0)]
        }
        /// グラデーションの形（0〜1 の位置・黒の濃さ）。短い帯にせず6点で滑らかにする（境目を見せない）
        /// 表紙の型（`CoverLayout`・長さ 340）が使う形。フェードの型は `stops`（字の所の濃さを基準線からの距離で決める）
        static let fadeStops: [(location: CGFloat, alpha: CGFloat)] = [
            (0, 0), (0.06, 0.04), (0.18, 0.16), (0.38, 0.38), (0.62, 0.66), (0.85, 0.88), (1, 1)
        ]

        // 右: 地図（右端は写真の右端にそろえる）。
        // 2026-11-14: 地図の上の所は黒 4% しか掛からない写真の上で、真鍮の線の明暗の比が 1.46〜1.93（画素）だった。
        // 写真の上は白だけ（板）なので白で描き、黒 49% 以上が掛かる所（基準線の 370 上から）へ下げる
        static let mapWidth: CGFloat = 380
        var mapHeight: CGFloat { 240 }
        var mapRect: CGRect {
            CGRect(x: Self.contentRight - Self.mapWidth, y: base - 130 - mapHeight,
                   width: Self.mapWidth, height: mapHeight)
        }
        /// 左の列の幅（地図の手前まで）。2026-11-14: 余白 72 に合わせ 580 → 556
        static let leftColumnWidth: CGFloat = 556
        /// 撮影者の行（名前と印）の幅。アバター（64）と間（16）の右から、地図の 16 手前まで。
        /// 2026-11-14: 480 のままだと長い名前の横の印が地図に掛かった（run 1292・4:5 と 1:1 と 9:16 の長い名前）
        static var authorColumnWidth: CGFloat { leftColumnWidth - avatarSize - 16 - 16 }

        /// グラデーションの濃さを、基準線から上への距離（d）で決めた点（2026-11-14）。
        /// run 1292 の画素: 白い写真の上で地名（白・基準線の 366 上）4.42、市区町村と印（真鍮・246 上）3.68、
        /// 1:1 は地図 2.46・地名 2.65（グラデーションが短く、字の所の黒が薄かった）。
        /// 地名と地図の所（d ≤ 376）は黒 62% 以上（白い写真の上で白の字が約 6.5:1）、
        /// 市区町村から下（d ≤ 270）は黒 80% 以上（真鍮が約 5.6:1・板の「写真の上の真鍮は黒 78% 以上」）
        static let stopsByDistance: [(distance: CGFloat, alpha: CGFloat)] = [
            (710, 0), (625, 0.05), (525, 0.2), (426, 0.45), (376, 0.62), (270, 0.8), (106, 0.92), (0, 1)
        ]
        /// この長さのグラデーションの点（0〜1 の位置）。1:1（560）は d > 376 の柔らかい所だけを縮め、字の所の濃さは同じ
        var stops: [(location: CGFloat, alpha: CGFloat)] {
            let length = fadeLength
            let firm: CGFloat = 376
            return Self.stopsByDistance.map { point in
                var d = point.distance
                if d > firm, length < 710 { d = firm + (d - firm) * (length - firm) / (710 - firm) }
                return (location: 1 - d / length, alpha: point.alpha)
            }
        }
        /// 撮影情報の3つの欄（左端からの位置・幅）。右端は本文の右端（2026-11-14: 余白 72 に合わせて詰めた）
        static let exifCells: [(x: CGFloat, width: CGFloat)] = [(0, 310), (330, 330), (680, 256)]

        // 左: 地名（明朝）・市区町村（真鍮）・撮影者・撮影情報
        static let placeFontSize: CGFloat = 96
        static let placeMinimumFontSize: CGFloat = 52
        var placeTop: CGFloat { base - 366 }
        var subPlaceTop: CGFloat { base - 246 }
        static let subPlaceFontSize: CGFloat = 36
        var authorTop: CGFloat { base - 186 }
        static let avatarSize: CGFloat = 64
        static let nameFontSize: CGFloat = 26
        static let usernameFontSize: CGFloat = 21
        /// 撮影情報の行の縦の中心（地図の下端より下）
        var exifCenterY: CGFloat { base - 90 }
        static let exifFontSize: CGFloat = 20
        static let exifSymbolSize: CGFloat = 26
    }

    // MARK: - 展示札型の寸法

    /// 「展示札」型（2026-11-06・見本 S2）。上に写真、下に作品札のような札（地名・撮影者・ラベルつきの撮影情報の表・地図）。
    /// 余白は 60 の線にそろえる。9:16 は下の 75 を空ける（Instagram の返信欄）。
    struct LabelLayout {
        static let width: CGFloat = 1080
        /// 2026-11-14: 60 → 72（`Layout.margin`）
        static let margin: CGFloat = Layout.margin
        static var contentLeft: CGFloat { margin }
        static var contentRight: CGFloat { width - margin }
        /// 2026-11-14: 112 → 176（帯の型と同じ。画素で一文の上端が 40px＝3.7% だった）
        static let header: CGFloat = Layout.header
        /// 見出しの縦の中心（額縁の内側と写真の真ん中）
        static var headerCenter: CGFloat { (15 + header) / 2 }
        /// 基準線から一番下の字（表の値）の下端まで（画素で測った 104）
        static let contentBelowBase: CGFloat = 104

        let height: CGFloat
        let base: CGFloat
        let labelHeight: CGFloat
        let topShift: CGFloat

        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Self.width / CGFloat(ratio.rawValue)
            // 9:16 は表の下端がストーリーの下の帯（20%）の上に来る所（2026-11-14: 75 では下端から 16.6% だった）
            base = ratio == .story ? Layout.storyTextBottom + Self.contentBelowBase : height
            labelHeight = ratio == .square ? 420 : 450
            topShift = Layout.topShift(ratio)
        }
        var headerCenterY: CGFloat { Self.headerCenter + topShift }
        var photoBottom: CGFloat { base - labelHeight }
        var photoRect: CGRect {
            CGRect(x: Self.margin, y: Self.header + topShift, width: Self.width - Self.margin * 2,
                   height: photoBottom - Self.header - topShift)
        }
        var eyebrowTop: CGFloat { photoBottom + 44 }
        var placeTop: CGFloat { photoBottom + 68 }
        static let placeFontSize: CGFloat = 60
        static let placeMinimumFontSize: CGFloat = 36
        var ruleY: CGFloat { photoBottom + 148 }
        var authorTop: CGFloat { photoBottom + 170 }
        var tableTop: CGFloat { photoBottom + 260 }
        /// 表の値の最大の高さ（22 の字で2行）
        static let tableValueHeight: CGFloat = 60
        /// 左の列（地名・罫線・撮影者・表）の幅。右は地図
        /// 2026-11-14: 620 → 608（余白 72 に合わせる。地図の左端 704 の 24 手前まで）
        static let leftColumnWidth: CGFloat = 608
        static let mapWidth: CGFloat = 304
        var mapRect: CGRect {
            CGRect(x: Self.contentRight - Self.mapWidth, y: photoBottom + 28, width: Self.mapWidth, height: 300)
        }
        /// 表の3列の左端と幅（ラベル CAMERA / LENS / EXPOSURE）
        /// 2026-11-14: 余白 72 に合わせて 12 右へ（60・268・476 → 72・280・488）。列の間の縦罫は `tableDividerXs`
        static let tableColumns: [(x: CGFloat, width: CGFloat)] = [(72, 180), (280, 180), (488, 180)]
        static let tableDividerXs: [CGFloat] = [260, 468]
        /// 表の中身が終わる縦の位置（下の余白 60 より上に収まる）
        var tableBottom: CGFloat { tableTop + 26 + Self.tableValueHeight }
    }

    // MARK: - 表紙型の寸法

    /// 「表紙」型（2026-11-06・見本 F5）。写真を上から全面に敷き、下の 250 は黒一色。写真の下 340 を黒へ溶かし、
    /// その途中に地名（大きな明朝）をまたがせる。額縁は載せない（写真の上は白だけ・真鍮は黒い地の上だけ）。
    struct CoverLayout {
        static let width: CGFloat = 1080
        /// 2026-11-14: 60 → 72（`Layout.margin`）
        static let margin: CGFloat = Layout.margin
        static var contentLeft: CGFloat { margin }
        static var contentRight: CGFloat { width - margin }
        /// 基準線から一番下の字（撮影者のアバター）の下端まで（画素で測った 115）
        static let contentBelowBase: CGFloat = 115
        let height: CGFloat
        let base: CGFloat
        let topShift: CGFloat

        init(ratio: SignatureShareCardRenderer.Ratio) {
            height = Self.width / CGFloat(ratio.rawValue)
            // 9:16 はストーリーの下の帯（20%）の上（2026-11-14: 75 では下端から 17.6% だった）
            base = ratio == .story ? Layout.storyTextBottom + Self.contentBelowBase : height
            topShift = Layout.topShift(ratio)
        }
        var headerCenterY: CGFloat { Layout.headerCenter + topShift }
        static let blackHeight: CGFloat = 250
        static let fadeLength: CGFloat = 340
        /// 表紙の型のグラデーションの形（2026-11-14 判断）。前はフェードの型と同じ `FadeLayout.fadeStops` で、
        /// 明朝の撮影地（112pt・枠の上端は写真の下端の 182 上＝グラデーションの 46%）の所が黒 47% しかなく、
        /// 白い写真の上の明暗の比が 4.67:1（run 1296・下限 4.5 のすぐ上）だった。
        /// 字の枠の上端（46%）で黒 75% にし、見出しを 7:1 以上に（白い写真の上で約 9:1）。長さ 340 と点の数は同じで、境目は見せない
        static let fadeStops: [(location: CGFloat, alpha: CGFloat)] = [
            (0, 0), (0.06, 0.05), (0.16, 0.18), (0.28, 0.40), (0.40, 0.64), (0.46, 0.75), (0.7, 0.92), (1, 1)
        ]
        /// 撮影地の枠の上端がグラデーションのどこか（0〜1）
        var placeFadeLocation: CGFloat { (placeTop - fadeTop) / Self.fadeLength }
        var photoBottom: CGFloat { base - Self.blackHeight }
        var fadeTop: CGFloat { photoBottom - Self.fadeLength }
        var placeTop: CGFloat { photoBottom - 182 }
        static let placeFontSize: CGFloat = 112
        static let placeMinimumFontSize: CGFloat = 56
        static let leftColumnWidth: CGFloat = 660
        var subPlaceTop: CGFloat { photoBottom - 48 }
        static let subPlaceFontSize: CGFloat = 40
        /// 地図（右端は写真の右端）。上はグラデーションの中・下は黒の上。
        /// 2026-11-14: 上端（写真の下端の 220 上・黒 35%）で真鍮の線の明暗の比が 1.42〜1.54（画素）だった。
        /// 写真の上は白だけ（板）なので白で描き、黒 69% 以上の所（写真の下端の 120 上）から始める
        static let mapWidth: CGFloat = 260
        var mapRect: CGRect {
            CGRect(x: Self.contentRight - Self.mapWidth, y: photoBottom - 120, width: Self.mapWidth, height: 250)
        }
        var authorTop: CGFloat { photoBottom + 70 }
        /// 撮影情報の2行（撮影者の右）
        static let exifX: CGFloat = 430
        /// 2026-11-14: 320 → 306（地図の左端 748 の 12 手前まで）
        static let exifWidth: CGFloat = 306
        var exifTop: CGFloat { photoBottom + 78 }
    }

    // MARK: - 残す島

    /// 2つの島がこれより近ければ「つながっている」とみなす（owner 了承の 60km）
    static let islandGapKm: Double = 60

    /// 経度を撮った場所の側へそろえる。±180° をまたぐ国（ロシア・フィジー）が
    /// 360° 幅に伸びないよう、輪ごとに隣の頂点へつなげて開く。
    static func unwrap(_ rings: [[[Double]]], aroundLongitude pinLongitude: Double) -> [[[Double]]] {
        rings.map { ring -> [[Double]] in
            guard let first = ring.first, first.count == 2 else { return ring }
            var previous = first[0] + 360 * ((pinLongitude - first[0]) / 360).rounded()
            return ring.enumerated().map { index, point in
                guard point.count == 2 else { return point }
                if index == 0 { return [previous, point[1]] }
                let unwrapped = point[0] + 360 * ((previous - point[0]) / 360).rounded()
                previous = unwrapped
                return [unwrapped, point[1]]
            }
        }
    }

    /// 開いた輪の中に点があるか（偶奇の規則）
    static func ringContains(_ ring: [[Double]], longitude x: Double, latitude y: Double) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if a.count == 2, b.count == 2, (a[1] > y) != (b[1] > y),
               x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0] {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// 2点の距離（km）。60km を見分けるだけなので正距円筒の近似で足りる
    static func distanceKm(_ a: [Double], _ b: [Double]) -> Double {
        let latitude = (a[1] + b[1]) / 2 * .pi / 180
        let dx = (a[0] - b[0]) * cos(latitude) * 111.32
        let dy = (a[1] - b[1]) * 110.57
        return (dx * dx + dy * dy).squareRoot()
    }

    /// 面積（緯度で経度を縮めた平面の上で）
    private static func area(_ ring: [[Double]], longitudeScale: Double) -> Double {
        guard ring.count >= 3 else { return 0 }
        var sum = 0.0
        var j = ring.count - 1
        for i in ring.indices {
            sum += ring[j][0] * longitudeScale * ring[i][1] - ring[i][0] * longitudeScale * ring[j][1]
            j = i
        }
        return abs(sum) / 2
    }

    /// 地図に収める輪の番号。`rings` は `unwrap` 済み。
    ///
    /// 撮った場所を含む島（無ければいちばん近い島）と一番大きい陸から始め、
    /// 60km 以内の島を次々に足す。日本の本州で撮れば小笠原・沖ノ鳥島・南鳥島が外れ、
    /// 沖縄で撮れば沖縄が残る。フランスは海外県が、米国は（ハワイで撮らなければ）ハワイとアラスカが外れる。
    /// 重い総当たりはしない: 外接矩形を 60km 広げても重ならない輪は比べず、
    /// 比べるときも相手の矩形の近くの頂点だけを比べる。
    static func focusRingIndices(_ rings: [[[Double]]], latitude: Double, longitude: Double) -> [Int] {
        let usable = rings.indices.filter { rings[$0].count >= 3 }
        guard !usable.isEmpty else { return [] }
        let bounds = rings.map { Bounds([$0]) }
        var seeds = usable.filter { ringContains(rings[$0], longitude: longitude, latitude: latitude) }
        if seeds.isEmpty {
            let pin = [longitude, latitude]
            // 輪ごとに1回だけ測る（比べるたびに測り直さない・2026-11-04 確かめ役の指摘）
            var nearest: (index: Int, km: Double)?
            for index in usable {
                var best = Double.infinity
                for point in rings[index] where point.count == 2 {
                    best = min(best, distanceKm(point, pin))
                }
                if best < (nearest?.km ?? .infinity) { nearest = (index, best) }
            }
            if let nearest { seeds = [nearest.index] }
        }
        let longitudeScale = max(0.2, cos(latitude * .pi / 180))
        var largest: (index: Int, area: Double)?
        for index in usable {
            let size = area(rings[index], longitudeScale: longitudeScale)
            if size > (largest?.area ?? -1) { largest = (index, size) }
        }
        if let largest { seeds.append(largest.index) }
        var kept = Set(seeds)
        var queue = Array(kept)
        let latitudeMargin = islandGapKm / 110.57
        while let current = queue.popLast() {
            guard let a = bounds[current] else { continue }
            for index in usable where !kept.contains(index) {
                guard let b = bounds[index] else { continue }
                let widest = max(abs(a.south), abs(a.north), abs(b.south), abs(b.north))
                let longitudeMargin = islandGapKm / (111.32 * max(0.05, cos(widest * .pi / 180)))
                guard b.west <= a.east + longitudeMargin, b.east >= a.west - longitudeMargin,
                      b.south <= a.north + latitudeMargin, b.north >= a.south - latitudeMargin else { continue }
                if isNear(rings[current], rings[index], a, b,
                          longitudeMargin: longitudeMargin, latitudeMargin: latitudeMargin) {
                    kept.insert(index)
                    queue.append(index)
                }
            }
        }
        return kept.sorted()
    }

    private static func isNear(_ ringA: [[Double]], _ ringB: [[Double]], _ a: Bounds, _ b: Bounds,
                               longitudeMargin: Double, latitudeMargin: Double) -> Bool {
        // 湖や飛び地のような内側の輪は、外の輪から遠くても同じ陸として残す
        if let first = ringB.first, first.count == 2,
           ringContains(ringA, longitude: first[0], latitude: first[1]) { return true }
        if let first = ringA.first, first.count == 2,
           ringContains(ringB, longitude: first[0], latitude: first[1]) { return true }
        let nearA = ringA.filter { $0.count == 2
            && b.contains(longitude: $0[0], latitude: $0[1], margin: max(longitudeMargin, latitudeMargin)) }
        guard !nearA.isEmpty else { return false }
        let nearB = ringB.filter { $0.count == 2
            && a.contains(longitude: $0[0], latitude: $0[1], margin: max(longitudeMargin, latitudeMargin)) }
        for p in nearA {
            for q in nearB where distanceKm(p, q) < islandGapKm { return true }
        }
        return false
    }

    // MARK: - 収め方

    /// 収める範囲を枠に入れる縮尺と置き方（緯度で経度を縮めた正距円筒）
    struct Projection {
        let bounds: Bounds
        let rect: CGRect
        let longitudeScale: Double
        let scale: Double

        init(bounds: Bounds, rect: CGRect, inset: CGFloat = 8) {
            self.bounds = bounds
            self.rect = rect
            longitudeScale = max(0.2, cos(((bounds.south + bounds.north) / 2) * .pi / 180))
            let spanX = max((bounds.east - bounds.west) * longitudeScale, 0.01)
            let spanY = max(bounds.north - bounds.south, 0.01)
            scale = min(Double(rect.width - inset * 2) / spanX, Double(rect.height - inset * 2) / spanY)
        }

        func point(longitude: Double, latitude: Double) -> CGPoint {
            CGPoint(x: Double(rect.midX) + (longitude - (bounds.west + bounds.east) / 2) * longitudeScale * scale,
                    y: Double(rect.midY) - (latitude - (bounds.south + bounds.north) / 2) * scale)
        }
    }

    /// 国の輪郭を撮った場所に合わせて開き、収める輪と縮尺を決める
    static func focus(_ shape: Shape, latitude: Double, longitude: Double,
                      in rect: CGRect) -> (rings: [[[Double]]], projection: Projection)? {
        let rings = unwrap(shape.r, aroundLongitude: longitude)
        let kept = focusRingIndices(rings, latitude: latitude, longitude: longitude)
        guard let bounds = Bounds(kept.map { rings[$0] }) else { return nil }
        return (rings, Projection(bounds: bounds, rect: rect))
    }

    // MARK: - 塗る県

    /// 撮影地の文字（`LocationMatch.shareCardDisplay` の「千葉県（市原市）」など）から県を選ぶ。
    ///
    /// 2026-11-04 判断: 県は**カードに出す撮影地の文字**で決める。ピンは 0.5° に丸めた座標
    /// （`approximateShareCoordinate`）なので、県の境の近くでは隣の県に入る。丸める前の座標は
    /// SNS に出さない約束なので、描く側に渡さない。文字に 47 都道府県の名前がそのまま無ければ塗らない
    /// （「イヴリーヌ県」のような海外の県を拾わないよう、末尾の「県」では見ない）。
    static func prefectureName(in location: String?) -> String? {
        guard let location else { return nil }
        let separators = CharacterSet(charactersIn: "（）()、，,・ 　/")
        let parts = location.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let japanese = parts.first(where: { RegionList.prefectures.contains($0) }) { return japanese }
        // 英語の環境の撮影地（"Kyoto"・"Miyagi Prefecture"・"Hyōgo Prefecture"）。
        // 「,」で区切った欠片ごとに英語名の表で引く（2026-11-04 確かめ役の指摘）
        let pieces = location.components(separatedBy: CharacterSet(charactersIn: "（）()、，,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return pieces.lazy.compactMap { prefecture(english: $0) }.first
    }

    /// 英語の県名（JIS の順・RegionList.prefectures と同じ並び）
    static let englishPrefectures = [
        "Hokkaido", "Aomori", "Iwate", "Miyagi", "Akita", "Yamagata", "Fukushima",
        "Ibaraki", "Tochigi", "Gunma", "Saitama", "Chiba", "Tokyo", "Kanagawa",
        "Niigata", "Toyama", "Ishikawa", "Fukui", "Yamanashi", "Nagano", "Gifu",
        "Shizuoka", "Aichi", "Mie", "Shiga", "Kyoto", "Osaka", "Hyogo",
        "Nara", "Wakayama", "Tottori", "Shimane", "Okayama", "Hiroshima", "Yamaguchi",
        "Tokushima", "Kagawa", "Ehime", "Kochi", "Fukuoka", "Saga", "Nagasaki",
        "Kumamoto", "Oita", "Miyazaki", "Kagoshima", "Okinawa",
    ]

    /// 英語の県名 → 和文の県名。"Kyoto"・"Kyoto Prefecture"・"Hyōgo"・"Tokyo Metropolis" を受ける
    /// （長音の記号と大文字小文字は落として比べる）。それ以外は nil
    static func prefecture(english raw: String) -> String? {
        var name = raw.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespaces)
        for suffix in [" prefecture", " metropolis"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        guard let index = englishPrefectures.firstIndex(where: { $0.lowercased() == name }) else { return nil }
        return RegionList.prefectures[index]
    }

    /// 塗る県の形。文字と丸めた位置が食い違う（県の外接矩形から 1° 以上離れている）ときは塗らない
    static func prefectureShape(named name: String?, among prefectures: [Shape],
                                latitude: Double, longitude: Double) -> Shape? {
        guard let name, let shape = prefectures.first(where: { $0.n == name }),
              let bounds = Bounds(shape.r),
              bounds.contains(longitude: longitude, latitude: latitude, margin: 1) else { return nil }
        return shape
    }

    // MARK: - 同梱の輪郭

    static func loadShapes(resource: String, bundle: Bundle = .main) -> [Shape] {
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([Shape].self, from: data) else { return [] }
        return result
    }
}
