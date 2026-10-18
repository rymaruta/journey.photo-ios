import Foundation

// キャンピングカーの組み立て図（2026-10-18・札 #307）。
//
// 板「写真で作るキャンピングカー」の部品（Camper.dc.html と r3.js の多面体・寸法の付箋）を、**閉じた立体の部品の並び**に
// 写したもの。SceneKit の側はこの並びを1つずつ `SCNNode` にするだけ（`CamperSceneView`）。
//
// 🔴 owner「内部も外部もどこから見てもホンモノにする」（2026-10-18）: 板や絵でごまかさない。
// - 窓は壁に開けた穴（厚み 4・ゴムの縁とクロームの枠も立体・ガラスは表から 2.2 奥の薄い板）
// - 扉は壁の穴に入った厚み 2.4 の板で、後ろの辺の蝶番で開く（外は塗装・内は内装の色・窓と取っ手 2）
// - 室内は床・内壁・天井・家具まで箱で組む（窓越しにも扉からも見える）
// - 底は床板、車輪の切り欠きの内側は泥よけの筒、床下に車台（フレーム・横梁・車軸・デフ・板ばね・
//   プロペラシャフト・燃料と水のタンク・マフラー・排気管・泥よけ）
// 線（継ぎ目・溝）も、細い溝は面の塗り分けか、厚みのある細い部品で作る（板の SVG の線を絵で貼らない）。
//
// 座標は板の単位で、上が +Y・地面が 0（板の `y` は `Y = 62 - y`）。SceneKit へは 1/100 にして渡す。

/// 部品の形
enum CamperShape: Sendable {
    /// 網（材質は網の束ごと）
    case mesh(CamperMesh)
    /// 角を丸めた箱（幅 X・高さ Y・奥行き Z）
    case box(CV3, chamfer: Double)
    /// 円柱（軸は Y）
    case cylinder(radius: Double, height: Double, segments: Int)
    /// 輪（軸は Y）
    case torus(ring: Double, pipe: Double)
    case sphere(radius: Double)
    /// 文字（ナンバー）。押し出しの厚み・字の高さ
    case text(String, height: Double, depth: Double)
}

/// 開け閉めで動く部品の組
enum CamperGroup: Sendable, Equatable {
    case body
    /// 扉（蝶番のまわりに回る）
    case door
    /// 夜、窓から地面へこぼれる灯りの溜まり（まとめない・影を落とさない）
    case glow
    /// 夜、開けた扉の口から地面へこぼれる灯り（扉を開けた時だけ見える）
    case doorGlow
}

/// 部品1つ
struct CamperNodeSpec: Sendable {
    var name: String
    var shape: CamperShape
    var material: CamperMaterial
    /// 置き場所（板の単位・上が +Y）
    var position: CV3
    var orientation: CQuat = .identity
    var scale = CV3(1, 1, 1)
    var group: CamperGroup = .body
    /// どの分類の部品か（影絵の見本と試験に使う）
    var category: CamperCategory?

    /// 内張りの材質（壁・床・天井の室内の側）。室内の灯りはここと `interior.` の部品だけを照らす
    static func isInteriorMaterial(_ m: CamperMaterial) -> Bool {
        switch m {
        case .inner, .ceiling, .floorIn, .wallWood: return true
        default: return false
        }
    }

    /// 室内の灯りが照らす所と、そうでない所に分ける（2026-10-18 Mac の絵 run 532）。
    /// SceneKit の omni は影を落とさないので、室内の灯りが壁を抜けて屋根の縁・窓枠・荷台の棒を下から照らし、
    /// 夜に細い光の筋がちらついた。灯りの組（categoryBitMask）を分けて、壁の外へ光が漏れないようにする。
    /// 扉の組は外（開けると扉の板は外に立つ）
    func splitForInteriorLight() -> (inside: CamperNodeSpec?, outside: CamperNodeSpec?) {
        guard group == .body else { return (nil, self) }
        if name.hasPrefix("interior.") { return (self, nil) }
        guard case .mesh(let m) = shape else { return (nil, self) }
        let parts = m.split(Self.isInteriorMaterial)
        var inside = self, outside = self
        inside.shape = .mesh(parts.matched)
        outside.shape = .mesh(parts.rest)
        return (parts.matched.isEmpty ? nil : inside, parts.rest.isEmpty ? nil : outside)
    }

    /// 三角形の数の目安（試験と性能の見張り）
    var triangleEstimate: Int {
        switch shape {
        case .mesh(let m): return m.triangleCount
        // 角の丸めは SceneKit の段数（`CamperScene` が 0.8 を超えたら 3 段・それ以下は 1 段）で数える:
        // 面 12・辺 12 本 × 段 × 2・角 8 × 段²（2026-10-18: 以前はどちらも 124 と見積もっていた）
        case .box(_, let c):
            guard c > 0 else { return 12 }
            let seg = c > 0.8 ? 3 : 1
            return 12 + 12 * seg * 2 + 8 * seg * seg
        case .cylinder(_, _, let s): return s * 4
        case .torus: return 24 * 12 * 2
        case .sphere: return 24 * 12 * 2
        case .text(let s, _, _): return s.count * 120
        }
    }
}

/// 灯り（夜）
struct CamperLightSpec: Sendable, Equatable {
    enum Kind: Sendable { case omni, spot }
    var name: String
    var kind: Kind
    var position: CV3
    /// spot の向き（板の単位の向き）
    var direction = CV3(0, -1, 0)
    var color: UInt32
    /// SceneKit の強さ（ルーメンの目安。実機で合わせる）
    var intensity: Double
    /// 届く距離（板の単位）
    var range: Double
    var group: CamperGroup = .body

    /// 室内の灯り（室内の部品だけを照らす。壁の外の縁・扉・屋根の棒に光の筋を乗せない）
    var inside: Bool { name.hasPrefix("interior.") }
}

/// 見る向き（カメラの寄り）
struct CamperAngle: Sendable, Equatable {
    /// 狙う点（板の単位）
    var target: CV3
    /// 横の回り（度。板の ry）
    var yaw: Double
    /// 見下ろす角度（度。板の -rx）
    var elevation: Double
    /// 寄りの倍率（板の zoom）
    var zoom: Double
}

/// 組み立て図
struct CamperBlueprint: Sendable {
    var nodes: [CamperNodeSpec] = []
    var lights: [CamperLightSpec] = []
    /// 扉の蝶番（回る軸は Y）と、開いたときの角度（ラジアン・外へ）
    var doorHinge = CV3(33.5, 0, 50)
    var doorOpenAngle = -100.0 * .pi / 180
    /// 車の外形（影・床の大きさ・寄りの計算に使う）
    var length: ClosedRange<Double> = -122...120
    var halfWidth = 50.0

    var triangleEstimate: Int { nodes.reduce(0) { $0 + $1.triangleEstimate } }
    func nodes(named prefix: String) -> [CamperNodeSpec] { nodes.filter { $0.name.hasPrefix(prefix) } }
}

/// 何を組むか
struct CamperConfig: Equatable, Sendable {
    var stage: CamperStage
    var mood: CamperMood
    var loadout: CamperLoadout
    /// ナンバーの数字の元（投稿の数）
    var posts: Int
    /// 影絵で見せる分類（まだ持っていない部品を試しに見ている）
    var silhouette: CamperCategory?

    init(stage: CamperStage, mood: CamperMood = .day, loadout: CamperLoadout = .standard, posts: Int = 0,
         silhouette: CamperCategory? = nil) {
        self.stage = stage
        self.mood = mood
        self.loadout = loadout
        self.posts = posts
        self.silhouette = silhouette
    }
}

// MARK: - 組み立て

struct CamperBuilder {

    /// 板の点（下が +y・地面 62）を上が +Y・地面 0 へ
    static func B(_ x: Double, _ y: Double, _ z: Double) -> CV3 { CV3(x, 62 - y, z) }
    static func Bd(_ x: Double, _ y: Double, _ z: Double) -> CV3 { CV3(x, -y, z) }
    static func B2(_ x: Double, _ y: Double) -> CV2 { CV2(x, 62 - y) }
    func B(_ x: Double, _ y: Double, _ z: Double) -> CV3 { Self.B(x, y, z) }
    func Bd(_ x: Double, _ y: Double, _ z: Double) -> CV3 { Self.Bd(x, y, z) }
    func B2(_ x: Double, _ y: Double) -> CV2 { Self.B2(x, y) }

    let config: CamperConfig
    var out = CamperBlueprint()

    var stage: CamperStage { config.stage }
    var night: Bool { config.mood == .night }
    var snow: Bool { config.mood == .snow }
    var van: Bool { config.stage == .van }

    // 車体の寸法（板の付箋「寸法」）
    var BW: Double { van ? 48 : 50 }
    let wall = 4.0
    let bevel = 2.6
    var wheels: [Double] { van ? [-62, 86] : [-70, 88] }
    var front: Double { van ? 119 : 120 }
    var rear: Double { van ? -100 : -122 }
    var roofTop: Double { van ? 126 : 134 }
    /// 塗り分けの境（上が +Y）。生成りはここより上
    var capY: Double { van ? 92 : 112 }
    let wheelY = 22.0
    let wheelR = 22.0
    let archR = 26.0
    /// 泥よけの筒の内側の端（Z）
    var wellInner: Double { BW - wall - 18 }

    init(config: CamperConfig) {
        self.config = config
    }

    // MARK: 部品を足す道具

    mutating func add(_ name: String, _ shape: CamperShape, _ m: CamperMaterial, at p: CV3, _ q: CQuat = .identity,
                      group: CamperGroup = .body, category: CamperCategory? = nil, scale: CV3 = CV3(1, 1, 1)) {
        out.nodes.append(CamperNodeSpec(name: name, shape: shape, material: m, position: p, orientation: q, scale: scale,
                                        group: group, category: category))
    }

    /// 角を丸めた箱（板の rbox: 真ん中・大きさ・角の丸み。板の座標）
    mutating func rbox(_ name: String, _ c: CV3, _ s: CV3, _ r: Double, _ m: CamperMaterial, _ q: CQuat = .identity,
                       group: CamperGroup = .body, category: CamperCategory? = nil) {
        let chamfer = max(0, min(r, min(s.x, s.y, s.z) * 0.45))
        add(name, .box(s, chamfer: chamfer), m, at: c, q, group: group, category: category)
    }

    /// 棒（2点の間の円柱）
    mutating func rod(_ name: String, _ a: CV3, _ b: CV3, _ r: Double, _ m: CamperMaterial, segments: Int = 10,
                      group: CamperGroup = .body, category: CamperCategory? = nil) {
        let d = b - a
        add(name, .cylinder(radius: r, height: d.length, segments: segments), m, at: (a + b) * 0.5,
            CQuat.yTo(d), group: group, category: category)
    }

    /// 旋盤の部品（板の lathe: 原点・軸・断面 (半径, 高さ)）
    mutating func lathe(_ name: String, _ origin: CV3, axis: CV3, _ profile: [(Double, Double)], segments: Int,
                        faceted: Bool = false, start: Double = 0, capStart: CamperMaterial? = nil,
                        capEnd: CamperMaterial? = nil, group: CamperGroup = .body, category: CamperCategory? = nil,
                        material: (Int) -> CamperMaterial) {
        let mesh = CamperMeshKit.lathe(profile.map { CV2($0.0, $0.1) }, segments: segments, faceted: faceted, start: start,
                                       material: material, capStart: capStart, capEnd: capEnd)
        add(name, .mesh(mesh), material(0), at: origin, CQuat.yTo(axis), group: group, category: category)
    }

    mutating func mesh(_ name: String, _ m: CamperMesh, group: CamperGroup = .body, category: CamperCategory? = nil) {
        guard !m.isEmpty else { return }
        add(name, .mesh(m), m.materials.first ?? .black, at: .zero, group: group, category: category)
    }

    // MARK: 塗り分け

    /// 表の塗り分け（真鍮の線は面の塗り分け。線を絵で貼らない）
    var bands: [CamperBand] {
        let c = capY
        return [
            CamperBand(minY: -.infinity, maxY: 43, material: .deep),
            CamperBand(minY: 43, maxY: 44, material: .pinstripe),
            CamperBand(minY: 44, maxY: c - 3.25, material: .paint),
            CamperBand(minY: c - 3.25, maxY: c - 2.75, material: .pinstripeDark),
            CamperBand(minY: c - 2.75, maxY: c - 1.85, material: .paint),
            CamperBand(minY: c - 1.85, maxY: c - 0.15, material: .pinstripe),
            CamperBand(minY: c - 0.15, maxY: c, material: .paint),
            CamperBand(minY: c, maxY: .infinity, material: .cap),
        ]
    }

    var coarse: [CamperBand] {
        [CamperBand(minY: -.infinity, maxY: 44, material: .deep),
         CamperBand(minY: 44, maxY: capY, material: .paint),
         CamperBand(minY: capY, maxY: .infinity, material: .cap)]
    }

    // MARK: 横の形

    /// 横の形（板の頂点・角の丸み・辺の名前）と、下の辺の車輪の切り欠き
    var profile: (points: [CV2], tags: [String]) {
        let corners: [(CV2, Double, String)] = van
            ? [(B2(-100, 36), 4, "rear"), (B2(-100, -64), 12, "roof"), (B2(54, -64), 14, "glass"), (B2(88, -12), 6, "hood"),
               (B2(116, -2), 8, "front"), (B2(119, 36), 4, "bottom")]
            : [(B2(-122, 36), 4, "rear"), (B2(-122, -72), 10, "roof"), (B2(72, -72), 12, "nose"), (B2(84, -48), 7, "under"),
               (B2(62, -37), 4, "glass"), (B2(88, -6), 6, "hood"), (B2(117, 1), 8, "front"), (B2(120, 36), 4, "bottom")]
        let r = CamperPolygon.rounded(corners.map { (p: $0.0, r: $0.1, tag: $0.2) })
        var points: [CV2] = []
        var tags: [String] = []
        // 下の辺（前の角のあと）に、前の車輪・後ろの車輪の切り欠きを入れる（板の archPts）
        let a0 = asin(4 / archR)
        for (i, p) in r.points.enumerated() {
            points.append(p)
            tags.append(r.tags[i])
            if i == r.points.count - 1 {
                for cx in wheels.reversed() {
                    for k in 0...10 {
                        let t = a0 + (Double.pi - 2 * a0) * Double(k) / 10
                        points.append(CV2(cx + cos(t) * archR, wheelY + sin(t) * archR))
                        tags.append(k == 10 ? "bottom" : "arch")
                    }
                }
            }
        }
        return CamperPolygon.ccwTagged(points, tags)
    }

    func sideMaterial(_ tag: String?, _ y: Double) -> CamperMaterial {
        switch tag {
        case "arch"?: return .well
        case "bottom"?: return .under
        default: return CamperMeshKit.material(at: y, in: coarse)
        }
    }

    // MARK: 窓と扉（板の座標の角丸の四角）

    func rr(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> [CV2] {
        CamperPolygon.roundedRect(x: x, y: 62 - y - h, w: w, h: h, r: r)
    }

    /// 扉の口（板 CamperSpec の扉 x33.5〜56.5・y−46.5〜30.5。バンは窓の小さい扉を x−10〜16 に）
    var doorHole: [CV2] { van ? rr(-10, -50, 26, 80, 2) : rr(33.5, -46.5, 23, 77, 2) }
    var doorWindow: [CV2] { van ? rr(-6, -48, 14, 14, 3) : rr(37, -42, 14, 15, 3) }

    /// 運転席の扉の口: 外形を 4 内へ寄せた形を、扉の前後と床の高さで切る（板の継ぎ目は外形からはみ出す所がある）
    var cabDoor: [CV2] {
        // 車輪の切り欠き（上の端 Y=48）より上だけを先に切り出してから寄せる（切り欠きの凹みで形が崩れない）
        let upper = CamperPolygon.clipY(profile.points, min: 49, max: 500)
        let inset = CamperPolygon.offset(upper, by: -4)
        let x0 = van ? 56.0 : 65.0
        // 上は板の継ぎ目の高さまで（運転席の上の張り出しの凹みを切り離す。凹んだ形を縦に切ると重なった辺が残る）
        return CamperPolygon.cleaned(CamperPolygon.clipY(CamperPolygon.clipX(inset, min: x0, max: 99), min: 0, max: van ? 120 : 97))
    }

    /// 運転席の窓（扉の口を 3 内へ・下は板の窓の下の高さ）
    var cabWindow: [CV2] {
        let inset = CamperPolygon.offset(cabDoor, by: -3.2)
        return CamperPolygon.cleaned(CamperPolygon.clipY(inset, min: van ? 84 : 72, max: 200))
    }

    var windowsNear: [[CV2]] {
        van ? windowShapes(-92, -54, 34, 18, 3) + windowShapes(-50, -54, 34, 18, 3)
            : windowShapes(-112, -46, 48, 25, 4) + windowShapes(-22, -46, 38, 21, 4)
    }

    var windowsFar: [[CV2]] {
        van ? windowShapes(-92, -54, 34, 18, 3) + windowShapes(-50, -54, 34, 18, 3) + windowShapes(-8, -54, 34, 18, 3)
            : windowShapes(-96, -46, 54, 23, 4) + windowShapes(2.5, -44, 24, 15, 3)  // B は板の x2 から 0.5 ずらす（A の角と一直線に並ぶと三角形に分ける所で細い隙間が出た・2026-10-18 判断）
    }

    /// 反対側の点検口（板の継ぎ目 x−116〜−100・y−8〜12）
    var hatch: [CV2] { van ? rr(-94, -8, 16, 20, 1.5) : rr(-116, -8, 16, 20, 1.5) }

    // MARK: 全体

    static func build(_ config: CamperConfig) -> CamperBlueprint {
        var b = CamperBuilder(config: config)
        b.out.length = (config.stage == .trailer ? -264 : (config.stage == .van ? -100 : -122))...(config.stage == .van ? 119 : 120)
        b.out.halfWidth = b.BW
        b.out.doorHinge = CV3(b.doorHole.map(\.x).min() ?? 33.5, 0, b.BW)
        b.shell()
        b.sides()
        b.doors()
        b.interior()
        b.exterior()
        b.frontFace()
        b.rearFace()
        b.allWheels()
        b.roof()
        b.underbody()
        b.awning()
        b.stickers()
        b.bikeRack()
        b.roofTent()
        b.campsite()
        b.wallSeams()
        if config.stage == .trailer { b.trailer() }
        b.nightLights()
        b.applyWallWood()
        b.applySilhouette()
        return b.out
    }

    /// 内壁の色を壁の木の部品にする（殻の内張り・横の壁の裏・扉の内側・泥よけの筒の室内側）
    mutating func applyWallWood() {
        let wood = wallMaterial
        out.nodes = out.nodes.map { n in
            var m = n
            if m.material == .inner { m.material = wood }
            if case .mesh(var mesh) = n.shape, mesh.groups.contains(where: { $0.material == .inner }) {
                mesh.groups = mesh.groups.map { $0.material == .inner ? (wood, $0.indices) : $0 }
                // 同じ材質が 2 つになったらまとめる
                var merged: [(material: CamperMaterial, indices: [Int32])] = []
                for g in mesh.groups {
                    if let i = merged.firstIndex(where: { $0.material == g.material }) { merged[i].indices += g.indices } else { merged.append(g) }
                }
                mesh.groups = merged
                m.shape = .mesh(mesh)
            }
            return m
        }
    }

    /// まだ持っていない部品を試しに見るときは、その分類の部品を影絵にする（板: 黒に細い灰の縁）
    mutating func applySilhouette() {
        guard let cat = config.silhouette else { return }
        out.nodes = out.nodes.map { n in
            guard n.category == cat else { return n }
            var m = n
            m.material = .silhouette
            if case .mesh(var mesh) = n.shape {
                var merged = CamperMesh()
                merged.positions = mesh.positions
                merged.normals = mesh.normals
                merged.uvs = mesh.uvs
                merged.groups = [(.silhouette, mesh.groups.flatMap(\.indices))]
                mesh = merged
                m.shape = .mesh(mesh)
            }
            return m
        }
    }

    // MARK: 車体の殻（屋根・前・後ろ・床・泥よけの筒）

    mutating func shell() {
        let (pts, tags) = CamperPolygon.split(profile.points, tags: profile.tags, atY: [44, capY])
        let (p, t) = CamperPolygon.ccwTagged(pts, tags)
        let zr = BW - wall
        var m = CamperMesh()
        // 外: 屋根・前・後ろ・運転席の上の張り出し。下の平らな辺と切り欠きは床板と泥よけの筒が受け持つ
        let isVan = van
        let skip: (Int) -> Bool = { i in
            let a = p[i], b = p[(i + 1) % p.count]
            if t[i] == "arch" { return true }
            if t[i] == "rear" && !isVan { return abs(a.x - b.x) < 0.01 } // 後ろの平らな壁は窓のある板（rearWall）
            if t[i] == "bottom" && abs(a.y - 26) < 0.01 && abs(b.y - 26) < 0.01 { return true }
            return false
        }
        CamperMeshKit.strip(&m, a: p, za: zr, b: p, zb: -zr, tiltA: 0, tiltB: 0, skip: skip) { i in
            let y = (p[i].y + p[(i + 1) % p.count].y) / 2
            switch t[i] {
            case "roof": return .roof
            case "under": return .under
            case "glass": return .glass
            case "bottom": return .under
            default: return CamperMeshKit.material(at: y, in: self.coarse)
            }
        }
        // 内張り（内向き・0.6 内へ）。フロントガラスには張らない
        let inner = CamperPolygon.offset(p, by: -0.6)
        var lining = CamperMesh()
        let n = p.count
        for i in 0..<n where !skip(i) && t[i] != "glass" {
            let j = (i + 1) % n
            let a = inner[i], b = inner[j]
            let d = b - a
            let l = max(d.length, 1e-9)
            let nn = CV3(-d.y / l, d.x / l, 0) // 内向き
            let mat: CamperMaterial = t[i] == "roof" ? .ceiling : (t[i] == "hood" || t[i] == "front" ? .dash : .inner)
            lining.quad(CV3(a.x, a.y, zr), CV3(b.x, b.y, zr), CV3(b.x, b.y, -zr), CV3(a.x, a.y, -zr), nn, nn, nn, nn, mat)
        }
        m.append(lining)
        mesh("body.shell", m)
        if !van { rearWall() }
        floorPan()
        wells()
    }

    /// 後ろの壁（窓の穴・厚み 4）。外は -X を向く
    mutating func rearWall() {
        let zr = BW - wall
        let y0 = 26 + 4.0, y1 = roofTop - 10
        let outline = [CV2(-zr, y0), CV2(zr, y0), CV2(zr, y1), CV2(-zr, y1)]
        // 後ろの窓（板 z −18〜14・y −52〜−38）。板の z は手前が +。後ろから見て左右が入れ替わるので z をそのまま u に
        let window = CamperPolygon.roundedRect(x: -18, y: 62 + 38, w: 32, h: 14, r: 2)
        let slab = CamperMeshKit.slab(outline: outline, holes: [window], thickness: wall, bevel: 0, holeBevel: 0.6,
                                      bands: bands, coarse: coarse, side: { [coarse] _, y in CamperMeshKit.material(at: y, in: coarse) },
                                      back: .inner, reveal: .reveal)
        let x0 = rear
        // (u, y, w) → (X = x0 - w, Y = y, Z = u)。w=0 が外の面（-X を向く）
        let placed = slab.mapped({ CV3(x0 - $0.z, $0.y, $0.x) }, normal: { CV3(-$0.z, $0.y, $0.x) }, mirror: true)
        mesh("body.rearWall", placed)
        windowTrim(window, plane: .rear(x0), name: "rear.window")
    }

    /// 床板（下の面）。泥よけの筒の所は切り欠く
    mutating func floorPan() {
        mesh("body.floorPan", notchedSlab(y: 26, thickness: 1, top: false, material: .under, back: .under))
        // 室内の床（木目・上の面 Y=34）
        mesh("interior.floor", notchedSlab(y: 34, thickness: 7.4, top: true, material: floorMaterial, back: .under), category: .floor)
        floorFinish()
    }

    /// 床の形（X は前後の端、Z は内壁の内側。泥よけの筒の所を切り欠く）を Y の高さに置いた板
    func notchedSlab(y: Double, thickness: Double, top: Bool, material: CamperMaterial, back: CamperMaterial) -> CamperMesh {
        let zr = BW - wall
        let x0 = rear + 4, x1 = front - 4
        let half = sqrt(archR * archR - 16)
        var lower: [CV2] = [CV2(x0, -zr)]
        for cx in wheels.sorted() {
            lower += [CV2(cx - half, -zr), CV2(cx - half, -wellInner), CV2(cx + half, -wellInner), CV2(cx + half, -zr)]
        }
        lower.append(CV2(x1, -zr))
        let upper = lower.reversed().map { CV2($0.x, -$0.y) }
        let outline = lower + upper
        let slab = CamperMeshKit.slab(outline: outline, thickness: thickness, bevel: 0, holeBevel: 0,
                                      bands: [CamperBand(minY: -.infinity, maxY: .infinity, material: material)],
                                      side: { _, _ in back }, back: back, reveal: back)
        if top {
            // 表（+z）を上へ: (u, v, w) → (X = u, Y = y + w, Z = -v)
            return slab.mapped({ CV3($0.x, y + $0.z, -$0.y) }, normal: { CV3($0.x, $0.z, -$0.y) })
        }
        // 表を下へ: (u, v, w) → (X = u, Y = y - w, Z = v)
        return slab.mapped({ CV3($0.x, y - $0.z, $0.y) }, normal: { CV3($0.x, -$0.z, $0.y) })
    }

    /// 車輪の切り欠きの内側（泥よけの筒）と奥の壁。外は暗く、室内側は内装の色
    mutating func wells() {
        let a0 = asin(4 / archR)
        let steps = 12
        for cx in wheels {
            for s in [1.0, -1.0] {
                var m = CamperMesh()
                let zOut = s * (BW - wall), zIn = s * wellInner
                for k in 0..<steps {
                    let t0 = a0 + (Double.pi - 2 * a0) * Double(k) / Double(steps)
                    let t1 = a0 + (Double.pi - 2 * a0) * Double(k + 1) / Double(steps)
                    for (r, inward) in [(archR, true), (archR + 0.6, false)] {
                        let p0 = CV3(cx + cos(t0) * r, wheelY + sin(t0) * r, 0), p1 = CV3(cx + cos(t1) * r, wheelY + sin(t1) * r, 0)
                        let n0 = CV3(cos(t0), sin(t0), 0) * (inward ? -1 : 1), n1 = CV3(cos(t1), sin(t1), 0) * (inward ? -1 : 1)
                        m.quad(CV3(p0.x, p0.y, zOut), CV3(p1.x, p1.y, zOut), CV3(p1.x, p1.y, zIn), CV3(p0.x, p0.y, zIn),
                               n0, n1, n1, n0, inward ? .well : .inner)
                    }
                }
                // 奥の壁（切り欠きの弧と床の線で囲む）
                var arc: [CV2] = []
                for k in 0...steps {
                    let t = a0 + (Double.pi - 2 * a0) * Double(k) / Double(steps)
                    arc.append(CV2(cx + cos(t) * archR, wheelY + sin(t) * archR))
                }
                let endWall = CamperMeshKit.slab(outline: arc, thickness: 0.6, bevel: 0, holeBevel: 0,
                                                 bands: [CamperBand(minY: -.infinity, maxY: .infinity, material: .well)],
                                                 side: { _, _ in .well }, back: .inner, reveal: .well)
                // 表（+z）を車輪の側へ
                let placed = s > 0
                    ? endWall.translated(CV3(0, 0, zIn))
                    : endWall.mirroredZ().translated(CV3(0, 0, zIn))
                m.append(placed)
                mesh("body.well", m)
            }
        }
    }

    // MARK: 横の壁（窓・扉の口・塗り分け）

    enum Plane {
        case side(Double)
        case rear(Double)
    }

    mutating func sides() {
        let (outline, tags) = profile
        var nearHoles = windowsNear + [doorHole, cabDoor]
        var farHoles = windowsFar + [cabDoor]
        if !van { farHoles.append(hatch) } else { farHoles.append(hatch) }
        nearHoles = nearHoles.filter { $0.count > 2 }
        farHoles = farHoles.filter { $0.count > 2 }
        for (s, holes) in [(1.0, nearHoles), (-1.0, farHoles)] {
            let slab = CamperMeshKit.slab(outline: outline, tags: tags, holes: holes, thickness: wall, bevel: bevel,
                                          holeBevel: 0.6, bands: bands, coarse: coarse,
                                          side: { [coarse] tag, y in
                                              tag == "arch" ? .well : (tag == "bottom" ? .under : CamperMeshKit.material(at: y, in: coarse))
                                          }, back: .inner, reveal: .reveal)
            let placed = s > 0 ? slab.translated(CV3(0, 0, BW)) : slab.mirroredZ().translated(CV3(0, 0, -BW))
            mesh(s > 0 ? "body.side.near" : "body.side.far", placed)
            for w in (s > 0 ? windowsNear : windowsFar) {
                windowTrim(w, plane: .side(s * BW), name: "window", category: .windowShape)
                windowDetails(w, z: s * BW)
            }
        }
    }

    /// 窓のゴムの縁（幅 1.5）・クロームの細い枠（外へ 1.4・幅 0.45）・ガラス（表から 2.2 奥・厚み 0.4）
    /// 窓の縁（ゴム・クローム）とガラス。`lit` は住む所の窓（夜に室内の灯りで光る）
    mutating func windowTrim(_ w: [CV2], plane: Plane, name: String, group: CamperGroup = .body, surface: Double? = nil,
                             category: CamperCategory? = nil, lit: Bool = true) {
        let seal = CamperMeshKit.extrude(CamperPolygon.offset(w, by: 1.5), holes: [w], depth: 0.9, front: .rubber, side: .rubber)
        let chrome = CamperMeshKit.extrude(CamperPolygon.offset(w, by: 1.85), holes: [CamperPolygon.offset(w, by: 1.4)],
                                           depth: 1.0, front: .chrome, side: .chrome)
        let pane: CamperMaterial = lit ? .glassLit : .glass
        let glass = CamperMeshKit.extrude(w, depth: 0.4, front: pane, side: pane, back: pane)
        func place(_ m: CamperMesh, depth: Double) -> CamperMesh {
            switch plane {
            case .side(let z):
                let face = surface ?? z
                let s = z >= 0 ? 1.0 : -1.0
                // 表は外（+Z か -Z）。`depth` は表からの深さ（正で外へ出る）
                return s > 0 ? m.translated(CV3(0, 0, face + depth)) : m.mirroredZ().translated(CV3(0, 0, -(abs(face) + depth)))
            case .rear(let x):
                return m.mapped({ CV3(x - depth - $0.z, $0.y, $0.x) }, normal: { CV3(-$0.z, $0.y, $0.x) }, mirror: true)
            }
        }
        var all = place(seal, depth: 0.55)
        all.append(place(chrome, depth: 0.7))
        all.append(place(glass, depth: -2.2))
        mesh(name, all, group: group, category: category)
    }

    // MARK: 扉（開く扉・運転席の扉・点検口）

    mutating func doors() {
        // 扉の板（厚み 2.4・口より 0.3 小さく）。外は塗装の帯、内は内装の色。窓の穴あり
        let panel = CamperPolygon.offset(doorHole, by: -0.3)
        let slab = CamperMeshKit.slab(outline: panel, holes: [doorWindow], thickness: 2.4, bevel: 0.8, holeBevel: 0.4,
                                      bands: bands, coarse: coarse, back: .inner, reveal: .reveal)
        mesh("door.panel", slab.translated(CV3(0, 0, BW)), group: .door)
        windowTrim(doorWindow, plane: .side(BW), name: "door.window", group: .door)
        let hx = out.doorHinge.x
        let span = (doorHole.map(\.x).max() ?? 56.5) - hx
        let handleX = hx + span * 0.85
        // 取っ手 2（外と内）・鍵穴
        handle("door.handle.out", at: CV3(handleX, 69, BW), s: 1, group: .door)
        handle("door.handle.in", at: CV3(handleX, 69, BW - 2.4), s: -1, group: .door, small: true)
        lathe("door.lock", CV3(handleX, 64, BW), axis: CV3(0, 0, 1), [(1.2, 0), (1.2, 1.2), (0.01, 1.4)], segments: 10,
              group: .door) { _ in .chrome }
        // 蝶番 2・ネジ 4（壁の側）
        for y in [62.0 + 38, 62.0 - 20] {
            rbox("door.hinge", CV3(hx + 1, y, BW + 0.6), CV3(2, 6, 1.2), 0.4, .chrome)
            for dy in [-3.0, 3.0] {
                lathe("door.screw", CV3(hx + 2, y + dy, BW + 1.2), axis: CV3(0, 0, 1), [(0.6, 0), (0.6, 0.3), (0.01, 0.5)],
                      segments: 8) { _ in .chromeDark }
            }
        }
        // 運転席の扉（両側・開かない）。窓の穴と取っ手
        for s in [1.0, -1.0] {
            let cab = CamperPolygon.offset(cabDoor, by: -0.3)
            guard cab.count > 2 else { continue }
            let p = CamperMeshKit.slab(outline: cab, holes: [cabWindow], thickness: wall, bevel: 0.8, holeBevel: 0.4,
                                       bands: bands, coarse: coarse, back: .inner, reveal: .reveal)
            mesh("cabDoor.panel", s > 0 ? p.translated(CV3(0, 0, BW)) : p.mirroredZ().translated(CV3(0, 0, -BW)))
            windowTrim(cabWindow, plane: .side(s * BW), name: "cabDoor.window", lit: false)
            handle("cabDoor.handle", at: CV3(94, 62, s * BW), s: s, small: true)
        }
        // 反対側の点検口（板が塞ぐ）と取っ手
        let h = CamperPolygon.offset(hatch, by: -0.3)
        let hp = CamperMeshKit.slab(outline: h, thickness: wall, bevel: 0.6, holeBevel: 0, bands: bands, coarse: coarse,
                                    back: .inner, reveal: .reveal)
        mesh("hatch.panel", hp.mirroredZ().translated(CV3(0, 0, -BW)))
        let hc = h.reduce(CV2(0, 0)) { $0 + $1 } * (1 / Double(h.count))
        handle("hatch.handle", at: CV3(hc.x, hc.y, -BW), s: -1, small: true)
    }

    // MARK: 室内

    mutating func interior() {
        let zr = BW - wall
        // 後ろの内壁（バンは殻の内張りが受け持つ）
        if !van {
            // 寝台の下の仕切り（運転席との境・低い壁）
            rbox("interior.bunkFront", CV3(66, 66, 0), CV3(2, 4, zr * 2 - 2), 0.4, .woodDark)
        }
        if van {
            // バン: 寝台の台とマットレス、保冷箱、木箱
            rbox("interior.bed", CV3(-70, 44, 0), CV3(52, 20, zr * 2 - 2), 1, .woodDark)
            rbox("interior.mattress", CV3(-70, 57, 0), CV3(50, 6, zr * 2 - 4), 2.4, .cushion)
            rbox("interior.pillow", CV3(-90, 62, 12), CV3(10, 4, 22), 1.6, .canvasLight)
            rbox("interior.cooler", CV3(-24, 43, -30), CV3(18, 16, 14), 2, .tint(0x2F4F74))
            rbox("interior.coolerLid", CV3(-24, 51.5, -30), CV3(18.6, 1.4, 14.6), 0.6, .canvasLight)
            rbox("interior.crate", CV3(-24, 42, 22), CV3(20, 14, 16), 1, .wood)
        } else {
            // 後ろの座卓（長椅子 2・背もたれ・天板・脚）
            rbox("interior.bench", CV3(-104, 48, 10), CV3(12, 28, 72), 2, .cushion)
            rbox("interior.benchBack", CV3(-110, 66, 10), CV3(4, 22, 72), 2, .cushion)
            rbox("interior.bench", CV3(-74, 48, 10), CV3(12, 28, 72), 2, .cushion)
            rbox("interior.table", CV3(-89, 60, 14), CV3(20, 2.2, 46), 1, .wood)
            rod("interior.tableLeg", CV3(-89, 34, 14), CV3(-89, 59, 14), 2, .chrome)
            // 台所（反対側の壁・扉の口の真向かい）: 箱・石の天板・流し・コンロ・やかん。
            // 2026-10-18 判断（Mac の絵 run 530）: 扉の口から奥の台所が読めなかったので、口の正面（x 2〜58）へ寄せた。
            // 開けた扉から入ると目の前が台所になる（向こうの壁の小窓 B の下）
            rbox("interior.kitchen", CV3(30, 46, -36), CV3(56, 24, 20), 1.4, .woodDark)
            rbox("interior.counter", CV3(30, 58.4, -36), CV3(57, 1.6, 21), 0.6, .stone)
            rbox("interior.sink", CV3(47, 58.6, -37), CV3(14, 1.4, 11), 0.6, .chromeDark)
            for dx in [22.0, 32.0] {
                add("interior.burner", .torus(ring: 2.6, pipe: 0.5), .black, at: CV3(dx, 59.6, -38))
            }
            lathe("interior.kettle", CV3(32, 59.2, -38), axis: CV3(0, 1, 0), [(3.4, 0), (3.8, 4), (2.4, 7), (0.01, 7.4)],
                  segments: 12, capStart: .chrome) { _ in .chrome }
            for k in 0..<4 {
                rbox("interior.kitchenDoorGap", CV3(9 + Double(k) * 14, 46, -25.8), CV3(0.6, 20, 0.4), 0.1, .black)
            }
            // 吊り戸棚（扉の継ぎ目）
            rbox("interior.cupboard", CV3(-40, 120, -40), CV3(140, 12, 12), 1.4, .woodDark)
            for k in 0..<7 {
                rbox("interior.cupboardGap", CV3(-100 + Double(k) * 20, 120, -33.8), CV3(0.6, 10, 0.4), 0.1, .black)
            }
            // 吊りランプ（夜は灯る・分類の部品）
            hangingLamp()
            // 寝台（運転席の上）
            rbox("interior.bunk", CV3(52, 112, 0), CV3(30, 3, 92), 1, .woodDark)
            rbox("interior.mattress", CV3(50, 117, 0), CV3(24, 6, 86), 2.4, .cushion)
            rbox("interior.pillow", CV3(56, 121, 24), CV3(10, 3, 20), 1.4, .canvasLight)
            // カーテン（扉の側の窓・分類の部品）
            curtains()
            // 扉を開けた所: 玄関マット・天井の灯り・内側のつかみ
            rbox("interior.doorMat", CV3(45, 34.4, BW - 9), CV3(20, 0.8, 11), 0.3, .mat)
            lathe("interior.doorLamp", CV3(45, 128, BW - 14), axis: CV3(0, -1, 0), [(0.3, 0), (0.3, 2), (3.4, 3), (3.8, 4.6), (0.01, 5)],
                  segments: 12) { [lampLit = night] _ in lampLit ? .lamp : .brass }
            bookshelf()
        }
        cushions()
        plant()
        mug()
        // 運転席: ダッシュボード・座席 2・ハンドル・柱・シフト
        rbox("interior.dash", CV3(van ? 92 : 96, 74, 0), CV3(12, 8, (BW - wall) * 2 - 4), 2, .dash)
        for z in [-22.0, 22.0] {
            rbox("interior.seat", CV3(76, 48, z), CV3(16, 6, 22), 2, .seat)
            rbox("interior.seatBack", CV3(69, 62, z), CV3(5, 26, 22), 2.4, .seat, CQuat.axisAngle(CV3(0, 0, 1), -10 * .pi / 180))
            rbox("interior.headrest", CV3(67.5, 78, z), CV3(4, 6, 14), 1.6, .seat)
            rbox("interior.seatBase", CV3(76, 40, z), CV3(12, 10, 16), 1, .black)
        }
        let axis = Bd(-0.55, -0.83, 0)
        add("interior.steering", .torus(ring: 7, pipe: 0.7), .black, at: B(88, -18, 22), CQuat.yTo(axis))
        rod("interior.column", B(88, -18, 22), B(95, -8, 22), 1, .black)
        rod("interior.gear", CV3(82, 40, 0), CV3(80, 52, 0), 0.6, .black)
        add("interior.gearKnob", .sphere(radius: 1.6), .black, at: CV3(80, 53, 0))
    }

    // MARK: 外の細部（扉の側・反対側・ミラー・方向指示）

    mutating func exterior() {
        let nearZ = BW
        if !van {
            // ステップ（溝 5）
            rbox("ext.step", B(45, 39, BW + 5), CV3(22, 2.2, 10), 0.8, .alu)
            for k in 0..<5 {
                rbox("ext.stepGroove", CV3(36 + Double(k) * 4.5, 62 - 39 + 1.15, BW + 5), CV3(0.6, 0.3, 8), 0.1, .black)
            }
            rod("ext.stepBracket", CV3(36, 22, BW), CV3(36, 23, BW + 9), 0.6, .black)
            rod("ext.stepBracket", CV3(54, 22, BW), CV3(54, 23, BW + 9), 0.6, .black)
            // つかみ棒と留め具
            lathe("ext.grab", B(60, 0, BW + 3.5), axis: CV3(0, 1, 0), [(1, 0), (1, 24)], segments: 10, capStart: .chrome,
                  capEnd: .chrome) { _ in .chrome }
            rbox("ext.grabMount", B(60, -24, BW + 1.5), CV3(3, 1.5, 4), 0.5, .chrome)
            rbox("ext.grabMount", B(60, 0, BW + 1.5), CV3(3, 1.5, 4), 0.5, .chrome)
            // 反対側: 冷蔵庫の換気口 2（桟 4 ずつ）・給油口
            for y in [-16.0, 0] {
                rbox("ext.vent", B(34, y, -nearZ - 0.8), CV3(18, 9, 1.6), 1, .black)
                for k in 0..<4 {
                    rbox("ext.ventSlat", B(34, y - 3 + Double(k) * 2, -nearZ - 1.7), CV3(15, 0.7, 0.6), 0.2, .chassis)
                }
            }
            lathe("ext.fuelCap", B(-30, 26, -nearZ), axis: CV3(0, 0, -1), [(3.6, 0), (3.6, 1), (0.01, 1.4)], segments: 16) { _ in .chrome }
        }
        // ミラー（両側・分類の部品）・方向指示（前後の横）
        mirrors()
        for s in [1.0, -1.0] {
            rbox("ext.markerFront", B(116, 22, s * (BW - 1)), CV3(3, 3, 3), 0.6, .amber)
            rbox("ext.markerRear", B(rear + 1, 24, s * (BW - 1)), CV3(3, 3, 3), 0.6, .amber)
        }
        // 屋根のつなぎ目（13 単位ごと・浅い溝の細い棒）
        let zr = BW - wall
        var x = rear + 13
        while x < (van ? 50 : 70) {
            rbox("ext.roofSeam", CV3(x, roofTop + 0.15, 0), CV3(0.8, 0.5, zr * 2), 0.2, .under)
            x += 13
        }
    }

    // MARK: 前（グリル・前照灯・印・バンパー・ナンバー・ワイパー）

    mutating func frontFace() {
        let FX = front
        grille(FX)
        lathe("front.emblem", B(FX + 2.2, 15.5, 0), axis: CV3(1, 0, 0), [(2.6, 0), (2.6, 0.6), (0.01, 0.9)], segments: 16,
              capStart: .brass) { _ in .brass }
        let lc = CamperCategory.headlight
        for s in [-1.0, 1.0] {
            switch config.loadout.key(.headlight) {
            case "twin_round":
                for dz in [-5.2, 5.2] {
                    let c = B(FX - 0.5, 14, s * 37 + dz)
                    lathe("light.bezel", c, axis: CV3(1, 0, 0), [(4.2, 0), (4.4, 1.2), (3.6, 2)], segments: 18, capStart: .chrome,
                          category: lc) { _ in .chrome }
                    lathe("light.lens", c + CV3(1.4, 0, 0), axis: CV3(1, 0, 0), [(3.6, 0), (2.8, 0.9), (0.01, 1.4)], segments: 18,
                          category: lc) { _ in .lens }
                }
            case "square":
                rbox("light.bezel", B(FX, 14, s * 37), CV3(2.4, 10, 14), 1.4, .chrome, category: lc)
                rbox("light.lens", B(FX + 1.3, 14, s * 37), CV3(0.8, 8, 11.2), 0.3, .lens, category: lc)
                rbox("light.reflector", B(FX + 0.9, 14, s * 37), CV3(0.4, 6, 9), 0.2, .chromeDark, category: lc)
            default:
                lathe("light.bezel", B(FX - 1, 14, s * 37), axis: CV3(1, 0, 0), [(6.4, 0), (6.6, 1.2), (5.6, 2)], segments: 20,
                      capStart: .chrome, category: lc) { _ in .chrome }
                // 反射板の輪 2（レンズの奥）とレンズ（厚みのある凸）
                for r in [2.2, 4.2] {
                    add("light.reflectorRing", .torus(ring: r, pipe: 0.18), .chromeDark, at: B(FX + 0.8, 14, s * 37),
                        CQuat.yTo(CV3(1, 0, 0)), category: lc)
                }
                lathe("light.lens", B(FX + 0.6, 14, s * 37), axis: CV3(1, 0, 0), [(5.6, 0), (4.4, 1.2), (0.01, 1.8)], segments: 20,
                      category: lc) { _ in .lens }
            }
            if config.loadout.key(.headlight) == "rally_brass" {
                lathe("light.rally", B(FX + 5, 26, s * 18), axis: CV3(1, 0, 0), [(4.2, 0), (4.6, 1.6), (3.8, 2.4)], segments: 18,
                      capStart: .brass, category: lc) { _ in .brass }
                lathe("light.rallyLens", B(FX + 6.8, 26, s * 18), axis: CV3(1, 0, 0), [(3.8, 0), (2.6, 0.9), (0.01, 1.3)],
                      segments: 18, category: lc) { _ in .lensAmber }
                rod("light.rallyStem", B(FX + 4, 29.5, s * 18), B(FX + 4, 31, s * 18), 0.6, .black, category: lc)
            }
            rbox("front.indicator", B(FX + 0.4, 23, s * 37), CV3(2, 3, 9), 0.8, .amber)
        }
        frontBumper(FX)
        plate(at: B(FX + 6.6, 32, 0), facing: CV3(1, 0, 0), name: "front.plate")
        for z in [-14.0, 14.0] {
            let a = B(van ? 80 : 84, -9, z - 14), b = B(van ? 74 : 79, -17, z + 4)
            rod("front.wiper", a, b, 0.5, .black)
            rod("front.wiperArm", a, a + CV3(-2, 2, 0), 0.6, .black)
        }
    }

    /// ナンバー（板 24×6・厚み 0.8 に、立体の文字）
    mutating func plate(at c: CV3, facing: CV3, name: String) {
        // 板は X が厚み・Z が幅（前）。後ろは向きを返す。ナンバーは図鑑の部品ではない（白い板に緑の数字）
        let q = CQuat.rotation(from: CV3(1, 0, 0), to: facing)
        rbox(name, c, q.rotate(CV3(0.8, 6, 24)).abs, 0.4, .plate(0xECE7DA))
        // 文字は +Z を向く形で作られる。前を向くよう回す
        add(name + ".number", .text(CamperCounting.plateNumber(config.posts), height: 3.6, depth: 0.3), .plateInk(0x1F5A3A),
            at: c + facing * 0.45, CQuat.rotation(from: CV3(0, 0, 1), to: facing))
    }

    // MARK: 後ろ（尾灯・バンパー・はしご・予備タイヤ・ナンバー）

    mutating func rearFace() {
        let BX = rear
        rbox("rear.bumper", B(BX - 2.6, 33, 0), CV3(6, 6, BW * 2), 2.4, .black)
        for s in [-1.0, 1.0] {
            rbox("rear.taillight", B(BX - 0.6, 14, s * (BW - 6)), CV3(2.2, 16, 7), 1.2, .red)
            rbox("rear.taillightRib", B(BX - 1.8, 14, s * (BW - 6)), CV3(0.4, 12, 0.6), 0.1, .chrome)
        }
        plate(at: B(BX - 5.5, 31.5, 0), facing: CV3(-1, 0, 0), name: "rear.plate")
        // 排気管の先
        lathe("rear.exhaustTip", B(BX - 2, 42, 22), axis: CV3(-1, 0, 0), [(1.8, 0), (1.8, 6), (1.3, 6), (1.3, 1)], segments: 14) { _ in .chrome }
        guard !van else { return }
        // はしご（柱 2・段 8・留め具 4。分類の部品）
        ladder(BX)
        // 予備タイヤのカバー（分類の部品）
        spareCover(BX)
    }

    // MARK: タイヤとホイール

    mutating func allWheels() {
        for cx in wheels {
            for s in [-1.0, 1.0] { tyre(cx: cx, z: s * (BW - 8), dir: s) }
        }
    }

    /// タイヤ（肩の丸いゴム・縦溝 1・横溝 22 本 × 2 列）とホイール（分類の部品）
    mutating func tyre(cx: Double, z zc: Double, dir: Double) {
        let wc = CamperCategory.wheel
        let center = CV3(cx, wheelY, zc)
        let axis = CV3(0, 0, dir)
        let q = CQuat.yTo(axis)
        let origin = center - axis * 11
        // 胴（溝の底は半径 21）と肩・側面・奥の蓋
        let floorR = 22 - treadSpec.depth
        let body = CamperMeshKit.lathe([CV2(14, 0), CV2(19.4, 0), CV2(22, 3), CV2(floorR, 3), CV2(floorR, 19), CV2(22, 19), CV2(19.4, 22), CV2(14, 22)],
                                       segments: 32, material: { k in k == 4 ? .tread : .rubber }, capStart: .rubber)
        add("wheel.tyre", .mesh(body), .rubber, at: origin, q)
        let ts = treadSpec
        let lugs = CamperMeshKit.treadBlocks(radius: 22, depth: ts.depth, rows: ts.rows, pitches: ts.pitches, land: ts.land,
                                             material: .tread)
        add("wheel.tread", .mesh(lugs), .tread, at: origin, q, category: .tireTread)
        let key = config.loadout.key(.wheel)
        let face = center + axis * 11
        let inward = CQuat.yTo(-axis)
        switch key {
        case "steel_black":
            // 黒い鉄の皿に丸い穴 6（穴は本当に抜けて、奥のブレーキの胴が見える）、クロームのキャップ
            let dish = CamperMeshKit.lathe([CV2(14.2, 0), CV2(12.6, 2), CV2(9.6, 4.4), CV2(6.2, 4), CV2(3.6, 3.2), CV2(0.01, 2.8)],
                                           segments: 32, material: { k in k == 4 ? .chromeDark : .steel })
            add("wheel.dish", .mesh(dish), .steel, at: face, inward, category: wc)
            for k in 0..<6 {
                let t = Double(k) / 6 * 2 * .pi
                add("wheel.hole", .cylinder(radius: 1.7, height: 1.2, segments: 12), .well,
                    at: center + CV3(cos(t) * 11, sin(t) * 11, dir * 7.4), q, category: wc)
            }
        case "brass_spoke":
            // 外の輪・芯・スポーク 8（隙間から奥のブレーキの胴が見える）
            let rim = CamperMeshKit.lathe([CV2(14.2, 0), CV2(13.2, 1.4), CV2(12.4, 1.4), CV2(12.4, 0.2)], segments: 32,
                                          material: { _ in .brass })
            add("wheel.dish", .mesh(rim), .brass, at: face, inward, category: wc)
            lathe("wheel.hub", face - axis * 2, axis: axis, [(3.4, 0), (3.4, 2.4), (1.8, 3.4), (0.01, 3.6)], segments: 16,
                  category: wc) { k in k == 2 ? .brass : .chrome }
            for k in 0..<16 {
                let t = Double(k) / 16 * 2 * .pi
                rod("wheel.spoke", center + CV3(cos(t) * 3, sin(t) * 3, dir * (k % 2 == 0 ? 9.0 : 10.0)),
                    center + CV3(cos(t + 0.2) * 12.6, sin(t + 0.2) * 12.6, dir * 10.4), 0.45, .brass, segments: 6, category: wc)
            }
        default:
            let dish = CamperMeshKit.lathe([CV2(14.2, 0), CV2(12.6, 2), CV2(9.6, 4.4), CV2(6.2, 4), CV2(3.6, 3.2), CV2(0.01, 2.8)],
                                           segments: 32, material: { k in k == 2 || k == 4 ? .chromeDark : .chrome })
            add("wheel.dish", .mesh(dish), .chrome, at: face, inward, category: wc)
            // 放射の筋 12（浅い溝）
            for k in 0..<12 {
                let t = Double(k) / 12 * 2 * .pi
                let p = center + CV3(cos(t) * 11.8, sin(t) * 11.8, dir * 9.7)
                add("wheel.rib", .box(CV3(2.8, 0.5, 0.4), chamfer: 0.1), .chromeDark, at: p,
                    CQuat.axisAngle(CV3(0, 0, 1), t) * CQuat.axisAngle(CV3(0, 1, 0), dir * 0.5), category: wc)
            }
        }
        // 真ん中のキャップ（分類の部品）
        hubcap(at: face - axis * 2.6, axis: axis)
        if key == "whitewall" {
            // 側面の白い帯（薄い輪の板）
            add("wheel.whitewall", .mesh(CamperMeshKit.lathe([CV2(15.6, 0), CV2(19, 0), CV2(19, 0.3), CV2(15.6, 0.3)], segments: 40,
                                                             material: { _ in .whitewall })),
                .whitewall, at: center + axis * 11.05, q, category: wc)
        }
        // ナット 6（六角）
        for k in 0..<6 {
            let t = Double(k) / 6 * 2 * .pi + 0.3
            lathe("wheel.nut", center + CV3(cos(t) * 7.6, sin(t) * 7.6, dir * 6.8), axis: axis, [(1.1, 0), (1.1, 1.1), (0.6, 1.4)],
                  segments: 6, faceted: true, capEnd: .chrome, category: wc) { _ in .chrome }
        }
        // 奥のブレーキの胴（穴越しに見える）
        add("wheel.drum", .cylinder(radius: 12, height: 5, segments: 24), .chassis, at: center + axis * 2, q)
    }

    // MARK: 屋根（太陽電池・換気口・荷台・積み荷・雪）

    mutating func roof() {
        let RT = roofTop
        if van {
            for z in [-36.0, 36] { rbox("roof.rail", CV3(-20, RT + 2, z), CV3(120, 3, 3), 1.2, .chrome) }
            for x in [-70.0, 30] { for z in [-36.0, 36] { rbox("roof.railFoot", CV3(x, RT + 0.6, z), CV3(4, 1.4, 4), 0.5, .black) } }
            cargo(base: RT + 3.5, x: -20)
            antenna()
            flag()
            if snow { rbox("roof.snow", CV3(-22, RT + 3, 0), CV3(148, 5, 90), 2.5, .snow) }
            return
        }
        solarPanels()
        rbox("roof.vent", CV3(-22, RT + 1.5, 0), CV3(18, 3, 18), 1.2, .tint(0xE7E3DA))
        // 換気口のふた（6 開く）
        rbox("roof.ventLid", CV3(-22, RT + 6, 0), CV3(16, 0.8, 16), 0.3, .tint(0xDAD4C6),
             CQuat.axisAngle(CV3(1, 0, 0), -0.38))
        // 荷台の脚 4・縦の棒 2・横木 3
        for x in [-4.0, 66] { for z in [-40.0, 40] { rbox("roof.rackFoot", CV3(x, RT + 3, z), CV3(4, 6, 4), 1, .black) } }
        for z in [-40.0, 40] { rbox("roof.rackRail", CV3(31, RT + 6.5, z), CV3(76, 3, 3), 1.2, .black) }
        for x in [0.0, 31, 62] { rbox("roof.rackBar", CV3(x, RT + 9.5, 0), CV3(3, 3, 86), 1.2, .alu) }
        cargo(base: RT + 11, x: 31)
        antenna()
        flag()
        if snow {
            rbox("roof.snow", CV3(-24, RT + 3, 0), CV3(188, 6, 96), 3, .snow)
        }
    }

    // MARK: 床下（車台）

    mutating func underbody() {
        let len = van ? 190.0 : 214
        let mid = (rear + front) / 2
        for z in [-26.0, 26] { rbox("under.frame", CV3(mid, 23, z), CV3(len, 4, 5), 0.4, .chassis) }
        for x in (van ? [-80.0, -30, 20, 60] : [-92.0, -34, 24, 70]) { rbox("under.crossmember", CV3(x, 23, 0), CV3(4, 3, 52), 0.3, .chassis) }
        for cx in wheels {
            rod("under.axle", CV3(cx, wheelY, -(BW - 8)), CV3(cx, wheelY, BW - 8), 2.4, .chassis)
            for z in [-26.0, 26] {
                rbox("under.leafSpring", CV3(cx, 24.6, z), CV3(34, 2.2, 4), 0.8, .tint(0x2A2B2E))
                rbox("under.leafSpring", CV3(cx, 22.8, z), CV3(24, 1.6, 3.6), 0.6, .tint(0x2A2B2E))
            }
        }
        // デフ（後ろの車軸）とプロペラシャフト
        lathe("under.diff", CV3(wheels[0], wheelY, -7), axis: CV3(0, 0, 1), [(0.01, 0), (5, 2), (6.4, 7), (5, 12), (0.01, 14)],
              segments: 14) { _ in .chassis }
        rod("under.propShaft", CV3(wheels[0] + 6, wheelY + 0.5, 0), CV3(wheels[1] - 10, 22.5, 0), 1.6, .chassis)
        // 燃料タンク・水タンク・マフラー・排気管
        rbox("under.fuelTank", CV3(16, 20.5, -27), CV3(30, 8, 16), 2, .tint(0x2A2C30))
        rbox("under.waterTank", CV3(-36, 21, 8), CV3(40, 7, 30), 2, .tank)
        rbox("under.muffler", CV3(-6, 19.5, 22), CV3(30, 6, 9), 2, .alu)
        rod("under.exhaust", CV3(66, 20, 22), CV3(9, 19.8, 22), 1.4, .tint(0x5A5D62))
        rod("under.exhaust", CV3(-21, 19.8, 22), CV3(rear + 4, 20, 22), 1.4, .tint(0x5A5D62))
        // 泥よけ 4（車輪の後ろ）
        mudFlaps()
    }

    // MARK: オーニング

    mutating func awning() {
        guard !van else { return }
        let ac = CamperCategory.awning
        // ケース（150×7×7・端の黒い蓋 2・リベット 9）
        rbox("awning.case", B(-42, -61, BW + 4), CV3(150, 7, 7), 3, .alu)
        rbox("awning.cap", B(-117.5, -61, BW + 4), CV3(1.5, 8, 8), 1.2, .black)
        rbox("awning.cap", B(33.5, -61, BW + 4), CV3(1.5, 8, 8), 1.2, .black)
        for k in 0..<9 {
            lathe("awning.rivet", B(-108 + Double(k) * 17, -57.3, BW + 7.5), axis: CV3(0, 0, 1), [(0.6, 0), (0.6, 0.2), (0.01, 0.5)],
                  segments: 8) { _ in .chromeDark }
        }
        guard config.loadout.awningOpen else { return }
        let color: UInt32 = config.loadout.part(.awning).swatch ?? 0x2F4F74
        // 広げた布（縞 10 本・厚み 0.4）・垂れ（5）・前の棒・脚 2・張り綱 2
        let n = 10, x0 = -116.0, x1 = 32.0, out = 46.0, drop = 14.0
        let y0 = 62 + 61.0
        let slope = atan2(drop, out)
        let width = (x1 - x0) / Double(n)
        let len = (out * out + drop * drop).squareRoot()
        let key = config.loadout.key(.awning)
        let striped = key != "scalloped_edge"
        // 縞の数で形を分ける（藍 10・森の緑 14 の細縞・赤茶 6 の太縞）
        let stripes = key == "forest_stripe" ? 14 : (key == "rust_stripe" ? 6 : n)
        let sw = (x1 - x0) / Double(stripes)
        for k in 0..<(striped ? stripes : 1) {
            let w = striped ? sw : x1 - x0
            let xc = striped ? x0 + sw * (Double(k) + 0.5) : (x0 + x1) / 2
            let m: CamperMaterial = (k % 2 == 0 || !striped) ? .canvas(color) : .canvasLight
            rbox("awning.stripe", CV3(xc, y0 - drop / 2, BW + 6 + out / 2), CV3(w, 0.4, len), 0.1, m,
                 CQuat.axisAngle(CV3(1, 0, 0), slope), category: ac)
            if key == "scalloped_edge" {
                // 波の垂れ（下が半円の布）
                let poly = [CV2(w / 2, 0), CV2(-w / 2, 0)] + (0...8).map { i -> CV2 in
                    let t = Double(i) / 8 * .pi
                    return CV2(-w / 2 * cos(t), -3 - sin(t) * 3)
                }
                let v = CamperMeshKit.extrude(poly, depth: 0.4, front: m, side: m)
                add("awning.valance", .mesh(v), m, at: CV3(xc, y0 - drop, BW + 6 + out + 0.2), category: ac)
            } else {
                rbox("awning.valance", CV3(xc, y0 - drop - 2.5, BW + 6 + out), CV3(w, 5, 0.4), 0.1, m, category: ac)
            }
        }
        rod("awning.frontBar", CV3(x0, y0 - drop, BW + 6 + out), CV3(x1, y0 - drop, BW + 6 + out), 1, .alu, category: ac)
        for xx in [x0 + 2, x1 - 2] {
            rod("awning.leg", CV3(xx, y0 - drop, BW + 6 + out), CV3(xx, 0.5, BW + 6 + out), 0.9, .alu, category: ac)
            rbox("awning.foot", CV3(xx, 0.4, BW + 6 + out), CV3(5, 0.8, 5), 0.3, .black, category: ac)
            let peg = CV3(xx + (xx < 0 ? -10 : 10), 0.2, BW + 6 + out + 18)
            rod("awning.rope", CV3(xx, y0 - drop, BW + 6 + out), peg, 0.25, .canvasLight, segments: 6, category: ac)
            rod("awning.peg", peg, peg + CV3(0, 2.5, 0), 0.4, .alu, segments: 6, category: ac)
        }
    }

    // MARK: ステッカー（図柄・白か金の縁。厚みのある紙）

    mutating func stickers() {
        // 図柄は山並み（写真のステッカーは第2段）。縁が分類の部品
        let key = "mountain"
        let edgeKey = config.loadout.key(.stickerEdge)
        let edge: CamperMaterial = edgeKey == "gold_foil" ? .foil : (edgeKey == "holo" ? .holo : .paper)
        let edgeDepth = edgeKey == "signed" ? 0.5 : 0.3
        let sc = CamperCategory.stickerEdge
        // 扉の側の壁（窓の下）と、予備タイヤのカバー
        let spots: [(CV2, Double)] = van ? [(CV2(-70, 70), 9), (CV2(-30, 70), 7)] : [(CV2(-88, 74), 11), (CV2(-50, 72), 8)]
        for (k, spot) in spots.enumerated() {
            var shapes = stickerShapes(key, center: spot.0, size: spot.1)
            guard !shapes.isEmpty else { continue }
            // 縁の形: 白い切り抜き 1.8・金の箔押しは縁に盛り上がった輪・ホログラムは広い 2.4 の縁
            var outline = CamperPolygon.offset(shapes[0].0, by: edgeKey == "holo" ? 2.4 : 1.8)
            if edgeKey == "holo" {
                // ホログラムは縁が細かく波打つ（光の当たる面が増えて、回すと色が流れる）
                let c = outline.reduce(CV2(0, 0)) { $0 + $1 } * (1 / Double(outline.count))
                var wavy: [CV2] = []
                for (i, p) in outline.enumerated() {
                    let q = outline[(i + 1) % outline.count]
                    for (j, t) in [0.0, 0.5].enumerated() {
                        let pt = p + (q - p) * t
                        let d = pt - c
                        let l = max(d.length, 1e-6)
                        wavy.append(pt + d * ((j == 0 ? 0.0 : 0.6) / l))
                    }
                }
                outline = wavy
            }
            // 貼った紙: 厚みのある縁（側面は紙の白・裏は糊の面）と、下の前の角がわずかに壁から浮いて反る
            // （2026-10-18 Mac の絵 run 529: 平らな円盤に見えた）。図柄の層も同じだけ反る
            let r = outline.map { ($0 - spot.0).length }.max() ?? spot.1
            let curl = CamperCurl(center: spot.0, direction: CV2(1, -1.2), start: r * 0.3, end: r, lift: 1.3, slices: 4)
            var m = CamperMeshKit.paper(outline, depth: edgeDepth, front: edge, side: edgeKey == "white_cut" ? .paper : edge,
                                        back: .paper, curl: curl)
            if edgeKey == "gold_foil" {
                let rim = CamperMeshKit.paper(CamperPolygon.offset(shapes[0].0, by: 1.8), holes: [CamperPolygon.offset(shapes[0].0, by: 1.1)],
                                              depth: 0.5, front: .foil, side: .foil, back: .foil, curl: curl)
                // 縁の輪は紙より 0.2 盛り上がる（裏は紙と同じく壁に付く）
                m.append(rim.translated(CV3(0, 0, 0.5 - edgeDepth)))
            }
            m = m.translated(CV3(0, 0, BW + edgeDepth))
            for (i, s) in shapes.enumerated() {
                m.append(CamperMeshKit.paper(s.0, depth: 0.2, front: s.1, side: s.1, back: s.1, curl: curl)
                    .translated(CV3(0, 0, BW + edgeDepth + 0.2 + Double(i) * 0.15)))
            }
            if edgeKey == "signed" {
                // 友達の名前の刻印（縁の下の細い真鍮の筆跡）
                let c = shapes[0].0.reduce(CV2(0, 0)) { $0 + $1 } * (1 / Double(shapes[0].0.count))
                let r = shapes[0].0.map { ($0 - c).length }.max() ?? 8
                var stroke: [CV2] = []
                for i in 0...10 { stroke.append(CV2(c.x - r * 0.5 + Double(i) * r * 0.1, c.y - r - 0.9 + sin(Double(i) * 1.7) * 0.4)) }
                let line = CamperMeshKit.paper(stroke + stroke.reversed().map { CV2($0.x, $0.y - 0.35) }, depth: 0.12, front: .brass,
                                               side: .brass, back: .brass, curl: curl)
                m.append(line.translated(CV3(0, 0, BW + edgeDepth + 0.05)))
            }
            shapes.removeAll()
            add("sticker.\(k)", .mesh(m), edge, at: .zero, category: sc)
        }
        if !van {
            // 予備タイヤのカバー（後ろ・-X を向く）
            let c = CV2(0, 0)
            let shapes = stickerShapes(key, center: c, size: 9)
            if !shapes.isEmpty {
                // カバーの丸みに沿って、上の縁がわずかに浮く
                let curl = CamperCurl(center: c, direction: CV2(0, 1), start: 4, end: 11, lift: 0.8, slices: 3)
                var m = CamperMeshKit.paper(CamperPolygon.offset(shapes[0].0, by: 1.4), depth: 0.3, front: edge, side: edge,
                                            back: .paper, curl: curl)
                for (i, s) in shapes.enumerated() {
                    m.append(CamperMeshKit.paper(s.0, depth: 0.2, front: s.1, side: s.1, back: s.1, curl: curl)
                        .translated(CV3(0, 0, 0.2 + Double(i) * 0.15)))
                }
                // +Z を -X へ（後ろ向き）。カバーの面は x = rear - 14.6
                let q = CQuat.rotation(from: CV3(0, 0, 1), to: CV3(-1, 0, 0))
                add("sticker.spare", .mesh(m), edge, at: B(rear - 14.6, -6, -20), q, category: sc)
            }
        }
    }

    /// 図柄の形（外の形が先頭）
    func stickerShapes(_ key: String, center c: CV2, size s: Double) -> [([CV2], CamperMaterial)] {
        switch key {
        case "compass":
            var star: [CV2] = []
            for k in 0..<16 {
                let t = Double(k) / 16 * 2 * .pi + .pi / 2
                let r = k % 2 == 1 ? s * 0.2 : (k % 4 == 0 ? s * 0.9 : s * 0.55)
                star.append(CV2(c.x + cos(t) * r, c.y + sin(t) * r))
            }
            return [(CamperPolygon.circle(c, s, count: 32), .tint(0xEDE6D3)), (star, .tint(0x7A2E22)),
                    (CamperPolygon.circle(c, s * 0.12, count: 12), .tint(0xC9A66B))]
        case "sun":
            var rays: [CV2] = []
            for k in 0..<24 {
                let t = Double(k) / 24 * 2 * .pi
                let r = k % 2 == 0 ? s : s * 0.72
                rays.append(CV2(c.x + cos(t) * r, c.y + sin(t) * r))
            }
            return [(rays, .tint(0xD9A441)), (CamperPolygon.circle(c, s * 0.5, count: 20), .tint(0xF2C66B))]
        case "wave":
            let disc = CamperPolygon.circle(c, s, count: 28)
            var wave: [CV2] = []
            for k in 0...16 {
                let x = c.x - s * 0.9 + Double(k) / 16 * s * 1.8
                wave.append(CV2(x, c.y + sin(Double(k) / 16 * 2 * .pi * 1.5) * s * 0.18))
            }
            wave += [CV2(c.x + s * 0.9, c.y - s * 0.55), CV2(c.x - s * 0.9, c.y - s * 0.55)]
            return [(disc, .tint(0xBFD5E3)), (wave, .tint(0x2F6F9A))]
        case "star":
            var star: [CV2] = []
            for k in 0..<10 {
                let t = Double(k) / 10 * 2 * .pi + .pi / 2
                let r = k % 2 == 0 ? s * 0.78 : s * 0.32
                star.append(CV2(c.x + cos(t) * r, c.y + sin(t) * r))
            }
            return [(CamperPolygon.circle(c, s, count: 28), .tint(0x14213A)), (star, .tint(0xE0C27F))]
        default:
            // 山並み: 丸い地に青い山と白い頂
            let disc = CamperPolygon.circle(c, s, count: 28)
            let ridge = [CV2(c.x - s * 0.85, c.y - s * 0.45), CV2(c.x - s * 0.3, c.y + s * 0.42), CV2(c.x + 0.05 * s, c.y),
                         CV2(c.x + s * 0.35, c.y + s * 0.55), CV2(c.x + s * 0.85, c.y - s * 0.45)]
            let cap = [CV2(c.x + s * 0.2, c.y + s * 0.32), CV2(c.x + s * 0.35, c.y + s * 0.55), CV2(c.x + s * 0.5, c.y + s * 0.32)]
            return [(disc, .tint(0xDCE6EE)), (ridge, .tint(0x3D5A78)), (cap, .tint(0xF6F9FC))]
        }
    }

    // MARK: トレーラー（流線形のアルミ・最後の段）

    mutating func trailer() {
        let corners: [(p: CV2, r: Double, tag: String)] = [
            (B2(-262, 34), 4, "rear"), (B2(-264, 4), 18, "rear"), (B2(-240, -34), 28, "roof"), (B2(-188, -40), 26, "roof"),
            (B2(-152, -6), 14, "front"), (B2(-150, 34), 4, "bottom"),
        ]
        let r = CamperPolygon.rounded(corners)
        let (p, t) = CamperPolygon.ccwTagged(r.points, r.tags)
        let TW = 40.0, tw = 3.0
        let alu: [CamperBand] = [
            CamperBand(minY: -.infinity, maxY: 45.25, material: .alu),
            CamperBand(minY: 45.25, maxY: 46.75, material: .pinstripe),
            CamperBand(minY: 46.75, maxY: .infinity, material: .alu),
        ]
        let window = CamperPolygon.circle(CV2(-226, 68), 8, count: 24)
        let door = CamperPolygon.roundedRect(x: -202, y: 34, w: 24, h: 52, r: 2)
        for (s, holes) in [(1.0, [window, door]), (-1.0, [window])] {
            let slab = CamperMeshKit.slab(outline: p, tags: t, holes: holes, thickness: tw, bevel: 2.4, holeBevel: 0.6,
                                          bands: alu, side: { _, _ in .alu }, back: .inner, reveal: .reveal)
            mesh("trailer.side", s > 0 ? slab.translated(CV3(0, 0, TW)) : slab.mirroredZ().translated(CV3(0, 0, -TW)))
            windowTrim(window, plane: .side(s * TW), name: "trailer.window")
        }
        // 扉（開かない）と取っ手
        let dp = CamperMeshKit.slab(outline: CamperPolygon.offset(door, by: -0.3), thickness: tw, bevel: 0.6, holeBevel: 0,
                                    bands: alu, back: .inner, reveal: .reveal)
        mesh("trailer.door", dp.translated(CV3(0, 0, TW)))
        rbox("trailer.handle", CV3(-182, 60, TW + 1), CV3(5, 1.6, 1.4), 0.5, .chrome)
        // 殻（屋根・前・後ろ）と内張り、床
        var m = CamperMesh()
        let skip: (Int) -> Bool = { i in
            let a = p[i], b = p[(i + 1) % p.count]
            return t[i] == "bottom" && abs(a.y - 28) < 0.01 && abs(b.y - 28) < 0.01
        }
        CamperMeshKit.strip(&m, a: p, za: TW - tw, b: p, zb: -(TW - tw), tiltA: 0, tiltB: 0, skip: skip) { _ in .alu }
        let inner = CamperPolygon.offset(p, by: -0.6)
        for i in 0..<p.count where !skip(i) {
            let j = (i + 1) % p.count
            let a = inner[i], b = inner[j]
            let d = b - a
            let l = max(d.length, 1e-9)
            let nn = CV3(-d.y / l, d.x / l, 0)
            m.quad(CV3(a.x, a.y, TW - tw), CV3(b.x, b.y, TW - tw), CV3(b.x, b.y, -(TW - tw)), CV3(a.x, a.y, -(TW - tw)), nn, nn, nn, nn, .inner)
        }
        mesh("trailer.shell", m)
        let flats = p.filter { abs($0.y - 28) < 0.01 }.map(\.x)
        if let lo = flats.min(), let hi = flats.max() {
            let pan = CamperMeshKit.extrude([CV2(lo, -(TW - tw)), CV2(hi, -(TW - tw)), CV2(hi, TW - tw), CV2(lo, TW - tw)],
                                            depth: 1, front: .under, side: .under)
            mesh("trailer.floor", pan.mapped({ CV3($0.x, 28 - $0.z, $0.y) }, normal: { CV3($0.x, -$0.z, $0.y) }))
        }
        // 中: マットレスと枕（丸窓から見える）
        rbox("trailer.mattress", CV3(-206, 35, 0), CV3(96, 8, 70), 2.4, .cushion)
        rbox("trailer.pillow", CV3(-246, 41, 0), CV3(12, 4, 40), 1.6, .canvasLight)
        rbox("trailer.blanket", CV3(-190, 39.6, 0), CV3(52, 1.4, 70.4), 0.6, .canvas(0x7A2E22))
        // 車輪（車体の外）と泥よけ
        for s in [-1.0, 1.0] {
            tyre(cx: -206, z: s * (TW + 12), dir: s)
            var fender = CamperMesh()
            let steps = 12
            for k in 0..<steps {
                let a0 = Double(k) / Double(steps) * .pi, a1 = Double(k + 1) / Double(steps) * .pi
                let r0 = 26.0
                let p0 = CV3(-206 + cos(a0) * r0, wheelY + sin(a0) * r0, 0), p1 = CV3(-206 + cos(a1) * r0, wheelY + sin(a1) * r0, 0)
                let n0 = CV3(cos(a0), sin(a0), 0), n1 = CV3(cos(a1), sin(a1), 0)
                // 外は磨いたアルミ、内（車輪の側）は暗い
                fender.quad(CV3(p0.x, p0.y, TW), CV3(p1.x, p1.y, TW), CV3(p1.x, p1.y, TW + 24), CV3(p0.x, p0.y, TW + 24),
                            n0, n1, n1, n0, .alu)
                let i0 = p0 - n0 * 0.5, i1 = p1 - n1 * 0.5
                fender.quad(CV3(i0.x, i0.y, TW), CV3(i0.x, i0.y, TW + 24), CV3(i1.x, i1.y, TW + 24), CV3(i1.x, i1.y, TW),
                            -n0, -n0, -n1, -n1, .well)
            }
            mesh("trailer.fender", s > 0 ? fender : fender.mirroredZ())
            rod("trailer.axle", CV3(-206, wheelY, s * TW), CV3(-206, wheelY, s * (TW + 8)), 2, .chassis)
        }
        // 牽引の棒と玉
        rbox("trailer.towBar", B(-136, 38, 0), CV3(30, 3, 4), 1, .black)
        lathe("trailer.hitch", B(-123, 36, 0), axis: CV3(0, -1, 0), [(2.2, 0), (2.2, 2), (0.01, 4)], segments: 12) { _ in .chrome }
        rbox("trailer.jack", CV3(-148, 12, 0), CV3(2, 22, 2), 0.4, .chrome)
    }

    // MARK: 夜の灯り（板の付箋「灯りと光の強さ」）

    /// 地面に寝かせた四角（上向き・貼り絵は 0〜1 に一度だけ）。灯りの溜まりに使う
    func glowQuad(width w: Double, depth d: Double) -> CamperMesh {
        var m = CamperMesh()
        let up = CV3(0, 1, 0)
        m.quad(CV3(-w / 2, 0, -d / 2), CV3(w / 2, 0, -d / 2), CV3(w / 2, 0, d / 2), CV3(-w / 2, 0, d / 2), up, up, up, up, .glowPool)
        m.uvs = m.positions.map { CV2($0.x / w + 0.5, $0.z / d + 0.5) }
        return m
    }

    mutating func nightLights() {
        guard night else { return }
        let warm: UInt32 = 0xFFB260
        // 室内の灯りが夜の主役（2026-10-18 Mac の絵 run 529: 灯りが弱く、端の小さな光の点ばかり目立った）
        if !van {
            // 室内の灯りは室内の部品だけを照らす（`CamperLightSpec.inside`）。扉の口のすぐ内に置くと口のまわりが白く飛んだ
            // （run 532）ので、前の灯りは台所の上（口から奥へ）に
            out.lights.append(CamperLightSpec(name: "interior.rear", kind: .omni, position: B(-70, -30, 0), color: warm,
                                              intensity: 1100, range: 80))
            out.lights.append(CamperLightSpec(name: "interior.front", kind: .omni, position: B(24, -34, -14), color: warm,
                                              intensity: 650, range: 60))
        } else {
            out.lights.append(CamperLightSpec(name: "interior.van", kind: .omni, position: B(-40, -30, 0), color: warm,
                                              intensity: 1200, range: 80))
        }
        // 窓と扉の口から地面へこぼれる灯り（光の溜まり。両側の窓の下と、開けた扉の前）
        for (side, windows) in [(1.0, windowsNear), (-1.0, windowsFar)] {
            for (k, w) in windows.enumerated() {
                let xs = w.map(\.x)
                guard let lo = xs.min(), let hi = xs.max() else { continue }
                add("glow.window.\(side > 0 ? "near" : "far").\(k)", .mesh(glowQuad(width: (hi - lo) * 1.6 + 24, depth: 58)),
                    .glowPool, at: CV3((lo + hi) / 2, 0.4, side * (BW + 30)), group: .glow)
            }
        }
        let dx = doorHole.map(\.x)
        // 扉の前の溜まりは口の幅ほど（run 532: 大きく明るすぎて口のまわりが白く飛んだ）
        add("glow.door", .mesh(glowQuad(width: 40, depth: 56)), .glowPool,
            at: CV3(((dx.min() ?? 33.5) + (dx.max() ?? 56.5)) / 2, 0.5, BW + 26), group: .doorGlow)
        for s in [-1.0, 1.0] {
            out.lights.append(CamperLightSpec(name: "headlight", kind: .spot, position: B(front + 3, 14, s * 37),
                                              direction: CV3(1, -0.08, 0), color: 0xFFF1CF, intensity: 1800, range: 220))
        }
        out.lights.append(CamperLightSpec(name: "taillight", kind: .omni, position: B(rear - 6, 14, 0), color: 0xFF3B30,
                                          intensity: 160, range: 46))
    }
}

extension CV3 {
    /// 各成分の大きさ（回した大きさを箱の寸法へ戻す）
    var abs: CV3 { CV3(Swift.abs(x), Swift.abs(y), Swift.abs(z)) }
}

// MARK: - 見る向き

enum CamperFraming {

    /// 初めの向き（板の注記: 縦 −14°・横 −32°）
    static func overview(_ stage: CamperStage) -> CamperAngle {
        let t = stage == .trailer ? CamperBuilder.B(-70, -16, 0) : CamperBuilder.B(0, -14, 0)
        return CamperAngle(target: t, yaw: -32, elevation: 14, zoom: stage.zoom)
    }

    /// 分類の部品の寄り（板 CamperDecorate・CamperCollection の part の向き）
    static func focus(_ c: CamperCategory, stage: CamperStage) -> CamperAngle {
        let B = CamperBuilder.B
        let van = stage == .van
        let rearX = van ? -100.0 : -122
        switch c {
        case .wheel, .hubcap, .tireTread: return CamperAngle(target: B(88, 40, 52), yaw: -18, elevation: 6, zoom: 4.4 * 0.8)
        case .headlight, .grille, .bumper:
            return CamperAngle(target: B(van ? 99 : 100, 12, 0), yaw: -62, elevation: 8, zoom: 2.3 * 0.8)
        case .mirror: return CamperAngle(target: B(van ? 60 : 68, -20, 56), yaw: -40, elevation: 8, zoom: 3.4)
        case .mudflap: return CamperAngle(target: B(60, 46, 50), yaw: 30, elevation: 4, zoom: 3.6)
        case .ladder, .bikeRack, .spareCover: return CamperAngle(target: B(rearX - 10, -10, 10), yaw: 60, elevation: 10, zoom: 1.6)
        case .handle: return CamperAngle(target: B(50, -6, 50), yaw: -14, elevation: 4, zoom: 4.2)
        case .windowShape: return CamperAngle(target: B(-40, -32, 50), yaw: -6, elevation: 4, zoom: 1.7)
        case .roofCargo, .roofTent, .solar, .antenna, .flag:
            return CamperAngle(target: B(-10, van ? -80 : -88, 0), yaw: -30, elevation: 32, zoom: 1.5)
        case .awning: return CamperAngle(target: B(-42, -24, 70), yaw: -24, elevation: 12, zoom: 1.0)
        case .paint: return overview(stage)
        case .stickerEdge: return CamperAngle(target: B(-70, -10, 50), yaw: -6, elevation: 4, zoom: 2.6)
        case .chair, .table, .firePit, .outdoorLight, .rug:
            return CamperAngle(target: CV3(-40, 18, 116), yaw: -20, elevation: 24, zoom: 1.6)
        case .hangingLamp where !van: return door(stage)
        case .curtain, .hangingLamp, .wallWood:
            return CamperAngle(target: B(-80, -24, 30), yaw: -10, elevation: 6, zoom: 2.4)
        case .cushion, .floor, .mug:
            return CamperAngle(target: B(-89, 0, 30), yaw: -12, elevation: 14, zoom: 3.0)
        case .plant: return CamperAngle(target: B(10, -6, -30), yaw: -8, elevation: 12, zoom: 2.6)
        case .bookshelf: return CamperAngle(target: B(-62, -38, -20), yaw: -8, elevation: 10, zoom: 2.4)
        }
    }

    /// 扉を開けた所（板 CamperViews の 9 は t[36,−8,40] z1.75 ry−12）。
    ///
    /// 2026-10-18 判断（Mac の絵 run 529）: 板の向きでは車の横をほぼ真横から見るので、開いた扉の口が
    /// 細い縦の帯にしか見えず、室内が見えなかった。扉は後ろの縁に蝶番があり外へ 100° 開く（扉の板は口の
    /// 後ろ側に立つ）ので、**前の側から斜めに**口をのぞく。視線は口から向こうの壁の台所（流し・コンロ・やかん）と
    /// 吊りランプへ抜ける。口（幅 23・高さ 77）が画面の高さの半分ほどになる寄り（2.1）。車の後ろ半分は
    /// 枠の外になる（口は車の長さの 1/10 なので、車ごと収めると室内は数 px になる）
    static func door(_ stage: CamperStage) -> CamperAngle {
        // 扉の口の真ん中（バンは x −10〜16、ほかは 33.5〜56.5）の、壁の少し内側
        let cx = stage == .van ? 3.0 : 45.0
        // 2026-10-18（run 530）: 口の向こうの台所の天板・吊りランプが読めるよう、斜めをゆるめ（口が広く見える）、
        // 少し見下ろし（天板の上が見える）、狙いを口の奥へ
        // run 532: 2.5 ではフロントのバンパーが右下のボタンの帯に掛かった。寄りを 2.1 に戻し、狙いを少し後ろ・下へ
        // （車が画面の上寄りになり、ボタンの帯に掛からない）
        return CamperAngle(target: CamperBuilder.B(cx - 6, 4, 16), yaw: -24, elevation: 9, zoom: 2.1)
    }
    /// 下から（板の under: t[0,24,0] rx46 ry−28）
    static let under = CamperAngle(target: CamperBuilder.B(0, 24, 0), yaw: -28, elevation: -46, zoom: 1.0)
    /// 後ろ（板 rear: t[−118,−16,0] z1.7 rx−10 ry50）
    static let rear = CamperAngle(target: CamperBuilder.B(-118, -16, 0), yaw: 50, elevation: 10, zoom: 1.7)

    /// 見下ろしの範囲（板: 縦は −60°〜12° の rx ＝ 見下ろし −12°〜60°。下から見る図のためだけに −50° まで開ける）
    static let elevationRange: ClosedRange<Double> = -50...70
    /// 寄りの範囲（遠く 0.6 倍〜近く 6 倍）
    static let zoomRange: ClosedRange<Double> = 0.6...6

    /// カメラの距離（板の透視 900 と同じ見え方。1/100 の単位）
    static func distance(zoom: Double) -> Double { 9.0 / max(0.1, zoom) }
    /// 縦の画角（度）。板の 360 の高さを 900 先から見る角度
    static let fieldOfView = 23.0

    /// 指で動かした分（板: 横 0.6°/pt・縦 0.4°/pt）
    static func dragged(_ v: CamperAngle, dx: Double, dy: Double) -> CamperAngle {
        var out = v
        out.yaw = v.yaw + dx * 0.6
        out.elevation = min(elevationRange.upperBound, max(elevationRange.lowerBound, v.elevation + dy * 0.4))
        return out
    }

    static func pinched(_ v: CamperAngle, scale: Double) -> CamperAngle {
        var out = v
        out.zoom = min(zoomRange.upperBound, max(zoomRange.lowerBound, v.zoom * scale))
        return out
    }
}
