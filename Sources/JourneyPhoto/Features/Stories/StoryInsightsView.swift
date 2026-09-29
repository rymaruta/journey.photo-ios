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

    @EnvironmentObject private var environment: AppEnvironment
    /// ブロックした人は一覧から外す（行からその人のページへ行き、ブロックできる）
    @EnvironmentObject private var hidden: ModerationStore
    /// 一覧から落とす「見せない」の写し。**戻ってきたとき（`onAppear`）に取る**
    /// ——描くたびに絞ると、見た人のページでブロックした瞬間に元の行が消え、
    /// そのページが閉じる（`UserProfileView` と同じ形）
    @State private var dropped = ModerationSnapshot()
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                tabs
                viewerList
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 題と、下に「9月24日 18:20に投稿」（板 26）
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(L("ストーリーの反応", "Story insights"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    if let posted = StoryPlayback.postedAt(story.createdAt) {
                        Text(posted)
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.faint)
                    }
                }
            }
        }
        .onAppear { dropped = hidden.snapshot }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 写真と数

    /// 左に縦長の写真（72×112）、右に3つの数を1枚の格子で（板 26）
    private var summary: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 72, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 1) {
                countCell(L("閲覧", "Views"), value: viewersLoaded ? viewers.count : nil)
                countCell(L("いいね", "Likes"), value: repliesLoaded ? replies.reactionCount : nil)
                countCell(L("返信", "Replies"), value: repliesLoaded ? replies.textReplies.count : nil)
            }
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    /// 写真ならそのまま、動画は記号（`StoryPoster`）
    private var thumbnail: some View {
        StoryPoster(story: story)
    }

    /// - Parameter value: nil は「読めていない」。**0 と書かない**
    private func countCell(_ label: String, value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.map { "\($0)" } ?? "—")
                .font(JPFont.mono(18, relativeTo: .title3))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(WebTheme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Self.cellColor)
    }

    /// 数の升の地（板の `#0b0b0c`）
    private static let cellColor = Color(red: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x0C / 255.0)

    // MARK: - 絞り

    /// 閲覧者 / リアクション。**下線のタブ**（板 26）。数は上の格子にある
    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Scope.allCases) { option in
                let selected = scope == option
                Button {
                    scope = option
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : WebTheme.faint)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selected ? Color.white : Color.clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
    }

    // MARK: - 見た人

    @ViewBuilder
    private var viewerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(WebTheme.danger)
            } else if scope == .reactions && repliesFailed && !repliesLoaded {
                // 反応だけ引けなかった回に「まだリアクションはありません」と言わない。
                // 前に読めていれば、その一覧と数を出し続ける（上の升と食い違わせない）
                Text(L("リアクションを読み込めませんでした。引き下げて読み直せます",
                       "Couldn't load reactions. Pull to retry"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.vertical, 12)
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
                UserProfileView(userId: viewer.userId)
            } label: {
                HStack(spacing: 12) {
                    RemoteImage(url: UserProfile.profileAssetURL(
                        userId: viewer.userId, suffix: nil, cacheBust: nil),
                                placeholderSymbol: "person.crop.circle.fill")
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewer.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        if let ago = ago(from: viewer.at) {
                            Text(ago)
                                .font(.system(size: 12))
                                .foregroundStyle(WebTheme.faint)
                        }
                        // いいねと返信の両方をした人は、返信の文を名前の下に
                        if hasReaction(from: viewer.userId), let reply = replyText(from: viewer.userId) {
                            Text("「\(reply)」")
                                .font(.system(size: 12))
                                .foregroundStyle(WebTheme.muted2)
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
                // いいねは白（真鍮は合図と手がかりだけ）（デザインシステム「黒塗りの真鍮」）
                Image(systemName: "heart.fill")
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityLabel(L("いいね", "Liked"))
            } else if let reply = replyText(from: viewer.userId) {
                Text("「\(reply)」")
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.muted2)
                    .lineLimit(1)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
        }
        .frame(minHeight: 62)
    }

    // MARK: - 数え方

    private func replyText(from userId: String) -> String? {
        replies.first { $0.uid == userId && ($0.emoji ?? "").isEmpty }?.text
    }

    private func hasReaction(from userId: String) -> Bool {
        replies.contains { $0.uid == userId && ($0.emoji ?? "").isEmpty == false }
    }

    /// 「2時間前」。決まりは閲覧画面と共用（`StoryPlayback.ago`）
    private func ago(from iso: String?) -> String? {
        StoryPlayback.ago(from: iso)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
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
        } catch is CancellationError {
            // 取り消された（画面を離れた・引き下げの途中で描き直された）。失敗と言わない
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
    }
}
