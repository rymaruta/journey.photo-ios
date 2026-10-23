import SwiftUI

/// ストーリーの反応（提案の絵・2026-09-21）。
///
/// **本人しか見られない。** `GET /stories/{id}/viewers` は投稿者以外に
/// 403 を返す（`api-user/src/stories.ts`）。押せる場所も本人の画面だけに置く。
///
/// **出す数は「サーバーが数えているもの」だけ。**
///
///     閲覧  … `viewers` の数              ある
///     返信  … `replies` の数              ある
///     いいね … 定型の反応をした人の数（1人1つ）  ある（返信の一種として届く）
///     シェア … **無い**                    出さない
///
/// 提案の絵には「シェア 16」があったが、サーバーは数えていない。
/// **0 と書くと「誰にも共有されていない」という嘘になる**ので、欄ごと出さない。
struct StoryInsightsView: View {

    let story: Story

    /// 閲覧画面が**もう読んだ**見た人・返信（2026-10-16）。渡されたら最初は読み直さない
    /// ——閲覧画面から開くたびに、同じ2つの一覧をもう一度読んでいた。引き下げ・人のページから
    /// 戻ったときの読み直しは今までどおり
    struct Seed: Equatable {
        let viewers: [StoryViewer]
        let replies: [StoryReply]

        /// **両方読めているときだけ**渡す（片方でも読めていなければ、反応の画面が自分で読む）
        static func from(viewers: [StoryViewer], viewersLoaded: Bool?,
                         replies: [StoryReply], repliesLoaded: Bool) -> Seed? {
            viewersLoaded == true && repliesLoaded ? Seed(viewers: viewers, replies: replies) : nil
        }
    }

    init(story: Story, seed: Seed? = nil) {
        self.story = story
        if let seed {
            _viewers = State(initialValue: seed.viewers)
            _replies = State(initialValue: seed.replies)
            _viewersLoaded = State(initialValue: true)
            _repliesLoaded = State(initialValue: true)
            _isLoading = State(initialValue: false)
        }
        _skipsFirstLoad = State(initialValue: Self.skipsFirstLoad(seed: seed))
    }

    /// 最初の読み込みを省くか（渡された一覧があるとき）
    nonisolated static func skipsFirstLoad(seed: Seed?) -> Bool { seed != nil }

    /// 最初の `.task` の読み込みを1回だけ省く印（`Seed`）
    @State private var skipsFirstLoad = false

    @EnvironmentObject private var environment: AppEnvironment
    /// ブロックした人は一覧から外す（行からその人のページへ行き、ブロックできる）
    @EnvironmentObject private var hidden: ModerationStore
    /// 一覧から落とす「見せない」の写し。**戻ってきたとき（`onAppear`）に取る**
    /// ——描くたびに絞ると、見た人のページでブロックした瞬間に元の行が消え、
    /// そのページが閉じる（`UserProfileView` と同じ形）
    @State private var dropped = ModerationSnapshot()
    /// 戻るスワイプ途中の `onAppear` で見た人の行を消さない印（`FrontConfirm`）
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?
    @State private var viewers: [StoryViewer] = []
    @State private var replies: [StoryReply] = []
    /// 返信・反応を**一度でも読めたか**。読めていない間は数を「—」にする
    /// （「0」は「まだ無い」と読まれる）
    @State private var repliesLoaded = false
    /// 直近の読み込みで返信・反応が引けなかった
    @State private var repliesFailed = false
    /// 見た人を**一度でも読めたか**。読めていない間は「閲覧」も「—」
    @State private var viewersLoaded = false
    /// 一覧の絞り（モック7）。**同じ一覧を絞るだけ**——別の口から
    /// 引き直さない（リアクションは見た人の一部で、数え方も1つ）
    @State private var scope: Scope = .viewers

    enum Scope: String, CaseIterable, Identifiable {
        case viewers, reactions
        var id: String { rawValue }
        var label: String {
            switch self {
            case .viewers: return L("閲覧者", "Viewers")
            case .reactions: return L("リアクション", "Reactions")
            }
        }
    }
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// 引き下げて読み直したのに読めなかった（短く知らせて消す。一覧は前のまま）
    @State private var refreshNotice: String?
    /// 「もう一度試す」の読み直しの最中
    @State private var isRetrying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                header
                if let refreshNotice {
                    Text(refreshNotice)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // **少しで消す**（閲覧画面の知らせと同じ 2.5 秒）
                        .task(id: refreshNotice) {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            if !Task.isCancelled { self.refreshNotice = nil }
                        }
                }
                summary
                tabs
                viewerList
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.xxs)
            .padding(.bottom, JPSpace.xl)
        }
        // v2 StoryInsights: シートの地は札の面（surface-1 #0E0E0F）。写真の上ではないので不透明の灰を使う
        .scrollContentBackground(.hidden)
        .background(WebTheme.card)
        // 2026-10-16 判断: 「閉じる」を見出しの行に置いたので、この画面の上のバーは隠す（板にバーは無い）。
        // 呼び出し側（`StoryViewerView` のシート）がバーに置いた「閉じる」もこれで出ない。
        // 見た人のページへ進んだ先は、その画面のバー（戻る）がそのまま出る
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(WebTheme.card, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            switch front.appear() {
            case .first:
                dropped = hidden.snapshot
            case .returning:
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled, front.confirm() else { return }
                    dropped = hidden.snapshot
                }
            }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
        }
        .task {
            // 閲覧画面から一覧を受け取った回は、最初の1回だけ読まない（戻ったときは読み直す）
            if skipsFirstLoad {
                skipsFirstLoad = false
                return
            }
            await load()
        }
        .refreshable { await load(pulled: true) }
    }

    // MARK: - 見出し・写真と数

    /// v2: 左に縦長の写真（48×64・角 8）、右に明朝 22 の「ストーリーの反応」と
    /// 「9月24日 18:20に投稿 · あと 22 時間」（12・text-3・等幅の数字）
    private var header: some View {
        HStack(alignment: .top, spacing: JPSpace.s) {
            StoryPoster(story: story)
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("ストーリーの反応", "Story insights"))
                    .font(JPFont.cardTitle)
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
                if let line = postedLine {
                    Text(line)
                        .font(JPFont.meta)
                        .foregroundStyle(WebTheme.text3)
                }
            }
            .padding(.top, JPSpace.xxs)
            Spacer(minLength: 0)
            // v2 StoryInsights: 「閉じる」は**見出しと同じ行の右端**（板の header の中）。
            // 上のバーは隠している（`body` の `.toolbar(.hidden, for: .navigationBar)`）
            SheetCloseButton()
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(WebTheme.text)
                .frame(minHeight: WebTheme.minTapTarget)
                .padding(.leading, JPSpace.xs)
        }
    }

    /// 「9月24日 18:20に投稿 · あと 22 時間」。期限が分からなければ投稿の時刻だけ
    private var postedLine: String? {
        let parts = [StoryPlayback.postedAt(story.createdAt),
                     StoryPlayback.remaining(until: story.expiresAt)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 写真の大きさ（板 48×64）
    static let thumbSize = (width: CGFloat(48), height: CGFloat(64))

    /// 行の右の印の読み上げ（板 v2 の `aria-label`）。**何をしたかを言う**（「いいね」だけだと押すボタンに聞こえる）
    nonisolated static var likedLabel: String { L("いいねしました", "Liked") }
    nonisolated static var repliedLabel: String { L("返信しました", "Replied") }
    /// 返信した人の印。閲覧画面の自分の足元の返信の丸と同じ記号
    static let replySymbol = "message"

    /// 3つの数を1枚の升目で（v2: 縁は白 8%・角 14・升の間も白 8% の線・数は SF 300 の 28）
    private var summary: some View {
        HStack(spacing: 0) {
            // 2026-10-07 判断: 数は**ブロックした人を落としてから**数える（下の一覧と同じ `dropped`）。
            // 落とす前の数だと、一覧に居ない人の分まで数えて合わなかった
            countCell(L("閲覧", "Views"), value: viewersLoaded ? dropped.viewers(viewers).count : nil)
            InsightsCellDivider()
            countCell(L("いいね", "Likes"), value: repliesLoaded ? dropped.replies(replies).reactionCount : nil)
            InsightsCellDivider()
            countCell(L("返信", "Replies"), value: repliesLoaded ? dropped.replies(replies).textReplies.count : nil)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }

    /// - Parameter value: nil は「読めていない」。**0 と書かない**
    private func countCell(_ label: String, value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { "\($0)" } ?? "—")
                .font(JPFont.figureLarge)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(WebTheme.text)
            Text(label)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, JPSpace.m)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 絞り

    /// 閲覧者 / リアクション。**下線のタブ**（v2: 左寄せで間 22・15pt・選んだら真鍮の字と 2 の下線＝
    /// CLAUDE.md の「選んでいるタブは真鍮」）。数は上の格子にある
    private var tabs: some View {
        HStack(spacing: 22) {
            ForEach(Scope.allCases) { option in
                let selected = scope == option
                Button {
                    scope = option
                } label: {
                    Text(option.label)
                        .font(JPFont.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(Self.tabColor(selected: selected))
                        .frame(minHeight: WebTheme.minTapTarget)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selected ? WebTheme.accent : Color.clear).frame(height: JPStroke.emphasis)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    /// タブの字の色（選んだら真鍮・選んでいなければ text-3）
    @MainActor static func tabColor(selected: Bool) -> Color {
        selected ? WebTheme.accent : WebTheme.text3
    }
    // MARK: - 見た人

    @ViewBuilder
    private var viewerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(WebTheme.danger)
                retryButton
            } else if scope == .reactions && repliesFailed && !repliesLoaded {
                // 反応だけ引けなかった回に「まだリアクションはありません」と言わない。
                // 前に読めていれば、その一覧と数を出し続ける（上の升と食い違わせない）
                Text(L("リアクションを読み込めませんでした。引き下げて読み直せます",
                       "Couldn't load reactions. Pull to retry"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.top, 12)
                retryButton
            } else if shownViewers.isEmpty {
                // **「まだ0人」と「読めなかった」を混ぜない**
                Text(scope == .reactions
                     ? L("まだリアクションはありません", "No reactions yet")
                     : L("まだ誰も見ていません", "No one has seen it yet"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.vertical, 12)
            } else {
                ForEach(shownViewers) { viewer in
                    viewerRow(viewer)
                }
            }
        }
    }

    /// 絞ったあとの一覧。**リアクションは見た人の一部**（別の口では引かない）
    private var shownViewers: [StoryViewer] {
        let visible = dropped.viewers(viewers)
        return scope == .reactions ? visible.filter { hasReaction(from: $0.userId) } : visible
    }

    /// 顔・名前・時刻。右に、反応なら真鍮のハート、文章の返信なら「…」。
    /// **押すとその人のページ**
    private func viewerRow(_ viewer: StoryViewer) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                // 閲覧画面の中から開いたページ。顔の輪を出さない（閲覧画面を二重に重ねない・`StoryAvatar`）
                UserProfileView(userId: viewer.userId)
                    .environment(\.insideStoryViewer, true)
            } label: {
                HStack(spacing: JPSpace.s) {
                    RemoteImage(url: UserProfile.profileAssetURL(
                        userId: viewer.userId, suffix: nil, cacheBust: nil),
                                placeholderSymbol: "person.crop.circle.fill")
                        .frame(width: Self.avatarSize, height: Self.avatarSize)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewer.name)
                            .font(JPFont.bodyEmphasis)
                            .foregroundStyle(WebTheme.text)
                        // v2: 時刻と返信の一言を1行に（「3時間前 · 「どこですか？」」）
                        if let line = subline(for: viewer) {
                            Text(line)
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.text3)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewer.deleted == true)
            if hasReaction(from: viewer.userId) {
                // 真鍮（owner「デザインの箇所は白より真鍮色が好き」（2026-09-29）。黒地の行の上）
                Image(systemName: "heart.fill")
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityLabel(Self.likedLabel)
            } else if replyText(from: viewer.userId) != nil {
                // 返信した人は吹き出しの印（一言は名前の下に出している）。**閲覧画面の足元の返信の丸と
                // 同じ丸い吹き出し**（`message`）——角の吹き出し（`bubble.left`）は owner が安っぽいと言った形
                Image(systemName: Self.replySymbol)
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityLabel(Self.repliedLabel)
            }
        }
        .frame(minHeight: Self.rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    /// 行の2行目（時刻・返信の一言）
    private func subline(for viewer: StoryViewer) -> String? {
        let reply = replyText(from: viewer.userId).map { "「\($0)」" }
        let parts = [ago(from: viewer.at), reply].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 行（板 60）と顔（板 40）
    static let rowHeight: CGFloat = 60
    static let avatarSize: CGFloat = 40

    // MARK: - 数え方

    private func replyText(from userId: String) -> String? {
        replies.first { $0.uid == userId && ($0.emoji ?? "").isEmpty }?.text
    }

    /// 読めなかった回の「もう一度試す」。**引き下げと同じ読み直し**（失敗したら短く知らせる）。
    /// 引き下げを知らない人にも出口を（2026-10-02 の調査）
    private var retryButton: some View {
        RetryButton(isBusy: isRetrying) {
            // 読み直している間は重ねない（続けて押すと古い回が新しい回を上書きする）
            guard !isRetrying else { return }
            isRetrying = true
            Task {
                await load(pulled: true)
                isRetrying = false
            }
        }
        .padding(.vertical, 8)
    }

    private func hasReaction(from userId: String) -> Bool {
        replies.contains { $0.uid == userId && ($0.emoji ?? "").isEmpty == false }
    }

    /// 「2時間前」。決まりは閲覧画面と共用（`StoryPlayback.ago`）
    private func ago(from iso: String?) -> String? {
        StoryPlayback.ago(from: iso)
    }

    /// - Parameter pulled: 引き下げて読み直した。**そのときだけ**失敗を短く知らせる
    ///   （人のページから戻ったときの裏での読み直しは黙る）
    private func load(pulled: Bool = false) async {
        // **一度読めたら、裏で読み直す。** 人のページから戻るたびに `.task` がまた走る。
        // そのたびに読み込み中に切り替えると、一覧が消えてスクロールの位置が失われた。
        // 読み直しに失敗しても、前に読めた一覧を出し続ける（失敗の知らせで置き換えない）
        let firstLoad = !viewersLoaded
        if firstLoad {
            isLoading = true
            errorMessage = nil
        }
        defer { isLoading = false }
        do {
            viewers = try await environment.stories.viewers(id: story.id)
            viewersLoaded = true
            // **返信が読めなくても、見た人は出す。** 片方の失敗で
            // 画面ごと空にしない。**読めなかった回に 0 件で上書きしない**
            // （引き下げで読み直して失敗すると、前に読めた数まで消えていた）
            let fetched = try? await environment.stories.replies(id: story.id)
            if let fetched {
                replies = fetched
                repliesLoaded = true
            } else if Task.isCancelled {
                // 取り消された回は「読めなかった」と言わない（前の知らせのまま）
                return
            }
            repliesFailed = fetched == nil
        } catch {
            switch Self.failureOutcome(error, firstLoad: firstLoad, pulled: pulled) {
            case .silent:
                break
            case .errorMessage:
                errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
            case .refreshNotice:
                refreshNotice = L("読み直せませんでした", "Couldn't refresh")
            }
        }
    }

    enum FailureOutcome: Equatable {
        /// 何も言わない（取り消し・裏での読み直し）
        case silent
        /// 一覧の代わりに失敗の文（まだ一度も読めていない）
        case errorMessage
        /// 一覧はそのまま、短い知らせ（引き下げて読み直したとき）
        case refreshNotice
    }

    /// 読めなかったときに何を出すか。
    /// - **取り消しは失敗と言わない**（`CancellationError`・`URLError.cancelled`）。画面を離れた・
    ///   引き下げの途中で描き直された回に「読み直せませんでした」が出ていた
    /// - 一度読めたあとは、引き下げたときだけ知らせる（人のページから戻ったときの裏での読み直しは黙る）
    nonisolated static func failureOutcome(_ error: Error, firstLoad: Bool, pulled: Bool) -> FailureOutcome {
        if error is CancellationError { return .silent }
        if let url = error as? URLError, url.code == .cancelled { return .silent }
        if firstLoad { return .errorMessage }
        return pulled ? .refreshNotice : .silent
    }
}

/// 升目の間の縦の髪線（白 8%・v2 StoryInsights の `border-right`）
private struct InsightsCellDivider: View {
    var body: some View {
        Rectangle().fill(WebTheme.hairline).frame(width: JPStroke.hairline)
    }
}
