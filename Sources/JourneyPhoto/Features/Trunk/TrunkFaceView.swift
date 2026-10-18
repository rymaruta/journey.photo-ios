import SwiftUI

/// 回したときの面（板「旅のトランク」の TrunkFaces・Trunk.dc.html の `face`・2026-10-18 owner 承認）。
///
/// 左右の側面（86×268）・上の面と底（360×86）・背面（360×268）を、**正面と同じ素材・縫い目・古び方**で描く。
/// 重ね方は板の z の順: 地・目・しみ・古び（`TrunkSkin`）→ 縁の擦れ → 絵 → 縁の革・縫い目 → 桟 → 帯 →
/// 合わせ目 → ベルト → 滑り材・鋲・足・蝶番 → 持ち手 → 角金具 → 型押し → 擦り傷・艶 → 縁の陰。
/// 数（どこに何があるか）は `TrunkFaces`。SceneKit の箱の各面に、1枚の絵にして貼る（`TrunkTextures`）
struct TrunkFaceView: View {
    let model: TrunkModel
    let posts: Int
    let side: TrunkFaceSide
    var parts: TrunkEquipped = .none
    /// 吊るしているラベルの手荷物タグ（上の面に持ち手からの紐を渡す・#305）
    var hangTags: [TrunkLooks.Tag] = []

    private var look: TrunkLook { TrunkLooks.look(model, stage: TrunkAging.stage(posts: posts)) }

    var body: some View {
        let look = look
        let fittings = TrunkFittings(parts)
        let size = TrunkFaces.size(side)
        ZStack(alignment: .topLeading) {
            // 地と絵（z 0〜1）
            Group {
                TrunkSkin(look: look, w: size.w, h: size.h)
                edgeWear(look, size)
                art(size)
                binding(look, size)
            }
            // 桟・帯・合わせ目・ベルト（z 1〜3）
            Group {
                bands(look, size)
                rail(look, size)
                seam(look, size)
                if TrunkFaces.showsStraps(side) {
                    TrunkBandStrips(look: look, height: size.h)
                }
            }
            // 金具・持ち手・仕上げ（z 4〜9）
            Group {
                bottomFittings(look, fittings)
                rivets(look, size)
                if side == .top {
                    // 吊るす物の紐（持ち手の下から正面の辺へ・#305）。持ち手より下に描き、付け根を持ち手で隠す
                    TrunkHangCords(cords: TrunkFaces.topCords(tags: hangTags, fittings: fittings))
                        .frame(width: size.w, height: size.h)
                }
                handle(look, fittings)
                corners(look, fittings, size)
                mark(look)
                finish(look, size)
            }
        }
        .frame(width: size.w, height: size.h, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: TrunkFaces.faceCorner))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrunkFaces.accessibilityLabel(model: model, side: side))
        .accessibilityAddTraits(.isImage)
    }

    // MARK: 縁の擦れ（革・布・木）

    private func edgeWear(_ look: TrunkLook, _ size: (w: Double, h: Double)) -> some View {
        TrunkEdgeWear(look: look, w: size.w, h: size.h, corner: TrunkFaces.faceCorner)
    }

    // MARK: 絵（漆の波・星図の星・背面の金蒔絵と星座）

    @ViewBuilder
    private func art(_ size: (w: Double, h: Double)) -> some View {
        if let art = TrunkFaces.sideArt(model, side: side) {
            switch art {
            case .waves(let tile):
                // 金の波の帯（`repeating-radial-gradient(circle at 50% 130%, … 14px 15.2px …)` を升ごとに）
                Canvas { ctx, canvas in
                    let h = 40.0, top = Double(canvas.height) - h
                    var x = 0.0
                    while x < Double(canvas.width) {
                        var c = ctx
                        c.clip(to: Path { $0.addRect(CGRect(x: x, y: top, width: tile, height: h)) })
                        let cx = x + tile / 2, cy = top + h * 1.3
                        var r = 14.6
                        while r < h * 1.6 {
                            c.stroke(Path { $0.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)) },
                                     with: .color(Color(trunk: TrunkRGBA(r: 217, g: 181, b: 102, a: 0.55))), lineWidth: 1.2)
                            r += 22
                        }
                        x += tile
                    }
                }
                .frame(width: size.w, height: size.h)
                .allowsHitTesting(false)
            case .stars:
                // 金の星が散る（`radial-gradient(#E3C98F 1.4px, transparent 2px) 12px 18px / 52px 64px` ほか）
                TrunkPartPaintView(paint: .layers([
                    .dots(TrunkPartDots(color: TrunkRGBA(0xE3C98F), tile: 52, cx: 12 + 26, cy: 18 + 26, inner: 1.4, outer: 2)),
                    .dots(TrunkPartDots(color: TrunkRGBA(0xE3C98F), tile: 64, cx: 36 + 32, cy: 50 + 32, inner: 1, outer: 1.6)),
                ]))
                .frame(width: size.w, height: size.h)
                .opacity(0.85)
            }
        }
        if side == .back, let art = TrunkFaces.backArt(model) {
            TrunkArtCanvas(strokes: TrunkArtwork.backStrokes(art), viewBox: (size.w, size.h), fit: false)
                .frame(width: size.w, height: size.h)
        }
    }

    // MARK: 縁の革・縫い目

    @ViewBuilder
    private func binding(_ look: TrunkLook, _ size: (w: Double, h: Double)) -> some View {
        let bw = TrunkFaces.bindingWidth(look)
        if bw > 0 {
            ZStack {
                RoundedRectangle(cornerRadius: TrunkFaces.faceCorner).strokeBorder(Color(trunk: look.binding.color), lineWidth: bw)
                RoundedRectangle(cornerRadius: TrunkFaces.faceCorner).strokeBorder(Color.black.opacity(0.4), lineWidth: 1)
                if look.binding.gold {
                    // 金の押し線（縁の内側 1pt あけて 1pt）
                    RoundedRectangle(cornerRadius: max(2, TrunkFaces.faceCorner - bw - 1))
                        .strokeBorder(Color(trunk: TrunkRGBA(0xC9A66B)), lineWidth: 1)
                        .padding(bw + 1)
                }
            }
            .frame(width: size.w, height: size.h)
        }
        if let stitch = look.stitch {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(trunk: stitch), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                .padding(TrunkFaces.stitchInset(look))
                .frame(width: size.w, height: size.h)
        }
    }

    // MARK: 桟・帯・合わせ目

    private func bands(_ look: TrunkLook, _ size: (w: Double, h: Double)) -> some View {
        let list = TrunkFaces.bands(side, look: look)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(list.indices), id: \.self) { i in
                let band = list[i]
                let fill = band.brass ? TrunkFill.metal(.brass) : (look.barFill ?? .metal(.brass))
                let w = band.horizontal ? size.w : band.size
                let h = band.horizontal ? band.size : size.h
                TrunkFillView(fill: fill, stage: look.stage, w: w, h: h)
                    .frame(width: w, height: h)
                    .overlay(Rectangle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.35), radius: 2, x: band.horizontal ? 0 : 2, y: band.horizontal ? 2 : 0)
                    .offset(x: band.horizontal ? 0 : band.position, y: band.horizontal ? band.position : 0)
            }
        }
        .frame(width: size.w, height: size.h, alignment: .topLeading)
    }

    @ViewBuilder
    private func rail(_ look: TrunkLook, _ size: (w: Double, h: Double)) -> some View {
        if TrunkFaces.showsRail(side) {
            TrunkFillView(fill: look.rail.fill, stage: look.stage, w: size.w, h: look.rail.height)
                .frame(width: size.w, height: look.rail.height)
                .shadow(color: Color.black.opacity(0.5), radius: 1.5, x: 0, y: 2)
                .offset(y: TrunkLooks.railY)
        }
    }

    /// ふたの合わせ目（金属の型は帯と同じ金属の縁・ほかは暗い線と細い光）
    @ViewBuilder
    private func seam(_ look: TrunkLook, _ size: (w: Double, h: Double)) -> some View {
        if let seam = TrunkFaces.seam(side) {
            let t = TrunkFaces.seamThickness(model)
            let w = seam.horizontal ? size.w : t
            let h = seam.horizontal ? t : size.h
            Group {
                if TrunkFaces.seamIsMetal(model) {
                    TrunkFillView(fill: look.rail.fill, stage: look.stage, w: w, h: h)
                        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.45), radius: 1.5, x: 0, y: 2)
                } else {
                    Color.black.opacity(0.75)
                        .shadow(color: Color.white.opacity(0.14), radius: 0, x: 0, y: 1)
                }
            }
            .frame(width: w, height: h)
            .offset(x: seam.horizontal ? 0 : seam.position - t / 2, y: seam.horizontal ? seam.position - t / 2 : 0)
        }
    }

    // MARK: 底（滑り材・足・蝶番）

    private func bottomFittings(_ look: TrunkLook, _ fittings: TrunkFittings) -> some View {
        let feet = TrunkFaces.feet(side, model: model)
        let hinges = TrunkFaces.hinges(side)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(feet.runners.indices), id: \.self) { i in
                let r = feet.runners[i]
                TrunkFillView(fill: .wood(edge: TrunkRGBA.mix(0x8E5A2C, 0xB07A48, look.stage), middle: TrunkRGBA.mix(0xB07440, 0xC99560, look.stage)),
                              stage: look.stage, w: r.w, h: r.h)
                    .frame(width: r.w, height: r.h)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .shadow(color: Color.black.opacity(0.5), radius: 1.5, x: 0, y: 2)
                    .offset(x: r.x, y: r.y)
            }
            ForEach(Array(feet.feet.indices), id: \.self) { i in
                foot(feet.feet[i], look)
            }
            ForEach(Array(hinges.indices), id: \.self) { i in
                let h = hinges[i]
                ZStack {
                    TrunkHardwareFace(look: look, fittings: fittings, w: h.w, h: h.h)
                    // 蝶番の節（9pt ごとの暗い線）
                    TrunkStripes(angle: 90, period: 18, bands: [(8, 9, TrunkRGBA(r: 0, g: 0, b: 0, a: 0.35))])
                }
                .frame(width: h.w, height: h.h)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.45)).frame(height: 1) }
                .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 2)
                .offset(x: h.x, y: h.y)
            }
        }
    }

    @ViewBuilder
    private func foot(_ f: TrunkFaces.Foot, _ look: TrunkLook) -> some View {
        switch f.kind {
        case .metal(let metal):
            ZStack {
                TrunkPaint.metal(metal, stage: look.stage, w: 16, h: 16)
                RadialGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0)],
                               center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 6.4)
            }
            .frame(width: 16, height: 16)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.65), radius: 2, x: 0, y: 3)
            .offset(x: f.x - 8, y: f.y - 8)
        case .rubber:
            RadialGradient(colors: [Color(trunk: TrunkRGBA(0x3A3A3E)), Color(trunk: TrunkRGBA(0x0E0E10))],
                           center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 9 * 0.7)
                .frame(width: 18, height: 18)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(trunk: TrunkRGBA(0xB9BEC3)), lineWidth: 2).padding(-1))
                .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 2)
                .offset(x: f.x - 9, y: f.y - 9)
        case .leatherPad:
            TrunkPaint.linear(TrunkGradient(angle: 135, stops: [TrunkStop(color: TrunkRGBA.mix(0x5A3418, 0x6E4626, look.stage), location: 0),
                                                                 TrunkStop(color: TrunkRGBA(0x2E1808), location: 1)]), w: 24, h: 16)
                .frame(width: 24, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 2)
                .offset(x: f.x - 12, y: f.y - 8)
        case .stud:
            TrunkRivetFace(slat: true, metal: nil, model: model, r: 2.8)
                .frame(width: 5.6, height: 5.6)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.6), radius: 0.75, x: 0, y: 1)
                .offset(x: f.x - 2.8, y: f.y - 2.8)
        }
    }

    // MARK: 鋲

    private func rivets(_ look: TrunkLook, _ size: (w: Double, h: Double)) -> some View {
        let dots = TrunkFaces.rivets(side, look: look)
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
        .frame(width: size.w, height: size.h, alignment: .topLeading)
    }

    // MARK: 持ち手（上の面）

    @ViewBuilder
    private func handle(_ look: TrunkLook, _ fittings: TrunkFittings) -> some View {
        if let rect = TrunkFaces.handle(side, thickness: fittings.handlePaint?.thickness ?? 10) {
            let clips = TrunkFaces.handleClips(side)
            ZStack(alignment: .topLeading) {
                // 落ちる影
                Capsule().fill(Color.black.opacity(0.45))
                    .frame(width: rect.w - 4, height: rect.h)
                    .blur(radius: 3)
                    .offset(x: rect.x + 4, y: rect.y + 6)
                ForEach(Array(clips.indices), id: \.self) { i in
                    TrunkHardwareFace(look: look, fittings: fittings, w: 20, h: 20)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.45)).frame(height: 1) }
                        .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
                        .offset(x: clips[i].x, y: clips[i].y)
                }
                Group {
                    if let part = fittings.handlePaint {
                        TrunkPartPaintView(paint: part.paint)
                    } else {
                        Color(trunk: look.handle)
                    }
                }
                .frame(width: rect.w, height: rect.h)
                // 上の細い光（正面の持ち手の `inset 0 2px 0 rgba(255,255,255,0.14)`）
                .overlay(alignment: .top) { Color.white.opacity(0.14).frame(height: 2) }
                .clipShape(Capsule())
                .overlay {
                    if TrunkFaces.handleStitched(model) {
                        Path { p in
                            p.move(to: CGPoint(x: 6, y: rect.h / 2))
                            p.addLine(to: CGPoint(x: rect.w - 6, y: rect.h / 2))
                        }
                        .stroke(Color(trunk: TrunkRGBA(r: 255, g: 235, b: 200, a: 0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                }
                .offset(x: rect.x, y: rect.y)
            }
        }
    }

    // MARK: 角金具（3つの面にまたがる）

    private func corners(_ look: TrunkLook, _ fittings: TrunkFittings, _ size: (w: Double, h: Double)) -> some View {
        let cs = TrunkFaces.cornerSize(side, look: look)
        let round = look.corners.round
        return ZStack(alignment: .topLeading) {
            ForEach(TrunkCorner.allCases, id: \.self) { pos in
                if let part = fittings.cornerLook {
                    // 付けた角金具は、どの面でも部品1点の絵と同じ L の字（正面と同じ・#305）
                    TrunkMountedCorner(corner: part, pos: pos, size: cs)
                        .offset(x: pos.isLeading ? -1 : size.w - cs + 1, y: pos.isTop ? -1 : size.h - cs + 1)
                } else {
                    let shape = side == .back ? pos.shape(round: round) : pos.faceShape(round: round)
                    TrunkCornerCap(look: look, pos: pos, paint: fittings.cornerPaint, size: cs)
                        .clipShape(shape)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.white.opacity(0.4)).frame(height: 1).clipShape(shape)
                        }
                        .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 1)
                        .offset(x: pos.isLeading ? -1 : size.w - cs + 1, y: pos.isTop ? -1 : size.h - cs + 1)
                }
            }
        }
        .frame(width: size.w, height: size.h, alignment: .topLeading)
    }

    // MARK: 型押し（背面）

    @ViewBuilder
    private func mark(_ look: TrunkLook) -> some View {
        if side == .back {
            let dark = model == .aluminum || model == .clipper
            // 押した字（飾り・読み上げから外す。COIN の刻印と同じ扱い）
            Text(verbatim: "JOURNEY PHOTO")
                .font(.system(size: 9, weight: .bold))
                .tracking(9 * 0.4)
                .foregroundStyle(dark ? Color(trunk: TrunkRGBA(r: 40, g: 46, b: 52, a: 0.45)) : Color.black.opacity(0.32))
                .shadow(color: Color.white.opacity(0.14), radius: 0, x: 0, y: 1)
                .lineLimit(1)
                .fixedSize()
                .frame(width: TrunkLooks.bodyWidth)
                .offset(y: TrunkFaces.markY)
                .accessibilityHidden(true)
        }
    }

    // MARK: 擦り傷・艶・縁の陰

    private func finish(_ look: TrunkLook, _ size: (w: Double, h: Double)) -> some View {
        ZStack(alignment: .topLeading) {
            if look.scratch > 0 {
                let s = look.scratch
                TrunkStripes(angle: 118, period: 31, bands: [(13, 13.6, TrunkRGBA(r: 255, g: 255, b: 255, a: 0.4 * s))])
                TrunkStripes(angle: 64, period: 47, bands: [(23, 23.5, TrunkRGBA(r: 30, g: 35, b: 40, a: 0.22 * s))])
            }
            ForEach(Array(look.gloss.indices), id: \.self) { i in
                switch look.gloss[i] {
                case .linear(let g):
                    TrunkPaint.linear(g, w: size.w, h: size.h).frame(width: size.w, height: size.h)
                case let .spot(color, center, radius):
                    TrunkSpot(color: color, x: center.x * size.w, y: center.y * size.h,
                              rx: radius.x * size.w, ry: radius.y * size.h)
                }
            }
            // 縁の陰（`inset 0 2px 0` の光・下 10/20 の暗がり・左右 10/18）
            LinearGradient(stops: [Gradient.Stop(color: Color.clear, location: 0),
                                   Gradient.Stop(color: Color.clear, location: max(0, 1 - 30 / size.h)),
                                   Gradient.Stop(color: Color.black.opacity(0.42), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [Gradient.Stop(color: Color.black.opacity(0.22), location: 0),
                                   Gradient.Stop(color: Color.clear, location: min(1, 28 / size.w))],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [Gradient.Stop(color: Color.clear, location: max(0, 1 - 28 / size.w)),
                                   Gradient.Stop(color: Color.black.opacity(0.26), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: size.w, height: 2)
        }
        .frame(width: size.w, height: size.h, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// 吊るす紐（立体の上の面と正面・`TrunkFaces.topCords`・`frontCords`）。端は丸く、少し影を落とす
struct TrunkHangCords: View {
    let cords: [TrunkFaces.HangCord]

    var body: some View {
        Canvas { ctx, _ in
            for c in cords {
                var line = Path()
                line.move(to: CGPoint(x: c.fromX, y: c.fromY))
                line.addLine(to: CGPoint(x: c.toX, y: c.toY))
                ctx.stroke(line, with: .color(Color.black.opacity(0.35)),
                           style: StrokeStyle(lineWidth: c.width + 1, lineCap: .round))
                ctx.stroke(line, with: .color(Color(trunk: c.color)), style: StrokeStyle(lineWidth: c.width, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
