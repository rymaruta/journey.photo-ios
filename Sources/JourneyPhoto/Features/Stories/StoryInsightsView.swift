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
///     いいね … 定型の反応（❤️）の数        ある（返信の一種として届く）
///     シェア … **無い**                    出さない
///
/// 提案の絵には「シェア 16」があったが、サーバーは数えていない。
/// **0 と書くと「誰にも共有されていない」という嘘になる**ので、欄ごと出さない。
struct StoryInsightsView: View {

    let story: Story

    @EnvironmentObject private var environment: AppEnvironment
    @State private var viewers: [StoryViewer] = []
    @State private var replies: [StoryReply] = []
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
                countCell(L("閲覧", "Views"), value: viewers.count)
                countCell(L("いいね", "Likes"), value: replies.reactionCount)
                countCell(L("返信", "Replies"), value: replies.textReplies.count)
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

    private func countCell(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
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
        scope == .reactions ? viewers.filter { hasReaction(from: $0.userId) } : viewers
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
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewer.deleted == true)
            if hasReaction(from: viewer.userId) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(WebTheme.accent)
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
            // **返信が読めなくても、見た人は出す。** 片方の失敗で
            // 画面ごと空にしない
            replies = (try? await environment.stories.replies(id: story.id)) ?? []
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
    }
}
