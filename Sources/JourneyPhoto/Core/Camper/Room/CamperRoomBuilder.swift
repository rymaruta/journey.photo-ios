import Foundation

// とおまわり号の中の部屋を組む（2026-10-19）。床・壁・窓・カーテン・台所・扉の口・天井と、置いた家具の場所と、夜の灯り。
// 素の Swift の並び（`CamperNodeSpec`・`CamperLightSpec`）を作り、SceneKit の側（`CamperRoomScene`）はそれを写すだけ。
//
// 🔴 owner「内部も外部もどこから見てもホンモノにする」:
// - 壁は 3 層（内の板 1・断熱 1.8・外板 1.2 = 板の付箋の壁の断面）。手前の壁を高さ 9 で切った所に断面が見える
// - 窓は壁に開けた穴（木の枠・黒いゴム・表から奥の硝子・窓台・その外の景色）。カーテンはひだのある布を棒に
// - 床は板張りの貼り絵と幅木。台所は箱の扉・取っ手・石の天板・本当に凹んだ流し・蛇口・二口の焜炉とやかん
// - 天井は下向きの面（上から見下ろす箱庭では裏なので見えず、低い目線と影では効く）
// 座標は部屋の座標（左奥が原点・板の単位）。SceneKit へは 1/100。

private typealias K = CamperRoomMeshKit
private func R(_ m: CamperRoomMaterial) -> CamperMaterial { .room(m) }

/// 置いた家具 1 つ（場面の側が形を写して置く）
struct CamperRoomPlacedItem: Equatable, Sendable {
    var uid: String
    var furnitureId: String
    /// 原点（床の物は足元の真ん中・壁の物は段の下の真ん中の壁の面・天井の物は天井の真ん中）
    var position: CV3
    /// 横の回り（ラジアン）。壁の物は壁の向き
    var yaw: Double
    var photos: [String]
    var placement: CamperRoomPlacement
    /// 床に落とす接地の影の大きさ（横・奥。板の単位）
    var footprint: CV2
}

struct CamperRoomBlueprint: Sendable {
    var layout: CamperRoomLayout
    var shell: [CamperNodeSpec] = []
    var items: [CamperRoomPlacedItem] = []
    /// 夜の灯り（置いた灯りの家具・天井の灯り）。昼の太陽と月は場面の側
    var lights: [CamperLightSpec] = []

    var triangleEstimate: Int { shell.reduce(0) { $0 + $1.triangleEstimate } }
}

enum CamperRoomBuilder {

    /// 手前の壁を切る高さ（板: 高さ 9）
    static let cutHeight = 9.0
    /// 壁の 3 層（内の板・断熱・外板）
    static let layers: [(depth: Double, inner: Double)] = [(1, 0), (1.8, 1), (1.2, 2.8)]
    /// 夜の灯りの数の上限（月・周りの光・天井の灯りと合わせて SceneKit の 1 つの物に効く 8 を超えない）
    static let maxLamps = 5

    static func build(_ layout: CamperRoomLayout, doc: CamperRoomDocument, paint: UInt32 = 0x5B6168) -> CamperRoomBlueprint {
        var bp = CamperRoomBlueprint(layout: layout)
        let style = doc.style
        bp.shell += floor(layout, style: style)
        bp.shell += walls(layout, style: style, paint: paint)
        bp.shell += windows(layout, style: style)
        if !layout.isStudio {
            bp.shell += kitchen(layout)
            bp.shell += doorway(layout)
        }
        bp.items = doc.all.compactMap { place($0) }
        bp.lights = lights(bp.items, style: style, layout: layout)
        return bp
    }

    private static func node(_ name: String, _ mesh: CamperMesh) -> CamperNodeSpec {
        CamperNodeSpec(name: name, shape: .mesh(mesh), material: .room(.trim), position: .zero)
    }

    // MARK: 床

    static func floor(_ l: CamperRoomLayout, style: CamperRoomStyle) -> [CamperNodeSpec] {
        let s = l.size, t = CamperRoomLayout.wallThickness
        var parts: [CamperNodeSpec] = []
        // 床板（厚み 3・壁の下まで）。貼り絵は 40 単位（1 m）で 1 回
        var slab = K.roundedBox(CV3(s.x + t * 2, 3, s.z + t * 2), radius: 0.3, segments: 1, material: { $0.y > 0.5 ? R(.floorFinish(style.floor)) : R(.skin(0x26282C)) })
        slab = K.placed(slab, at: CV3(s.x / 2, -1.5, s.z / 2))
        parts.append(node("room.floor", K.reUV(slab, scale: 40)))
        // 天井（下向きの面だけ・上からは裏で見えない）
        var ceiling = CamperMesh()
        ceiling.positions = [CV3(0, CamperRoomLayout.ceiling, 0), CV3(s.x, CamperRoomLayout.ceiling, 0), CV3(s.x, CamperRoomLayout.ceiling, s.z),
                             CV3(0, CamperRoomLayout.ceiling, s.z)]
        ceiling.normals = Array(repeating: CV3(0, -1, 0), count: 4)
        ceiling.uvs = [CV2(0, 0), CV2(4, 0), CV2(4, 2), CV2(0, 2)]
        ceiling.groups = [(R(.wallFinish("plywood_birch")), [0, 1, 2, 0, 2, 3])]
        parts.append(node("room.ceiling", ceiling))
        // 幅木（奥の壁・後ろの壁・前の仕切り。扉の壁は低く切るので付けない）
        parts.append(node("room.baseboard.back", K.block(CV3(s.x, 3.2, 0.9), at: CV3(s.x / 2, 0, 0.45), radius: 0.2, R(.trim))))
        parts.append(node("room.end.rear.full.baseboard", K.block(CV3(0.9, 3.2, s.z), at: CV3(0.45, 0, s.z / 2), radius: 0.2, R(.trim))))
        parts.append(node("room.end.front.full.baseboard", K.block(CV3(0.9, 3.2, s.z), at: CV3(s.x - 0.45, 0, s.z / 2), radius: 0.2, R(.trim))))
        return parts
    }

    // MARK: 壁

    /// 壁 1 枚（3 層・窓の穴あり）。外形は壁の面の上の (横, 高さ)、表は +Z（部屋の内）
    static func wallLayers(outline: [CV2], holes: [[CV2]], style: CamperRoomStyle, paint: UInt32) -> CamperMesh {
        var parts: [CamperMesh] = []
        for (i, layer) in layers.enumerated() {
            let front: CamperMaterial = i == 0 ? R(.wallFinish(style.wall)) : (i == 1 ? R(.insulation) : R(.skin(paint)))
            let side: CamperMaterial = i == 0 ? R(.wallFinish(style.wall)) : (i == 1 ? R(.insulation) : R(.skin(paint)))
            let reveal: CamperMaterial = i == 2 ? R(.skin(paint)) : R(.trim)
            var m = CamperMeshKit.slab(outline: outline, holes: holes, thickness: layer.depth, bevel: 0, holeBevel: 0,
                                       bands: [CamperBand(minY: -.infinity, maxY: .infinity, material: front)],
                                       side: { _, _ in side }, back: i == 2 ? R(.skin(paint)) : front, reveal: reveal)
            m = m.translated(CV3(0, 0, -layer.inner))
            parts.append(i == 0 ? K.reUV(m, scale: 40) : m)
        }
        return K.merge(parts)
    }

    static func windowHole(_ w: CamperRoomWindow) -> [CV2] {
        let cell = CamperRoomLayout.cell
        return CamperPolygon.roundedRect(x: Double(w.from) * cell + 2, y: w.bottom, w: Double(w.to - w.from + 1) * cell - 4, h: w.top - w.bottom, r: 4,
                                         seg: 3)
    }

    static func walls(_ l: CamperRoomLayout, style: CamperRoomStyle, paint: UInt32) -> [CamperNodeSpec] {
        let s = l.size, t = CamperRoomLayout.wallThickness, h = CamperRoomLayout.ceiling
        var out: [CamperNodeSpec] = []
        // 奥の壁（z = 0・+Z 向き）
        let backHoles = l.windows.filter { $0.wall == .back }.map(windowHole)
        let back = wallLayers(outline: [CV2(-t, -3), CV2(s.x + t, -3), CV2(s.x + t, h), CV2(-t, h)], holes: backHoles, style: style, paint: paint)
        out.append(node("room.wall.back", back))
        // 後ろの壁（x = 0・+X 向き）。横は z（壁の面の上で -z）
        let leftHoles = l.windows.filter { $0.wall == .left }.map { w in windowHole(w).map { CV2(-$0.x, $0.y) } }
        for (name, height, holes) in [("room.end.rear.full", h, leftHoles), ("room.end.rear.low", cutHeight, [])] {
            let m = wallLayers(outline: [CV2(-(s.z + t), -3), CV2(t, -3), CV2(t, height), CV2(-(s.z + t), height)], holes: holes, style: style, paint: paint)
            out.append(node(name, K.placed(m, at: .zero, yaw: .pi / 2)))
        }
        // 前の仕切り（x = 幅・-X 向き。運転席との境）
        for (name, height) in [("room.end.front.full", h), ("room.end.front.low", cutHeight)] {
            let m = wallLayers(outline: [CV2(-t, -3), CV2(s.z + t, -3), CV2(s.z + t, height), CV2(-t, height)], holes: [], style: style, paint: paint)
            out.append(node(name, K.placed(m, at: CV3(s.x, 0, 0), yaw: -.pi / 2)))
        }
        // 扉の壁（z = 奥行き・-Z 向き）は、いつも高さ 9 で切る。扉の口は切れ目
        let cell = CamperRoomLayout.cell
        let d0 = Double(l.door.lowerBound) * cell, d1 = Double(l.door.upperBound + 1) * cell
        let pieces = l.isStudio ? [(-t, s.x + t)] : [(-t, d0), (d1, s.x + t)]
        for (a, b) in pieces where b > a {
            let m = wallLayers(outline: [CV2(-b, -3), CV2(-a, -3), CV2(-a, cutHeight), CV2(-b, cutHeight)], holes: [], style: style, paint: paint)
            out.append(node("room.wall.door", K.placed(m, at: CV3(0, 0, s.z), yaw: .pi)))
        }
        return out
    }

    // MARK: 窓とカーテン

    static func windows(_ l: CamperRoomLayout, style: CamperRoomStyle) -> [CamperNodeSpec] {
        let cell = CamperRoomLayout.cell
        var out: [CamperNodeSpec] = []
        for (i, w) in l.windows.enumerated() {
            let hole = windowHole(w)
            let x0 = Double(w.from) * cell + 2, width = Double(w.to - w.from + 1) * cell - 4
            let cx = x0 + width / 2, cy = (w.bottom + w.top) / 2, hgt = w.top - w.bottom
            var parts: [CamperMesh] = []
            // 木の枠（内の面から少し出る）・黒いゴム・硝子（表から 2.2 奥）・窓台
            let ring = CamperPolygon.offset(CamperPolygon.ccw(hole), by: 1.6)
            parts.append(CamperMeshKit.extrude(ring, holes: [CamperPolygon.cw(hole)], depth: 1.4, front: R(.trim), side: R(.trim), bevel: 0.35)
                .translated(CV3(0, 0, 1.2)))
            parts.append(K.tube(CamperPolygon.offset(CamperPolygon.ccw(hole), by: -0.5).map { CV3($0.x, $0.y, -2.0) }, radius: 0.55, sides: 6,
                                closed: true, R(.windowRubber)))
            parts.append(K.placed(K.panel(width: width - 1, height: hgt - 1, R(.glass)), at: CV3(cx, cy, -2.2)))
            parts.append(K.block(CV3(width + 6, 1.4, 4), at: CV3(cx, w.bottom - 1.4, 1.4), radius: 0.5, R(.trim)))
            // 外の景色（光を受けない絵・壁の後ろ 14）。上の端は壁の上から見えない高さまで
            parts.append(K.placed(K.panel(width: width * 1.9, height: 60, R(.windowView)), at: CV3(cx, 44, -14)))
            // カーテンの棒と金具・左右に寄せたひだの布
            let rodY = w.top + 5
            parts.append(K.tube([CV3(x0 - 8, rodY, 3.2), CV3(x0 + width + 8, rodY, 3.2)], radius: 0.4, sides: 8, R(.agedBrass)))
            for x in [x0 - 9, x0 + width + 9] {
                parts.append(K.placed(K.sphere(radius: 0.8, segments: 10, R(.agedBrass)), at: CV3(x, rodY, 3.2)))
                parts.append(K.tube([CV3(x + (x < cx ? 1.5 : -1.5), rodY, 3.2), CV3(x + (x < cx ? 1.5 : -1.5), rodY, 0.2)], radius: 0.3, sides: 6,
                                    R(.agedBrass)))
            }
            let color = CamperRoomMaterials.curtainColor(style.curtain)
            for side in [-1.0, 1.0] {
                let panelW = 9.0
                let px = side < 0 ? x0 - 2 + panelW / 2 - 4 : x0 + width + 2 - panelW / 2 + 4
                parts.append(K.placed(K.drape(width: panelW, height: rodY - w.bottom + 4, folds: 3, depth: 1.1, flare: 0.3, R(.curtain(color))),
                                      at: CV3(px, rodY - 0.6, 3.0)))
                // 留め紐（裾の上で布をまとめる）
                parts.append(K.tube(K.arc(center: CV3(px, w.bottom + 8, 3.6), radius: 3.4, from: .pi * 1.05, to: .pi * 1.95, steps: 8)
                    .map { CV3($0.x, w.bottom + 8 + ($0.y - (w.bottom + 8)) * 0.3, 3.6 + abs($0.y - (w.bottom + 8)) * 0.2) },
                                    radius: 0.3, sides: 5, R(.rope)))
            }
            var mesh = K.merge(parts)
            // 後ろの壁の窓は向きを回す
            if w.wall == .left { mesh = K.placed(mesh.mapped({ CV3(-$0.x, $0.y, $0.z) }, normal: { CV3(-$0.x, $0.y, $0.z) }, mirror: true), at: .zero, yaw: .pi / 2) }
            out.append(node(w.wall == .left ? "room.end.rear.full.window\(i)" : "room.window\(i)", mesh))
        }
        return out
    }

    // MARK: 台所

    static func kitchen(_ l: CamperRoomLayout) -> [CamperNodeSpec] {
        let cell = CamperRoomLayout.cell
        let k = l.kitchen
        let x0 = Double(k.x) * cell, w = Double(k.w) * cell, d = Double(k.d) * cell
        let cx = x0 + w / 2
        let top = CamperRoomLayout.kitchenHeight
        let body = R(.cabinet(0x8E9A8A))
        var parts: [CamperMesh] = []
        // 箱（下は引っ込んだ蹴込み）
        parts.append(K.block(CV3(w - 0.4, 3, d - 4), at: CV3(cx, 0, (d - 4) / 2), radius: 0.2, R(.painted(0x1E1F21))))
        parts.append(K.block(CV3(w - 0.4, top - 5.4, d - 1.2), at: CV3(cx, 3, (d - 1.2) / 2), radius: 0.4, body))
        // 扉 3 枚（隙間・面取り）と真鍮の取っ手
        let doorW = (w - 1.6) / 3
        for i in 0..<3 {
            let dx = x0 + 0.8 + doorW * (Double(i) + 0.5)
            parts.append(K.block(CV3(doorW - 0.5, top - 7, 0.9), at: CV3(dx, 3.6, d - 1.2 + 0.45), radius: 0.35, body))
            let hx = dx + (i == 1 ? 0 : (i == 0 ? doorW / 2 - 2.4 : -doorW / 2 + 2.4))
            parts.append(K.tube([CV3(hx, top - 8, d - 0.3), CV3(hx, top - 8, d + 0.8), CV3(hx, top - 14, d + 0.8), CV3(hx, top - 14, d - 0.3)],
                                radius: 0.32, sides: 6, R(.brass)))
        }
        // 石の天板（流しの穴）
        let sinkW = 16.0, sinkD = 12.0, sinkX = x0 + 14
        let topOutline = CamperPolygon.roundedRect(x: x0 - 0.5, y: -0.5, w: w + 1, h: d + 1.6, r: 0.6, seg: 2)
        let sinkHole = CamperPolygon.cw(CamperPolygon.roundedRect(x: sinkX - sinkW / 2, y: d / 2 - sinkD / 2, w: sinkW, h: sinkD, r: 1.6, seg: 3))
        var counter = CamperMeshKit.slab(outline: topOutline, holes: [sinkHole], thickness: 2.4, bevel: 0.6, holeBevel: 0.3,
                                         bands: [CamperBand(minY: -.infinity, maxY: .infinity, material: R(.countertop))],
                                         side: { _, _ in R(.countertop) }, back: R(.countertop), reveal: R(.sinkSteel))
        // 板の面（x, y）を床に寝かせる: 表（+Z）を上（+Y）へ。y はそのまま z へ
        counter = counter.mapped({ CV3($0.x, top + $0.z, $0.y) }, normal: { CV3($0.x, $0.z, $0.y) }, mirror: true)
        parts.append(counter)
        // 流し（本当に凹んだ箱・内向きの面）と排水口
        parts.append(CamperRoomShapes.basin(center: CV3(sinkX, top - 2.4, d / 2), width: sinkW - 0.4, depth: sinkD - 0.4, height: 8, R(.sinkSteel)))
        parts.append(K.placed(K.disc(radius: 1.1, height: 0.2, bevel: 0.05, segments: 14, R(.chrome)), at: CV3(sinkX, top - 10.3, d / 2)))
        // 蛇口（首の曲がった管・レバー）
        let base = CV3(sinkX, top, 2.6)
        parts.append(K.placed(K.disc(radius: 1.3, height: 1.2, bevel: 0.3, segments: 16, R(.chrome)), at: base))
        parts.append(K.tube([base + CV3(0, 1, 0), base + CV3(0, 9, 0), base + CV3(0, 11.5, 1.6), base + CV3(0, 11, 4.4), base + CV3(0, 8.6, 5.8)],
                            radius: 0.55, sides: 10, R(.chrome)))
        parts.append(K.tube([base + CV3(0, 3, 0), base + CV3(1.6, 4.4, 0.6), base + CV3(3.4, 4.8, 0.6)], radius: 0.3, sides: 6, R(.chrome)))
        // 二口の焜炉（黒い硝子の板・火口の輪・五徳）とやかん
        let stoveX = x0 + w - 16
        parts.append(K.block(CV3(24, 0.5, 16), at: CV3(stoveX, top, d / 2), radius: 0.4, R(.castIron)))
        for dx in [-5.5, 5.5] {
            let c = CV3(stoveX + dx, top + 0.5, d / 2)
            parts.append(K.tube(K.arc(center: .zero, radius: 3, from: 0, to: 2 * .pi, steps: 20).map { c + CV3($0.x, 0.3, $0.y) }, radius: 0.35,
                                sides: 6, closed: true, R(.iron)))
            for a in stride(from: 0.0, to: 2 * .pi, by: .pi / 2) {
                parts.append(K.tube([c + CV3(cos(a) * 1.4, 1.4, sin(a) * 1.4), c + CV3(cos(a) * 4.4, 1.4, sin(a) * 4.4)], radius: 0.25, sides: 5, R(.iron)))
            }
        }
        let kettle = CV3(stoveX + 5.5, top + 2.1, d / 2)
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(3.2, 0), CV2(3.6, 1.4), CV2(3.0, 3.6), CV2(1.4, 4.6), CV2(1.4, 5.0), CV2(0, 5.0)], segments: 24,
                                      R(.enamel(0x2F4F74))), at: kettle))
        parts.append(K.tube([kettle + CV3(-2.8, 1.6, 0), kettle + CV3(-4.6, 3.4, 0), kettle + CV3(-5.4, 4.6, 0)], radius: 0.5, sides: 8,
                            R(.enamel(0x2F4F74))))
        parts.append(K.tube(K.arc(center: kettle + CV3(0, 5, 0), radius: 2.6, from: 0.2, to: .pi - 0.2, steps: 8), radius: 0.25, sides: 6, R(.iron)))
        // 壁のタイル（目地のある白いタイル・天板の上 16）
        parts.append(K.placed(K.panel(width: w, height: 16, R(.ceramic(0xE9E4DA))), at: CV3(cx, top + 2.4 + 8, 0.25)))
        for k in 1..<4 {
            parts.append(K.block(CV3(w, 0.25, 0.2), at: CV3(cx, top + 2.4 + Double(k) * 4, 0.3), radius: 0.05, R(.painted(0xB8B2A6))))
        }
        for k in 1..<Int(w / 8) {
            let off = (k % 2 == 0) ? 0.0 : 4
            parts.append(K.block(CV3(0.2, 16, 0.2), at: CV3(x0 + Double(k) * 8 - off, top + 2.4, 0.3), radius: 0.05, R(.painted(0xB8B2A6))))
        }
        // まな板と瓶
        parts.append(K.placed(K.roundedBox(CV3(9, 0.8, 6.4), radius: 0.4, segments: 2, R(.wornWood(.oak))), at: CV3(sinkX + 12, top + 2.8, d / 2 + 2),
                              yaw: 0.15))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.5, 0), CV2(1.6, 4), CV2(1.1, 4.6), CV2(1.1, 5.4), CV2(0, 5.4)], segments: 16, R(.glass)),
                              at: CV3(x0 + 4, top + 2.4, 4)))
        parts.append(K.placed(K.lathe([CV2(0, 0), CV2(1.3, 0), CV2(1.3, 3.2), CV2(0, 3.2)], segments: 14, R(.linen(0xD9A441))), at: CV3(x0 + 4, top + 2.4, 4)))
        return [node("room.kitchen", K.merge(parts))]
    }

    // MARK: 扉の口

    static func doorway(_ l: CamperRoomLayout) -> [CamperNodeSpec] {
        let cell = CamperRoomLayout.cell, s = l.size
        let d0 = Double(l.door.lowerBound) * cell, d1 = Double(l.door.upperBound + 1) * cell
        var parts: [CamperMesh] = []
        // 敷居（アルミの縞板）と、扉の枠の柱（切った高さまで）
        parts.append(K.block(CV3(d1 - d0, 1, 5), at: CV3((d0 + d1) / 2, 0, s.z + 1.5), radius: 0.3, R(.chrome)))
        for x in [d0 + 1, d1 - 1] { parts.append(K.block(CV3(2, cutHeight, 5), at: CV3(x, 0, s.z + 1.5), radius: 0.3, R(.trim))) }
        // 玄関のマット（扉の内・#7a3a2a）
        parts.append(K.rug(K.roundedRect(20, 11, r: 1).map { CV2($0.x + (d0 + d1) / 2, $0.y + s.z - 7) }, thickness: 0.7, top: R(.cotton(0x7A3A2A)),
                           edge: R(.cotton(0x5E2C20))))
        return [node("room.doorway", K.merge(parts))]
    }

    // MARK: 家具の置き場所

    static func place(_ item: CamperRoomItem) -> CamperRoomPlacedItem? {
        guard let f = item.furniture else { return nil }
        let cell = CamperRoomLayout.cell
        switch f.placement {
        case .floor, .ceiling:
            guard let r = item.rect else { return nil }
            let cx = (Double(r.x) + Double(r.w) / 2) * cell, cz = (Double(r.z) + Double(r.d) / 2) * cell
            let y = f.placement == .floor ? 0 : CamperRoomLayout.ceiling
            return CamperRoomPlacedItem(uid: item.u, furnitureId: f.id, position: CV3(cx, y, cz), yaw: -Double(item.turns) * .pi / 2,
                                        photos: item.p.map { [$0] } ?? [], placement: f.placement,
                                        footprint: CV2(Double(r.w) * cell, Double(r.d) * cell))
        case .wall:
            guard let s = item.wallSpan else { return nil }
            let along = (Double(s.columns.lowerBound) + Double(f.width) / 2) * cell
            let y = CamperRoomLayout.rowBottoms[s.rows.lowerBound]
            let pos = s.wall == .back ? CV3(along, y, 0) : CV3(0, y, along)
            return CamperRoomPlacedItem(uid: item.u, furnitureId: f.id, position: pos, yaw: s.wall == .back ? 0 : .pi / 2,
                                        photos: item.p.map { [$0] } ?? [], placement: .wall,
                                        footprint: CV2(Double(f.width) * cell, CamperRoomLayout.rowHeight * Double(f.depth)))
        }
    }

    // MARK: 灯り

    /// 夜の灯り（灯りの家具の電球の所。多ければ部屋の真ん中に近い順に `maxLamps` まで）
    static func lights(_ items: [CamperRoomPlacedItem], style: CamperRoomStyle, layout: CamperRoomLayout) -> [CamperLightSpec] {
        let color = CamperRoomMaterials.lightColor(style.light)
        let center = CV3(layout.size.x / 2, 40, layout.size.z / 2)
        var lamps: [(CamperLightSpec, Double)] = []
        for it in items {
            guard let lamp = CamperRoomFurnitureModels.lamp(it.furnitureId) else { continue }
            let q = CQuat.axisAngle(CV3(0, 1, 0), it.yaw)
            let p = it.position + q.rotate(lamp.position)
            // 火（ストーブ）は灯りの色でなく炎の色
            let fire = it.furnitureId.hasPrefix("heater.") || it.furnitureId == "wall_lamp.candle_sconce"
            let spec = CamperLightSpec(name: "interior.lamp.\(it.uid)", kind: .omni, position: p, color: fire ? 0xFF8A3C : color,
                                       intensity: lamp.intensity, range: lamp.range, moods: [.night])
            lamps.append((spec, (p - center).length))
        }
        var out = lamps.sorted { $0.1 < $1.1 }.prefix(maxLamps).map(\.0)
        // 天井の柔らかい灯り（部屋全体を下から包む・影あり。板の「室内の灯り」）
        out.append(CamperLightSpec(name: "interior.ceiling", kind: .spot, position: CV3(layout.size.x / 2, CamperRoomLayout.ceiling - 2, layout.size.z / 2),
                                   direction: CV3(0, -1, 0), color: color, intensity: 40, range: 160, spotInner: 60, spotOuter: 150,
                                   castsShadow: true, moods: [.night]))
        return out
    }
}
