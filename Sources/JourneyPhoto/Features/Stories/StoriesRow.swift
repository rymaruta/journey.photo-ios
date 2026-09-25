import SwiftUI

/// ギャラリーの上に出す、ストーリーの横並び。
struct StoriesRow: View {

    /// **外から「読み直せ」と言うための数**。
    ///
    /// この行は自分の投稿口（`+`）からの帰りは自分で読み直すが、
    /// **`MyPageView` の「投稿」ボタンから出したストーリー**は別のシートなので
    /// 気づけず、投稿したのに自分のストーリーが並ばなかった。
    /// 真偽値にしないのは `NotificationRouter` と同じ理由（2回目が効かない）。
    var reloadToken: Int = 0

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    /// 見たかどうか（リングの色）。**サーバーに口が無いので端末に覚える**
    @EnvironmentObject private var seen: SeenStoriesStore
    @StateObject private var model = StoriesViewModel()
    @State private var opened: Story?
    @State private var showComposer = false

    var body: some View {
        Group {
            if auth.userId != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // **自分の入口を先頭に置く。** ストーリーが1本も
                        // 無いときに行ごと消すと、投稿する場所が無くなる
                        Button {
                            showComposer = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.title3)
                                    .accessibilityLabel(L("ストーリーを投稿", "Post a story"))
                                    .frame(width: 64, height: 64)
                                    .background(WebTheme.surface, in: Circle())
                                Text(L("ストーリー", "Story"))
                                    .font(.caption)
                                    .frame(width: 68)
                            }
                        }
                        .buttonStyle(.plain)

                        ForEach(model.stories) { story in
                            Button {
                                opened = story
                            } label: {
                                VStack(spacing: 4) {
                                    // **見たものは輪を落とす。** 全部同じ輪だと
                                    // 「どれがまだか」が分からず、行が意味を失う
                                    let unseen = seen.hasUnseen(model.siblings(of: story))
                                    StoryThumb(story: story)
                                        .overlay(Circle().strokeBorder(
                                            unseen ? AnyShapeStyle(WebTheme.accent)
                                                   : AnyShapeStyle(WebTheme.outline),
                                            lineWidth: 2))
                                    Text(story.authorName)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(width: 68)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .task(id: "\(auth.userId ?? "-")#\(reloadToken)") {
            guard auth.userId != nil else { return }
            await reload()
        }
        // 閲覧画面で通報・ブロックしたら読み直す（`GalleryView` と同じ形）。
        // 読み直さないと、消したはずの輪が並んだまま
        .onChange(of: hidden.revision) { _, _ in
            Task { await reload() }
        }
        .fullScreenCover(item: $opened) { story in
            viewer(for: story)
        }
        .onChange(of: opened?.id) { _, id in
            // **開いた1本を見たことにする。** 閲覧画面の中で次へ送ったぶんは
            // あちらが知らせる（この行は開いた1本しか知らない）
            if let id { seen.markSeen(id) }
        }
        .sheet(isPresented: $showComposer, onDismiss: {
            Task { await reload() }
        }) {
            NavigationStack { StoryComposerView() }
        }
    }

    private func reload() async {
        await model.load(environment: environment,
                         blockedUserIds: hidden.blockedUserIds,
                         reportedPhotoIds: hidden.reportedPhotoIds)
    }

    /// 押した1本と同じ投稿者の兄弟をまとめて渡す。輪は1本＝1つのままで、
    /// 閲覧画面の中だけ続けて見られる
    private func viewer(for story: Story) -> some View {
        let group = StoryPlayback.siblings(of: story, in: model.stories)
        return StoryViewerView(stories: group.stories, startIndex: group.index,
                               viewerId: auth.userId, onSeen: { seen.markSeen($0) })
    }
}

@MainActor
final class StoriesViewModel: ObservableObject {

    @Published private(set) var stories: [Story] = []

    /// その1本と**同じ投稿者の束**（輪の色は束ごとに決める——1本でも
    /// 未読なら点ける）
    func siblings(of story: Story) -> [Story] {
        StoryPlayback.siblings(of: story, in: stories).stories
    }

    func load(environment: AppEnvironment, blockedUserIds: Set<String> = [],
              reportedPhotoIds: Set<String> = []) async {
        // 取れなくても画面は壊さない（ストーリーは添え物）
        let fetched = (try? await environment.stories.list()) ?? []
        // 通報した1本はサーバーが落とさないので端末で消す
        stories = StoryPlayback.visible(fetched, blockedUserIds: blockedUserIds,
                                        reportedPhotoIds: reportedPhotoIds)
    }
}
