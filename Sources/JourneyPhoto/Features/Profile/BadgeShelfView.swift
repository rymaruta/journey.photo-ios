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
                if isMine, allowsChoosing, let profile {
                    decorateSection(profile)
                }
                medalsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationTitle(L("バッジ", "Badges"))
        .navigationBarTitleDisplayMode(.inline)
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

    /// 板: 「名前の横に飾る」。いま出しているバッジ（無ければ「まだ選んでいません」）。押すと名前の横の画面
    private func decorateSection(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("名前の横に飾る", "Next to your name"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Spacer()
                Text(L("1つ", "One"))
                    .font(JPFont.mono(12))
                    .foregroundStyle(WebTheme.faint)
            }
            Button { showNameSide = true } label: {
                HStack(spacing: 10) {
                    if let badge = profile.shownBadge, BadgeCatalog.isKnown(badge.key) {
                        Image(BadgeCatalog.smallImage(badge.key, tier: badge.tier))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BadgeCatalog.fullName(badge.key, tier: badge.tier))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WebTheme.foreground)
                            Text(L("名前の横に出ています", "Shown next to your name"))
                                .font(.caption)
                                .foregroundStyle(WebTheme.accent)
                        }
                    } else {
                        Image(systemName: "seal")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(WebTheme.faint)
                            .frame(width: 40, height: 40)
                        Text(L("まだ選んでいません", "Nothing chosen yet"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WebTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Text(L("変える", "Change"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WebTheme.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(ProMarkColors.color(0x0E0E0E), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ProMarkColors.color(0x3A3220), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("名前の横のバッジを選ぶ", "Choose the badge next to your name"))
        }
    }

    // MARK: - メダル

    private var medalsSection: some View {
        let shown = items
        let count = BadgeCatalog.shelfCount(shown)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isMine ? L("獲得したメダル", "Medals")
                            : L("\(profile?.name ?? "") のメダル", "\(profile?.name ?? "")'s medals"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .lineLimit(1)
                Spacer()
                if isMine, !shown.isEmpty {
                    HStack(spacing: 0) {
                        Text("\(count.earned)").foregroundStyle(WebTheme.foreground)
                        Text(" / \(count.total)").foregroundStyle(WebTheme.faint)
                    }
                        .font(JPFont.mono(12))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("\(count.total) 個のうち \(count.earned) 個", "\(count.earned) of \(count.total)"))
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(WebTheme.danger)
            }
            if shown.isEmpty {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if errorMessage == nil {
                    Text(L("まだメダルはありません。", "No medals yet."))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted2)
                        .padding(.vertical, 20)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(shown) { item in
                        tile(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ item: BadgeCatalog.ShelfItem) -> some View {
        let content = VStack(spacing: 5) {
            Image(BadgeCatalog.largeImage(item.key, tier: item.tier))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                // 板: まだのものは色を抜いて 35%
                .grayscale(item.isEarned ? 0 : 1)
                .opacity(item.isEarned ? 1 : 0.35)
            Text(BadgeCatalog.name(item.key))
                .font(.caption.weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(WebTheme.minimumScale(forTextSize: 12))
            if let progress = item.progress {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .top)
        .background(ProMarkColors.color(0x0B0B0B), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ProMarkColors.color(0x1F1F1F), lineWidth: 1))

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
