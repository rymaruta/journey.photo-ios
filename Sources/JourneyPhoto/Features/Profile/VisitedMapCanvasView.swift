import SwiftUI

/// 行った県マップの**地図**（札 #503・提案書 第2版 案 A「実形の日本地図」）。
///
/// 形は既存の `japan-prefectures.json`（`PrefectureMapGeometry`）。県ごとに回数の段で塗る:
/// 未＝斜線／1 回＝#796440 無地／2 回＝#C9A66B 点／3 回＝#F3DCA6 横縞／4 回以上＝#F3DCA6 格子／
/// 写真の候補＝斜線＋真鍮の点線の縁。**色だけに頼らず模様と数字（拡大時）と読み上げでも伝える。**
/// 真鍮は黒い地の上だけ（この画面は黒地）。
///
/// - 拡大（ピンチ・＋−）と移動（拡大中のドラッグ）。押した点は `PrefectureMapGeometry.prefecture(at:)` が
///   近い県まで拾う。長押し（0.5 秒）は、スイッチによらず札を開く
/// - 色の切り替えは 0.15 秒。そろった周の祝いは、地図が一度だけ 1.6 秒かけて明るくなる。
///   **「視差効果を減らす」では動かさない**（すぐ切り替わるだけ・明るくもしない）
/// - 読み上げは県ごとの要素（「東京都、5 回」）。操作は「ダブルタップで 1 回足す／札を開く」
/// - 沖縄は左上の挿入図（細い枠）。小笠原・奄美などの島は描かない（`PrefectureMapGeometry`）
struct VisitedMapCanvasView: View {

    let geometry: PrefectureMapGeometry
    @ObservedObject var model: VisitedMapModel
    @Binding var viewport: VisitedMapViewport
    /// 押した点と県（札の「近くの県」を作るため）
    var onTap: (CGPoint, String) -> Void = { _, _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var panStart: VisitedMapViewport?
    @State private var pinchStart: VisitedMapViewport?
    @State private var touchBegan: Date?
    @State private var moved = false
    @State private var pinched = false
    /// 回数が変わった県だけ 0.15 秒かけて切り替える
    @State private var fades: [String: Fade] = [:]
    @State private var liftStart: Date?

    private struct Fade {
        let from: Int
        let start: Date
    }

    nonisolated static let fadeSeconds: Double = 0.15
    nonisolated static let liftSeconds: Double = 1.6
    /// 祝いで混ぜる白の最大の割合
    nonisolated static let liftStrength: Double = 0.22

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size
            ZStack {
                TimelineView(.animation(minimumInterval: nil, paused: fades.isEmpty && liftStart == nil)) { context in
                    Canvas { ctx, _ in
                        draw(&ctx, container: container, now: context.date)
                    }
                }
                .accessibilityHidden(true)
                labels(container: container)
                    .accessibilityHidden(true)
                accessibilityLayer(container: container)
            }
            .frame(width: container.width, height: container.height)
            .contentShape(Rectangle())
            // 画面のスクロールを止めないよう、どちらも同時に受ける（拡大中だけ画面のスクロールを止める）
            .simultaneousGesture(dragGesture(container: container))
            .simultaneousGesture(pinchGesture(container: container))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(VisitedMapText.mapAccessibility)
            .accessibilityIdentifier("visitedMap.map")
        }
        .onChange(of: levels) { old, new in startFades(from: old, to: new) }
        .onChange(of: model.celebration) { _, new in
            guard new != nil, !reduceMotion else { return }
            liftStart = Date()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(Self.liftSeconds * 1_000_000_000) + 100_000_000)
                liftStart = nil
            }
        }
    }

    // MARK: - 段

    private var levels: [Int] { model.record.counts.map(VisitedPrefectures.level(forCount:)) }

    private func startFades(from old: [Int], to new: [Int]) {
        guard !reduceMotion, old.count == new.count else { return }
        let now = Date()
        var changed: [String: Fade] = [:]
        for (index, name) in RegionList.prefectures.enumerated() where old[index] != new[index] {
            changed[name] = Fade(from: old[index], start: now)
        }
        guard !changed.isEmpty else { return }
        for (name, fade) in changed { fades[name] = fade }
        Task {
            try? await Task.sleep(nanoseconds: UInt64((Self.fadeSeconds + 0.1) * 1_000_000_000))
            let cutoff = Date().addingTimeInterval(-Self.fadeSeconds)
            fades = fades.filter { $0.value.start > cutoff }
        }
    }

    // MARK: - 描く

    private func draw(_ ctx: inout GraphicsContext, container: CGSize, now: Date) {
        let content = geometry.size
        let v = viewport
        let counts = model.record.counts
        let candidates = Set(model.candidates)
        let lift = liftAmount(now)

        func mapped(_ p: CGPoint) -> CGPoint { v.screenPoint(forUnit: p, content: content, container: container) }
        func path(for piece: PrefectureMapGeometry.Piece) -> Path {
            var path = Path()
            for polygon in piece.polygons {
                guard let first = polygon.first else { continue }
                path.move(to: mapped(first))
                for p in polygon.dropFirst() { path.addLine(to: mapped(p)) }
                path.closeSubpath()
            }
            return path
        }
        let visible = CGRect(origin: .zero, size: container).insetBy(dx: -40, dy: -40)

        struct Item {
            let piece: PrefectureMapGeometry.Piece
            let path: Path
            let level: Int
            let fill: UInt32
            let progress: Double
            let screenBounds: CGRect
        }
        var items: [Item] = []
        for (index, name) in RegionList.prefectures.enumerated() {
            guard let piece = geometry.piece(name) else { continue }
            let topLeft = mapped(piece.bounds.origin)
            let bottomRight = mapped(CGPoint(x: piece.bounds.maxX, y: piece.bounds.maxY))
            let screenBounds = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x,
                                      height: bottomRight.y - topLeft.y)
            let level = VisitedPrefectures.level(forCount: counts[index])
            var fill = VisitedMapStyle.fill(forLevel: level)
            var progress = 1.0
            if let fade = fades[name] {
                progress = min(1, max(0, now.timeIntervalSince(fade.start) / Self.fadeSeconds))
                fill = VisitedMapStyle.mix(VisitedMapStyle.fill(forLevel: fade.from), fill, progress)
            }
            if lift > 0 { fill = VisitedMapStyle.mix(fill, 0xFFFFFF, lift) }
            items.append(Item(piece: piece, path: visible.intersects(screenBounds) ? path(for: piece) : Path(),
                              level: level, fill: fill, progress: progress, screenBounds: screenBounds))
        }

        // 1. 塗り
        for item in items where visible.intersects(item.screenBounds) {
            ctx.fill(item.path, with: .color(ProMarkColors.color(item.fill)))
        }
        // 2. 模様（県の形の内側だけ）
        for item in items where visible.intersects(item.screenBounds) {
            guard let line = Self.patternPath(item.level, bounds: item.screenBounds.intersection(visible)) else { continue }
            var layer = ctx
            layer.clip(to: item.path)
            if item.level == 0 {
                layer.stroke(line.path, with: .color(Color.white.opacity(0.12)), style: line.style)
            } else {
                let ink = item.level >= 2 ? VisitedMapStyle.inkOnBright : VisitedMapStyle.inkOnDark
                layer.stroke(line.path, with: .color(ProMarkColors.color(ink).opacity(0.42 * item.progress)),
                             style: line.style)
            }
        }
        // 3. 縁。未の県は白の細線、塗った県は黒（隣との境）、写真の候補は真鍮の点線
        for item in items where visible.intersects(item.screenBounds) {
            if item.level == 0 {
                if candidates.contains(item.piece.prefecture) {
                    ctx.stroke(item.path, with: .color(WebTheme.accent),
                               style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                } else {
                    ctx.stroke(item.path, with: .color(Color.white.opacity(0.2)), lineWidth: 0.6)
                }
            } else {
                ctx.stroke(item.path, with: .color(Color.black.opacity(0.9)), lineWidth: 1)
            }
        }
        // 4. 沖縄の挿入図の枠
        if let inset = geometry.inset {
            let a = mapped(inset.origin)
            let b = mapped(CGPoint(x: inset.maxX, y: inset.maxY))
            var frame = Path()
            frame.addRoundedRect(in: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y),
                                 cornerSize: CGSize(width: 8, height: 8))
            ctx.stroke(frame, with: .color(Color.white.opacity(0.14)), lineWidth: 1)
        }
    }

    /// 祝いの明るさ（0 → ピーク → 0 を 1.6 秒で）。動かさない設定のときは 0
    private func liftAmount(_ now: Date) -> Double {
        guard !reduceMotion, let start = liftStart else { return 0 }
        let t = now.timeIntervalSince(start) / Self.liftSeconds
        guard t >= 0, t <= 1 else { return 0 }
        return sin(t * .pi) * Self.liftStrength
    }

    /// 段ごとの模様の線（画面の点）。間隔は拡大しても変えない。無地は nil
    static func patternPath(_ level: Int, bounds: CGRect) -> (path: Path, style: StrokeStyle)? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        switch VisitedMapStyle.pattern(forLevel: level) {
        case .solid:
            return nil
        case .hatch:
            // 斜線（右上がり・間隔 7）
            let gap: CGFloat = 7
            var path = Path()
            var x = bounds.minX - bounds.height
            while x < bounds.maxX {
                path.move(to: CGPoint(x: x, y: bounds.maxY))
                path.addLine(to: CGPoint(x: x + bounds.height, y: bounds.minY))
                x += gap
            }
            return (path, StrokeStyle(lineWidth: 1))
        case .dots:
            // 点（間隔 7・直径 2）
            let gap: CGFloat = 7
            var path = Path()
            var y = (bounds.minY / gap).rounded(.down) * gap
            while y < bounds.maxY {
                var x = (bounds.minX / gap).rounded(.down) * gap
                while x < bounds.maxX {
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + 0.01, y: y))
                    x += gap
                }
                y += gap
            }
            return (path, StrokeStyle(lineWidth: 2.2, lineCap: .round))
        case .stripes:
            // 横縞（間隔 6・太さ 1.4）
            let gap: CGFloat = 6
            var path = Path()
            var y = (bounds.minY / gap).rounded(.down) * gap
            while y < bounds.maxY {
                path.move(to: CGPoint(x: bounds.minX, y: y))
                path.addLine(to: CGPoint(x: bounds.maxX, y: y))
                y += gap
            }
            return (path, StrokeStyle(lineWidth: 1.4))
        case .grid:
            // 格子（間隔 6・太さ 1.2）
            let gap: CGFloat = 6
            var path = Path()
            var y = (bounds.minY / gap).rounded(.down) * gap
            while y < bounds.maxY {
                path.move(to: CGPoint(x: bounds.minX, y: y))
                path.addLine(to: CGPoint(x: bounds.maxX, y: y))
                y += gap
            }
            var x = (bounds.minX / gap).rounded(.down) * gap
            while x < bounds.maxX {
                path.move(to: CGPoint(x: x, y: bounds.minY))
                path.addLine(to: CGPoint(x: x, y: bounds.maxY))
                x += gap
            }
            return (path, StrokeStyle(lineWidth: 1.2))
        }
    }

    // MARK: - 字（拡大したとき）

    @ViewBuilder
    private func labels(container: CGSize) -> some View {
        let zoom = viewport.zoom
        let counts = model.record.counts
        ZStack {
            if zoom >= VisitedMapViewport.countsFromZoom {
                ForEach(Array(RegionList.prefectures.enumerated()), id: \.offset) { item in
                    label(item.element, count: counts[item.offset], container: container,
                          showsName: zoom >= VisitedMapViewport.namesFromZoom)
                }
            }
            if let inset = geometry.inset {
                let corner = viewport.screenPoint(forUnit: CGPoint(x: inset.minX + 10, y: inset.maxY - 4),
                                                  content: geometry.size, container: container)
                Text(VisitedMapText.okinawaInset)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .fixedSize()
                    .position(x: corner.x + 20, y: corner.y - 8)
            }
        }
    }

    @ViewBuilder
    private func label(_ name: String, count: Int, container: CGSize, showsName: Bool) -> some View {
        if let piece = geometry.piece(name) {
            let at = viewport.screenPoint(forUnit: piece.anchor, content: geometry.size, container: container)
            if CGRect(origin: .zero, size: container).insetBy(dx: -20, dy: -20).contains(at),
               count > 0 || showsName {
                let level = VisitedPrefectures.level(forCount: count)
                let ink = level >= 2 ? ProMarkColors.color(VisitedMapStyle.inkOnBright)
                                      : (level == 1 ? Color.white : WebTheme.text2)
                VStack(spacing: 0) {
                    if showsName {
                        Text(PrefectureResolver.shortName(name))
                            .font(JPFont.caption.weight(.semibold))
                    }
                    if count > 0 {
                        Text(VisitedPrefectures.countText(count))
                            .font(JPFont.number(JPTypeScale.caption, weight: .bold, relativeTo: .caption))
                    }
                }
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
                .position(x: at.x, y: at.y)
            }
        }
    }

    // MARK: - 読み上げ

    private func accessibilityLayer(container: CGSize) -> some View {
        let counts = model.record.counts
        let candidates = Set(model.candidates)
        let adds = model.addsOnTap
        return ZStack {
            ForEach(Array(RegionList.prefectures.enumerated()), id: \.offset) { item in
                accessibilityElement(item.element, count: counts[item.offset], isCandidate: candidates.contains(item.element),
                                     adds: adds, order: Double(RegionList.prefectures.count - item.offset), container: container)
            }
        }
    }

    @ViewBuilder
    private func accessibilityElement(_ name: String, count: Int, isCandidate: Bool, adds: Bool,
                                      order: Double, container: CGSize) -> some View {
        if let piece = geometry.piece(name) {
            let at = viewport.screenPoint(forUnit: piece.anchor, content: geometry.size, container: container)
            // 読み上げの枠は 44pt の箱（`position` の外に付けると地図いっぱいの枠になる）
            Color.clear
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VisitedMapText.prefectureAccessibility(name, count: count, isCandidate: isCandidate))
                .accessibilityHint(VisitedMapText.tapHint(addsCount: adds))
                .accessibilityAddTraits(.isButton)
                .accessibilitySortPriority(order)
                .accessibilityAction { model.tap(name) }
                .accessibilityAction(named: L("札を開く", "Open details")) { model.openCard(name) }
                .accessibilityIdentifier("visitedMap.pref.\(name)")
                .position(x: at.x, y: at.y)
        }
    }

    // MARK: - ジェスチャー

    private func dragGesture(container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if touchBegan == nil {
                    touchBegan = Date()
                    panStart = viewport
                    moved = false
                }
                let distance = (value.translation.width * value.translation.width
                                + value.translation.height * value.translation.height).squareRoot()
                if distance > 10 { moved = true }
                // 動かすのは拡大しているときだけ（1 倍では画面のスクロールに任せる）。ピンチ中は動かさない
                if moved, pinchStart == nil, let start = panStart, start.isZoomed {
                    viewport = start.panned(by: value.translation, content: geometry.size, container: container)
                }
            }
            .onEnded { value in
                let began = touchBegan
                let didMove = moved
                let didPinch = pinched
                touchBegan = nil
                panStart = nil
                moved = false
                pinched = false
                guard !didMove, !didPinch else { return }
                let long = began.map { Date().timeIntervalSince($0) >= 0.5 } ?? false
                tap(at: value.location, long: long, container: container)
            }
    }

    private func pinchGesture(container: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                pinched = true
                let start = pinchStart ?? viewport
                if pinchStart == nil { pinchStart = viewport }
                viewport = start.zoomed(to: start.zoom * value.magnification, around: value.startLocation,
                                        content: geometry.size, container: container)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func tap(at location: CGPoint, long: Bool, container: CGSize) {
        let unit = viewport.unitPoint(forScreen: location, content: geometry.size, container: container)
        let tolerance = viewport.tolerance(content: geometry.size, container: container)
        guard let name = geometry.prefecture(at: unit, tolerance: tolerance) else { return }
        onTap(unit, name)
        if long { model.openCard(name) } else { model.tap(name) }
    }
}
