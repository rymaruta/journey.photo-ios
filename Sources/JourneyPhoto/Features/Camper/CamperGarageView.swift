import SwiftUI

/// 写真で作るキャンピングカー（板「写真で作るキャンピングカー」の 1 自分のキャンピングカー・5 車が育つ・6 部品のコレクション）。
///
/// 上に立体の車（指で回す・2本の指で寄る・2度たたくと初めの向き）、下に時刻・段・集めた部品。
/// 第1段（2026-10-18）はサーバーを変えない: 段も部品の「持っている／まだ」も、自分の投稿からこの端末で数える
/// （`CamperCounting`）。付けた部品は人ごとにこの端末へ覚える（`CamperStore`）。
/// 第2段（2026-10-19）: 要サーバーの 33 個は `GET /user/camper` の部品を足す（`CamperServerModel`）。読めて配り始めて
/// いる間だけ分母が 131 になり、読めない・始まっていない間は端末の数え方のまま（分母 98・「近日」）。
struct CamperGarageView: View {
    let ownerName: String?
    let userId: String?
    /// 自分の写真の一覧（下書きを含む。数えるのは `CamperCounting.count` が公開した写真だけ）
    let photos: [Photo]
    /// 写真を一度でも読めたか。読めるまでは「届いた」の判定も保存もしない（2026-10-18 #312 の見直し:
    /// 読み込み前に開くと、数が 0 で飾りが外れ、「届いた」がもう一度出た）
    let photosLoaded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 文字の大きさの設定。アクセシビリティの大きさでは横に並べた札を縦に積む（2026-10-21 判断）
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var environment: AppEnvironment
    /// 要サーバーの部品（`GET /user/camper`）。読めない間は何も足さない
    @StateObject private var server = CamperServerModel()
    /// 付けている飾り（保存する値は外さない・`CamperGarageEditor`）
    @State private var editor = CamperGarageEditor()
    private var loadout: CamperLoadout { editor.loadout }
    @State private var loaded = false
    @State private var mood: CamperMood = .day
    @State private var angle = CamperFraming.overview(.camper)
    @State private var animateAngle = false
    @State private var dragStart: CamperAngle?
    @State private var pinchStart: CamperAngle?
    @State private var doorOpen = false
    /// 見本で見ている段（まだ着いていない段も見られる）
    @State private var previewStage: CamperStage?
    /// まだ持っていない部品を影絵で見ている
    @State private var previewPart: CamperPart?
    @State private var group: CamperGroupKind = .ext
    @State private var category: CamperCategory = .wheel
    /// 届いた部品（一度に 3 個まで・板の付箋）
    @State private var arrival: CamperArrivals?
    @State private var readyMarker = ""
    /// 数えた結果（マイページの描き直しのたびに数えない。この画面の中で、写真が変わった時だけ数える）
    @State private var stats = CamperStats()
    @State private var arrivalChecked = false

    private var store: CamperStore { CamperStore(userId: userId) }
    private var owned: Set<String> { CamperCatalog.owned(stats, server: server.parts) }
    private var serverOpen: Bool { server.parts.open }
    private var dex: (have: Int, total: Int) { CamperCatalog.dexCount(owned, serverOpen: serverOpen) }
    private var actualStage: CamperStage { CamperStage.stage(books: stats.books) }
    private var stage: CamperStage { previewStage ?? actualStage }

    /// 画面に出す飾り（持っていない部品は外して見せる）。**保存する値（`loadout`）は外さない**——数え直しの途中や
    /// 写真を読む前に外して保存すると、選んだ部品が消える
    private var worn: CamperLoadout { editor.worn(owned: owned) }

    /// 数え直す目印（写真の数・先頭と最後の id・読めたか）
    private var countKey: Int { CamperCounting.countKey(photos, loaded: photosLoaded) }

    private var config: CamperConfig {
        var shown = worn
        if let previewPart { shown.pick(previewPart) }
        return CamperConfig(stage: stage, mood: mood, loadout: shown, posts: stats.posts, silhouette: previewPart?.category)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                stageView(width: geo.size.width, height: min(360, max(220, geo.size.width * 0.9), geo.size.height * 0.46))
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        moods
                        statsRow
                        stagesRow
                        collection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .background { backdrop }
        .navigationTitle(L("キャンピングカー", "Camper"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .task(id: countKey) { recount() }
        .task(id: userId) { await loadServer() }
        .onChange(of: server.settled) { _, _ in checkArrivals() }
        .sheet(item: $arrival) { batch in
            CamperArrivalView(parts: batch.parts, giver: { server.parts.giverName($0) }, collected: dex.have, total: dex.total,
                              onEquip: { part in
                                  equip(part)
                                  arrival = nil
                              }, onClose: { arrival = nil })
        }
    }

    // MARK: 読み込み

    private func load() {
        guard !loaded else { return }
        loaded = true
        // 覚えている飾りはそのまま持つ（外すのは見せる時だけ・`worn`）
        editor.open(store)
        angle = CamperFraming.overview(actualStage)
    }

    /// 写真から数え直す。写真を一度でも読めたら、新しく届いた部品を一度だけ見せる
    private func recount() {
        let before = actualStage
        stats = CamperCounting.count(photos)
        if actualStage != before, previewStage == nil, !doorOpen { angle = CamperFraming.overview(actualStage) }
        checkArrivals()
    }

    /// 要サーバーの部品を読む（見本の起動ではサーバーに送らず見本を使う）
    private func loadServer() async {
        let service = environment.camper
        await server.load(userId: userId, store: store) {
            if PreviewSession.camperSample { return CamperServerSample.mine }
            return try await service.mine()
        }
    }

    /// 届いた部品を見せる。**写真を読めて、サーバーの答えも出てから**（読めた・読めなかった）一度だけ。
    /// 一度に 3 個まで（板の付箋）。サーバーのこの回に届いた分・写真の保存で届いた分を先に（2026-10-19 第2段）
    private func checkArrivals() {
        guard photosLoaded, server.settled, !arrivalChecked else { return }
        arrivalChecked = true
        let fresh = store.openArrivals(owned: owned, photosLoaded: photosLoaded, first: server.parts.freshFirst,
                                       limit: CamperArrivals.limit)
        server.noteShown(store: store)
        if !fresh.isEmpty, PreviewSession.userId == nil || ProcessInfo.processInfo.arguments.contains("-JPPreviewCamperArrival") {
            arrival = CamperArrivals(parts: fresh)
        }
    }

    private func equip(_ part: CamperPart) {
        guard editor.equip(part, owned: owned, store: store) else { return }
        previewPart = nil
    }

    // MARK: 見出し

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CamperText.eyebrow(owner: ownerName, stage: actualStage))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .lineLimit(1)
            // 見出しは車の名前（板 Main: 眉ラベル「〜の車 · 段」の下に「とおまわり号」）
            Text(CamperText.carName)
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(L("旅を重ねるほど車が育ち、撮るほど部品が集まります", "It grows with your trips; parts arrive as you shoot"))
                .font(.caption)
                .foregroundStyle(WebTheme.muted2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: 立体の車

    /// とおまわり号の中へ入った（2026-10-19・`CamperRoomView`）
    @State private var insideRoom = false

    /// 中に入る（扉が開いて口へ寄ってから、室内の画面へ。「視差効果を減らす」ではすぐ）
    private func goInside() {
        if !doorOpen { toggleDoor() }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(nanoseconds: 650_000_000) }
            insideRoom = true
        }
    }

    private func stageView(width: CGFloat, height: CGFloat) -> some View {
        CamperSceneView(config: config, angle: angle, animateAngle: animateAngle, doorOpen: doorOpen, reduceMotion: reduceMotion) { marker in
            readyMarker = marker
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(rotate)
        .simultaneousGesture(zoom)
        .onTapGesture(count: 2) { aim(CamperFraming.overview(stage)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CamperText.accessibilityLabel(stage: stage, mood: mood, loadout: config.loadout, doorOpen: doorOpen,
                                                          preview: previewPart))
        .accessibilityAddTraits(.isImage)
        .accessibilityValue(PreviewSession.userId != nil ? readyMarker : "")
        .accessibilityAction(named: doorOpen ? L("扉を閉じる", "Close the door") : L("扉を開ける", "Open the door")) { toggleDoor() }
        .accessibilityAction(named: L("右へ回す", "Turn right")) { turn(by: 45) }
        .accessibilityAction(named: L("左へ回す", "Turn left")) { turn(by: -45) }
        .accessibilityIdentifier("camper.scene")
        .overlay(alignment: .bottomTrailing) { sceneButtons }
        .overlay(alignment: .bottomLeading) { CamperRoomEntrance(action: goInside).padding(12) }
        .navigationDestination(isPresented: $insideRoom) {
            CamperRoomView(ownerName: ownerName, userId: userId, photos: photos, photosLoaded: photosLoaded, stage: actualStage, stats: stats,
                           paint: config.loadout.paint, initialMood: mood)
        }
        .overlay(alignment: .top) {
            if previewStage != nil && previewStage != actualStage || previewPart != nil {
                Text(previewPart != nil ? L("まだ持っていない部品 · 見本", "Not yet collected · preview") : L("まだ先 · 見本", "Not yet · preview"))
                    .font(JPFont.caption.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(WebTheme.accentSoft, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityIdentifier("camper.previewBadge")
            }
        }
    }

    private var rotate: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStart ?? angle
                if dragStart == nil { dragStart = angle }
                animateAngle = false
                angle = CamperFraming.dragged(start, dx: Double(value.translation.width), dy: Double(value.translation.height))
            }
            .onEnded { value in
                guard let start = dragStart else { return }
                dragStart = nil
                // 惰性（離した勢いの 35%。「視差効果を減らす」ではそのまま止める）
                let extra = reduceMotion ? 0 : Double(value.predictedEndTranslation.width - value.translation.width) * 0.35
                animateAngle = !reduceMotion
                angle = CamperFraming.dragged(start, dx: Double(value.translation.width) + extra, dy: Double(value.translation.height))
            }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? angle
                if pinchStart == nil { pinchStart = angle }
                animateAngle = false
                angle = CamperFraming.pinched(start, scale: Double(value.magnification))
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func aim(_ a: CamperAngle) {
        animateAngle = true
        angle = a
    }

    private func turn(by degrees: Double) {
        var a = angle
        a.yaw += degrees
        aim(a)
    }

    private func toggleDoor() {
        doorOpen.toggle()
        // 開けたら扉の口から室内へ寄る。閉じたら初めの向きへ戻す（寄ったまま夜や段を見ない）
        if doorOpen {
            aim(CamperFraming.door(stage))
        } else if angle == CamperFraming.door(stage) {
            aim(CamperFraming.overview(stage))
        }
    }

    private var sceneButtons: some View {
        HStack(spacing: 8) {
            sceneButton(doorOpen ? "door.left.hand.open" : "door.left.hand.closed",
                        label: doorOpen ? L("扉を閉じる", "Close the door") : L("扉を開ける", "Open the door"),
                        id: "camper.door") { toggleDoor() }
            if stage != .van {
                sceneButton("beach.umbrella", label: loadout.awningOpen ? L("オーニングを畳む", "Stow the awning") : L("オーニングを広げる", "Open the awning"),
                            id: "camper.awning") {
                    editor.setAwning(!loadout.awningOpen, store: store)
                }
            }
            sceneButton("arrow.counterclockwise", label: L("初めの向きに戻す", "Reset the view"), id: "camper.reset") {
                aim(CamperFraming.overview(stage))
            }
        }
        .padding(12)
    }

    private func sceneButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .jpGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: 時刻・数・段

    private var moods: some View {
        HStack(spacing: 8) {
            ForEach(CamperMood.allCases, id: \.self) { m in
                Button { mood = m } label: {
                    Text(m.name)
                        .jpSystemFont(14, weight: m == mood ? .semibold : .regular, relativeTo: .subheadline)
                        .foregroundStyle(m == mood ? CamperStyle.brassLight : WebTheme.text)
                        .frame(minWidth: 60, minHeight: WebTheme.minTapTarget)
                        .padding(.horizontal, 8)
                        .overlay(Capsule().strokeBorder(m == mood ? WebTheme.accent : WebTheme.line, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(m == mood ? .isSelected : [])
                .accessibilityIdentifier("camper.mood.\(m.rawValue)")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("時刻と天気", "Time and weather"))
    }

    /// 3 つの数の札。アクセシビリティの大きさでは縦に積む（横 3 つでは見出しが 1 字ずつ折れ、数が縮んで読めない・2026-10-21）
    @ViewBuilder
    private var statsRow: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 8) { statTiles }
        } else {
            HStack(spacing: 8) { statTiles }
        }
    }

    @ViewBuilder
    private var statTiles: some View {
        statTile(L("集めた部品", "Parts"), "\(dex.have) / \(dex.total)", note: CamperText.dexNote(serverOpen: serverOpen))
        statTile(L("写真", "Photos"), "\(stats.posts)")
        // 数えるのは公開した写真の旅（マイページの旅の棚は非公開も入るので、数が違う人がいる・#312 の見直し）
        statTile(L("公開した旅", "Public trips"), "\(stats.books)")
    }

    private func statTile(_ label: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(JPFont.caption).foregroundStyle(WebTheme.faint)
            Text(value).font(JPFont.number(17, weight: .semibold, relativeTo: .body)).foregroundStyle(WebTheme.foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let note {
                Text(note).font(JPFont.number(12, weight: .regular, relativeTo: .caption)).foregroundStyle(WebTheme.faint)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var stagesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("車が育つ", "Your camper grows")).jpEyebrow().foregroundStyle(WebTheme.accent)
            // アクセシビリティの大きさでは段を縦に積む（横 3 つでは「キャンピングカー」が切れる・2026-10-21）
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { stageButtons }
            } else {
                HStack(spacing: 8) { stageButtons }
            }
        }
    }

    private var stageButtons: some View {
        ForEach(CamperStage.allCases, id: \.self) { s in
            let reached = s.requiredBooks <= stats.books
            let on = s == stage
            Button {
                previewStage = s == actualStage ? nil : s
                doorOpen = false
                aim(CamperFraming.overview(s))
            } label: {
                VStack(spacing: 2) {
                    Text(s.name)
                        .jpSystemFont(14, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(s == actualStage ? CamperStyle.brassLight : (reached ? WebTheme.text : WebTheme.muted2))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(s == actualStage ? L("いま", "Now")
                         : (reached ? L("通ってきた", "Passed") : L("あと \(s.requiredBooks - stats.books) 冊", "\(s.requiredBooks - stats.books) more trips")))
                        .font(JPFont.number(12, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(s == actualStage ? WebTheme.accent : WebTheme.faint)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(s == actualStage ? WebTheme.accentSoft : WebTheme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(on ? WebTheme.accent : (reached ? WebTheme.hairline : WebTheme.line),
                                  style: StrokeStyle(lineWidth: 1, dash: reached || on ? [] : [4, 3])))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityHint(reached ? "" : L("まだ先の段を見本で見ます", "Preview a stage you haven't reached"))
            .accessibilityIdentifier("camper.stage.\(s.rawValue)")
        }
    }

    // MARK: 部品のコレクション

    private var collection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 横に入らない大きさ（文字の大きさの設定）では、数を眉ラベルの下へ回す（2026-10-21）
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(CamperText.partsTitle).jpEyebrow().foregroundStyle(WebTheme.accent)
                    Spacer()
                    collectionCount
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(CamperText.partsTitle).jpEyebrow().foregroundStyle(WebTheme.accent)
                    collectionCount
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(CamperGroupKind.allCases, id: \.self) { g in
                        Button {
                            group = g
                            if let first = CamperCategory.allCases.first(where: { $0.group == g }) { pickCategory(first) }
                        } label: {
                            Text(g.name)
                                .jpSystemFont(14, weight: .semibold, relativeTo: .subheadline)
                                .foregroundStyle(g == group ? CamperStyle.brassLight : WebTheme.muted2)
                                .padding(.horizontal, 10)
                                .frame(minHeight: WebTheme.minTapTarget)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(g == group ? WebTheme.accent : Color.clear).frame(height: 2)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(g == group ? .isSelected : [])
                        .accessibilityIdentifier("camper.group.\(g.rawValue)")
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CamperCategory.allCases.filter { $0.group == group }, id: \.self) { c in
                        let (have, total) = CamperCatalog.categoryCount(c, owned: owned, serverOpen: serverOpen)
                        Button { pickCategory(c) } label: {
                            HStack(spacing: 6) {
                                // 選んでいる分類は色だけでなく印の形でも示す（#312 の見直し）
                                Image(systemName: c == category ? "checkmark" : c.symbol).font(JPFont.footnote.weight(c == category ? .bold : .regular))
                                Text(c.name).font(JPFont.footnote.weight(.semibold)).lineLimit(1)
                                Text("\(have)/\(total)").font(JPFont.number(12, weight: .regular, relativeTo: .caption))
                                    .foregroundStyle(WebTheme.faint)
                            }
                            .foregroundStyle(c == category ? CamperStyle.brassLight : WebTheme.text)
                            .padding(.horizontal, 12)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .background(c == category ? WebTheme.accentSoft : WebTheme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(c == category ? WebTheme.accent : Color.clear, lineWidth: c == category ? 2 : 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(c == category ? .isSelected : [])
                        .accessibilityIdentifier("camper.category.\(c.rawValue)")
                    }
                }
            }
            partsGrid
            if let previewPart {
                howToGet(previewPart)
            }
        }
    }

    private var collectionCount: some View {
        Text("\(dex.have) / \(dex.total) · \(CamperText.dexNote(serverOpen: serverOpen))")
            .font(JPFont.number(13, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(WebTheme.text)
    }

    private func pickCategory(_ c: CamperCategory) {
        category = c
        group = c.group
        previewPart = nil
        if c == .awning, !loadout.awningOpen { editor.setAwning(true, store: nil) }
        aim(CamperFraming.focus(c, stage: stage))
    }

    private var partsGrid: some View {
        let parts = CamperCatalog.parts(category)
        // アクセシビリティの大きさでは 2 列（3 列では部品の名前が 1 字ずつ折れる・2026-10-21）
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            if category.optional {
                let on = worn.key(category) == CamperLoadout.none && previewPart == nil
                Button {
                    previewPart = nil
                    editor.remove(category, store: store)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "nosign").font(.system(size: 22)).foregroundStyle(WebTheme.muted2)
                        Text(L("付けない", "None")).font(JPFont.caption).foregroundStyle(WebTheme.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .background(on ? WebTheme.accentSoft : WebTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? WebTheme.accent : WebTheme.hairline, lineWidth: on ? 2 : 1))
                    .overlay(alignment: .topTrailing) { if on { CamperSelectedMark() } }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("camper.part.none")
            }
            ForEach(parts) { part in
                partCard(part)
            }
        }
    }

    private func partCard(_ part: CamperPart) -> some View {
        let have = owned.contains(part.id)
        let on = previewPart?.id == part.id || (previewPart == nil && worn.key(part.category) == part.key)
        return Button {
            if have {
                equip(part)
            } else {
                previewPart = part
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: part.category.symbol)
                        .font(.system(size: 24))
                        .foregroundStyle(have ? WebTheme.foreground : WebTheme.faint)
                    if let swatch = part.swatch {
                        Circle().fill(CamperStyle.color(swatch)).frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Color.black, lineWidth: 1))
                            .opacity(have ? 1 : 0.3)
                            .offset(x: 6, y: 4)
                    }
                }
                .frame(height: 30)
                Text(have ? part.name : L("？？？", "???"))
                    .font(JPFont.caption)
                    .foregroundStyle(have ? WebTheme.text : WebTheme.faint)
                    .multilineTextAlignment(.center)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                    .minimumScaleFactor(0.85)
                CamperRarityDots(rarity: part.rarity)
                if !have {
                    if part.unlock.isAvailable {
                        CamperProgressBar(fraction: part.unlock.fraction(stats))
                            .padding(.horizontal, 8)
                    } else if serverOpen, part.unlock.isServer {
                        // 要サーバー（第2段）: 記録で決まる部品だけ棒を出す（写真で決まる部品は「まだ」の点線だけ）
                        if let p = CamperServerRule.progress(part.id, server.parts.progress) {
                            CamperProgressBar(fraction: Double(p.have) / Double(max(1, p.need)))
                                .padding(.horizontal, 8)
                        }
                    } else {
                        // 要サーバー（第1段では届かない）。数の分母にも入れない
                        Text(L("近日", "Soon"))
                            .font(JPFont.caption.weight(.semibold))
                            .foregroundStyle(WebTheme.accent)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(on ? WebTheme.accentSoft : WebTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(on ? WebTheme.accent : (have ? WebTheme.hairline : WebTheme.line),
                              style: StrokeStyle(lineWidth: on ? 2 : 1, dash: have || on ? [] : [3, 3])))
            // 付けている部品は色だけでなくチェックの印でも示す（#312 の見直し）
            .overlay(alignment: .topTrailing) { if on { CamperSelectedMark() } }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CamperText.partLabel(part, owned: have, stats: stats, server: server.parts))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("camper.part")
    }

    private func howToGet(_ part: CamperPart) -> some View {
        let p = part.unlock.progress(stats)
        return VStack(alignment: .leading, spacing: 6) {
            Text(part.name).font(JPFont.rowTitle).foregroundStyle(WebTheme.foreground)
            Text(part.look).font(JPFont.footnote).foregroundStyle(WebTheme.muted2)
            Text(part.unlock.how(serverOpen: serverOpen)).font(JPFont.footnote).foregroundStyle(WebTheme.text)
            if part.unlock.isAvailable {
                HStack(spacing: 8) {
                    CamperProgressBar(fraction: part.unlock.fraction(stats))
                    Text("\(p.have) / \(p.need)").font(JPFont.number(12, weight: .semibold, relativeTo: .caption)).foregroundStyle(WebTheme.accent)
                }
            } else if serverOpen, let sp = CamperServerRule.progress(part.id, server.parts.progress) {
                HStack(spacing: 8) {
                    CamperProgressBar(fraction: Double(sp.have) / Double(max(1, sp.need)))
                    Text("\(sp.have) / \(sp.need)").font(JPFont.number(12, weight: .semibold, relativeTo: .caption)).foregroundStyle(WebTheme.accent)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("camper.howToGet")
    }

    private var backdrop: some View {
        RadialGradient(colors: [CamperStyle.color(CamperMaterials.backdrop(mood)), Color.black],
                       center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 520)
            .ignoresSafeArea()
    }
}

/// 選んでいる印（真鍮の丸にチェック・黒地の上だけ）。色だけで選択を示さないための形
struct CamperSelectedMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(WebTheme.accent, Color.black)
            .padding(6)
            .accessibilityHidden(true)
    }
}

/// 珍しさの印（真鍮の四角 4 つ・黒地の上だけ）
struct CamperRarityDots: View {
    let rarity: CamperRarity

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i <= rarity.rawValue ? WebTheme.accent : CamperStyle.color(0x333333))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rarity.name)
    }
}

/// 一度に届いた部品（届いた画面に出す束・最大 3 個）
struct CamperArrivals: Identifiable, Equatable {
    /// 板の付箋「同じ写真で一度に届くのは 3 個まで（届いた画面が続きすぎない）」
    static let limit = 3

    let parts: [CamperPart]
    var id: String { parts.map(\.id).joined(separator: ",") }

    init(parts: [CamperPart]) { self.parts = Array(parts.prefix(Self.limit)) }
}

/// 部品が届いたときの画面（板 CamperGet: 光の輪・名前・届いた理由・いま車に付ける）。
/// 2026-10-19 第2段: 一度に 3 個まで。大きく出すのは1つで、ほかは下の札（押すと大きく出す方を替える）。
/// 贈り物で届いた部品は「〜から贈られました」（`CamperText.because`）
struct CamperArrivalView: View {
    let parts: [CamperPart]
    /// 贈ってくれた人の名前（贈り物でなければ nil・名前の無い人は空の字）
    var giver: (String) -> String? = { _ in nil }
    let collected: Int
    let total: Int
    let onEquip: (CamperPart) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = 0

    private var part: CamperPart { parts[min(max(0, selected), parts.count - 1)] }

    var body: some View {
        VStack(spacing: 16) {
            // 部品の絵と説明は送れる枠に入れる（3 個届いた回に縦が足りず、下のボタンが押しつぶされて「あとで」の当たりが
            // 18pt になった・2026-10-19 Mac run 561）。下の2つのボタンはいつも決まった高さ
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 16) {
                    ZStack {
                        // 光の輪（板: 24 秒で 1 回転。「視差効果を減らす」では止める）
                        TimelineView(.animation(paused: reduceMotion)) { context in
                            let t = context.date.timeIntervalSinceReferenceDate
                            Circle()
                                .fill(AngularGradient(colors: [WebTheme.accent.opacity(0.35), Color.clear, WebTheme.accent.opacity(0.25), Color.clear,
                                                               WebTheme.accent.opacity(0.35)], center: .center,
                                                      startAngle: .degrees(0), endAngle: .degrees(360)))
                                .frame(width: 220, height: 220)
                                .rotationEffect(.degrees(reduceMotion ? 0 : (t.truncatingRemainder(dividingBy: 24)) / 24 * 360))
                        }
                        Image(systemName: part.category.symbol)
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(WebTheme.foreground)
                    }
                    .accessibilityHidden(true)
                    VStack(spacing: 12) {
                        Text(parts.count > 1 ? L("部品が \(parts.count) 個届いた", "\(parts.count) parts arrived") : L("部品が届いた", "A part arrived"))
                            .jpEyebrow().foregroundStyle(WebTheme.accent)
                        Text(part.name).font(JPFont.screenTitle).foregroundStyle(WebTheme.foreground)
                        CamperRarityDots(rarity: part.rarity)
                        Text(CamperText.because(part, giver: giver(part.id))).font(.subheadline).foregroundStyle(WebTheme.text)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("camper.arrival.because")
                        Text(part.look).font(.footnote).foregroundStyle(WebTheme.muted2).multilineTextAlignment(.center)
                        Text(L("\(part.category.name) · 部品 \(collected) / \(total)", "\(part.category.name) · \(collected) of \(total) parts"))
                            .font(JPFont.number(12, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(WebTheme.faint)
                    }
                        if parts.count > 1 { others }
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
            }
            Button { onEquip(part) } label: {
                Text(L("いま車に付ける", "Put it on now"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(WebTheme.accentFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("camper.arrival.equip")
            Button(action: onClose) {
                Text(L("あとで", "Later"))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                    // 当たりは字だけでなく 44pt の帯全体（2026-10-19 Mac run 561: 当たりが 18pt だった）
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: WebTheme.minTapTarget)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("camper.arrival.close")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.black.ignoresSafeArea() }
    }

    /// 一緒に届いた部品の札（選んでいる札は真鍮の縁とチェックの形・黒地の上）
    private var others: some View {
        VStack(spacing: 8) {
            Text(CamperText.alsoArrived(parts.count - 1)).font(JPFont.caption).foregroundStyle(WebTheme.faint)
            // 名前の長い部品が並んでも画面の外にはみ出さない（横に送る）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { i, p in
                        let on = p.id == part.id
                        Button { selected = i } label: {
                            HStack(spacing: 6) {
                                Image(systemName: on ? "checkmark" : p.category.symbol).font(JPFont.footnote.weight(on ? .bold : .regular))
                                Text(p.name).font(JPFont.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(on ? CamperStyle.brassLight : WebTheme.text)
                            .padding(.horizontal, 12)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .background(on ? WebTheme.accentSoft : WebTheme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? WebTheme.accent : Color.clear, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("camper.arrival.part")
                    }
                }
            }
        }
    }
}

/// 色（キャンピングカーの画面だけで使う真鍮の明るい字・0xRRGGBB の色）
enum CamperStyle {
    /// 板の選択中の字 #F3DCA6
    static let brassLight = color(0xF3DCA6)

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// 進み具合の細い棒（真鍮・板 CamperCatalog）
struct CamperProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WebTheme.surface)
                Capsule().fill(WebTheme.accent).frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
