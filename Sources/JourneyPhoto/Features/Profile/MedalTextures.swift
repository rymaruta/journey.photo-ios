import Foundation
import UIKit

// メダルを手に取って回す画面（`MedalViewerView`）の貼り絵。
//
// **SwiftUI を読まない。** 描画の `UIColor` は UIKit の側を使う（SwiftUI と両方を読むと、
// Linux の模型では名前が割れる・`TripBookCardRenderer` と同じ形）

// MARK: - 貼り絵の寸法（画面に依らない・テストで見張る）

/// 硬貨の寸法と、表・裏・縁の貼り絵の置き方。
///
/// 円柱の面には四角い絵の内接円が貼られる（SceneKit の平面の角を半径いっぱいに丸めて円にする）。
/// だから**絵の円の部分が四角いっぱいになるよう拡大して描く**（円の外の余白・後光は切り落とす）
enum MedalTextureLayout {
    /// 貼り絵の一辺（px）。画面に出る硬貨は最大 360pt＝3倍で約 1080px
    static let textureSide: Double = 1024

    /// 裏の絵（`reverse-<metal>.png`）のうち、硬貨の円が占める割合（素材を測って 0.915）
    static let reverseDiscRatio: Double = 0.915

    /// 板の基準: 300pt の面で、無料のメダルの円の半径は 147.6
    static let boardDiscRadius: Double = 147.6
    /// 硬貨の厚み（板: 18pt）。半径に対する比で持つ
    static let thicknessPerRadius: Double = 18 / boardDiscRadius

    /// 裏に重ねる名前と日付の中心（板: 中心から下へ +86 / +102・300pt の面で）と字の大きさ（16 / 11）
    static let nameOffset: Double = 86
    static let dateOffset: Double = 102
    static let nameFont: Double = 16
    static let dateFont: Double = 11
    /// 名前に使える幅（円の直径に対する割合）。はみ出す名前は縮め、それでも長ければ切る
    static let nameMaxWidth: Double = 0.62

    /// 縁の帯（`edge-<metal>.png`）は 858pt 分の長さ。円周にこの回数だけ繰り返して巻く
    static let edgeStripLength: Double = 858

    /// 画面の硬貨の一辺（pt）。左右に 20pt ずつ空け、大きすぎない
    static func coinSide(screenWidth: Double) -> Double {
        max(160, min(screenWidth - 40, 360))
    }

    /// 初期ユーザーの後光の一辺（硬貨の 1.3 倍）。**画面の幅を超える**（430pt の画面で 468pt）ので、
    /// 組みの大きさに効かせない（`MedalViewerView` は硬貨の背景に置く）
    static func haloSide(coin: Double) -> Double { coin * 1.3 }

    /// 絵の円が `side` の四角いっぱいになる描き方（中心に置いて拡大する）
    static func fillRect(discRatio: Double, side: Double = textureSide) -> CGRect {
        let drawn = side / discRatio
        let origin = (side - drawn) / 2
        return CGRect(x: origin, y: origin, width: drawn, height: drawn)
    }

    /// 板の 300pt の面の長さを、貼り絵の px に（円の半径 147.6 が貼り絵の半分）
    static func boardToTexture(_ value: Double, side: Double = textureSide) -> Double {
        value * (side / 2) / boardDiscRadius
    }

    /// 名前・日付の中心の高さ（貼り絵の上から）
    static func nameCenterY(side: Double = textureSide) -> Double { side / 2 + boardToTexture(nameOffset, side: side) }
    static func dateCenterY(side: Double = textureSide) -> Double { side / 2 + boardToTexture(dateOffset, side: side) }

    /// 名前の字の大きさ。**幅に収まらなければ縮める**（板の 7 割まで）
    static func nameFontSize(textWidthAtBase: Double, side: Double = textureSide) -> Double {
        let base = boardToTexture(nameFont, side: side)
        let limit = side * nameMaxWidth
        guard textWidthAtBase > limit, textWidthAtBase > 0 else { return base }
        return max(base * 0.7, base * limit / textWidthAtBase)
    }

    /// 縁の帯の繰り返しの回数（円周 ÷ 帯の長さ）。半径は板の 300pt の面で
    static func edgeRepeat(discRadius: Double = boardDiscRadius) -> Double {
        2 * Double.pi * discRadius / edgeStripLength
    }
}

// MARK: - 貼り絵を描く

/// 表・裏・縁の貼り絵。**重くないので画面の処理で描く**（1024px を2枚・数十ms）
enum MedalTextures {

    struct Faces {
        let front: UIImage?
        let back: UIImage?
        let edge: UIImage?
        let edgeRepeat: Double
        /// 金属（光の映り込みの色を決める）
        var metal: BadgeCatalog.Metal = .silver
    }

    static func make(badge: EarnedBadge, ownerName: String) -> Faces {
        let metal = BadgeCatalog.metal(badge.key, tier: badge.tier)
        let front = UIImage(named: BadgeCatalog.largeImage(badge.key, tier: badge.tier)).map {
            disc($0, ratio: BadgeCatalog.discRatio(badge.key))
        }
        let back = UIImage(named: metal.reverseImage).map {
            reverse($0, name: ownerName, date: BadgeCatalog.awardDate(badge.at))
        }
        return Faces(front: front, back: back, edge: UIImage(named: metal.edgeImage),
                   edgeRepeat: MedalTextureLayout.edgeRepeat(), metal: metal)
    }

    private static func renderer() -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        // 倍率は 1（端末の 3x で9倍の画素にしない・`TripBookCardRenderer` と同じ）
        format.scale = 1
        let side = MedalTextureLayout.textureSide
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    }

    /// 表: 円の部分が四角いっぱいになるよう拡大（後光・余白は切り落とす）
    static func disc(_ image: UIImage, ratio: Double) -> UIImage {
        renderer().image { _ in
            image.draw(in: MedalTextureLayout.fillRect(discRatio: ratio))
        }
    }

    /// 裏: 金属の絞り羽根に、名前（明朝）と日付（等幅の数字）を重ねる
    static func reverse(_ image: UIImage, name: String, date: String?) -> UIImage {
        let side = MedalTextureLayout.textureSide
        // 板の文字の色（淡い真鍮）
        let gold = UIColor(red: 233 / 255, green: 207 / 255, blue: 150 / 255, alpha: 1)
        return renderer().image { _ in
            image.draw(in: MedalTextureLayout.fillRect(discRatio: MedalTextureLayout.reverseDiscRatio))

            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let base = MedalTextureLayout.boardToTexture(MedalTextureLayout.nameFont)
                let measure = font(display: base)
                let width = Double((trimmed as NSString).size(withAttributes: [.font: measure]).width)
                let size = MedalTextureLayout.nameFontSize(textWidthAtBase: width)
                drawCentered(trimmed, font: font(display: size), color: gold, kern: 0,
                             centerY: MedalTextureLayout.nameCenterY(), maxWidth: side * MedalTextureLayout.nameMaxWidth)
            }
            if let date {
                let size = MedalTextureLayout.boardToTexture(MedalTextureLayout.dateFont)
                drawCentered(date, font: UIFont.monospacedDigitSystemFont(ofSize: size, weight: .medium),
                             color: gold.withAlphaComponent(0.8), kern: size * 0.16,
                             centerY: MedalTextureLayout.dateCenterY(), maxWidth: side)
            }
        }
    }

    private static func font(display size: Double) -> UIFont {
        UIFont(name: JPFont.displayName, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
    }

    private static func drawCentered(_ text: String, font: UIFont, color: UIColor, kern: Double,
                                     centerY: Double, maxWidth: Double) {
        let side = MedalTextureLayout.textureSide
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        var shown = text
        // 縮めても収まらない名前は末尾を「…」にする（円の外へはみ出させない）
        while shown.count > 1,
              Double((shown as NSString).size(withAttributes: attributes).width) > maxWidth {
            shown = String(shown.dropLast(2)) + "…"
        }
        let size = (shown as NSString).size(withAttributes: attributes)
        let point = CGPoint(x: (side - Double(size.width)) / 2, y: centerY - Double(size.height) / 2)
        (shown as NSString).draw(at: point, withAttributes: attributes)
    }
}

// MARK: - 凹凸（法線の絵）

/// 硬貨の面の傾きを決める法線の絵（normal map）を作る（2026-10-09・2026-10-14 見直し）。
///
/// 絵を平らな板に貼っただけだと、回しても光が面を流れず、のっぺり見える（owner:
/// 「3D回転させた時の立体感たりない・表も裏ものっぺりしてる」）。そこで**面を少しふくらませる**
/// （本物のメダルのように中心が高い）。回すと光が面を横切る。
///
/// **浮き彫りは「ほんの少し」だけ**（2026-10-14 owner「回転した時に表と裏があまりにも凹凸感なさすぎて、
/// 画像貼っただけののっぺり…ほんの少しだけ凹凸感欲しい」）。10-09 に絵の明るさをそのまま高さにした
/// ときは文字や網目まで盛り上がってざらつき、owner が「少し気持ち悪い」と言った（そのときの割合は 1）。
/// 今回は次の4つで、印や文字の**大きな形だけ**が盛り上がるようにする:
/// - 明るさを高さに使う割合を控えめに（`faceRelief` × 強さ）
/// - ぼかしを広くして（半径 3 を3回・σ≈3.5px）細かい網目を消す（`faceBlurRadius`）
/// - ゆるい傾き（地の網目の濃淡）は捨てる（`reliefFloor`）。強さを上げても網目がぎらつかない
/// - 傾きに上限を付ける（`maxReliefSlope`）。文字の縁の急な所が光ってぎらつかない
///
/// それに加え、**縁の内側に面取り**（`bevelWidth`・`bevelDepth`）を付ける。外へ向かって下がる斜面で、
/// 回す向きによって光る側と陰る側が入れ替わる。
///
/// 強さは **`amount` の1つで調整する**。浮き彫りの割合と網目を捨てる幅は強さに比例、傾きの上限と面取りの
/// 幅・深さは強さの平方根に比例（強くしても急になりすぎない）。0 にすると前の作り（ふくらみだけ）に戻る。
/// **既定は 2.5**（2026-10-14 owner が選んだ。Mac run 427: 1 では前の作りと見分けがつかなかった・平均の差 6.5/255。
/// run 430: 4・6 ではピンや星のまわりににじみが出た）。比べる試作（https://claude.ai/artifact/C7gyZEE2VzgMqcMnZcQvvR）
/// で owner が選んだ「B（ふくらみ・控えめな映り込み）」の光と映り込みはそのまま。
///
/// **画像の型を読まない**（数の配列だけ）ので Linux のテストで見張れる
enum MedalRelief {
    /// 法線の絵の一辺（px）。貼り絵（1024）の半分で足りる（光の具合はなめらかなので）
    static let side = 512
    /// 凹凸の強さ（大きいほど傾く）
    static let strength: Double = 1.1
    /// 面のふくらみ（中心と縁の高さの差・明るさ 0〜1 と同じ物差し）
    static let dome: Double = 0.22
    /// 縁の帯の凹凸の強さ（ギザの溝に光が乗る程度）
    static let edgeStrength: Double = 0.8

    /// 🔴 **浮き彫りと面取りの強さ（この1つで調整する）。** 2.5＝既定（owner が選んだ・2026-10-14）。
    /// 0＝前の作り（ふくらみだけ・凹凸なし）。候補は 2.5・4・6 を撮り比べた（Mac run 430）:
    /// 4 からはピンや星のまわりに灰色のにじみ、6 では黒い輪が出た。1 は前の作りと見分けがつかなかった
    static let amount: Double = 2.5
    /// 「視差効果を減らす」の人は半分にする（回すと動く光と陰を弱める）
    static let reducedMotionScale: Double = 0.5

    /// 表と裏で明るさを高さに使う割合（`amount` が 1 のとき・比例）。10-09 の 1 そのままは強すぎた
    static let faceRelief: Double = 0.05
    /// 表と裏の浮き彫りの傾きの上限（`amount` が 1 のとき・平方根に比例）。
    /// tan で 0.3 ≈ 17°、既定の 2.5 で 0.47 ≈ 25°、4 で 0.6 ≈ 31°、6 で 0.73 ≈ 36°
    static let maxReliefSlope: Double = 0.3
    /// これより緩い傾きは捨てる（`amount` が 1 のとき・比例）。地の網目は 0.04 以下、印や文字の縁は 0.3〜1
    static let reliefFloor: Double = 0.06
    /// 縁の面取りの幅（半径に対する割合）と深さ（`amount` が 1 のとき・平方根に比例・明るさ 0〜1 と同じ物差し）。
    /// 幅は `maxBevelWidth` まで。傾きは強さに依らずほぼ一定（約43°）で、幅が広がって見えやすくなる
    static let bevelWidth: Double = 0.035
    static let bevelDepth: Double = 0.02
    static let maxBevelWidth: Double = 0.075

    /// ぼかしの半径（縁の帯: 箱ぼかしを3回重ねて σ≈2.4px）
    static let blurRadius = 2
    /// 表と裏のぼかしの半径（σ≈3.5px・細かい網目や文字の画を消し、大きな形だけ残す）
    static let faceBlurRadius = 3
    static let blurPasses = 3

    /// 表・裏の凹凸の割合をまとめたもの
    struct Face: Equatable {
        /// 明るさを高さに使う割合
        let relief: Double
        /// 浮き彫りの傾きの上限
        let maxSlope: Double
        /// これより緩い浮き彫りの傾きは捨てる
        let floor: Double
        /// 面取りの幅と深さ
        let bevelWidth: Double
        let bevelDepth: Double
    }

    /// 強さ（`amount`）から表・裏の割合を決める。0 以下は凹凸なし（ふくらみだけ）
    static func face(amount: Double) -> Face {
        let a = max(0, amount)
        let root = a.squareRoot()
        return Face(relief: faceRelief * a, maxSlope: maxReliefSlope * root, floor: reliefFloor * a,
                    bevelWidth: a > 0 ? min(maxBevelWidth, bevelWidth * root) : 0,
                    bevelDepth: bevelDepth * root)
    }

    /// いま使う強さ。「視差効果を減らす」なら弱める
    static func effectiveAmount(reduceMotion: Bool, base: Double = MedalRelief.amount) -> Double {
        reduceMotion ? base * reducedMotionScale : base
    }

    /// 明るさ（0〜255・行ごと・上から）から、法線の絵（RGBA・1画素4バイト）を作る。
    /// `relief` は明るさを高さに使う割合（0 なら明るさは見ず、ふくらみだけ）。
    ///
    /// 法線は「右＝+x・上＝+y・手前＝+z」で、`色 = 法線 × 0.5 + 0.5`（緑が上向き）。
    /// `wrapsX` は縁の帯のように左右がつながる絵（端の傾きを向こう側の画素で計る）。
    /// `dome` を 0 にするとふくらみを付けない。`maxReliefSlope` を渡すと、明るさから起こした傾きを
    /// その値で頭打ちにする（なめらかに・tanh）。`bevelDepth` が 0 より大きいと、円の外側
    /// `bevelWidth` の幅に外へ下がる面取りを付ける
    static func normalMap(luminance: [UInt8], width: Int, height: Int,
                          strength: Double, dome: Double, relief: Double = 1,
                          wrapsX: Bool = false, blurRadius: Int = MedalRelief.blurRadius,
                          maxReliefSlope: Double? = nil, reliefFloor: Double = 0,
                          bevelWidth: Double = 0, bevelDepth: Double = 0) -> [UInt8] {
        guard width > 2, height > 2, luminance.count == width * height else { return [] }
        // 傾きは画素の差 × 半分の幅（絵の大きさに依らない強さにする）
        let scale = strength * Double(min(width, height)) / 2

        // 明るさから起こす高さ（浮き彫り）
        var lifted = [Double](repeating: 0, count: width * height)
        if relief != 0 {
            lifted = luminance.map { Double($0) / 255 * relief }
            for _ in 0..<blurPasses {
                lifted = boxBlur(lifted, width: width, height: height, radius: blurRadius, wrapsX: wrapsX)
            }
        }
        // 形の高さ（ふくらみ・面取り）
        var shape = [Double](repeating: 0, count: width * height)
        let hasBevel = bevelDepth > 0 && bevelWidth > 0
        if dome != 0 || hasBevel {
            let cx = Double(width - 1) / 2, cy = Double(height - 1) / 2
            let radius = Double(min(width, height)) / 2
            for y in 0..<height {
                for x in 0..<width {
                    let dx = (Double(x) - cx) / radius, dy = (Double(y) - cy) / radius
                    let r2 = dx * dx + dy * dy
                    var value = -dome * r2
                    if hasBevel { value -= bevelDepth * bevelProfile(r: r2.squareRoot(), width: bevelWidth) }
                    shape[y * width + x] = value
                }
            }
        }

        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let up = max(0, y - 1), down = min(height - 1, y + 1)
            for x in 0..<width {
                let left = wrapsX ? (x - 1 + width) % width : max(0, x - 1)
                let right = wrapsX ? (x + 1) % width : min(width - 1, x + 1)
                let dxCount = Double(right > left ? right - left : 2)
                let dyCount = Double(max(1, down - up))
                var rx = (lifted[y * width + right] - lifted[y * width + left]) / dxCount * scale
                var ry = (lifted[down * width + x] - lifted[up * width + x]) / dyCount * scale
                if reliefFloor > 0 {
                    (rx, ry) = deadZone(rx, ry, floor: reliefFloor)
                }
                if let limit = maxReliefSlope {
                    (rx, ry) = softLimit(rx, ry, limit: limit)
                }
                let gx = rx + (shape[y * width + right] - shape[y * width + left]) / dxCount * scale
                let gy = ry + (shape[down * width + x] - shape[up * width + x]) / dyCount * scale
                // 右へ高くなる＝面は左を向く（-x）。下へ高くなる＝面は上を向く（+y）
                var nx = -gx, ny = gy, nz = 1.0
                let length = (nx * nx + ny * ny + nz * nz).squareRoot()
                nx /= length; ny /= length; nz /= length
                let i = (y * width + x) * 4
                out[i] = encode(nx)
                out[i + 1] = encode(ny)
                out[i + 2] = encode(nz)
            }
        }
        return out
    }

    /// 面取りの形: 円の外側 `width` の幅で 0 → 1 へなめらかに（smoothstep）。内側は 0
    static func bevelProfile(r: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        let t = min(1, max(0, (r - (1 - width)) / width))
        return t * t * (3 - 2 * t)
    }

    /// `floor` より緩い傾き（x, y）をなめらかに捨てる（大きさ m を m²/(m²+floor²) 倍・向きは変えない）
    static func deadZone(_ x: Double, _ y: Double, floor: Double) -> (Double, Double) {
        let m2 = x * x + y * y
        guard floor > 0, m2 > 0 else { return (x, y) }
        let f = m2 / (m2 + floor * floor)
        return (x * f, y * f)
    }

    /// 傾き（x, y）の大きさを `limit` でなめらかに頭打ちにする（向きは変えない）
    static func softLimit(_ x: Double, _ y: Double, limit: Double) -> (Double, Double) {
        let magnitude = (x * x + y * y).squareRoot()
        guard magnitude > 1e-12 else { return (x, y) }
        guard limit > 0 else { return (0, 0) }
        let f = limit * tanh(magnitude / limit) / magnitude
        return (x * f, y * f)
    }

    // MARK: 光の向き（回した角度から）

    /// 主な光の位置（左上手前・場面の座標）。`MedalCoinCoordinator` の光と同じ値
    static let keyLight: (x: Double, y: Double, z: Double) = (-2.5, 3, 5)

    /// 硬貨を `yaw`（横）・`pitch`（縦）だけ回したとき、硬貨から見た光の向き（長さ 1）。
    /// SceneKit の `eulerAngles` は 横 → 縦 の順で回す（場面 = Rx(pitch)・Ry(yaw)・硬貨）ので、
    /// 硬貨の側へ戻すには Ry(-yaw)・Rx(-pitch) をかける
    static func lightInCoin(yaw: Double, pitch: Double,
                            light: (x: Double, y: Double, z: Double) = keyLight) -> (x: Double, y: Double, z: Double) {
        let length = (light.x * light.x + light.y * light.y + light.z * light.z).squareRoot()
        guard length > 0 else { return (0, 0, 1) }
        let (lx, ly, lz) = (light.x / length, light.y / length, light.z / length)
        // Rx(-pitch)
        let cp = cos(-pitch), sp = sin(-pitch)
        let y1 = ly * cp - lz * sp, z1 = ly * sp + lz * cp
        // Ry(-yaw)
        let cy = cos(-yaw), sy = sin(-yaw)
        let x2 = lx * cy + z1 * sy, z2 = -lx * sy + z1 * cy
        return (x2, y1, z2)
    }

    /// 法線（硬貨の側）に主な光が当たる明るさ（0〜1・ランバート）
    static func keyShade(normal: (x: Double, y: Double, z: Double), yaw: Double, pitch: Double) -> Double {
        let l = lightInCoin(yaw: yaw, pitch: pitch)
        return max(0, normal.x * l.x + normal.y * l.y + normal.z * l.z)
    }

    private static func encode(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 0.5 + 0.5) * 255).rounded()))
    }

    /// 縦横に分けた箱ぼかし（端は端の画素を伸ばす。`wrapsX` なら左右は向こう側へつなぐ）
    static func boxBlur(_ values: [Double], width: Int, height: Int, radius: Int, wrapsX: Bool) -> [Double] {
        guard radius > 0 else { return values }
        let count = Double(radius * 2 + 1)
        var horizontal = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var sum = 0.0
                for k in -radius...radius {
                    let sx = wrapsX ? ((x + k) % width + width) % width : min(width - 1, max(0, x + k))
                    sum += values[row + sx]
                }
                horizontal[row + x] = sum / count
            }
        }
        var out = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for k in -radius...radius {
                    sum += horizontal[min(height - 1, max(0, y + k)) * width + x]
                }
                out[y * width + x] = sum / count
            }
        }
        return out
    }
}

// MARK: - 見本の向き（画面写真のため・Debug の起動の鍵）

/// 画面写真で硬貨を止めて見せる向きと強さ（`PreviewSession.medalPoses`）。
/// 回さずにこの角度で止め、硬貨を押すと次の向きへ進む
struct MedalPose: Equatable {
    /// 横の回り（ラジアン）。0＝正面
    let yaw: Double
    /// 浮き彫りと面取りの強さ（`MedalRelief.amount` の代わり）
    let amount: Double

    /// `"0:4,0.45:4,1.1:4"`（横の回り:強さ をカンマで区切る）を読む。強さを省くと既定。
    /// 読めない組みは飛ばす。強さは 0〜8 に収める
    static func parse(_ raw: String) -> [MedalPose] {
        raw.split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = parts.first, let yaw = Double(first), yaw.isFinite else { return nil }
            var amount = MedalRelief.amount
            if parts.count > 1 {
                guard let value = Double(parts[1]), value.isFinite else { return nil }
                amount = min(8, max(0, value))
            }
            return MedalPose(yaw: yaw, amount: amount)
        }
    }
}
