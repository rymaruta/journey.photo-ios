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
    /// **もう無い**（404）。消した・見えなくなった。再試行を出さない
    @State private var gone = false
    @State private var showEditor = false

    var body: some View {
        Group {
            if let contents, !contents.items.isEmpty {
                // **写真の上に題と ✕ を重ねる**（板 38）。上のバーは隠す——
                // 出したままだと写真がバーの裏から始まり、題が2か所に出る
                StoryViewerView(
                    stories: contents.items, startIndex: 0, viewerId: auth.userId,
                    // 題は**読み直した中身**から（名前を変えた後も最初の題のままだった）
                    highlight: .init(title: contents.title.isEmpty ? highlight.displayTitle : contents.title,
                                     // 表紙も読み直した中身から（編集で外した表紙が残った）
                                     coverURL: contents.coverURL(fallback: highlight.coverURL),
                                     // **並んでいる本数を出す**（サーバーの数はアーカイブから
                                     // 外れたぶんも数えていて、進行バーの区切りと割れる）
                                     count: contents.items.count,
                                     onEdit: isMine ? { showEditor = true } : nil),
                    // 編集のシートを開いている間は止める（時間切れで画面ごと戻されない）
                    holds: showEditor
                )
                // 🔴 **並びが変わったら作り直す。** 編集で減らすと、前の位置（`@State index`）が
                // 並びの外を指したまま残り、真っ黒な画面から出られなくなった（バーも隠している）
                .id(contents.items.map(\.id))
            } else if gone {
                note(icon: "sparkles",
                     title: L("このハイライトはもうありません", "This highlight no longer exists"),
                     message: L("削除されたか、見られなくなりました。",
                                "It was deleted or is no longer visible to you."))
            } else if failed {
                // **「取れなかった」と「空」を分ける。** 同じ絵にすると、
                // 圏外で開いた人が「消えた」と思う
                note(icon: "wifi.slash",
                     title: L("開けませんでした", "Couldn't open it"),
                     message: L("通信を確かめて、もう一度お試しください。",
                                "Check your connection and try again."),
                     // 「もう一度お試しください」と言うなら、試す手段を置く
                     retry: { Task { await load() } })
            } else if contents != nil {
                note(icon: "sparkles",
                     title: L("中身がありません", "Nothing inside"),
                     message: L("入れていたストーリーが、アーカイブから外れています。",
                                "The stories in it are no longer in your archive."))
            } else {
                // 読み込み中。**上のバーと題は出さない**——出してから中身が出た瞬間にバーを隠すと、
                // 画面が跳ねた。出口は中身が出たときと同じ右上の ✕（2026-10-16 判断）
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) { loadingClose }
            }
        }
        .webScreen()
        .navigationTitle(highlight.displayTitle)
        // **写真の上に題と ✕ を重ねる**（板 38）ので、中身が出ている間・読み込み中は上のバーを隠す。
        // バーを出すのは、空・失敗・もう無いの札のときだけ（`showsNavigationBar`）
        .toolbar(Self.showsNavigationBar(itemCount: contents.map { $0.items.count }, failed: failed, gone: gone)
                 ? .visible : .hidden,
                 for: .navigationBar)
        // 🔴 **再生中は下のタブバーを隠す**（板 HighlightPlayer は写真が下端まで・2026-10-16 判断）。
        // 読み込み中から隠しておく（中身が出た瞬間に下が跳ねない）
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // 中身が出ている間は写真の上の「編集」を使う。空・失敗のときだけバーに
            // もう無い輪には出さない（開いても直すものが無い）
            if isMine && !gone && (contents?.items.isEmpty ?? true) {
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

    /// 上のバーを出すか。**中身が出ている間（写真の上に題と ✕）と読み込み中は出さない**。
    /// `body` の分かれ道と同じ順で決める（中身があれば、読み直しに失敗しても閲覧画面のまま）。
    /// - Parameter itemCount: 読めた中身の本数（nil は読み込み中・もう無い）
    nonisolated static func showsNavigationBar(itemCount: Int?, failed: Bool, gone: Bool) -> Bool {
        if let itemCount, itemCount > 0 { return false }
        if gone || failed { return true }
        return itemCount != nil
    }

    /// 読み込み中の ✕（中身が出たときの閲覧画面の ✕ と同じ位置・形。押せるのは 44pt）
    private var loadingClose: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.title3)
                .foregroundStyle(.white)
                .webTappable()
                .accessibilityLabel(Labels.Common.close)
        }
        // 閲覧画面の見出しの行と同じ高さ（上 5 ＋ 進み線 2.5 ＋ 間 9）・右 4
        .padding(.trailing, 4)
        .padding(.top, 16)
    }

    /// 空と失敗を分けて出す小さな札。**共通の部品は作らない**
    /// （この画面でしか使わないものを外に出すと、次の人が探しに行く）
    private func note(icon: String, title: String, message: String,
                      retry: (() -> Void)? = nil) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(WebTheme.faint)
            Text(title).font(.headline).foregroundStyle(WebTheme.foreground)
            Text(message).font(.callout).foregroundStyle(WebTheme.muted2)
                .multilineTextAlignment(.center)
            // ボタンの形は `ErrorBanner` と同じ
            if let retry {
                Button(Labels.Common.retry, action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        failed = false
        gone = false
        do {
            contents = try await environment.highlights.contents(userId: userId, id: highlight.id)
        } catch {
            // 編集で消して戻った回もここ（404）。「通信を確かめて」と言わない
            if HighlightService.isGone(error) {
                contents = nil
                gone = true
            } else {
                failed = true
            }
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
    /// 直近の読み込みが失敗した。**「まだハイライトがありません」と分ける**
    @State private var failed = false

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
                                Text(L("\(count)件", count == 1 ? "1 story" : "\(count) stories"))
                                    .font(.caption)
                                    .foregroundStyle(WebTheme.faint)
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            if loaded && highlights.isEmpty && failed {
                ErrorBanner(message: Labels.Common.loadFailed) { Task { await load() } }
                    .listRowBackground(Color.clear)
            } else if loaded && highlights.isEmpty {
                Text(L("まだハイライトがありません。", "No highlights yet."))
                    .font(.callout)
                    .foregroundStyle(WebTheme.faint)
                    .listRowBackground(Color.clear)
            }
        }
        .webScreen()
        .navigationTitle(L("ストーリーハイライト", "Story highlights"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let list = try? await environment.highlights.list(userId: userId)
        if let list { highlights = list }
        failed = list == nil
        loaded = true
    }
}
