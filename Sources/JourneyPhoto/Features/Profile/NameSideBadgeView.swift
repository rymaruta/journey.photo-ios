import SwiftUI

/// 名前の横の画面（板 BadgePicker・2026-10-09）。マイページの名前の行を押すと開く。
///
/// - 上: 名前を実際の大きさで出した下見（選んでいる途中の印がそのまま並ぶ）
/// - Pro の人だけ: Pro マークの形（絞り羽根 / PRO）
/// - 持っているバッジの格子。押すと1つ選ぶ（選んだものに真鍮の輪）・「なし」も選べる。
///   長押しで手に取って回す
/// - 「決める」でプロフィールの部分更新（`displayBadge`・`proMarkStyle`）
///
/// **開いたら先に `GET /user/badges` を呼ぶ。** サーバーはそこで数え直して保存し、保存の
/// `displayBadge` はその保存済みの持ち物で確かめる。読み終えるまで「決める」は押せない
/// （読めなかったときはプロフィールの持ち物のまま選ばせる）
///
/// **第1段階では Pro 限定の章の段は出さない**（まだ買えない＝押しても行き止まりになる）。
struct NameSideBadgeView: View {

    /// 開いた時点の自分のプロフィール
    let profile: UserProfile
    /// 棚へ進む口を出すか（棚から開いたときは出さない＝行き来の輪を作らない）
    var showsShelfLink = true

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    /// 選んでいるバッジの鍵（nil は「なし」）
    @State private var selected: String?
    @State private var style: ProMarkStyle = .iris
    @State private var saving = false
    @State private var errorMessage: String?
    /// 長押しで手に取ったメダル
    @State private var viewing: EarnedBadge?
    /// 持っているバッジ。開いた時点はプロフィールの値、`GET /user/badges` を読んだら差し替える
    @State private var badges: BadgeSet
    /// `GET /user/badges` を読み終えたか（失敗も含む）。それまで「決める」は押せない
    @State private var refreshed = false

    init(profile: UserProfile, showsShelfLink: Bool = true) {
        self.profile = profile
        self.showsShelfLink = showsShelfLink
        _selected = State(initialValue: NameSideChoice.initialSelection(profile))
        _style = State(initialValue: profile.markStyle)
        _badges = State(initialValue: profile.earnedBadges)
    }

    private var owned: [EarnedBadge] { BadgeCatalog.owned(badges) }
    private var selectedBadge: EarnedBadge? { selected.flatMap { badges[$0] } }

    /// 板: 4列・隙間 2pt
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(profile.isPro
                         ? L("名前の横に出すバッジを1つ選びます。Pro マークの形も選べます。長押しで手に取って回せます。",
                             "Choose one badge to show next to your name, and the shape of your Pro mark. Press and hold a badge to turn it in your hand.")
                         : L("名前の横に出すバッジを1つ選びます。長押しで手に取って回せます。",
                             "Choose one badge to show next to your name. Press and hold a badge to turn it in your hand."))
                        .font(.caption)
                        .lineSpacing(3)
                        .foregroundStyle(WebTheme.faint)
                        .padding(.horizontal, 20)
                    preview
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    if profile.isPro {
                        markStylePicker
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    Text(L("持っているバッジ", "Your badges"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    badgeGrid
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                    if showsShelfLink {
                        shelfLink
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                }
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom) { footer }
            .background(NameSideChoice.sheetBackground)
            .navigationTitle(L("名前の横", "Next to your name"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NameSideChoice.sheetBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(WebTheme.foreground)
                            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Labels.Common.close)
                }
            }
        }
        .presentationBackground(NameSideChoice.sheetBackground)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
        .fullScreenCover(item: $viewing) { badge in
            MedalViewerView(badge: badge, ownerName: profile.name)
        }
        .task { await refreshBadges() }
    }

    /// サーバーに数え直してもらう（ここで新しく取れたメダルも選べるようになる）
    private func refreshBadges() async {
        guard !refreshed else { return }
        let profiles = environment.profiles
        let status = try? await profiles.myBadges()
        if let status { badges = status.badges }
        refreshed = true
    }

    // MARK: - 下見

    /// 板: 「プロフィールでの見え方」。名前は明朝 26 のまま（実際の大きさ）
    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("プロフィールでの見え方", "How it looks on your profile"))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            HStack(spacing: 4) {
                Text(profile.name)
                    .font(JPFont.display(26, relativeTo: .title))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    // 明朝は 18pt を割らない（26 × 0.7 ≈ 18.2・JPFont の注記）
                    .minimumScaleFactor(0.7)
                NameMarks(verified: profile.verified, proStyle: profile.isPro ? style : nil,
                          badge: selectedBadge, nameSize: 26, relativeTo: .title, fit: .mincho)
            }
            .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
            Text(selectedBadge.map { BadgeCatalog.fullName($0.key, tier: $0.tier) }
                 ?? L("バッジを出さない", "No badge"))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pro マークの形

    private var markStylePicker: some View {
        HStack(spacing: 10) {
            Text(L("Pro マークの形", "Pro mark"))
                .font(.caption)
                .foregroundStyle(WebTheme.muted)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(ProMarkStyle.allCases) { option in
                    let on = style == option
                    Button { style = option } label: {
                        HStack(spacing: 6) {
                            ProMark(style: option, side: 18)
                            if option == .iris {
                                Text(option.label).font(.caption)
                            }
                        }
                        .foregroundStyle(on ? Color.white : WebTheme.muted)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 92, minHeight: WebTheme.minTapTarget)
                        .background(on ? NameSideChoice.chosenFill : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(on ? WebTheme.accent : Color.clear, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 持っているバッジ

    @ViewBuilder
    private var badgeGrid: some View {
        if owned.isEmpty && !refreshed {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if owned.isEmpty {
            Text(L("まだバッジはありません。写真を投稿したり旅を記録したりすると集まります。",
                   "No badges yet. Post photos and record your trips to collect them."))
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
                .padding(.horizontal, 6)
                .padding(.vertical, 12)
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(owned) { badge in
                    badgeCell(badge)
                }
                noneCell
            }
        }
    }

    private func badgeCell(_ badge: EarnedBadge) -> some View {
        let on = selected == badge.key
        return VStack(spacing: 5) {
            Image(BadgeCatalog.smallImage(badge.key, tier: badge.tier))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .padding(4)
                // 板: 選んだものは地の色 2pt を挟んだ真鍮の 2pt の輪
                .overlay(Circle().strokeBorder(on ? WebTheme.accent : Color.clear, lineWidth: 2))
            Text(BadgeCatalog.name(badge.key))
                .font(.caption.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : WebTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(WebTheme.minimumScale(forTextSize: 12))
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .contentShape(Rectangle())
        .onTapGesture { selected = badge.key }
        .onLongPressGesture(minimumDuration: 0.45, perform: { viewing = badge })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BadgeCatalog.fullName(badge.key, tier: badge.tier))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selected = badge.key }
        .accessibilityAction(named: L("手に取って回す", "Turn it in your hand")) { viewing = badge }
    }

    /// 「なし」（名前の横に何も出さない）
    private var noneCell: some View {
        let on = selected == nil
        return Button { selected = nil } label: {
            VStack(spacing: 5) {
                Circle()
                    .strokeBorder(WebTheme.outline, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "nosign")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(WebTheme.faint)
                    )
                    .padding(4)
                    .overlay(Circle().strokeBorder(on ? WebTheme.accent : Color.clear, lineWidth: 2))
                Text(L("なし", "None"))
                    .font(.caption.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.white : WebTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("バッジを出さない", "No badge"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var shelfLink: some View {
        NavigationLink {
            BadgeShelfView(mode: .mine, allowsChoosing: false)
        } label: {
            HStack(spacing: 6) {
                Text(L("バッジの棚を見る（集め方と次の段）", "Open the badge shelf"))
                    .font(.footnote.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            // 黒地の上のリンクは真鍮（CLAUDE.md の owner の好み）
            .foregroundStyle(WebTheme.accent)
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 決める

    private var footer: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .multilineTextAlignment(.center)
            }
            Button { Task { await save() } } label: {
                ZStack {
                    Text(L("決める", "Done"))
                        .font(.body.weight(.bold))
                        .opacity(saving ? 0 : 1)
                    if saving { ProgressView().tint(WebTheme.accentText) }
                }
                .foregroundStyle(WebTheme.accentText)
                .frame(maxWidth: .infinity, minHeight: 50)
                // 写真の無い画面の主ボタンは真鍮の塗りに墨の字（CLAUDE.md）
                .background(WebTheme.accentFill, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(saving || !refreshed)
            .opacity(refreshed ? 1 : 0.5)
            .accessibilityIdentifier("nameSide.save")
            Text(profile.isPro
                 ? L("バッジは1つ（Pro でも1つ）。Pro マークは Pro の間だけ出ます",
                     "One badge (Pro included). The Pro mark shows while you're Pro.")
                 : L("名前の横に出せるバッジは1つです", "You can show one badge next to your name"))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(NameSideChoice.sheetBackground)
    }

    private func save() async {
        guard !saving, refreshed else { return }
        guard let patch = NameSideChoice.patch(profile: profile, selected: selected, style: style) else {
            dismiss()
            return
        }
        saving = true
        errorMessage = nil
        do {
            try await environment.profiles.update(patch)
            saving = false
            // マイページはこの合図でプロフィールだけ読み直す（`MyPageView`）
            auth.noteProfileChanged()
            dismiss()
        } catch {
            saving = false
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("保存できませんでした。時間をおいてもう一度お試しください。",
                     "Couldn't save. Please try again later.")
        }
    }
}

/// 名前の横の画面の決まり（画面に依らない・テストで見張る）
enum NameSideChoice {

    /// シートの地（板: #0E0E0F）
    static let sheetBackground = ProMarkColors.color(0x0E0E0F)
    /// 選んでいる Pro マークの札の地（板: #17140E）
    static let chosenFill = ProMarkColors.color(0x17140E)

    /// 開いたときに選ばれているもの。**持っている鍵を選んでいるときだけ**（取り消された鍵は「なし」）
    static func initialSelection(_ profile: UserProfile) -> String? {
        guard let badge = profile.shownBadge, BadgeCatalog.isKnown(badge.key) else { return nil }
        return badge.key
    }

    /// 送る部分更新。**変わったものだけ**を載せ、何も変わっていなければ nil（送らずに閉じる）。
    ///
    /// - バッジ: 選んだ鍵、または「なし」（JSON の null）
    /// - Pro マークの形: Pro の人だけ
    static func patch(profile: UserProfile, selected: String?, style: ProMarkStyle) -> ProfilePatch? {
        var patch = ProfilePatch()
        var changed = false
        // 持っていない鍵を指していた人が「なし」のまま決めたら、その古い値も消す
        if selected != profile.chosenBadgeKey {
            patch.displayBadge = Clearable(selected)
            changed = true
        }
        if profile.isPro, style != profile.markStyle {
            patch.proMarkStyle = style.rawValue
            changed = true
        }
        return changed ? patch : nil
    }
}
