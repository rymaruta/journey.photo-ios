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
    /// 開いたときの兄弟の並び。**開いた瞬間に写して、閉じるまで変えない**
    /// ——開く前に始まった読み直しが開いたあとに返ってきても、閲覧画面の並びは動かない
    @State private var openedGroup: (stories: [Story], index: Int) = ([], 0)
    @State private var showComposer = false
    /// 裏で送っているストーリー（板 27「投稿した直後」）
    @ObservedObject private var uploads = StoryUploadCenter.shared
    @State private var showUploadFailure = false

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
                        // **送っている間・失敗した残りがある間は、自分の輪がそれを示す**（板 27）
                        if uploads.isBusy {
                            uploadRing(ordered.mine)
                        } else {
                            mineRing(ordered.mine)
                        }
                        ForEach(ordered.others) { story in
                            // **見たものは輪を落とす。** 全部同じ輪だと
                            // 「どれがまだか」が分からず、行が意味を失う
                            let unseen = seen.hasUnseen(model.siblings(of: story))
                            Button {
                                open(story)
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
        // 🔴 **閲覧画面を開いている間は読み直さない**（下の `hidden.revision` と同じ理由）。
        // 裏で送っていたストーリーが送り終わる・投稿シートが閉じる、で読み直すと、
        // 閲覧画面に渡す並びが開いたまま作り直され、見ている1本の位置がずれる。
        // 閉じたときに `onDismiss` が読み直すので、ここで止めても取りこぼさない
        .task(id: "\(auth.userId ?? "-")#\(reloadToken)") {
            guard auth.userId != nil, opened == nil else { return }
            await reload()
        }
        // 裏の送信が全部終わったら読み直す（自分の新しいストーリーを並べる）
        .onChange(of: uploads.finished) { _, _ in
            guard opened == nil else { return }
            Task { await reload() }
        }
        // 途中で止まったとき。**出たぶんは残し、残りを送り直すかやめるかを選ばせる**
        .confirmationDialog(L("ストーリーを送れませんでした", "Couldn't send your story"),
                            isPresented: $showUploadFailure, titleVisibility: .visible) {
            Button(L("もう一度送る", "Try again")) { uploads.retry() }
            Button(L("やめる", "Discard"), role: .destructive) {
                uploads.discard()
                // 出せたぶんがあれば並べる
                Task { await reload() }
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            if case .failed(let message, _) = uploads.phase {
                Text(message)
            }
        }
        // 閲覧画面で通報・ブロックしたら読み直す（`GalleryView` と同じ形）。
        // 読み直さないと、消したはずの輪が並んだまま
        //
        // 🔴 **閲覧画面を開いている間は読み直さない**（閉じたときに読み直す）。
        // 開いている間に一覧が変わると、閲覧画面に渡す並びが作り直され、
        // 通報した1本が消えて「残り0本」で閉じたり、真っ黒な画面に閉じ込められたりした
        .onChange(of: hidden.revision) { _, _ in
            guard opened == nil else { return }
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
                    open(mine)
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

    /// **送っている間の自分の輪**（板 27「投稿した直後——上がるまで自分の輪が進み具合を示す」）。
    /// 進み具合は「出し終えた本数 ÷ 全部」。0本目でも少しだけ点ける（止まって見えない）。
    /// 失敗したら輪を赤くし、名前を「送れませんでした」に。押すと送り直すかやめるかを選ぶ
    @ViewBuilder
    private func uploadRing(_ mine: Story?) -> some View {
        let failed: Bool = { if case .failed = uploads.phase { return true }; return false }()
        let progress: Double = {
            if case .sending(let done, let total) = uploads.phase, total > 0 {
                return max(0.08, Double(done) / Double(total))
            }
            return 1
        }()
        Button {
            if failed { showUploadFailure = true }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 2)
                        .padding(1)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(failed ? WebTheme.danger : WebTheme.accent,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                    if let mine {
                        StoryThumb(story: mine, size: 52)
                            .opacity(0.6)
                    } else {
                        Circle().fill(WebTheme.surface).frame(width: 52, height: 52)
                    }
                    if failed {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 62, height: 62)
                ringName(failed ? L("送れませんでした", "Failed") : L("送信中…", "Sending…"),
                         emphasized: true)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
        .disabled(!failed)
        .accessibilityLabel(uploadAccessibilityLabel)
        .accessibilityIdentifier("stories.uploading")
    }

    private var uploadAccessibilityLabel: String {
        switch uploads.phase {
        case .sending(let done, let total):
            return L("ストーリーを送信中（\(total)本中\(done)本）", "Sending your story (\(done) of \(total))")
        case .failed:
            return L("ストーリーを送れませんでした。押すと送り直すかやめるかを選べます",
                     "Couldn't send your story. Tap to retry or discard.")
        case .idle:
            return L("あなた", "You")
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
        await model.load(environment: environment, viewerId: auth.userId,
                         blockedUserIds: hidden.blockedUserIds,
                         reportedPhotoIds: hidden.reportedPhotoIds)
    }

    /// 押した輪と同じ投稿者の兄弟をまとめて写してから開く。輪は1人＝1つで、
    /// 開くのは輪に出していた1本から
    private func open(_ story: Story) {
        let group = StoryPlayback.siblings(of: story, in: model.stories)
        openedGroup = (group.stories, group.index)
        opened = story
    }

    /// 閲覧画面。**開いたときに写した並びを渡す**（`model.stories` から毎回作り直すと、
    /// 開いている間の読み直しで並びが変わり、見ている1本の位置がずれる）
    private func viewer(for story: Story) -> some View {
        var stories = openedGroup.stories
        var index = openedGroup.index
        // 写しが無い・別の1本の写し（念のため）なら、いまの一覧から作る
        if !stories.contains(where: { $0.id == story.id }) {
            let group = StoryPlayback.siblings(of: story, in: model.stories)
            stories = group.stories
            index = group.index
        }
        return StoryViewerView(stories: stories, startIndex: index,
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

    /// いまの一覧を読んだ人（切り替えたら前の人の一覧を残さない）
    private var loadedFor: String?

    func load(environment: AppEnvironment, viewerId: String?, blockedUserIds: Set<String> = [],
              reportedPhotoIds: Set<String> = []) async {
        // 取れなくても画面は壊さない（ストーリーは添え物）
        // ⚠️ `if let x = try? await …` は構文検査（tree-sitter）が読めない。2文に割る
        let fetched = try? await environment.stories.list()
        stories = StoryPlayback.afterLoad(fetched: fetched, previous: stories,
                                          sameViewer: loadedFor == viewerId,
                                          blockedUserIds: blockedUserIds,
                                          reportedPhotoIds: reportedPhotoIds)
        if fetched != nil { loadedFor = viewerId }
    }
}
