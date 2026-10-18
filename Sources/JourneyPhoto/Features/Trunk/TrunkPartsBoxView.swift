import SwiftUI

/// 部品箱（モック PartsBox.dc.html・2026-10-17 次の版）。
///
/// 集めた数・硬貨・かけら → 種類のタブ（集めた数つき）→ 12 点の格子（持っていない部品は影と「？」・
/// 付けている部品は真鍮の縁と「付けている」）→ かけら5つで1つ交換。持っている部品を押すと、その種類の
/// 付け替えの画面へ。かけらが5つあれば、影の部品を押して交換する部品を選べる
struct TrunkPartsBoxView: View {
    @ObservedObject var model: TrunkViewModel
    var ownerName: String?

    @EnvironmentObject private var toasts: ToastCenter
    @State private var kind: TrunkPartKind = .handle
    @State private var exchangeTarget: TrunkPart?
    @State private var confirmExchange = false
    @State private var equipKind: TrunkPartKind?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        Group {
            if let state = model.state {
                content(state)
            } else {
                JPLoadingState(kind: .grid).padding(.horizontal, 20)
            }
        }
        .webScreen()
        .navigationTitle(L("部品箱", "Parts box"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TrunkEquipView(model: model, ownerName: ownerName, startKind: kind)
                } label: {
                    Text(L("付け替える", "Change parts"))
                        .font(.subheadline)
                        .underline()
                        .foregroundStyle(WebTheme.accent)
                        .frame(minHeight: WebTheme.minTapTarget)
                }
                .accessibilityIdentifier("trunk.parts.equip")
            }
        }
        .navigationDestination(item: $equipKind) { k in
            TrunkEquipView(model: model, ownerName: ownerName, startKind: k)
        }
        .task { if model.state == nil { await model.load(offline: false) } }
        .confirmationDialog(L("かけら5つで交換しますか", "Exchange five fragments?"), isPresented: $confirmExchange,
                            titleVisibility: .visible) {
            if let part = exchangeTarget {
                Button(L("「\(part.name)」と交換する", "Exchange for \u{201C}\(part.name)\u{201D}")) {
                    Task {
                        if await model.exchange(part.id) {
                            exchangeTarget = nil
                            toasts.show(L("「\(part.name)」を部品箱に入れました", "\u{201C}\(part.name)\u{201D} is in your parts box"))
                        }
                    }
                }
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.parts")
    }

    private func content(_ state: TrunkState) -> some View {
        let owned = state.ownedParts
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    if let error = model.actionError {
                        Text(error)
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.danger)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }
                    stats(state)
                        .padding(.top, 8)
                    tabs(owned)
                        .padding(.top, 14)
                    grid(state)
                        .padding(.top, 14)
                }
            }
            exchangeCard(state)
        }
    }

    // MARK: 数え札（集めた部品・硬貨・かけら）

    private func stats(_ state: TrunkState) -> some View {
        let c = TrunkPartsBoxText.collected(state.ownedParts)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("集めた部品", "Collected"))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(c.owned)")
                        .font(JPFont.number(20, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(WebTheme.text)
                    Text(" / \(c.total)")
                        .font(JPFont.mono(13))
                        .foregroundStyle(TrunkStyle.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("硬貨", "Coins"))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                HStack(spacing: 6) {
                    TrunkCoinMark(size: 16)
                    Text("\(state.coins)")
                        .font(JPFont.number(20, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(WebTheme.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("かけら", "Fragments"))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                HStack(spacing: 4) {
                    ForEach(0..<TrunkPartsBoxText.fragmentsPerExchange, id: \.self) { i in
                        TrunkFragmentMark(filled: i < TrunkPartsBoxText.filledFragments(state.fragments))
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TrunkPartsBoxText.fragmentsLabel(state.fragments))
        }
        .padding(.horizontal, 20)
    }

    // MARK: 種類のタブ

    private func tabs(_ owned: Set<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TrunkPartKind.allCases) { k in
                    PillChip(title: k.tabName,
                             countText: "\(TrunkPartsBoxText.collected(owned, kind: k))/\(TrunkPartKind.perKind)",
                             selected: k == kind) { kind = k }
                        .accessibilityIdentifier("trunk.parts.tab.\(k.rawValue)")
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, -PillChip.tapSlack)
    }

    // MARK: 格子

    private func grid(_ state: TrunkState) -> some View {
        let owned = state.ownedParts
        let canExchange = TrunkPartsBoxText.canExchange(fragments: state.fragments)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(TrunkPartCatalog.parts(of: kind)) { part in
                let has = owned.contains(part.id)
                let equipped = state.equipped.ids(part.kind).contains(part.id)
                let picked = exchangeTarget?.id == part.id
                Button {
                    if has {
                        equipKind = part.kind
                    } else if canExchange {
                        exchangeTarget = picked ? nil : part
                    }
                } label: {
                    cell(part, has: has, equipped: equipped, picked: picked)
                }
                .buttonStyle(.plain)
                .disabled(!has && !canExchange)
                .accessibilityLabel(has ? "\(part.name)\(equipped ? L("（付けている）", " (on)") : "")"
                                        : L("まだ持っていない\(part.kind.tabName)", "A \(part.kind.tabName.lowercased()) you don\u{2019}t have"))
                .accessibilityHint(has ? L("付け替えの画面を開きます", "Opens Change parts")
                                       : (canExchange ? L("交換する部品に選びます", "Choose to exchange") : ""))
                .accessibilityAddTraits(picked || equipped ? .isSelected : [])
                .accessibilityIdentifier(has ? "trunk.parts.owned" : "trunk.parts.missing")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func cell(_ part: TrunkPart, has: Bool, equipped: Bool, picked: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if has {
                    TrunkPartView(part: part)
                } else {
                    // 持っていない部品は白 10% の一色の影絵（2026-10-17 owner。板の黒 35% は #121212 の札でほぼ見えない）。
                    // 形だけを出し、色・質感は出さない
                    Color.white.opacity(TrunkPartsBoxText.missingShadowOpacity)
                        .frame(width: 96, height: 96)
                        .mask { TrunkPartView(part: part, shadow: false) }
                }
            }
            .frame(width: 96, height: 96)
            Text(has ? part.name : "？")
                .font(JPFont.footnote)
                .foregroundStyle(has ? TrunkStyle.muted : WebTheme.outline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.accent, lineWidth: equipped ? 2 : 0))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(WebTheme.accent.opacity(picked ? 0.8 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .overlay(alignment: .topLeading) {
            if equipped {
                Text(L("付けている", "On"))
                    .font(JPFont.eyebrow)
                    .foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(TrunkStyle.chip, in: Capsule())
                    .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            TrunkRarityMark(rarity: part.rarity, size: 9).padding(9)
        }
    }

    // MARK: かけらの交換

    private func exchangeCard(_ state: TrunkState) -> some View {
        let can = TrunkPartsBoxText.canExchange(fragments: state.fragments)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("かけら5つで1つ交換", "Five fragments for one part"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                Text(TrunkGachaText.exchangeNote(fragments: state.fragments, selected: exchangeTarget))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { confirmExchange = true } label: {
                Text(L("交換する", "Exchange"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(can && exchangeTarget != nil ? WebTheme.accentText : WebTheme.outline)
                    .padding(.horizontal, 14)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .background(can && exchangeTarget != nil ? WebTheme.accentFill : TrunkStyle.line,
                                in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!can || exchangeTarget == nil || model.busy)
            .accessibilityIdentifier("trunk.parts.exchange")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 26)
    }
}

/// かけらの印（ひし形・埋まっていれば真鍮・空なら灰の縁）
struct TrunkFragmentMark: View {
    let filled: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(filled ? AnyShapeStyle(LinearGradient(colors: [Color(trunk: TrunkRGBA(0xF2DFAE)), WebTheme.accent,
                                                                 Color(trunk: TrunkRGBA(0x7E6438))],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(WebTheme.outline, lineWidth: filled ? 0 : 1.5))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(45))
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

// MARK: - 付け替える

/// 部品を付け替える（モック Equip.dc.html）。場所のタブ → 持っている部品の並び → トランクに即座に映る → 保存
struct TrunkEquipView: View {
    @ObservedObject var model: TrunkViewModel
    var ownerName: String?
    var startKind: TrunkPartKind = .handle

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var auth: AuthStore
    @State private var kind: TrunkPartKind?
    @State private var draft: TrunkEquipped?
    @State private var confirmLeave = false
    @State private var picks = 0

    private var current: TrunkPartKind { kind ?? startKind }
    private var saved: TrunkEquipped { model.state?.equipped ?? .none }
    private var working: TrunkEquipped { draft ?? saved }
    private var dirty: Bool { draft != nil && draft != saved }

    var body: some View {
        VStack(spacing: 0) {
            if let state = model.state {
                preview(state)
                slotTabs.padding(.top, 6)
                Text(TrunkPartsBoxText.slotNote(current, count: working.ids(current).count))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                tray(state).padding(.top, 8)
                if let error = model.actionError {
                    Text(error)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                Spacer(minLength: 8)
                bottom
            } else {
                JPLoadingState(kind: .rows).padding(.horizontal, 20)
            }
        }
        .background { TrunkStyle.stageBackground(centerY: 0.28) }
        .navigationTitle(L("部品を付け替える", "Change parts"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if dirty { confirmLeave = true } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WebTheme.text)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                }
                .accessibilityLabel(L("戻る", "Back"))
                .accessibilityIdentifier("trunk.equip.back")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await save() } } label: {
                    Text(Labels.Common.save)
                        .font(.headline)
                        .foregroundStyle(dirty ? WebTheme.accent : WebTheme.outline)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                }
                .disabled(!dirty || model.busy)
                .accessibilityIdentifier("trunk.equip.save")
            }
        }
        .confirmationDialog(L("付け替えを保存していません", "Your changes aren\u{2019}t saved"), isPresented: $confirmLeave,
                            titleVisibility: .visible) {
            Button(L("保存して戻る", "Save and go back")) {
                Task { if await save() { dismiss() } }
            }
            Button(L("保存せずに戻る", "Go back without saving"), role: .destructive) { dismiss() }
            Button(Labels.Common.cancel, role: .cancel) {}
        }
        .sensoryFeedback(.selection, trigger: picks)
        .task { if model.state == nil { await model.load(offline: false) } }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.equip")
    }

    @discardableResult
    private func save() async -> Bool {
        guard let draft else { return true }
        let ok = await model.equip(draft)
        if ok {
            self.draft = nil
            toasts.show(L("付け替えました", "Parts changed"))
        }
        return ok
    }

    /// トランク（下書きの部品で・いま選んでいる場所に真鍮の破線）
    private func preview(_ state: TrunkState) -> some View {
        GeometryReader { geo in
            let w = min(360, Double(geo.size.width) - 30)
            let k = w / TrunkLooks.canvasWidth
            ZStack(alignment: .topLeading) {
                TrunkFigure(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,
                            ownerName: ownerName, parts: working,
                            wrinkles: TrunkWrinkles(userId: auth.userId).strengths, width: w)
                if let r = TrunkEquipText.outline(current) {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WebTheme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: r.w * k, height: r.h * k)
                        .offset(x: r.x * k, y: r.y * k)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: w, height: TrunkLooks.canvasHeight * k, alignment: .topLeading)
            .padding(.top, 20)
            .frame(width: Double(geo.size.width))
        }
        .frame(height: 330)
    }

    private var slotTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TrunkPartKind.allCases) { k in
                    PillChip(title: k.tabName, selected: k == current) {
                        kind = k
                        model.actionError = nil
                    }
                    .accessibilityIdentifier("trunk.equip.tab.\(k.rawValue)")
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, -PillChip.tapSlack)
    }

    private func tray(_ state: TrunkState) -> some View {
        let owned = TrunkPartCatalog.parts(of: current).filter { state.ownedParts.contains($0.id) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if owned.isEmpty {
                    Text(L("まだこの部品を持っていません。カプセルの機械で集められます。",
                           "You don\u{2019}t have this kind yet. Collect them at the capsule machine."))
                        .font(JPFont.footnote)
                        .foregroundStyle(TrunkStyle.muted)
                        .frame(height: 124)
                }
                ForEach(owned) { part in
                    let on = working.ids(part.kind).contains(part.id)
                    Button {
                        let next = TrunkEquipText.toggling(part, on: working)
                        if next.full {
                            model.actionError = TrunkEquipText.fullNote(part.kind)
                        } else {
                            model.actionError = nil
                            draft = next.equipped
                            picks += 1
                        }
                    } label: {
                        VStack(spacing: 0) {
                            TrunkPartView(part: part)
                            Text(part.name)
                                .font(JPFont.footnote.weight(on ? .semibold : .regular))
                                .foregroundStyle(on ? WebTheme.accent : TrunkStyle.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.bottom, 8)
                        .frame(width: 96, height: 124)
                        .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.accent, lineWidth: on ? 2 : 0))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(part.kind.title) · \(part.name)\(on ? L("（付けている）", " (on)") : "")")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("trunk.equip.part")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var bottom: some View {
        HStack(spacing: 8) {
            Button {
                draft = TrunkEquipText.clearing(current, on: working)
                picks += 1
            } label: {
                TrunkButtonFace(title: L("外す", "Take off"), kind: .secondary, height: 48, size: 15)
            }
            .buttonStyle(.plain)
            .disabled(working.ids(current).isEmpty)
            .accessibilityIdentifier("trunk.equip.clear")
            NavigationLink {
                TrunkGachaView(model: model)
            } label: {
                TrunkButtonFace(title: L("カプセルを回す", "Turn the capsule machine"), kind: .secondary, height: 48, size: 15)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.equip.gacha")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }
}
