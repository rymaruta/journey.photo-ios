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
            VStack(alignment: .leading, spacing: 20) {
                header
                counts
                viewerList
            }
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationTitle(L("ストーリーの反応", "Story insights"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 見出し

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .aspectRatio(16.0 / 11.0, contentMode: .fit)
                // **`RemoteImage` で直接描かない。** 動画のストーリーは
                // 真っ黒になる（`Tools/check-swift-refs.js` がこれを見張って
                // いて、実際にここで捕まえてもらった）
                .overlay { StoryThumb(story: story) }
                .clipped()
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.8)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                if let caption = story.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(2)
                }
                if let place = story.location, !place.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill")
                        Text(place)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.85))
                }
                if let posted = postedAgo {
                    Text(posted)
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    // MARK: - 数

    private var counts: some View {
        HStack(spacing: 10) {
            countBox(L("閲覧", "Views"), systemImage: "eye", value: viewers.count)
            countBox(L("いいね", "Likes"), systemImage: "heart.fill", value: reactionCount)
            countBox(L("返信", "Replies"), systemImage: "bubble.right", value: textReplyCount)
        }
        .padding(.horizontal, 16)
    }

    private func countBox(_ label: String, systemImage: String, value: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(WebTheme.foreground)
            Text(label)
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
            Text("\(value)")
                .font(.title2.weight(.bold))
                .foregroundStyle(WebTheme.foreground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 見た人

    @ViewBuilder
    private var viewerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 閲覧者 / リアクション（モック7）。数はどちらも**数えたもの**
            Picker("", selection: $scope) {
                ForEach(Scope.allCases) { option in
                    Text("\(option.label) \(count(for: option))").tag(option)
                }
            }
            .pickerStyle(.segmented)

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
            } else {
                ForEach(shownViewers) { viewer in
                    viewerRow(viewer)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// 絞ったあとの一覧。**リアクションは見た人の一部**（別の口では引かない）
    private var shownViewers: [StoryViewer] {
        scope == .reactions ? viewers.filter { hasReaction(from: $0.userId) } : viewers
    }

    private func count(for scope: Scope) -> Int {
        scope == .reactions ? viewers.filter { hasReaction(from: $0.userId) }.count : viewers.count
    }

    private func viewerRow(_ viewer: StoryViewer) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: UserProfile.profileAssetURL(
                userId: viewer.userId, suffix: nil, cacheBust: nil),
                        placeholderSymbol: "person.crop.circle.fill")
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(viewer.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                if let ago = ago(from: viewer.at) {
                    Text(ago)
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
                // その人からの返信があれば、そのまま続けて出す
                if let reply = replyText(from: viewer.userId) {
                    Text(reply)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            Spacer()
            if hasReaction(from: viewer.userId) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(WebTheme.foreground)
            }
        }
        .frame(minHeight: WebTheme.minTapTarget)
    }

    // MARK: - 数え方

    /// 定型の反応（❤️😍😂😮😢👏）。**返信の一種として届く**
    private var reactionCount: Int {
        replies.filter { $0.emoji?.isEmpty == false }.count
    }

    /// 文章の返信だけ（反応は上で数えている）
    private var textReplyCount: Int {
        replies.filter { ($0.emoji ?? "").isEmpty }.count
    }

    private func replyText(from userId: String) -> String? {
        replies.first { $0.uid == userId && ($0.emoji ?? "").isEmpty }?.text
    }

    private func hasReaction(from userId: String) -> Bool {
        replies.contains { $0.uid == userId && ($0.emoji ?? "").isEmpty == false }
    }

    private var postedAgo: String? {
        ago(from: story.createdAt).map { L("\($0)に投稿", "Posted \($0)") }
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
