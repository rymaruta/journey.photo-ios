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
    struct Noise {
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
        case .glow: return glow()
        case .lampFace: return lampFace()
        case .tailFace: return tailFace()
        case .beam: return beam()
        case .flame: return flame()
        case .roomGlow: return roomGlow()
        case .planks, .chevron, .herringbone, .checkerTiles, .cork, .boards, .birchPly, .darkBoards, .wallpaperStripe,
             .leather, .linenSlub, .knit, .rush, .wicker, .rope, .ovalRings, .runnerWeave, .enamelChip, .castIron, .foliage,
             .clockDial, .windowDay, .windowNight, .matBoard, .photoPlaceholder, .wornWood:
            return CamperRoomTextures.make(kind)
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

    /// 周りの空（正距円筒・256×128）。上から空・地平線・地面。
    ///
    /// 2026-10-18 判断（Mac の絵 run 529: 塗装の映り込みがほとんど感じられない）: 空と地面のなだらかな色の差だけでは
    /// clearCoat に映るものが無い。写真のスタジオと同じく、**くっきりした地平線**（明るい空の下端と暗い地面の境）と、
    /// 縁のはっきりした光の箱（頭の上の大きな箱・左右の縦長の箱）を置く。回すと塗装の面の上を線と箱が流れる
    static func environment(_ mood: CamperMood) -> CamperBitmap {
        var b = CamperBitmap(width: 256, height: 128)
        let s = CamperMaterials.sky(mood)
        let top = rgb(s.top), hor = rgb(s.horizon), gn = rgb(s.groundNear), gf = rgb(s.groundFar)
        /// 縁の柔らかい四角（1 で中・0 で外。縁の幅 `soft` 画素）
        func box(_ x: Double, _ y: Double, _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, soft: Double) -> Double {
            let dx = max(x0 - x, x - x1, 0), dy = max(y0 - y, y - y1, 0)
            return max(0, 1 - (dx * dx + dy * dy).squareRoot() / soft)
        }
        for y in 0..<b.height {
            let v = (Double(y) + 0.5) / Double(b.height)
            for x in 0..<b.width {
                let fx = Double(x) + 0.5, fy = Double(y) + 0.5
                var c: (Double, Double, Double)
                if v < 0.5 {
                    c = lerp(top, hor, pow(v / 0.5, 2.2))
                } else {
                    // 地平線の下は 1.5 画素で暗い地面へ落ちる（映り込みの線がくっきり出る）
                    let edge = min(1, (v - 0.5) * Double(b.height) / 1.5)
                    c = lerp(hor, lerp(gn, gf, (v - 0.5) / 0.5), edge)
                }
                var light = 0.0
                if mood == .night {
                    // 月の小さな光と、地平線の上の薄い街明かりの帯
                    // 月は小さく弱く（run 532: 縁のクロームと塗装に細い光の筋がちらついた）
                    let dx = (fx - 160) / 5, dy = (fy - 26) / 5
                    light = exp(-(dx * dx + dy * dy)) * 0.3
                    light += box(fx, fy, 0, 256, 58, 63, soft: 4) * 0.06
                } else {
                    let k = mood == .snow ? 0.7 : 1.0
                    // 頭の上の大きな光の箱・左右の縦長の箱・地平線の上の細い帯
                    light += box(fx, fy, 70, 186, 6, 24, soft: 3) * 0.9 * k
                    light += box(fx, fy, 20, 34, 24, 56, soft: 2) * 0.75 * k
                    light += box(fx, fy, 150, 162, 22, 56, soft: 2) * 0.65 * k
                    light += box(fx, fy, 216, 236, 30, 54, soft: 2) * 0.5 * k
                }
                c = (min(1, c.0 + light), min(1, c.1 + light), min(1, c.2 + light * 0.97))
                b.set(x, y, c)
            }
        }
        return b
    }

    /// 灯りの溜まり（真ん中が明るく、外へなだらかに消える丸・64×64・白〜黒）。足し合わせる光なので黒は何も足さない。
    /// 2026-10-19: 硬い円に見えた（owner）ので、ガウスの裾で縁まで 0 になめらかに落とす（縁の 1 画素で切れない）
    static func glow() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let dx = (Double(x) - 31.5) / 31.5, dy = (Double(y) - 31.5) / 31.5
                let r2 = dx * dx + dy * dy
                // exp(−4r²) の裾を、縁（r=1）でちょうど 0 になるよう引いて伸ばす
                let edge = exp(-4.0)
                let v = r2 >= 1 ? 0 : max(0, (exp(-4 * r2) - edge) / (1 - edge))
                b.set(x, y, (v, v, v))
            }
        }
        return b
    }

    /// 灯りのレンズの明暗（64×64・白〜灰）。真ん中の芯（いちばん明るい）、反射板の輪 2 本（板 r2.2・r4.2 ／ レンズ 5.6）、
    /// 輪の間は少し暗く、縁へ暗く落ちる。箱のレンズ（角形・方向指示）にも面ごとに 1 枚ずつ貼られる
    static func lampFace() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let dx = (Double(x) - 31.5) / 31.5, dy = (Double(y) - 31.5) / 31.5
                let r = min(1, (dx * dx + dy * dy).squareRoot())
                let core = exp(-pow(r / 0.2, 2))
                let ring1 = exp(-pow((r - 0.39) / 0.05, 2)) * 0.55
                let ring2 = exp(-pow((r - 0.75) / 0.05, 2)) * 0.4
                let body = 0.42 * (1 - r * r)
                let v = min(1, 0.12 + body + core * 0.6 + ring1 + ring2)
                b.set(x, y, (v, v, v))
            }
        }
        return b
    }

    /// 尾灯のプリズムの筋（32×64・白〜灰）。縦の筋 6 本と、上下の縁へ暗く
    static func tailFace() -> CamperBitmap {
        var b = CamperBitmap(width: 32, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let u = Double(x) / Double(b.width - 1), v = Double(y) / Double(b.height - 1)
                let rib = 0.72 + 0.28 * abs(sin(u * .pi * 6))
                let ends = 1 - pow(abs(v - 0.5) * 2, 3) * 0.55
                let sides = 1 - pow(abs(u - 0.5) * 2, 4) * 0.4
                let c = rib * ends * sides
                b.set(x, y, (c, c, c))
            }
        }
        return b
    }

    /// 前照灯の光の帯（64×64・白〜黒）。u が前（0 が車の側）、v が横。前へ行くほど横に広がり、弱く消える
    /// （板 pools の beam: 幅 ±40 から ±110 へ・#fff1cf 0.55 → 0）
    static func beam() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let u = Double(x) / Double(b.width - 1)
                let v = (Double(y) - 31.5) / 31.5
                let half = (40 + 70 * u) / 110
                let lateral = exp(-pow(v / half, 2) * 2.2) * (abs(v) < 1 ? 1 : 0)
                let along = pow(1 - u, 1.6) * min(1, u * 12)
                let c = lateral * along
                b.set(x, y, (c, c, c))
            }
        }
        return b
    }

    /// 窓越しの室内の明かり（64×48・白〜黒。v=0 が上）。天井の灯りの下（真ん中の上寄り）が明るく縁へ落ち、両側に
    /// カーテンのひだ（縦の明暗）、下半分に家具（長椅子・机）の影の暗い帯、縁は黒へなめらかに落ちる（四角い板に見せない）
    static func roomGlow() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 48)
        func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
            let t = min(1, max(0, (x - e0) / (e1 - e0)))
            return t * t * (3 - 2 * t)
        }
        for y in 0..<b.height {
            for x in 0..<b.width {
                let u = (Double(x) + 0.5) / Double(b.width), v = (Double(y) + 0.5) / Double(b.height)
                // 明るいところを窓の半分以上に広げる（2026-10-19 Mac night3: 真ん中だけ明るくて暗い四角に見えた）
                let dx = (u - 0.5) / 0.75, dy = (v - 0.4) / 0.7
                var c = 0.55 + 0.45 * exp(-(dx * dx + dy * dy) * 1.2)
                // カーテン（両側 22%）: ひだの明暗。布を透ける光は少し明るい
                let side = min(u, 1 - u)
                if side < 0.22 {
                    let fold = 0.6 + 0.4 * abs(sin(u * .pi * 18))
                    c = c * (1 - smooth(0.17, 0.22, side)) * fold * 1.1 + c * smooth(0.17, 0.22, side)
                }
                // 家具の影（下 40% を暗く・机の天板の線は少し明るく）
                let shade = smooth(0.66, 0.76, v)
                c *= 1 - 0.45 * shade
                if abs(v - 0.62) < 0.015, side >= 0.22 { c *= 1.25 }
                // 縁は黒へ（窓の枠の内側の影）
                let edge = smooth(0.0, 0.06, min(u, 1 - u)) * smooth(0.0, 0.08, min(v, 1 - v))
                c = min(1, c * edge)
                b.set(x, y, (c, c, c))
            }
        }
        return b
    }

    /// 炎の色（32×64・色つき）。v=0 が根元（白に近い黄）、上へ橙・赤、先（v=1）は黒＝足しても何も出ない。
    /// 横は真ん中が明るく、縁へ落ちる
    static func flame() -> CamperBitmap {
        var b = CamperBitmap(width: 32, height: 64)
        let base = rgb(0xFFF1C2), mid = rgb(0xFF9A3C), tip = rgb(0xB8341A)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let v = 1 - Double(y) / Double(b.height - 1)
                let u = abs(Double(x) / Double(b.width - 1) - 0.5) * 2
                let c = v < 0.4 ? lerp(base, mid, v / 0.4) : lerp(mid, tip, (v - 0.4) / 0.6)
                let k = pow(1 - v, 0.8) * (1 - u * u * 0.7)
                b.set(x, y, (c.0 * k, c.1 * k, c.2 * k))
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
