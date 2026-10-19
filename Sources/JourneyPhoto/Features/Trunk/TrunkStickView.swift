import SwiftUI

/// 自分の手で貼る（モック Stick.dc.html・全画面・2026-10-17 次の版）。
///
/// 手持ちのラベルを押さえて持ち上げ、トランクの上へ運んで離すと、その場所に貼る（置き場はサーバーに保存）。
/// 貼ったラベルは押さえて動かせる（動かすと少しよれる）・2本指で回せる・回すボタンで 8° ずつ。
/// 「ひとつ戻す」は直前の1手（貼る・動かす・はがす）を戻す。「おまかせで並べる」は空いているおまかせの
/// 置き場に、手持ちの新しいものから貼る。「はがして手持ちに戻す」は選んでいる1枚（無ければいちばん新しい1枚）。
///
/// 触覚と音: 貼ったとき。「視差効果を減らす」の人には、貼ったときの弾みと持ち上げの拡大を出さない
struct TrunkStickView: View {
    @ObservedObject var model: TrunkViewModel
    var ownerName: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var auth: AuthStore

    /// 運んでいるラベル
    private struct Carry: Equatable {
        let label: TrunkLabel
        /// 手持ちから（false なら貼ったものを動かしている）
        let fromTray: Bool
        /// 動かす前の置き場（貼ったものだけ）
        let from: TrunkPos?
        var x: Double
        var y: Double
    }

    /// 戻せる1手
    private enum Step: Equatable {
        case stuck(String)
        case moved(String, from: TrunkPos)
        case unstuck(String, pos: TrunkPos?)
    }

    @State private var carry: Carry?
    /// 手持ちの札を押さえてから、縦に動かしたか（横なら並びを送る）
    @State private var trayIntent: [String: Bool] = [:]
    @State private var selectedId: String?
    /// 保存を待っている置き場（ラベルごと・回した・動かした）。画面の上にはこれを出す（`TrunkPlaceCommitter`）
    @StateObject private var places = TrunkPlaceCommitter()
    /// 貼るのを待っている1枚（応答の前から、離した所に出す）
    @State private var pendingStick: TrunkLabel?
    @State private var steps: [Step] = []
    @State private var pop: String?
    @State private var popScale = 1.0
    @State private var stickTicks = 0
    @State private var wrinkles: [String: Double] = [:]
    /// 2本指で回し始めたときの置き場
    @State private var rotateBase: TrunkPos?
    /// 2本指で回している最中（運ぶ方を始めない）。取り消されても必ず下がるよう `@GestureState`
    @GestureState private var rotating = false
    /// 2本指で回し始めたラベル（指を離したら、これを送る）
    @State private var rotatingId: String?
    /// 今の1本目の指の間に2本指で回した（離したときに「押しただけ」で選び直さない）
    @State private var rotatedDuringDrag = false
    /// トランクの上を1本目の指で押さえている最中（2本指のあとの離しを見分ける）
    @GestureState private var dragging = false
    /// 「完了」で送っている最中
    @State private var saving = false
    /// 「完了」で送れなかった（もう一度・保存せずに閉じる を選ぶ）
    @State private var showSaveFailed = false

    private let space = "trunk.stick"

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            // モック: 見出し 56 ＋ 28 の下に 360×300。下の札と手持ちの並びに 330 を残して縮める
            let layout = TrunkStickLayout(width: width, top: 84, maxHeight: max(180, Double(geo.size.height) - 84 - 330))
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    header
                    trunkArea(layout, width: width)
                        .padding(.top, 28)
                    controls
                        .padding(.top, 10)
                    trayHeader
                        .padding(.top, 14)
                    tray(layout)
                        .padding(.top, 10)
                    if let error = model.actionError {
                        Text(error)
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                    Spacer(minLength: 8)
                    bottomButtons
                }
                carryPreview(layout)
            }
            .coordinateSpace(.named(space))
        }
        .background { TrunkStyle.stageBackground(centerY: 0.34) }
        .sensoryFeedback(.impact(weight: .medium), trigger: stickTicks)
        .task {
            places.bind(model)
            places.onSaved = { id, from in steps.append(.moved(id, from: from)) }
            wrinkles = TrunkWrinkles(userId: auth.userId).strengths
            if model.state == nil { await model.load(offline: false) }
        }
        .onDisappear {
            places.sendLeftovers()
            // 画面を抱え込まない（`.task` で付けた「ひとつ戻す」への積み）
            places.onSaved = nil
        }
        // 2本指が取り消されても（onEnded が来なくても）回した1枚を送ってから、印を全部下げる
        .onChange(of: rotating) { _, now in
            guard !now else { return }
            if let id = rotatingId { places.schedule(id, delay: 0) }
            rotatingId = nil
            rotateBase = nil
            if !dragging { rotatedDuringDrag = false }
        }
        .onChange(of: dragging) { _, now in
            // 1本目が離れた・取り消された: 離しの処理（onEnded）のあとで下げる
            guard !now else { return }
            Task { @MainActor in rotatedDuringDrag = false }
        }
        .confirmationDialog(L("置き場を保存できませんでした", "Couldn\u{2019}t save where your labels are"),
                            isPresented: $showSaveFailed, titleVisibility: .visible) {
            Button(L("もう一度", "Try again")) { Task { await finish() } }
            Button(L("保存せずに閉じる", "Close without saving")) {
                // 溜まった置き場は送らない（トランクは元の置き場で描く）
                places.discardAll()
                dismiss()
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(model.actionError ?? TrunkText.placeNotSaved)
        }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.stick")
    }

    private var state: TrunkState? { model.state }

    /// 画面の上だけで動かしている置き場（保存を待っている分）
    private var overrides: [String: TrunkPos] { places.overrides }

    /// 「完了」: 溜まった置き場を送ってから閉じる。送れなければ閉じずに、もう一度か保存せずに閉じるかを聞く
    private func finish() async {
        saving = true
        let ok = await places.flush()
        saving = false
        if ok { dismiss() } else { showSaveFailed = true }
    }

    /// 描く貼ったラベル（待っている1枚を先頭に）
    private var stuck: [TrunkLabel] {
        let base = state?.stuck ?? []
        guard let pendingStick, !base.contains(where: { $0.id == pendingStick.id }) else { return base }
        return [pendingStick] + base
    }

    /// 手持ち（待っている1枚と運んでいる1枚は薄く）
    private var pocket: [TrunkLabel] {
        (state?.pocket ?? []).filter { $0.id != pendingStick?.id }
    }

    /// 回す・はがす相手（選んでいる1枚。無ければいちばん新しい1枚）
    private var target: TrunkLabel? {
        if let selectedId, let label = stuck.first(where: { $0.id == selectedId }) { return label }
        return stuck.first
    }

    // MARK: 見出し

    private var header: some View {
        ZStack {
            Text(L("ラベルを貼る", "Stick labels"))
                .font(.headline)
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button { Task { await undo() } } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(steps.isEmpty ? WebTheme.outline : WebTheme.text)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(steps.isEmpty || model.busy)
                .accessibilityLabel(L("ひとつ戻す", "Undo"))
                .accessibilityIdentifier("trunk.stick.undo")
                Spacer()
                Button {
                    // 回して間もなく閉じても、溜まった置き場を送ってから閉じる。送れなければ閉じずに一言
                    Task { await finish() }
                } label: {
                    HStack(spacing: 6) {
                        if saving {
                            ProgressView()
                                .tint(WebTheme.accent)
                            Text(L("保存しています", "Saving"))
                                .font(.subheadline)
                                .foregroundStyle(WebTheme.accent)
                        } else {
                            Text(L("完了", "Done"))
                                .font(.headline)
                                .foregroundStyle(WebTheme.accent)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .accessibilityIdentifier("trunk.stick.done")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 56)
    }

    // MARK: トランク

    private func trunkArea(_ layout: TrunkStickLayout, width: Double) -> some View {
        let s = state
        let size = layout.size
        return ZStack(alignment: .topLeading) {
            if let s {
                TrunkBoxView(model: s.effectiveModel, posts: s.posts ?? 0, stuck: stuck, ownerName: ownerName,
                             parts: s.equipped, overrides: overrides, hidden: carry.flatMap { $0.fromTray ? nil : $0.label.id },
                             wrinkles: wrinkles, pop: pop, popScale: popScale)
                    .scaleEffect(layout.scale, anchor: .topLeading)
                    .frame(width: size.w, height: size.h, alignment: .topLeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(TrunkText.accessibilityLabel(model: s.effectiveModel,
                                                                     labels: TrunkPlacement.layout(stuck, stage: 0).count,
                                                                     tags: TrunkLooks.tags(stuck: stuck, posts: s.posts ?? 0).count,
                                                                     equipped: s.equipped))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("trunk.stick.trunk")
                selection(layout)
                ghost(layout)
            } else {
                JPLoadingState(kind: .rows).frame(width: size.w, height: size.h)
            }
        }
        .frame(width: size.w, height: size.h, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(trunkDrag(layout))
        .simultaneousGesture(rotateGesture)
        .frame(width: width)
    }

    /// 選んでいる1枚の枠（真鍮の破線・回す・はがす相手）
    @ViewBuilder
    private func selection(_ layout: TrunkStickLayout) -> some View {
        if carry == nil, let target, let placed = placedRect(target.id) {
            let c = layout.screenPoint(bodyX: placed.x + placed.w / 2, bodyY: placed.y + placed.h / 2)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(WebTheme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                .frame(width: (placed.w + 10) * layout.scale, height: (placed.h + 10) * layout.scale)
                .rotationEffect(.degrees(placed.rot))
                .position(x: c.x - layout.originX, y: c.y - layout.originY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 離す所の影（モックの真鍮 80% の破線）
    @ViewBuilder
    private func ghost(_ layout: TrunkStickLayout) -> some View {
        if let carry {
            let b = layout.bodyPoint(screenX: carry.x, screenY: carry.y, lifted: true)
            if TrunkPlacement.canDrop(x: b.x, y: b.y) {
                let size = TrunkPlacement.size(carry.label)
                let c = layout.screenPoint(bodyX: b.x, bodyY: b.y)
                RoundedRectangle(cornerRadius: min(size.w, size.h) * 0.4 * layout.scale)
                    .strokeBorder(WebTheme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: size.w * layout.scale, height: size.h * layout.scale)
                    .position(x: c.x - layout.originX, y: c.y - layout.originY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// 置いてある1枚の枠（胴の座標）
    private func placedRect(_ id: String) -> TrunkSlots.Placed? {
        TrunkPlacement.layout(stuck, stage: 0, overrides: overrides).first { $0.label.id == id }
    }

    /// いまの置き場（置き場なしのラベルは、おまかせの置き場の真ん中）
    private func currentPos(_ id: String) -> TrunkPos? {
        if let p = overrides[id] { return p }
        if let p = stuck.first(where: { $0.id == id })?.pos { return p }
        guard let placed = placedRect(id) else { return nil }
        return TrunkPlacement.pos(x: placed.x + placed.w / 2, y: placed.y + placed.h / 2, rot: placed.rot)
    }

    /// トランクの上: 押さえたラベルを動かす・押しただけなら選ぶ
    private func trunkDrag(_ layout: TrunkStickLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                guard !model.busy else { return }
                let moved = abs(Double(value.translation.width)) + abs(Double(value.translation.height))
                if carry == nil {
                    // 2本指で回している最中は運び始めない（1本目が少し動いても）
                    guard moved > 6, !rotating else { return }
                    let start = layout.bodyPoint(screenX: Double(value.startLocation.x), screenY: Double(value.startLocation.y),
                                                 lifted: false)
                    let placed = TrunkPlacement.layout(stuck, stage: 0, overrides: overrides)
                    guard let label = TrunkPlacement.hit(placed, x: start.x, y: start.y), label.id != pendingStick?.id else { return }
                    selectedId = label.id
                    carry = Carry(label: label, fromTray: false, from: currentPos(label.id),
                                  x: Double(value.location.x), y: Double(value.location.y))
                } else {
                    carry?.x = Double(value.location.x)
                    carry?.y = Double(value.location.y)
                }
            }
            .onEnded { value in
                if let carry, !carry.fromTray {
                    drop(carry, layout)
                    return
                }
                // 2本指で回したあとの離し: 選び直さない（回したラベルのまま）
                guard !rotatedDuringDrag else {
                    rotatedDuringDrag = false
                    return
                }
                // 押しただけ: 指の下のラベルを選ぶ
                let p = layout.bodyPoint(screenX: Double(value.location.x), screenY: Double(value.location.y), lifted: false)
                let placed = TrunkPlacement.layout(stuck, stage: 0, overrides: overrides)
                if let label = TrunkPlacement.hit(placed, x: p.x, y: p.y) { selectedId = label.id }
            }
    }

    /// 2本指で回す（選んでいる1枚）
    private var rotateGesture: some Gesture {
        RotateGesture()
            .updating($rotating) { _, state, _ in state = true }
            .onChanged { value in
                rotatedDuringDrag = true
                // 1本目で運び始めていたら、回す方を選ぶ（置き場は動かす前に戻る）
                if let c = carry, !c.fromTray { carry = nil }
                // 回し始めたラベルを覚える（途中で選んでいるものが替わっても、同じ1枚を回して送る）
                guard let id = rotatingId ?? target?.id, let base = rotateBase ?? currentPos(id) else { return }
                if rotatingId == nil { rotatingId = id }
                if rotateBase == nil { rotateBase = base }
                places.note(id, from: base, to: TrunkPlacement.rotated(base, by: value.rotation.degrees))
            }
            // 指を離した・取り消された、のどちらも `onChange(of: rotating)` で送って印を下げる
    }

    // MARK: 回す

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            if target != nil {
                rotateButton(L("左に回す", "Rotate left"), symbol: "rotate.left", delta: -TrunkPlacement.rotateStep,
                             id: "trunk.stick.rotateLeft")
                Text(L("いま貼った1枚を回す", "Rotate the last label"))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                    .frame(minWidth: 120)
                    .multilineTextAlignment(.center)
                rotateButton(L("右に回す", "Rotate right"), symbol: "rotate.right", delta: TrunkPlacement.rotateStep,
                             id: "trunk.stick.rotateRight")
            } else {
                Text(L("下のラベルを押さえたまま、トランクの上へ運んで離します。",
                       "Hold a label below, carry it onto the trunk and let go."))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }
        }
        .frame(minHeight: WebTheme.minTapTarget)
    }

    private func rotateButton(_ label: String, symbol: String, delta: Double, id: String) -> some View {
        Button {
            guard let target, let base = currentPos(target.id) else { return }
            places.note(target.id, from: base, to: TrunkPlacement.rotated(base, by: delta))
            places.schedule(target.id, delay: 0.5)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WebTheme.accent)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .overlay(Circle().strokeBorder(WebTheme.accent.opacity(0.6), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: 手持ち

    private var trayHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L("手持ちのラベル", "Your pocket"))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            Spacer()
            Text(L("\(pocket.count) 枚", "\(pocket.count)"))
                .font(JPFont.mono(12))
                .foregroundStyle(TrunkStyle.faint)
        }
        .padding(.horizontal, 20)
    }

    private func tray(_ layout: TrunkStickLayout) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if pocket.isEmpty {
                    Text(L("手持ちのラベルはありません。写真を投稿すると届きます。", "No labels in your pocket. Post a photo to get one."))
                        .font(JPFont.footnote)
                        .foregroundStyle(TrunkStyle.muted)
                        .frame(height: 96)
                }
                ForEach(pocket) { label in
                    trayCell(label, layout)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollDisabled(carry != nil)
        .frame(height: 96)
    }

    private func trayCell(_ label: TrunkLabel, _ layout: TrunkStickLayout) -> some View {
        let size = TrunkPlacement.size(label)
        let lifted = carry?.label.id == label.id
        return TrunkLabelView(label: label, w: size.w * 0.8, h: size.h * 0.8, rot: 0)
            .frame(width: 96, height: 96)
            .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.accent, lineWidth: lifted ? 2 : 0))
            .opacity(lifted ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .simultaneousGesture(trayDrag(label, layout))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(TrunkLabelDesign.accessibilityLabel(label))を持ち上げる",
                                  "Pick up \(TrunkLabelDesign.accessibilityLabel(label))"))
            .accessibilityHint(L("トランクの空いている所に貼ります", "Sticks it on a free spot of the trunk"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { await stickAuto(label) } }
            .accessibilityIdentifier("trunk.stick.tray")
    }

    /// 手持ちの札: 縦に動かしたら持ち上げる（横なら並びを送る）
    private func trayDrag(_ label: TrunkLabel, _ layout: TrunkStickLayout) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
            .onChanged { value in
                guard !model.busy, pendingStick == nil else { return }
                if trayIntent[label.id] == nil {
                    trayIntent[label.id] = abs(Double(value.translation.height)) >= abs(Double(value.translation.width))
                }
                guard trayIntent[label.id] == true else { return }
                if carry == nil {
                    carry = Carry(label: label, fromTray: true, from: nil, x: Double(value.location.x), y: Double(value.location.y))
                } else {
                    carry?.x = Double(value.location.x)
                    carry?.y = Double(value.location.y)
                }
            }
            .onEnded { _ in
                trayIntent[label.id] = nil
                guard let carry, carry.fromTray, carry.label.id == label.id else { return }
                dropFromTray(carry, layout)
            }
    }

    // MARK: 運ぶ・離す

    @ViewBuilder
    private func carryPreview(_ layout: TrunkStickLayout) -> some View {
        if let carry {
            let size = TrunkPlacement.size(carry.label)
            let rot = carry.fromTray ? TrunkPlacement.carryRotation : (carry.from?.rot ?? 0)
            TrunkLabelView(label: carry.label, w: size.w * layout.scale, h: size.h * layout.scale, rot: rot)
                .scaleEffect(reduceMotion ? 1 : 1.1)
                .shadow(color: Color.black.opacity(0.6), radius: 8, x: 0, y: 18)
                .position(x: carry.x, y: carry.y - TrunkPlacement.liftOffset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func dropFromTray(_ carry: Carry, _ layout: TrunkStickLayout) {
        let b = layout.bodyPoint(screenX: carry.x, screenY: carry.y, lifted: true)
        self.carry = nil
        guard TrunkPlacement.canDrop(x: b.x, y: b.y) else { return }
        let pos = TrunkPlacement.pos(x: b.x, y: b.y, rot: TrunkPlacement.carryRotation)
        Task { await stick(carry.label, at: pos) }
    }

    private func drop(_ carry: Carry, _ layout: TrunkStickLayout) {
        let b = layout.bodyPoint(screenX: carry.x, screenY: carry.y, lifted: true)
        self.carry = nil
        guard TrunkPlacement.canDrop(x: b.x, y: b.y), let from = carry.from else { return }
        let id = carry.label.id
        let pos = TrunkPlacement.moved(from, toX: b.x, y: b.y)
        places.note(id, from: from, to: pos)
        // 送るのも committer の予定に入れる（「保存せずに閉じる」で取り消せる・混んでいたらやり直す）
        let userId = auth.userId
        places.schedule(id, delay: 0) { outcome, closed in
            // 送れた（すぐ後に回した頼み・「完了」が送った分も）: 動かしたことに変わりはない。断られたら何も付けない
            guard outcome == .saved else { return }
            // 貼ったあとに動かすと、紙が少しよれる
            let store = TrunkWrinkles(userId: userId)
            store.noteMoved(id)
            // 閉じたあとに送れた: よれだけ覚え、閉じた先の画面で音・触覚を出さない
            guard !closed else { return }
            wrinkles = store.strengths
            stickTicks += 1
            TrunkSound.stick()
        }
    }

    /// 貼る（離した所に・応答の前から出しておく）
    private func stick(_ label: TrunkLabel, at pos: TrunkPos) async {
        pendingStick = label.withPos(pos)
        let ok = await model.stickWhenFree(label.id, at: pos)
        pendingStick = nil
        guard ok else { return }
        steps.append(.stuck(label.id))
        selectedId = label.id
        stickTicks += 1
        TrunkSound.stick()
        await press(label.id)
    }

    /// 読み上げの「持ち上げる」: 空いているおまかせの置き場に貼る
    private func stickAuto(_ label: TrunkLabel) async {
        guard let s = state else { return }
        let others = s.pocket.filter { $0.id != label.id }
        guard let plan = TrunkPlacement.autoArrange(pocket: [label] + others, stuck: s.stuck).first, plan.id == label.id else {
            model.actionError = TrunkText.noFreeSlot
            return
        }
        await stick(label, at: plan.pos)
    }

    /// 貼った瞬間に押さえる（1.12 → 0.97 → 1・260ms）。「視差効果を減らす」の人には出さない
    private func press(_ id: String) async {
        guard !reduceMotion else { return }
        pop = id
        popScale = 1.12
        withAnimation(.easeOut(duration: 0.156)) { popScale = 0.97 }
        try? await Task.sleep(nanoseconds: 156_000_000)
        withAnimation(.easeOut(duration: 0.104)) { popScale = 1 }
        try? await Task.sleep(nanoseconds: 120_000_000)
        pop = nil
    }

    // MARK: 下の2つ

    private var bottomButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    let done = await model.autoArrange()
                    steps += done.map { Step.stuck($0) }
                    if let last = done.last {
                        selectedId = last
                        stickTicks += 1
                        TrunkSound.stick()
                    }
                }
            } label: {
                TrunkButtonFace(title: L("おまかせで並べる", "Arrange for me"), kind: .secondary, height: 48, size: 15)
            }
            .buttonStyle(.plain)
            .disabled(model.busy || pocket.isEmpty)
            .accessibilityIdentifier("trunk.stick.auto")
            Button {
                Task { await unstickTarget() }
            } label: {
                TrunkButtonFace(title: L("はがして手持ちに戻す", "Peel off to pocket"), kind: .secondary, height: 48, size: 15)
            }
            .buttonStyle(.plain)
            .disabled(model.busy || target == nil)
            .accessibilityIdentifier("trunk.stick.peel")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }

    private func unstickTarget() async {
        guard let target else { return }
        // 戻すときは、はがす前に描いていた所へ貼り直す（置き場なしのラベルも、おまかせの置き場の所に・2026-10-19 の直し。
        // 前は置き場なしで貼り直し、いちばん新しい番号の置き場＝別の所に入っていた）
        let pos = currentPos(target.id)
        // 保存を待っている置き場（回した・動かした直後）は送らない。はがしたあとに送ると「まだ貼っていない」と断られる
        places.discard(target.id)
        if await model.unstick(target.id, overrides: overrides) {
            steps.append(.unstuck(target.id, pos: pos))
            selectedId = nil
        }
    }

    /// 直前の1手を戻す
    private func undo() async {
        guard let last = steps.last, await model.waitUntilIdle() else { return }
        let ok: Bool
        switch last {
        case .stuck(let id):
            places.discard(id)
            ok = await model.unstick(id, overrides: overrides)
            if ok, selectedId == id { selectedId = nil }
        case let .moved(id, from):
            ok = await model.place(id, at: from)
        case let .unstuck(id, pos):
            if let pos { ok = await model.stick(id, at: pos) } else { ok = await model.stick(id) }
        }
        if ok { steps.removeLast() }
    }
}
