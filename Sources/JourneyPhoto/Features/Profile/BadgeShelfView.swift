import SwiftUI

/// バッジの棚（板 Shelf・2026-10-09）。
///
/// - **自分の棚**（お知らせの「NEW MEDAL」・名前の横の画面から）: 持っているメダル（色つき）と
///   まだのメダル（色を抜いて暗く）、それぞれ「あと◯で次」。`GET /user/badges` を読む
/// - **人の棚**（人の頁で名前の横のバッジを押す）: その人が持っているメダルだけ。
///   公開プロフィールの `badges` から作り、進み具合は出さない（本人にしか返らない）
///
/// 持っているメダルを押すと手に取って回せる。
struct BadgeShelfView: View {

    enum Mode: Hashable {
        case mine
        /// 人の棚。`profile` は開いた頁が読み終えていたもの（無ければここで読む）
        case other(userId: String)
    }

    let mode: Mode
    /// 開いた頁で読み終えていたプロフィール（人の棚で読み直さないため）
    var preloaded: UserProfile?
    /// 自分の棚に「名前の横に飾る」の札を出すか（名前の横の画面から来たときは出さない）
    var allowsChoosing = true

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore

    @State private var profile: UserProfile?
    @State private var status: BadgeStatus?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var viewing: EarnedBadge?
    @State private var showNameSide = false
    /// 「外す」を送っている間（二度押しで2本送らない）
    @State private var removing = false
    @EnvironmentObject private var toasts: ToastCenter

    init(mode: Mode, preloaded: UserProfile? = nil, allowsChoosing: Bool = true) {
        self.mode = mode
        self.preloaded = preloaded
        self.allowsChoosing = allowsChoosing
        _profile = State(initialValue: preloaded)
    }

    private var isMine: Bool { mode == .mine }

    private var items: [BadgeCatalog.ShelfItem] {
        BadgeShelfRules.items(mode: mode, status: status, profile: profile)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 板 v2 Shelf: 題は明朝（板の 30 は字の段に無いので画面の題の 26）
                Text(L("バッジ", "Badges"))
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)
                if isMine, allowsChoosing, let profile {
                    decorateSection(profile)
                }
                medalsSection
            }
            .padding(.horizontal, ProfileV2.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xl)
        }
        .webScreen()
        .navigationTitle(L("バッジ", "Badges"))
        .navigationBarTitleDisplayMode(.inline)
        // 題は上の明朝の見出しが受け持つ。中央は空けておく（戻る文字と読み上げには題を持つ）
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
        .task(id: auth.userId) { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $viewing) { badge in
            MedalViewerView(badge: badge, ownerName: profile?.name ?? "")
        }
        .sheet(isPresented: $showNameSide, onDismiss: { Task { await load() } }) {
            if let profile {
                NameSideBadgeView(profile: profile, showsShelfLink: false)
            }
        }
    }

    // MARK: - 名前の横に飾る

    /// 板 v2 Shelf: 上の札に**いま飾っているバッジ**（52pt の絵・「名前の横に飾る · 1つ（Pro でも1つ）」・名前）と、
    /// 右に「変える」（線のボタン → 名前の横の画面）と「外す」（飾りを外す・資格は残る）。
    /// 何も飾っていなければ「まだ選んでいません」と「選ぶ」
    private func decorateSection(_ profile: UserProfile) -> some View {
        let shown = profile.shownBadge.flatMap { BadgeCatalog.isKnown($0.key) ? $0 : nil }
        return HStack(spacing: JPSpace.s) {
            if let badge = shown {
                // 大きい絵を表示の画素ちょうどに縮める（名前の横と同じ・2026-10-09 判断）
                RasterBadgeArt(image: BadgeCatalog.largeImage(badge.key, tier: badge.tier), side: 52)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "seal")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(WebTheme.text3)
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("名前の横に飾る · 1つ（Pro でも1つ）", "Next to your name · one (Pro included)"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                Text(shown.map { BadgeCatalog.fullName($0.key, tier: $0.tier) } ?? L("まだ選んでいません", "Nothing chosen yet"))
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(shown == nil ? WebTheme.text2 : WebTheme.foreground)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { showNameSide = true } label: {
                Group {
                    if shown == nil {
                        Text(L("選ぶ", "Choose"))
                    } else {
                        Text(L("変える", "Change"))
                    }
                }
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .padding(.horizontal, JPSpace.s)
                    .frame(minHeight: JPHeight.inlineButton)
                    .overlay(Capsule().strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("名前の横のバッジを選ぶ", "Choose the badge next to your name"))
            if let badge = shown {
                Button { Task { await removeBadge(profile) } } label: {
                    Text(L("外す", "Remove"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .padding(.horizontal, JPSpace.xs)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(removing)
                .accessibilityLabel(L("\(BadgeCatalog.fullName(badge.key, tier: badge.tier))を外す",
                                      "Remove \(BadgeCatalog.fullName(badge.key, tier: badge.tier))"))
                .accessibilityIdentifier("shelf.removeBadge")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, JPSpace.xs)
        .padding(.vertical, JPSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        // v2 の札（#0E0E0F・白 8% の縁・角 16）
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.l))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }

    /// 飾りを外す（名前の横に何も出さない）。名前の横の画面の「なし」で決めるのと同じ部分更新
    /// （`NameSideChoice.patch`・Pro マークと公式の印は触らない）。外したら読み直してマイページにも知らせる
    private func removeBadge(_ profile: UserProfile) async {
        guard !removing,
              let patch = NameSideChoice.patch(profile: profile, selected: nil, style: profile.chosenProMark)
        else { return }
        removing = true
        defer { removing = false }
        do {
            try await environment.profiles.update(patch)
            auth.noteProfileChanged()
            await load()
        } catch {
            toasts.show((error as? LocalizedError)?.errorDescription
                        ?? L("外せませんでした。時間をおいてもう一度お試しください。",
                             "Couldn't remove it. Please try again later."),
                        kind: .failure)
        }
    }

    // MARK: - メダル

    /// 板 v2 Shelf: 眉「獲得したメダル」と右に「7 / 12」（等幅・持っている数だけ白）、その下に
    /// 真鍮の 2pt の進み線、3 列のメダル（84pt・札の地は敷かない・まだのものは色を抜いて 35%）
    private var medalsSection: some View {
        let shown = items
        let count = BadgeCatalog.shelfCount(shown)
        return VStack(alignment: .leading, spacing: JPSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(isMine ? L("獲得したメダル", "Medals")
                            : L("\(profile?.name ?? "") のメダル", "\(profile?.name ?? "")'s medals"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if isMine, !shown.isEmpty {
                    HStack(spacing: 0) {
                        Text("\(count.earned)").foregroundStyle(WebTheme.foreground)
                            .font(JPFont.number(JPTypeScale.footnote, weight: .semibold, relativeTo: .footnote))
                        Text(" / \(count.total)").foregroundStyle(WebTheme.text2)
                    }
                        .font(JPFont.mono(JPTypeScale.footnote, relativeTo: .footnote))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("\(count.total) 個のうち \(count.earned) 個", "\(count.earned) of \(count.total)"))
                }
            }
            if isMine, !shown.isEmpty {
                progressLine(earned: count.earned, total: count.total)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(WebTheme.danger)
            }
            if shown.isEmpty {
                if loading {
                    JPLoadingState(kind: .rows)
                } else if errorMessage == nil {
                    EmptyState(message: L("まだメダルはありません。", "No medals yet."))
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: JPSpace.xs), count: 3),
                          spacing: JPSpace.xxs) {
                    ForEach(shown) { item in
                        tile(item)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    /// 獲得の進み線（板 v2 Shelf: 2pt・地は白 10%・持っている割合だけ真鍮）。数は上の「7 / 12」が言う
    private func progressLine(earned: Int, total: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(WebTheme.accent)
                    .frame(width: proxy.size.width * BadgeShelfRules.progress(earned: earned, total: total))
            }
        }
        .frame(height: JPStroke.emphasis)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(_ item: BadgeCatalog.ShelfItem) -> some View {
        let content = VStack(spacing: JPSpace.xxs) {
            Image(BadgeCatalog.largeImage(item.key, tier: item.tier))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: BadgeShelfRules.medalSide, height: BadgeShelfRules.medalSide)
                // 板: まだのものは色を抜いて 35%。持っているものは影で浮かせる
                .grayscale(item.isEarned ? 0 : 1)
                .opacity(item.isEarned ? 1 : 0.35)
                .shadow(color: .black.opacity(item.isEarned ? 0.6 : 0), radius: 6, y: 6)
            Text(BadgeCatalog.name(item.key))
                .font(JPFont.footnote.weight(.semibold))
                .foregroundStyle(item.isEarned ? WebTheme.foreground : WebTheme.text3)
                .lineLimit(1)
                .minimumScaleFactor(WebTheme.minimumScale(forTextSize: 13))
            if let progress = item.progress {
                Text(progress)
                    .font(JPFont.caption.monospacedDigit())
                    .foregroundStyle(WebTheme.text3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, JPSpace.xs)
        .frame(maxWidth: .infinity, alignment: .top)

        if let earned = item.earned {
            Button { viewing = earned } label: { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(BadgeShelfRules.label(item))
                .accessibilityHint(L("手に取って回す", "Turn it in your hand"))
                .accessibilityIdentifier("shelf.medal.\(item.key)")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BadgeShelfRules.label(item))
        }
    }

    // MARK: - 読み込み

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        switch mode {
        case .mine:
            guard auth.userId != nil else { return }
            // 画面の値は先に取り出しておく（並べて走らせる2本は画面の外で動く）
            let profiles = environment.profiles
            async let fetchedStatus = try? profiles.myBadges()
            async let fetchedProfile = try? profiles.myProfile()
            let (newStatus, newProfile) = await (fetchedStatus, fetchedProfile)
            if let newProfile { profile = newProfile }
            if let newStatus { status = newStatus }
            // 進み具合が読めなくても、プロフィールの `badges` で持っているものは出す
            errorMessage = (newStatus == nil && status == nil)
                ? L("進み具合を読み込めませんでした。引っぱって読み直せます。",
                    "Couldn't load your progress. Pull to retry.")
                : nil
        case .other(let userId):
            let profiles = environment.profiles
            let fresh = try? await profiles.publicProfile(userId: userId)
            if let fresh {
                profile = fresh
                errorMessage = nil
            } else if profile == nil {
                errorMessage = Labels.Common.loadFailed
            }
        }
    }
}

/// 棚の決まり（画面に依らない・テストで見張る）
enum BadgeShelfRules {

    /// メダルの絵の一辺（板 v2 Shelf: 84。v1 は 72 の札の中）
    static let medalSide: CGFloat = 84

    /// 進み線の割合（0〜1）。全部が 0 なら 0（0 で割らない）
    static func progress(earned: Int, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(max(earned, 0), total)) / CGFloat(total)
    }

    /// 棚に並べるもの。
    /// - 自分: `GET /user/badges` が読めればそれ（進み具合つき）。読めなければプロフィールの持ち物だけ
    /// - 人: プロフィールの持ち物だけ（進み具合なし）
    static func items(mode: BadgeShelfView.Mode, status: BadgeStatus?, profile: UserProfile?) -> [BadgeCatalog.ShelfItem] {
        switch mode {
        case .mine:
            if let status {
                return BadgeCatalog.shelf(badges: status.badges, progress: status.progress)
            }
            return BadgeCatalog.shelf(badges: profile?.earnedBadges ?? BadgeSet(), progress: nil)
        case .other:
            return BadgeCatalog.shelf(badges: profile?.earnedBadges ?? BadgeSet(), progress: nil)
        }
    }

    /// 読み上げ（「都道府県 · 銀、あと17で次」「夜の光、まだ持っていません、あと5枚」）
    static func label(_ item: BadgeCatalog.ShelfItem) -> String {
        var parts: [String] = []
        if let earned = item.earned {
            parts.append(BadgeCatalog.fullName(item.key, tier: earned.tier))
        } else {
            parts.append(BadgeCatalog.name(item.key))
            parts.append(L("まだ持っていません", "not earned yet"))
        }
        if let progress = item.progress { parts.append(progress) }
        return parts.joined(separator: L("、", ", "))
    }
}
