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
    /// 開いたときに写した**人ごとの束の並び**と、押した人の位置（`StoryReel`）
    @State private var openedReel: (groups: [StoryReel.Group], start: Int) = ([], 0)
    @State private var showComposer = false
    /// 裏で送っているストーリー（板 27「投稿した直後」）
    @ObservedObject private var uploads = StoryUploadCenter.shared
    @State private var showUploadFailure = false

    var body: some View {
        // 🔴 **入れ物は中身が空にならない形にする**（2026-10-16 判断）。前は `Group` の中を `if` だけにして
        // いたので、読み込み中（輪の列を出さない間）は中身が無く、`Group` に付けた `.task` が一度も走らな
        // かった。読み込まない → `settled` が立たない → 輪の列がいつまでも出ない（1.1.5 でホームの
        // ストーリーが消えた）。出さない間も高さ 0 の見えない1枚を置き、`.task` を必ず走らせる
        VStack(spacing: 0) {
            // **読み込み中は輪の列を出さない**（板 Main の `showRings: !loading`）。ただし既に持っている
            // 輪・送っている輪があれば出したまま（読み直しのたびに列を消すとちらつく・`showsRings`）
            if auth.userId != nil,
               Self.showsRings(settled: model.settled, hasRings: !model.stories.isEmpty, uploading: uploads.isBusy) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: StoryRingMetrics.spacing) {
                        // **1人＝1つの輪。自分は先頭、未読 → 既読の順**（板 27・v2 StoryRings）
                        let ordered = StoryPlayback.orderedRings(
                            StoryPlayback.rings(model.stories, isSeen: { seen.contains($0) }),
                            me: auth.userId,
                            isUnseen: { seen.hasUnseen(model.siblings(of: $0)) })
                        // **送っている間・失敗した残りがある間は、自分の輪がそれを示す**（板 27）
                        if uploads.isBusy {
                            uploadRing(ordered.mine)
                        } else if ordered.mine == nil && ordered.others.isEmpty && model.loaded {
                            // **フォロー中の輪が無いとき**（v2 StoryRings の4つ目）。丸1つだけ置くと
                            // 何の列か分からないので、入口の行と「探す」への道を出す
                            emptyRow
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
                                         unseen: unseen,
                                         name: story.authorName)
                            }
                            .buttonStyle(.plain)
                            // 「haru_t のストーリー 3本（まだ見ていない）」（板 v2 StoryRings の `aria-label`）。
                            // 輪の色と切れ目で見せていることを、読み上げでも言う
                            .accessibilityLabel(Self.ringLabel(name: story.authorName,
                                                               count: model.siblings(of: story).count,
                                                               unseen: unseen))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }
            } else {
                Self.loadingAnchor
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

    /// 自分の輪。**ストーリーがあれば真鍮の輪だけ、無ければ自分の顔に白 22% の輪と「＋」**。
    /// どちらも名前は「あなた」（板 27・v2 StoryRings「いつもの並び」「自分のストーリーが無いとき」）
    ///
    /// 2026-10-16 判断: ストーリーがあるときは「＋」を出さない（板 v2 の「いつもの並び」の「あなた」は輪だけ）。
    /// 2本目は下の札の「投稿」から足せる。輪の右下に小さな「＋」を重ねていたときは、自分の輪を開く
    /// つもりで投稿画面が開くことがあった
    @ViewBuilder
    private func mineRing(_ mine: Story?) -> some View {
        if let mine {
            Button {
                open(mine)
            } label: {
                // 自分の輪は**見たかどうかに関係なく真鍮**（板の「あなた」の輪）
                ringItem(story: mine, count: model.siblings(of: mine).count,
                         unseen: true, name: L("あなた", "You"))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("あなたのストーリー", "Your story"))
        } else {
            // **自分の入口を先頭に置く。** ストーリーが1本も無いときに
            // 行ごと消すと、投稿する場所が無くなる
            // 「＋」は見た目 22 の丸だが、**押せるのは輪と名前の全体**（幅 64・44pt 以上）。
            // 「＋」だけの小さな的は置かない
            Button {
                showComposer = true
            } label: {
                VStack(spacing: StoryRingMetrics.nameSpacing) {
                    StoryRing(count: 1, unseen: false) { myFace }
                        .overlay(alignment: .bottomTrailing) {
                            plusBadge.offset(x: 2, y: 2)
                        }
                    ringName(L("あなた", "You"), color: WebTheme.text2)
                }
                .frame(width: StoryRingMetrics.size)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("ストーリーを投稿", "Post a story"))
        }
    }

    /// 自分の顔（無ければ人の印）
    private var myFace: some View {
        RemoteImage(url: auth.userId.flatMap { UserProfile.profileAssetURL(userId: $0, suffix: nil, cacheBust: nil) },
                    placeholderSymbol: "person.crop.circle.fill")
    }

    /// 「＋」の白い丸（22・墨の「＋」・黒 3 の縁。板の `.plus`）。
    /// 丸は輪に重ねる決まった大きさなので、記号も既定の大きさで止める（大きい文字でも丸からはみ出さない）
    private var plusBadge: some View {
        Image(systemName: "plus")
            .font(.caption2.weight(.bold))
            .dynamicTypeSize(...DynamicTypeSize.large)
            .foregroundStyle(WebTheme.accentText)
            .frame(width: StoryRingMetrics.plusSize, height: StoryRingMetrics.plusSize)
            .background(Color.white, in: Circle())
            .padding(StoryRingMetrics.gap)
            .background(Color.black, in: Circle())
            .accessibilityHidden(true)
    }

    /// **フォロー中の輪が無いとき**（v2 StoryRings の4つ目）。自分の顔＋「＋」・「ストーリーを追加」と
    /// 一行の説明、下に「探す」への道（真鍮の下線・黒地の上のリンク）
    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showComposer = true
            } label: {
                HStack(spacing: JPSpace.s) {
                    myFace
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .clipShape(Circle())
                        .overlay(alignment: .bottomTrailing) {
                            plusBadge
                                .scaleEffect(StoryRingMetrics.smallPlusSize / StoryRingMetrics.plusSize)
                                .offset(x: 6, y: 6)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("ストーリーを追加", "Add a story"))
                            .font(JPFont.bodyEmphasis)
                            .foregroundStyle(WebTheme.text)
                        Text(L("フォローした人がストーリーを上げると、ここに輪が並びます",
                               "When people you follow post stories, their rings show up here"))
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: JPHeight.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stories.empty.add")
            Button {
                TabRouter.shared.openSearch()
            } label: {
                Text(L("探すで写真の作者を見つける", "Find photographers in Search"))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.accent)
                    .underline()
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // 横に流れる列の中なので、幅を決める（いちばん狭い iPhone の幅 320 − 左右の端 16×2）
        .frame(width: StoryRingMetrics.emptyRowWidth, alignment: .leading)
    }

    /// **送っている間の自分の輪**（板 27「投稿した直後——上がるまで、自分の輪の真鍮が時計回りに満ちていく」）。
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
            VStack(spacing: StoryRingMetrics.nameSpacing) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(StoryRingMetrics.uploadTrackOpacity),
                                lineWidth: StoryRingMetrics.stroke)
                        .padding(StoryRingMetrics.stroke / 2)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(failed ? WebTheme.danger : WebTheme.accent,
                                style: StrokeStyle(lineWidth: StoryRingMetrics.stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(StoryRingMetrics.stroke / 2)
                    Group {
                        if let mine {
                            StoryThumb(story: mine, size: StoryRingMetrics.photo)
                        } else {
                            myFace
                                .frame(width: StoryRingMetrics.photo, height: StoryRingMetrics.photo)
                                .clipShape(Circle())
                        }
                    }
                    .opacity(StoryRingMetrics.uploadPhotoOpacity)
                    if failed {
                        Image(systemName: "exclamationmark")
                            .font(.body.weight(.bold))
                            .dynamicTypeSize(...StoryViewerView.chromeTypeLimit)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: StoryRingMetrics.size, height: StoryRingMetrics.size)
                ringName(failed ? L("送れませんでした", "Failed") : L("送信中…", "Sending…"),
                         color: failed ? WebTheme.danger : WebTheme.text2)
            }
            .frame(width: StoryRingMetrics.size)
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

    /// 輪の列を出すか。**一覧の読み込みが一度終わるまでは出さない**（板 Main の `showRings: !loading`）。
    /// 既に輪を持っている（読み直し中）・送っている輪があるなら出したまま（ちらつかせない）
    nonisolated static func showsRings(settled: Bool, hasRings: Bool, uploading: Bool) -> Bool {
        settled || hasRings || uploading
    }

    /// 輪の列を出さない間に置く、高さ 0 の見えない1枚。**これが無いと入れ物が空になり、`.task` が走らない**
    static var loadingAnchor: some View {
        Color.clear.frame(height: 0).accessibilityHidden(true)
    }

    /// 人の輪の読み上げ（板 v2 StoryRings の「haru_t のストーリー 3本（まだ見ていない）」）
    nonisolated static func ringLabel(name: String, count: Int, unseen: Bool) -> String {
        let n = max(1, count)
        return L("\(name) のストーリー \(n)本（\(unseen ? "まだ見ていない" : "見た")）",
                 "\(name)'s story, \(n == 1 ? "1 item" : "\(n) items") (\(unseen ? "not seen yet" : "seen"))")
    }

    /// 輪1つと名前（`StoryRing`・下に名前 12pt。板 27 は 10pt だが本文の最小 12 に合わせる）
    private func ringItem(story: Story, count: Int, unseen: Bool, name: String) -> some View {
        VStack(spacing: StoryRingMetrics.nameSpacing) {
            StoryRing(count: count, unseen: unseen) {
                StoryThumb(story: story, size: StoryRingMetrics.photo)
            }
            ringName(name, color: Self.nameColor(unseen: unseen))
        }
        .frame(width: StoryRingMetrics.size)
    }

    /// 名前の色。**未読は白、既読は灰（text-3・黒地の上）**（v2 StoryRings。輪の色でも見分ける）
    @MainActor static func nameColor(unseen: Bool) -> Color {
        unseen ? WebTheme.text : WebTheme.text3
    }

    private func ringName(_ name: String, color: Color) -> some View {
        Text(name)
            // 本文の最小は 12pt（CLAUDE.md。板 27 は 10 だが、決まりを優先）。
            // **眉ラベル（11）扱いにはしない**——名前は人を見分ける本文なので 12（.caption）。
            // 輪の幅（64）は決まっているので、大きい文字は xxLarge で止める（1行で切れる）
            .font(JPFont.caption)
            .dynamicTypeSize(...StoryViewerView.chromeTypeLimit)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: StoryRingMetrics.size)
    }

    private func reload() async {
        await model.load(environment: environment, viewerId: auth.userId,
                         blockedUserIds: hidden.blockedUserIds,
                         reportedPhotoIds: hidden.reportedPhotoIds)
    }

    /// 押した輪から開く。**輪の並び（自分 → 未読 → 既読）の順に人ごとの束を写し**、
    /// 押した人から始めて、見終えたら次の人へ進む（`StoryReelView`）。
    /// 輪は1人＝1つで、各束は輪に出していた1本から開く
    private func open(_ story: Story) {
        let ordered = StoryPlayback.orderedRings(
            StoryPlayback.rings(model.stories, isSeen: { seen.contains($0) }),
            me: auth.userId,
            isUnseen: { seen.hasUnseen(model.siblings(of: $0)) })
        let rings = [ordered.mine].compactMap { $0 } + ordered.others
        let groups = StoryReel.groups(rings: rings, in: model.stories)
        let start = groups.firstIndex { $0.stories.contains { $0.id == story.id } }
        if let start {
            openedReel = (groups, start)
        } else {
            // 念のため（押した1本が並びに無い）: その人の束だけ
            let group = StoryPlayback.siblings(of: story, in: model.stories)
            openedReel = ([StoryReel.Group(stories: group.stories, start: group.index)], 0)
        }
        opened = story
    }

    /// 閲覧画面。**開いたときに写した並びを渡す**（`model.stories` から毎回作り直すと、
    /// 開いている間の読み直しで並びが変わり、見ている1本の位置がずれる）
    private func viewer(for story: Story) -> some View {
        var reel = openedReel
        // 写しが無い・別の1本の写し（念のため）なら、いまの一覧から作る
        if !reel.groups.contains(where: { $0.stories.contains { $0.id == story.id } }) {
            let group = StoryPlayback.siblings(of: story, in: model.stories)
            reel = ([StoryReel.Group(stories: group.stories, start: group.index)], 0)
        }
        return StoryReelView(groups: reel.groups, startGroup: reel.start,
                             viewerId: auth.userId, onSeen: { seen.markSeen($0) },
                             onDeleted: { model.remove(id: $0) })
    }
}

@MainActor
final class StoriesViewModel: ObservableObject {

    @Published private(set) var stories: [Story] = []
    /// 一度でも一覧を読めたか（読み終える前に「輪が無い」の行を出さない・2026-10-14）
    @Published private(set) var loaded = false
    /// 一度でも読み込みが終わったか（**取れなかった回も含む**）。終わるまで輪の列を出さない
    /// （`StoriesRow.showsRings`）。取れなかった回も立てる——立てないと、圏外で開いた人に
    /// 投稿の入口（自分の「＋」）がいつまでも出なかった（2026-10-16 判断）
    @Published private(set) var settled = false

    /// その1本と**同じ投稿者の束**（輪の色は束ごとに決める——1本でも
    /// 未読なら点ける）
    func siblings(of story: Story) -> [Story] {
        StoryPlayback.siblings(of: story, in: stories).stories
    }

    /// 消した1本を外す。**閲覧画面には開いたときの写しを渡している**ので、
    /// 開いている間に外しても閲覧画面の並びは動かない
    ///
    /// **消した id は覚えておき、読み直しの結果からも外す**——削除より先に始まった
    /// 読み直し（閉じたときの `onDismiss`）があとから返ると、消した1本が戻るため
    func remove(id: String) {
        deletedIds.insert(id)
        stories.removeAll { $0.id == id }
    }

    private var deletedIds: Set<String> = []

    /// いまの一覧を読んだ人（切り替えたら前の人の一覧を残さない）
    private var loadedFor: String?

    /// 読み込みの回。🔴 **取れた答えは、それより後に始めた回の取れた答えがもう入っていたら書かない。**
    /// 人が替わった直後は `.task` と `hidden.revision` の読み直しが同時に走り、先に始めた回が
    /// 後から着くと、前の人のブロックの集合で絞った一覧で戻していた。
    /// **取れなかった回は番号を進めない**——後の回が圏外で落ちたときに、先の回で取れた一覧まで
    /// 捨てると輪が空のまま残る（3dbf727 のレビュー）。先の回の答えは、最後に頼まれた
    /// ブロック・通報の集合で絞る
    private var loadSeq = 0
    private var appliedSeq = 0
    private var latestViewer: String??
    private var latestBlocked: Set<String> = []
    private var latestReported: Set<String> = []

    func load(environment: AppEnvironment, viewerId: String?, blockedUserIds: Set<String> = [],
              reportedPhotoIds: Set<String> = []) async {
        loadSeq += 1
        let seq = loadSeq
        defer { settled = true }
        latestViewer = .some(viewerId)
        latestBlocked = blockedUserIds
        latestReported = reportedPhotoIds
        // 取れなくても画面は壊さない（ストーリーは添え物）
        // ⚠️ `if let x = try? await …` は構文検査（tree-sitter）が読めない。2文に割る
        let fetched = try? await environment.stories.list()
        if fetched != nil {
            // 別の人の鍵で取った一覧は使わない・もっと新しい一覧が入っていたら使わない
            guard latestViewer == .some(viewerId), seq > appliedSeq else { return }
            appliedSeq = seq
        } else {
            // 取れなかった回は、いちばん新しい回のときだけ扱う（古い失敗で消さない）
            guard seq == loadSeq else { return }
        }
        stories = StoryPlayback.afterLoad(fetched: fetched, previous: stories,
                                          sameViewer: loadedFor == viewerId,
                                          blockedUserIds: latestBlocked,
                                          reportedPhotoIds: latestReported)
            .filter { !deletedIds.contains($0.id) }
        if fetched != nil {
            loadedFor = viewerId
            loaded = true
        }
    }
}
