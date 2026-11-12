import SwiftUI

/// 部品箱（モック PartsBox.dc.html・2026-10-17 次の版）。
///
/// 集めた数・硬貨・かけら → 種類のタブ（集めた数つき）→ 12 点の格子（持っていない部品は影と「？」・
/// 付けている部品は真鍮の縁と「付けている」）→ かけら5つで1つ交換。持っている部品を押すと、その種類の
/// 付け替えの画面へ。かけらが5つあれば、影の部品を押して交換する部品を選べる
///
/// **1.1.83 の案（2026-11-12 判断）**: 種類は「選んでいるタブ」（真鍮の字と下線・板 05）——前は絞り込みのチップと
/// 同じ白塗りで、選ぶ物と絞り込みの区別が付かなかった。持っている部品を押すとシートで見て「トランクに付ける」
/// （付け替えの画面へ行って保存を確かめられる 3 回 → 2 回）。押せばすぐ保存し、知らせの「取り消す」で戻す。
/// 硬貨は数え札の右上のチップから機械へ1回で
struct TrunkPartsBoxView: View {
    @ObservedObject var model: TrunkViewModel
    var ownerName: String?

    @EnvironmentObject private var toasts: ToastCenter
    @State private var kind: TrunkPartKind = .handle
    @State private var exchangeTarget: TrunkPart?
    @State private var confirmExchange = false
    @State private var equipKind: TrunkPartKind?
    /// シートで見ている持っている部品
    @State private var viewing: TrunkPart?
    @EnvironmentObject private var connectivity: Connectivity

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
        .sheet(item: $viewing) { part in
            TrunkPartSheet(model: model, part: part)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
                    // 圏外は上の帯（前に見た部品箱を出したまま・2026-11-12 判断。回る輪や字だけにしない）
                    if connectivity.isOffline {
                        OfflineBanner(title: TrunkPartsOfflineCopy.title, detail: TrunkPartsOfflineCopy.detail)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            .accessibilityIdentifier("trunk.parts.offline")
                    }
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

    // MARK: 数え札（集めた部品が主役・硬貨は脇）

    /// 2026-10-21 判断（全画面の点検 99）: 前は「集めた部品・硬貨・かけら」を同じ大きさの札3つで並べていて、
    /// どれが大事か読めなかった。**主役は「集めた部品 26 / 108」の1つ**（大きな数字）、硬貨は同じ札の右に小さく。
    /// かけらは交換の札（下）へ移した——かけらを使うのはそこだけ
    private func stats(_ state: TrunkState) -> some View {
        let c = TrunkPartsBoxText.collected(state.ownedParts)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("集めた部品", "Collected"))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(c.owned)")
                        .font(JPFont.number(28, weight: .semibold, relativeTo: .title2))
                        .foregroundStyle(WebTheme.foreground)
                    Text(" / \(c.total)")
                        .font(JPFont.number(15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(TrunkStyle.faint)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trunk.parts.collected")
            Spacer(minLength: 0)
            // 硬貨のチップから機械へ1回で（2026-11-12 判断・前は数を見せるだけ）
            NavigationLink {
                TrunkGachaView(model: model)
            } label: {
                HStack(spacing: 6) {
                    TrunkCoinMark(size: 14)
                    Text("\(state.coins)")
                        .font(JPFont.number(13, weight: .medium, relativeTo: .footnote))
                        .foregroundStyle(WebTheme.foreground)
                    // 数と動きは区切りの記号を使わず、余白と色（真鍮）で分ける
                    Text(L("カプセルを回す", "Turn the machine"))
                        .padding(.leading, 4)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.accent)
                }
                // 線のチップ（丸いボタンの面 `jpCapsuleFace` を通す・見た目 34＋上下 5 で当たり 44）
                .jpCapsuleFace(font: JPFont.footnote, text: WebTheme.foreground, fill: Color.clear, border: WebTheme.line,
                               fullWidth: false, minHeight: PillChip.height, textInset: 12)
                .padding(.vertical, PillChip.tapSlack)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("硬貨 \(state.coins) 枚、カプセルを回す", "\(Plural.count(state.coins, "coin")), turn the machine"))
            .accessibilityIdentifier("trunk.parts.coins")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trunkCard(radius: 14)
        .padding(.horizontal, 20)
    }

    // MARK: 種類のタブ

    /// 選んでいるタブ（真鍮の字と下線・板 05・2026-11-12 判断）。集めた数は字の横に小さく
    private func tabs(_ owned: Set<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JPSpace.l) {
                ForEach(TrunkPartKind.allCases) { k in
                    TrunkKindTab(title: k.tabName, count: "\(TrunkPartsBoxText.collected(owned, kind: k))",
                                 selected: k == kind) { kind = k }
                        .accessibilityIdentifier("trunk.parts.tab.\(k.rawValue)")
                }
            }
            .padding(.horizontal, 20)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
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
                        viewing = part
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
                .accessibilityHint(has ? L("見て、トランクに付けられます", "View it and put it on your trunk")
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
        .trunkCard(radius: 14)
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
                // かけらの印は使う場所（交換の札）に置く（2026-10-21・上の数え札から移した）
                HStack(spacing: 4) {
                    ForEach(0..<TrunkPartsBoxText.fragmentsPerExchange, id: \.self) { i in
                        TrunkFragmentMark(filled: i < TrunkPartsBoxText.filledFragments(state.fragments))
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TrunkPartsBoxText.fragmentsLabel(state.fragments))
                .accessibilityIdentifier("trunk.parts.fragments")
                Text(TrunkGachaText.exchangeNote(fragments: state.fragments, selected: exchangeTarget))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { confirmExchange = true } label: {
                Text(L("交換する", "Exchange"))
                    .font(JPFont.bodyEmphasis)
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
        .trunkCard(radius: 14)
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

/// 部品を付け替える（モック Equip.dc.html）。場所のタブ → 持っている部品の並び → トランクに即座に映る。
///
/// **押すたびに保存する（2026-11-12 判断・1.1.83 の案）**: 前は下書きを持って右上の「保存」で決め、戻るときに
/// 「付け替えを保存していません」と聞いていた。いまは押せばすぐ保存し、右上の「ひとつ戻す」で直前の付け方へ戻す
/// （聞く・選ばせるのは最小に）。続けて押しても書き込みは1つずつ（書いている間は押せない）
struct TrunkEquipView: View {
    @ObservedObject var model: TrunkViewModel
    var ownerName: String?
    var startKind: TrunkPartKind = .handle

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var auth: AuthStore
    @State private var kind: TrunkPartKind?
    /// 「ひとつ戻す」で戻る前の付け方（新しい順に積む）
    @State private var history: [TrunkEquipped] = []
    @State private var picks = 0

    private var current: TrunkPartKind { kind ?? startKind }
    private var working: TrunkEquipped { model.state?.equipped ?? .none }

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await undoLast() } } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: WebTheme.toolbarIconSize, weight: .regular))
                        .foregroundStyle(history.isEmpty ? WebTheme.outline : WebTheme.accent)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                }
                .disabled(history.isEmpty || model.busy)
                .accessibilityLabel(L("ひとつ戻す", "Undo"))
                .accessibilityIdentifier("trunk.equip.undo")
            }
        }
        .sensoryFeedback(.selection, trigger: picks)
        .task { if model.state == nil { await model.load(offline: false) } }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.equip")
    }

    /// 付け方を替えてすぐ保存する。保存できたら前の付け方を「ひとつ戻す」に積む
    private func apply(_ next: TrunkEquipped) async {
        let before = working
        guard next != before else { return }
        picks += 1
        if await model.equip(next) { history.append(before) }
    }

    /// 「ひとつ戻す」: 直前の付け方へ戻して保存する
    private func undoLast() async {
        guard let previous = history.last else { return }
        if await model.equip(previous) {
            history.removeLast()
            picks += 1
        }
    }

    /// トランク（下書きの部品で・いま選んでいる場所に真鍮の破線）
    private func preview(_ state: TrunkState) -> some View {
        GeometryReader { geo in
            let w = min(360, Double(geo.size.width) - 30)
            let k = w / TrunkLooks.canvasWidth
            ZStack(alignment: .topLeading) {
                TrunkFigure(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,
                            ownerName: ownerName, parts: working,
                            wrinkles: TrunkWrinkles(userId: auth.userId).strengths, width: w, tagPicks: state.tagPicks)
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
                            Task { await apply(next.equipped) }
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
                        .trunkCard(radius: 14)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.accent, lineWidth: on ? 2 : 0))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                    .accessibilityLabel("\(part.kind.title)\u{2002}\(part.name)\(on ? L("（付けている）", " (on)") : "")")
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
                Task { await apply(TrunkEquipText.clearing(current, on: working)) }
            } label: {
                TrunkButtonFace(title: L("外す", "Take off"), kind: .secondary)
            }
            .buttonStyle(.plain)
            .disabled(working.ids(current).isEmpty || model.busy)
            .accessibilityIdentifier("trunk.equip.clear")
            NavigationLink {
                TrunkGachaView(model: model)
            } label: {
                TrunkButtonFace(title: L("カプセルを回す", "Turn the capsule machine"), kind: .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.equip.gacha")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }
}

/// 部品箱の種類のタブ（選んでいるタブ＝真鍮の字と下線 2・板 05。`TripCreateTabs` と同じ形）。当たり 44
struct TrunkKindTab: View {
    let title: String
    let count: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(selected ? JPFont.bodyEmphasis : JPFont.body)
                Text(count)
                    .font(JPFont.number(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(selected ? WebTheme.accent : WebTheme.text3)
            }
            .foregroundStyle(selected ? WebTheme.accent : WebTheme.text2)
            .lineLimit(1)
            .frame(minHeight: WebTheme.minTapTarget)
            .overlay(alignment: .bottom) {
                if selected { Rectangle().fill(WebTheme.accent).frame(height: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 持っている部品を押したシート（2026-11-12 判断・案「部品を押す → シート → 付ける」）。
/// 大きい絵・名前・段 → 主ボタン「トランクに付ける」（付けていれば副の「外す」）。**押せばすぐ保存**し、
/// 閉じたあとの知らせの「取り消す」で前の付け方に戻す（前は付け替えの画面で保存を確かめていた）
struct TrunkPartSheet: View {
    @ObservedObject var model: TrunkViewModel
    let part: TrunkPart

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    private var equipped: Bool { model.state?.equipped.ids(part.kind).contains(part.id) ?? false }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    TrunkRarityMark(rarity: part.rarity, size: 9)
                    Text(TrunkGachaText.eyebrow(part))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                }
                Spacer()
                Button { dismiss() } label: {
                    Text(Labels.Common.close)
                        .font(.body)
                        .foregroundStyle(WebTheme.text)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trunk.partSheet.close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            TrunkPartView(part: part, size: 140)
                .frame(height: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TrunkPartDrawing.accessibilityLabel(part))
                .accessibilityAddTraits(.isImage)
            Text(part.name)
                .font(JPFont.display(22, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Text(equipped ? L("トランクに付けています", "On your trunk") : L("どの型のトランクにも付けられます", "Fits every trunk style"))
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.muted)
                .padding(.top, 4)
            Spacer(minLength: 12)
            if let error = model.actionError {
                Text(error)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            Button { Task { await toggle() } } label: {
                TrunkButtonFace(title: equipped ? L("外す", "Take off") : L("トランクに付ける", "Put it on my trunk"),
                                kind: equipped ? .secondary : .main)
            }
            .buttonStyle(.plain)
            .disabled(model.busy)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .accessibilityIdentifier("trunk.partSheet.equip")
        }
        .webScreen()
        .onAppear { model.actionError = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.partSheet")
    }

    /// 付ける・外す。すぐ保存して閉じ、知らせに「取り消す」を添える。いっぱいなら黙って外さず一言
    private func toggle() async {
        guard let state = model.state else { return }
        let before = state.equipped
        let next = TrunkEquipText.toggling(part, on: before)
        guard !next.full else {
            model.actionError = TrunkEquipText.fullNote(part.kind)
            return
        }
        let wasOn = equipped
        guard await model.equip(next.equipped) else { return }
        dismiss()
        toasts.show(wasOn ? L("外しました", "Taken off") : L("トランクに付けました", "Put on your trunk"),
                    undo: ToastCenter.Undo(title: TrunkText.undoTitle) { [model] in await model.equip(before) })
    }
}
