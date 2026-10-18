import Foundation

/// 手で描く小さな貼り絵（画素の並び。RGBA・上の行から）。**大きさを抑える**（いちばん大きくて 256×128）。
/// 素の Swift なので Linux でも大きさと中身を試験できる。iOS の側（`CamperSceneView`）が `CGImage` にする
struct CamperBitmap: Equatable, Sendable {
    let width: Int
    let height: Int
    var rgba: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        rgba = [UInt8](repeating: 0, count: width * height * 4)
    }

    mutating func set(_ x: Int, _ y: Int, _ c: (Double, Double, Double), _ a: Double = 1) {
        let i = (y * width + x) * 4
        rgba[i] = UInt8(max(0, min(255, (c.0 * 255).rounded())))
        rgba[i + 1] = UInt8(max(0, min(255, (c.1 * 255).rounded())))
        rgba[i + 2] = UInt8(max(0, min(255, (c.2 * 255).rounded())))
        rgba[i + 3] = UInt8(max(0, min(255, (a * 255).rounded())))
    }

    func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3])
    }
}

enum CamperTextures {

    /// 貼り絵の大きさの上限（性能・2026-10-18 判断: 1 枚 256 px まで）
    static let maxSide = 256

    static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }

    /// 決まった乱れ（同じ絵になる）
    private struct Noise {
        var seed: UInt64
        mutating func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((seed >> 33) & 0xFFFF) / 65535
        }
    }

    /// 素材の貼り絵（白〜灰の明るさの絵。色は素材の色を掛ける）
    static func make(_ kind: CamperTextureKind) -> CamperBitmap {
        switch kind {
        case .woodGrain: return woodGrain()
        case .weave: return weave()
        case .solarCells: return solarCells()
        case .brushed: return brushed()
        }
    }

    /// 木目（長い辺に沿う筋・128×64）
    static func woodGrain() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 64)
        var n = Noise(seed: 7)
        let phases = (0..<6).map { _ in n.next() * 6.28 }
        for y in 0..<b.height {
            for x in 0..<b.width {
                let fx = Double(x) / Double(b.width) * 2 * .pi
                var v = 0.0
                for (k, ph) in phases.enumerated() { v += sin(fx * Double(k % 3 + 1) + ph) * 0.6 / Double(k + 1) }
                let line = sin((Double(y) + v * 6) * 0.9)
                let shade = 0.82 + 0.18 * (line * 0.5 + 0.5) - (abs(line) > 0.94 ? 0.12 : 0)
                b.set(x, y, (shade, shade, shade))
            }
        }
        return b
    }

    /// 織り目（3 単位の格子・32×32）
    static func weave() -> CamperBitmap {
        var b = CamperBitmap(width: 32, height: 32)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let over = ((x / 4) + (y / 4)) % 2 == 0
                let thread = over ? 0.92 - Double(y % 4) * 0.03 : 0.82 - Double(x % 4) * 0.03
                b.set(x, y, (thread, thread, thread))
            }
        }
        return b
    }

    /// 太陽電池の升（枠の線 6 列・128×128）
    static func solarCells() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 128)
        let frame = rgb(0xC9CCD1)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let onLine = x % 21 < 1 || y % 18 < 1
                let sheen = 0.9 + 0.1 * Double((x * 7 + y * 3) % 5) / 5
                b.set(x, y, onLine ? frame : (sheen, sheen, sheen))
            }
        }
        return b
    }

    /// 細い筋（アルミ・64×64）
    static func brushed() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 64)
        var n = Noise(seed: 3)
        let rows = (0..<64).map { _ in 0.9 + n.next() * 0.1 }
        for y in 0..<b.height {
            for x in 0..<b.width { b.set(x, y, (rows[y], rows[y], rows[y])) }
        }
        return b
    }

    /// 周りの空（正距円筒・256×128）。上から空・地平線・地面。昼は左上に太陽の柔らかい光
    static func environment(_ mood: CamperMood) -> CamperBitmap {
        var b = CamperBitmap(width: 256, height: 128)
        let s = CamperMaterials.sky(mood)
        let top = rgb(s.top), hor = rgb(s.horizon), gn = rgb(s.groundNear), gf = rgb(s.groundFar)
        for y in 0..<b.height {
            let v = Double(y) / Double(b.height - 1)
            for x in 0..<b.width {
                var c: (Double, Double, Double)
                if v < 0.5 {
                    c = lerp(top, hor, pow(v / 0.5, 1.6))
                } else {
                    c = lerp(gn, gf, (v - 0.5) / 0.5)
                }
                if mood != .night {
                    // 光の箱（左上）と細い縦の光（右）。回すとクロームと塗装の上を流れる
                    let dx = (Double(x) - 92) / 26, dy = (Double(y) - 30) / 20
                    let glow = exp(-(dx * dx + dy * dy)) * (mood == .snow ? 0.5 : 0.7)
                    let ex = (Double(x) - 176) / 5, ey = (Double(y) - 46) / 22
                    let strip = exp(-(ex * ex + ey * ey)) * 0.4
                    c = (min(1, c.0 + glow + strip), min(1, c.1 + glow + strip), min(1, c.2 + glow * 0.95 + strip))
                } else {
                    // 夜は月の小さな光
                    let dx = (Double(x) - 160) / 6, dy = (Double(y) - 26) / 6
                    let moon = exp(-(dx * dx + dy * dy)) * 0.6
                    c = (min(1, c.0 + moon), min(1, c.1 + moon), min(1, c.2 + moon))
                }
                b.set(x, y, c)
            }
        }
        return b
    }

    /// 床（真ん中から外へ透けていく楕円・板の floor）。256×256
    static func floor(_ mood: CamperMood) -> CamperBitmap {
        var b = CamperBitmap(width: 256, height: 256)
        let f = CamperMaterials.floor(mood)
        let a = rgb(f.inner.0), o = rgb(f.outer.0)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let dx = (Double(x) - 127.5) / 127.5, dy = (Double(y) - 127.5) / 127.5
                let r = (dx * dx + dy * dy).squareRoot()
                let c: (Double, Double, Double)
                let alpha: Double
                if r < 0.55 {
                    c = lerp(a, o, r / 0.55)
                    alpha = f.inner.1 + (f.outer.1 - f.inner.1) * (r / 0.55)
                } else {
                    c = o
                    alpha = max(0, f.outer.1 * (1 - (r - 0.55) / 0.45))
                }
                b.set(x, y, c, alpha)
            }
        }
        return b
    }

    /// 車体の下の暗がり（黒の楕円・外へ透ける）。128×64。板の「車体の下の暗がり 0.75」
    static func contactShadow() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let dx = (Double(x) - 63.5) / 63.5, dy = (Double(y) - 31.5) / 31.5
                let r = (dx * dx + dy * dy).squareRoot()
                let alpha = r >= 1 ? 0 : 0.75 * pow(1 - r, 1.4)
                b.set(x, y, (0, 0, 0), alpha)
            }
        }
        return b
    }
}
