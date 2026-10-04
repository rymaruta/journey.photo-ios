import SwiftUI

/// 「新しくなったこと」（2026-10-04）。更新して初めて開いたときに1回だけシートで出す
/// （決まりは `WhatsNew.pending`・`WhatsNewGate`）。設定の「新しくなったこと」からも開き直せる。
///
/// 写真の無い画面なので、板（DesignSystem「黒塗りの真鍮」）の決まりどおり:
/// 黒地・見出しは明朝・眉ラベルとアイコンは真鍮（黒地の上）・本文は 12pt 以上・
/// 押せる行は 44pt 以上・閉じる口は主ボタン1つ（`accentFill`＋墨）。
/// 押すと行ける項目は、シートを閉じてから下の札を切り替える（`TabRouter`）
struct WhatsNewView: View {

    let releases: [WhatsNew.Release]
    /// 主ボタンの文言。起動で出たときは「はじめる」、設定から開いたときは「閉じる」
    var primaryTitle: String = L("はじめる", "Get started")

    @Environment(\.dismiss) private var dismiss

    private var items: [WhatsNew.Item] { releases.flatMap(\.items) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        row(item, index: index)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Button { dismiss() } label: {
                Text(primaryTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WebTheme.accentFill, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(WebTheme.background)
            .accessibilityIdentifier("whatsNew.close")
        }
        .webScreen()
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("whatsNew")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT'S NEW")
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            Text(L("新しくなったこと", "What's new"))
                .font(JPFont.display(30, relativeTo: .largeTitle))
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private func row(_ item: WhatsNew.Item, index: Int) -> some View {
        if let destination = item.destination {
            Button { open(destination) } label: {
                rowLabel(item, chevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(hint(destination))
            .accessibilityIdentifier("whatsNew.item.\(index)")
        } else {
            rowLabel(item, chevron: false)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("whatsNew.item.\(index)")
        }
    }

    private func rowLabel(_ item: WhatsNew.Item, chevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(WebTheme.accent)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.localized)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                Text(item.detail.localized)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.faint)
                    .frame(height: 32)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: WebTheme.minTapTarget)
        .contentShape(Rectangle())
    }

    private func hint(_ destination: WhatsNew.Destination) -> String {
        switch destination {
        case .home: return L("ホームを開きます", "Opens Home")
        case .search: return L("探すを開きます", "Opens Search")
        case .map: return L("マップを開きます", "Opens the map")
        case .mypage: return L("マイページを開きます", "Opens My Page")
        }
    }

    /// シートを閉じてから札を切り替える（`RootView` が受けて、メニューのシートも下ろす）
    private func open(_ destination: WhatsNew.Destination) {
        dismiss()
        let router = TabRouter.shared
        switch destination {
        case .home: router.openHome()
        case .search: router.openSearch()
        case .map: router.openMap()
        case .mypage: router.openMyPage()
        }
    }
}
