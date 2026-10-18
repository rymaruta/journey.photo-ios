import SwiftUI

/// 旅のトランク（モック Trunk.dc.html をそのまま写す・2026-10-17）。360×300 の枠に描き、
/// 置く大きさに縮める（`TrunkFigure`）。
///
/// 重ね方はモックの z の順: 持ち手 → 胴（地・目・しみ・型ごとの古び・絵・ラベル）→ 縁の革・縫い目・桟 →
/// ベルト → 帯・尾錠 → 鋲 → 角・留め金 → 錠前・名札 → 擦り傷・艶 → 縁の陰 → 手荷物タグ。
/// 色はすべて `TrunkLooks.look(model, stage:)`（投稿の数で連続的に古びる・`TrunkAging.stage`）。
struct TrunkBoxView: View {
    let model: TrunkModel
    /// 公開している投稿の数（古び方）
    let posts: Int
    /// 貼ったラベル（新しい順）。置けるのは 11 枚（`TrunkSlots`）
    var stuck: [TrunkLabel] = []
    /// 名札に刻む名前（寝台列車・飛行艇の型）
    var ownerName: String?
    /// 胴だけ（3D の箱の表に貼る絵・持ち手とタグを描かない）
    var bodyOnly = false
    /// 付けている部品（2026-10-17 次の版・モック PartsOnTrunk・Equip）
    var parts: TrunkEquipped = .none
    /// 画面の上だけで動かしている置き場（自分の手で貼る画面）
    var overrides: [String: TrunkPos] = [:]
    /// 描かないラベル（自分の手で貼る画面で、指で持ち上げている1枚）
    var hidden: String?
    /// 動かしてよれたラベル（id → よれの強さ 0〜1）
    var wrinkles: [String: Double] = [:]
    /// 貼った瞬間に押さえる1枚と、その大きさ（モック Stick の `stickPress`・1.12 → 0.97 → 1）
    var pop: String?
    var popScale: Double = 1
    /// 手荷物タグを作るラベル（新しい順）。**絵に描くラベルを減らす画面（型を選ぶ）でも、タグはトランクの全部の
    /// ラベルから作る**（画面ごとにタグの枚数・中身を割らない・`TrunkLooks.tagSource`）。nil なら `stuck`
    var tagsFrom: [TrunkLabel]?

    private var stage: Double { TrunkAging.stage(posts: posts) }
    private var look: TrunkLook { TrunkLooks.look(model, stage: stage) }
    private var fittings: TrunkFittings { TrunkFittings(parts) }

    private static let W = TrunkLooks.bodyWidth
    private static let H = TrunkLooks.bodyHeight

    var body: some View {
        let look = look
        let fittings = fittings
        ZStack(alignment: .topLeading) {
            if !bodyOnly { handle(look, fittings) }
            trunkBody(look, fittings)
                .offset(y: bodyOnly ? 0 : TrunkLooks.bodyTop)
            if !bodyOnly {
                tags(look)
                hanging(fittings)
            }
        }
        .frame(width: TrunkLooks.canvasWidth, height: bodyOnly ? Self.H : TrunkLooks.canvasHeight, alignment: .topLeading)
    }

    // MARK: 持ち手

    private func handle(_ look: TrunkLook, _ fittings: TrunkFittings) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let part = fittings.handlePaint {
                    // 付けた持ち手（モックの `P.handle`・`P.handleW`）
                    TrunkPartPaintView(paint: part.paint)
                        .frame(width: 100, height: 36)
                        .clipShape(TrunkHandleShape(thickness: part.thickness))
                } else {
                    TrunkHandleShape()
                        .fill(Color(trunk: look.handle))
                        .frame(width: 100, height: 36)
                }
            }
            .shadow(color: Color.black.opacity(0.5), radius: 1.5, x: 0, y: 2)
            .offset(x: 130, y: 2)
            if model != .aluminum && model != .urushi {
                // 持ち手の縫い目（破線）
                Path { p in
                    p.move(to: CGPoint(x: 145, y: 6))
                    p.addLine(to: CGPoint(x: 215, y: 6))
                }
                .stroke(Color(trunk: TrunkRGBA(r: 255, g: 235, b: 200, a: 0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            ForEach([120.0, 220.0], id: \.self) { x in
                lockFace(look, fittings, w: 20, h: 14)
                    .frame(width: 20, height: 14)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                    .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
                    .offset(x: x, y: 26)
            }
        }
    }

    // MARK: 胴

    private func trunkBody(_ look: TrunkLook, _ fittings: TrunkFittings) -> some View {
        ZStack(alignment: .topLeading) {
            surfaceLayers(look)
            hardwareLayers(look, fittings)
            finishLayers(look)
            onBody(fittings)
        }
        .frame(width: Self.W, height: Self.H, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .drawingGroup()
        .shadow(color: Color.black.opacity(0.6), radius: 0, x: 0, y: 3)
        .shadow(color: Color.black.opacity(0.75), radius: 25, x: 0, y: 30)
    }

    /// 地・目・しみ・古び・絵・ラベル（z 0）
    @ViewBuilder
    private func surfaceLayers(_ look: TrunkLook) -> some View {
        TrunkSkin(look: look, w: Self.W, h: Self.H)
        // 縁の擦れ（板 Trunk の `edgeWear`・回したときの面とそろえる・2026-10-18）。古びていなければ何も描かない
        TrunkEdgeWear(look: look, w: Self.W, h: Self.H, corner: 16, front: true)
        if let art = look.art {
            TrunkArtCanvas(strokes: TrunkArtwork.strokes(art), viewBox: (Self.W, Self.H), fit: false)
                .frame(width: Self.W, height: Self.H)
        }
        labels
    }

    /// 縁・桟・ベルト・帯・鋲・角・留め金・錠前・名札（z 1〜6）
    @ViewBuilder
    private func hardwareLayers(_ look: TrunkLook, _ fittings: TrunkFittings) -> some View {
        binding(look)
        bars(look)
        straps(look)
        rail(look)
        buckles(look, fittings)
        rivets(look)
        corners(look, fittings)
        latches(look)
        lock(look, fittings)
        plate(look)
    }

    /// 錠前の面（付けた錠前の金属があればそれ・モックの `P.lock`）
    private func lockFace(_ look: TrunkLook, _ fittings: TrunkFittings, w: Double, h: Double) -> some View {
        TrunkHardwareFace(look: look, fittings: fittings, w: w, h: h)
    }

    /// 胴に付けた部品（ピンバッジ・ワッペン）。ラベルと艶の上に（モック Equip の z 10）
    private func onBody(_ fittings: TrunkFittings) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(fittings.placements.filter(\.onBody).enumerated()), id: \.offset) { _, p in
                placed(p, dy: -TrunkLooks.bodyTop)
            }
        }
        .frame(width: Self.W, height: Self.H, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// 持ち手から吊るす部品（手荷物タグ・チャーム・鍵）。胴の上に（モック Equip の z 11）
    private func hanging(_ fittings: TrunkFittings) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(fittings.placements.filter { !$0.onBody }.enumerated()), id: \.offset) { _, p in
                placed(p, dy: 0)
            }
        }
        .frame(width: TrunkLooks.canvasWidth, height: TrunkLooks.canvasHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func placed(_ p: TrunkFittings.Placement, dy: Double) -> some View {
        TrunkPartView(part: p.part, size: TrunkPartDrawing.size * p.scale)
            .rotationEffect(.degrees(p.rot), anchor: UnitPoint(x: p.anchorX, y: p.anchorY))
            .offset(x: p.x, y: p.y + dy)
    }

    /// 擦り傷・艶・縁の陰（z 7〜8）
    @ViewBuilder
    private func finishLayers(_ look: TrunkLook) -> some View {
        scratches(look)
        gloss(look)
        shade
    }

    /// 貼ったラベル（置き場つきはその場所に・置き場なしは新しい 11 枚をおまかせに・古いものほど褪せる）
    private var labels: some View {
        let placed = TrunkPlacement.layout(stuck, stage: stage, overrides: overrides)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(placed.indices), id: \.self) { i in
                let p = placed[i]
                if p.label.id != hidden {
                    TrunkLabelView(label: p.label, w: p.w, h: p.h, age: p.age, rot: p.rot,
                                   wrinkle: wrinkles[p.label.id] ?? 0)
                        .scaleEffect(p.label.id == pop ? popScale : 1)
                        .position(x: p.x + p.w / 2, y: p.y + p.h / 2)
                }
            }
        }
        .frame(width: Self.W, height: Self.H, alignment: .topLeading)
    }

    // MARK: 縁・桟・ベルト

    @ViewBuilder
    private func binding(_ look: TrunkLook) -> some View {
        if look.binding.width > 0 {
            let bw = look.binding.width
            ZStack {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color(trunk: look.binding.color), lineWidth: bw)
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.4), lineWidth: 1)
                if look.binding.gold {
                    // 金の押し線（縁の内側 3pt に 1pt）
                    RoundedRectangle(cornerRadius: max(2, 16 - bw - 3))
                        .strokeBorder(Color(trunk: TrunkRGBA(0xC9A66B)), lineWidth: 1)
                        .padding(bw + 3)
                }
            }
            .frame(width: Self.W, height: Self.H)
        }
        if let stitch = look.stitch {
            let inset = (look.binding.width > 0 ? look.binding.width : 6) - 4
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Color(trunk: stitch), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                .padding(inset)
                .frame(width: Self.W, height: Self.H)
        }
    }

    private func bars(_ look: TrunkLook) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(look.bars.indices), id: \.self) { i in
                let bar = look.bars[i]
                let fill = bar.brass ? TrunkFill.metal(.brass) : (look.barFill ?? .metal(.brass))
                if let x = bar.x {
                    TrunkFillView(fill: fill, stage: stage, w: bar.size, h: Self.H)
                        .frame(width: bar.size, height: Self.H)
                        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.35), radius: 2, x: 2, y: 0)
                        .offset(x: x)
                } else if let y = bar.y {
                    TrunkFillView(fill: fill, stage: stage, w: Self.W, h: bar.size)
                        .frame(width: Self.W, height: bar.size)
                        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 2)
                        .offset(y: y)
                }
            }
        }
        .frame(width: Self.W, height: Self.H, alignment: .topLeading)
    }

    /// 革のベルト・組紐・麻の縄（縦に通す）
    private func straps(_ look: TrunkLook) -> some View {
        TrunkBandStrips(look: look, height: Self.H, holes: true)
    }

    private func rail(_ look: TrunkLook) -> some View {
        TrunkFillView(fill: look.rail.fill, stage: stage, w: Self.W, h: look.rail.height)
            .frame(width: Self.W, height: look.rail.height)
            .shadow(color: Color.black.opacity(0.5), radius: 1.5, x: 0, y: 2)
            .offset(y: TrunkLooks.railY)
    }

    /// 尾錠・組紐の留め・縄の結び（帯より上）。錠前を付けたら尾錠も同じ金属（モックの `P.lock || buckle`）
    private func buckles(_ look: TrunkLook, _ fittings: TrunkFittings) -> some View {
        ZStack(alignment: .topLeading) {
            if let s = look.straps {
                ForEach(s.x, id: \.self) { x in
                    ZStack(alignment: .top) {
                        if let metal = fittings.lockMetal {
                            TrunkPartPaintView(paint: .metal(metal))
                                .mask { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black, lineWidth: 4.5) }
                            TrunkPartPaintView(paint: .metal(metal))
                                .frame(width: 2.5, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                                .offset(y: -2)
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(TrunkPaint.metal(s.buckle, stage: stage, w: s.width + 8, h: 30), lineWidth: 4.5)
                            // 尾錠の針
                            TrunkPaint.metal(s.buckle, stage: stage, w: 2.5, h: 22)
                                .frame(width: 2.5, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                                .offset(y: -2)
                        }
                    }
                    .frame(width: s.width + 8, height: 30)
                    .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 2)
                    .offset(x: x - 4, y: 64)
                }
            }
            if let c = look.cords {
                ForEach(c.x, id: \.self) { x in
                    TrunkFillView(fill: .metal(.gilt), stage: stage, w: c.width + 10, h: 18)
                        .frame(width: c.width + 10, height: 18)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 2)
                        .offset(x: x - 5, y: 70)
                }
            }
            if let hemp = look.hemp {
                ForEach(hemp.x, id: \.self) { x in
                    LinearGradient(colors: [Color(trunk: TrunkRGBA(0x5A3418)), Color(trunk: TrunkRGBA(0x2E1808))],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: hemp.width + 12, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 2)
                        .offset(x: x - 6, y: 66)
                }
            }
        }
        .frame(width: Self.W, height: Self.H, alignment: .topLeading)
    }

    // MARK: 金具

    private func rivets(_ look: TrunkLook) -> some View {
        let dots = TrunkLooks.rivets(look)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(dots.indices), id: \.self) { i in
                let d = dots[i]
                TrunkRivetFace(slat: d.slat, metal: look.rivetMetal, model: look.model, r: d.r)
                    .frame(width: d.r * 2, height: d.r * 2)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.6), radius: 0.75, x: 0, y: 1)
                    .offset(x: d.x - d.r, y: d.y - d.r)
            }
        }
        .frame(width: Self.W, height: Self.H, alignment: .topLeading)
    }

    private func corners(_ look: TrunkLook, _ fittings: TrunkFittings) -> some View {
        let cs = look.corners.size
        return ZStack(alignment: .topLeading) {
            ForEach(TrunkCorner.allCases, id: \.self) { pos in
                TrunkCornerCap(look: look, pos: pos, paint: fittings.cornerPaint, size: cs)
                    .frame(width: cs, height: cs)
                    .clipShape(pos.shape(round: look.corners.round))
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.white.opacity(0.4)).frame(height: 1)
                            .clipShape(pos.shape(round: look.corners.round))
                    }
                    .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 1)
                    .offset(x: pos.isLeading ? -1 : Self.W - cs + 1, y: pos.isTop ? -1 : Self.H - cs + 1)
            }
        }
        .frame(width: Self.W, height: Self.H, alignment: .topLeading)
    }

    @ViewBuilder
    private func latches(_ look: TrunkLook) -> some View {
        if look.latches {
            ZStack(alignment: .topLeading) {
                ForEach([96.0, 238.0], id: \.self) { x in
                    TrunkPaint.metal(.chrome, stage: stage, w: 26, h: 34)
                        .frame(width: 26, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(alignment: .top) { Rectangle().fill(Color.white).frame(height: 1).padding(.horizontal, 3) }
                        .shadow(color: Color.black.opacity(0.5), radius: 1.5, x: 0, y: 2)
                        .offset(x: x, y: 66)
                }
            }
            .frame(width: Self.W, height: Self.H, alignment: .topLeading)
        }
    }

    private func lock(_ look: TrunkLook, _ fittings: TrunkFittings) -> some View {
        let lk = look.lock
        return ZStack {
            lockFace(look, fittings, w: lk.width, h: lk.height)
            if lk.tab {
                // 柳行李の革の留め（真鍮の輪）
                Circle().strokeBorder(Color(trunk: TrunkRGBA(0xC9A66B)), lineWidth: 2.5)
                    .frame(width: 10, height: 10)
                    .offset(y: 5)
            } else {
                UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 4)
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 7, height: 11)
                    .shadow(color: Color.white.opacity(0.25), radius: 0, x: 0, y: 1)
            }
        }
        .frame(width: lk.width, height: lk.height)
        .clipShape(TrunkLockShape(round: lk.round))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.45)).frame(height: 1)
                .clipShape(TrunkLockShape(round: lk.round))
        }
        .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 2)
        .offset(x: 180 - lk.width / 2, y: TrunkLooks.lockTop(look))
    }

    @ViewBuilder
    private func plate(_ look: TrunkLook) -> some View {
        if let plate = look.plate {
            let small = plate == .chrome
            VStack(spacing: 1) {
                Text(small ? "AIR · JOURNEY PHOTO" : "JOURNEY PHOTO")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(7 * 0.3)
                Text(ownerName.flatMap { $0.isEmpty ? nil : $0 } ?? L("持ち主の名前", "Owner\u{2019}s name"))
                    .font(.custom(JPFont.displayName, fixedSize: 11))
                    .tracking(11 * 0.12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Color(trunk: small ? TrunkRGBA(0x2A3036) : TrunkRGBA(0x3A2A12)))
            .shadow(color: small ? Color.white.opacity(0.6) : Color(trunk: TrunkRGBA(r: 255, g: 240, b: 200, a: 0.6)),
                    radius: 0, x: 0, y: 1)
            .padding(.horizontal, 6)
            .frame(width: small ? 88 : 112, height: small ? 32 : 40)
            .background(TrunkPaint.metal(small ? .chrome : .brass, stage: stage, w: small ? 88 : 112, h: small ? 32 : 40))
            .clipShape(RoundedRectangle(cornerRadius: small ? 4 : 5))
            .shadow(color: Color.black.opacity(small ? 0.5 : 0.6), radius: 1.5, x: 0, y: small ? 1 : 2)
            .offset(x: small ? 136 : 124, y: small ? 214 : 204)
        }
    }

    // MARK: 仕上げ

    @ViewBuilder
    private func scratches(_ look: TrunkLook) -> some View {
        if look.scratch > 0 {
            let s = look.scratch
            ZStack(alignment: .topLeading) {
                TrunkStripes(angle: 118, period: 31, bands: [(13, 13.6, TrunkRGBA(r: 255, g: 255, b: 255, a: 0.4 * s))])
                TrunkStripes(angle: 64, period: 47, bands: [(23, 23.5, TrunkRGBA(r: 30, g: 35, b: 40, a: 0.22 * s))])
                TrunkSpot(color: TrunkRGBA(r: 0, g: 0, b: 0, a: 0.18 * s), x: Self.W * 0.70, y: Self.H * 0.60, rx: 26, ry: 14)
            }
            .frame(width: Self.W, height: Self.H, alignment: .topLeading)
        }
    }

    private func gloss(_ look: TrunkLook) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(look.gloss.indices), id: \.self) { i in
                switch look.gloss[i] {
                case .linear(let g):
                    TrunkPaint.linear(g, w: Self.W, h: Self.H).frame(width: Self.W, height: Self.H)
                case let .spot(color, center, radius):
                    TrunkSpot(color: color, x: center.x * Self.W, y: center.y * Self.H,
                              rx: radius.x * Self.W, ry: radius.y * Self.H)
                }
            }
        }
        .frame(width: Self.W, height: Self.H, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// 縁の陰（モックの `inset` の影4つ: 上の細い光・下と左右の暗がり）
    private var shade: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [Gradient.Stop(color: Color.clear, location: 0),
                                   Gradient.Stop(color: Color.clear, location: 1 - 42 / Self.H),
                                   Gradient.Stop(color: Color.black.opacity(0.5), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [Gradient.Stop(color: Color.black.opacity(0.25), location: 0),
                                   Gradient.Stop(color: Color.clear, location: 38 / Self.W)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [Gradient.Stop(color: Color.clear, location: 1 - 38 / Self.W),
                                   Gradient.Stop(color: Color.black.opacity(0.3), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            Rectangle().fill(Color.white.opacity(0.14)).frame(width: Self.W, height: 2)
        }
        .frame(width: Self.W, height: Self.H, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: 手荷物タグ

    private func tags(_ look: TrunkLook) -> some View {
        // 行き先と日付はこの人のラベルから（`TrunkLooks.tags(stuck:posts:)`）。地名が足りなければ枚数も減る
        let list = TrunkLooks.tags(stuck: TrunkLooks.tagSource(stuck: stuck, tagsFrom: tagsFrom), posts: posts)
        let st = stage
        return ZStack(alignment: .topLeading) {
            ForEach(Array(list.indices), id: \.self) { i in
                let t = list[i]
                // 吊るす紐
                Rectangle().fill(Color(trunk: TrunkRGBA(0x2A2A2A)))
                    .frame(width: 3, height: 14)
                    .rotationEffect(.degrees(t.rot), anchor: .top)
                    .offset(x: t.x + 22, y: 2)
                TrunkTagView(tag: t, stage: st)
                    .rotationEffect(.degrees(t.rot), anchor: UnitPoint(x: 0.5, y: -10.0 / 68))
                    .offset(x: t.x, y: 12)
            }
        }
    }
}

/// 胴の地・目・しみ・型ごとの古び（正面の胴と、回したときの面が同じ描き方を使う・2026-10-18）。
/// CSS の背景と同じく、置く面の大きさ（`w`×`h`）に対して描く
struct TrunkSkin: View {
    let look: TrunkLook
    let w: Double
    let h: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            surface(look.surface)
            texture(look.texture)
            stains
            modelWear
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    @ViewBuilder
    private func surface(_ surface: TrunkSurface) -> some View {
        switch surface {
        case let .radial(inner, outer, center, radius, outerStop):
            ZStack(alignment: .topLeading) {
                Color(trunk: outer)
                EllipticalGradient(stops: [Gradient.Stop(color: Color(trunk: inner), location: 0),
                                           Gradient.Stop(color: Color(trunk: outer), location: outerStop),
                                           Gradient.Stop(color: Color(trunk: outer), location: 1)],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: radius.x * w * 2, height: radius.y * h * 2)
                    .position(x: center.x * w, y: center.y * h)
            }
            .frame(width: w, height: h)
        case let .canvasStripes(base, thin, band):
            ZStack {
                Color(trunk: base)
                TrunkStripes(angle: 90, period: 18, bands: [(8, 9, thin), (16, 18, band)])
            }
            .frame(width: w, height: h)
        case .corrugated:
            ZStack {
                Color(trunk: TrunkRGBA(0xDADEE2))
                TrunkStripes(angle: 180, period: 9, bands: [(7, 8, TrunkRGBA(0xA9AFB5)), (8, 9, TrunkRGBA(0xF1F3F5))])
            }
            .frame(width: w, height: h)
        case let .wicker(a, b, c):
            ZStack {
                Color(trunk: a)
                TrunkStripes(angle: 0, period: 9, bands: [(4, 5, b), (5, 9, c)])
                TrunkStripes(angle: 90, period: 6, bands: [(0, 1, TrunkRGBA(r: 60, g: 35, b: 10, a: 0.22))])
            }
            .frame(width: w, height: h)
        case let .planks(top, bottom):
            ZStack {
                LinearGradient(colors: [Color(trunk: top), Color(trunk: bottom)], startPoint: .top, endPoint: .bottom)
                TrunkStripes(angle: 91, period: 17, bands: [(0, 2, TrunkRGBA(r: 0, g: 0, b: 0, a: 0.10)),
                                                             (9, 10, TrunkRGBA(r: 255, g: 220, b: 180, a: 0.05))])
                TrunkStripes(angle: 180, period: 44, bands: [(0, 1.5, TrunkRGBA(r: 0, g: 0, b: 0, a: 0.45))])
            }
            .frame(width: w, height: h)
        case .polished:
            TrunkPaint.linear(TrunkGradient(angle: 100, stops: [
                TrunkStop(color: TrunkRGBA(0x8E969E), location: 0), TrunkStop(color: TrunkRGBA(0xE9EDF0), location: 0.20),
                TrunkStop(color: TrunkRGBA(0xB7BEC5), location: 0.38), TrunkStop(color: TrunkRGBA(0xF7F9FA), location: 0.52),
                TrunkStop(color: TrunkRGBA(0x9AA2AA), location: 0.72), TrunkStop(color: TrunkRGBA(0xD4D9DD), location: 1),
            ]), w: w, h: h)
            .frame(width: w, height: h)
        }
    }

    @ViewBuilder
    private func texture(_ texture: TrunkTexture) -> some View {
        switch texture {
        case .none:
            EmptyView()
        case .grain:
            TrunkGrain.leather.frame(width: w, height: h)
        case .weave:
            ZStack {
                TrunkStripes(angle: 0, period: 3, bands: [(0, 1, TrunkRGBA(r: 0, g: 0, b: 0, a: 0.07))])
                TrunkStripes(angle: 90, period: 3, bands: [(0, 1, TrunkRGBA(r: 255, g: 255, b: 255, a: 0.05))])
            }
            .frame(width: w, height: h)
        case .sheen:
            TrunkPaint.linear(TrunkGradient(angle: 115, stops: [
                TrunkStop(color: TrunkRGBA(r: 255, g: 255, b: 255, a: 0), location: 0.30),
                TrunkStop(color: TrunkRGBA(r: 255, g: 255, b: 255, a: 0.45), location: 0.42),
                TrunkStop(color: TrunkRGBA(r: 255, g: 255, b: 255, a: 0), location: 0.54),
            ]), w: w, h: h)
            .frame(width: w, height: h)
        case .seams:
            TrunkStripes(angle: 180, period: 90, bands: [(89, 90, TrunkRGBA(r: 40, g: 50, b: 60, a: 0.45))])
                .frame(width: w, height: h)
        }
    }

    /// 角の擦れ（明るいしみ）と茶色いしみ（帆布）
    private var stains: some View {
        let st = look.stage
        let light = TrunkRGBA(r: 255, g: 240, b: 215, a: 1)
        let dark = TrunkRGBA(r: 80, g: 50, b: 20, a: 1)
        return ZStack(alignment: .topLeading) {
            TrunkSpot(color: light.alpha(look.scuff * st * 1.4), x: w * 0.22, y: h * 0.86, rx: 50, ry: 26)
            TrunkSpot(color: light.alpha(look.scuff * st * 1.2), x: w * 0.80, y: h * 0.10, rx: 70, ry: 18)
            TrunkSpot(color: dark.alpha(look.stain * st), x: w * 0.62, y: h * 0.64, rx: 40, ry: 30)
            TrunkSpot(color: dark.alpha(look.stain * st * 0.8), x: w * 0.14, y: h * 0.40, rx: 30, ry: 22)
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }

    /// 型ごとの古び方（モック MaterialAging・`modelWear`）
    @ViewBuilder
    private var modelWear: some View {
        let st = look.stage
        ZStack(alignment: .topLeading) {
            switch look.model {
            case .urushi:
                // 黒が透けて、角から下塗りの朱が出てくる
                TrunkSpot(color: TrunkRGBA(r: 196, g: 58, b: 36, a: 0.55 * st), x: w * 0.06, y: h * 0.08, rx: w * 0.34, ry: h * 0.22)
                TrunkSpot(color: TrunkRGBA(r: 196, g: 58, b: 36, a: 0.5 * st), x: w * 0.94, y: h * 0.92, rx: w * 0.30, ry: h * 0.20)
                TrunkSpot(color: TrunkRGBA(r: 170, g: 46, b: 30, a: 0.32 * st), x: w * 0.50, y: h * 0.34, rx: w * 0.22, ry: h * 0.14)
                TrunkSpot(color: TrunkRGBA(r: 196, g: 58, b: 36, a: 0.35 * st), x: w * 0.98, y: h * 0.30, rx: w * 0.18, ry: h * 0.30)
            case .kori:
                // 縁が濃く焼け、編み目に明るい筋
                EllipticalGradient(stops: [Gradient.Stop(color: Color.clear, location: 0),
                                           Gradient.Stop(color: Color.clear, location: 0.55),
                                           Gradient.Stop(color: Color(trunk: TrunkRGBA(r: 90, g: 50, b: 18, a: 0.38 * st)), location: 1)],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: w * 1.2, height: h)
                    .position(x: w / 2, y: h / 2)
                TrunkStripes(angle: 90, period: 83, bands: [(37, 39, TrunkRGBA(r: 255, g: 240, b: 210, a: 0.18 * st))])
            case .sleeper:
                TrunkPaint.linear(TrunkGradient(angle: 165, stops: [
                    TrunkStop(color: TrunkRGBA(r: 255, g: 215, b: 200, a: 0.12 * st), location: 0),
                    TrunkStop(color: TrunkRGBA(r: 255, g: 215, b: 200, a: 0), location: 0.40),
                ]), w: w, h: h)
                TrunkSpot(color: TrunkRGBA(r: 255, g: 220, b: 200, a: 0.12 * st), x: w * 0.5, y: h * 0.92, rx: w * 0.30, ry: h * 0.16)
            case .captain:
                TrunkStripes(angle: 180, period: 44, bands: [(0, 20, TrunkRGBA(r: 255, g: 235, b: 210, a: 0.10 * st))])
                TrunkSpot(color: TrunkRGBA(r: 200, g: 200, b: 190, a: 0.18 * st), x: w * 0.20, y: h * 0.80, rx: w * 0.40, ry: h * 0.30)
            case .starchart:
                TrunkSpot(color: TrunkRGBA(r: 201, g: 166, b: 107, a: 0.10 * st), x: w * 0.5, y: h * 0.5, rx: w * 0.5, ry: h * 0.4)
            case .steamer:
                TrunkSpot(color: TrunkRGBA(r: 255, g: 240, b: 215, a: 0.12 * st), x: w * 0.30, y: h * 0.70, rx: w * 0.30, ry: h * 0.20)
                TrunkSpot(color: TrunkRGBA(r: 60, g: 40, b: 20, a: 0.25 * st), x: w * 0.80, y: h * 0.30, rx: w * 0.26, ry: h * 0.18)
            case .canvas:
                TrunkPaint.linear(TrunkGradient(angle: 180, stops: [
                    TrunkStop(color: TrunkRGBA(r: 255, g: 245, b: 225, a: 0.16 * st), location: 0),
                    TrunkStop(color: TrunkRGBA(r: 255, g: 245, b: 225, a: 0), location: 0.5),
                ]), w: w, h: h)
            case .leather:
                TrunkSpot(color: TrunkRGBA(r: 255, g: 225, b: 190, a: 0.12 * st), x: w * 0.5, y: 0, rx: w * 0.40, ry: h * 0.30)
            case .aluminum, .clipper:
                EmptyView()
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// 縁の擦れ（革・布・木の型だけ・古び方 0 では描かない）。正面と回したときの面が同じ部品を使う。
/// 板 Trunk の `edgeWear`: 内側の明るい縁と内へにじむ光・斜めの擦れ筋。正面はさらに角の擦れと横のしわ
struct TrunkEdgeWear: View {
    let look: TrunkLook
    let w: Double
    let h: Double
    let corner: Double
    /// 正面（胴）か。正面は縁が太く、角の擦れと横のしわが加わる
    var front = false

    var body: some View {
        if let wear = TrunkFaces.edgeWear(look.model, stage: look.stage, front: front) {
            let st = look.stage
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(Color(trunk: TrunkRGBA(r: 255, g: 226, b: 186, a: 0.10 * st)), lineWidth: wear.width)
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(Color(trunk: TrunkRGBA(r: 255, g: 222, b: 180, a: wear.alpha)), lineWidth: wear.blur / 2)
                    .blur(radius: wear.blur / 4)
                if front {
                    TrunkSpot(color: TrunkRGBA(r: 255, g: 232, b: 200, a: 0.22 * st), x: w * 0.12, y: h * 0.96, rx: 60, ry: 22)
                    TrunkSpot(color: TrunkRGBA(r: 255, g: 232, b: 200, a: 0.20 * st), x: w * 0.88, y: h * 0.04, rx: 70, ry: 20)
                    TrunkSpot(color: TrunkRGBA(r: 255, g: 232, b: 200, a: 0.18 * st), x: w * 0.5, y: h, rx: 44, ry: 16)
                }
                TrunkStripes(angle: 118, period: 61,
                             bands: [(23, 23.6, TrunkRGBA(r: 255, g: 235, b: 205, a: (front ? 0.14 : 0.12) * st))])
                if front {
                    TrunkStripes(angle: 178, period: 83, bands: [(37, 38, TrunkRGBA(r: 30, g: 15, b: 5, a: 0.22 * st)),
                                                                  (38, 39, TrunkRGBA(r: 255, g: 230, b: 200, a: 0.10 * st))])
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .allowsHitTesting(false)
        }
    }
}

/// 革のベルト・組紐・麻の縄（縦に通す帯）。正面と、回り込んだ上・底・背面が同じ描き方を使う（2026-10-18）
struct TrunkBandStrips: View {
    let look: TrunkLook
    /// 帯の長さ（面の高さ）
    let height: Double
    /// ベルトの穴を描くか（正面だけ）
    var holes = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let s = look.straps {
                ForEach(s.x, id: \.self) { x in
                    ZStack(alignment: .topLeading) {
                        LinearGradient(stops: [Gradient.Stop(color: Color.black.opacity(0.4), location: 0),
                                               Gradient.Stop(color: Color(trunk: s.color), location: 0.18),
                                               Gradient.Stop(color: Color(trunk: s.color), location: 0.82),
                                               Gradient.Stop(color: Color.black.opacity(0.4), location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                        TrunkGrain.leather
                        // 縫い目（左右 3pt の内側の破線）
                        Path { p in
                            p.move(to: CGPoint(x: 3, y: 0)); p.addLine(to: CGPoint(x: 3, y: height))
                            p.move(to: CGPoint(x: s.width - 3, y: 0)); p.addLine(to: CGPoint(x: s.width - 3, y: height))
                        }
                        .stroke(Color(trunk: s.edge), style: StrokeStyle(lineWidth: 1.2, dash: [3.6, 2.4]))
                        // ベルトの穴（正面だけ。回り込んだ面には無い）
                        ForEach(holes ? [104.0, 116, 128] : [], id: \.self) { y in
                            Circle().fill(Color.black.opacity(0.75))
                                .frame(width: 4, height: 4)
                                .offset(x: s.width / 2 - 2, y: y)
                        }
                    }
                    .frame(width: s.width, height: height)
                    .overlay(Rectangle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.35), radius: 3, x: 3, y: 0)
                    .offset(x: x)
                }
            }
            if let c = look.cords {
                ForEach(c.x, id: \.self) { x in
                    ZStack {
                        Color(trunk: TrunkRGBA.mix(0xB3261E, 0xC8503A, look.stage))
                        TrunkStripes(angle: 40, period: 7, bands: [(3, 4, TrunkRGBA(0x6E140F)),
                                                                    (4, 7, TrunkRGBA.mix(0xC8352A, 0xD06048, look.stage))])
                    }
                    .frame(width: c.width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: Color.black.opacity(0.5), radius: 2.5, x: 2, y: 0)
                    .offset(x: x)
                }
            }
            if let hemp = look.hemp {
                ForEach(hemp.x, id: \.self) { x in
                    ZStack {
                        Color(trunk: TrunkRGBA.mix(0xE2D2A8, 0xCDBB8E, look.stage))
                        TrunkStripes(angle: 62, period: 7, bands: [(3, 4.5, TrunkRGBA(0xA8955F)),
                                                                    (4.5, 7, TrunkRGBA.mix(0xD3C094, 0xBFAC7E, look.stage))])
                    }
                    .frame(width: hemp.width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 2, y: 0)
                    .offset(x: x)
                }
            }
        }
        .frame(width: TrunkLooks.bodyWidth, height: height, alignment: .topLeading)
    }
}

/// 鋲の頭（桟の真鍮の鋲・飛行艇の鋲・アルミの鋲）。正面と回したときの面で同じ
struct TrunkRivetFace: View {
    let slat: Bool
    let metal: TrunkMetal?
    let model: TrunkModel
    let r: Double

    var body: some View {
        if slat {
            RadialGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(0xF6E3B4)), location: 0),
                                   Gradient.Stop(color: Color(trunk: TrunkRGBA(0x9C7A42)), location: 0.7),
                                   Gradient.Stop(color: Color(trunk: TrunkRGBA(0x9C7A42)), location: 1)],
                           center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: r * 2)
        } else if model == .clipper {
            RadialGradient(stops: [Gradient.Stop(color: Color.white, location: 0),
                                   Gradient.Stop(color: Color(trunk: TrunkRGBA(0x8A9198)), location: 0.7),
                                   Gradient.Stop(color: Color(trunk: TrunkRGBA(0x8A9198)), location: 1)],
                           center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: r * 2)
        } else {
            // アルミのケースの鋲（新品のクローム）
            TrunkPaint.metal(metal ?? .chrome, stage: 0, w: r * 2, h: r * 2)
        }
    }
}

/// 角金具の面（付けた角金具・船長の箱の青緑のくすみ・角の鋲）。正面と、3つの面にまたがる回したときの面で同じ
struct TrunkCornerCap: View {
    let look: TrunkLook
    let pos: TrunkCorner
    let paint: TrunkPartPaint?
    let size: Double

    var body: some View {
        let rp = pos.rivetPoint
        return ZStack(alignment: .topLeading) {
            if let paint {
                // 付けた角金具（モックの `P.corner`）
                TrunkPartPaintView(paint: paint)
            } else {
                TrunkFillView(fill: look.corners.fill, stage: look.stage, w: size, h: size)
            }
            if look.model == .captain && look.stage > 0 {
                // 真鍮の角が青緑にくすむ（船長の箱）
                TrunkSpot(color: TrunkRGBA(r: 86, g: 150, b: 120, a: 0.55 * look.stage), x: rp.x * size, y: rp.y * size,
                          rx: size * 0.6, ry: size * 0.6, fadeEnd: 0.7)
            }
            if look.corners.rivet {
                // 角の鋲（明るい頭と暗い縁）
                RadialGradient(stops: [Gradient.Stop(color: Color(trunk: TrunkRGBA(r: 255, g: 250, b: 235, a: 0.9)), location: 0),
                                       Gradient.Stop(color: Color(trunk: TrunkRGBA(r: 255, g: 250, b: 235, a: 0.9)), location: 1.2 / 3.2),
                                       Gradient.Stop(color: Color(trunk: TrunkRGBA(r: 60, g: 40, b: 15, a: 0.9)), location: 1.6 / 3.2),
                                       Gradient.Stop(color: Color(trunk: TrunkRGBA(r: 60, g: 40, b: 15, a: 0.9)), location: 2.8 / 3.2),
                                       Gradient.Stop(color: Color.clear, location: 1)],
                               center: .center, startRadius: 0, endRadius: 3.2)
                    .frame(width: 6.4, height: 6.4)
                    .position(x: rp.x * size, y: rp.y * size)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}

/// 錠前と同じ金属の面（錠前・持ち手の付け根・蝶番。付けた錠前があればその金属・モックの `P.lock`）
struct TrunkHardwareFace: View {
    let look: TrunkLook
    let fittings: TrunkFittings
    let w: Double
    let h: Double

    var body: some View {
        if let metal = fittings.lockMetal {
            TrunkPartPaintView(paint: .metal(metal))
        } else {
            TrunkFillView(fill: look.lock.fill, stage: look.stage, w: w, h: h)
        }
    }
}

/// 手荷物タグ1枚（50×68）
private struct TrunkTagView: View {
    let tag: TrunkLooks.Tag
    let stage: Double

    var body: some View {
        let fg = Color(trunk: TrunkLooks.tagColor(tag.fg, stage: stage))
        VStack(spacing: 0) {
            Circle().fill(Color(trunk: TrunkRGBA(0x0B0B0B)))
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color(trunk: TrunkLooks.tagColor(TrunkRGBA(0x9C8150), stage: stage)), lineWidth: 2)
                    .padding(-2))
                .padding(.top, 5)
                .padding(.bottom, 4)
            // 地名は人ごとに長さが違うので、タグの幅に収まるよう縮める（省くのは `TrunkLooks.tagCode`）
            Text(tag.code)
                .font(.system(size: 9, weight: .heavy).monospacedDigit())
                .tracking(9 * 0.06)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: 44)
            // 縞の符号（1・1・2・1 の繰り返し）
            TrunkStripes(angle: 90, period: 5, bands: [(0, 1, TrunkLooks.tagColor(tag.fg, stage: stage)),
                                                        (2, 4, TrunkLooks.tagColor(tag.fg, stage: stage))])
                .frame(height: 6)
                .opacity(0.8)
                .padding(.horizontal, 6)
                .padding(.top, 3)
            if !tag.printedDay.isEmpty {
                Text(tag.printedDay)
                    .font(.system(size: 6).monospacedDigit())
                    .tracking(6 * 0.06)
                    .opacity(0.8)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(fg)
        .frame(width: 50, height: 68)
        .background {
            ZStack {
                Color(trunk: TrunkLooks.tagColor(tag.bg, stage: stage))
                TrunkGrain(dots: [(TrunkRGBA(r: 0, g: 0, b: 0, a: 0.06), 3, 0.75, 0)])
            }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 7, bottomTrailingRadius: 7, topTrailingRadius: 5))
        .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 4)
    }
}

/// トランクの角の4か所（角の丸みの向きと鋲の位置）
enum TrunkCorner: CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var isTop: Bool { self == .topLeading || self == .topTrailing }
    var isLeading: Bool { self == .topLeading || self == .bottomLeading }

    /// 鋲の位置（角の札の中の割合・モックの `rp`）
    var rivetPoint: (x: Double, y: Double) {
        switch self {
        case .topLeading: return (0.3, 0.3)
        case .topTrailing: return (0.7, 0.3)
        case .bottomLeading: return (0.3, 0.7)
        case .bottomTrailing: return (0.7, 0.7)
        }
    }

    /// 回したときの面の角金具の形（板 Trunk の `capCss`: 外の角 10・内の角 6、アルミは 10 の対）
    func faceShape(round: Bool) -> UnevenRoundedRectangle {
        let big = 10.0, small = round ? 10.0 : 6.0
        let r: (tl: Double, tr: Double, br: Double, bl: Double)
        switch self {
        case .topLeading: r = (big, 0, small, 0)
        case .topTrailing: r = (0, big, 0, small)
        case .bottomLeading: r = (0, small, 0, big)
        case .bottomTrailing: r = (small, 0, big, 0)
        }
        return UnevenRoundedRectangle(topLeadingRadius: r.tl, bottomLeadingRadius: r.bl,
                                      bottomTrailingRadius: r.br, topTrailingRadius: r.tr)
    }

    /// 角の札の形（CSS の border-radius の4つ: 左上・右上・右下・左下）
    func shape(round: Bool) -> UnevenRoundedRectangle {
        let r: (tl: Double, tr: Double, br: Double, bl: Double)
        switch (self, round) {
        case (.topLeading, true), (.bottomTrailing, true): r = (14, 0, 14, 0)
        case (.topTrailing, true), (.bottomLeading, true): r = (0, 14, 0, 14)
        case (.topLeading, false): r = (14, 0, 8, 0)
        case (.topTrailing, false): r = (0, 14, 0, 8)
        case (.bottomLeading, false): r = (0, 8, 0, 14)
        case (.bottomTrailing, false): r = (8, 0, 14, 0)
        }
        return UnevenRoundedRectangle(topLeadingRadius: r.tl, bottomLeadingRadius: r.bl,
                                      bottomTrailingRadius: r.br, topTrailingRadius: r.tr)
    }
}

/// 持ち手（上の角が丸い U の字・太さ 10。付けた持ち手の部品は部品の太さ・`TrunkFittings.handlePaint`）
struct TrunkHandleShape: Shape {
    var thickness: Double = 10

    func path(in rect: CGRect) -> Path {
        let w = Double(rect.width), h = Double(rect.height), t = thickness
        let outer = 22.0, inner = max(0, outer - t), k = 0.5522847498
        let segments: [SVGPath.Segment] = [
            .move(SVGPath.Point(x: 0, y: h)),
            .line(SVGPath.Point(x: 0, y: outer)),
            .cubic(c1: SVGPath.Point(x: 0, y: outer * (1 - k)), c2: SVGPath.Point(x: outer * (1 - k), y: 0), to: SVGPath.Point(x: outer, y: 0)),
            .line(SVGPath.Point(x: w - outer, y: 0)),
            .cubic(c1: SVGPath.Point(x: w - outer * (1 - k), y: 0), c2: SVGPath.Point(x: w, y: outer * (1 - k)), to: SVGPath.Point(x: w, y: outer)),
            .line(SVGPath.Point(x: w, y: h)),
            .line(SVGPath.Point(x: w - t, y: h)),
            .line(SVGPath.Point(x: w - t, y: t + inner)),
            .cubic(c1: SVGPath.Point(x: w - t, y: t + inner * (1 - k)), c2: SVGPath.Point(x: w - t - inner * (1 - k), y: t),
                   to: SVGPath.Point(x: w - t - inner, y: t)),
            .line(SVGPath.Point(x: t + inner, y: t)),
            .cubic(c1: SVGPath.Point(x: t + inner * (1 - k), y: t), c2: SVGPath.Point(x: t, y: t + inner * (1 - k)),
                   to: SVGPath.Point(x: t, y: t + inner)),
            .line(SVGPath.Point(x: t, y: h)),
            .close,
        ]
        return TrunkPaint.path(SVGPath.translate(segments, dx: Double(rect.minX), dy: Double(rect.minY)))
    }
}

/// 錠前の形（角丸 5 か、丸）
struct TrunkLockShape: Shape {
    let round: Bool

    func path(in rect: CGRect) -> Path {
        let x = Double(rect.minX), y = Double(rect.minY), w = Double(rect.width), h = Double(rect.height)
        if round { return TrunkPaint.path(SVGPath.ellipse(cx: x + w / 2, cy: y + h / 2, rx: w / 2, ry: h / 2)) }
        return TrunkPaint.path(SVGPath.rect(x: x, y: y, w: w, h: h, r: 5))
    }
}

/// トランクを決まった幅に縮めて置く（モックの 360×300 を `width` に）
struct TrunkFigure: View {
    let model: TrunkModel
    let posts: Int
    var stuck: [TrunkLabel] = []
    var ownerName: String?
    var parts: TrunkEquipped = .none
    /// 動かしてよれたラベル（`TrunkWrinkles`・どの画面のトランクも同じ見た目に）
    var wrinkles: [String: Double] = [:]
    let width: Double
    /// 手荷物タグを作るラベル（`TrunkBoxView.tagsFrom`）
    var tagsFrom: [TrunkLabel]?

    var body: some View {
        let k = width / TrunkLooks.canvasWidth
        TrunkBoxView(model: model, posts: posts, stuck: stuck, ownerName: ownerName, parts: parts, wrinkles: wrinkles,
                     tagsFrom: tagsFrom)
            .scaleEffect(k, anchor: .topLeading)
            .frame(width: width, height: TrunkLooks.canvasHeight * k, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TrunkText.accessibilityLabel(model: model,
                                                             labels: TrunkPlacement.layout(stuck, stage: 0).count,
                                                             tags: TrunkLooks.tags(stuck: TrunkLooks.tagSource(stuck: stuck, tagsFrom: tagsFrom),
                                                                                   posts: posts).count, equipped: parts))
            .accessibilityAddTraits(.isImage)
    }
}

/// 置き場の幅に合わせて縮めるトランク（小さい画面で横にはみ出さない）。`maxWidth` より大きくはしない
struct TrunkFigureFit: View {
    let model: TrunkModel
    let posts: Int
    var stuck: [TrunkLabel] = []
    var ownerName: String?
    var parts: TrunkEquipped = .none
    var wrinkles: [String: Double] = [:]
    let maxWidth: Double
    /// 手荷物タグを作るラベル（`TrunkBoxView.tagsFrom`）
    var tagsFrom: [TrunkLabel]?

    var body: some View {
        GeometryReader { geo in
            TrunkFigure(model: model, posts: posts, stuck: stuck, ownerName: ownerName, parts: parts, wrinkles: wrinkles,
                        width: min(maxWidth, Double(geo.size.width)), tagsFrom: tagsFrom)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(TrunkLooks.canvasWidth / TrunkLooks.canvasHeight, contentMode: .fit)
        .frame(maxWidth: maxWidth)
    }
}
