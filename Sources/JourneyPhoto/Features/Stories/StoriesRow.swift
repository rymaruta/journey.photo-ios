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
                                    .background(Color(.secondarySystemBackground), in: Circle())
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
                                    StoryThumb(story: story)
                                        .overlay(Circle().strokeBorder(.tint, lineWidth: 2))
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
            await model.load(environment: environment)
        }
        .fullScreenCover(item: $opened) { story in
            StoryViewerView(story: story, isMine: story.userId == auth.userId)
        }
        .sheet(isPresented: $showComposer, onDismiss: {
            Task { await model.load(environment: environment) }
        }) {
            NavigationStack { StoryComposerView() }
        }
    }
}

@MainActor
final class StoriesViewModel: ObservableObject {

    @Published private(set) var stories: [Story] = []

    func load(environment: AppEnvironment) async {
        // 取れなくても画面は壊さない（ストーリーは添え物）
        stories = (try? await environment.stories.list()) ?? []
    }
}
