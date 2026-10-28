import SwiftUI
import UIKit

/// 名前の横の画面（板 BadgePicker・2026-10-09）。マイページの名前の行を押すと開く。
///
/// - 上: 名前を実際の大きさで出した下見（選んでいる途中の印がそのまま並ぶ）
/// - Pro の人だけ: Pro マークの形（絞り羽根 / PRO / 外す）
/// - 公式の人だけ: 公式の印（付ける / 外す）
/// - 持っているバッジの格子。押すと1つ選ぶ（選んだものに真鍮の輪）・「なし」も選べる。
///   長押しで手に取って回す
/// - 「決める」でプロフィールの部分更新（`displayBadge`・`proMarkStyle`）
///
/// **開いたら先に `GET /user/badges` を呼ぶ。** サーバーはそこで数え直して保存し、保存の
/// `displayBadge` はその保存済みの持ち物で確かめる。読み終えるまで「決める」は押せない
/// （読めなかったときはプロフィールの持ち物のまま選ばせる）
///
/// **「PRO 限定」の段（第2段階・板 BadgePicker）**: まだ持っていない Pro 限定のバッジ（サポーター章・
/// これから届く季節の章・第3段階の機能の章）を暗く並べる。Pro でなければ鍵の印を付け、押すと
/// Pro の案内（板 63）。Pro の人には鍵も「Pro で集める」も出さない（届くのを待つだけ）。
///
/// **Pro の人の「PRO 限定」の段（2026-10-09 判断）**: 以前は押しても何も起きず説明も無かった。
/// 眉ラベルの下に「季節ごとに届く・届いたら上から選べる」の一行を置き、まだ届いていない章を押すと
/// 届く時期を下の知らせ（`ToastOverlay`）で出す（`ProChapters.arrivalNote`）。読み上げも同じ文。
///
/// **格子の絵（2026-10-09 判断）**: 2つの格子とも大きい絵を表示の画素ちょうどに縮めて出す
/// （`RasterBadgeArt`・名前の横と同じ・板 BadgePicker）。`-s` の引き伸ばしはぼやけていた。
/// 機能の章（暁・圏外）も 2026-10-10 に板の大きい絵を取り込んだので、すべて大きい絵
///
/// **印の取り外し（2026-10-10 owner「メダルと同様に取り外しできるように」）**: Pro マークと公式の印も
/// バッジと同じく名前の横に「付ける／外す」もの。外しても資格（Pro・公式）は残り、いつでも付け直せる
/// （公式の資格の付け外しは運営だけのまま）。外すと自分にも他の人にも出ない（サーバーが公開の形から落とす）。
///
/// 2026-10-10 判断（並べ方）: 板（BadgePicker）の Pro マークの形は札と2択を1行に並べるが、3択にすると
/// 390pt 幅に収まらない（92pt × 3 ＋ 札）。札を上の行に置き、下の行に同じ幅の選択肢を横いっぱいに並べる。
/// 「外す」の絵は板に手本が無いので、バッジの「なし」と同じ点線の丸と斜線（`NameSideNoneMark`）を小さくして使う。
/// 公式の印の段も同じ形（付ける / 外す）で、公式の人にだけ出す
struct NameSideBadgeView: View {

    /// 開いた時点の自分のプロフィール
    let profile: UserProfile
    /// 棚へ進む口を出すか（棚から開いたときは出さない＝行き来の輪を作らない）
    var showsShelfLink = true

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss
    /// Pro の案内（PRO 限定の段から）
    @State private var showPaywall = false
    /// 案内を開いた時点の「サーバーに渡し終えた回数」。閉じたときに進んでいれば買えた
    @State private var deliveredAtPaywall = 0

    /// 選んでいるバッジの鍵（nil は「なし」）
    @State private var selected: String?
    /// 選んでいる Pro マークの形（nil は外す）
    @State private var style: ProMarkStyle? = .iris
    /// 公式の印を付けているか（公式の人だけ意味を持つ）
    @State private var verifiedOn = true
    /// 初期メンバーの印の本人の設定（nil は決めていない＝既定。資格のある人だけ意味を持つ）
    @State private var earlyOn: Bool?
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
        _style = State(initialValue: profile.chosenProMark)
        _verifiedOn = State(initialValue: !profile.verifiedMarkRemoved)
        _earlyOn = State(initialValue: profile.earlyMarkChoice)
        _badges = State(initialValue: profile.earnedBadges)
    }

    private var owned: [EarnedBadge] { BadgeCatalog.owned(badges) }
    /// 公式の資格があるか（外していても true）
    private var isVerified: Bool { profile.verified == true }
    private var selectedBadge: EarnedBadge? { selected.flatMap { badges[$0] } }
    /// 初期メンバーの印の資格（初期ユーザーのバッジ。`GET /user/badges` を読んだらそちらで見る）
    private var isEarlyMember: Bool { badges[FoundingGiftGate.badgeKey] != nil }
    /// この設定なら初期メンバーの印が名前の横に出るか（下見・サーバーの `showsEarlyMark` と同じ規則）
    private var earlyShown: Bool {
        NameSideChoice.earlyShown(profile: profile, badges: badges, selected: selected, style: style,
                                  verifiedOn: verifiedOn, earlyOn: earlyOn)
    }

    /// 板: 4列・隙間 2pt
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(NameSideChoice.intro(isPro: profile.isPro, verified: isVerified))
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
                    if isVerified {
                        verifiedPicker
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    if isEarlyMember {
                        earlyPicker
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    // 板 v2 BadgePicker: 節の見出しは眉（真鍮＋消える線・土台の `JPEyebrowLine`）
                    JPEyebrowLine(L("持っているバッジ", "Your badges"))
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    badgeGrid
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                    proSection
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
                // 板 v2 BadgePicker: 題は明朝 22（`JPFont.cardTitle`）
                ToolbarItem(placement: .principal) {
                    Text(L("名前の横", "Next to your name"))
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .accessibilityAddTraits(.isHeader)
                }
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
        // 買えたら（サーバーが受け取ったら）この画面も閉じる。マイページが Pro の姿で読み直す
        .fullScreenCover(isPresented: $showPaywall, onDismiss: {
            if store.deliveredRevision != deliveredAtPaywall { dismiss() }
        }) {
            PaywallView()
        }
        // シートの上ではアプリの下の知らせ（`RootView`）が隠れるので、ここにも置く（`TripPickerView` と同じ）。
        // 足元の「決める」と注記（90pt 前後）に重ねない
        .overlay(alignment: .bottom) {
            ToastOverlay().padding(.bottom, 110)
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

    /// 板 v2: 「プロフィールでの見え方」。**黒地の札**（マイページと同じ地で、実寸の名前・印を見せる）。
    /// 名前は明朝 26 のまま（実際の大きさ）。見出しは 12 の text-3（板 v2 の `.cap`）
    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("プロフィールでの見え方", "How it looks on your profile"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
            HStack(spacing: 4) {
                Text(profile.name)
                    .font(JPFont.display(26, relativeTo: .title))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    // 明朝は 18pt を割らない（26 × 0.7 ≈ 18.2・JPFont の注記）
                    .minimumScaleFactor(0.7)
                NameMarks(verified: isVerified && verifiedOn, proStyle: profile.isPro ? style : nil,
                          early: earlyShown, badge: selectedBadge, nameSize: 26, relativeTo: .title, fit: .mincho)
            }
            .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
            Text(selectedBadge.map { BadgeCatalog.fullName($0.key, tier: $0.tier) }
                 ?? L("バッジを出さない", "No badge"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
        }
        .padding(.horizontal, JPSpace.m)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jpCardFace(fill: WebTheme.background)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pro マークの形

    /// 板の切り替え（地 6%・選んだものは #17140E の地に真鍮の 1pt の縁）。札は上の行、選択肢は下の行に
    /// 同じ幅で並べる（3択が 390pt 幅に収まるように・上の注記）
    private var markStylePicker: some View {
        markRow(title: L("Pro マークの形", "Pro mark")) {
            ForEach(ProMarkStyle.allCases) { option in
                markOption(on: style == option, label: option.label,
                           identifier: "nameSide.proMark.\(option.rawValue)",
                           action: { style = option }) {
                    HStack(spacing: 6) {
                        ProMark(style: option, side: 18)
                        if option == .iris {
                            Text(option.label).font(.caption)
                        }
                    }
                }
            }
            markOption(on: style == nil, label: L("Pro マークを外す", "Remove the Pro mark"),
                       identifier: "nameSide.proMark.none",
                       action: { style = nil }) {
                removeLabel
            }
        }
    }

    // MARK: - 公式の印

    /// 公式の人だけ。付ける / 外す（資格そのものは運営だけが付け外しする）
    private var verifiedPicker: some View {
        markRow(title: L("公式の印", "Verified mark")) {
            markOption(on: verifiedOn, label: L("公式の印を付ける", "Show the verified mark"),
                       identifier: "nameSide.verified.on",
                       action: { verifiedOn = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(WebTheme.accentText, WebTheme.accent)
                        .accessibilityHidden(true)
                    Text(L("付ける", "Show")).font(.caption)
                }
            }
            markOption(on: !verifiedOn, label: L("公式の印を外す", "Remove the verified mark"),
                       identifier: "nameSide.verified.off",
                       action: { verifiedOn = false }) {
                removeLabel
            }
        }
    }

    // MARK: - 初期メンバーの印

    /// 初期ユーザーのバッジを持つ人だけ。付ける / 外す。**選ばれている札は本人が決めた値だけ**
    /// （2026-10-28 Web のレビューの指摘と同じ判断: 出ているかで札を選ぶと、既定で出ている人の
    /// 「付ける」が最初から選ばれていて、押しても決めたことにならない）。決めるまでは下の一行で今の状態を言う
    private var earlyPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            markRow(title: L("初期メンバーの印", "Early member mark")) {
                markOption(on: earlyOn == true, label: L("初期メンバーの印を付ける", "Show the early member mark"),
                           identifier: "nameSide.early.on",
                           action: { earlyOn = true }) {
                    HStack(spacing: 6) {
                        EarlyMemberMark(side: 18).accessibilityHidden(true)
                        Text(L("付ける", "Show")).font(.caption)
                    }
                }
                markOption(on: earlyOn == false, label: L("初期メンバーの印を外す", "Remove the early member mark"),
                           identifier: "nameSide.early.off",
                           action: { earlyOn = false }) {
                    removeLabel
                }
            }
            if earlyOn == nil {
                Text(NameSideChoice.earlyAutoNote(shown: earlyShown))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nameSide.early.auto")
            }
        }
    }

    /// 「外す」の札（バッジの「なし」と同じ点線の丸と斜線を小さく）
    private var removeLabel: some View {
        HStack(spacing: 6) {
            NameSideNoneMark(side: 18)
            Text(L("外す", "Remove")).font(.caption)
        }
    }

    private func markRow<Options: View>(title: String,
                                        @ViewBuilder options: () -> Options) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
            // 板 v2: 選択肢は1つずつの札（間 8）。入れ物の地は敷かない
            HStack(spacing: JPSpace.xs) {
                options()
            }
        }
    }

    private func markOption<Content: View>(on: Bool, label: String, identifier: String,
                                           action: @escaping () -> Void,
                                           @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .lineLimit(1)
                .minimumScaleFactor(WebTheme.minimumScale(forTextSize: 12))
                .foregroundStyle(on ? Color.white : WebTheme.text2)
                .padding(.horizontal, 8)
                // 板 v2: 48・角 12・選んでいないものは白 8% の縁、選んだものは真鍮の 2pt の縁（形でも分かる）
                .frame(maxWidth: .infinity, minHeight: JPHeight.field)
                .background(on ? NameSideChoice.chosenFill : Color.clear,
                            in: RoundedRectangle(cornerRadius: JPRadius.field))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.field)
                    .strokeBorder(on ? WebTheme.accent : WebTheme.hairline,
                                  lineWidth: on ? JPStroke.emphasis : JPStroke.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
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
            RasterBadgeArt(image: BadgeCatalog.largeImage(badge.key, tier: badge.tier),
                           side: NameSideChoice.ownedArtSide)
                .padding(4)
                // 板: 選んだものは地の色 2pt を挟んだ真鍮の 2pt の輪
                .overlay(Circle().strokeBorder(on ? WebTheme.accent : Color.clear, lineWidth: 2))
            Text(BadgeCatalog.name(badge.key))
                .font(.caption.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : WebTheme.text2)
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
        .accessibilityIdentifier("nameSide.badge.\(badge.key)")
    }

    /// 「なし」（名前の横に何も出さない）
    private var noneCell: some View {
        let on = selected == nil
        return Button { selected = nil } label: {
            VStack(spacing: 5) {
                NameSideNoneMark(side: 56)
                    .padding(4)
                    .overlay(Circle().strokeBorder(on ? WebTheme.accent : Color.clear, lineWidth: 2))
                Text(L("なし", "None"))
                    .font(.caption.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.white : WebTheme.text2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("バッジを出さない", "No badge"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - PRO 限定

    private var lockedItems: [ProChapters.LockedItem] { ProChapters.lockedItems(owned: badges) }

    private func openPaywall() {
        deliveredAtPaywall = store.deliveredRevision
        showPaywall = true
    }

    /// 板: 眉ラベル「PRO 限定」と右に「Pro で集める」（真鍮・44pt）、48pt の絵を 55% で4列・右下に鍵
    @ViewBuilder
    private var proSection: some View {
        let items = lockedItems
        if !items.isEmpty {
            HStack {
                Text(L("PRO 限定", "PRO ONLY"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Spacer(minLength: 8)
                if !profile.isPro {
                    Button { openPaywall() } label: {
                        Text(L("Pro で集める", "Collect with Pro"))
                            .font(.caption)
                            .foregroundStyle(WebTheme.accent)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("nameSide.proCollect")
                }
            }
            .frame(minHeight: WebTheme.minTapTarget)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            if profile.isPro {
                // Pro の人には「待てば届く」ことと、届いた後の選び方を一行で言う（白の本文系・12pt）
                Text(NameSideChoice.proWaitingNote)
                    .font(.caption)
                    .lineSpacing(3)
                    .foregroundStyle(WebTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("nameSide.proNote")
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(items) { item in
                    lockedCell(item)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func lockedCell(_ item: ProChapters.LockedItem) -> some View {
        let locked = !profile.isPro
        let note = ProChapters.arrivalNote(item)
        return Button {
            if locked {
                openPaywall()
            } else {
                // Pro の人: 届く時期を知らせる（VoiceOver には読み上げでも同じ文）
                toasts.show(note, kind: .info)
                // 押した名前の読み上げと重ならないよう少し待つ（`SavedSpotsMapView` の `announce` と同じ）
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    UIAccessibility.post(notification: .announcement, argument: note)
                }
            }
        } label: {
            VStack(spacing: 4) {
                RasterBadgeArt(image: item.image, side: NameSideChoice.lockedArtSide)
                    .opacity(0.55)
                    .overlay(alignment: .bottomTrailing) {
                        if locked {
                            // 板: 16pt・真鍮の線 2・地の色の丸（角 8・内側 2）。右 -3・下 -2 にはみ出す
                            Image(systemName: "lock")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(WebTheme.accent)
                                .frame(width: 16, height: 16)
                                .background(NameSideChoice.sheetBackground, in: RoundedRectangle(cornerRadius: 8))
                                .offset(x: 3, y: 2)
                        }
                    }
                Text(item.name)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(WebTheme.minimumScale(forTextSize: 12))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 80)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? L("\(item.name)（Pro 限定）", "\(item.name) (Pro only)")
                                   : L("\(item.name)（まだ届いていません）", "\(item.name) (not yet)"))
        .accessibilityHint(locked ? L("Pro の案内を開きます", "Opens the Pro page") : note)
        .accessibilityIdentifier("nameSide.pro.\(item.id)")
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
        .accessibilityIdentifier("nameSide.shelf")
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
                // 写真の無い画面の主ボタンは真鍮の塗りに墨の字（CLAUDE.md・土台の `JPPillStyle.main`）
                Text(L("決める", "Done"))
                    .opacity(saving ? 0 : 1)
                    .jpPillButton(.main(onPhoto: false))
                    .overlay { if saving { ProgressView().tint(WebTheme.accentText) } }
            }
            .buttonStyle(.plain)
            .disabled(saving || !refreshed)
            .opacity(refreshed ? 1 : 0.5)
            .accessibilityIdentifier("nameSide.save")
            // 板の文言（第2段階から Pro があるので、Pro でない人にも同じ文を出す）
            Text(L("バッジは1つ（Pro でも1つ）。Pro マークは Pro の間だけ出ます",
                   "One badge (Pro included). The Pro mark shows while you're Pro."))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(NameSideChoice.sheetBackground)
    }

    private func save() async {
        guard !saving, refreshed else { return }
        guard let patch = NameSideChoice.patch(profile: profile, selected: selected, style: style,
                                               verifiedOn: verifiedOn,
                                               earlyOn: isEarlyMember ? earlyOn : nil) else {
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

    /// 「持っているバッジ」の絵の一辺（板: 56pt）
    static let ownedArtSide: Double = 56
    /// 「PRO 限定」の絵の一辺（板: 48pt）
    static let lockedArtSide: Double = 48

    /// Pro の人の「PRO 限定」の段の一行（2026-10-09）
    static var proWaitingNote: String {
        L("Pro の間に、季節ごとに届きます。届いたら上の「持っているバッジ」から選べます",
          "While you're Pro, a new one arrives each season. Once it arrives, choose it from “Your badges” above.")
    }

    /// 上の説明の一行。持っている資格に合わせて、付け外しできる印を言う（2026-10-10）
    static func intro(isPro: Bool, verified: Bool) -> String {
        switch (isPro, verified) {
        case (true, true):
            return L("名前の横に出すバッジを1つ選びます。Pro マークの形と公式の印も選べ、外すこともできます。長押しで手に取って回せます。",
                     "Choose one badge to show next to your name. You can also choose your Pro mark and verified mark, or remove them. Press and hold a badge to turn it in your hand.")
        case (true, false):
            return L("名前の横に出すバッジを1つ選びます。Pro マークの形も選べ、外すこともできます。長押しで手に取って回せます。",
                     "Choose one badge to show next to your name, and the shape of your Pro mark, or remove it. Press and hold a badge to turn it in your hand.")
        case (false, true):
            return L("名前の横に出すバッジを1つ選びます。公式の印は外すこともできます。長押しで手に取って回せます。",
                     "Choose one badge to show next to your name. You can also remove your verified mark. Press and hold a badge to turn it in your hand.")
        case (false, false):
            return L("名前の横に出すバッジを1つ選びます。長押しで手に取って回せます。",
                     "Choose one badge to show next to your name. Press and hold a badge to turn it in your hand.")
        }
    }

    /// 初期メンバーの印がこの設定なら出るか（2026-10-28）。**サーバーの `showsEarlyMark` と同じ規則**:
    /// 資格があり、本人が決めていればそれ、決めていなければ（既定）名前の横に公式の印・Pro マーク・
    /// 選んだバッジのどれも出ていないとき。保存した後に出すのはサーバーの答え（`UserProfile.showsEarlyMark`）
    static func earlyShown(qualified: Bool, choice: Bool?, verifiedShown: Bool, proShown: Bool,
                           badgeShown: Bool) -> Bool {
        guard qualified else { return false }
        if let choice { return choice }
        return !verifiedShown && !proShown && !badgeShown
    }

    /// 画面の今の選び方から、上の規則の入力を組む（下見に使う）。**Pro マークは選んでいる形**
    /// （`style`。nil は外す）で見る——開いたときの値で見ると、外しても下見が変わらない
    static func earlyShown(profile: UserProfile, badges: BadgeSet, selected: String?, style: ProMarkStyle?,
                           verifiedOn: Bool, earlyOn: Bool?) -> Bool {
        earlyShown(qualified: badges[FoundingGiftGate.badgeKey] != nil, choice: earlyOn,
                   verifiedShown: profile.verified == true && verifiedOn,
                   proShown: profile.isPro && style != nil,
                   badgeShown: selected.flatMap { badges[$0] } != nil
                       || keepsUnknownOwnedBadge(profile: profile, selected: selected))
    }

    /// 決めていない（既定の）ときの一行。いま付いているか・外れているかと、その理由
    static func earlyAutoNote(shown: Bool) -> String {
        shown
            ? L("いまは自動で付いています（名前の横にほかの印が無いため）。決めておくこともできます。",
                "Shown for now: nothing else is next to your name. Choose to keep it or remove it.")
            : L("いまは自動で外れています（名前の横にほかの印があるため）。「付ける」で並べて出せます。",
                "Hidden for now: something else is next to your name. Choose Show to add it.")
    }

    /// 開いたときに選ばれているもの。**持っている鍵を選んでいるときだけ**（取り消された鍵は「なし」）
    static func initialSelection(_ profile: UserProfile) -> String? {
        guard let badge = profile.shownBadge, BadgeCatalog.isKnown(badge.key) else { return nil }
        return badge.key
    }

    /// 送る部分更新。**変わったものだけ**を載せ、何も変わっていなければ nil（送らずに閉じる）。
    ///
    /// - バッジ: 選んだ鍵、または「なし」（JSON の null）
    /// - Pro マークの形: Pro の人だけ。nil は外す（`"none"`）
    /// - 公式の印: 公式の人だけ（`verifiedMarkOff`）。`verifiedOn` が nil なら触らない
    /// - 初期メンバーの印: 資格のある人だけが渡す（`earlyMarkOn`）。決めた値が開いたときと違えば送る。
    ///   `earlyOn` が nil（決めていない）なら触らない
    static func patch(profile: UserProfile, selected: String?, style: ProMarkStyle?,
                      verifiedOn: Bool? = nil, earlyOn: Bool? = nil) -> ProfilePatch? {
        var patch = ProfilePatch()
        var changed = false
        // 持っていない鍵を指していた人が「なし」のまま決めたら、その古い値も消す。
        // ただし**持っているがこの版のアプリが知らない鍵**（新しい章など）は、選び直していなければ
        // 触らない（2026-10-09 バグ調査 低-1: 「決める」だけで飾りが外れていた）
        if selected != profile.chosenBadgeKey, !keepsUnknownOwnedBadge(profile: profile, selected: selected) {
            patch.displayBadge = Clearable(selected)
            changed = true
        }
        if profile.isPro, style != profile.chosenProMark {
            patch.proMarkStyle = style?.rawValue ?? ProMarkStyle.removedValue
            changed = true
        }
        if profile.verified == true, let verifiedOn, verifiedOn == profile.verifiedMarkRemoved {
            patch.verifiedMarkOff = !verifiedOn
            changed = true
        }
        if let earlyOn, earlyOn != profile.earlyMarkChoice {
            patch.earlyMarkOn = earlyOn
            changed = true
        }
        return changed ? patch : nil
    }

    /// 飾っているのが「持っているがアプリの知らない鍵」で、利用者が「なし」のまま（選び直していない）か
    static func keepsUnknownOwnedBadge(profile: UserProfile, selected: String?) -> Bool {
        guard selected == nil, let key = profile.chosenBadgeKey,
              profile.earnedBadges[key] != nil, !BadgeCatalog.isKnown(key) else { return false }
        return true
    }
}

/// 「なし／外す」の絵（点線の丸と斜線）。バッジの格子の「なし」（56pt）と、Pro マーク・公式の印の
/// 「外す」（18pt）で同じ形を使う（2026-10-10）。線と記号は大きさに比例させる（56pt で線 1.5・点線 4/3・記号 20）
struct NameSideNoneMark: View {
    let side: Double

    var body: some View {
        let k = side / 56
        Circle()
            .strokeBorder(WebTheme.outline,
                          style: StrokeStyle(lineWidth: max(1, 1.5 * k), dash: [max(1.5, 4 * k), max(1, 3 * k)]))
            .frame(width: side, height: side)
            .overlay(
                Image(systemName: "nosign")
                    .font(.system(size: max(9, 20 * k), weight: .regular))
                    .foregroundStyle(WebTheme.faint)
            )
            .accessibilityHidden(true)
    }
}
