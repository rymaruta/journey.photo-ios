import SwiftUI

/// 部品箱（モック PartsBox.dc.html・2026-10-17 次の版）。
///
/// **2026-11-23 判断（札 #711・案「トランクを見やすく」版3・owner 承認）**: 前は部品箱にトランクが見えず、付けた姿を
/// 見るには「付け替える」の別の画面（同じ部品の一覧がもう1つ）か、前の画面に戻る必要があった。いまは:
/// 上に小さいトランク（集めた数つき）→ 種類のタブ（真鍮の字と下線・板 05）→ 格子。
/// **持っている部品を押すとその場で付く**（トランクが少し弾み、軽く震える。下に「付けました」と「元に戻す」を 3 秒）。
/// もう一度押すと外す。持っていない部品を押すと手に入れ方（かけらが5つあればその部品と交換）と「カプセルを回す」。
/// 「付け替える」の画面と入口はなくした（付けるまで 3 回 → 1 回）。硬貨とかけらは下の帯にまとめた
struct TrunkPartsBoxView: View {
    @ObservedObject var model: TrunkViewModel
    var ownerName: String?

    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var connectivity: Connectivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kind: TrunkPartKind = .handle
    /// 持っていない部品を押したシート
    @State private var missing: TrunkPart?
    /// シートの「カプセルを回す」から機械へ
    @State private var showGacha = false
    /// 付けた・外したときにトランクを弾ませる
    @State private var pop = false
    /// 軽い触覚の引き金（付けた・外した回数）
    @State private var picks = 0

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
        .navigationDestination(isPresented: $showGacha) { TrunkGachaView(model: model) }
        .sheet(item: $missing) { part in
            TrunkMissingPartSheet(model: model, part: part) {
                missing = nil
                showGacha = true
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: picks)
        .task { if model.state == nil { await model.load(offline: false) } }
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
                    preview(state)
                        .padding(.top, 4)
                    tabs(owned)
                        .padding(.top, 12)
                    grid(state)
                        .padding(.top, 12)
                    Text(TrunkPartsBoxText.tapHint)
                        .font(JPFont.caption)
                        .foregroundStyle(TrunkStyle.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
            dock(state)
        }
    }

    // MARK: 上の小さいトランク

    /// 付けた姿をその場で見る（2026-11-23）。左上に集めた数（数は白の等幅、残りは text-2）。足元に真鍮の淡い光
    private func preview(_ state: TrunkState) -> some View {
        let c = TrunkPartsBoxText.collected(state.ownedParts)
        return ZStack(alignment: .topLeading) {
            TrunkStyle.glow(width: 260, height: 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            TrunkFigure(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,
                        ownerName: ownerName, parts: state.equipped,
                        wrinkles: TrunkWrinkles(userId: auth.userId).strengths, width: 200, tagPicks: state.tagPicks)
                .scaleEffect(pop ? 1.06 : 1)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(c.owned)")
                    .font(JPFont.number(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(WebTheme.text)
                Text(" / \(c.total)")
                    .font(JPFont.number(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(TrunkStyle.muted)
                Text(L(" 集めました", " collected"))
                    .font(JPFont.caption)
                    .foregroundStyle(TrunkStyle.muted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TrunkPartsBoxText.collectedCaption(owned: c.owned, total: c.total))
            .accessibilityIdentifier("trunk.parts.collected")
        }
        .frame(maxWidth: .infinity)
        .trunkCard(radius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.parts.preview")
    }

    // MARK: 種類のタブ

    /// 選んでいるタブ（真鍮の字と下線・板 05・2026-11-12 判断）。集めた数は字の横に小さく
    private func tabs(_ owned: Set<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JPSpace.l) {
                ForEach(TrunkPartKind.allCases) { k in
                    TrunkKindTab(title: k.tabName, count: "\(TrunkPartsBoxText.collected(owned, kind: k))",
                                 selected: k == kind) {
                        kind = k
                        model.actionError = nil
                    }
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
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(TrunkPartCatalog.parts(of: kind)) { part in
                let has = owned.contains(part.id)
                let equipped = state.equipped.ids(part.kind).contains(part.id)
                Button {
                    if has {
                        Task { await toggle(part) }
                    } else {
                        missing = part
                    }
                } label: {
                    cell(part, has: has, equipped: equipped)
                }
                .buttonStyle(.plain)
                .disabled(has && model.busy)
                .accessibilityLabel(has ? "\(part.name)\(equipped ? L("（付けている）", " (on)") : "")"
                                        : L("まだ持っていない\(part.kind.tabName)", "A \(part.kind.tabName.lowercased()) you don\u{2019}t have"))
                .accessibilityHint(has ? (equipped ? L("押すと外します", "Tap to take it off") : L("押すとトランクに付けます", "Tap to put it on your trunk"))
                                       : L("手に入れ方を見ます", "See how to get it"))
                .accessibilityAddTraits(equipped ? .isSelected : [])
                .accessibilityIdentifier(has ? "trunk.parts.owned" : "trunk.parts.missing")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func cell(_ part: TrunkPart, has: Bool, equipped: Bool) -> some View {
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
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 押した部品を付ける・外す。**すぐ保存**し、トランクを弾ませて軽く震わせ、「元に戻す」を 3 秒出す。
    /// ピン・ワッペンがいっぱいなら変えずに一言（黙って古いものを外さない）
    private func toggle(_ part: TrunkPart) async {
        guard let state = model.state else { return }
        let before = state.equipped
        let next = TrunkEquipText.toggling(part, on: before)
        guard !next.full else {
            model.actionError = TrunkEquipText.fullNote(part.kind)
            return
        }
        model.actionError = nil
        let putOn = !before.ids(part.kind).contains(part.id)
        guard await model.equip(next.equipped) else { return }
        picks += 1
        bounce()
        toasts.show(TrunkPartsBoxText.equippedNotice(part, on: putOn), seconds: TrunkPartsBoxText.undoSeconds,
                    undo: ToastCenter.Undo(title: TrunkPartsBoxText.undoTitle) { [model] in await model.equip(before) })
    }

    /// トランクを少し弾ませる（動きを減らす設定では弾ませない。触覚と知らせで伝わる）
    private func bounce() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { pop = true }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = false }
        }
    }

    // MARK: 下の帯（硬貨とかけら）

    /// 硬貨（押すとカプセルの機械へ1回で）と、かけらの5つの印をまとめた帯（2026-11-23。前は交換の札と数え札に分かれていた）
    private func dock(_ state: TrunkState) -> some View {
        HStack(spacing: 8) {
            NavigationLink {
                TrunkGachaView(model: model)
            } label: {
                HStack(spacing: 6) {
                    TrunkCoinMark(size: 14)
                    Text(TrunkPartsBoxText.coinsTitle(state.coins))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.foreground)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TrunkStyle.muted)
                        .accessibilityHidden(true)
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
            Spacer(minLength: 8)
            Text(TrunkPartsBoxText.fragmentsCaption)
                .font(JPFont.caption)
                .foregroundStyle(TrunkStyle.faint)
                .accessibilityHidden(true)
            // かけらの印は硬貨の隣（交換は持っていない部品を押したシートから）
            HStack(spacing: 2) {
                ForEach(0..<TrunkPartsBoxText.fragmentsPerExchange, id: \.self) { i in
                    TrunkFragmentMark(filled: i < TrunkPartsBoxText.filledFragments(state.fragments))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TrunkPartsBoxText.fragmentsLabel(state.fragments))
            .accessibilityIdentifier("trunk.parts.fragments")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(WebTheme.card)
        .overlay(alignment: .top) { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
    }
}

/// 持っていない部品を押したシート（2026-11-23・札 #711）。手に入れ方と「カプセルを回す」。
/// かけらが5つあれば、その部品と交換するボタンを主にする（押す前に何と何を替えるかがボタンの字で分かるので、確かめは出さない）
struct TrunkMissingPartSheet: View {
    @ObservedObject var model: TrunkViewModel
    let part: TrunkPart
    var onGacha: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    var body: some View {
        let fragments = model.state?.fragments ?? 0
        let canExchange = TrunkPartsBoxText.canExchange(fragments: fragments)
        VStack(spacing: 0) {
            // 閉じるは左上のシートの「閉じる」（2026-11-13 owner 承認・#187）。眉ラベル（種類）はその右
            HStack(spacing: JPSpace.s) {
                SheetCloseButton(onContent: true)
                    .accessibilityIdentifier("trunk.missingSheet.close")
                Text(part.kind.tabName)
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Color.white.opacity(TrunkPartsBoxText.missingShadowOpacity)
                .frame(width: 120, height: 120)
                .mask { TrunkPartView(part: part, size: 120, shadow: false) }
                .frame(height: 130)
                .accessibilityHidden(true)
            Text(TrunkPartsBoxText.missingTitle)
                .font(JPFont.display(20, relativeTo: .title3))
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Text(TrunkPartsBoxText.missingNote(fragments: fragments))
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 6)
            Spacer(minLength: 12)
            if let error = model.actionError {
                Text(error)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            VStack(spacing: 8) {
                if canExchange {
                    Button { Task { await exchange() } } label: {
                        TrunkButtonFace(title: TrunkPartsBoxText.exchangeTitle, kind: .main)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                    .accessibilityIdentifier("trunk.missingSheet.exchange")
                }
                Button(action: onGacha) {
                    TrunkButtonFace(title: L("カプセルを回す", "Turn the capsule machine"), kind: canExchange ? .secondary : .main)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trunk.missingSheet.gacha")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .webScreen()
        .onAppear { model.actionError = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.missingSheet")
    }

    /// かけら5つでこの部品と交換する。できたら閉じて知らせる（失敗の一言は `actionError`）
    private func exchange() async {
        guard await model.exchange(part.id) else { return }
        dismiss()
        toasts.show(TrunkPartsBoxText.exchangedNotice(part))
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

