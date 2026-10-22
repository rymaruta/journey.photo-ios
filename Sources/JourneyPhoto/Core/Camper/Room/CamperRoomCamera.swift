import Foundation

// 室内のカメラ（2026-10-19・付箋「室内の見せ方」）。
//
// 斜め上から見下ろす箱庭: 縦 −38°・横 −34°。回せる範囲は横 −90°〜90°（後ろの面は見せない）、縦 −60°〜−25°、二本指で 0.8〜28 倍。
// 1.8 倍より寄ると、家具の無い所をなぞって部屋の中を見て回る（大きな部屋の端まで届く）。
// 2026-10-19 判断: 部屋は回さず、カメラが部屋のまわりを回る（指の位置から床・壁のマスを読むのが、同じ式で済む）。
// SceneKit の側は `eye` と `orientation` をそのまま入れる。指の位置から床・壁の点を読む（`ray`）のも同じ式なので、
// 画面の絵と押した所がずれない。素の Swift なので試験できる。

struct CamperRoomCamera: Equatable, Sendable {
    /// 横の回り（度。0 で扉の壁の側から奥の壁を正面に見る。正でカメラが前（運転席の側）へ回り、後ろの壁を見る）
    ///
    /// 2026-10-19 判断: 板は「横 −34°・運転席側の仕切りは常に奥」だが、それでは掛けられる「後ろの壁」が手前になって
    /// 切られる。後ろの壁（窓と壁の物）が奥に見える向き（前の側から 34°）を初めの向きにした。角度の大きさは板どおり
    var yaw = 34.0
    /// 見下ろす角度（度・正）
    var pitch = 38.0
    /// 寄りの倍率
    var zoom = 1.0
    /// 狙う点（部屋の座標・板の単位）
    var target = CV3(90, 22, 45)
    /// 倍率 1 の距離を決めて寄る（図鑑の寄り）。nil は部屋の広さから
    var baseDistanceOverride: Double?

    static let yawRange = -90.0...90.0
    static let pitchRange = 25.0...60.0
    /// 大きな部屋でも家具のそばまで寄れる（2026-10-19。部屋を画面いっぱいに見たままでは、端の家具が豆になる）
    static let zoomRange = 0.8...28.0
    /// 縦の画角（度）
    static let fieldOfView = 34.0

    /// 部屋の初めの向き（部屋の真ん中を狙い、部屋が画面に収まる距離）
    static func overview(_ layout: CamperRoomLayout) -> CamperRoomCamera {
        let s = layout.size
        return CamperRoomCamera(yaw: 34, pitch: 38, zoom: 1, target: CV3(s.x / 2, 18, s.z / 2 + 4))
    }

    /// 写真を飾るときの向き（奥の壁へ寄る・板 CamperRoomMain の photos: 縦 −14°・横 −6°・1.55 倍）
    static func wall(_ layout: CamperRoomLayout) -> CamperRoomCamera {
        let s = layout.size
        return CamperRoomCamera(yaw: 6, pitch: 25, zoom: 1.55, target: CV3(s.x / 2, 46, 10))
    }

    /// 見本の起動の寄り（`CamperRoomPreview.cameraPreset`）。corner: 扉の壁と前の仕切りの角（切った壁の天端・角・敷居）、
    /// curtain: 奥の壁の最初の窓の右の脇（カーテン・留め紐・窓台）。知らない名前は nil
    static func preview(_ name: String, layout: CamperRoomLayout) -> CamperRoomCamera? {
        let s = layout.size
        func at(_ target: CV3, yaw: Double, pitch: Double, distance: Double) -> CamperRoomCamera {
            CamperRoomCamera(yaw: yaw, pitch: pitch, zoom: baseDistance(layout) / distance, target: target).clamped()
        }
        switch name {
        case "corner":
            return at(CV3(s.x - 14, 4, s.z - 8), yaw: 34, pitch: 38, distance: 70)
        case "curtain":
            guard let w = layout.windows.first(where: { $0.wall == .back }) else { return nil }
            let x1 = Double(w.to + 1) * CamperRoomLayout.cell
            return at(CV3(x1 + 2, (w.bottom + w.top) / 2 - 4, 8), yaw: 6, pitch: 25, distance: 75)
        default:
            return nil
        }
    }

    /// 選んだ額が見える向き。部屋の真ん中ではなく、その額の前に寄る
    static func framing(_ item: CamperRoomItem, layout: CamperRoomLayout) -> CamperRoomCamera {
        guard let placed = CamperRoomBuilder.place(item, ceiling: layout.ceilingHeight) else { return wall(layout) }
        let p = placed.position
        let left = item.w == .left
        let yaw = left ? 72.0 : 6.0
        // 額の真ん中（段の下 + 半分）を狙う。天井の換気窓が画面の主役にならないよう、見下ろしを浅くする
        let midY = p.y + (placed.footprint.y / 2)
        let target = left
            ? CV3(min(layout.size.x * 0.45, p.x + 36), midY, p.z)
            : CV3(p.x, midY, min(22, layout.size.z * 0.28))
        // 額（およそ 20）が読める距離。広い部屋でも部屋全体を映さない。
        // pitch は範囲の下限（25）——それ以上見下ろすと天井の換気窓が画面に入る
        let zoom = min(zoomRange.upperBound, max(1.65, baseDistance(layout) / 100))
        return CamperRoomCamera(yaw: yaw, pitch: pitchRange.lowerBound, zoom: zoom, target: target).clamped()
    }

    /// 部屋の広さから決める、倍率 1 の距離（部屋の対角が画面に収まる）
    static func baseDistance(_ layout: CamperRoomLayout) -> Double {
        let s = layout.size
        let diag = (s.x * s.x + s.z * s.z).squareRoot()
        return diag * 1.55 + 60
    }

    func distance(_ layout: CamperRoomLayout) -> Double { (baseDistanceOverride ?? Self.baseDistance(layout)) / zoom }

    /// 範囲に収める
    func clamped() -> CamperRoomCamera {
        var c = self
        c.yaw = min(Self.yawRange.upperBound, max(Self.yawRange.lowerBound, yaw))
        c.pitch = min(Self.pitchRange.upperBound, max(Self.pitchRange.lowerBound, pitch))
        c.zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom))
        return c
    }

    /// カメラの置き場所（部屋の座標）。扉の壁（z の大きい側）の上から見下ろす
    func eye(_ layout: CamperRoomLayout) -> CV3 {
        let d = distance(layout)
        let y = yaw * .pi / 180, p = pitch * .pi / 180
        let back = CV3(sin(-y) * cos(p) * -1, sin(p), cos(-y) * cos(p))
        return target + back * d
    }

    /// 向き（−Z がカメラの見る向き。横に yaw、縦に pitch だけ下を向く）
    var orientation: CQuat {
        let y = CQuat.axisAngle(CV3(0, 1, 0), yaw * .pi / 180)
        let p = CQuat.axisAngle(CV3(1, 0, 0), -pitch * .pi / 180)
        return y * p
    }

    /// 画面の点（左上が原点）から、部屋の中へ向かう光線（始点と向き）
    func ray(_ point: CGPoint, viewport: CGSize, layout: CamperRoomLayout) -> (origin: CV3, direction: CV3) {
        let w = max(1, Double(viewport.width)), h = max(1, Double(viewport.height))
        let nx = Double(point.x) / w * 2 - 1
        let ny = 1 - Double(point.y) / h * 2
        let t = tan(Self.fieldOfView * .pi / 360)
        let local = CV3(nx * t * w / h, ny * t, -1).normalized
        return (eye(layout), orientation.rotate(local).normalized)
    }

    /// 部屋の点を画面の点へ（回す・しまうの札を家具の上に出す）。カメラの後ろなら nil
    func project(_ p: CV3, viewport: CGSize, layout: CamperRoomLayout) -> CGPoint? {
        let inv = CQuat(x: -orientation.x, y: -orientation.y, z: -orientation.z, w: orientation.w)
        let local = inv.rotate(p - eye(layout))
        guard local.z < -0.01 else { return nil }
        let w = max(1, Double(viewport.width)), h = max(1, Double(viewport.height))
        let t = tan(Self.fieldOfView * .pi / 360)
        let nx = local.x / -local.z / (t * w / h), ny = local.y / -local.z / t
        return CGPoint(x: (nx + 1) / 2 * w, y: (1 - ny) / 2 * h)
    }

    /// 指で回す（横に動かすと横の回り、縦に動かすと見下ろしの角度）
    func dragged(dx: Double, dy: Double) -> CamperRoomCamera {
        var c = self
        c.yaw -= dx * 0.3
        c.pitch += dy * 0.2
        return c.clamped()
    }

    func pinched(_ scale: Double) -> CamperRoomCamera {
        var c = self
        c.zoom *= scale
        return c.clamped()
    }

    /// 寄った状態で、狙う点を床の上で動かす（指に部屋が付いてくる）。部屋の外へは出ない
    func panned(dx: Double, dy: Double, layout: CamperRoomLayout) -> CamperRoomCamera {
        var c = self
        let y = yaw * .pi / 180
        let lookX = -sin(y), lookZ = -cos(y)
        let rightX = lookZ, rightZ = -lookX
        let scale = distance(layout) / 500
        c.target.x += (-dx * rightX + dy * lookX) * scale
        c.target.z += (-dx * rightZ + dy * lookZ) * scale
        let s = layout.size
        c.target.x = min(max(0, c.target.x), s.x)
        c.target.z = min(max(0, c.target.z), s.z)
        return c
    }

    /// 二度押し（2026-10-21）: 離れていれば押した床の点へ 2.4 倍で寄り、寄っていれば初めの向きへ戻る
    func doubleTapped(floor point: CV3?, layout: CamperRoomLayout) -> CamperRoomCamera {
        if zoom >= Self.doubleTapZoom * 0.75 { return Self.overview(layout) }
        var c = self
        c.zoom = Self.doubleTapZoom
        if let p = point {
            let s = layout.size
            c.target = CV3(min(max(0, p.x), s.x), 18, min(max(0, p.z), s.z))
        }
        return c.clamped()
    }

    static let doubleTapZoom = 2.4

    /// 初めの向きから動いているか（「向きを戻す」を出す）
    func differs(from other: CamperRoomCamera) -> Bool {
        abs(yaw - other.yaw) > 2 || abs(pitch - other.pitch) > 2 || abs(zoom - other.zoom) > 0.06 || (target - other.target).length > 3
    }

    /// 持ち上げた家具を画面の端（帯 `band` pt の中）へ運んだら、カメラが少しだけその向きへ追う（2026-10-21）。
    /// 端でなければ nil。寄っていない（部屋が全部見えている）ときは追わない
    func following(_ point: CGPoint, viewport: CGSize, layout: CamperRoomLayout, band: Double = 44) -> CamperRoomCamera? {
        guard zoom > 1.25 else { return nil }
        let x = Double(point.x), y = Double(point.y), w = Double(viewport.width), h = Double(viewport.height)
        func push(_ d: Double) -> Double { max(0, min(1, (band - d) / band)) }
        // 左の端では部屋を右へ送る（指を右へなぞったのと同じ）。上の端（奥）では部屋を手前へ
        let dx = (push(x) - push(w - x)) * 7
        let dy = (push(y) - push(h - y)) * 7
        guard abs(dx) > 0.01 || abs(dy) > 0.01 else { return nil }
        return panned(dx: dx, dy: dy, layout: layout)
    }

    /// カメラの側の端の壁（後ろ x = 0 か、前 x = 幅）。手前の壁は高さ 9 で切る（どちらを切るかは向きで自動）。
    /// 正の向きではカメラが前の側にいるので、前の仕切りを切る
    var cutsFrontEnd: Bool { yaw >= 0 }
}

/// 光線と平面・箱の交わり（指の位置から床・壁・家具を読む）
enum CamperRoomPick {

    /// 高さ y の水平な面との交点
    static func hitHorizontal(_ ray: (origin: CV3, direction: CV3), y: Double) -> CV3? {
        guard abs(ray.direction.y) > 1e-6 else { return nil }
        let t = (y - ray.origin.y) / ray.direction.y
        guard t > 0 else { return nil }
        return ray.origin + ray.direction * t
    }

    /// 壁の面（奥の壁 z = 0・後ろの壁 x = 0）との交点
    static func hitWall(_ ray: (origin: CV3, direction: CV3), _ wall: CamperRoomWall) -> CV3? {
        switch wall {
        case .back:
            guard abs(ray.direction.z) > 1e-6 else { return nil }
            let t = -ray.origin.z / ray.direction.z
            return t > 0 ? ray.origin + ray.direction * t : nil
        case .left:
            guard abs(ray.direction.x) > 1e-6 else { return nil }
            let t = -ray.origin.x / ray.direction.x
            return t > 0 ? ray.origin + ray.direction * t : nil
        }
    }

    /// 箱（最小・最大の角）と交わる距離
    static func hitBox(_ ray: (origin: CV3, direction: CV3), min lo: CV3, max hi: CV3) -> Double? {
        var tMin = 0.0, tMax = Double.greatestFiniteMagnitude
        for (o, d, a, b) in [(ray.origin.x, ray.direction.x, lo.x, hi.x), (ray.origin.y, ray.direction.y, lo.y, hi.y),
                             (ray.origin.z, ray.direction.z, lo.z, hi.z)] {
            if abs(d) < 1e-9 {
                if o < a || o > b { return nil }
                continue
            }
            var t1 = (a - o) / d, t2 = (b - o) / d
            if t1 > t2 { swap(&t1, &t2) }
            tMin = max(tMin, t1)
            tMax = min(tMax, t2)
            if tMin > tMax { return nil }
        }
        return tMin
    }

    /// 置いた家具の箱（部屋の座標）。壁の物は壁から厚みだけ出る
    static func bounds(_ item: CamperRoomItem, ceiling: Double = CamperRoomLayout.ceiling) -> (min: CV3, max: CV3)? {
        guard let f = item.furniture else { return nil }
        let cell = CamperRoomLayout.cell
        switch f.placement {
        case .floor:
            guard let r = item.rect else { return nil }
            let h = max(f.height, 3)
            return (CV3(Double(r.x) * cell, 0, Double(r.z) * cell), CV3(Double(r.x + r.w) * cell, h, Double(r.z + r.d) * cell))
        case .ceiling:
            guard let r = item.rect else { return nil }
            let top = ceiling
            return (CV3(Double(r.x) * cell, top - f.height, Double(r.z) * cell), CV3(Double(r.x + r.w) * cell, top, Double(r.z + r.d) * cell))
        case .wall:
            guard let s = item.wallSpan else { return nil }
            let lo = CamperRoomLayout.rowBottoms[s.rows.lowerBound], hi = lo + CamperRoomLayout.rowHeight * Double(s.rows.count)
            let a = Double(s.columns.lowerBound) * cell, b = Double(s.columns.upperBound) * cell
            let t = max(f.height, 4)
            return s.wall == .back ? (CV3(a, lo, 0), CV3(b, hi, t)) : (CV3(0, lo, a), CV3(t, hi, b))
        }
    }

    /// 指の下の家具（いちばん手前）
    static func item(at ray: (origin: CV3, direction: CV3), in doc: CamperRoomDocument, ceiling: Double = CamperRoomLayout.ceiling) -> CamperRoomItem? {
        var best: (CamperRoomItem, Double)?
        for item in doc.all {
            guard let b = bounds(item, ceiling: ceiling), let t = hitBox(ray, min: b.min, max: b.max) else { continue }
            if best == nil || t < best!.1 { best = (item, t) }
        }
        return best?.0
    }

    /// 押して置く（2026-10-21）: 棚の家具を、押した所に置くとしたらどこか（床・天井は押した所のマス、壁は先に当たる壁の段）。
    /// 押した所が部屋の面に当たらなければ nil
    static func spot(for f: CamperRoomFurniture, ray: (origin: CV3, direction: CV3), layout: CamperRoomLayout) -> CamperRoomItem? {
        let template: CamperRoomItem
        switch f.placement {
        case .floor:
            let y = 0.0
            guard let p = hitHorizontal(ray, y: y), p.x >= -5, p.z >= -5, p.x <= layout.size.x + 5, p.z <= layout.size.z + 5 else { return nil }
            template = .floor("new", f.id, x: 0, z: 0)
        case .ceiling:
            guard let p = hitHorizontal(ray, y: layout.ceilingHeight - f.height), p.x >= -5, p.z >= -5,
                  p.x <= layout.size.x + 5, p.z <= layout.size.z + 5 else { return nil }
            template = .ceiling("new", f.id, x: 0, z: 0)
        case .wall:
            template = .wall("new", f.id, .back, c: -999, row: 0)
        }
        let out = moved(template, ray: ray, layout: layout)
        if f.placement == .wall, out.c == -999 { return nil }
        return out
    }

    /// 動かしている家具の新しい場所（指の下のマス。家具の真ん中が指の下に来るように）
    static func moved(_ item: CamperRoomItem, ray: (origin: CV3, direction: CV3), layout: CamperRoomLayout) -> CamperRoomItem {
        guard let f = item.furniture else { return item }
        let cell = CamperRoomLayout.cell
        var out = item
        switch f.placement {
        case .floor, .ceiling:
            let y = f.placement == .floor ? 0 : layout.ceilingHeight - f.height
            guard let p = hitHorizontal(ray, y: y), let r = item.rect else { return item }
            out.x = Int((p.x / cell - Double(r.w) / 2).rounded())
            out.z = Int((p.z / cell - Double(r.d) / 2).rounded())
        case .wall:
            // 奥の壁と後ろの壁のうち、指の先が先に当たる方
            let hits = CamperRoomWall.allCases.compactMap { w -> (CamperRoomWall, CV3, Double)? in
                guard let p = hitWall(ray, w) else { return nil }
                let along = w == .back ? p.x : p.z
                let max = Double(layout.columns(w)) * cell
                guard along >= -cell, along <= max + cell, p.y > 0, p.y < layout.ceilingHeight else { return nil }
                return (w, p, (p - ray.origin).length)
            }.sorted { $0.2 < $1.2 }
            guard let (w, p, _) = hits.first else { return item }
            let along = w == .back ? p.x : p.z
            out.w = w
            out.c = Int((along / cell - Double(f.width) / 2).rounded())
            let rowF = (p.y - CamperRoomLayout.rowBottoms[0]) / CamperRoomLayout.rowHeight - Double(f.depth) / 2
            out.row = min(CamperRoomLayout.rowBottoms.count - f.depth, max(0, Int(rowF.rounded())))
        }
        return out
    }
}
