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
        // 奥の林（手前の列はまばら・奥ほど密に。重なって一続きの林の影に見える数）
        add(x: -1500...1500, z: -1300 ... -800, count: 16, tall: 380...620)
        add(x: -2200...2200, z: -2200 ... -1300, count: 36, tall: 450...820)
        // 両脇の遠く（引いて見たときの左右の端）
        add(x: -2600 ... -1300, z: -800...700, count: 10, tall: 420...760)
        add(x: 1300...2600, z: -800...700, count: 10, tall: 420...760)
        return out
    }

    /// 針葉樹の網（段 6 つ・9 角）。光を受けない一色で描くので、面の向きは外向きに付けるだけ。
    /// 2026-10-21（Mac run 627 の 95l）: 段の下の縁が水平な輪と細い幹だと、画面の上の端で切れた木の下半分が四角い建物の
    /// 並びに見えた。いちばん下の段の裾を地面まで下ろし（幹は見せない）、どの段の縁もぎざぎざに垂らす（枝先）
    static func treeMesh(_ trees: [Tree], material: CamperMaterial) -> CamperMesh {
        var m = CamperMesh()
        let sides = 9
        let tiers = 6
        for (index, t) in trees.enumerated() {
            for i in 0..<tiers {
                let f = Double(i) / Double(tiers)
                // 段の裾（いちばん下は地面の少し下）と先（上の段ほど細く、重なる）
                let y0 = i == 0 ? -10 : t.height * f * 0.86
                let apex = t.height * min(1, f * 0.86 + 0.3)
                let r = t.radius * (1.05 - f * 0.78)
                let top = t.base + CV3(0, apex, 0)
                let twist = Double(i) * 0.7 + Double(index) * 1.3
                var rim: [CV3] = []
                for k in 0..<sides {
                    let a = Double(k) / Double(sides) * 2 * .pi + twist
                    // 枝先は外へ出て垂れ、間は内へ上がる
                    let out = k % 2 == 0
                    let rr = r * (out ? 1 : 0.7)
                    let yy = y0 + (out ? -t.height * 0.025 : t.height * 0.03)
                    rim.append(t.base + CV3(cos(a) * rr, max(-10, yy), sin(a) * rr))
                }
                for k in 0..<sides {
                    let p0 = rim[k], p1 = rim[(k + 1) % sides]
                    let mid = (p0 + p1) * 0.5 - t.base
                    let nrm = CV3(mid.x, t.radius * 0.5, mid.z).normalized
                    m.tri(p0, p1, top, nrm, nrm, nrm, material)
                }
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
