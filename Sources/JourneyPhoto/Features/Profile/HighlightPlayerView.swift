import SwiftUI

/// 輪を1つ開く。中身はストーリーそのものなので、**同じ見せ方**に通す
/// （`StoryViewerView`）。専用の再生器は作らない。
struct HighlightPlayerView: View {

    let userId: String
    let highlight: Highlight
    let isMine: Bool

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var contents: HighlightContents?
    @State private var failed = false
    @State private var showEditor = false

    var body: some View {
        Group {
            if let contents, !contents.items.isEmpty {
                StoryViewerView(stories: contents.items, startIndex: 0, viewerId: auth.userId)
            } else if failed {
                // **「取れなかった」と「空」を分ける。** 同じ絵にすると、
                // 圏外で開いた人が「消えた」と思う
                note(icon: "wifi.slash",
                     title: L("開けませんでした", "Couldn't open it"),
                     message: L("通信を確かめて、もう一度お試しください。",
                                "Check your connection and try again."))
            } else if contents != nil {
                note(icon: "sparkles",
                     title: L("中身がありません", "Nothing inside"),
                     message: L("入れていたストーリーが、アーカイブから外れています。",
                                "The stories in it are no longer in your archive."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .webScreen()
        .navigationTitle(highlight.displayTitle)
        .toolbar {
            if isMine {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("編集", "Edit")) { showEditor = true }
                }
            }
        }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await load() } }) {
            HighlightEditorView(existing: highlight)
        }
        .task { await load() }
    }

    /// 空と失敗を分けて出す小さな札。**共通の部品は作らない**
    /// （この画面でしか使わないものを外に出すと、次の人が探しに行く）
    private func note(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(WebTheme.faint)
            Text(title).font(.headline).foregroundStyle(WebTheme.foreground)
            Text(message).font(.callout).foregroundStyle(WebTheme.muted2)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        failed = false
        do {
            contents = try await environment.highlights.contents(userId: userId, id: highlight.id)
        } catch {
            failed = true
        }
    }
}

/// すべての輪（モック2-5 の「すべて見る」）。
struct HighlightsListView: View {

    let userId: String
    let isMine: Bool

    @EnvironmentObject private var environment: AppEnvironment

    @State private var highlights: [Highlight] = []
    @State private var loaded = false

    var body: some View {
        List {
            ForEach(highlights) { highlight in
                NavigationLink {
                    HighlightPlayerView(userId: userId, highlight: highlight, isMine: isMine)
                } label: {
                    HStack(spacing: 12) {
                        Group {
                            if let url = highlight.coverURL { RemoteImage(url: url) }
                            else { Circle().fill(WebTheme.surface) }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(highlight.displayTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WebTheme.foreground)
                            // **数えた値だけ出す**（サーバーが並びの長さを返す）
                            if let count = highlight.count {
                                Text(L("\(count)件", "\(count) stories"))
                                    .font(.caption)
                                    .foregroundStyle(WebTheme.faint)
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            if loaded && highlights.isEmpty {
                Text(L("まだハイライトがありません。", "No highlights yet."))
                    .font(.callout)
                    .foregroundStyle(WebTheme.faint)
                    .listRowBackground(Color.clear)
            }
        }
        .webScreen()
        .navigationTitle(L("ストーリーハイライト", "Story highlights"))
        .task { await load() }
    }

    private func load() async {
        let list = try? await environment.highlights.list(userId: userId)
        if let list { highlights = list }
        loaded = true
    }
}
