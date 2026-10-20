import SwiftUI
import UIKit

/// とおまわり号の中（2026-10-19・板 CamperRoomMain・CamperRoomFlow・CamperRoomViews）。
///
/// 上に斜め上から見下ろす箱庭の部屋（指一本で回す・寄ってから指一本で中を見る・二本指で寄る）、下に 4 つの道具（置く・模様替え・写真・図鑑）。
/// 右上で昼と夜。家具は長押しで持ち上げ、マス目に吸い付かせて動かす（白は置ける・赤はぶつかる）。二本指でひねると
/// 90° 回る。「しまう」で持ち物へ。「元に戻す」は 1 手ずつ。配置は人ごとにこの端末へ覚える（`CamperRoomStore`）。
///
/// 2026-10-19 判断: 板の 4 つ目の道具「招く」はサーバーが要るので第1段では出さず、家具の図鑑を置いた
/// （友達が訪ねるのはサーバーと一緒に・docs/CAMPER.md）。
struct CamperRoomView: View {
    let ownerName: String?
    let userId: String?
    let photos: [Photo]
    let stage: CamperStage
    let stats: CamperStats
    let paint: UInt32
    let initialMood: CamperMood

    enum Mode: String { case home, edit, style, photos }
    enum StyleTab: String, CaseIterable { case wall, floor, curtain, light }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var photoImages = CamperRoomPhotoImages()
    @State private var room: CamperRoomKind = .car
    @State private var editor: CamperRoomEditor?
    @State private var mode: Mode = .home
    @State private var mood: CamperMood = .day
    @State private var camera = CamperRoomCamera()
    @State private var animateCamera = false
    @State private var selected: String?
    @State private var drag: CamperRoomItem?
    @State private var dragCheck: CamperRoomCheck?
    @State private var gesture: PointerState?
    @State private var pinchStart: CamperRoomCamera?
    @State private var trayTab: CamperRoomPlacement = .floor
    @State private var styleTab: StyleTab = .wall
    @State private var framePick: String?
    @State private var photoPick: String?
    @State private var showDex = false
    @State private var readyMarker = ""
    @State private var viewport = CGSize(width: 390, height: 440)
    @State private var notice: String?
    @State private var lifted = 0
    @State private var loaded = false
    /// 置く棚の縦の割合（下の段÷箱庭と棚の合計。指で上下に伸ばせる・端末に覚える・2026-10-20 owner）
    @State private var editPanelFraction = CamperRoomPanelSplit.load()
    @State private var resizeDragStart: Double?
    @State private var splitHeight: CGFloat = 520

    /// 指の動き（始めた所・持ち上げた家具・回し始めのカメラ）
    struct PointerState {
        var start: CGPoint
        var began = Date()
        var item: CamperRoomItem?
        var moving = false
        var rotating = false
        var camera: CamperRoomCamera
    }

    private var layout: CamperRoomLayout { CamperRoomLayout.make(room, stage: stage) }
    private var store: CamperRoomStore { CamperRoomStore(userId: userId) }
    /// 数えた値と持っている家具（写真の言葉を読むので重い。描き直しのたびに数えず、写真が替わった時だけ）
    @State private var roomStats = CamperRoomStats()
    @State private var owned: Set<String> = []
    private var partsOwned: Set<String> { CamperCatalog.owned(stats) }
    private var shownDoc: CamperRoomDocument { editor?.shown(owned: owned) ?? CamperRoomRules.starterDocument(layout) }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                if CamperRoomKind.rooms(stage).count > 1 { roomTabs }
                if mode == .edit {
                    // 置く棚の縦幅を指で変えられる（2026-10-20 owner「Cursor の窓のように広く狭く」）
                    GeometryReader { split in
                        let total = max(split.size.height, 1)
                        let frac = CamperRoomPanelSplit.clamped(editPanelFraction)
                        let handle: CGFloat = 22
                        let panelH = min(total - 160 - handle, max(210, total * frac))
                        let sceneH = max(160, total - panelH - handle)
                        VStack(spacing: 0) {
                            sceneArea(width: geo.size.width, height: sceneH)
                            panelResizeHandle(totalHeight: total)
                            panel
                                .frame(height: panelH, alignment: .top)
                                .clipped()
                        }
                        .onAppear { splitHeight = total }
                        .onChange(of: split.size.height) { _, h in splitHeight = h }
                    }
                } else {
                    let sceneHeight = min(460, max(300, geo.size.height * 0.56))
                    sceneArea(width: geo.size.width, height: sceneHeight)
                    panel
                }
            }
        }
        .background { Color.black.ignoresSafeArea() }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // 部屋の中はタブを隠す（下の道具の段がタブに掛からない・Mac run 568）
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: load)
        .onChange(of: room) { _, _ in openRoom() }
        .onChange(of: photos.count) { _, _ in
            recount()
            fillFramesIfNeeded()
        }
        .task(id: photoLoadKey) {
            // 飾る画面では一覧の写真も先に読む（押してから待つと「載らない」ように見える・#326）
            let ids = mode == .photos ? hangablePhotoIds + photoIds : photoIds
            photoImages.load(ids, from: photos)
        }
        .sheet(isPresented: $showDex) {
            CamperRoomDexView(owned: owned, stats: stats, roomStats: roomStats, paint: paint, initialMood: mood) { showDex = false }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lifted)
    }

    /// 箱庭と置く棚の境（上下にドラッグで棚の縦幅を変える）
    private func panelResizeHandle(totalHeight: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.32))
            .frame(width: 40, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizeDragStart == nil { resizeDragStart = editPanelFraction }
                        let delta = -Double(value.translation.height) / Double(max(totalHeight, 1))
                        setEditPanelFraction((resizeDragStart ?? CamperRoomPanelSplit.defaultFraction) + delta)
                    }
                    .onEnded { _ in resizeDragStart = nil }
            )
            .accessibilityElement()
            .accessibilityLabel(L("棚の高さを変える", "Resize the shelf"))
            .accessibilityHint(L("上下に払うと、棚の高さが変わります", "Swipe up or down to change the shelf height"))
            .accessibilityValue(L("\(Int((CamperRoomPanelSplit.clamped(editPanelFraction) * 100).rounded()))パーセント",
                                  "\(Int((CamperRoomPanelSplit.clamped(editPanelFraction) * 100).rounded())) percent"))
            .accessibilityAdjustableAction { direction in
                let step = 0.06
                switch direction {
                case .increment: setEditPanelFraction(editPanelFraction + step)
                case .decrement: setEditPanelFraction(editPanelFraction - step)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("camper.room.panelResize")
    }

    private func setEditPanelFraction(_ value: Double) {
        let next = CamperRoomPanelSplit.clamped(value)
        editPanelFraction = next
        CamperRoomPanelSplit.save(next)
    }

    private var photoIds: [String] { (editor?.doc.all ?? []).compactMap(\.p) }
    /// 写真の先読みをやり直す鍵（飾る画面に入った・額の写真が変わった・一覧の件数が変わった）
    private var photoLoadKey: String {
        "\(mode.rawValue)|\(photos.count)|\(photoIds.sorted().joined(separator: ","))"
    }

    // MARK: 開く・覚える

    private func load() {
        guard !loaded else { return }
        loaded = true
        mood = initialMood == .night ? .night : .day
        recount()
        openRoom()
        if CamperRoomPreview.lift { showLiftPreview() }
    }

    private func recount() {
        roomStats = CamperRoomCounting.count(photos)
        owned = CamperRoomCatalog.owned(stats, roomStats)
    }

    private func openRoom() {
        let l = layout
        let doc = CamperRoomPreview.reset ? CamperRoomRules.starterDocument(l) : store.load(l)
        var e = CamperRoomEditor(doc: doc, layout: l)
        e.fillEmptyFrames(hangablePhotoIds)
        editor = e
        if e.doc != doc { save() }
        selected = nil
        drag = nil
        camera = CamperRoomCamera.overview(l)
    }

    private func save() {
        guard let editor, !CamperRoomPreview.reset else { return }
        store.save(editor.doc)
    }

    /// 見本: 置く場面で、家具を 1 つ持ち上げて、ぶつかる所へ動かした途中
    private func showLiftPreview() {
        guard let editor else { return }
        mode = .edit
        guard let item = editor.doc.items.first(where: { $0.k == "storage.trunk" }) ?? editor.doc.items.first(where: { $0.furniture?.isRug == false }),
              let bed = editor.doc.items.first(where: { $0.k.hasPrefix("bed.") })?.rect else { return }
        var moved = item
        moved.x = bed.x + 1
        moved.z = bed.z + 1
        drag = moved
        dragCheck = editor.preview(moved)
    }

    // MARK: 見出し

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                if mode == .home { dismiss() } else { goHome() }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    Text(mode == .home ? L("外へ", "Outside") : L("部屋", "Room")).font(.system(size: 15))
                }
                .foregroundStyle(WebTheme.foreground)
                .padding(.leading, 4)
                .padding(.trailing, 10)
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mode == .home ? L("外へ出る", "Go outside") : L("部屋に戻る", "Back to the room"))
            .accessibilityIdentifier("camper.room.back")
            VStack(spacing: 2) {
                Text(eyebrow).jpEyebrow().foregroundStyle(WebTheme.accent).lineLimit(1)
                Text(title).font(JPFont.display(20, relativeTo: .title3)).foregroundStyle(WebTheme.foreground).lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Button {
                mood = mood == .night ? .day : .night
            } label: {
                Image(systemName: mood == .night ? "sun.max" : "moon")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mood == .night ? L("昼にする", "Make it day") : L("夜にする", "Make it night"))
            .accessibilityIdentifier("camper.room.night")
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var eyebrow: String {
        switch mode {
        case .home: return CamperText.carName
        case .edit: return L("床 \(layout.width)×\(layout.depth) マス", "Floor \(layout.width) × \(layout.depth)")
        case .style: return CamperText.carName
        case .photos: return L("壁に飾る", "On the wall")
        }
    }

    private var title: String {
        switch mode {
        case .home: return L("\(CamperText.carName)の中", "Inside \(CamperText.carName)")
        case .edit: return L("家具を置く", "Arrange")
        case .style: return L("模様替え", "Restyle")
        case .photos: return L("写真を飾る", "Hang photos")
        }
    }

    /// 7 部屋。名前が横に並びきらないので、横に送れる
    private var roomTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(CamperRoomKind.rooms(stage), id: \.self) { k in
                    Button { room = k } label: {
                        Text(k.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(k == room ? WebTheme.accent : WebTheme.muted2)
                            .padding(.horizontal, 12)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .overlay(alignment: .bottom) { Rectangle().fill(k == room ? WebTheme.accent : Color.clear).frame(height: 2) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(k == room ? .isSelected : [])
                    .accessibilityIdentifier("camper.room.room.\(k.rawValue)")
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: 部屋の場面

    private func sceneArea(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            CamperRoomSceneView(layout: layout, doc: shownDoc, paint: paint, mood: mood, camera: camera, animateCamera: animateCamera && !reduceMotion,
                                editing: mode == .edit, photosMode: mode == .photos, focusFrame: mode == .photos ? framePick : nil,
                                previewPhotoId: mode == .photos ? photoPick : nil, selected: selected, drag: drag, dragCheck: dragCheck,
                                photoImages: photoImages.images) { marker in
                readyMarker = marker
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(pointer)
            .simultaneousGesture(pinch)
            .simultaneousGesture(twist)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sceneLabel)
            .accessibilityAddTraits(.isImage)
            .accessibilityValue(PreviewSession.userId != nil ? readyMarker : "")
            .accessibilityAction(named: L("右へ回す", "Turn right")) { turn(by: 30) }
            .accessibilityAction(named: L("左へ回す", "Turn left")) { turn(by: -30) }
            .accessibilityIdentifier("camper.room.scene")
            .onAppear { viewport = CGSize(width: width, height: height) }
            .onChange(of: width) { _, w in viewport.width = w }
            if let selected, drag == nil, mode == .edit || mode == .home, let point = actionPoint(selected) {
                itemActions(selected)
                    .position(x: min(max(point.x, 110), width - 110), y: min(max(point.y - 34, 30), height - 30))
            }
            if let notice {
                Text(notice)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .overlay(Capsule().strokeBorder(WebTheme.danger.opacity(0.6), lineWidth: 1))
                    .frame(width: width)
                    .padding(.top, 10)
                    .accessibilityIdentifier("camper.room.notice")
            }
        }
        .frame(width: width, height: height)
        .background(RadialGradient(colors: [CamperStyle.color(mood == .night ? 0x1C1206 : 0x1D1B14), Color.black],
                                   center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 420))
    }

    private var sceneLabel: String {
        let n = editor?.counts.floor ?? 0
        return L("\(CamperText.carName)の中。\(layout.kind.name)・\(mood == .night ? "夜" : "昼")・家具 \(n)",
                 "Inside \(CamperText.carName). \(layout.kind.name), \(mood == .night ? "night" : "day"), \(n) pieces")
    }

    /// 回す・しまうの札を出す所（家具の上の画面の点）
    private func actionPoint(_ uid: String) -> CGPoint? {
        guard let item = editor?.doc.item(uid), let b = CamperRoomPick.bounds(item, ceiling: layout.ceilingHeight) else { return nil }
        let top = CV3((b.min.x + b.max.x) / 2, b.max.y, (b.min.z + b.max.z) / 2)
        return camera.project(top, viewport: viewport, layout: layout)
    }

    private func itemActions(_ uid: String) -> some View {
        let isWall = editor?.doc.item(uid)?.furniture?.placement == .wall
        return HStack(spacing: 6) {
            if !isWall {
                floatingButton(L("回す", "Turn"), symbol: "rotate.right", id: "camper.room.rotate",
                               label: L("右へ 90 度回す", "Turn 90 degrees")) { rotateSelected() }
            }
            floatingButton(L("しまう", "Put away"), symbol: "tray.and.arrow.down", id: "camper.room.stow", label: L("しまう", "Put away")) {
                stow(uid)
            }
        }
    }

    private func floatingButton(_ title: String, symbol: String, id: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(CamperStyle.color(0x0C0C0C).opacity(0.82), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: 指の動き

    /// 一本指: 家具を押すと選ぶ。長押し（0.35 秒）で持ち上げ、そのまま動かすとマス目に吸い付く。
    /// 選んでいる家具は押してすぐ動かせる。家具の無い所をなぞると部屋が回る。
    /// 1.8 倍より寄っているときは、同じなぞりで部屋の中を見て回る（大きな部屋の端まで届く）
    private var pointer: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let editor else { return }
                if gesture == nil {
                    let ray = camera.ray(value.startLocation, viewport: viewport, layout: layout)
                    let hit = mode == .style ? nil : CamperRoomPick.item(at: ray, in: editor.doc, ceiling: layout.ceilingHeight)
                    gesture = PointerState(start: value.startLocation, item: hit, camera: camera)
                    if let hit { scheduleLift(hit.u) }
                }
                guard var g = gesture else { return }
                let dx = Double(value.translation.width), dy = Double(value.translation.height)
                let far = (dx * dx + dy * dy).squareRoot() > 8
                if !g.moving, !g.rotating, far {
                    if let item = g.item, item.u == selected, mode == .edit || mode == .home {
                        g.moving = true
                        beginMove(item)
                    } else if drag == nil {
                        g.rotating = true
                    }
                }
                if drag != nil, let item = g.item {
                    g.moving = true
                    let ray = camera.ray(value.location, viewport: viewport, layout: layout)
                    let candidate = CamperRoomPick.moved(item, ray: ray, layout: layout)
                    drag = candidate
                    dragCheck = editor.preview(candidate)
                } else if g.rotating {
                    animateCamera = false
                    if g.camera.zoom > 1.8 {
                        camera = g.camera.panned(dx: dx, dy: dy, layout: layout)
                    } else {
                        camera = g.camera.dragged(dx: dx, dy: dy)
                    }
                }
                gesture = g
            }
            .onEnded { value in
                defer { gesture = nil }
                guard let g = gesture else { return }
                if let candidate = drag, g.moving || g.item != nil {
                    finishMove(candidate)
                    return
                }
                let dx = Double(value.translation.width), dy = Double(value.translation.height)
                if (dx * dx + dy * dy).squareRoot() <= 8 {
                    tap(g.item)
                }
            }
    }

    /// 長押しで持ち上げる（0.35 秒・指が動いていなければ）
    private func scheduleLift(_ uid: String) {
        let started = Date()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let g = gesture, g.began <= started.addingTimeInterval(0.01), !g.rotating, g.item?.u == uid, drag == nil,
                  mode != .style, mode != .photos else { return }
            var next = g
            next.moving = true
            gesture = next
            selected = uid
            if mode == .home { mode = .edit }
            if let item = editor?.doc.item(uid) { beginMove(item) }
        }
    }

    private func beginMove(_ item: CamperRoomItem) {
        drag = item
        dragCheck = editor?.preview(item)
        selected = item.u
        lifted += 1
    }

    /// 指を離した: 置ければ置く。ぶつかるなら元の場所へ戻る（0.25 秒）
    private func finishMove(_ candidate: CamperRoomItem) {
        guard var e = editor else { return }
        let check = e.move(candidate)
        editor = e
        if check.ok {
            save()
        } else {
            flash(check.message)
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            drag = nil
            dragCheck = nil
        }
    }

    private func tap(_ item: CamperRoomItem?) {
        if mode == .photos {
            if let item, (item.furniture?.photoSlots ?? 0) > 0 { look(at: item) }
            return
        }
        guard mode != .style else { return }
        selected = item?.u == selected ? nil : item?.u
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? camera
                if pinchStart == nil { pinchStart = camera }
                animateCamera = false
                camera = start.pinched(Double(value.magnification))
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// 二本指でひねる: 選んでいる家具を 90° 回す
    private var twist: some Gesture {
        RotateGesture()
            .onEnded { value in
                guard abs(value.rotation.degrees) > 30, selected != nil else { return }
                rotateSelected()
            }
    }

    private func turn(by degrees: Double) {
        animateCamera = true
        var c = camera
        c.yaw += degrees
        camera = c.clamped()
    }

    // MARK: 家具の操作

    private func rotateSelected() {
        guard let uid = selected, var e = editor else { return }
        if e.rotate(uid) {
            editor = e
            save()
        } else {
            flash(L("回すと、まわりとぶつかります", "No room to turn it here"))
        }
    }

    private func stow(_ uid: String) {
        guard var e = editor else { return }
        e.stow(uid)
        editor = e
        selected = nil
        save()
    }

    private func place(_ f: CamperRoomFurniture) {
        guard var e = editor else { return }
        if let uid = e.place(f, owned: owned) {
            editor = e
            selected = uid
            save()
        } else {
            flash(L("置ける所がありません", "There\u{2019}s no space for it"))
        }
    }

    private func undo() {
        guard var e = editor, e.undo() else { return }
        editor = e
        selected = nil
        save()
    }

    private func flash(_ text: String) {
        notice = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if notice == text { notice = nil }
        }
    }

    private func goHome() {
        mode = .home
        selected = nil
        drag = nil
        animateCamera = true
        camera = CamperRoomCamera.overview(layout)
    }

    // MARK: 下の段

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch mode {
            case .home: homePanel
            case .edit: editPanel
            case .style: stylePanel
            case .photos: photosPanel
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private var countsLine: some View {
        let c = editor?.counts ?? (floor: 0, wall: 0, ceiling: 0, photos: 0)
        let l = layout
        return Text(L("家具 \(c.floor) / \(l.floorLimit) · 壁 \(c.wall) / \(l.wallLimit) · 天井 \(c.ceiling) / \(l.ceilingLimit) · 写真 \(c.photos) / \(l.photoLimit)",
                      "Floor \(c.floor)/\(l.floorLimit) · Wall \(c.wall)/\(l.wallLimit) · Ceiling \(c.ceiling)/\(l.ceilingLimit) · Photos \(c.photos)/\(l.photoLimit)"))
            .font(JPFont.number(13, weight: .regular, relativeTo: .footnote))
            .foregroundStyle(WebTheme.text2)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityIdentifier("camper.room.counts")
    }

    private var homePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            countsLine
            HStack(spacing: 8) {
                tool(L("置く", "Arrange"), symbol: "square.on.square.dashed", id: "place") { enter(.edit) }
                tool(L("模様替え", "Restyle"), symbol: "paintbrush", id: "style") { enter(.style) }
                tool(L("写真", "Photos"), symbol: "photo.on.rectangle", id: "photos") { enter(.photos) }
                tool(L("図鑑", "Collection"), symbol: "books.vertical", id: "dex") { showDex = true }
            }
            Text(L("家具を長押しで持ち上げる。指一本で部屋を回し、二本指で寄る。夜にすると灯りが付く。",
                   "Press and hold a piece to lift it. Drag to turn the room, pinch to zoom. Lights come on at night."))
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text(L("外へ出る", "Step outside"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camper.room.out")
        }
    }

    private func tool(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(WebTheme.foreground)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(WebTheme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("camper.room.tool.\(id)")
    }

    private func enter(_ m: Mode) {
        mode = m
        selected = nil
        animateCamera = true
        if m == .photos {
            if let frame = editor?.doc.all.first(where: { ($0.furniture?.photoSlots ?? 0) > 0 }) {
                look(at: frame)
            } else {
                camera = CamperRoomCamera.wall(layout)
                framePick = nil
                photoPick = nil
            }
        } else {
            camera = CamperRoomCamera.overview(layout)
        }
    }

    // MARK: 置く

    private var editPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabs(CamperRoomPlacement.allCases.map { ($0.rawValue, $0.name) }, selected: trayTab.rawValue, label: L("置く場所", "Where")) { raw in
                trayTab = CamperRoomPlacement(rawValue: raw) ?? .floor
            }
            let tray = editor?.tray(trayTab, owned: owned) ?? []
            // 横に送る一覧は家具が増えると探しにくい（2026-10-20 owner「5×5 みたいな一覧」）。5 列の升目で縦に送る。
            // 升の絵は 44pt だと縦が潰れるので、枠を大きく取る（2026-10-20 owner「枠が狭い・縦幅がなさすぎる」）
            ScrollView {
                if tray.isEmpty {
                    Text(L("棚は空です。図鑑で集めると増えます", "Nothing left on the shelf. Collect more in the collection"))
                        .font(.system(size: 13)).foregroundStyle(WebTheme.text2)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(tray) { f in
                            Button { place(f) } label: {
                                VStack(spacing: 4) {
                                    CamperRoomThumb(furniture: f, silhouette: false)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 72)
                                    Text(f.name).font(.system(size: 12)).foregroundStyle(WebTheme.text)
                                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, minHeight: 108)
                                .background(CamperStyle.color(0x141414), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("\(f.name)を置く", "Place \(f.name)"))
                            .accessibilityIdentifier("camper.room.tray.\(f.id)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Text(L("長押しで持ち上げる。白いマスは置ける、赤はぶつかる。二本指で 90 度回す。棚の上の線を上下に動かすと高さが変わる。",
                   "Press and hold to lift. White squares fit, red ones collide. Twist with two fingers to turn. Drag the bar above the shelf to resize it."))
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: undo) {
                    Text(L("元に戻す", "Undo"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(editor?.canUndo == true ? WebTheme.foreground : WebTheme.faint)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(editor?.canUndo != true)
                .accessibilityIdentifier("camper.room.undo")
                // 「元に戻す」と主ボタンを半分ずつ（主ボタンが全幅を取って「元に戻す」が消えた・Mac run 568）
                // 「できた」は作業の終わりの言い方としておかしいので「閉じる」（2026-10-20 owner）
                primaryButton(L("閉じる", "Close"), id: "camper.room.done", fill: true) { goHome() }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 模様替え

    private var stylePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabs(StyleTab.allCases.map { ($0.rawValue, styleTabName($0)) }, selected: styleTab.rawValue, label: L("模様替えするもの", "What to change")) { raw in
                styleTab = StyleTab(rawValue: raw) ?? .wall
            }
            let options = styleOptions(styleTab)
            HStack(spacing: 10) {
                ForEach(options, id: \.key) { o in
                    let on = o.key == currentStyle(styleTab)
                    Button {
                        guard o.have, var e = editor else { return }
                        var s = e.doc.style
                        switch styleTab {
                        case .wall: s.wall = o.key
                        case .floor: s.floor = o.key
                        case .curtain: s.curtain = o.key
                        case .light: s.light = o.key
                        }
                        e.setStyle(s)
                        editor = e
                        save()
                    } label: {
                        VStack(spacing: 6) {
                            CamperRoomSwatch(spec: o.spec, have: o.have)
                                .frame(width: 64, height: 64)
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(on ? WebTheme.accent : Color.white.opacity(0.16),
                                                                                        style: StrokeStyle(lineWidth: on ? 2 : 1, dash: o.have ? [] : [4, 3])))
                                .overlay(alignment: .topTrailing) { if on { CamperSelectedMark() } }
                            Text(o.have ? o.name : (o.soon ? L("近日", "Soon") : L("まだ", "Not yet")))
                                .font(.system(size: 12))
                                .foregroundStyle(on ? WebTheme.accent : (o.have ? WebTheme.text : WebTheme.faint))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(o.name + (o.have ? "" : L("（まだ持っていません）", " (not collected yet)")))
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("camper.room.style.\(o.key)")
                }
            }
            Text(L("選ぶとすぐ部屋に映る。灯りの色は夜に見える。持っていない柄は外まわりの図鑑で集める。",
                   "Changes show right away. Light colours show at night. Collect more patterns in the parts collection."))
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            primaryButton(L("これにする", "Use this"), id: "camper.room.styleDone", fill: true) { goHome() }
        }
    }

    private func styleTabName(_ t: StyleTab) -> String {
        switch t {
        case .wall: return L("壁紙", "Walls")
        case .floor: return L("床", "Floor")
        case .curtain: return L("カーテン", "Curtains")
        case .light: return L("灯り", "Light")
        }
    }

    private func currentStyle(_ t: StyleTab) -> String {
        let s = editor?.doc.style ?? CamperRoomStyle()
        switch t {
        case .wall: return s.wall
        case .floor: return s.floor
        case .curtain: return s.curtain
        case .light: return s.light
        }
    }

    struct StyleOption {
        var key: String
        var name: String
        var spec: CamperMaterialSpec
        var have: Bool
        var soon = false
    }

    /// 壁と床は外まわりの図鑑の「室内」の部品（持っている物だけ選べる）、カーテンと灯りは色
    private func styleOptions(_ t: StyleTab) -> [StyleOption] {
        switch t {
        case .wall, .floor:
            let cat: CamperCategory = t == .wall ? .wallWood : .floor
            return CamperCatalog.parts(cat).map { p in
                StyleOption(key: p.key, name: p.name, spec: t == .wall ? CamperRoomMaterials.wallSpec(p.key) : CamperRoomMaterials.floorSpec(p.key),
                            have: partsOwned.contains(p.id), soon: !p.unlock.isAvailable)
            }
        case .curtain:
            return CamperRoomMaterials.curtainColors.map {
                StyleOption(key: $0.key, name: L($0.ja, $0.en), spec: CamperMaterialSpec(color: $0.color, texture: .linenSlub), have: true)
            }
        case .light:
            return CamperRoomMaterials.lightColors.map {
                StyleOption(key: $0.key, name: L($0.ja, $0.en), spec: CamperMaterialSpec(color: $0.color, texture: .glow), have: true)
            }
        }
    }

    // MARK: 写真を飾る

    private var frames: [CamperRoomItem] { (editor?.doc.all ?? []).filter { ($0.furniture?.photoSlots ?? 0) > 0 } }

    /// 飾れる自分の写真（下書き以外・新しい順）。60 枚で切ると、それより古い投稿が額に入らない
    private var hangablePhotos: [Photo] {
        photos.filter { $0.published != false }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    private var hangablePhotoIds: [String] { hangablePhotos.map(\.id) }

    /// 空の額に、届いた写真を入れる（写真の一覧が部屋より後に届く）
    private func fillFramesIfNeeded() {
        guard var e = editor else { return }
        let before = e.doc
        e.fillEmptyFrames(hangablePhotoIds)
        guard e.doc != before else { return }
        editor = e
        save()
        if let id = framePick, photoPick == nil, let item = e.doc.item(id) { photoPick = item.p }
    }

    /// その額の前に寄る。入っている写真があれば、下の一覧でも選んでおく
    private func look(at item: CamperRoomItem) {
        framePick = item.u
        photoPick = item.p
        animateCamera = true
        camera = CamperRoomCamera.framing(item, layout: layout)
    }

    private var photosPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if frames.isEmpty {
                Text(L("まだ額がありません。「置く」の壁の棚から額を掛けてください。", "No frames yet. Hang one from the wall shelf in Arrange."))
                    .font(.system(size: 13)).foregroundStyle(WebTheme.text2)
                Spacer(minLength: 0)
                primaryButton(L("額を掛ける", "Hang a frame"), id: "camper.room.addFrame", fill: false) {
                    trayTab = .wall
                    enter(.edit)
                }
            } else {
                // 飾る額（写真のある画面なので、選んだ印と主ボタンは白）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(frames.enumerated()), id: \.element.u) { i, f in
                            let on = f.u == framePick
                            Button { look(at: f) } label: {
                                Text("\(f.furniture?.name ?? "") \(i + 1)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(on ? Color.black : WebTheme.text)
                                    .padding(.horizontal, 14)
                                    .frame(height: 36)
                                    .background(on ? Color.white : Color.clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(on ? Color.white : Color.white.opacity(0.22), lineWidth: 1))
                                    .padding(.vertical, 4)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                            .accessibilityIdentifier("camper.room.frame")
                        }
                    }
                }
                let mine = hangablePhotos
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                        ForEach(mine, id: \.id) { p in
                            let on = p.id == photoPick
                            Button {
                                photoPick = p.id
                                // 選んだ瞬間に額へ見本を載せる（「この額に飾る」の前に結果が見える）
                                if let id = framePick, let frame = editor?.doc.item(id) {
                                    animateCamera = true
                                    camera = CamperRoomCamera.framing(frame, layout: layout)
                                }
                            } label: {
                                AsyncImage(url: p.gridImageURL) { phase in
                                    switch phase {
                                    case .success(let image): image.resizable().scaledToFill()
                                    default: WebTheme.card
                                    }
                                }
                                .frame(height: 68)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.white : Color.clear, lineWidth: 3))
                                .overlay(alignment: .topTrailing) {
                                    if on {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18))
                                            .foregroundStyle(Color.black, Color.white).padding(4)
                                    }
                                }
                                .frame(minHeight: WebTheme.minTapTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(p.accessibilityText)
                            .accessibilityAddTraits(on ? .isSelected : [])
                            .accessibilityIdentifier("camper.room.photo")
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                if mine.isEmpty {
                    Text(L("投稿した写真がまだありません", "You haven\u{2019}t posted any photos yet"))
                        .font(.system(size: 13)).foregroundStyle(WebTheme.text2)
                }
                primaryButton(L("この額に飾る", "Hang it here"), id: "camper.room.hang", fill: false) {
                    guard let frame = framePick, let photo = photoPick, var e = editor else { return }
                    e.setPhoto(frame, photoId: photo)
                    editor = e
                    save()
                    if let updated = e.doc.item(frame) { look(at: updated) }
                    flash(L("この額に飾りました", "Hung on this frame"))
                }
                .disabled(framePick == nil || photoPick == nil)
                .opacity(framePick == nil || photoPick == nil ? 0.5 : 1)
            }
        }
    }

    // MARK: 部品

    /// 置く場所・模様替えの札（選んでいる札は真鍮の字と下線・黒地の上）
    private func tabs(_ items: [(String, String)], selected: String, label: String, pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                let on = item.0 == selected
                Button { pick(item.0) } label: {
                    Text(item.1)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? WebTheme.accent : WebTheme.muted2)
                        .padding(.horizontal, 12)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .overlay(alignment: .bottom) { Rectangle().fill(on ? WebTheme.accent : Color.clear).frame(height: 2) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("camper.room.tab.\(item.0)")
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    /// 主ボタン（写真の無い画面は真鍮の塗りに墨の字・写真の並ぶ画面は白）
    private func primaryButton(_ title: String, id: String, fill brass: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(brass ? WebTheme.accentText : Color.black)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(brass ? WebTheme.accentFill : Color.white, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// 外の車の画面の入口（板 CamperRoomFlow の 1: 写真の無い画面なので主ボタンは真鍮の塗りに墨の字）
struct CamperRoomEntrance: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "door.left.hand.open").font(.system(size: 15, weight: .semibold))
                Text(L("中に入る", "Step inside")).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(WebTheme.accentText)
            .padding(.horizontal, 16)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.accentFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("家具を置いたり、写真を飾ったりできます", "Arrange furniture and hang your photos"))
        .accessibilityIdentifier("camper.room.enter")
    }
}

/// 模様替えの見本の四角（貼り絵に色を掛けた小さな絵）
struct CamperRoomSwatch: View {
    let spec: CamperMaterialSpec
    let have: Bool

    /// 作った見本の絵（貼り絵を描くのは重いので、描き直しのたびに作らない）
    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor private static func image(_ kind: CamperTextureKind, _ color: UInt32) -> UIImage? {
        let key = CamperScenePlan.textureKey(kind, color)
        if let hit = cache[key] { return hit }
        guard let cg = CamperScenePalette.cgImage(CamperTextures.make(kind).tinted(color)) else { return nil }
        let made = UIImage(cgImage: cg)
        cache[key] = made
        return made
    }

    var body: some View {
        Group {
            if have, let kind = spec.texture, let image = Self.image(kind, spec.color) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                CamperStyle.color(have ? spec.color : 0x1A1A1A)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
    }
}

/// 置く棚の縦幅（箱庭と棚の境をドラッグしたときの割合）。小さくしすぎ・大きくしすぎを防ぐ
enum CamperRoomPanelSplit {
    static let minFraction = 0.34
    static let maxFraction = 0.70
    /// 升の絵が潰れない程度の初めの高さ（2026-10-20）
    static let defaultFraction = 0.50
    private static let defaultsKey = "camper.room.editPanelFraction"

    static func clamped(_ value: Double) -> Double {
        min(maxFraction, max(minFraction, value))
    }

    static func load() -> Double {
        let stored = UserDefaults.standard.object(forKey: defaultsKey) as? Double
        return clamped(stored ?? defaultFraction)
    }

    static func save(_ value: Double) {
        UserDefaults.standard.set(clamped(value), forKey: defaultsKey)
    }
}
