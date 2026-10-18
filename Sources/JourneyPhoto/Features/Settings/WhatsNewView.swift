import SwiftUI

/// 「新しくなったこと」（2026-10-04）。更新して初めて開いたときに1回だけシートで出す
/// （決まりは `WhatsNew.pending`・`WhatsNewGate`）。設定の「新しくなったこと」からも開き直せる。
///
/// 写真の無い画面なので、板（DesignSystem「黒塗りの真鍮」）の決まりどおり:
/// 黒地・見出しは明朝・眉ラベルとアイコンは真鍮（黒地の上）・本文は 12pt 以上・
/// 押せる行は 44pt 以上・閉じる口は主ボタン1つ（`accentFill`＋墨）。
/// 押すと行ける項目は、シートを閉じてから下の札を切り替える（`TabRouter`）。
///
/// **履歴（`mode: .history`・2026-10-18 owner「過去の履歴を見れるようにしたい」）**: 設定から開いたとき。
/// いちばん上は最新の版を起動時と同じ形で、その下に眉ラベル「これまでのお知らせ」（`JPEyebrowLine`・
/// 板 02 の眉ラベルと右へ消える真鍮の線）、版ごとに白 8% の区切り線（板 Settings の行の間の線）と
/// 見出し「1.0.82 · 10月10日」（板 Settings の節の見出しと同じ 12・500・弱い白。数字は等幅）。
/// 並べ方は `WhatsNew.sections`（Linux で試せる）。起動時（`.launch`）の見た目は変えない
struct WhatsNewView: View {

    let releases: [WhatsNew.Release]
    /// 起動時は `.launch`（新しい分を平らに）、設定から開いたときは `.history`
    var mode: WhatsNew.Mode = .launch
    /// 主ボタンの文言。起動で出たときは「はじめる」、設定から開いたときは「閉じる」
    var primaryTitle: String = L("はじめる", "Get started")

    @Environment(\.dismiss) private var dismiss

    private var sections: [WhatsNew.Section] { WhatsNew.sections(releases, mode: mode) }

    /// 目印 `whatsNew.item.<n>` の n は画面全体の通し番号（起動時の今までの番号と同じ）
    private func offset(of section: Int) -> Int {
        sections.prefix(section).reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    VStack(alignment: .leading, spacing: 0) {
                        if index == 1 {
                            // 履歴の入口。2つ目のかたまりの上に1回だけ
                            JPEyebrowLine(L("これまでのお知らせ", "Earlier updates"))
                                .padding(.top, JPSpace.s)
                                .padding(.bottom, JPSpace.xs)
                                .accessibilityIdentifier("whatsNew.history")
                        }
                        if let heading = section.heading {
                            // 眉ラベルの真下の1つ目は線を引かない（眉ラベルの線と二重になる）
                            releaseHeading(heading, version: section.id, rule: index > 1)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(section.items.enumerated()), id: \.offset) { i, item in
                                row(item, index: offset(of: index) + i)
                            }
                        }
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
        // 画面全体に目印を付けない——付けると中の部品（主ボタンの `whatsNew.close`）の目印まで
        // 上書きされ、UI テストが主ボタンを見つけられなかった（run 344）
    }

    /// 版の区切り: 白 8% の 1px の線（板 Settings の行の間の線）→ 12 の余白 → 見出し（12・500・text3）
    @ViewBuilder
    private func releaseHeading(_ text: String, version: String, rule: Bool) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            if rule {
                Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(JPFont.mono(JPTypeScale.caption, medium: true))
                .foregroundStyle(WebTheme.text3)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("whatsNew.release.\(version)")
        }
        .padding(.top, JPSpace.xs)
        .padding(.bottom, JPSpace.xxs)
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
