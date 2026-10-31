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
    /// 自分の写真を読み終えたか（読む前は新しい家具の印を決めない）
    let photosLoaded: Bool
    let stage: CamperStage
    let stats: CamperStats
    let paint: UInt32
    let initialMood: CamperMood
    /// 外から入った時の、寄った口の絵（部屋が組み上がるまで覆い、組み上がったらなだらかに消す・2026-10-21）
    var entry: CamperSceneSnapshot? = nil
    /// 持っていない柄の「外まわりの図鑑で見る」（部屋を出て、外の車の図鑑のその分類を開く・2026-10-22）。nil なら出さない
    var onCollect: ((_ partId: String) -> Void)? = nil
    @State private var entryImage: UIImage?
    @State private var entryCovered = true

    enum Mode: String { case home, edit, style, photos }
    typealias StyleTab = CamperRoomStyleTab

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
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
    /// 置く棚の分類（床一括にしない・2026-10-21）
    @State private var trayCategory: CamperRoomCategory = .bed
    /// 置く棚の控え（`CamperRoomShelfMemo`）。中身を替えても描き直させない（控えなので）
    @State private var shelfMemo = CamperRoomShelfMemo()
    @State private var styleTab: StyleTab = .wall
    /// 模様替えの途中の状態（入った時の柄・試している見本。`CamperRoomStyleSession`）
    @State private var styleSession = CamperRoomStyleSession()
    /// 持っていない柄を部屋で試している見本（保存しない・2026-10-22）
    private var trial: CamperRoomStyleChoice? {
        get { styleSession.trial }
        nonmutating set { styleSession.trial = newValue }
    }
    /// 灯りの札の間だけ夜にした（札を離れたら昼に戻す）
    @State private var autoNight = false
    /// 下の板の中身が要る高さ（場面ごとに測る）。板はこの高さだけ取り、部屋の絵は残り全部（2026-10-22）
    @State private var panelNeed: [Mode: CGFloat] = [:]
    /// 部屋の絵の高さが最後に変わった時（入った時の覆いを消すのを、大きさが落ち着くまで待つ）
    @State private var sceneResizedAt = Date.distantPast
    @State private var framePick: String?
    @State private var photoPick: String?
    @State private var showDex = false
    /// 見本の起動だけ: 全家具の接写の一覧（`CamperRoomPreview.contact`）
    @State private var showContact = false
    /// 押して置く（2026-10-21）: 棚で押した家具と、部屋の中の置ける所
    @State private var armed: CamperRoomFurniture?
    @State private var hints: CamperRoomFitArea?
    /// 新しく届いた家具（棚・図鑑の真鍮の点と「置く」の件数）
    @State private var news: Set<String> = []
    /// 初めての人への短い手引き（端末に 1 回）
    @State private var showCoach = false
    /// マスに吸い付いた・置けた時の軽い触覚
    @State private var snapTick = 0
    @State private var placedTick = 0
    /// 二度押しを見分ける（前に押した時刻と場所）
    @State private var lastTap: (at: Date, point: CGPoint)?
    @State private var readyMarker = ""
    /// 額の中身（読み上げの値の後ろに ` framed=<保存した id>,… preview=<選んだだけの id>,…` で足す・見本の起動のときだけ）。
    /// UI テストが「飾った写真が額に入ったか」を確かめる（`CriticalFlowTests`・2026-10-22）
    @State private var framedMarker = ""
    /// 見本の起動の試験用: 額の印画の様子（`CamperRoomScene.photoProbe`）
    @State private var photoProbe = ""
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
    private var seenStore: CamperRoomSeenStore { CamperRoomSeenStore(userId: userId) }
    /// 数えた値と持っている家具（写真の言葉を読むので重い。描き直しのたびに数えず、写真が替わった時だけ）
    @State private var roomStats = CamperRoomStats()
    @State private var owned: Set<String> = []
    private var partsOwned: Set<String> { CamperCatalog.owned(stats) }
    private var shownDoc: CamperRoomDocument {
        var doc = editor?.shown(owned: owned) ?? CamperRoomRules.starterDocument(layout)
        // 持っていない柄の見本は、映すだけで覚えない
        if mode == .style { doc.style = styleSession.shown(doc.style, tab: styleTab) }
        return doc
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                if CamperRoomKind.rooms(stage).count > 1 { roomTabs }
                // 部屋の絵は場面を替えても同じ 1 つ（2026-10-22: 置くの場面だけ別の枝に組んでいたので、「置く」を押すたびに
                // 立体を作り直し、組み上がるまで部屋が消えていた・Mac run 666）。高さだけを場面ごとに分ける
                GeometryReader { split in
                    let total = max(Double(split.size.height), 1)
                    let need = Double(panelNeed[mode] ?? 260)
                    let fit = mode == .edit ? editSplit(total: total)
                        : CamperRoomSheetFit.split(total: total, need: need, photos: mode == .photos)
                    VStack(spacing: 0) {
                        sceneArea(width: geo.size.width, height: CGFloat(fit.scene))
                        if mode == .edit {
                            // 置く棚の縦幅を指で変えられる（2026-10-20 owner「Cursor の窓のように広く狭く」）
                            panelResizeHandle(totalHeight: CGFloat(total))
                            panel
                                .frame(height: CGFloat(fit.panel), alignment: .top)
                                .clipped()
                        } else {
                            // 下の板は中身が要るだけの高さ、部屋の絵は残り全部（2026-10-22 owner の実機: 板が中身より低く、
                            // 見本の名前が説明と重なり、部屋の絵が上へ押し出されて切れた）。大きい文字では板を送る
                            fittedPanel(height: CGFloat(fit.panel), scrolls: CamperRoomSheetFit.scrolls(need: need, panel: fit.panel))
                        }
                    }
                    .onAppear { splitHeight = CGFloat(total) }
                    .onChange(of: split.size.height) { _, h in splitHeight = h }
                }
            }
        }
        .background { Color.black.ignoresSafeArea() }
        // 描画の数（見本の起動の計測のときだけ・見えない 1pt・2026-10-31・#430）
        .overlay(alignment: .topLeading) { if PreviewSession.camperPerf { CamperRenderProbe(id: "camper.perf.room") } }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // 部屋の中はタブを隠す（下の道具の段がタブに掛からない・Mac run 568）
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: load)
        // 部屋を閉じたら家具の小さな絵の控えを捨てる（2026-10-21 点検: 控えが増え続けた）
        .onDisappear { CamperRoomThumbs.shared.removeAll() }
        .onChange(of: room) { _, _ in openRoom() }
        .onChange(of: photos.count) { _, _ in
            recount()
            fillFramesIfNeeded()
        }
        .onChange(of: photosLoaded) { _, _ in recount() }
        .task(id: photoLoadKey) {
            // 飾る画面では一覧の写真も先に読む（押してから待つと「載らない」ように見える・#326）
            let ids = mode == .photos ? hangablePhotoIds + photoIds : photoIds
            photoImages.load(ids, from: photos)
        }
        .sheet(isPresented: $showDex) {
            CamperRoomDexView(owned: owned, stats: stats, roomStats: roomStats, paint: paint, initialMood: mood, news: news,
                              onSeen: { markSeen($0) }) { showDex = false }
        }
        .fullScreenCover(isPresented: $showContact) {
            CamperRoomContactSheet(paint: paint, kind: CamperRoomPreview.contactKind ?? .board, photos: hangablePhotos) { showContact = false }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lifted)
        // マスに吸い付くたびに軽く・置けたら成功の触覚（2026-10-21）
        .sensoryFeedback(.selection, trigger: snapTick)
        .sensoryFeedback(.success, trigger: placedTick)
    }

    /// 置くの場面の (部屋の絵, 棚) の高さ（境のつまみ 22 を除く。棚は指で決めた割合・部屋の絵は 160 以上）
    private func editSplit(total: Double) -> (scene: Double, panel: Double) {
        let handle = 22.0
        let frac = CamperRoomPanelSplit.clamped(editPanelFraction)
        let panel = min(total - 160 - handle, max(210, total * frac))
        return (max(160, total - panel - handle), panel)
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
        entryImage = entry?.last
        mood = initialMood == .night ? .night : .day
        recount()
        openRoom()
        if CamperRoomPreview.lift { showLiftPreview() }
        // 見本の旗が重なっても決まった動き: 接写の一覧の種類は `contactKind` が1つに決める（脚 → 額 → 板）、
        // 家具を選ぶのは持ち上げの見本でない時だけ
        if CamperRoomPreview.contactKind != nil { showContact = true }
        if CamperRoomPreview.select, !CamperRoomPreview.lift { selected = editor?.doc.items.first { $0.k == "storage.trunk" }?.u }
        showCoach = CamperRoomPreview.coach || (!CamperRoomPreview.reset && CamperRoomCoach.shouldShow())
    }

    private func recount() {
        roomStats = CamperRoomCounting.count(photos)
        owned = CamperRoomCatalog.owned(stats, roomStats)
        // 見本の起動は保存しない。手引きの見本だけ、新しい印の見え方を撮るために寝台の 1 点と別の 2 点に印を付ける
        if CamperRoomPreview.coach {
            news = Set(owned.filter { $0.hasPrefix("bed.") }.sorted().prefix(1) + owned.sorted().prefix(2))
        } else {
            news = CamperRoomPreview.reset ? [] : seenStore.news(owned: owned, photosLoaded: photosLoaded)
        }
    }

    /// 新しい家具を見たにする（置いた・図鑑の寄りで見た）
    private func markSeen(_ id: String) {
        guard news.contains(id) else { return }
        news.remove(id)
        if !CamperRoomPreview.reset { seenStore.markSeen([id]) }
    }

    private func openRoom() {
        let l = layout
        let doc = CamperRoomPreview.reset ? CamperRoomRules.starterDocument(l) : store.load(l)
        var e = CamperRoomEditor(doc: doc, layout: l)
        e.fillEmptyFrames(hangablePhotoIds)
        editor = e
        // 前の部屋の見本・入った時の柄を持ち越さない（2026-10-22 確かめ役）
        styleSession.roomChanged(to: e.doc.style)
        if e.doc != doc { save() }
        selected = nil
        drag = nil
        disarm()
        camera = CamperRoomPreview.cameraPreset.flatMap { CamperRoomCamera.preview($0, layout: l) } ?? CamperRoomCamera.overview(l, viewport: viewport)
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
                    Image(systemName: "chevron.left").jpSystemFont(17, weight: .semibold)
                    Text(mode == .home ? L("外へ", "Outside") : L("部屋", "Room")).jpSystemFont(15)
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
                autoNight = false
            } label: {
                Image(systemName: mood == .night ? "sun.max" : "moon")
                    .jpSystemFont(17, weight: .semibold)
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
                            .jpSystemFont(14, weight: .semibold)
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
            sceneActions(sceneView(width: width, height: height))
                .accessibilityIdentifier("camper.room.scene")
                .onAppear { refit { viewport = CGSize(width: width, height: height) } }
                .onChange(of: width) { _, w in refit { viewport.width = w } }
                // 板の高さが変わると絵の高さも変わる。初めの向きのままなら、新しい縦横に合わせ直す（2026-10-22）
                .onChange(of: height) { _, h in
                    sceneResizedAt = Date()
                    refit { viewport.height = h }
                }
            if let selected, drag == nil, mode == .edit || mode == .home, let point = actionPoint(selected) {
                // 右上の「向きを戻す」（44pt・上端 12）が出ている時は、その下まで下げて重ねない（2026-10-22）
                let top: CGFloat = showsResetView ? 86 : 30
                itemActions(selected)
                    .position(x: min(max(point.x, 110), width - 110), y: min(max(point.y - 34, top), height - 30))
            }
            sceneOverlays(width: width, height: height)
            entryCover(width: width, height: height)
            if let notice {
                Text(notice)
                    .jpSystemFont(13, weight: .semibold)
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

    /// 外から入った時の覆い: 寄った口の絵を、部屋が組み上がる（camper-room-ready）まで重ね、なだらかに消す。
    /// 確かめ役 2026-10-21: 部屋を組む約 1 秒、暗い暖色の地だけが出た（95p5・95q5）
    /// PR #364 の検証（Mac が重い回）で、4 秒の打ち切りで覆いが先に消え、部屋が描かれる前の暗い地が写った。覆いは
    /// 「部屋が画面に載って描いたコマ」（`onDrawn`）でだけ消す。打ち切りは 20 秒（それでも描かれない時だけ）。
    /// 写した絵が無い時も、暗い地ではなく灯った口の色の暖かい地で覆う
    @ViewBuilder
    private func entryCover(width: CGFloat, height: CGFloat) -> some View {
        if entry != nil {
            Group {
                if let entryImage {
                    Image(uiImage: entryImage).resizable().scaledToFill()
                } else {
                    // 灯った口の奥の色（暖かい木の壁・暗い外の縁）
                    RadialGradient(colors: [CamperStyle.color(0x8A6440), CamperStyle.color(0x3A2A1C), CamperStyle.color(0x161A22)],
                                   center: .center, startRadius: 0, endRadius: max(width, height) * 0.7)
                }
            }
            .frame(width: width, height: height)
            .clipped()
            .opacity(entryCovered ? 1 : 0)
            .allowsHitTesting(false)
            // 見本の起動だけ、画面写真の試験が覆いの有無を確かめられるよう読み上げの木に残す
            .accessibilityHidden(PreviewSession.userId == nil)
            .accessibilityIdentifier("camper.room.entryCover")
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    if entryCovered { uncoverEntry() }
                }
            }
        }
    }

    /// 覆いを消す。組み上がった後の最初のコマを描いてから（`CamperRoomSceneView.onDrawn`・Mac run 646: 夜の 1 回目は
    /// 組み上がった合図の直後に消すと、部屋がまだ描かれていない暗い地が数秒見えた）
    private func uncoverEntry() {
        guard entryCovered else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.45)) { entryCovered = false }
    }

    /// 描いた知らせ（`onDrawn`）から覆いを消すまで: 下の板の高さを測り終え、部屋の絵の大きさが 0.5 秒動かなくなってから
    /// （2026-10-22 Mac run 684: 板の高さを中身から決めるようにした後、昼に入った直後に覆いが消えて暗い画面が写った。
    /// 絵の大きさが変わった直後の描き直しのコマを「描いた」と数えた見立て）。3 秒で打ち切って消す
    private func uncoverWhenSettled() {
        Task { @MainActor in
            for _ in 0..<30 {
                let measured = mode == .edit || mode == .photos || panelNeed[mode] != nil
                if measured, Date().timeIntervalSince(sceneResizedAt) > 0.5 { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            uncoverEntry()
        }
    }

    /// 箱庭そのもの（2026-10-21: 1 つの式に修飾が多すぎて、Xcode の型検査が時間切れになった・Mac run 597。分けた）
    private func sceneView(width: CGFloat, height: CGFloat) -> some View {
        CamperRoomSceneView(layout: layout, doc: shownDoc, paint: paint, mood: mood, camera: camera, animateCamera: animateCamera && !reduceMotion,
                            editing: mode == .edit, photosMode: mode == .photos, focusFrame: mode == .photos ? framePick : nil,
                            previewPhotoId: mode == .photos ? photoPick : nil, selected: selected, drag: drag, dragCheck: dragCheck,
                            photoImages: photoImages.images, hints: mode == .edit ? hints : nil,
                            onProbe: PreviewSession.userId != nil ? { photoProbe = $0 } : nil,
                            onReady: { marker in readyMarker = marker },
                            onFramed: { framed, previewed in
                                framedMarker = " framed=" + framed.values.sorted().joined(separator: ",")
                                    + " preview=" + previewed.values.sorted().joined(separator: ",")
                            },
                            // 覆いは板の高さが落ち着いてから消す（`uncoverWhenSettled`・Mac run 684）
                            onDrawn: { uncoverWhenSettled() })
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(pointer)
        .simultaneousGesture(pinch)
        .simultaneousGesture(twist)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sceneLabel)
        .accessibilityAddTraits(.isImage)
        .accessibilityValue(PreviewSession.userId != nil ? readyMarker + " " + photoProbe + framedMarker : "")
    }

    /// 読み上げの操作（部屋を回す・家具を選ぶ）。修飾を分けて、Xcode の型検査が時間切れにならないようにする
    private func sceneActions<V: View>(_ v: V) -> some View {
        itemVoiceActions(
            v.accessibilityAction(named: L("右へ回す", "Turn right")) { turn(by: 30) }
                .accessibilityAction(named: L("左へ回す", "Turn left")) { turn(by: -30) }
                // 読み上げでも家具を選ぶ・動かす・回す・しまうができる（2026-10-21）
                .accessibilityAction(named: L("次の家具を選ぶ", "Select the next piece")) { selectNext(1) }
                .accessibilityAction(named: L("前の家具を選ぶ", "Select the previous piece")) { selectNext(-1) }
        )
    }

    /// 読み上げで、選んだ家具を動かす・回す・しまう
    private func itemVoiceActions<V: View>(_ v: V) -> some View {
        let back = L("選んだ家具を奥へ（壁の物は上へ）", "Move the piece back (up on a wall)")
        let front = L("選んだ家具を手前へ（壁の物は下へ）", "Move the piece forward (down on a wall)")
        return v.accessibilityAction(named: L("選んだ家具を左へ", "Move the piece left")) { nudge(-1, 0) }
            .accessibilityAction(named: L("選んだ家具を右へ", "Move the piece right")) { nudge(1, 0) }
            .accessibilityAction(named: back) { nudge(0, -1) }
            .accessibilityAction(named: front) { nudge(0, 1) }
            .accessibilityAction(named: L("選んだ家具を回す", "Turn the piece")) { voiceRotate() }
            .accessibilityAction(named: L("選んだ家具をしまう", "Put the piece away")) { voiceStow() }
    }

    private func voiceRotate() {
        if selected == nil { announce(Self.pickFirst) } else { rotateSelected() }
    }

    private func voiceStow() {
        guard let selected else { return announce(Self.pickFirst) }
        stow(selected)
        announce(L("しまいました", "Put away"))
    }

    private var sceneLabel: String {
        let n = editor?.counts.floor ?? 0
        let base = L("\(CamperText.carName)の中。\(layout.kind.name)・\(mood == .night ? "夜" : "昼")・家具 \(n)",
                     "Inside \(CamperText.carName). \(layout.kind.name), \(mood == .night ? "night" : "day"), \(n) pieces")
        guard let uid = selected, let f = editor?.doc.item(uid)?.furniture else { return base }
        return base + L("。選んでいる家具: \(f.name)", ". Selected: \(f.name)")
    }

    // MARK: 箱庭の上の札（向きを戻す・押して置く・初めての手引き）

    @ViewBuilder
    private func sceneOverlays(width: CGFloat, height: CGFloat) -> some View {
        // 向きを初めに戻す（回した・寄った後。写真を飾る場面は額へ寄るので出さない）
        if showsResetView {
            Button(action: resetCamera) {
                Image(systemName: "arrow.counterclockwise")
                    .jpSystemFont(15, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .background(Color.black.opacity(0.62), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("向きを初めに戻す", "Reset the view"))
            .accessibilityIdentifier("camper.room.resetView")
            .position(x: width - 34, y: 34)
        }
        // 押して置く: 何を置こうとしているか・やめる
        if let armed, mode == .edit {
            armedBanner(armed, width: width)
                .position(x: width / 2, y: height - 38)
        }
        if mode == .style, trial != nil {
            Text(L("見本 · まだ持っていない柄", "Preview · not collected yet"))
                .jpSystemFont(12, weight: .semibold, relativeTo: .caption)
                .foregroundStyle(WebTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.82), in: Capsule())
                .position(x: width / 2, y: 22)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        if showCoach, mode == .home {
            coachCard
                .frame(width: min(width - 32, 340))
                .position(x: width / 2, y: height / 2)
        }
    }

    /// 向きを初めに戻すボタンを出すか（回した・寄った後。写真を飾る場面は額へ寄るので出さない）
    private var showsResetView: Bool {
        mode != .photos && drag == nil && camera.differs(from: overviewCamera)
    }

    /// 押して置く途中の札（何を置くか・やめる）
    private func armedBanner(_ armed: CamperRoomFurniture, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("\(armed.name)を置く所を押す", "Tap where \(armed.name) goes"))
                    .jpSystemFont(13, weight: .semibold).foregroundStyle(Color.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(L("白いマスに置けます · 棚でもう一度押すと空いた所へ", "White squares fit · tap it again on the shelf to drop it anywhere"))
                    .jpSystemFont(12).foregroundStyle(WebTheme.text2)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Button(action: disarm) {
                Text(L("やめる", "Cancel"))
                    .jpSystemFont(13, weight: .semibold).foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, 10)
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camper.room.armed.cancel")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .frame(width: width - 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camper.room.armed")
    }

    /// 初めての人への手引き（3 行・端末に 1 回。写真の無い所なので主ボタンは真鍮の塗りに墨の字）
    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("はじめての方へ", "Getting started")).jpEyebrow().foregroundStyle(WebTheme.accent)
            ForEach(Self.coachLines, id: \.symbol) { line in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: line.symbol)
                        .jpSystemFont(18, weight: .semibold)
                        .foregroundStyle(WebTheme.accent)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    Text(line.text).jpSystemFont(14).foregroundStyle(WebTheme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                showCoach = false
                if !CamperRoomPreview.coach { CamperRoomCoach.done() }
            } label: {
                Text(L("わかった", "Got it"))
                    .jpSystemFont(15, weight: .semibold)
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                    .background(WebTheme.accentFill, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camper.room.coach.done")
        }
        .padding(16)
        .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camper.room.coach")
    }

    static let coachLines: [(symbol: String, text: String)] = [
        ("hand.tap", L("家具を長押しすると持ち上がる。そのまま動かして離すと置ける", "Press and hold a piece to lift it, then drag and let go")),
        ("rotate.right", L("二本指でひねると 90 度回る。選ぶと横に「回す・しまう」も出る", "Twist with two fingers to turn it. Select it for Turn and Put away")),
        ("plus.magnifyingglass", L("二度押しで寄る・もう一度で戻る。指一本で部屋を回す", "Double-tap to zoom in and again to zoom out. Drag to turn the room")),
    ]

    private static let pickFirst = L("先に家具を選んでください", "Select a piece first")

    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// 絵の縦横に合わせた初めの向き（`CamperRoomCamera.overview(_:viewport:)`・2026-10-22）
    private var overviewCamera: CamperRoomCamera { CamperRoomCamera.overview(layout, viewport: viewport) }

    /// 絵の大きさを変える。初めの向きのままだったら、新しい大きさに合わせ直す（人が回した・寄った向きは変えない）
    private func refit(_ change: () -> Void) {
        let atHome = !camera.differs(from: overviewCamera) || !camera.differs(from: CamperRoomCamera.overview(layout))
        change()
        if atHome, mode != .photos, CamperRoomPreview.cameraPreset == nil { camera = overviewCamera }
    }

    private func resetCamera() {
        animateCamera = true
        camera = overviewCamera
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
                Image(systemName: symbol).jpSystemFont(13, weight: .semibold)
                Text(title).jpSystemFont(13, weight: .semibold)
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
                    // 押して置く途中は、家具を選ばず「置く所」として読む
                    let hit = mode == .style || armed != nil ? nil : CamperRoomPick.item(at: ray, in: editor.doc, ceiling: layout.ceilingHeight)
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
                    // マスが替わったら軽い触覚（吸い付いた手応え）
                    if candidate != drag { snapTick += 1 }
                    drag = candidate
                    dragCheck = editor.preview(candidate)
                    // 画面の端へ運んだら、カメラが少し追う（寄っているときだけ）
                    if let next = camera.following(value.location, viewport: viewport, layout: layout) {
                        animateCamera = false
                        camera = next
                    }
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
                    if armed != nil {
                        placeArmed(at: value.location)
                        return
                    }
                    if g.item == nil, mode == .home || mode == .edit, isDoubleTap(value.location) {
                        doubleTap(at: value.location)
                        return
                    }
                    tap(g.item)
                }
            }
    }

    /// 家具の無い所を 0.35 秒のうちに同じ辺りで 2 回押した
    private func isDoubleTap(_ point: CGPoint) -> Bool {
        let now = Date()
        if let last = lastTap, CamperRoomTaps.isDouble(last: last.at, lastPoint: last.point, now: now, point: point) {
            lastTap = nil
            return true
        }
        lastTap = (now, point)
        return false
    }

    /// 二度押し: 離れていれば押した所へ寄り、寄っていれば初めの向きへ
    private func doubleTap(at point: CGPoint) {
        let ray = camera.ray(point, viewport: viewport, layout: layout)
        animateCamera = true
        camera = camera.doubleTapped(floor: CamperRoomPick.hitHorizontal(ray, y: 0), layout: layout, home: overviewCamera)
        lastTap = nil
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

    /// 空いている所へ置く（棚で同じ家具をもう一度押した・読み上げのとき）
    private func place(_ f: CamperRoomFurniture) {
        guard var e = editor else { return }
        disarm()
        if let uid = e.place(f, owned: owned) {
            editor = e
            selected = uid
            placed(f)
        } else {
            flash(L("置ける所がありません", "There\u{2019}s no space for it"))
        }
    }

    /// 棚の家具を押した（2026-10-21・押して置く）: 置ける所を薄く光らせて、部屋の中で押した所に置く。
    /// 同じ家具をもう一度押すと、今までどおり空いている所へ。読み上げのときは押してすぐ置く（部屋のマスを指で探せない）
    private func trayTap(_ f: CamperRoomFurniture) {
        if voiceOver || armed?.id == f.id {
            place(f)
            return
        }
        guard let area = editor?.fitArea(f), !area.isEmpty else {
            flash(L("置ける所がありません", "There\u{2019}s no space for it"))
            return
        }
        selected = nil
        armed = f
        hints = area
        // 壁の物は壁が見える向きへ、床・天井の物は部屋全体へ
        if f.placement == .wall, camera.differs(from: overviewCamera) {
            animateCamera = true
            camera = overviewCamera
        }
    }

    /// 押して置く: 部屋の中で押した所に置く（置けなければ理由を出して、そのまま選び直せる）
    private func placeArmed(at point: CGPoint) {
        guard let f = armed, var e = editor else { return }
        let ray = camera.ray(point, viewport: viewport, layout: layout)
        guard let spot = CamperRoomPick.spot(for: f, ray: ray, layout: layout) else {
            flash(L("部屋の中を押してください", "Tap inside the room"))
            return
        }
        switch e.place(f, at: spot, owned: owned) {
        case .success(let uid):
            editor = e
            selected = uid
            disarm()
            placed(f)
        case .failure(let check):
            flash(check.message)
        }
    }

    private func placed(_ f: CamperRoomFurniture) {
        markSeen(f.id)
        placedTick += 1
        save()
    }

    private func disarm() {
        armed = nil
        hints = nil
    }

    private func undo() {
        guard var e = editor, e.undo() else { return }
        editor = e
        selected = nil
        disarm()
        save()
    }

    private func redo() {
        guard var e = editor, e.redo() else { return }
        editor = e
        selected = nil
        disarm()
        save()
    }

    /// 読み上げ: 次の（前の）家具を選ぶ
    private func selectNext(_ step: Int) {
        guard let items = editor?.doc.all, !items.isEmpty else {
            announce(L("家具がありません", "No furniture yet"))
            return
        }
        let now = items.firstIndex { $0.u == selected } ?? (step > 0 ? -1 : items.count)
        let next = items[((now + step) % items.count + items.count) % items.count]
        selected = next.u
        announce(next.furniture?.name ?? "")
    }

    /// 読み上げ: 選んだ家具を 1 マス動かす（床・天井は左右と奥・手前、壁は左右と上下）
    private func nudge(_ dx: Int, _ dz: Int) {
        guard let uid = selected, var e = editor, let item = e.doc.item(uid) else {
            announce(Self.pickFirst)
            return
        }
        var moved = item
        if item.w != nil {
            moved.c = (item.c ?? 0) + dx
            moved.row = (item.row ?? 0) - dz
        } else {
            moved.x = (item.x ?? 0) + dx
            moved.z = (item.z ?? 0) + dz
        }
        let check = e.move(moved)
        if check.ok {
            editor = e
            save()
            announce(L("動かしました", "Moved"))
        } else {
            announce(check.message)
        }
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
        disarm()
        styleSession.end()
        lightTabNight()
        animateCamera = true
        camera = overviewCamera
    }

    // MARK: 下の段

    private var panelContent: some View {
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
    }

    /// 決まった高さに収める板（置く・写真を飾る。中で一覧を送る）
    private var panel: some View {
        panelContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black)
    }

    /// 家・模様替えの板: 中身が要る高さを測り、その高さだけ取る（`CamperRoomSheetFit`）。収まらない時（大きい文字）だけ送れる。
    /// 写真を飾る板は一覧を中で送るので、決まった割合
    @ViewBuilder
    private func fittedPanel(height: CGFloat, scrolls: Bool) -> some View {
        if mode == .photos {
            panel.frame(height: height)
        } else {
            let measuring = mode
            ScrollView(.vertical, showsIndicators: scrolls) {
                panelContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { h in
                        if abs((panelNeed[measuring] ?? 0) - h) > 0.5 { panelNeed[measuring] = h }
                    }
            }
            .scrollDisabled(!scrolls)
            .frame(height: height)
            .background(Color.black)
            .accessibilityIdentifier("camper.room.panel")
        }
    }

    private var countsLine: some View {
        let c = editor?.counts ?? (floor: 0, wall: 0, ceiling: 0, photos: 0)
        let l = layout
        return Text(L("家具 \(c.floor) / \(l.floorLimit) · 壁 \(c.wall) / \(l.wallLimit) · 天井 \(c.ceiling) / \(l.ceilingLimit) · 写真 \(c.photos) / \(l.photoLimit)",
                      "Floor \(c.floor)/\(l.floorLimit) · Wall \(c.wall)/\(l.wallLimit) · Ceiling \(c.ceiling)/\(l.ceilingLimit) · Photos \(c.photos)/\(l.photoLimit)"))
            .font(JPFont.number(13, weight: .regular, relativeTo: .footnote))
            .foregroundStyle(WebTheme.text2)
            // 大きい文字では縮めず折り返す（等幅の数字の塊は切らない・板 06）
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.75)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("camper.room.counts")
    }

    private var homePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            countsLine
            // 大きい文字では 4 つを 2×2 に（横 4 つでは名前が縮んで読めない・板 06）
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                tool(L("置く", "Arrange"), symbol: "square.on.square.dashed", id: "place", badge: news.count) { enter(.edit) }
                tool(L("模様替え", "Restyle"), symbol: "paintbrush", id: "style") { enter(.style) }
                tool(L("写真", "Photos"), symbol: "photo.on.rectangle", id: "photos") { enter(.photos) }
                tool(L("図鑑", "Collection"), symbol: "books.vertical", id: "dex") { showDex = true }
            }
            Text(L("家具を長押しで持ち上げる。指一本で部屋を回し、二本指か二度押しで寄る。夜にすると灯りが付く。",
                   "Press and hold a piece to lift it. Drag to turn the room; pinch or double-tap to zoom. Lights come on at night."))
                .jpSystemFont(13)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("camper.room.hint")
            // 2026-10-21 判断: 下の「外へ出る」は左上の「外へ」と同じ操作なので外した（板 CamperRoomFlow も左上の「外へ」だけ）
        }
    }

    private func tool(_ title: String, symbol: String, id: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).jpSystemFont(20)
                // 縮めない（12pt が下限）。入らなければ 2 行に
                Text(title).jpSystemFont(12, weight: .semibold).lineLimit(2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(WebTheme.foreground)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(WebTheme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            // 新しく届いた家具の数（件数バッジ: 真鍮＋墨＋黒 2px の縁）
            .overlay(alignment: .topTrailing) {
                if badge > 0 { CountBadge(count: badge, maximum: 99).padding(6) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? L("\(title)、新しい家具 \(badge)", "\(title), \(badge) new") : title)
        .accessibilityIdentifier("camper.room.tool.\(id)")
    }

    private func enter(_ m: Mode) {
        mode = m
        selected = nil
        animateCamera = true
        trial = nil
        if m == .style {
            styleSession.begin(editor?.doc.style ?? CamperRoomStyle())
            lightTabNight()
        }
        if m == .photos {
            if let frame = editor?.doc.all.first(where: { ($0.furniture?.photoSlots ?? 0) > 0 }) {
                look(at: frame)
            } else {
                camera = CamperRoomCamera.wall(layout)
                framePick = nil
                photoPick = nil
            }
        } else {
            camera = overviewCamera
        }
    }

    // MARK: 置く

    private var editPanel: some View {
        // 棚の絞り込みは 1 回だけ（分類チップごとに全部の家具を絞り直さない・2026-10-21 見直し）。
        // 材料が変わらない描き直し（家具を動かす・カメラ）では作り直さない（`CamperRoomShelfMemo`・2026-10-28）
        let shelf = shelfMemo.shelf(editor, placement: trayTab, owned: owned, news: news)
        let cats = shelf.categories
        let cat = cats.contains(trayCategory) ? trayCategory : (cats.first ?? .bed)
        let tray = shelf.items(cat)
        return VStack(alignment: .leading, spacing: 10) {
            tabs(CamperRoomPlacement.allCases.map { ($0.rawValue, $0.name) }, selected: trayTab.rawValue, label: L("置く場所", "Where")) { raw in
                let next = CamperRoomPlacement(rawValue: raw) ?? .floor
                trayTab = next
                disarm()
                if let first = editor?.trayCategories(next, owned: owned).first { trayCategory = first }
            }
            // 分類チップ（床の家具を一括りにしない・2026-10-21）
            if !cats.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(cats, id: \.self) { c in trayChip(c, on: c == cat, fresh: shelf.fresh.contains(c)) }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityLabel(L("家具の種類", "Furniture kind"))
                .accessibilityIdentifier("camper.room.trayCats")
            }
            // 横に送る一覧は家具が増えると探しにくい（2026-10-20 owner「5×5 みたいな一覧」）。5 列の升目で縦に送る。
            // 升の絵は 44pt だと縦が潰れるので、枠を大きく取る（2026-10-20 owner「枠が狭い・縦幅がなさすぎる」）
            ScrollView {
                if tray.isEmpty {
                    Text(L("棚は空です。図鑑で集めると増えます", "Nothing left on the shelf. Collect more in the collection"))
                        .jpSystemFont(13).foregroundStyle(WebTheme.text2)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    // 大きい文字では 3 列（5 列では名前が 1 字ずつ折れる・2026-10-22）
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 3 : 5), spacing: 8) {
                        ForEach(tray) { f in trayCard(f) }
                    }
                }
                // 大きい文字では説明を棚と一緒に送る（決まった高さの板で、説明が棚を押しつぶした）
                if typeSize.isAccessibilitySize { editHint.padding(.top, 10) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("camper.room.trayGrid")
            if !typeSize.isAccessibilitySize { editHint }
            HStack(spacing: 8) {
                Button(action: undo) {
                    Text(L("元に戻す", "Undo"))
                        .jpSystemFont(15, weight: .semibold)
                        .foregroundStyle(editor?.canUndo == true ? WebTheme.foreground : WebTheme.faint)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(editor?.canUndo != true)
                .accessibilityIdentifier("camper.room.undo")
                // やり直す（戻しすぎた手を取り戻す・2026-10-21）
                Button(action: redo) {
                    Text(L("やり直す", "Redo"))
                        .jpSystemFont(15, weight: .semibold)
                        .foregroundStyle(editor?.canRedo == true ? WebTheme.foreground : WebTheme.faint)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(editor?.canRedo != true)
                .accessibilityIdentifier("camper.room.redo")
                // 「元に戻す」と主ボタンを半分ずつ（主ボタンが全幅を取って「元に戻す」が消えた・Mac run 568）
                // 「できた」は作業の終わりの言い方としておかしいので「閉じる」（2026-10-20 owner）
                primaryButton(L("閉じる", "Close"), id: "camper.room.done", fill: true) { goHome() }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var editHint: some View {
        Text(L("棚の家具を押して、置きたい所を押す。部屋の家具は長押しで持ち上げる。白いマスは置ける、赤はぶつかる。二本指で 90 度回す。",
               "Tap a piece, then tap where it goes. Press and hold a piece in the room to lift it. White fits, red collides. Twist to turn."))
            .jpSystemFont(12)
            .foregroundStyle(WebTheme.text2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("camper.room.editHint")
    }

    /// 置く棚の分類チップ（選んだチップは真鍮の塗りに墨の字。新しい家具がある分類は点）
    private func trayChip(_ c: CamperRoomCategory, on: Bool, fresh: Bool) -> some View {
        let label: String = fresh ? L("\(c.name)、新しい家具あり", "\(c.name), has new pieces") : c.name
        let ink: Color = on ? WebTheme.accentText : WebTheme.text
        let fill: Color = on ? WebTheme.accentFill : CamperStyle.color(0x1C1C1C)
        let edge: Color = on ? Color.clear : Color.white.opacity(0.14)
        let dot: Color = on ? WebTheme.accentText : WebTheme.accent
        return Button {
            trayCategory = c
        } label: {
            HStack(spacing: 5) {
                Text(c.name)
                // 新しい家具がある分類（未読の点の真鍮。選んだチップの塗りの上は墨）
                if fresh { Circle().fill(dot).frame(width: 7, height: 7) }
            }
            .jpSystemFont(13, weight: .semibold)
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            // 1 字の分類（「机」）も幅 44pt（36pt だった・Mac run 672）
            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(edge, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityLabel(label)
        .accessibilityIdentifier("camper.room.tray.cat.\(c.rawValue)")
    }

    /// 棚の家具の枠（押して置く途中は真鍮の縁・新しい家具は真鍮の点）
    private func trayCard(_ f: CamperRoomFurniture) -> some View {
        let on = armed?.id == f.id
        let fresh = news.contains(f.id)
        let label: String = (fresh ? L("新しい家具、", "New, ") : "") + L("\(f.name)を置く", "Place \(f.name)")
        let hint: String = voiceOver ? L("空いている所に置きます", "Puts it in a free spot")
            : L("押してから、部屋の中の置きたい所を押します", "Then tap where it goes in the room")
        let edge: Color = on ? WebTheme.accent : Color.white.opacity(0.12)
        return Button { trayTap(f) } label: {
            VStack(spacing: 4) {
                CamperRoomThumb(furniture: f, silhouette: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                Text(f.name).jpSystemFont(12).foregroundStyle(on ? WebTheme.accent : WebTheme.text)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 108)
            .background(CamperStyle.color(0x141414), in: RoundedRectangle(cornerRadius: 14))
            // 押して置く途中の家具は真鍮の縁 2pt（黒地の上・選んだ札と同じ）
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(edge, lineWidth: on ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if fresh { Circle().fill(WebTheme.accent).frame(width: 8, height: 8).padding(7) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("camper.room.tray.\(f.id)")
    }

    // MARK: 模様替え

    /// 模様替え（2026-10-22 作り直し・owner の実機 1.1.37「操作感も悪い」）。
    /// - 見本は 4 列（大きい文字は 2 列）の升目。札の高さは中身から決め、名前が下の説明に重ならない
    /// - 持っていない柄も本当の柄を暗く見せ、鍵と「いま / 要る数」（近日は砂時計と「近日」）。押すと部屋で試せる（見本・覚えない）
    /// - 押すとすぐ部屋に映って覚える。変えていなければ下は「閉じる」（線だけ）、変えたら「元に戻す」と「これにする」
    /// - 灯りの札の間は夜にして見せる（灯りの色は昼には見えない）
    private var stylePanel: some View {
        let choices = CamperRoomStyleBoard.choices(styleTab, partsOwned: partsOwned, stats: stats)
        let now = editor?.doc.style ?? CamperRoomStyle()
        let current = CamperRoomStyleBoard.key(now, styleTab)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: typeSize.isAccessibilitySize ? 2 : 4)
        return VStack(alignment: .leading, spacing: 12) {
            tabs(StyleTab.allCases.map { ($0.rawValue, $0.name) }, selected: styleTab.rawValue, label: L("模様替えするもの", "What to change")) { raw in
                pickStyleTab(StyleTab(rawValue: raw) ?? .wall)
            }
            LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                ForEach(choices, id: \.key) { c in
                    styleCell(c, on: c.key == current, trying: trial?.key == c.key)
                }
            }
            if let trial { trialCard(trial) }
            Text(CamperRoomStyleBoard.note(styleTab, hasLocked: choices.contains { !$0.owned }))
                .jpSystemFont(12)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("camper.room.styleNote")
            styleFooter(now)
        }
    }

    /// 見本の札 1 つ（選んでいる柄は真鍮の縁 2pt とチェック・黒地の上。試している見本は白の縁 2pt）
    private func styleCell(_ c: CamperRoomStyleChoice, on: Bool, trying: Bool) -> some View {
        let edge: Color = on ? WebTheme.accent : (trying ? Color.white.opacity(0.85) : Color.white.opacity(0.16))
        return Button { pickStyle(c) } label: {
            VStack(spacing: 6) {
                CamperRoomSwatch(spec: styleSpec(c.key), have: true)
                    .overlay { if !c.owned { lockedVeil(c) } }
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(edge, style: StrokeStyle(lineWidth: on || trying ? 2 : 1, dash: c.owned || trying ? [] : [4, 3])))
                    .overlay(alignment: .topTrailing) { if on { CamperSelectedMark() } }
                Text(c.name)
                    .jpSystemFont(12, weight: on ? .semibold : .regular, relativeTo: .caption)
                    .foregroundStyle(on ? WebTheme.accent : (c.owned ? WebTheme.text : WebTheme.muted2))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = c.progressText {
                    Text(progress)
                        .font(JPFont.number(12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(c.state == .soon ? WebTheme.faint : WebTheme.accent)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .top)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(styleLabel(c))
        .modifier(CamperRoomOptionalHint(hint: c.owned ? nil : (trying ? L("もう一度押すと見本をやめます", "Tap again to stop the preview")
                                                                          : L("押すと部屋で見本を試せます", "Tap to try it in the room"))))
        .accessibilityAddTraits(on || trying ? .isSelected : [])
        .accessibilityIdentifier("camper.room.style.\(c.key)")
    }

    /// 持っていない柄の覆い（柄を暗くして鍵・近日は砂時計）。色だけで「持っていない」を言わない
    private func lockedVeil(_ c: CamperRoomStyleChoice) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            Image(systemName: c.state == .soon ? "hourglass" : "lock.fill")
                .jpSystemFont(16, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.92))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
    }

    private func styleLabel(_ c: CamperRoomStyleChoice) -> String {
        let how = c.partId.flatMap { CamperCatalog.part($0) }?.unlock.how ?? ""
        switch c.state {
        case .owned: return c.name
        case .locked(let have, let need):
            return L("\(c.name)。まだ持っていません。\(how)。いま \(min(have, need)) / \(need)",
                     "\(c.name). Not collected yet. \(how). \(min(have, need)) of \(need)")
        case .soon: return L("\(c.name)。近日。\(how)", "\(c.name). Coming soon. \(how)")
        }
    }

    private func styleSpec(_ key: String) -> CamperMaterialSpec {
        switch styleTab {
        case .wall: return CamperRoomMaterials.wallSpec(key)
        case .floor: return CamperRoomMaterials.floorSpec(key)
        case .curtain: return CamperMaterialSpec(color: CamperRoomMaterials.curtainColor(key), texture: .linenSlub)
        case .light: return CamperMaterialSpec(color: CamperRoomMaterials.lightColor(key), texture: .glow)
        }
    }

    /// 試している見本の札（どうすれば届くか・進み具合・外まわりの図鑑へ）
    private func trialCard(_ c: CamperRoomStyleChoice) -> some View {
        let part = c.partId.flatMap { CamperCatalog.part($0) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(L("見本 · まだ持っていない柄", "Preview · not collected yet")).jpEyebrow().foregroundStyle(WebTheme.accent)
            Text(c.name).font(JPFont.rowTitle).foregroundStyle(WebTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if let part {
                Text(part.unlock.how).font(JPFont.footnote).foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .locked(let have, let need) = c.state {
                HStack(spacing: 8) {
                    CamperProgressBar(fraction: c.fraction)
                    Text("\(min(have, need)) / \(need)")
                        .font(JPFont.number(12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(WebTheme.accent)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("いま \(min(have, need)) / \(need)", "\(min(have, need)) of \(need)"))
            }
            HStack(spacing: 4) {
                Button {
                    trial = nil
                } label: {
                    Text(L("見本をやめる", "Stop preview"))
                        .jpSystemFont(14, weight: .semibold)
                        .foregroundStyle(WebTheme.foreground)
                        .padding(.trailing, 8)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("camper.room.styleTrialEnd")
                Spacer(minLength: 0)
                // 外まわりの図鑑へ（黒地の上の手がかりなので真鍮）
                if let onCollect, let partId = c.partId {
                    Button {
                        onCollect(partId)
                    } label: {
                        HStack(spacing: 4) {
                            Text(L("外まわりの図鑑で見る", "See it in the parts collection"))
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        .jpSystemFont(14, weight: .semibold)
                        .foregroundStyle(WebTheme.accent)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("camper.room.styleCollect")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camper.room.styleTrial")
    }

    /// 下のボタン（`CamperRoomStyleBoard.footer`）。大きい文字では縦に積む
    @ViewBuilder
    private func styleFooter(_ now: CamperRoomStyle) -> some View {
        switch styleSession.footer(now: now) {
        case .close:
            secondaryButton(L("閉じる", "Close"), id: "camper.room.styleDone") { goHome() }
        case .revertOrKeep:
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { styleFooterButtons }
            } else {
                HStack(spacing: 8) { styleFooterButtons }
            }
        }
    }

    @ViewBuilder
    private var styleFooterButtons: some View {
        secondaryButton(L("元に戻す", "Revert"), id: "camper.room.styleRevert") { revertStyle() }
        primaryButton(L("これにする", "Use this"), id: "camper.room.styleDone", fill: true) { goHome() }
    }

    private func pickStyleTab(_ t: StyleTab) {
        trial = nil
        styleTab = t
        lightTabNight()
    }

    /// 灯りの札の間だけ夜にする（昼に灯りの色を選んでも見えない）。札を離れたら昼に戻す
    private func lightTabNight() {
        if mode == .style, styleTab == .light, mood == .day {
            mood = .night
            autoNight = true
            announce(L("灯りの色が見えるよう夜にしました", "Turned to night so you can see the light"))
        } else if autoNight, mode != .style || styleTab != .light {
            mood = .day
            autoNight = false
        }
    }

    /// 柄を選ぶ。持っている柄はすぐ部屋に映して覚える。持っていない柄は部屋で試すだけ（もう一度押すとやめる）
    private func pickStyle(_ c: CamperRoomStyleChoice) {
        guard c.owned else {
            trial = trial?.key == c.key ? nil : c
            announce(trial == nil ? L("見本をやめました", "Stopped the preview")
                                  : L("\(c.name)を見本で映しています", "Previewing \(c.name)"))
            return
        }
        trial = nil
        guard var e = editor else { return }
        let next = CamperRoomStyleBoard.with(e.doc.style, styleTab, key: c.key)
        guard next != e.doc.style else { return }
        e.setStyle(next)
        editor = e
        save()
    }

    /// 模様替えに入った時の柄へ戻す
    private func revertStyle() {
        trial = nil
        guard let entry = styleSession.entry, var e = editor, e.doc.style != entry else { return }
        e.setStyle(entry)
        editor = e
        save()
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
                    .jpSystemFont(13).foregroundStyle(WebTheme.text2)
                Spacer(minLength: 0)
                primaryButton(L("額を掛ける", "Hang a frame"), id: "camper.room.addFrame", fill: false) {
                    trayTab = .wall
                    trayCategory = .photoFrame
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
                                    .jpSystemFont(13, weight: .semibold)
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
                .accessibilityIdentifier("camper.room.frames")
                let mine = hangablePhotos
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                        ForEach(mine, id: \.id) { p in
                            let on = p.id == photoPick
                            Button {
                                photoPick = p.id
                                // 選んだ瞬間に額へ見本を載せる（「この額に飾る」の前に結果が見える）
                                photoImages.load([p.id], from: photos, force: photoImages.images[p.id] == nil)
                                if let id = framePick, let frame = editor?.doc.item(id) {
                                    animateCamera = true
                                    camera = CamperRoomCamera.framing(frame, layout: layout)
                                }
                            } label: {
                                // 升の大きさを先に決めてから写真を敷く（写真の元の縦横で枠が 100〜178pt に伸び、
                                // 押せる範囲が隣の升と「この額に飾る」に重なっていた・Mac run 672・2026-10-22）
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 68)
                                    .overlay {
                                        AsyncImage(url: p.gridImageURL) { phase in
                                            switch phase {
                                            case .success(let image): image.resizable().scaledToFill()
                                            default: WebTheme.card
                                            }
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .contentShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.white : Color.clear, lineWidth: 3))
                                .overlay(alignment: .topTrailing) {
                                    if on {
                                        Image(systemName: "checkmark.circle.fill").jpSystemFont(18)
                                            .foregroundStyle(Color.black, Color.white).padding(4)
                                    }
                                }
                                .frame(minHeight: WebTheme.minTapTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(p.accessibilityText)
                            // 見本の起動のときだけ写真の id を値に出す（UI テストが額に写ったかと突き合わせる・2026-10-22）
                            .accessibilityValue(PreviewSession.userId != nil ? p.id : "")
                            .accessibilityAddTraits(on ? .isSelected : [])
                            .accessibilityIdentifier("camper.room.photo")
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("camper.room.photoGrid")
                if mine.isEmpty {
                    Text(L("投稿した写真がまだありません", "You haven\u{2019}t posted any photos yet"))
                        .jpSystemFont(13).foregroundStyle(WebTheme.text2)
                }
                // 選んだ写真を読めなかった時は、白い額のまま黙らない（2026-10-21 owner の実機で額が白いまま）
                if let pick = photoPick, photoImages.failed.contains(pick) {
                    Button {
                        photoImages.load([pick], from: photos, force: true)
                    } label: {
                        Text(L("写真を読み込めませんでした。押してもう一度読む", "Couldn\u{2019}t load the photo. Tap to try again"))
                            .jpSystemFont(13).foregroundStyle(WebTheme.danger)
                            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("camper.room.photo.retry")
                }
                // 選んだ写真がもうこの額に入っている時は押せない（何も変わらないのに主ボタンが光らない・2026-10-22 owner）
                let hung = photoPick != nil && framePick.flatMap { editor?.doc.item($0)?.p } == photoPick
                let idle = framePick == nil || photoPick == nil || hung
                primaryButton(hung ? L("この写真を飾っています", "This photo is up") : L("この額に飾る", "Hang it here"),
                              id: "camper.room.hang", fill: false) {
                    guard let frame = framePick, let photo = photoPick, var e = editor else { return }
                    e.setPhoto(frame, photoId: photo)
                    editor = e
                    save()
                    // 飾った直後に印画が無いと「反映されない」に見えるので、失敗していても読み直す
                    photoImages.load([photo], from: photos, force: true)
                    if let updated = e.doc.item(frame) { look(at: updated) }
                    flash(L("この額に飾りました", "Hung on this frame"))
                }
                .disabled(idle)
                .opacity(idle ? 0.5 : 1)
            }
        }
    }

    // MARK: 部品

    /// 置く場所・模様替えの札（選んでいる札は真鍮の字と下線・黒地の上）
    private func tabs(_ items: [(String, String)], selected: String, label: String, pick: @escaping (String) -> Void) -> some View {
        // 大きい文字で横に並びきらない時は横に送る（名前を縮めない・2026-10-22）
        ViewThatFits(in: .horizontal) {
            tabRow(items, selected: selected, pick: pick)
            ScrollView(.horizontal, showsIndicators: false) { tabRow(items, selected: selected, pick: pick) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func tabRow(_ items: [(String, String)], selected: String, pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                let on = item.0 == selected
                Button { pick(item.0) } label: {
                    Text(item.1)
                        .jpSystemFont(14, weight: .semibold)
                        .foregroundStyle(on ? WebTheme.accent : WebTheme.muted2)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .overlay(alignment: .bottom) { Rectangle().fill(on ? WebTheme.accent : Color.clear).frame(height: 2) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("camper.room.tab.\(item.0)")
            }
            Spacer(minLength: 0)
        }
    }

    /// 副ボタン（線だけ・白の字）。変えていない時の「閉じる」・「元に戻す」
    private func secondaryButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .jpSystemFont(16, weight: .semibold)
                .foregroundStyle(WebTheme.foreground)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 50)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// 主ボタン（写真の無い画面は真鍮の塗りに墨の字・写真の並ぶ画面は白）
    private func primaryButton(_ title: String, id: String, fill brass: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .jpSystemFont(16, weight: .semibold)
                .foregroundStyle(brass ? WebTheme.accentText : Color.black)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)
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
                Image(systemName: "door.left.hand.open").jpSystemFont(15, weight: .semibold)
                Text(L("中に入る", "Step inside")).jpSystemFont(15, weight: .semibold)
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

/// 読み上げの手がかり（無い時は付けない。空の文字を渡すと空の手がかりが付く）
struct CamperRoomOptionalHint: ViewModifier {
    let hint: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

/// 模様替えの見本の四角（貼り絵に色を掛けた小さな絵）
///
/// 2026-10-28 判断: **貼り絵は画面の処理の外で描く**（`draw` を `Task.detached` で）。描き直しの中で
/// 256px の貼り絵を描いていたので、模様替えの札を開くと見本の数だけ画面が止まっていた。描き上がるまでは
/// 素材の色（貼り絵が無い見本と同じ地）を出す。同じ絵を二重に描かない（描いている途中は待つ）——
/// 家具の小さな絵（`CamperRoomThumbs`）と同じ作り
struct CamperRoomSwatch: View {
    let spec: CamperMaterialSpec
    let have: Bool

    /// 作った見本の絵（貼り絵を描くのは重いので、描き直しのたびに作らない）
    @MainActor private static var cache: [String: UIImage] = [:]
    @MainActor private static var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// 試験用: 貼り絵を描いた回数
    @MainActor private(set) static var renderCount = 0

    /// 描き上がった絵と、その鍵（見本が替わったら古い絵を出さない）
    @State private var loaded: Loaded?

    private struct Loaded {
        let key: String
        let image: UIImage
    }

    /// 貼り絵の鍵。持っていない・貼り絵の無い見本は nil（色だけ）
    private var textureKey: String? {
        guard have, let kind = spec.texture else { return nil }
        return CamperScenePlan.textureKey(kind, spec.color)
    }

    /// 絵を返す（控えに無ければ画面の処理の外で描く。同じ絵を描いている途中なら、それを待つ）
    @MainActor static func image(_ kind: CamperTextureKind, _ color: UInt32) async -> UIImage? {
        let key = CamperScenePlan.textureKey(kind, color)
        if let hit = cache[key] { return hit }
        if let running = inFlight[key] { return await running.value }
        renderCount += 1
        let task = Task { () -> UIImage? in
            let bitmap = await Task.detached(priority: .userInitiated) { draw(kind, color) }.value
            guard let cg = CamperScenePalette.cgImage(bitmap) else { return nil }
            return UIImage(cgImage: cg)
        }
        inFlight[key] = task
        let made = await task.value
        inFlight[key] = nil
        if let made { cache[key] = made }
        return made
    }

    /// 貼り絵を描く（重い。画面の処理の外で呼ぶ）
    nonisolated static func draw(_ kind: CamperTextureKind, _ color: UInt32) -> CamperBitmap {
        CamperTextures.make(kind).tinted(color)
    }

    var body: some View {
        let key = textureKey
        Group {
            if let key, let image = Self.cache[key] ?? (loaded?.key == key ? loaded?.image : nil) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                CamperStyle.color(have ? spec.color : 0x1A1A1A)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
        .task(id: key) {
            guard let key, let kind = spec.texture, Self.cache[key] == nil else { return }
            if let image = await Self.image(kind, spec.color) { loaded = Loaded(key: key, image: image) }
        }
    }
}

/// 二度押しの見分け（2026-10-21）: 0.35 秒のうちに、44pt の内で 2 回
enum CamperRoomTaps {
    static let interval = 0.35
    static let radius = 44.0

    static func isDouble(last: Date, lastPoint: CGPoint, now: Date, point: CGPoint) -> Bool {
        guard now.timeIntervalSince(last) < interval else { return false }
        let dx = Double(point.x - lastPoint.x), dy = Double(point.y - lastPoint.y)
        return (dx * dx + dy * dy).squareRoot() < radius
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
