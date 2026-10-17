import SwiftUI

/// トランクの型（モック Models.dc.html・無料の4型＋特別なトランクの入口・2026-10-17）。
///
/// 型を替えても、貼ったラベルと古び方はそのまま引き継がれる（サーバーは型の名前だけを持つ）。
/// 選んでいる型の札は真鍮の 2pt の縁と「✓ 使っている型」。
struct TrunkModelsView: View {
    @ObservedObject var model: TrunkViewModel
    var ownerName: String?

    var body: some View {
        ScrollView {
            if let state = model.state {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("だれでも使える \(TrunkModel.free.count) 型", "\(TrunkModel.free.count) styles for everyone"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(L("型を替えても、貼ったラベルと古び方はそのまま引き継がれます。",
                           "Your labels and the wear carry over when you change style."))
                        .font(JPFont.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(TrunkStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    if let error = model.actionError {
                        Text(error)
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.danger)
                            .padding(.top, 8)
                    }
                    VStack(spacing: 10) {
                        ForEach(TrunkModel.free) { m in
                            TrunkModelCard(trunk: m, state: state, ownerName: ownerName,
                                           selected: state.effectiveModel == m) {
                                Task { await model.setModel(m) }
                            }
                        }
                    }
                    .padding(.top, 14)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(L("トランクの型", "Trunk styles"))
                    NavigationLink {
                        TrunkProModelsView(model: model, ownerName: ownerName)
                    } label: {
                        HStack(spacing: 8) {
                            Text(L("特別なトランク", "Special trunks"))
                                .font(.subheadline)
                                .foregroundStyle(WebTheme.text)
                            TrunkProTag()
                            Text(L("\(TrunkModel.pro.count) 型", "\(TrunkModel.pro.count) styles"))
                                .font(JPFont.footnote)
                                .foregroundStyle(TrunkStyle.muted)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(TrunkStyle.muted)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                    .accessibilityIdentifier("trunk.models.pro")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            } else {
                JPLoadingState(kind: .rows)
            }
        }
        .webScreen()
        .navigationTitle(L("トランクの型", "Trunk style"))
        .navigationBarTitleDisplayMode(.inline)
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.models.screen")
    }
}

/// 型の札（左に小さいトランク・右に名前・素材・古び方）
struct TrunkModelCard: View {
    let trunk: TrunkModel
    let state: TrunkState
    var ownerName: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let info = TrunkText.info(trunk)
        Button(action: action) {
            HStack(spacing: 12) {
                // モック: 360×300 を 0.389 倍（140×117）・ラベルは2枚
                TrunkFigure(model: trunk, posts: state.posts ?? 0, stuck: Array(state.stuck.prefix(2)),
                            ownerName: ownerName, width: 140)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.name)
                        .font(JPFont.display(18, relativeTo: .title3))
                        .foregroundStyle(WebTheme.text)
                    Text(info.material)
                        .font(.caption)
                        .lineSpacing(2)
                        .foregroundStyle(TrunkStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(info.aging)
                        .font(.caption)
                        .lineSpacing(2)
                        .foregroundStyle(TrunkStyle.faint)
                        .fixedSize(horizontal: false, vertical: true)
                    if selected {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .accessibilityHidden(true)
                            Text(L("使っている型", "In use"))
                                .font(JPFont.footnote.weight(.semibold))
                        }
                        .foregroundStyle(WebTheme.accent)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 16).strokeBorder(WebTheme.accent, lineWidth: 2) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(info.name)。\(info.material)。\(info.aging)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("trunk.models.card")
    }
}

/// 特別なトランク（Pro の6型・モック PaidTrunks.dc.html を電話の幅に）。
///
/// Pro の人は札を押すとその型になる。Pro でない人には型の説明を見せ、押すと Pro の案内を開く
struct TrunkProModelsView: View {
    @ObservedObject var model: TrunkViewModel
    var ownerName: String?

    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("SPECIAL TRUNKS · Pro に含まれる \(TrunkModel.pro.count) 型",
                       "SPECIAL TRUNKS · \(TrunkModel.pro.count) styles with Pro"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Text(L("本物の職人の仕事を、手のひらに", "Real craftsmanship, in your hand"))
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                Text(L("どれも実在の旅道具の作り方から起こしています。Pro の間は6型すべてを自由に替えられます。古び方もその素材らしく変わります。貼ったラベルはどの型にもそのまま移ります。",
                       "Each is drawn from how real travel gear is made. With Pro you can switch among all six. Each wears in its own way, and your labels move to any style."))
                    .font(.subheadline)
                    .lineSpacing(5)
                    .foregroundStyle(TrunkStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                if let error = model.actionError {
                    Text(error)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .padding(.top, 8)
                }
                VStack(spacing: 20) {
                    ForEach(TrunkModel.pro) { m in proCard(m) }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .webScreen()
        .navigationTitle(L("特別なトランク", "Special trunks"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPaywall, onDismiss: {
            // 買えたかもしれない: Pro の型を選べるか読み直す
            Task { await model.refreshAfterPaywall() }
        }) { PaywallView() }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.proModels.screen")
    }

    private func proCard(_ trunk: TrunkModel) -> some View {
        let info = TrunkText.info(trunk)
        let state = model.state
        let isPro = state?.isPro ?? false
        let selected = state?.effectiveModel == trunk
        return Button {
            if isPro { Task { await model.setModel(trunk) } } else { showPaywall = true }
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                TrunkFigureFit(model: trunk, posts: state?.posts ?? 0, stuck: Array((state?.stuck ?? []).prefix(3)),
                               ownerName: ownerName, maxWidth: 300)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(info.name)
                            .font(JPFont.display(24, relativeTo: .title2))
                            .foregroundStyle(WebTheme.text)
                        Spacer(minLength: 0)
                        TrunkProTag()
                    }
                    if let concept = info.concept {
                        Text(concept)
                            .font(JPFont.footnote)
                            .lineSpacing(4)
                            .foregroundStyle(TrunkStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        specRow(L("素材", "Material"), info.material)
                        if let hardware = info.hardware { specRow(L("金具", "Fittings"), hardware) }
                        specRow(L("古び方", "Wear"), info.aging)
                        if let only = info.only { specRow(L("この型だけ", "Only here"), only, accent: true) }
                    }
                    .padding(.top, 12)
                    HStack(spacing: 6) {
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).accessibilityHidden(true)
                            Text(L("使っている型", "In use"))
                        } else {
                            Text(isPro ? L("この型にする", "Use this style") : L("Pro で使う", "Use with Pro"))
                        }
                    }
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    .frame(minHeight: WebTheme.minTapTarget)
                }
            }
            .padding(20)
            .background(Color(trunk: TrunkRGBA(0x0B0B0B)), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(selected ? WebTheme.accent : TrunkStyle.line, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("trunk.proModels.card")
    }

    private func specRow(_ title: String, _ value: String, accent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(TrunkStyle.faint)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineSpacing(2)
                .foregroundStyle(accent ? WebTheme.accent : TrunkStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
