import Foundation

// 撮った写真を、木の並びに沿って奥・中・手前の 3 枚の紙に切る（板 CampCapture「切り出す」）。
//
// 🔴 **3 枚に分ける方法は未検証の案**（板の注記・2026-10-18）。2 つを用意して、どちらでも壊れない形にする:
//   1. 前景の型（iOS 17 の `VNGenerateForegroundInstanceMaskRequest`）が取れたら、手前の 1 枚はその型の上の縁
//   2. 奥・中（と、型が取れないときの手前）は**写真の濃さの段**で切る: 霧の森は遠い木ほど白く、近い木ほど黒い。
//      空の明るさから地面の暗さまでを 3 つの段に分け、列ごとに上から見て初めてその段より暗くなる所を稜線にする
//   3. 濃さに差が無い写真（真っ白・真っ暗）は、決まった高さの波で 3 枚にする（`fallback`）
//
// ここは画素の数だけを扱う（Linux でテストできる）。画像を読む・Vision を呼ぶのは `CampCutter`。

/// 切り絵 1 枚（板の `LAY` の 1 つ）。座標は切り抜いた範囲の幅を 360 とした単位
struct CampCutLayer: Equatable, Codable, Sendable {
    /// 稜線の点（u は 0〜360 を 6 ずつ 61 点、v はこの層の上の端からの下がり）
    var points: [CampVec2]
    /// 切り抜いた範囲の上からの、この層の上の端
    var top: Double
    /// この層の高さ（上の端から範囲の下の端まで）
    var height: Double
}

extension CampVec2: Codable {
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(try c.decode(Double.self), try c.decode(Double.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

/// 3 枚の切り絵（奥 0・中 1・手前 2）
struct CampCutLayers: Equatable, Codable, Sendable {
    /// 範囲の幅（板: 360）と高さ（同じ単位）
    var width: Double
    var height: Double
    var layers: [CampCutLayer]
    /// どう切ったか（前景の型・濃さの段・決まった波）
    var method: CampCutMethod

    /// 紙の札の幅（範囲の幅 + 左右 8 ずつ・板の `IW`）
    static let cardWidth = 376.0
    /// 札の余白（写真の外の紙のフチの内側）
    static let margin = 8.0
    /// 紙のフチ（板: 写真の 6.5 px 分。輪郭を 6 外へずらした形を板にする）
    static let rim = 6.0
    /// 稜線の点の間隔
    static let step = 6.0

    /// 札の上の写真の輪郭（稜線 + 下の角の丸み・札の座標）。板の `RP`
    static func photoOutline(_ layer: CampCutLayer) -> [CampVec2] {
        let ih = layer.height + 2 * margin, iw = cardWidth
        return layer.points.map { CampVec2($0.x + margin, $0.y + margin) }
            + [CampVec2(iw - 8, ih - 20), CampVec2(iw - 12, ih - 8), CampVec2(20, ih - 8), CampVec2(8, ih - 20)]
    }

    /// 紙の板の外形（写真の輪郭を紙のフチの分だけ外へ）
    static func rimOutline(_ layer: CampCutLayer) -> [CampVec2] {
        CampGeometry.outset(photoOutline(layer), by: rim)
    }
}

enum CampCutMethod: String, Codable, Sendable {
    /// 手前の 1 枚を前景の型（Vision）で切り、奥・中を濃さの段で切った
    case foregroundMask
    /// 3 枚とも濃さの段で切った
    case luminance
    /// 濃さに差が無く、決まった波で切った
    case fallback
}

/// 濃さの段で 3 枚に切る
enum CampLayerSplit {

    /// 段の深さ（空の明るさ → 地面の暗さの何割まで暗くなったら稜線とみなすか）。奥・中・手前
    static let thresholds: [Double] = [0.2, 0.45, 0.72]
    /// 隣の層との間を最低これだけ空ける（範囲の高さに対する割合）
    static let minGap = 0.06
    /// 濃さの差がこれより小さい写真は、決まった波で切る
    static let minContrast = 0.12
    /// どの層も最低これだけの高さを残す（範囲の高さに対する割合・紙が細くなりすぎない）
    static let minLayerHeight = 0.18
    /// 決まった波の高さ（奥・中・手前・範囲の高さに対する割合）
    static let fallbackTops: [Double] = [0.18, 0.42, 0.62]

    /// 列の数（360 を 6 ずつ → 61 点）
    static var columns: Int { Int(CampCutLayers.cardWidth - 2 * CampCutLayers.margin) / Int(CampCutLayers.step) + 1 }

    /// 切る。`luma` は 0〜1 の明るさ（行ごと・`width` × `height`）。`foreground` は前景の型（同じ大きさ・1 が前景）
    static func split(luma: [Double], width: Int, height: Int, foreground: [Bool]? = nil) -> CampCutLayers {
        let unitW = CampCutLayers.cardWidth - 2 * CampCutLayers.margin
        let unitH = width > 0 ? unitW * Double(height) / Double(width) : unitW * 4 / 3
        guard width > 1, height > 4, luma.count == width * height else {
            return fallback(unitHeight: unitH)
        }
        // 空（上の 15%）の明るさと、地面（全体の暗い 5%）の明るさ
        let skyRows = max(1, height * 15 / 100)
        let sky = percentile(Array(luma[0..<(skyRows * width)]), 0.9)
        let ground = percentile(luma, 0.05)
        let contrast = sky - ground
        guard contrast >= minContrast else { return fallback(unitHeight: unitH) }

        let n = columns
        // 列ごとの明るさ（縦に 3 行ずつならす）
        func column(_ c: Int) -> [Double] {
            let x = min(width - 1, Int((Double(c) / Double(n - 1)) * Double(width - 1)))
            let raw = (0..<height).map { luma[$0 * width + x] }
            return raw.indices.map { y in
                let lo = max(0, y - 1), hi = min(height - 1, y + 1)
                return raw[lo...hi].reduce(0, +) / Double(hi - lo + 1)
            }
        }
        let cols = (0..<n).map(column)
        var tops: [[Double]] = thresholds.map { f in
            let t = sky - contrast * f
            return cols.map { col in
                // 上から 2 行続けて段より暗くなった所
                for y in 0..<(height - 1) where col[y] < t && col[y + 1] < t { return Double(y) }
                return Double(height - 1)
            }
        }
        var method = CampCutMethod.luminance
        // 前景の型があれば、手前の 1 枚はその上の縁（型が無い列は濃さの段のまま）
        if let foreground, foreground.count == width * height {
            var any = false
            for c in 0..<n {
                let x = min(width - 1, Int((Double(c) / Double(n - 1)) * Double(width - 1)))
                if let y = (0..<height).first(where: { foreground[$0 * width + x] }) {
                    tops[2][c] = Double(y)
                    any = true
                }
            }
            if any { method = .foregroundMask }
        }
        // ならす（隣 2 列ずつ）
        tops = tops.map { smooth($0, radius: 2) }
        // 奥 ≤ 中 ≤ 手前（下が大きい）。間を空け、どの層も高さを残す
        let gap = minGap * Double(height)
        let maxTop = Double(height) * (1 - minLayerHeight)
        for c in 0..<n {
            tops[0][c] = min(tops[0][c], maxTop - 2 * gap)
            tops[1][c] = min(max(tops[1][c], tops[0][c] + gap), maxTop - gap)
            tops[2][c] = min(max(tops[2][c], tops[1][c] + gap), maxTop)
        }
        let scale = unitH / Double(height)
        return CampCutLayers(width: unitW, height: unitH,
                             layers: tops.map { layer(fromTops: $0.map { $0 * scale }, unitHeight: unitH) },
                             method: method)
    }

    /// 決まった波で 3 枚（濃さに差が無い写真・読めなかった写真）
    static func fallback(unitHeight: Double) -> CampCutLayers {
        let n = columns
        let layers = fallbackTops.enumerated().map { li, f -> CampCutLayer in
            let tops = (0..<n).map { c -> Double in
                let u = Double(c) / Double(n - 1), k = Double(li)
                let slow: Double = sin(u * Double.pi * (2.2 + k * 0.7) + k * 1.3) * 0.035
                let fast: Double = sin(u * Double.pi * 7.1 + k) * 0.012
                return (f + slow + fast) * unitHeight
            }
            return layer(fromTops: tops, unitHeight: unitHeight)
        }
        return CampCutLayers(width: CampCutLayers.cardWidth - 2 * CampCutLayers.margin, height: unitHeight,
                             layers: layers, method: .fallback)
    }

    /// 稜線の高さ（範囲の上から）から、層の上の端と点を作る（板の `LAY` の形）
    static func layer(fromTops tops: [Double], unitHeight: Double) -> CampCutLayer {
        let top = max(0, (tops.min() ?? 0) - 1)
        let pts = tops.enumerated().map { CampVec2(Double($0.offset) * CampCutLayers.step, (($0.element - top) * 10).rounded() / 10) }
        return CampCutLayer(points: pts, top: top, height: max(1, unitHeight - top))
    }

    static func smooth(_ v: [Double], radius: Int) -> [Double] {
        v.indices.map { i in
            let lo = max(0, i - radius), hi = min(v.count - 1, i + radius)
            return v[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
    }

    static func percentile(_ v: [Double], _ p: Double) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[min(s.count - 1, max(0, Int((Double(s.count - 1) * p).rounded())))]
    }

    /// 明るさ（Rec. 601・板の `lumOf` と同じ重み）
    static func luminance(r: UInt8, g: UInt8, b: UInt8) -> Double {
        (0.3 * Double(r) + 0.59 * Double(g) + 0.11 * Double(b)) / 255
    }
}

/// 撮る画面の四隅の枠と、写真の切り抜く範囲（板 CampCapture の 1 撮る）
enum CampCrop {

    /// 枠（390 × 844 の画面で x 80.4〜309.6・y 351.5〜663.9）を画面の大きさの割合で
    static let frameFraction = (x0: 80.4 / 390, x1: 309.6 / 390, y0: 351.5 / 844, y1: 663.9 / 844)

    static func frame(width: Double, height: Double) -> (x: Double, y: Double, w: Double, h: Double) {
        let f = frameFraction
        return (f.x0 * width, f.y0 * height, (f.x1 - f.x0) * width, (f.y1 - f.y0) * height)
    }

    /// 映像を枠いっぱいに敷いた（aspect fill）ときの、枠に当たる写真の範囲（写真の画素）
    static func photoRect(frame: (x: Double, y: Double, w: Double, h: Double), view: (w: Double, h: Double),
                          photo: (w: Double, h: Double)) -> (x: Double, y: Double, w: Double, h: Double) {
        guard view.w > 0, view.h > 0, photo.w > 0, photo.h > 0 else { return (0, 0, photo.w, photo.h) }
        let scale = max(view.w / photo.w, view.h / photo.h)
        let offX = (view.w - photo.w * scale) / 2, offY = (view.h - photo.h * scale) / 2
        let x = (frame.x - offX) / scale, y = (frame.y - offY) / scale
        let w = frame.w / scale, h = frame.h / scale
        let cx = max(0, min(photo.w - 1, x)), cy = max(0, min(photo.h - 1, y))
        return (cx, cy, max(1, min(photo.w - cx, w)), max(1, min(photo.h - cy, h)))
    }
}
