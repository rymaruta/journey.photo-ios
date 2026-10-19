import Foundation

// 島の場面の組み立て（板 Camp の `renderVals` の「island / things on the island / tent / fire pit / conifers /
// the captured photo as a paper diorama / gear」をそのまま移したもの）。
//
// 返すのは形と素材の一覧だけ。SceneKit の節（SCNNode）に組むのは `CampSceneRenderer`。
// 板は SVG に描く都合で「線」を使っていたところ（張り綱・根・草）は細い筒・細い三角に、
// 「縫い目・地層の線・ファスナー」は素材の貼り絵（`CampTexture`）に置き換える。

/// 形 1 つ
enum CampShape: Equatable, Sendable {
    /// 自前の網
    case mesh(CampMesh)
    /// 角の丸い箱（`yaw` は縦の軸・`roll` は奥の軸の回り。度・板の `rbox`）。`top` は上の面だけ別の素材
    case box(center: CampVec3, size: CampVec3, chamfer: Double, yaw: Double, roll: Double, top: CampMaterialKey?)
    /// 2 点を結ぶ筒（`caps` は始まり・終わりの切り口の素材）
    case tube(from: CampVec3, to: CampVec3, radius: Double, caps: [CampMaterialKey]?)
    /// 細くなる筒（幹・ペグの先）
    case taper(from: CampVec3, to: CampVec3, radius0: Double, radius1: Double)
    /// 輪（マグの縁の青）
    case ring(center: CampVec3, radius: Double, pipe: Double)
}

/// 何の部品か（見せ方の絞り込み・テスト・描く数を減らすとき）
enum CampGroup: String, CaseIterable, Sendable {
    case island, underside, path, pond, scatter, rocks, tent, tentInside, fire, trees, cutout, gear, table, lantern, woodpile
}

/// 形・素材・役目
struct CampPiece: Equatable, Sendable {
    var shape: CampShape
    var material: CampMaterialKey
    var group: CampGroup
    /// 芝に影を落とす（実装の指定「影を落とす物」: テント・針葉樹・切り絵・椅子・保冷箱・机・岩）
    var castsShadow: Bool = true
    /// 細かい線（縫い目・草むら・苔・地層の線）。回している間は描かない（付箋: 約 1,390 → 約 950）
    var detail: Bool = false
    /// 切り絵の番号（立てる動き・置く前の浮き）。切り絵でなければ nil
    var cutout: String? = nil
    /// 切り絵の層（奥 0・中 1・手前 2）
    var layer: Int? = nil
}

/// 光る点（焚き火・ランタン・テントの中の灯り）
struct CampPointLight: Equatable, Sendable {
    var position: CampVec3
    var color: UInt32
    var intensity: Double
    var range: Double
}

/// 立てた切り絵（撮った写真を 3 枚に切ったもの）
struct CampPlacedCutout: Equatable, Sendable {
    let id: String
    let layers: CampCutLayers
    /// 置き場所（0 手前の芝・1 小道のそば・2 テントの横）
    let spot: Int
}

/// 場面の注文
struct CampSceneOptions: Equatable, Sendable {
    var stage: CampStage = .tent
    var season: CampSeason = .summer
    var time: CampTime = .evening
    var focus: CampFocus = .all
    /// 立てた切り絵（置き場所ごとに 1 つ）
    var cutouts: [CampPlacedCutout] = []
    /// 置く前の切り絵（少し浮かせて、点線の輪と影を出す）
    var placing: CampPlacedCutout? = nil
}

/// 組み上がった場面
struct CampScene: Equatable, Sendable {
    var pieces: [CampPiece] = []
    var lights: [CampPointLight] = []
    /// 炎の芯（揺れる 3 層の炎を立てる所）と高さ
    var flame: (position: CampVec3, height: Double, opacity: Double)?
    /// 火の粉・煙の出る所（出さなければ nil）
    var sparks: CampVec3?
    var smoke: (position: CampVec3, opacity: Double)?
    /// 柔らかく光る輪（テントの扉の前・ランタン・焚き火）: 位置・半径・濃さ
    var glows: [(position: CampVec3, radius: Double, opacity: Double)] = []
    /// 置く前の点線の輪と影（中心・半径 x・z）
    var placeRing: (center: CampVec3, rx: Double, rz: Double)?
    var placeShadow: (center: CampVec3, rx: Double, rz: Double)?
    /// 島の上の面の外形（芝の上だけに出すもの・落ち影の切り抜き）
    var topOutline: [CampVec2] = []

    static func == (a: CampScene, b: CampScene) -> Bool {
        a.pieces == b.pieces && a.lights == b.lights && a.topOutline == b.topOutline
            && a.sparks == b.sparks && a.flame?.position == b.flame?.position && a.glows.count == b.glows.count
    }

    func pieces(in group: CampGroup) -> [CampPiece] { pieces.filter { $0.group == group } }
}

/// テントの寸法（板: 半幅 24・半長 30・高さ 38・フライは前後に 3 はみ出す。扉の穴 (−10,0)(10,0)(0,−29)）。
/// 扉のある妻壁の貼り絵（ファスナーの点線）も同じ値で描く
enum CampTentSpec {
    static let halfWidth = 24.0
    static let halfLength = 30.0
    static let height = 38.0
    static let overhang = 3.0
    static let angle = 30.0
    /// 扉の穴の下の端（±10）と上の端（棟から 9 下）
    static let doorHalf = 10.0
    static var doorTop: Double { -height + 9 }
    /// 妻壁の頂（棟から 1.5 下）
    static var wallTop: Double { -height + 1.5 }
}

enum CampSceneBuilder {

    // MARK: - 寸法の付箋の値

    /// 島の外形 9 点（x, z, 角の丸み）
    static let islandBase: [(Double, Double, Double)] = [
        (-112, -70, 26), (-56, -118, 30), (42, -114, 30), (108, -78, 26), (122, 12, 28),
        (96, 98, 28), (8, 122, 30), (-82, 104, 28), (-122, 28, 26),
    ]
    static let islandThickness = 24.0
    static let islandBevel = 3.4
    /// 切り絵の置き場所（手前の芝・小道のそば・テントの横）
    static let cutoutSpots: [(Double, Double)] = [(-74, 52), (-6, 88), (-70, -10)]
    /// 切り絵の幅・紙の厚み・3 枚の間隔
    static let cutoutWidth = 42.0
    static let paperThickness = 1.6
    static let layerDepths: [Double] = [-6, -0.8, 4.4]
    static let cutoutAngle = 32.0

    /// 島の外形（育ちの倍率つき・角を丸めた点）
    static func islandOutline(stage: CampStage) -> [CampVec2] {
        let s = stage.scale
        return CampGeometry.rounded(islandBase.map { (CampVec2($0.0 * s, $0.1 * s), $0.2 * s) }).map(\.point)
    }

    // MARK: - 組み立て

    static func build(_ o: CampSceneOptions) -> CampScene {
        var scene = CampScene()
        var rnd = CampRandom(11)
        let s0 = o.stage.scale
        let winter = o.season == .winter, autumn = o.season == .autumn, spring = o.season == .spring
        let night = o.time == .night, dusk = o.time == .evening, morning = o.time == .morning
        let focus = o.focus
        func show(_ f: CampFocus) -> Bool { focus == .all || focus == f }
        let grass = CampMaterials.grassColor(o.season)
        let outline = islandOutline(stage: o.stage)
        scene.topOutline = outline

        func add(_ shape: CampShape, _ m: CampMaterialKey, _ g: CampGroup, shadow: Bool = true, detail: Bool = false) {
            scene.pieces.append(CampPiece(shape: shape, material: m, group: g, castsShadow: shadow, detail: detail))
        }
        func addMesh(_ mesh: CampMesh, _ m: CampMaterialKey, _ g: CampGroup, shadow: Bool = true, detail: Bool = false) {
            guard !mesh.isEmpty else { return }
            add(.mesh(mesh), m, g, shadow: shadow, detail: detail)
        }
        func box(_ c: CampVec3, _ size: CampVec3, _ r: Double, _ m: CampMaterialKey, _ g: CampGroup,
                 yaw: Double = 0, roll: Double = 0, top: CampMaterialKey? = nil, shadow: Bool = true, detail: Bool = false) {
            add(.box(center: c, size: size, chamfer: r, yaw: yaw, roll: roll, top: top), m, g, shadow: shadow, detail: detail)
        }
        func tube(_ a: CampVec3, _ b: CampVec3, _ r: Double, _ m: CampMaterialKey, _ g: CampGroup,
                  caps: [CampMaterialKey]? = nil, shadow: Bool = true, detail: Bool = false) {
            add(.tube(from: a, to: b, radius: r, caps: caps), m, g, shadow: shadow, detail: detail)
        }
        // 細い葉・草（根元の幅 w の三角。両面）
        var blades = CampMesh()
        func blade(_ base: CampVec3, _ tip: CampVec3, width: Double, color: UInt32) {
            let dir = CampVec3(tip.x - base.x, 0, tip.z - base.z)
            var side = CampVec3(-dir.z, 0, dir.x).normalized
            if side.length < 0.5 { side = CampVec3(1, 0, 0) }
            let half = side * (width / 2)
            blades.flatTriangle(base - half, base + half, tip, color: CampMaterials.rgb(color))
        }
        // 小さな点（花・苔・落ち葉）。上を向いた六角
        var dots = CampMesh()
        func dot(_ c: CampVec3, size: Double, color: UInt32) {
            let r = size / 2
            let ring = (0..<6).map { i -> CampVec3 in
                let a = Double(i) / 6 * 2 * .pi
                return CampVec3(c.x + cos(a) * r, c.y, c.z + sin(a) * r)
            }
            dots.flatPolygon(ring, outward: CampVec3(0, -1, 0), color: CampMaterials.rgb(color))
        }

        // ---------- 島（芝・土の層・面取り・岩の底） ----------
        let bands = CampGeometry.extrudeY(outline, top: 0, bottom: islandThickness, bevel: islandBevel)
        addMesh(bands[3] ?? CampMesh(), .grass, .island, shadow: false)
        addMesh(bands[2] ?? CampMesh(), .lip, .island, shadow: false)
        addMesh(bands[1] ?? CampMesh(), .soil, .island, shadow: false)
        addMesh(bands[0] ?? CampMesh(), .soilDark, .island, shadow: false)
        addMesh(bands[4] ?? CampMesh(), .soilDark, .island, shadow: false)
        // 壁に垂れる根（2 点に 1 つ・55%）
        for i in stride(from: 0, to: outline.count, by: 2) {
            let p = outline[i]
            let n = CampVec3(p.x, 0, p.y).normalized
            if rnd.next() < 0.55 {
                let y = 9 + rnd.next() * 12
                tube(CampVec3(p.x + n.x * 0.6, 4, p.y + n.z * 0.6), CampVec3(p.x + n.x * 1.6, y, p.y + n.z * 1.6),
                     0.35, .char, .island, shadow: false, detail: true)
            }
        }
        // 壁に埋まった小石（3 点に 1 つ）
        for i in stride(from: 1, to: outline.count, by: 3) {
            let p = outline[i]
            let n = CampVec3(p.x, 0, p.y).normalized
            let y = 12 + rnd.next() * 8, w = 4 + rnd.next() * 3, yaw = rnd.next() * 90
            box(CampVec3(p.x - n.x * 0.8, y, p.y - n.z * 0.8), CampVec3(w, 3, 4), 1, .stone, .island, yaw: yaw,
                shadow: false, detail: true)
        }
        // 芝の縁から垂れる草（冬は雪で出さない）
        if !winter {
            for i in outline.indices {
                let p = outline[i], q = outline[(i + 1) % outline.count]
                for _ in 0..<2 {
                    let t = rnd.next()
                    let x = p.x + (q.x - p.x) * t, z = p.y + (q.y - p.y) * t
                    let n = CampVec3(x, 0, z).normalized
                    let tipY = 4 + rnd.next() * 4
                    blade(CampVec3(x, 0.5, z), CampVec3(x + n.x * 2.5, tipY, z + n.z * 2.5), width: 1.1,
                          color: CampMaterials.mix(grass, 0x1D2412, 0.35))
                }
            }
        }
        // 岩の底（輪 4 と先端）
        func ring(_ y: Double, _ s: Double, _ off: (Double, Double) = (0, 0)) -> [CampVec3] {
            outline.map { CampVec3($0.x * s + off.0, y, $0.y * s + off.1) }
        }
        let rockRings = [ring(24, 1), ring(52, 0.74, (6, -4)), ring(84, 0.44, (10, 2)), ring(110, 0.16, (4, 6))]
        let underside = CampGeometry.loft(rockRings, inside: CampVec3(0, 50, 0), band: { k, i in (i + k) % 3 == 0 ? 1 : 0 })
        addMesh(underside[0] ?? CampMesh(), .rock, .underside, shadow: false)
        var rockDark = underside[1] ?? CampMesh()
        let tip = CampVec3(6, 128, 4)
        let last = rockRings[rockRings.count - 1]
        for i in last.indices {
            rockDark.flatTriangle(last[i], last[(i + 1) % last.count], tip, outward: CampGeometry.centroid([last[i], tip]) - CampVec3(0, 90, 0))
        }
        addMesh(rockDark, .rockDark, .underside, shadow: false)
        // 岩の底のすじ（面に沿わせる）
        func rockScale(_ y: Double) -> Double {
            if y <= 52 { return 1 - (y - 24) / 28 * 0.26 }
            return 0.74 - (y - 52) / 32 * 0.30
        }
        for i in stride(from: 0, to: outline.count, by: 4) {
            let p = outline[i]
            let y1 = 48 + rnd.next() * 10
            let a = CampVec3(p.x * rockScale(30) * 1.01, 30, p.y * rockScale(30) * 1.01)
            let b = CampVec3(p.x * rockScale(y1) * 1.01, y1, p.y * rockScale(y1) * 1.01)
            tube(a, b, 0.35, .char, .underside, shadow: false, detail: true)
        }

        // ---------- 小道（飛び石 10） ----------
        if o.stage != .fire {
            for i in 0...9 {
                let t = Double(i) / 9
                let x = -20 * s0 + t * 96 * s0 + sin(t * 3) * 8
                let z = 64 * s0 - t * 30 * s0 + (i % 2 == 1 ? 3 : -3)
                box(CampVec3(x, -0.6, z), CampVec3(7 + Double(i % 3), 1.4, 5.5), 0.6, i % 2 == 1 ? .stone : .stoneLight,
                    .path, yaw: Double(i * 37), shadow: false)
            }
        }
        // ---------- 池（キャンプ場） ----------
        if o.stage == .camp {
            var pond = CampMesh()
            let pts = (0..<26).map { i -> CampVec3 in
                let t = Double(i) / 26 * 2 * .pi
                return CampVec3(-60 + cos(t) * 26, -0.25, 58 + sin(t) * 16)
            }
            pond.flatPolygon(pts, outward: CampVec3(0, -1, 0))
            addMesh(pond, .water, .pond, shadow: false)
            for i in 0..<10 {
                let t = Double(i) / 10 * 2 * .pi
                box(CampVec3(-60 + cos(t) * 27, -1, 58 + sin(t) * 17), CampVec3(4, 2.4, 3.4), 1, .stone, .pond, yaw: t * 57,
                    shadow: false)
            }
            for i in 0..<7 {
                let x = -82 + Double(i) * 3.2, z = 50 + Double(i % 2) * 3
                tube(CampVec3(x, 0, z), CampVec3(x + 1.4, -10 - Double(i % 3) * 3, z - 1), 0.45, .reed, .pond, detail: true)
            }
        }
        // ---------- 季節の散らし（花・葉・草の点） ----------
        if !winter {
            for i in 0..<46 {
                let a = rnd.next() * 2 * .pi, d = rnd.next().squareRoot() * 100 * s0
                let x = cos(a) * d, z = sin(a) * d * 0.9
                let color: UInt32 = spring ? (i % 3 != 0 ? 0xF4C6D4 : 0xFFF6F0)
                    : (autumn ? [0xD9772E, 0xB9452A, 0xE6A63A][i % 3] : (i % 4 != 0 ? 0x6F9A48 : 0xE9E2A4))
                dot(CampVec3(x, -0.4, z), size: spring || autumn ? 1.6 : 1.1, color: color)
            }
        }

        // ---------- 岩 3 と草むら ----------
        func boulder(_ x: Double, _ z: Double, _ r0: Double, _ hgt: Double, _ seed: Int) {
            var rr = CampRandom(seed)
            let n = 10
            let jit = (0..<n).map { _ in 0.78 + rr.next() * 0.44 }
            let levels: [(Double, Double)] = [(0.96, 0.8), (1, -0.32 * hgt), (0.84, -0.72 * hgt), (0.42, -hgt)]
            let rings: [[CampVec3]] = levels.enumerated().map { k, lv in
                jit.enumerated().map { i, j in
                    let a = Double(i) / Double(n) * 2 * .pi + Double(k) * 0.13
                    return CampVec3(x + cos(a) * r0 * lv.0 * j, lv.1, z + sin(a) * r0 * lv.0 * j * 0.86)
                }
            }
            let mid = CampVec3(x, -hgt * 0.4, z)
            let parts = CampGeometry.loft(rings, inside: mid, smooth: true, band: { k, i in (i + k) % 4 == 0 ? 1 : 0 })
            addMesh(parts[0] ?? CampMesh(), .stone, .rocks)
            addMesh(parts[1] ?? CampMesh(), .rockDark, .rocks)
            var cap = CampMesh()
            cap.flatPolygon(rings[3], outward: CampVec3(0, -1, 0))
            addMesh(cap, .stone, .rocks)
            if !winter {
                for _ in 0..<6 {
                    let a = rr.next() * 6.28
                    dot(CampVec3(x + cos(a) * r0 * 0.6, -hgt * 0.8 - 0.05, z + sin(a) * r0 * 0.5), size: 1.6, color: 0xA9B07C)
                }
            } else {
                var snow = CampMesh()
                snow.flatPolygon(rings[3].map { CampVec3($0.x, $0.y - 0.6, $0.z) }, outward: CampVec3(0, -1, 0))
                addMesh(snow, .snow, .rocks)
            }
        }
        func tuft(_ x: Double, _ z: Double, _ n: Int = 7, _ hh: Double = 5) {
            guard !winter else { return }
            for i in 0..<n {
                let a = rnd.next() * 2 * .pi, d = 0.6 + rnd.next() * 1.8
                let p = CampVec3(x + cos(a) * d, 0.2, z + sin(a) * d)
                let tipY = -hh * (0.6 + rnd.next() * 0.6)
                let color = CampMaterials.mix(grass, i % 2 == 1 ? 0x1D2412 : 0xE9E2A4, i % 2 == 1 ? 0.35 : 0.18)
                blade(p, CampVec3(p.x + cos(a) * 2.2, tipY, p.z + sin(a) * 2.2), width: 0.8, color: color)
            }
        }
        if focus != .tent && o.stage != .fire {
            boulder(100 * s0, -30 * s0, 8, 7, 7)
            boulder(20 * s0, 100 * s0, 6, 5, 13)
            boulder(26 * s0, 104 * s0, 3.4, 3, 19)
            tuft(92 * s0, -24 * s0)
            tuft(14 * s0, 96 * s0)
        }

        // ---------- テント（帆布の三角・扉の中に寝袋 2 と枕） ----------
        if o.stage != .fire && show(.tent) {
            let extras = buildTent(s0: s0, winter: winter, night: night, add: add, box: box, tube: tube)
            scene.lights += extras.lights
            scene.glows += extras.glows
            let hw = CampTentSpec.halfWidth, hl = CampTentSpec.halfLength
            let tp = tentPoint(s0)
            let a = tp(-hw - 3, 0, hl), b = tp(hw + 3, 0, -hl)
            tuft(a.x, a.z)
            tuft(b.x, b.z)
        }

        // ---------- 焚き火（石の輪 10・薪 3・炎・火の粉・煙） ----------
        let fire = CampLighting.firePosition
        if show(.fire) || focus == .gear {
            let fx = fire.x, fz = fire.z
            for i in 0..<10 {
                let t = Double(i) / 10 * 2 * .pi
                box(CampVec3(fx + cos(t) * 11, -1.6, fz + sin(t) * 11),
                    CampVec3(5 + Double(i % 3), 3.4 + Double(i % 2), 4.4), 1.4, .stone, .fire, yaw: -t * 57 + 90)
            }
            var ash = CampMesh()
            ash.flatPolygon((0..<18).map { i -> CampVec3 in
                let t = Double(i) / 18 * 2 * .pi
                return CampVec3(fx + cos(t) * 9, -0.3, fz + sin(t) * 9)
            }, outward: CampVec3(0, -1, 0))
            addMesh(ash, .ash, .fire, shadow: false)
            for i in 0..<3 {
                let t = Double(i) / 3 * 2 * .pi + 0.4
                let a = CampVec3(fx + cos(t) * 10, 0, fz + sin(t) * 10)
                let b = CampVec3(fx + cos(t) * 1.5, -11, fz + sin(t) * 1.5)
                let dir = (b - a).normalized
                tube(a, a + dir * 15, 2.2, .bark, .fire, caps: [.cutEnd, .char])
            }
            scene.flame = (CampVec3(fx, -2, fz), night ? 30 : (dusk ? 26 : 20), night ? 1 : (dusk ? 0.95 : 0.85))
            if night || dusk { scene.sparks = CampVec3(fx, -16, fz) }
            if !night { scene.smoke = (CampVec3(fx, -26, fz), morning || o.time == .day ? 0.8 : 0.5) }
            scene.glows.append((CampVec3(fx, -8, fz), night ? 60 : (dusk ? 34 : 18), night ? 0.95 : 0.6))
            let light = CampLighting.of(time: o.time, season: o.season)
            scene.lights.append(CampPointLight(position: fire, color: CampLighting.fireColor,
                                               intensity: light.fireIntensity, range: light.fireRange))
        }

        // ---------- 針葉樹（5 段の裾がぎざぎざに垂れる・裏も閉じる・根元の太い幹） ----------
        if show(.trees) {
            let pines: [(Double, Double, Double)] = o.stage == .fire ? [(-42, -36, 1)]
                : (o.stage == .tent ? [(-86, -46, 1.1), (62, -70, 0.9)] : [(-96, -40, 1.15), (70, -78, 0.95), (-30, -96, 0.85)])
            for (x0, z0, s) in pines {
                let x = x0 * s0, z = z0 * s0
                addMesh(CampGeometry.lathe(origin: CampVec3(x, 0.6, z), axis: CampVec3(0, -1, 0),
                                           profile: [(3.8 * s, 0), (2.9 * s, 3 * s), (2.4 * s, 12 * s), (1.4 * s, 34 * s)],
                                           segments: 8, capEnd: true), .bark, .trees)
                let tiers: [(Double, Double, Double)] = [(23, 9, 19), (19.5, 20, 17), (15.5, 30, 16), (11.5, 40, 14), (7, 49, 13)]
                let tierColor = [0, 0, 1, 1, 2]
                for (k, tier) in tiers.enumerated() {
                    let (r, y0, h) = tier
                    let n = 14
                    let apex = CampVec3(x, -(y0 + h) * s, z)
                    let ringPts = (0..<n).map { i -> CampVec3 in
                        let a = Double(i) / Double(n) * 2 * .pi + Double(k) * 0.7
                        let rr = (i % 2 == 1 ? 0.76 : 1) * r * s
                        let dy = (i % 2 == 1 ? -1.4 : 1.1) * s
                        return CampVec3(x + cos(a) * rr, -y0 * s + dy, z + sin(a) * rr)
                    }
                    func nOf(_ p: CampVec3) -> CampVec3 { CampVec3(p.x - x, -r * 0.8 * s, p.z - z).normalized }
                    var cone = CampMesh(), under = CampMesh()
                    for i in 0..<n {
                        let a2 = ringPts[i], b2 = ringPts[(i + 1) % n]
                        cone.smoothTriangle([apex, a2, b2], [CampVec3(0, -1, 0), nOf(a2), nOf(b2)])
                    }
                    let u = CampVec3(x, -(y0 + 2.5) * s, z)
                    for i in 0..<n {
                        under.flatTriangle(ringPts[(i + 1) % n], ringPts[i], u,
                                           outward: CampGeometry.centroid([ringPts[i], ringPts[(i + 1) % n], u]) - apex)
                    }
                    addMesh(cone, .pine(tierColor[k]), .trees)
                    addMesh(under, .pineUnder, .trees, shadow: false)
                }
                tuft(x + 3, z + 4)
                tuft(x - 4, z - 3, 5)
            }
        }

        // ---------- 写真の切り絵の箱庭 ----------
        if o.stage != .fire && (show(.cutout) || focus == .trees) {
            var placed = o.cutouts
            if let placing = o.placing {
                placed.removeAll { $0.spot == placing.spot }
            }
            for c in placed { buildCutout(&scene, c, s0: s0, lift: 0) }
            if let placing = o.placing {
                buildCutout(&scene, placing, s0: s0, lift: -9)
                let sp = cutoutSpots[max(0, min(2, placing.spot))]
                let sx = sp.0 * s0, sz = sp.1 * s0
                scene.placeRing = (CampVec3(sx, -0.6, sz), 34, 24)
                scene.placeShadow = (CampVec3(sx + 3, -0.3, sz + 3), 30, 16)
            }
        }

        // ---------- 道具（椅子・保冷箱・机・ランタンの柱・薪の山） ----------
        if o.stage != .fire && show(.gear) {
            func chair(_ cx: Double, _ cz: Double) {
                let a = atan2(fire.x - cx, fire.z - cz)
                let deg = a * 180 / .pi
                func r(_ x: Double, _ y: Double, _ z: Double) -> CampVec3 {
                    CampVec3(cx + x * cos(a) + z * sin(a), y, cz - x * sin(a) + z * cos(a))
                }
                for sd in [-1.0, 1.0] {
                    tube(r(sd * 8, 0, -7), r(sd * 8, -10, 6), 0.55, .frame, .gear)
                    tube(r(sd * 8, 0, 6), r(sd * 8, -10, -7), 0.55, .frame, .gear)
                    tube(r(sd * 8.3, -9.5, -8), r(sd * 8.3, -26, -12), 0.55, .frame, .gear)
                    tube(r(sd * 8.6, -15, -9.4), r(sd * 8.6, -15, 6), 0.55, .frame, .gear)
                    box(r(sd * 8.6, -15.6, -1), CampVec3(2.2, 1, 11), 0.45, .woodDark, .gear, yaw: deg)
                    for zz in [-7.0, 6.0] {
                        box(r(sd * 8, -0.45, zz), CampVec3(1.8, 0.9, 1.8), 0.3, .rubber, .gear, yaw: deg)
                    }
                }
                let seat = (0...2).map { j in (0...3).map { i -> CampVec3 in
                    let u = Double(i) / 3, t = Double(j) / 2
                    return r(-8 + u * 16, -10 + 2.2 * sin(.pi * u) * sin(.pi * (0.2 + 0.6 * t)), 6 - t * 14)
                } }
                let back = (0...2).map { j in (0...3).map { i -> CampVec3 in
                    let u = Double(i) / 3, t = Double(j) / 2
                    return r(-8 + u * 16, -10.5 - t * 15.5, -8 - t * 4 - 1.6 * sin(.pi * u) * sin(.pi * t))
                } }
                let uvSeat: (Int, Int) -> [CampVec2] = { k, i in
                    [CampVec2(Double(i) / 3, Double(k) / 2), CampVec2(Double(i + 1) / 3, Double(k) / 2),
                     CampVec2(Double(i + 1) / 3, Double(k + 1) / 2), CampVec2(Double(i) / 3, Double(k + 1) / 2)]
                }
                for m in CampGeometry.loft(seat, inside: r(0, -40, 0), smooth: true, open: true, uv: uvSeat).values {
                    addMesh(m, .seat, .gear)
                }
                for m in CampGeometry.loft(back, inside: r(0, -16, 20), smooth: true, open: true, uv: uvSeat).values {
                    addMesh(m, .seat, .gear)
                }
            }
            chair(64 * s0, 14 * s0)
            if o.stage == .camp { chair(14, 64) }
            let cx = 82 * s0, cz = 44 * s0
            box(CampVec3(cx, -6, cz), CampVec3(18, 12, 12), 2, .cooler, .gear, yaw: 20)
            box(CampVec3(cx, -13, cz), CampVec3(19, 3, 13), 1.2, .lid, .gear, yaw: 20)
            box(CampVec3(cx - 7.5, -9, cz + 6.8), CampVec3(2, 4, 1.2), 0.4, .chrome, .gear, yaw: 20)
            box(CampVec3(cx + 6, -9, cz + 1.6), CampVec3(2, 4, 1.2), 0.4, .chrome, .gear, yaw: 20)
            if o.stage == .camp {
                let tx = 30.0, tz = -40.0
                for k in 0..<5 {
                    box(CampVec3(tx, -16, tz - 8 + Double(k) * 4), CampVec3(34, 1.6, 3.4), 0.6, k % 2 == 1 ? .wood : .woodDark, .table)
                }
                for (x, z) in [(-14.0, -8.0), (14, -8), (-14, 8), (14, 8)] {
                    tube(CampVec3(tx + x, -15, tz + z), CampVec3(tx + x * 1.1, 0, tz + z * 1.1), 0.6, .woodDark, .table)
                }
                addMesh(CampGeometry.lathe(origin: CampVec3(tx - 8, -17, tz + 2), axis: CampVec3(0, -1, 0),
                                           profile: [(2.6, 0), (2.6, 5.4), (2.9, 6)], segments: 12, capStart: true), .enamel, .table)
                add(.ring(center: CampVec3(tx - 8, -23, tz + 2), radius: 2.9, pipe: 0.3), .enamelRim, .table, shadow: false)
                addMesh(CampGeometry.lathe(origin: CampVec3(tx + 7, -17, tz - 2), axis: CampVec3(0, -1, 0),
                                           profile: [(4.4, 0), (4.8, 3), (3.6, 7), (1.4, 8.4), (0.01, 9)], segments: 12,
                                           capStart: true), .chrome, .table)
                tube(CampVec3(tx + 11, -21, tz - 2), CampVec3(tx + 15, -24, tz - 2), 0.6, .chrome, .table)
                var map = CampMesh()
                let mp = [CampVec3(tx - 4, -17.2, tz + 4), CampVec3(tx + 8, -17.2, tz + 7), CampVec3(tx + 6, -17.2, tz + 15),
                          CampVec3(tx - 6, -17.2, tz + 12)]
                map.flatPolygon(mp, outward: CampVec3(0, -1, 0), uv: [CampVec2(0, 0), CampVec2(1, 0), CampVec2(1, 1), CampVec2(0, 1)])
                addMesh(map, .paperMap, .table, shadow: false)
                // ランタンの柱
                let lx = -88.0, lz = 10.0
                tube(CampVec3(lx, 0, lz), CampVec3(lx, -52, lz), 0.9, .frame, .lantern)
                tube(CampVec3(lx, -50, lz), CampVec3(lx + 8, -50, lz), 0.5, .frame, .lantern)
                addMesh(CampGeometry.lathe(origin: CampVec3(lx + 8, -44, lz), axis: CampVec3(0, -1, 0),
                                           profile: [(3.6, 0), (3.6, 1.2), (0.01, 1.4)], segments: 10, capStart: true), .brass, .lantern)
                addMesh(CampGeometry.lathe(origin: CampVec3(lx + 8, -42.6, lz), axis: CampVec3(0, -1, 0),
                                           profile: [(3, 0), (3.2, 6), (3, 9)], segments: 10), .glassLit, .lantern, shadow: false)
                addMesh(CampGeometry.lathe(origin: CampVec3(lx + 8, -34, lz), axis: CampVec3(0, -1, 0),
                                           profile: [(3.8, 0), (3.8, 1.2), (0.01, 1.4)], segments: 10, capStart: true), .brass, .lantern)
                if night {
                    scene.glows.append((CampVec3(lx + 8, -38, lz), 22, 0.9))
                    scene.lights.append(CampPointLight(position: CampLighting.lanternPosition, color: CampLighting.lanternColor,
                                                       intensity: CampLighting.lanternIntensity, range: CampLighting.lanternRange))
                }
                // 薪の山（6 本）
                for k in 0..<6 {
                    let row = k < 3 ? 0.0 : 1.0, col = Double(k % 3)
                    let a = CampVec3(-6 + col * 5.2 + row * 2.6, -2.4 - row * 4.6, -74)
                    tube(a, a + CampVec3(0, 0, 18), 2.4, .bark, .woodpile, caps: [.cutEnd, .cutEnd])
                }
            }
        }

        addMesh(blades, .vertexColor, .scatter, shadow: false, detail: true)
        addMesh(dots, .vertexColor, .scatter, shadow: false, detail: true)
        return scene
    }

    /// テントの置き場所の座標（中心 (−34, −26) × 倍率、向き 30°）
    static func tentPoint(_ s0: Double) -> (Double, Double, Double) -> CampVec3 {
        let ta = CampTentSpec.angle * .pi / 180, tx = -34 * s0, tz = -26 * s0
        return { x, y, z in CampVec3(tx + x * cos(ta) + z * sin(ta), y, tz - x * sin(ta) + z * cos(ta)) }
    }

    /// テントのフライの格子（片側 4 段 × 6 列・中央が 1.8 内へ沈む）。`side` は −1 / 1
    static func flyRows(side sd: Double, s0: Double) -> [[CampVec3]] {
        let hw = CampTentSpec.halfWidth, hl = CampTentSpec.halfLength, ht = CampTentSpec.height, ov = CampTentSpec.overhang
        let tp = tentPoint(s0)
        return (0...3).map { j in
            let t = Double(j) / 3
            return (0...5).map { i in
                let u = Double(i) / 5, z = -hl - ov + u * (2 * hl + 2 * ov)
                let sag = 1.8 * sin(.pi * t) * (0.55 + 0.45 * sin(.pi * u))
                let ex = sd * (hw + 2)
                var x = ex * (1 - t), y = 1 + (-ht - 1) * t
                let nx = sd * ht, ny = -(hw + 2), nl = hypot(nx, ny)
                x -= nx / nl * sag
                y -= ny / nl * sag
                return tp(x, y, z)
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private static func buildTent(s0: Double, winter: Bool, night: Bool,
                                  add: (CampShape, CampMaterialKey, CampGroup, Bool, Bool) -> Void,
                                  box: (CampVec3, CampVec3, Double, CampMaterialKey, CampGroup, Double, Double, CampMaterialKey?, Bool, Bool) -> Void,
                                  tube: (CampVec3, CampVec3, Double, CampMaterialKey, CampGroup, [CampMaterialKey]?, Bool, Bool) -> Void)
        -> (lights: [CampPointLight], glows: [(position: CampVec3, radius: Double, opacity: Double)]) {
        let hw = CampTentSpec.halfWidth, hl = CampTentSpec.halfLength, ht = CampTentSpec.height, ov = CampTentSpec.overhang
        let tp = tentPoint(s0)
        let inside = tp(0, -12, 0)
        // フライ（両側）
        for sd in [-1.0, 1.0] {
            let rows = flyRows(side: sd, s0: s0)
            let uv: (Int, Int) -> [CampVec2] = { k, i in
                [CampVec2(Double(i) / 5, Double(k) / 3), CampVec2(Double(i + 1) / 5, Double(k) / 3),
                 CampVec2(Double(i + 1) / 5, Double(k + 1) / 3), CampVec2(Double(i) / 5, Double(k + 1) / 3)]
            }
            for m in CampGeometry.loft(rows, inside: inside, smooth: true, open: true, uv: uv).values {
                add(.mesh(m), .fly, .tent, true, false)
            }
            // 裾の張り出しの金具・張り綱・木の自在・ペグ
            for i in [1, 4] {
                let e = rows[0][i]
                let peg = tp(sd * (hw + 17), 0, -hl - ov + Double(i) / 5 * (2 * hl + 2 * ov))
                box(e + CampVec3(0, -0.6, 0), CampVec3(2.4, 1.2, 2.4), 0.5, .brass, .tent, 0, 0, nil, true, false)
                tube(e, peg, 0.2, .rope, .tent, nil, false, false)
                box(e + (peg - e) * 0.68, CampVec3(1.6, 0.8, 0.8), 0.3, .woodDark, .tent, 0, 0, nil, false, false)
                box(peg + CampVec3(0, -1.2, 0), CampVec3(0.9, 3.2, 0.9), 0.3, .chrome, .tent, 0, 0, nil, true, false)
            }
            if winter {
                let snowRows = rows.dropFirst().map { r in r.map { p in p + (p - inside).normalized * 0.7 } }
                for m in CampGeometry.loft(Array(snowRows), inside: inside, smooth: true, open: true).values {
                    add(.mesh(m), .snow, .tent, false, false)
                }
            }
        }
        // 棟の縫い目（細い筒）
        tube(tp(0, -ht - 0.4, -hl - ov), tp(0, -ht - 0.4, hl + ov), 0.5, .fly, .tent, nil, false, false)
        // 前後の支柱（アルミ）と真鍮の先・ゴムの足
        for zz in [hl + 1.2, -hl - 1.2] {
            tube(tp(0, 0, zz), tp(0, -ht - 1, zz), 0.75, .alu, .tent, nil, true, false)
            add(.taper(from: tp(0, -ht - 1, zz), to: tp(0, -ht - 1 - 3.4, zz), radius0: 0.45, radius1: 0.45), .brass, .tent, false, false)
            add(.taper(from: tp(0, -ht - 1 - 3.4, zz), to: tp(0, -ht - 1 - 4.4, zz), radius0: 0.45, radius1: 0.01), .brass, .tent, false, false)
            box(tp(0, -0.4, zz), CampVec3(2.4, 0.8, 2.4), 0.3, .rubber, .tent, 30, 0, nil, false, false)
        }
        // 妻壁: 裏は無地、表は扉の穴（本当の穴）
        let a1 = tp(-hw, 0, hl), b1 = tp(hw, 0, hl), rf = tp(0, CampTentSpec.wallTop, hl)
        let a2 = tp(-hw, 0, -hl), b2 = tp(hw, 0, -hl), rb = tp(0, CampTentSpec.wallTop, -hl)
        let dl = tp(-CampTentSpec.doorHalf, 0, hl), dr = tp(CampTentSpec.doorHalf, 0, hl), dt = tp(0, CampTentSpec.doorTop, hl)
        let front = (tp(0, 0, 1) - tp(0, 0, 0)).normalized
        func wallUV(_ lx: Double, _ ly: Double) -> CampVec2 { CampVec2((lx + hw) / (2 * hw), -ly / ht) }
        var back = CampMesh()
        back.flatPolygon([a2, rb, b2], outward: -front, uv: [wallUV(-hw, 0), wallUV(0, CampTentSpec.wallTop), wallUV(hw, 0)])
        add(.mesh(back), .tentEnd, .tent, true, false)
        var frontWall = CampMesh()
        frontWall.flatPolygon([a1, dl, dt, dr, b1, rf], outward: front,
                              uv: [wallUV(-hw, 0), wallUV(-CampTentSpec.doorHalf, 0), wallUV(0, CampTentSpec.doorTop),
                                   wallUV(CampTentSpec.doorHalf, 0), wallUV(hw, 0), wallUV(0, CampTentSpec.wallTop)])
        add(.mesh(frontWall), .tentEndFront, .tent, true, false)
        // 結んだ扉布 2 と木のトグル
        var flaps = CampMesh()
        flaps.flatTriangle(tp(-10, 0, hl + 0.4), tp(-0.6, CampTentSpec.doorTop - 0.6, hl + 0.4), tp(-17, -8, hl + 5), outward: front)
        flaps.flatTriangle(tp(10, 0, hl + 0.4), tp(0.6, CampTentSpec.doorTop - 0.6, hl + 0.4), tp(17, -8, hl + 5), outward: front)
        add(.mesh(flaps), .flap, .tent, true, false)
        for sd in [-1.0, 1.0] {
            let p = tp(sd * 16, -8.6, hl + 4.6), q = tp(sd * 13, -11, hl + 3)
            tube(p, p + (q - p).normalized * 2.4, 0.7, .woodDark, .tent, nil, false, false)
            tube(tp(sd * 16, -8, hl + 4.6), tp(sd * 19, -12, hl + 0.2), 0.2, .char, .tent, nil, false, true)
        }
        // 棟の端の張り綱 2
        for sgn in [1.0, -1.0] {
            let top = tp(0, -ht, sgn * (hl + ov)), peg = tp(0, 0, sgn * (hl + ov + 22))
            tube(top, peg, 0.22, .rope, .tent, nil, false, false)
            box(top + (peg - top) * 0.7, CampVec3(0.8, 0.8, 1.6), 0.3, .woodDark, .tent, 30, 0, nil, false, false)
            box(peg + CampVec3(0, -1.2, 0), CampVec3(0.9, 3.2, 0.9), 0.3, .chrome, .tent, 0, 0, nil, true, false)
        }
        // 床のシートは扉の前に 1.8 出る
        box(tp(0, -0.25, hl + 0.9), CampVec3(20, 0.5, 1.8), 0.2, .groundSheet, .tent, 30, 0, nil, false, false)

        // テントの中（内幕は壁から 3 内側・奥の壁 z −28・寝袋 2・枕・床）。扉の穴からだけ見える
        let toDoor = front
        var innerBack = CampMesh()
        innerBack.flatPolygon([tp(-hw + 3, 0, -hl + 2), tp(0, -ht + 4, -hl + 2), tp(hw - 3, 0, -hl + 2)], outward: toDoor)
        add(.mesh(innerBack), .innerBack, .tentInside, false, false)
        let axis = tp(0, -12, 0)
        var sideA = CampMesh(), sideB = CampMesh()
        let qa = [tp(-hw + 3, 0, hl), tp(-hw + 3, 0, -hl + 2), tp(0, -ht + 4, -hl + 2), tp(0, -ht + 4, hl)]
        let qb = [tp(hw - 3, 0, hl), tp(hw - 3, 0, -hl + 2), tp(0, -ht + 4, -hl + 2), tp(0, -ht + 4, hl)]
        sideA.flatPolygon(qa, outward: axis - CampGeometry.centroid(qa))
        sideB.flatPolygon(qb, outward: axis - CampGeometry.centroid(qb))
        add(.mesh(sideA), .innerSideA, .tentInside, false, false)
        add(.mesh(sideB), .innerSideB, .tentInside, false, false)
        var floor = CampMesh()
        floor.flatPolygon([tp(-hw + 3, -0.05, hl), tp(hw - 3, -0.05, hl), tp(hw - 3, -0.05, -hl + 2), tp(-hw + 3, -0.05, -hl + 2)],
                          outward: CampVec3(0, -1, 0))
        add(.mesh(floor), .innerFloor, .tentInside, false, false)
        let bags: [(Double, Double, CampMaterialKey, CampMaterialKey, CampMaterialKey)] = [
            (-13, -2, .bag1, .bag1Top, .quilt1), (2, 13, .bag2, .bag2Top, .quilt2),
        ]
        for (x0, x1, side, top, quilt) in bags {
            let cx = (x0 + x1) / 2
            let z0 = -hl + 4, z1 = hl - 7
            box(tp(cx, -2.1, (z0 + z1) / 2), CampVec3(x1 - x0, 4.2, z1 - z0), 1.2, side, .tentInside, 30, 0, top, false, false)
            // キルトの線 4
            for k in 1..<5 {
                let zz = z0 + Double(k) * (2 * hl - 11) / 5
                box(tp(cx, -4.25, zz), CampVec3(x1 - x0 - 1.2, 0.15, 0.4), 0, quilt, .tentInside, 30, 0, nil, false, false)
            }
            // 枕（幅 9・高さ 2.4）
            box(tp(cx, -5.4, -hl + 6), CampVec3(9, 2.4, 6), 1, .pillow, .tentInside, 30, 0, nil, false, false)
        }
        guard night else { return ([], []) }
        // 天井の灯り（内壁を照らす）と、扉の前にこぼれる光
        return ([CampPointLight(position: tp(0, -ht + 10, -4), color: 0xFFD08A, intensity: 1.2, range: 30)],
                [(tp(0, -10, hl + 6), 26, 0.55), (tp(0, -ht + 10, -4), 16, 0.9)])
    }

    /// 切り絵の箱庭 1 つ（3 枚の紙・木の台と溝 3・真鍮の留め具 6）。`lift` は置く前の浮き（−9）
    static func buildCutout(_ scene: inout CampScene, _ c: CampPlacedCutout, s0: Double, lift: Double) {
        let sp = cutoutSpots[max(0, min(2, c.spot))]
        let sx = sp.0 * s0, sz = sp.1 * s0
        let ang = cutoutAngle * .pi / 180
        let ux = CampVec3(cos(ang), 0, -sin(ang)), nz = CampVec3(sin(ang), 0, cos(ang))
        let iw = CampCutLayers.cardWidth, w = cutoutWidth, k = w / iw
        for (li, layer) in c.layers.layers.enumerated() {
            let ih = layer.height + 2 * CampCutLayers.margin, h = ih * k, dz = layerDepths[min(li, 2)]
            let topLeft = CampVec3(sx, -h + lift - 1.5, sz) + ux * (-w / 2) + nz * dz
            func at(_ u: Double, _ v: Double, _ d: Double) -> CampVec3 {
                topLeft + ux * (u * k) + CampVec3(0, v * k, 0) + nz * d
            }
            let rim = CampCutLayers.rimOutline(layer)
            let slab = CampGeometry.slab(rim, thickness: paperThickness, size: CampVec2(iw, ih), map: at)
            var front = CampPiece(shape: .mesh(slab.front), material: .cutoutFront(c.id, li), group: .cutout)
            front.cutout = c.id
            front.layer = li
            var back = CampPiece(shape: .mesh(slab.back), material: .paperBack, group: .cutout)
            back.cutout = c.id
            back.layer = li
            var edge = CampPiece(shape: .mesh(slab.edge), material: .paperEdge, group: .cutout, castsShadow: false)
            edge.cutout = c.id
            edge.layer = li
            scene.pieces += [front, back, edge]
            for u in [-14.0, 14.0] {
                var clip = CampPiece(shape: .box(center: CampVec3(sx, -5.4 + lift, sz) + ux * u + nz * (dz + 1.3),
                                                 size: CampVec3(3.4, 2.6, 0.7), chamfer: 0.3, yaw: cutoutAngle, roll: 0, top: nil),
                                     material: .brass, group: .cutout, castsShadow: false)
                clip.cutout = c.id
                scene.pieces.append(clip)
            }
        }
        var base = CampPiece(shape: .box(center: CampVec3(sx, -2.2 + lift, sz) + nz * -0.8, size: CampVec3(50, 4.4, 17),
                                         chamfer: 1.4, yaw: cutoutAngle, roll: 0, top: nil),
                             material: .woodDark, group: .cutout)
        base.cutout = c.id
        scene.pieces.append(base)
        for dz in layerDepths {
            var groove = CampPiece(shape: .box(center: CampVec3(sx, -4.45 + lift, sz) + nz * dz, size: CampVec3(46, 0.2, 0.9),
                                               chamfer: 0, yaw: cutoutAngle, roll: 0, top: nil),
                                   material: .grooves, group: .cutout, castsShadow: false, detail: true)
            groove.cutout = c.id
            scene.pieces.append(groove)
        }
    }
}
