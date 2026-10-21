import Foundation

// 夜の外の遠景（2026-10-21・owner「夜のキャンピングカーの外だね」「光の感じまじで残念」）。
//
// 前の夜は、車の後ろが画面の黒い地のままで、車が黒い空間に浮いて見えた。夜のキャンプ場の写真には、車の奥に
// 林の影（針葉樹の重なり）と、遠くの山の稜線がかすかに見える。ここはその形だけを作る（素の Swift・Linux で試験できる）。
// 色は光を受けない一色で、霞（奥ほど・低いほど地平線の色に寄る）は場面の側（`CamperScene`）の shader で足す。
//
// 置き場所（2026-10-21 判断）: カメラはいつも車の手前（+Z の側・5〜15 m）にあり、車が回る台の上で回る。
// 木は車の奥（Z が −7 より奥）と、両脇の遠く（|X| が 12 より外）だけに置き、カメラと車の間には置かない。
// 単位は板の単位（1 = 1 cm。SceneKit へは 1/100）。

enum CamperNightScenery {

    /// 木 1 本（根元の位置・高さ・太さ）
    struct Tree: Equatable, Sendable {
        var base: CV3
        var height: Double
        var radius: Double
    }

    /// 針葉樹の並び（決まった乱れ・毎回同じ）。奥の林と、両脇の遠くの木
    static func trees() -> [Tree] {
        var n = CamperTextures.Noise(seed: 2026_1021)
        var out: [Tree] = []
        func add(x: ClosedRange<Double>, z: ClosedRange<Double>, count: Int, tall: ClosedRange<Double>) {
            for _ in 0..<count {
                let px = x.lowerBound + (x.upperBound - x.lowerBound) * n.next()
                let pz = z.lowerBound + (z.upperBound - z.lowerBound) * n.next()
                let h = tall.lowerBound + (tall.upperBound - tall.lowerBound) * n.next()
                out.append(Tree(base: CV3(px, 0, pz), height: h, radius: h * (0.2 + 0.07 * n.next())))
            }
        }
        // 奥の林（手前の列はまばら・奥ほど密に）
        add(x: -1500...1500, z: -1300 ... -800, count: 14, tall: 380...620)
        add(x: -2200...2200, z: -2200 ... -1300, count: 30, tall: 450...820)
        // 両脇の遠く（引いて見たときの左右の端）
        add(x: -2600 ... -1300, z: -800...700, count: 10, tall: 420...760)
        add(x: 1300...2600, z: -800...700, count: 10, tall: 420...760)
        return out
    }

    /// 針葉樹の網（段になった円錐 4 つ・7 角）。光を受けない一色で描くので、面の向きは外向きに付けるだけ
    static func treeMesh(_ trees: [Tree], material: CamperMaterial) -> CamperMesh {
        var m = CamperMesh()
        let sides = 7
        for t in trees {
            // 幹の根元を少し見せる（下の 12%）
            let trunkTop = t.height * 0.12
            let tiers = 4
            for i in 0..<tiers {
                let f = Double(i) / Double(tiers)
                let y0 = trunkTop + (t.height - trunkTop) * f * 0.78
                let apex = trunkTop + (t.height - trunkTop) * min(1, f * 0.78 + 0.42)
                let r = t.radius * (1 - f * 0.62)
                let top = t.base + CV3(0, apex, 0)
                for k in 0..<sides {
                    let a0 = Double(k) / Double(sides) * 2 * .pi + Double(i) * 0.4
                    let a1 = Double(k + 1) / Double(sides) * 2 * .pi + Double(i) * 0.4
                    let p0 = t.base + CV3(cos(a0) * r, y0, sin(a0) * r)
                    let p1 = t.base + CV3(cos(a1) * r, y0, sin(a1) * r)
                    let nrm = CV3(cos((a0 + a1) / 2), 0.4, sin((a0 + a1) / 2))
                    m.tri(p0, p1, top, nrm, nrm, nrm, material)
                }
            }
            // 幹（細い四角柱）
            let w = t.radius * 0.08
            let b = t.base
            for (dx, dz) in [(w, 0.0), (0, w), (-w, 0), (0, -w)] {
                let side = CV3(-dz, 0, dx).normalized
                let n0 = CV3(dx, 0, dz).normalized
                m.quad(b + CV3(dx, 0, dz) - side * w, b + CV3(dx, 0, dz) + side * w,
                       b + CV3(dx, trunkTop + 20, dz) + side * w, b + CV3(dx, trunkTop + 20, dz) - side * w, n0, n0, n0, n0, material)
            }
        }
        return m
    }

    /// 遠い山の稜線（車の真ん中から半径 `radius` の輪・高さは正弦の重ね合わせ）。内向きの帯
    static func ridgeMesh(radius: Double = 5200, segments: Int = 120, material: CamperMaterial) -> CamperMesh {
        var m = CamperMesh()
        func height(_ a: Double) -> Double {
            420 + 260 * sin(a * 2 + 0.6) + 170 * sin(a * 5 + 1.9) + 90 * sin(a * 11 + 0.3) + 45 * sin(a * 23 + 2.2)
        }
        for k in 0..<segments {
            let a0 = Double(k) / Double(segments) * 2 * .pi
            let a1 = Double(k + 1) / Double(segments) * 2 * .pi
            let p0 = CV3(cos(a0) * radius, -40, sin(a0) * radius), p1 = CV3(cos(a1) * radius, -40, sin(a1) * radius)
            let q0 = CV3(cos(a0) * radius, max(80, height(a0)), sin(a0) * radius)
            let q1 = CV3(cos(a1) * radius, max(80, height(a1)), sin(a1) * radius)
            let inward0 = CV3(-cos(a0), 0, -sin(a0)), inward1 = CV3(-cos(a1), 0, -sin(a1))
            m.quad(p0, p1, q1, q0, inward0, inward1, inward1, inward0, material)
        }
        return m
    }
}
