import SwiftUI

/// ギャラリーの上に出す、ストーリーの横並び。
struct StoriesRow: View {

    /// **外から「読み直せ」と言うための数**（`TabRouter.postSheetsClosed`）。
    ///
    /// この行は自分の投稿口（`+`）からの帰りは自分で読み直すが、
    /// **下の札の「投稿」から出したストーリー**は `RootView` のシートなので
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
                    HStack(alignment: .top, spacing: 12) {
                        // **1人＝1つの輪。自分は先頭、未読 → 既読の順**（板 27）
                        let ordered = StoryPlayback.orderedRings(
                            StoryPlayback.rings(model.stories, isSeen: { seen.contains($0) }),
                            me: auth.userId,
                            isUnseen: { seen.hasUnseen(model.siblings(of: $0)) })
                        mineRing(ordered.mine)
                        ForEach(ordered.others) { story in
                            // **見たものは輪を落とす。** 全部同じ輪だと
                            // 「どれがまだか」が分からず、行が意味を失う
                            let unseen = seen.hasUnseen(model.siblings(of: story))
                            Button {
                                opened = story
                            } label: {
                                ringItem(story: story,
                                         count: model.siblings(of: story).count,
                                         color: unseen ? WebTheme.accent : Color.white.opacity(0.18),
                                         name: story.authorName, emphasized: unseen)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
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
        // 🔴 **閉じたら読み直す。** 閲覧画面で自分のストーリーを消しても、
        // 閉じるだけで一覧を読み直さず、消した輪が並んだままだった
        .fullScreenCover(item: $opened, onDismiss: {
            Task { await reload() }
        }) { story in
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

    // MARK: - 輪

    /// 自分の輪。**ストーリーがあれば真鍮の区切り輪と「＋」の札、無ければ破線の丸**。
    /// どちらも名前は「あなた」（板 27）
    @ViewBuilder
    private func mineRing(_ mine: Story?) -> some View {
        if let mine {
            ZStack(alignment: .topTrailing) {
                Button {
                    opened = mine
                } label: {
                    ringItem(story: mine, count: model.siblings(of: mine).count,
                             color: WebTheme.accent, name: L("あなた", "You"), emphasized: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("あなたのストーリー", "Your story"))
                // 右下の「＋」: もう1本足す
                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WebTheme.accentText)
                        .frame(width: 22, height: 22)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                        // **押せる範囲は丸で小さく。** 44の四角にすると自分の写真の
                        // 右下4分の1を奪い、ストーリーを開くつもりで投稿画面が開いた
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("ストーリーを投稿", "Post a story"))
                // 白丸の中心を輪の右下の線の上へ（板 27 の位置）
                .offset(x: 5, y: 37)
            }
        } else {
            // **自分の入口を先頭に置く。** ストーリーが1本も無いときに
            // 行ごと消すと、投稿する場所が無くなる
            Button {
                showComposer = true
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        Image(systemName: "plus")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 62, height: 62)
                    ringName(L("あなた", "You"), emphasized: false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("ストーリーを投稿", "Post a story"))
        }
    }

    /// 輪1つ（外径62・線2・写真52・下に名前10pt。板 27 の寸法）
    private func ringItem(story: Story, count: Int, color: Color,
                          name: String, emphasized: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                // **本数で区切る**（1本は切れ目なし）。上から時計回り
                ForEach(Array(StoryPlayback.ringSegments(count: count).enumerated()), id: \.offset) { _, seg in
                    Circle()
                        .trim(from: seg.start, to: seg.end)
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                }
                StoryThumb(story: story, size: 52)
            }
            .frame(width: 62, height: 62)
            ringName(name, emphasized: emphasized)
        }
        .frame(width: 64)
    }

    /// 名前。**未読は太く白く、既読は細く薄く**（板 27）
    private func ringName(_ name: String, emphasized: Bool) -> some View {
        Text(name)
            .font(.system(size: 10, weight: emphasized ? .semibold : .regular))
            .foregroundStyle(emphasized ? WebTheme.text : WebTheme.faint)
            .lineLimit(1)
            .frame(maxWidth: 64)
    }

    private func reload() async {
        await model.load(environment: environment,
                         blockedUserIds: hidden.blockedUserIds,
                         reportedPhotoIds: hidden.reportedPhotoIds)
    }

    /// 押した輪と同じ投稿者の兄弟をまとめて渡す。輪は1人＝1つで、
    /// 開くのは輪に出していた1本から
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
