import Foundation

// とおまわり号の中の貼り絵（2026-10-19）。外まわりの `CamperTextures` と同じく、白〜灰の明るさの絵に素材の色を掛ける
// （色の付いた絵は素材の色を白にする）。1 枚 256 px まで。決まった乱れ（`CamperTextures.Noise`）なので毎回同じ絵になる。
// 貼り絵の 1 回の大きさは、網の貼り絵の位置（`CamperMesh.uv`・16 単位 ≈ 40 cm で 1 回）に合わせて描く。

enum CamperRoomTextures {

    typealias RGB = (Double, Double, Double)

    static func make(_ kind: CamperTextureKind) -> CamperBitmap {
        switch kind {
        case .planks: return planks()
        case .chevron: return parquet(herringbone: false)
        case .herringbone: return parquet(herringbone: true)
        case .checkerTiles: return checkerTiles()
        case .cork: return cork()
        case .boards: return boards(count: 4, contrast: 0.16, seed: 11)
        case .darkBoards: return boards(count: 5, contrast: 0.22, seed: 17)
        case .birchPly: return birchPly()
        case .wallpaperStripe: return wallpaperStripe()
        case .leather: return leather()
        case .linenSlub: return linenSlub()
        case .knit: return knit()
        case .rush: return rush()
        case .wicker: return wicker()
        case .rope: return rope()
        case .ovalRings: return ovalRings()
        case .runnerWeave: return runnerWeave()
        case .enamelChip: return enamelChip()
        case .castIron: return castIron()
        case .foliage: return foliage()
        case .clockDial: return clockDial()
        case .windowDay: return windowView(night: false)
        case .windowNight: return windowView(night: true)
        case .matBoard: return matBoard()
        case .photoPlaceholder: return photoPlaceholder()
        case .wornWood: return wornWood()
        default: return CamperTextures.make(.weave)
        }
    }

    // MARK: 乱れ

    /// 格子の値をなめらかにつないだ乱れ（0〜1・周期 `period` で繰り返す）
    static func valueNoise(_ x: Double, _ y: Double, period: Int, seed: UInt64) -> Double {
        func h(_ i: Int, _ j: Int) -> Double {
            let ii = ((i % period) + period) % period, jj = ((j % period) + period) % period
            var n = CamperTextures.Noise(seed: seed &+ UInt64(ii * 7919 + jj * 104_729))
            _ = n.next()
            return n.next()
        }
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Double(x0), fy = y - Double(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = h(x0, y0), b = h(x0 + 1, y0), c = h(x0, y0 + 1), d = h(x0 + 1, y0 + 1)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }

    /// 重ねた乱れ（細かいむら）
    static func fbm(_ x: Double, _ y: Double, period: Int, seed: UInt64, octaves: Int = 4) -> Double {
        var v = 0.0, amp = 0.5, f = 1.0, total = 0.0
        for o in 0..<octaves {
            v += valueNoise(x * f, y * f, period: period * Int(f), seed: seed &+ UInt64(o * 31)) * amp
            total += amp
            amp *= 0.5
            f *= 2
        }
        return v / total
    }

    private static func gray(_ v: Double) -> RGB { (v, v, v) }

    /// 木目の明るさ（u は木の長さの向き・v は幅の向き。0〜1 の繰り返し）
    static func grain(_ u: Double, _ v: Double, seed: UInt64, rings: Double = 9) -> Double {
        let warp = fbm(u * 3, v * 2, period: 3, seed: seed) * 2.2
        let ring = sin((v * rings + warp) * .pi * 2)
        let fine = fbm(u * 24, v * 6, period: 24, seed: seed &+ 5)
        let late = pow(max(0, ring), 6) * 0.22
        return 0.86 + 0.1 * fine - late + 0.04 * ring
    }

    // MARK: 床

    /// 板張り（板 8 枚・継ぎ目は半分ずつずらす。板ごとに色と艶が少し違う。継ぎ目の溝は暗く細い）
    static func planks() -> CamperBitmap {
        var b = CamperBitmap(width: 256, height: 256)
        let boards = 8
        var n = CamperTextures.Noise(seed: 41)
        let tones = (0..<boards * 2).map { _ in 0.88 + n.next() * 0.16 }
        let joints = (0..<boards).map { _ in n.next() }
        for y in 0..<b.height {
            let v = Double(y) / Double(b.height) * Double(boards)
            let row = Int(v), fv = v - Double(row)
            for x in 0..<b.width {
                var u = Double(x) / Double(b.width) + joints[row]
                let seg = Int(floor(u * 2))
                u = u * 2 - Double(seg)
                let tone = tones[(row * 2 + ((seg % 2) + 2) % 2) % tones.count]
                var g = grain(u, fv * 0.35 + Double(row) * 0.21, seed: UInt64(row * 13 + 3)) * tone
                // 継ぎ目（長い辺と短い辺）と、角のわずかな面取りの陰
                if fv < 0.035 || fv > 0.965 { g *= 0.45 } else if fv < 0.07 || fv > 0.93 { g *= 0.88 }
                if u < 0.008 || u > 0.992 { g *= 0.5 }
                b.set(x, y, gray(min(1, g)))
            }
        }
        return b
    }

    /// 寄木（矢筈・ヘリンボーン）
    static func parquet(herringbone: Bool) -> CamperBitmap {
        var b = CamperBitmap(width: 256, height: 256)
        let size = 256.0
        let unit = size / 4
        for y in 0..<b.height {
            for x in 0..<b.width {
                let px = Double(x), py = Double(y)
                // 斜めの座標で、細長い板（4:1）を V 字に並べる
                let col = Int(floor(px / unit))
                let flip = col % 2 == 0
                let lx = px - Double(col) * unit
                let ly = py + (flip ? lx : (unit - lx)) * (herringbone ? 1 : 0.5)
                let along = ly.truncatingRemainder(dividingBy: unit) / unit
                let piece = Int(floor(ly / (unit / 4)))
                let fv = (ly / (unit / 4)).truncatingRemainder(dividingBy: 1)
                var g = grain(along, fv * 0.3 + Double(piece) * 0.17, seed: UInt64(piece * 7 + col * 3))
                g *= 0.9 + 0.12 * valueNoise(Double(piece), Double(col), period: 16, seed: 9)
                if fv < 0.05 || fv > 0.95 { g *= 0.55 }
                if lx < 1.2 || lx > unit - 1.2 { g *= 0.55 }
                b.set(x, y, gray(min(1, g)))
            }
        }
        return b
    }

    /// 市松のタイル（生成りと墨・目地・艶のむら）。色の付いた絵
    static func checkerTiles() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 128)
        let light: RGB = (0.91, 0.89, 0.84), dark: RGB = (0.17, 0.17, 0.18), grout: RGB = (0.55, 0.53, 0.5)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let tx = x / 32, ty = y / 32
                let fx = x % 32, fy = y % 32
                if fx < 1 || fy < 1 { b.set(x, y, grout); continue }
                let base = (tx + ty) % 2 == 0 ? light : dark
                let m = 0.94 + 0.08 * fbm(Double(x) / 16, Double(y) / 16, period: 8, seed: 23)
                b.set(x, y, (base.0 * m, base.1 * m, base.2 * m))
            }
        }
        return b
    }

    /// コルク（粒）
    static func cork() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 128)
        var n = CamperTextures.Noise(seed: 5)
        var dots: [(Double, Double, Double)] = []
        for _ in 0..<420 { dots.append((n.next() * 128, n.next() * 128, 0.6 + n.next() * 1.8)) }
        for y in 0..<b.height {
            for x in 0..<b.width {
                b.set(x, y, gray(0.8 + 0.2 * fbm(Double(x) / 10, Double(y) / 10, period: 12, seed: 3)))
            }
        }
        for d in dots {
            let r = Int(ceil(d.2))
            for dy in -r...r {
                for dx in -r...r {
                    let x = (Int(d.0) + dx + 128) % 128, y = (Int(d.1) + dy + 128) % 128
                    if Double(dx * dx + dy * dy) <= d.2 * d.2 {
                        let p = b.pixel(x, y)
                        let v = Double(p.r) / 255 * (d.2 > 1.6 ? 0.62 : 1.12)
                        b.set(x, y, gray(min(1, v)))
                    }
                }
            }
        }
        return b
    }

    // MARK: 壁

    /// 縦の板張り（板 `count` 枚。溝・板ごとの色の違い・節）
    static func boards(count: Int, contrast: Double, seed: UInt64) -> CamperBitmap {
        var b = CamperBitmap(width: 256, height: 256)
        var n = CamperTextures.Noise(seed: seed)
        let tones = (0..<count).map { _ in 1 - contrast / 2 + n.next() * contrast }
        let knots = (0..<count).map { _ in (n.next(), n.next()) }
        for y in 0..<b.height {
            for x in 0..<b.width {
                let u = Double(x) / Double(b.width) * Double(count)
                let i = Int(u), fu = u - Double(i)
                let v = Double(y) / Double(b.height)
                var g = grain(v, fu * 0.4 + Double(i) * 0.3, seed: seed &+ UInt64(i)) * tones[i]
                let k = knots[i]
                let dk = hypot((fu - k.0) * 3, (v - k.1) * 8)
                if dk < 0.5 { g *= 0.78 + 0.22 * dk / 0.5 }
                if fu < 0.03 || fu > 0.97 { g *= 0.42 } else if fu < 0.06 { g *= 0.85 }
                b.set(x, y, gray(min(1, g)))
            }
        }
        return b
    }

    /// 樺の合板（大きな板・淡い木目・継ぎ目の細い線）
    static func birchPly() -> CamperBitmap {
        var b = CamperBitmap(width: 256, height: 256)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let u = Double(x) / 256, v = Double(y) / 256
                var g = 0.9 + 0.08 * (grain(v, u * 0.6, seed: 77, rings: 4) - 0.86)
                g += 0.04 * fbm(u * 8, v * 8, period: 8, seed: 12)
                if x < 1 || y < 1 { g *= 0.6 }
                b.set(x, y, gray(min(1, g)))
            }
        }
        return b
    }

    /// 縞の壁紙（生成りと煤けた薔薇色・紙の目）。色の付いた絵
    static func wallpaperStripe() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let paper = 0.95 + 0.05 * fbm(Double(x) / 4, Double(y) / 4, period: 16, seed: 8)
                let c: RGB = x % 32 < 16 ? (0.9, 0.86, 0.78) : (0.73, 0.55, 0.5)
                b.set(x, y, (c.0 * paper, c.1 * paper, c.2 * paper))
            }
        }
        return b
    }

    // MARK: 布・革

    /// 革（細かい粒としわ・擦れて明るい所）
    static func leather() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 128)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let px = Double(x) / 128, py = Double(y) / 128
                let pebble = valueNoise(px * 48, py * 48, period: 48, seed: 61)
                let crease = abs(fbm(px * 4, py * 4, period: 4, seed: 63) - 0.5)
                let wear = fbm(px * 2, py * 2, period: 2, seed: 65)
                var g = 0.78 + 0.12 * pebble + 0.12 * wear
                if crease < 0.025 { g *= 0.82 }
                b.set(x, y, gray(min(1, g)))
            }
        }
        return b
    }

    /// 麻（太さの揃わない糸・節）
    static func linenSlub() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 128)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let warp = valueNoise(Double(x) / 2, Double(y) / 18, period: 64, seed: 71)
                let weft = valueNoise(Double(x) / 18, Double(y) / 2, period: 64, seed: 73)
                let over = (x / 2 + y / 2) % 2 == 0
                var g = 0.84 + (over ? warp : weft) * 0.14
                g += 0.05 * fbm(Double(x) / 32, Double(y) / 32, period: 4, seed: 75)
                b.set(x, y, gray(min(1, g)))
            }
        }
        return b
    }

    /// 編み目（縦に並ぶ V の目）
    static func knit() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let cx = Double(x % 8) - 3.5, cy = Double(y % 6)
                let leg = abs(abs(cx) - (cy * 0.5 + 0.8))
                let g = 0.7 + 0.3 * max(0, 1 - leg / 1.8)
                b.set(x, y, gray(g))
            }
        }
        return b
    }

    /// 畳の目（藺草の細い筋と、織りの縦糸）
    static func rush() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 128)
        for y in 0..<b.height {
            let row = sin(Double(y) * .pi / 2) * 0.5 + 0.5
            for x in 0..<b.width {
                var g = 0.82 + 0.1 * row + 0.06 * valueNoise(Double(x) / 6, Double(y) / 2, period: 32, seed: 81)
                if x % 32 < 1 { g *= 0.8 }
                b.set(x, y, gray(min(1, g)))
            }
        }
        return b
    }

    /// 籐の編み目（縦の芯と横に編む皮）
    static func wicker() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let cellX = x / 8, cellY = y / 4
                let over = (cellX + cellY) % 2 == 0
                let fx = Double(x % 8) / 8, fy = Double(y % 4) / 4
                var g = over ? 0.92 - 0.25 * pow(fx - 0.5, 2) * 4 : 0.75 - 0.2 * pow(fy - 0.5, 2) * 4
                g += 0.05 * valueNoise(Double(x) / 3, Double(y) / 3, period: 21, seed: 91)
                b.set(x, y, gray(min(1, g)))
            }
        }
        return b
    }

    /// 撚った紐（斜めの撚り）
    static func rope() -> CamperBitmap {
        var b = CamperBitmap(width: 32, height: 32)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let t = Double(x + y).truncatingRemainder(dividingBy: 8) / 8
                b.set(x, y, gray(0.7 + 0.3 * sin(t * .pi)))
            }
        }
        return b
    }

    /// 楕円の輪の敷物（色の楕円を 5 重・編んだ縄の筋）。色の付いた絵（貼り絵の位置は 0〜1）
    static func ovalRings() -> CamperBitmap {
        var b = CamperBitmap(width: 256, height: 128)
        let colors: [RGB] = [(0.55, 0.24, 0.17), (0.82, 0.72, 0.52), (0.27, 0.36, 0.3), (0.72, 0.5, 0.3), (0.2, 0.27, 0.4), (0.86, 0.8, 0.68)]
        for y in 0..<b.height {
            for x in 0..<b.width {
                let dx = (Double(x) - 127.5) / 127.5, dy = (Double(y) - 63.5) / 63.5
                let r = (dx * dx + dy * dy).squareRoot()
                guard r <= 1 else { b.set(x, y, colors[0]); continue }
                let ring = r * 5.5
                let c = colors[min(colors.count - 1, Int(ring))]
                let braid = 0.82 + 0.18 * sin((atan2(dy, dx) * 40 + ring * 12))
                let groove = abs(sin(ring * .pi * 2)) < 0.12 ? 0.75 : 1.0
                b.set(x, y, (c.0 * braid * groove, c.1 * braid * groove, c.2 * braid * groove))
            }
        }
        return b
    }

    /// 細長い敷物（縞の織り・端の房の手前の濃い帯）。色の付いた絵（貼り絵の位置は 0〜1）
    static func runnerWeave() -> CamperBitmap {
        var b = CamperBitmap(width: 256, height: 96)
        let bands: [RGB] = [(0.47, 0.17, 0.13), (0.86, 0.79, 0.64), (0.2, 0.29, 0.4), (0.86, 0.79, 0.64), (0.6, 0.42, 0.22)]
        for y in 0..<b.height {
            for x in 0..<b.width {
                let v = Double(y) / Double(b.height)
                let u = Double(x) / Double(b.width)
                var c: RGB = (0.47, 0.17, 0.13)
                let edge = min(u, 1 - u)
                if edge > 0.06, v > 0.12, v < 0.88 {
                    let k = Int((v - 0.12) / 0.76 * 9)
                    c = bands[[1, 2, 1, 4, 3, 4, 1, 2, 1][min(8, max(0, k))]]
                    // 菱の文様
                    let dm = abs((u * 24).truncatingRemainder(dividingBy: 2) - 1) + abs(v * 2 - 1) * 1.4
                    if dm < 0.5 { c = bands[0] }
                }
                let weave = (x + y) % 2 == 0 ? 1.0 : 0.9
                let fuzz = 0.92 + 0.08 * valueNoise(Double(x) / 2, Double(y) / 2, period: 128, seed: 97)
                b.set(x, y, (c.0 * weave * fuzz, c.1 * weave * fuzz, c.2 * weave * fuzz))
            }
        }
        return b
    }

    // MARK: 金属・陶器

    /// 琺瑯・塗りの艶のむらと、小さな欠け
    static func enamelChip() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 128)
        var n = CamperTextures.Noise(seed: 101)
        let chips = (0..<6).map { _ in (n.next() * 128, n.next() * 128, 0.8 + n.next() * 1.4) }
        for y in 0..<b.height {
            for x in 0..<b.width {
                var g = 0.94 + 0.06 * fbm(Double(x) / 32, Double(y) / 32, period: 4, seed: 103)
                for c in chips where hypot(Double(x) - c.0, Double(y) - c.1) < c.2 { g = 0.35 }
                b.set(x, y, gray(g))
            }
        }
        return b
    }

    /// 鋳物・素焼きのざらつき
    static func castIron() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let g = 0.75 + 0.25 * fbm(Double(x) / 4, Double(y) / 4, period: 16, seed: 107)
                b.set(x, y, gray(g))
            }
        }
        return b
    }

    /// 葉（葉脈と色のむら）
    static func foliage() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                var g = 0.75 + 0.25 * fbm(Double(x) / 8, Double(y) / 8, period: 8, seed: 109)
                if abs(Double(x) - 32) < 0.8 || abs((Double(x) - 32) - (Double(y) - 32) * 0.5).truncatingRemainder(dividingBy: 12) < 0.6 { g *= 1.12 }
                b.set(x, y, gray(min(1, g)))
            }
        }
        return b
    }

    // MARK: 絵

    /// 時計の文字盤（白・外の輪・目盛り 60 と太い 12）。色の付いた絵（0〜1）
    static func clockDial() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 128)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let dx = (Double(x) - 63.5) / 63.5, dy = (Double(y) - 63.5) / 63.5
                let r = (dx * dx + dy * dy).squareRoot()
                var c: RGB = (0.96, 0.95, 0.92)
                let a = atan2(dy, dx)
                let tick60 = abs(sin(a * 30)) < 0.06 && r > 0.82 && r < 0.9
                let tick12 = abs(sin(a * 6)) < 0.07 && r > 0.7 && r < 0.9
                if tick60 || tick12 { c = (0.1, 0.1, 0.11) }
                if r > 0.95 { c = (0.12, 0.12, 0.13) }
                let shade = 1 - 0.06 * r * r
                b.set(x, y, (c.0 * shade, c.1 * shade, c.2 * shade))
            }
        }
        return b
    }

    /// 窓の外（昼: 空と遠い山並みと木立。夜: 濃い紺の空に星と山の影）。色の付いた絵（0〜1）
    static func windowView(night: Bool) -> CamperBitmap {
        var b = CamperBitmap(width: 256, height: 128)
        var n = CamperTextures.Noise(seed: night ? 211 : 213)
        let stars = (0..<90).map { _ in (n.next() * 256, n.next() * 70, n.next()) }
        for y in 0..<b.height {
            let v = Double(y) / Double(b.height)
            for x in 0..<b.width {
                let u = Double(x) / Double(b.width)
                var c: RGB = night ? (0.03 + 0.05 * v, 0.05 + 0.07 * v, 0.12 + 0.1 * v) : (0.55 + 0.35 * v, 0.7 + 0.22 * v, 0.9 + 0.06 * v)
                let far = 0.52 + 0.08 * sin(u * 9) + 0.05 * fbm(u * 6, 0, period: 6, seed: 3)
                let near = 0.66 + 0.06 * sin(u * 17 + 1) + 0.08 * fbm(u * 14, 1, period: 14, seed: 5)
                if v > far { c = night ? (0.04, 0.05, 0.08) : (0.47, 0.58, 0.68) }
                if v > near {
                    let leaf = fbm(u * 40, v * 20, period: 40, seed: 7)
                    c = night ? (0.02, 0.03, 0.03) : (0.2 + 0.12 * leaf, 0.32 + 0.14 * leaf, 0.2 + 0.08 * leaf)
                }
                b.set(x, y, c)
            }
        }
        if night {
            for s in stars {
                let x = Int(s.0) % 256, y = Int(s.1)
                let v = 0.5 + 0.5 * s.2
                b.set(x, y, (v, v, v * 0.95))
            }
        }
        return b
    }

    /// 額のマット（白い紙・内側の斜めの切り口が明るい）
    static func matBoard() -> CamperBitmap {
        var b = CamperBitmap(width: 64, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                b.set(x, y, gray(0.95 + 0.05 * fbm(Double(x) / 4, Double(y) / 4, period: 16, seed: 117)))
            }
        }
        return b
    }

    /// まだ写真を入れていない額の中（淡い灰の地に山の形）。色の付いた絵（0〜1）
    static func photoPlaceholder() -> CamperBitmap {
        var b = CamperBitmap(width: 96, height: 64)
        for y in 0..<b.height {
            let v = Double(y) / Double(b.height)
            for x in 0..<b.width {
                let u = Double(x) / Double(b.width)
                var c: RGB = (0.5 + 0.2 * v, 0.55 + 0.18 * v, 0.6 + 0.12 * v)
                if v > 0.55 + 0.15 * abs(sin(u * 5)) { c = (0.32, 0.36, 0.38) }
                b.set(x, y, c)
            }
        }
        return b
    }

    /// 使い込んだ木（木目に、擦れて明るい所と、手垢で暗い所のむら）
    static func wornWood() -> CamperBitmap {
        var b = CamperBitmap(width: 128, height: 64)
        for y in 0..<b.height {
            for x in 0..<b.width {
                let u = Double(x) / 128, v = Double(y) / 64
                var g = grain(u, v * 0.5, seed: 131)
                g *= 0.92 + 0.16 * fbm(u * 3, v * 3, period: 3, seed: 133)
                b.set(x, y, gray(min(1, g)))
            }
        }
        return b
    }
}
