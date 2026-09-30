import SwiftUI
// Linux では URLSession が別モジュールに居る（次の写真の先読み・iOS では何も起きない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ストーリーを全画面で見る。
///
/// **同じ投稿者の兄弟をまとめて受ける**（`StoryPlayback.siblings`）。
/// 上の進行バーは1本ごとの区切りで、写真は投稿者が選んだ秒数で自動送り、
/// 動画は鳴り終わりで次へ。決まりは `StoryPlayback` にあり、ここは描くだけ。
///
/// **止まる条件**は `StoryPlayback.isFrozen`——長押し・メニュー・シート・
/// 返信欄の焦点・送信中・絵がまだ出ていない、のどれか。
struct StoryViewerView: View {

    /// 同じ投稿者のストーリー（古い順）
    let stories: [Story]
    /// 見ている人。投稿者と同じなら本人の画面
    let viewerId: String?

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter
    /// アプリの状態（前面・通知センターを出した・ホームへ戻った）
    @Environment(\.scenePhase) private var scenePhase
    /// 前面に居るか。**`scenePhase` を直に読まず、ここへ写してから読む。**
    ///
    /// 時計（`runClock`）は1本ごとに一度だけ始まり、始めた瞬間の画面の
    /// 写しを持ち続ける。`@State` は入れ物を指しているので写しからでも
    /// 今の値が見えるが、`@Environment` は値を写しの中に持つので、
    /// 始めた瞬間の値のまま固まる——通知センターを出している間に次の1本へ
    /// 送られると、前面へ戻っても「止まっている」を見続け、その1本が
    /// 進まなくなる（2026-09-26 のレビューで見つかった）
    @State private var isForeground = true
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    /// 通報して落とした・自分で消した1本。**兄弟の並びから消す**（左タップで戻れないように）
    @State private var dropped: Set<String> = []

    // 進行
    /// 写真の時計（`StoryPlayback.Clock`）。**書き換わるのは動く／止まるの切り替えと、
    /// 1本を頭から始めたときだけ**——バーは `TimelineView` が描画ごとに読む
    @State private var clock = StoryPlayback.Clock()
    @State private var pressing = false
    /// 0.35秒押し続けた（`pressing` は触れた瞬間に立つので、見た目はこちらで決める）
    @State private var longHeld = false
    @State private var paused = false
    /// 止めている間に終わった1本（解けたら進める）
    @State private var pendingEnd: String?
    /// 終わりの知らせを受け取った1本（同じ1本の2回目を捨てる。移ったら空にする）
    @State private var endedIds: Set<String> = []
    /// 通報している1本。**押した時点で控える**——シートの `onDismiss` は閉じる動きの
    /// 後に走り、その間に次の1本へ進んでいると、描き直された閉包の `story` は
    /// 次の1本になっている（通報した1本が並びから落ちなかった）
    @State private var reportingStory: Story?
    @State private var muted = false
    /// この画面が鳴らした曲の回（`MusicPreviewPlayer.session`）。鳴らしていなければ nil
    @State private var songSession: Int?
    /// この画面の札（`MusicPreviewPlayer.beginStoryViewing`）。作り直すと新しくなる
    @State private var viewingToken = UUID()
    @State private var captionHidden = false
    /// いまの1本の写真が敷かれた大きさ（データで置いた文字の置き場所を決める）。移ったら nil
    @State private var mediaImageSize: CGSize?
    /// 票を入れたあとの票の状態（1本ごと）。**一覧を読み直すまでの間、入れた票を見せる**
    @State private var voteStates: [String: StoryVoteState] = [:]
    /// 票を送っている最中（二度押しを止める）
    @State private var voting = false
    /// 絵が出た（動画は出どころが無いので最初から true）
    @State private var mediaReady: Bool

    // メニューと確認
    @State private var showMenu = false
    @State private var showReport = false
    @State private var showBlockConfirm = false
    /// 見出しの名前を押して開く投稿者のページ
    @State private var showAuthor = false
    /// 撮影地から開いた撮影スポットのガイド（`StorySpotLink`）
    @State private var guideSpot: OfficialSpot?
    /// 撮影スポットの索引（撮影地をガイドへつなぐのに使う）。**取れなかった回は空**＝つながないだけ
    @State private var spotIndex: [OfficialSpot] = []
    /// 自分のストーリーを消す前の確認（板「25f 削除の確認」）。
    /// **以前は確認なしで即座に消えていた**
    @State private var showDeleteConfirm = false

    // 返信と反応
    @State private var reply = ""
    @FocusState private var replyFocused: Bool
    @State private var message: String?
    @State private var viewers: [StoryViewer] = []
    @State private var showInsights = false
    @State private var replies: [StoryReply] = []
    /// 返信を読み終えた（**「まだ」と「0件」を分ける**——同じ空の配列で
    /// 見分けていたので、読み込み中に反応込みの数を出して後で減っていた）
    @State private var repliesLoaded = false
    /// 見た人を読めたか。nil＝読み込み中、false＝読めなかった
    @State private var viewersLoaded: Bool?
    @State private var showReplies = false
    /// 返信を読めなかった。**空の一覧と区別する**（数は出ているのに
    /// 何も無い画面は「消えた」に見える）
    @State private var repliesFailed = false
    /// 送っている最中。**二度押しで2件送らない**。自動送りも止める
    @State private var isSending = false

    /// 見終えた1本を知らせる。**送るたびに呼ぶ**——次へ送ったぶんも
    /// 既読にしないと、閉じたときに輪が点いたまま残る
    let onSeen: ((String) -> Void)?
    /// 消し終えた1本を知らせる。**消している間に払って閉じても**、一覧から外せるように
    /// （閉じたときの読み直しが削除より先に走ると、消した1本が輪に戻っていた）
    let onDeleted: ((String) -> Void)?

    /// ハイライトとして見ている（板 38）。**期限の切れたストーリーの並び**なので、
    /// 返信欄・見た人・削除を出さない（返信はサーバーが期限切れを断り、
    /// 削除はハイライトではなくストーリーそのものを消してしまう）
    struct HighlightContext {
        let title: String
        let coverURL: URL?
        let count: Int
        /// 自分のハイライトなら「編集」
        let onEdit: (() -> Void)?
    }
    let highlight: HighlightContext?
    /// 外の画面が止めている（ハイライトの編集シートなど）。**時計は直に読まない**（`isHeld`）
    let holds: Bool
    /// `holds` の写し。**`isForeground` と同じ理由で `@State` に写してから読む**——
    /// `holds` はただの `let` なので、時計（`runClock`）が持つ画面の写しの中では
    /// 始めた瞬間の `false` のまま固まる。編集シートを開いても時計が進み、最後の1本
    /// なら画面ごと戻されていた（`HighlightPlayerView` の「止める」が効いていなかった）
    @State private var isHeld: Bool

    /// 束の最後まで見た。**あれば閉じずにこれを呼ぶ**（人から人への並び・`StoryReelView`
    /// が次の人へ回す）。無ければ今までどおり閉じる
    let onGroupEnd: (() -> Void)?
    /// 束の先頭で、始まってすぐ左を押した。**あれば前の人へ**（無ければ頭から）
    let onGroupBack: (() -> Void)?
    /// 払う動き（横・下）を外の画面が受け持つ（`StoryReelView` が指に付けて回す・縮める）。
    /// true のときこの画面の払いは何もしない——両方が動くと1回の払いで2つ進む
    let swipesHandledOutside: Bool
    /// 並びから落とした1本（通報・削除）を外へ知らせる。**人を行き来して閲覧画面が
    /// 作り直されても、落とした1本を戻さない**ため（`StoryReelView` が覚える）
    let onDropped: ((String) -> Void)?
    /// いま払ってはいけない（返信欄に入力中・メニューや確認が開いている・送信中）を
    /// 外へ知らせる。**外の払い（`StoryReelView`）が見る**——返信の一言の候補を横に
    /// 流しただけで次の人へ回り、書きかけが消えていた
    let onSwipeLockChange: ((Bool) -> Void)?

    init(stories: [Story], startIndex: Int, viewerId: String?,
         highlight: HighlightContext? = nil,
         holds: Bool = false,
         onGroupEnd: (() -> Void)? = nil,
         onGroupBack: (() -> Void)? = nil,
         swipesHandledOutside: Bool = false,
         onDropped: ((String) -> Void)? = nil,
         onSwipeLockChange: ((Bool) -> Void)? = nil,
         onSeen: ((String) -> Void)? = nil,
         onDeleted: ((String) -> Void)? = nil) {
        self.onGroupEnd = onGroupEnd
        self.onGroupBack = onGroupBack
        self.swipesHandledOutside = swipesHandledOutside
        self.onDropped = onDropped
        self.onSwipeLockChange = onSwipeLockChange
        self.stories = stories
        self.onDeleted = onDeleted
        self.viewerId = viewerId
        self.highlight = highlight
        self.holds = holds
        _isHeld = State(initialValue: holds)
        self.onSeen = onSeen
        let start = stories.indices.contains(startIndex) ? startIndex : 0
        _index = State(initialValue: start)
        _mediaReady = State(initialValue: stories.indices.contains(start) ? stories[start].isVideo : false)
    }

    /// 通報で落としたぶんを除いた並び
    private var visible: [Story] { stories.filter { !dropped.contains($0.id) } }

    private var current: Story? {
        visible.indices.contains(index) ? visible[index] : nil
    }

    private func isMine(_ story: Story) -> Bool {
        viewerId != nil && story.userId == viewerId
    }

    private var frozen: Bool {
        StoryPlayback.isFrozen(
            pressing: pressing,
            paused: paused,
            menuOpen: showMenu,
            sheetOpen: showReplies || showInsights || showReport || showBlockConfirm
                || showAuthor || showDeleteConfirm || guideSpot != nil || isHeld,
            replyFocused: replyFocused,
            isSending: isSending,
            mediaReady: mediaReady,
            // 前面に居ない間は止める（動画も止まり、戻ると続きから）
            inBackground: !isForeground
        )
    }

    /// 払ってはいけない間（`onSwipeLockChange`）。長押し・絵の読み込みは含めない
    /// （止まっていても払って次へは行ける）
    private var swipeLocked: Bool {
        replyFocused || isSending || showMenu || showReplies || showInsights || showReport
            || showBlockConfirm || showAuthor || showDeleteConfirm || guideSpot != nil
    }

    /// この人の束をもう見せられない（最後の1本を消した・通報した・ブロックした）。
    /// **並びの中なら次の人へ**、そうでなければ閉じる
    private func leaveGroup() {
        if let onGroupEnd { onGroupEnd() } else { dismiss() }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let story = current {
                content(for: story)
            }
        }
        // 曲（板の「♪」）。**鳴らしていなかった**——曲名を文字で出すだけだった
        .onAppear {
            // 開いている間は場を返さない（動画の音を切らない）。返すのは閉じたとき
            MusicPreviewPlayer.shared.beginStoryViewing(viewingToken)
            // **ほかで鳴っている曲は止める**（Web の `stopGlobalMusic`）。止めないと
            // 動画の音と重なり、「音を消す」がその曲を消音していた
            if MusicPreviewPlayer.shared.playingURL != nil {
                MusicPreviewPlayer.shared.stop(releaseSession: false)
            }
            syncSong(restart: true)
        }
        .onChange(of: current?.id) { _, _ in syncSong(restart: true) }
        .onChange(of: frozen) { _, isFrozen in
            // **止まった瞬間にバーも止める。** 時計の見回り（`runClock`）を待つと、長押しから
            // 最大 `clockStep` だけバーが進み続けて見える
            syncClock(frozen: isFrozen)
            syncSong(restart: false)
            settlePendingEnd()
        }
        // 知らせが消えたら（2.5秒で消える）、待たせていた1本を進める
        .onChange(of: message) { _, _ in settlePendingEnd() }
        .onChange(of: holds) { _, now in isHeld = now }
        .onChange(of: muted) { _, now in
            if ownsSong { MusicPreviewPlayer.shared.setMuted(now) }
        }
        // 閉じたら止める（閉じたあとも鳴り続けないように）。場は最後の閲覧画面が
        // 閉じたときに返す（返さないと他のアプリの音楽が戻らない）
        .onDisappear {
            stopSong()
            MusicPreviewPlayer.shared.endStoryViewing(viewingToken)
        }
    }

    // MARK: - 曲

    /// 表示中の1本に合わせて曲を鳴らす・止める。
    ///
    /// - 別の1本に移った・頭から見直した（`restart`）→ 頭から
    /// - 止めている間（長押し・一時停止・メニュー・シート・背面）→ 一時停止、解けたら続きから
    /// - 曲の無い1本 → 止める
    private func syncSong(restart: Bool) {
        let player = MusicPreviewPlayer.shared
        guard let story = current, let url = StoryPlayback.songURL(for: story) else {
            // 曲の無い1本では止めるが、場は返さない（その1本の動画の音を切らない）
            stopSong()
            return
        }
        if restart || songSession == nil {
            // `song` は渡さない——ストーリーの曲は画面の下の再生バーに出す曲ではない
            // Web で選んだ「好きな部分」から鳴らす（繰り返しもそこから）
            songSession = player.play(url, song: nil, loops: true, from: StoryPlayback.songStart(for: story))
        }
        // 自分の曲でなくなっていたら（ほかの画面が鳴らした）触らない
        guard ownsSong else { return }
        player.setMuted(muted)
        if frozen { player.pause() } else { player.resume() }
    }

    /// いま鳴っているのがこの画面の鳴らした曲か
    private var ownsSong: Bool {
        songSession != nil && songSession == MusicPreviewPlayer.shared.session
            && MusicPreviewPlayer.shared.playingURL != nil
    }

    /// **自分が鳴らした曲だけ止める。** 見分けは URL ではなく鳴らした回の番号
    /// ——通報で並びから外れた1本の曲も止まり、同じ曲を別の画面が鳴らし直しても
    /// そちらは止めない
    private func stopSong() {
        defer { songSession = nil }
        guard ownsSong else { return }
        // 場は返さない（閉じたときに `endStoryViewing` が返す）
        MusicPreviewPlayer.shared.stop(releaseSession: false)
    }

    /// 写真の下に残す黒い帯の高さ（足元の操作がここに乗る。板は 844 のうち 84）
    private static let footerHeight: CGFloat = 60

    /// **写真を画面いっぱいに敷き、全部をその上に重ねる**（ストーリーの板）。
    ///
    /// 以前は 進行バー → 見出し → 写真（`.fit`）→ ひとこと → 足元 と縦に積んでいて、
    /// 写真の上下に黒い帯が出ていた。板は写真が上端まで伸び、下の角だけ丸く、
    /// その下の黒い帯に返信欄が乗る
    private func content(for story: Story) -> some View {
        ZStack(alignment: .top) {
            if let highlight {
                // ハイライトは写真を画面いっぱい（角丸なし）に敷き、足元も重ねる
                photoArea(for: story)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        highlightFooter(for: story, highlight: highlight)
                            .opacity(chrome.hidesChrome ? 0 : 1)
                    }
            } else {
            VStack(spacing: 0) {
                photoArea(for: story)
                    .ignoresSafeArea(edges: .top)
                footer(for: story)
                    .frame(minHeight: Self.footerHeight)
                    // 止めている間は足元を隠す（板「25b」は進行バーだけ残す）。
                    // 場所は残す——消すと写真の枠が伸び縮みする
                    .opacity(chrome.hidesChrome ? 0 : 1)
                    .allowsHitTesting(!chrome.hidesChrome)
            }
            }
            VStack(spacing: 9) {
                progressBar(for: story)
                header(for: story)
                    .opacity(chrome.hidesChrome ? 0 : 1)
                    .allowsHitTesting(!chrome.hidesChrome)
            }
            .padding(.top, 5)

            if chrome.showsPill {
                pausedPill
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            if showMenu {
                menuSheet(for: story)
            }
            if showDeleteConfirm {
                deleteConfirm(for: story)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showMenu)
        .animation(.easeOut(duration: 0.18), value: chrome)
        .task(id: story.id) {
            // 端末の既読（輪の色）。**サーバーの応答を待たない**
            // ——圏外でも、見たものは見たことにする
            onSeen?(story.id)
            // ハイライトは期限切れの並び。見た印も見た人・返信も、サーバーは
            // 期限で消しているので叩かない
            guard highlight == nil else { return }
            // **見たことを伝えるのは1回。** 失敗しても画面は止めない
            await environment.stories.markViewed(id: story.id)
            if isMine(story) {
                // **次の1本へ移ったあとに返ってきた答えは書かない。** 書くと、`go` で
                // 空にしたあとへ前の1本の見た人・返信が入り、いまの1本の数に見える
                do {
                    let loaded = try await environment.stories.viewers(id: story.id)
                    guard !Task.isCancelled else { return }
                    viewers = loaded
                    viewersLoaded = true
                } catch {
                    guard !Task.isCancelled else { return }
                    viewersLoaded = false
                }
                // **返信は本人だけが読める。** 読めないと、送られた返信が
                // どこにも出ない（送る側の画面だけあった）
                do {
                    let loaded = try await environment.stories.replies(id: story.id)
                    guard !Task.isCancelled else { return }
                    replies = loaded
                    repliesFailed = false
                    repliesLoaded = true
                } catch {
                    guard !Task.isCancelled else { return }
                    repliesFailed = true
                }
            }
        }
        // 時計は読み込みと別に回す。同じ task に入れると、見た人の一覧を
        // 待っている間、写真が出ているのに秒数が始まらない
        .task(id: story.id) { await runClock(for: story) }
        // 次の写真を先に読んでおく（1本ごとにバーが 0 のまま待たないように）
        .task(id: story.id) { prefetchNext() }
        .onAppear {
            isForeground = scenePhase == .active
            onSwipeLockChange?(swipeLocked)
        }
        .onChange(of: swipeLocked) { _, locked in onSwipeLockChange?(locked) }
        .onChange(of: scenePhase) { _, phase in isForeground = phase == .active }
        .alert(L("この人をブロックしますか？", "Block this person?"), isPresented: $showBlockConfirm) {
            Button(L("ブロック", "Block"), role: .destructive) {
                Task { await block(story) }
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("おたがいの投稿・ストーリー・通知が見えなくなります。設定からいつでも解除できます。", "You won't see each other's posts, stories or notifications. You can undo this in Settings."))
        }
        .sheet(isPresented: $showReport, onDismiss: {
            let reported = reportingStory ?? story
            reportingStory = nil
            afterReport(reported)
        }) {
            // **写真の通報と同じ口。** サーバーの `report.ts` は id で行を引き、
            // ストーリー行（`story-<uuid>`）も `src` を持つので通る
            let target = reportingStory ?? story
            ReportSheet(photoId: target.id, ownerId: target.userId)
        }
        // 一覧から開いたページでブロックしたら、その人の返信を外す
        .sheet(isPresented: $showReplies, onDismiss: {
            replies.removeAll { reply in reply.uid.map { hidden.blockedUserIds.contains($0) } ?? false }
        }) {
            repliesSheet
        }
        // **ページの中でブロックしたら、閲覧画面ごと閉じる**（「…」からの
        // ブロックと同じ後始末）。閉じないとブロックした人のストーリーが流れ続ける
        .sheet(isPresented: $showAuthor, onDismiss: {
            if let userId = story.userId, hidden.blockedUserIds.contains(userId) { leaveGroup() }
        }) {
            if let userId = story.userId {
                NavigationStack {
                    UserProfileView(userId: userId)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                        }
                }
            }
        }
        // 撮影地から開いた撮影スポットのガイド。**見ている間は止める**（`frozen` の sheetOpen）
        .sheet(item: $guideSpot) { spot in
            NavigationStack {
                OfficialSpotView(spot: spot, spots: spotIndex, photos: [])
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                    }
            }
        }
        // 撮影スポットの索引は**一度だけ**読む（静的な JSON・サービスに60秒の控えと端末の控え）
        .task {
            guard spotIndex.isEmpty else { return }
            let fetched = try? await environment.spots.fetchIndex()
            guard !Task.isCancelled, let fetched else { return }
            spotIndex = fetched
        }
        .sheet(isPresented: $showInsights) {
            NavigationStack {
                StoryInsightsView(story: story)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                    }
            }
        }
    }

    // MARK: - 写真

    /// 写真・上下の暗がり・指の操作・ひとこと。**下の角だけ丸める**（板は半径24）
    private func photoArea(for story: Story) -> some View {
        ZStack(alignment: .bottomLeading) {
            // **写真は「透明な枠の上に重ねる」形で置く。** `.fill` の絵は枠より
            // 大きい寸法を申告するので、そのまま並べると ZStack ごと画面より
            // 広がり、上に重ねた文字や操作が画面の外へずれる
            Color.black
            Color.clear.overlay {
            StoryMedia(
                story: story,
                isMuted: StoryPlayback.videoMuted(muted: muted,
                                                  hasSong: StoryPlayback.songURL(for: story) != nil),
                isPaused: frozen,
                onEnded: { [id = story.id] in mediaEnded(id) },
                // 出せないと分かった回も進める——止めたままだと永久に固まる
                // （Web の `!mediaReady && !mediaError` と同じ）
                onSettled: { _ in mediaReady = true },
                onImageLayout: { [id = story.id] size in
                    // 前の1本の絵の知らせが遅れて来ても、いまの1本に当てない
                    if visible.indices.contains(index), visible[index].id == id { mediaImageSize = size }
                }
            )
            // 🔴 **1本ごとに作り直す。** 同じ型・同じ場所のままだと SwiftUI は
            // 部品を使い回し、動画の再生器（`StoryVideo` の `@State`）が前の1本の
            // まま残る——動画が2本続くと、2本目は1本目の終わりの絵で止まり、
            // 鳴り終わりの合図も来ないので先へ進めなかった
            .id(story.id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // 上と下の暗がり（白い文字を写真の明るさに負けさせない。板は上180・下200）。
            // **重ねて置き、寸法の申告に加えない。** 縦に積むと合わせて 380pt を
            // 求め、キーボードで写真の枠が縮んだときに枠ごと画面からあふれた
            .overlay(alignment: .top) {
                LinearGradient(colors: [Color.black.opacity(0.65), Color.black.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
                    .allowsHitTesting(false)
            }

            tapZones

            // Web で置いた文字・スタンプ・投票（`texts`）。**送る的より上**——投票のボタンを
            // 押せるように（ほかは指を素通りさせる）。「テキストを非表示」で隠す（Web と同じ）
            if !story.texts.isEmpty && !captionHidden {
                StoryTextLayer(texts: story.texts,
                               imageSize: story.isVideo ? nil : mediaImageSize,
                               voteState: voteStates[story.id] ?? story.vote,
                               canVote: viewerId != nil && !isMine(story) && highlight == nil,
                               voting: voting,
                               onVote: { choice in Task { await sendVote(choice, to: story) } })
                    .id(story.id)
            }

            // 暗幕。メニュー45%・返信を書いている間35%・削除の確認55%（板の値）
            Color.black
                .opacity(dimOpacity)
                .allowsHitTesting(false)

            // **撮影地の行だけ押せる**（撮影スポットのガイドへ）。ひとことと曲は指を素通りさせ、
            // 左右の送る的を塞がない（中で1つずつ `allowsHitTesting(false)` を付ける）
            captionBlock(for: story)
                .padding(.horizontal, 32)
                .padding(.bottom, highlight == nil ? 96 : 150)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .jpGlass(in: Capsule())
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
                    // **少しで消す。** 画面の外の知らせ（`ToastCenter`）は全画面の
                    // 上には出ないので、ここで出して自分で片づける
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        if !Task.isCancelled { self.message = nil }
                    }
            }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: highlight == nil ? 24 : 0,
                                          bottomTrailingRadius: highlight == nil ? 24 : 0))
    }

    /// ひとこと（明朝30・影）・撮影地・曲。**写真の左下に重ねる**（板の配置）。
    /// 撮影地は以前は見出しの2行目にあった
    @ViewBuilder
    private func captionBlock(for story: Story) -> some View {
        // **文字をデータで置いた1本はひとことを出さない**——`caption` はその文字から作られた
        // もので、写真の上の文字と二重になる（Web も `texts` があれば出さない）
        let caption = captionHidden || !story.texts.isEmpty ? nil : story.caption.flatMap { $0.isEmpty ? nil : $0 }
        let place = story.location.flatMap { $0.isEmpty ? nil : $0 }
        let song = story.songLine
        if caption != nil || place != nil || song != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let caption {
                    Text(caption)
                        .font(JPFont.display(30, relativeTo: .largeTitle))
                        .lineSpacing(6)
                        // 長い文でも写真の枠を押し広げない（ひとことは200字まで）
                        .lineLimit(5)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white)
                        .jpPhotoTextShadow()
                        .allowsHitTesting(false)
                }
                if let place {
                    if let spot = StorySpotLink.spot(for: story, in: spotIndex) {
                        // 撮影地 → 撮影スポットのガイド（「行きたい」もそこで押せる）
                        Button {
                            guideSpot = spot
                        } label: {
                            HStack(spacing: 4) {
                                photoMeta(symbol: "mappin", text: place)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(WebTheme.muted)
                                    .jpPhotoTextShadow()
                            }
                            .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("撮影地 \(place)。撮影スポットのガイドを開く",
                                              "Location \(place). Open the photo spot guide"))
                    } else {
                        photoMeta(symbol: "mappin", text: place)
                            .allowsHitTesting(false)
                    }
                }
                if let song {
                    photoMeta(symbol: "music.note", text: song)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// 写真の上の小さい行（ピン・音符＋12pt）
    private func photoMeta(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .foregroundStyle(WebTheme.muted)
        .jpPhotoTextShadow()
    }

    // MARK: - 進行バー

    /// 1本ごとの区切り。**写真だけ経過を塗る。** 動画の区切りは経過の
    /// 出どころが無いので塗らず、少し明るい地で「今ここ」だけ示す
    ///
    /// **画面の描画ごとに伸ばす**（`TimelineView(.animation)`）。止まっている間は
    /// 描き直しも止める（`paused`）。時計の刻みで伸ばすと、刻みの遅れがそのまま
    /// 「一瞬止まってから動く」段差に見えた（`StoryPlayback.Clock`）
    private func progressBar(for story: Story) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: !clock.isRunning)) { context in
            let fills = StoryPlayback.segmentFills(
                count: visible.count,
                current: index,
                elapsed: clock.elapsed(at: context.date),
                duration: StoryPlayback.duration(seconds: story.durationSec),
                isVideo: story.isVideo
            )
            HStack(spacing: 4) {
                ForEach(fills.indices, id: \.self) { i in
                    segment(fill: fills[i], isCurrent: i == index)
                }
            }
        }
        .frame(height: 3)
        // **バーには外の動きを乗せない。** 一時停止を解いて次へ移ると、同じ更新で
        // 見出しの出し入れ（`.animation(value: chrome)`）が走り、0へ戻る縮みが見えた
        .transaction { $0.animation = nil }
        .padding(.horizontal, 10)
        .accessibilityLabel(L("\(visible.count)本中\(index + 1)本目", "\(index + 1) of \(visible.count)"))
    }

    private func segment(fill: Double?, isCurrent: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(isCurrent && fill == nil ? 0.6 : 0.3))
                if let fill {
                    // アニメーションは付けない——描画ごとに正しい幅を描くので、
                    // 付けると0へ戻るとき（次の1本・頭から）に縮む動きが見える
                    Capsule().fill(Color.white)
                        .frame(width: geo.size.width * fill)
                }
            }
        }
    }

    // MARK: - 見出し

    /// アバター34・名前14・経過時間12を1行に。右に「…」と ✕（地なし・44）。
    /// 名前を押すと投稿者のページ（板のリンク）
    private func header(for story: Story) -> some View {
        HStack(spacing: 10) {
            // 自分の名前は押せない形で描く（自分のページはマイページ）。
            // 無効のボタンにすると薄く描かれ、読み上げも「使用不可」になる
            if let highlight {
                highlightLabel(highlight)
            } else if isMine(story) || story.userId == nil {
                authorLabel(for: story)
            } else {
                Button {
                    showAuthor = true
                } label: {
                    authorLabel(for: story)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            // 上の「…」は人の投稿（通報とブロックの入口・審査 1.2。人のハイライトも）と、
            // **自分のハイライトで音があるとき**（動画・曲。音を消す口がここにしか無い）だけ。
            // 自分のストーリー（ハイライト以外）は足元の「…」が同じシートを開くので出さない
            // （同じ印が上下に2つ並ぶ）
            if StoryPlayback.showsTopMenu(isMine: isMine(story), inHighlight: highlight != nil,
                                          hasAudio: story.isVideo || StoryPlayback.songURL(for: story) != nil) {
                Button {
                    showMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .webTappable()
                        .accessibilityLabel(L("その他の操作", "More actions"))
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .webTappable()
                    .accessibilityLabel(Labels.Common.close)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
    }

    /// ハイライトの見出し（表紙・題・「ストーリーハイライト · 5件」。板 38）
    private func highlightLabel(_ highlight: HighlightContext) -> some View {
        HStack(spacing: 10) {
            Group {
                if let url = highlight.coverURL {
                    RemoteImage(url: url)
                } else {
                    Circle().fill(WebTheme.surface)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 0) {
                Text(highlight.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(L("ストーリーハイライト · \(highlight.count)件", "Story highlight · \(highlight.count)"))
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.muted)
            }
        }
        .frame(minHeight: WebTheme.minTapTarget)
    }

    /// ハイライトの足元（左に等幅の日付、右に自分なら「編集」）
    private func highlightFooter(for story: Story, highlight: HighlightContext) -> some View {
        HStack {
            if let date = StoryPlayback.dotDate(story.createdAt) {
                Text(L("\(date) · 残したストーリー", "\(date) · Kept story"))
                    .font(JPFont.mono(11))
                    .foregroundStyle(WebTheme.muted)
            }
            Spacer(minLength: 0)
            if let onEdit = highlight.onEdit {
                Button(action: onEdit) {
                    Text(L("編集", "Edit"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .jpGlass(in: Capsule(), border: 0.4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    /// 見出しの左（アバター・名前・時刻）
    private func authorLabel(for story: Story) -> some View {
        HStack(spacing: 10) {
            if let userId = story.userId {
                RemoteImage(url: UserProfile.profileAssetURL(userId: userId, suffix: nil, cacheBust: nil),
                            placeholderSymbol: "person.crop.circle.fill")
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            }
            if isMine(story) {
                // 自分: 「あなた」と、下に等幅で「2時間前 · あと 22 時間で消えます」（板 25e）
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("あなた", "You"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    if let line = ownTimeLine(for: story) {
                        Text(line)
                            .font(JPFont.mono(11))
                            .foregroundStyle(WebTheme.muted2)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(story.authorName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let ago = StoryPlayback.ago(from: story.createdAt) {
                    Text(ago)
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.muted)
                        .lineLimit(1)
                }
            }
        }
        .frame(minHeight: WebTheme.minTapTarget)
        .contentShape(Rectangle())
    }

    // MARK: - 指の操作

    /// 左半分は前へ（始まってすぐ）か最初から、右半分は次へ。
    /// **押している間は止まる**（離すと再開）。
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { leftTap() }
                .onLongPressGesture(minimumDuration: 0.35, perform: { longHeld = true }, onPressingChanged: { pressedNow in
                    pressing = pressedNow
                    if !pressedNow { longHeld = false }
                })
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if paused { paused = false } else if !isSending { advance() }
                }
                .onLongPressGesture(minimumDuration: 0.35, perform: { longHeld = true }, onPressingChanged: { pressedNow in
                    pressing = pressedNow
                    if !pressedNow { longHeld = false }
                })
        }
        // **払っても動く。** 他のアプリのストーリーは全部そうなので、
        // タップしか効かないと「反応しない」と受け取られる。
        // 行き先はタップと同じに寄せた（`StoryPlayback.swipe`）——同じ画面で
        // 「押すと進む」と「払うと別の動き」が並ぶと、人が覚えられない
        .simultaneousGesture(
            DragGesture(minimumDistance: StoryPlayback.swipeThreshold)
                .onEnded { value in
                    guard !swipesHandledOutside else { return }
                    switch StoryPlayback.swipe(
                        dx: value.translation.width, dy: value.translation.height) {
                    case .next: if !isSending { advance() }
                    case .back: leftTap()
                    case .close: dismiss()
                    case .ignore: break
                    }
                }
        )
    }

    private func leftTap() {
        // **メニューで止めているなら、押すと続きから**（板「25b」）
        if paused { paused = false; return }
        // 🔴 **送っている間（返信・♡・残す・削除）は前後へ送らない。** 止めていたのは
        // 時計だけで、タップや払いでは移れたため、結果の「残しました」「送れません
        // でした」が別の1本の画面に出ていた。**払って閉じるのは止めない**（圏外で
        // 返事を待つ間に閉じられなくなる）
        guard !isSending else { return }
        switch StoryPlayback.leftTap(index: index, elapsed: clock.elapsed(at: Date()),
                                     hasPreviousGroup: onGroupBack != nil) {
        case .previousGroup:
            onGroupBack?()
        case .restart:
            // 動画は時計を回さない（回すと次の1本まで毎フレーム描き直す）
            clock.restart(running: !frozen && !(current?.isVideo ?? false), at: Date())
            syncSong(restart: true)
        case .previous(let target):
            go(to: target)
        }
    }

    /// 動画の終わり（読めずに諦めた回も）。`StoryPlayback.mediaEnded`
    ///
    /// **知らせ（「送りました」・失敗）が出ている間も待つ。** 進むと `go` が消し、
    /// 一瞬も読めなかった。知らせは2.5秒で消え、そこで `settlePendingEnd` が進める
    private func mediaEnded(_ id: String) {
        switch StoryPlayback.mediaEnded(storyId: id, currentId: current?.id,
                                        frozen: frozen || message != nil) {
        case .ignore: break
        case .hold: pendingEnd = id
        case .advance:
            // 同じ1本の2回目（失敗の通知と状態の見張りの両方）は捨てる——最後の1本だと
            // 2回閉じていた
            guard endedIds.insert(id).inserted else { return }
            advance()
        }
    }

    /// 待たせていた終わりを、止めも知らせも無くなったところで進める
    private func settlePendingEnd() {
        guard !frozen, message == nil, let pending = pendingEnd else { return }
        pendingEnd = nil
        mediaEnded(pending)
    }

    /// 次へ。**最後なら閉じる**（人から人への並びの中なら、次の人へ）
    private func advance() {
        if let target = StoryPlayback.next(after: index, count: visible.count) {
            go(to: target)
        } else if let onGroupEnd {
            onGroupEnd()
        } else {
            dismiss()
        }
    }

    /// 別の1本へ移る。**前の1本の状態を持ち越さない**——返信の下書き・
    /// 「送りました」・見た人・返信の一覧が別のストーリーの画面に出ないように
    private func go(to target: Int) {
        guard visible.indices.contains(target) else { return }
        index = target
        // 止めておく。絵が出て（`mediaReady`）止める理由が無くなったら `syncClock` が動かす
        clock.restart(running: false, at: Date())
        pendingEnd = nil
        endedIds = []
        // 別の1本へ移ったら止めていたのを解く（払って移ると止まったまま進んでいた）
        paused = false
        mediaReady = visible[target].isVideo
        captionHidden = false
        mediaImageSize = nil
        reply = ""
        message = nil
        viewers = []
        replies = []
        repliesFailed = false
        repliesLoaded = false
        viewersLoaded = nil
    }

    /// 時計の見回りの間隔。**バーの動きはこの長さに縛られない**（描画ごとに伸びる）。
    /// 決めるのは「使い切ったら次へ」の遅れの上限だけ
    private static let clockStep: TimeInterval = 0.05

    /// 時計を今の止まる条件に合わせる。**変わったときだけ `@State` を書く**
    /// （同じ値を書き続けると、それだけで画面全体が描き直される）
    private func syncClock(frozen isFrozen: Bool) {
        guard current.map({ !$0.isVideo }) ?? false else { return }
        var next = clock
        if next.set(running: !isFrozen, at: Date()) { clock = next }
    }

    /// 写真の時計の見回り。**動画は回さない**（鳴り終わりが送る）。
    /// 経過は `StoryPlayback.Clock` が時刻から計算するので、`sleep` の遅れで
    /// バーが止まって見えることはない。ここは「使い切ったら次へ」だけを見る。
    /// **アプリが背面にある間は止まっている**（`isForeground` が `frozen` に入る）ので、
    /// その時間は数えない
    private func runClock(for story: Story) async {
        guard !story.isVideo else { return }
        let duration = StoryPlayback.duration(seconds: story.durationSec)
        syncClock(frozen: frozen)
        while !Task.isCancelled {
            let before = Date()
            try? await Task.sleep(for: .milliseconds(Int(Self.clockStep * 1000)))
            if Task.isCancelled { return }
            // 🔴 **間があきすぎた分は数えない**（`StoryPlayback.stalledSeconds`）。前面に戻る
            // 合図（`isForeground`）より先にここが走ると、背面にいた時間を丸ごと足して
            // 次の1本へ飛んでいた（2026-09-26 のバグ探し。旧 `tickDelta` と同じ守り）
            // **間のうち、時計が動いていた部分だけを見る**（見回りが眠った後で動き出した
            // 分まで捨てない）
            let now = Date()
            if let since = clock.runningSince {
                let stalled = StoryPlayback.stalledSeconds(gap: now.timeIntervalSince(max(before, since)))
                if stalled > 0 {
                    var next = clock
                    next.discard(stalled, at: now)
                    clock = next
                }
            }
            // `onChange(of: frozen)` の取りこぼしに備えて、ここでも合わせる
            syncClock(frozen: frozen)
            // 知らせ（「送りました」など）が出ている間は進めない（`go` が消して読めない）。
            // 知らせは2.5秒で消える
            if !frozen, message == nil, clock.elapsed(at: Date()) >= duration {
                advance()
                return
            }
        }
    }

    /// 次の1本が写真なら、先に読んでおく。`AsyncImage` と同じ `URLSession.shared`
    /// （＝`URLCache.shared`・`JourneyPhotoApp` で容量を広げてある）に入れるだけ。
    /// **失敗は気にしない**（表示のときにもう一度読む）
    private func prefetchNext() {
        guard let target = StoryPlayback.next(after: index, count: visible.count),
              visible.indices.contains(target),
              !visible[target].isVideo,
              let url = visible[target].imageURL else { return }
        URLSession.shared.dataTask(with: url).resume()
    }

    // MARK: - 「…」のメニュー

    /// 止めている間の見せ方（`StoryPlayback.chrome`）。**メニューを開いている間は
    /// 数えない**——メニューの板は見出しを見せたまま暗くするだけ
    private var chrome: StoryPlayback.Chrome {
        StoryPlayback.chrome(longHeld: longHeld, paused: paused,
                             overlayOpen: showMenu || showDeleteConfirm)
    }

    private var dimOpacity: Double {
        if showDeleteConfirm { return 0.55 }
        if showMenu { return 0.45 }
        if replyFocused { return 0.35 }
        return 0
    }

    /// 危ない操作の文字（ブロック・通報・削除）。**危険の色 `WebTheme.danger`（#F0565A）**。
    /// 以前は `#ff8a80` で「黒地用の danger は暗い面で読めない」としていたが、実際は
    /// シート #161618 の上で 5.32:1、確認の面 #1E1E20 の上で 4.9:1 と文字の線を越える（デザインシステム「黒塗りの真鍮」）
    private static let storyDanger = WebTheme.danger

    /// 板「25b 長押しで一時停止」の札（ガラスの丸・13pt）
    private var pausedPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause")
                .font(.system(size: 14))
            Text(StoryPlayback.pausedNote(pressing: chrome.pillSaysRelease))
                .font(.system(size: 13))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .jpGlass(in: Capsule(), border: 0)
    }

    // MARK: - 「…」のメニュー

    /// 板「25c」の下からのシート。**開いている間は止まる**ことを上に書く。
    /// 出す項目は `StoryPlayback.menuItems` が決める（押しても何も起きない
    /// 項目は出さない）
    private func menuSheet(for story: Story) -> some View {
        let items = StoryPlayback.menuItems(
            isMine: isMine(story),
            isVideo: story.isVideo,
            hasSong: StoryPlayback.songURL(for: story) != nil,
            hasCaption: story.caption?.isEmpty == false || !story.texts.isEmpty,
            hasOwner: story.userId != nil,
            canKeep: Self.canKeepAsPhoto(story),
            inHighlight: highlight != nil
        )
        return ZStack(alignment: .bottom) {
            // 外を押したら閉じる
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showMenu = false }
                .ignoresSafeArea()
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text(L("開いている間は止まっています", "Paused while this is open"))
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                    if items.contains(.pause) {
                        menuRow(symbol: paused ? "play" : "pause",
                                title: paused ? L("再開", "Resume") : L("一時停止", "Pause")) {
                            paused.toggle()
                        }
                    }
                    if items.contains(.mute) {
                        menuRow(symbol: muted ? "speaker.wave.2" : "speaker.slash",
                                title: muted ? L("音を出す", "Unmute") : L("音を消す", "Mute")) {
                            muted.toggle()
                        }
                    }
                    if items.contains(.hideCaption) {
                        menuRow(symbol: "textformat",
                                title: captionHidden ? L("テキストを表示", "Show text") : L("テキストを非表示", "Hide text")) {
                            captionHidden.toggle()
                        }
                    }
                    if items.contains(.block) {
                        // 「非表示」とは書かない。サーバーにあるのは両向きのブロックだけで、
                        // 片向きに隠す口は無い（相手からも見えなくなる）
                        menuRow(symbol: "nosign", title: L("\(story.authorName) をブロック", "Block \(story.authorName)"),
                                danger: true) {
                            showBlockConfirm = true
                        }
                    }
                    if items.contains(.report) {
                        menuRow(symbol: "flag", title: L("通報する", "Report"), danger: true) {
                            reportingStory = story
                            showReport = true
                        }
                    }
                    // 24時間で消える前に、自分の写真として残す。
                    // **動画には出さない**（サーバーが 400 で断る・`storyKeep.ts`）
                    // **自分用（アーカイブ）の投稿にも出さない**（サーバーが 409 で断る・`storyKeep.ts`）
                    if items.contains(.keep) {
                        menuRow(symbol: "bookmark", title: L("写真として残す", "Keep as photo")) {
                            Task { await keep(story) }
                        }
                        .disabled(isSending)
                    }
                    // **確かめてから消す**（以前は押した瞬間に消えていた）
                    if items.contains(.delete) {
                        menuRow(symbol: "trash", title: Labels.Common.delete, danger: true) {
                            showDeleteConfirm = true
                        }
                        .disabled(isSending)
                    }
                }
                .background(Self.sheetColor, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    showMenu = false
                } label: {
                    Text(Labels.Common.cancel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Self.sheetColor, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        // 読み上げでも裏（見出し・返信欄）に触れさせない
        .accessibilityAddTraits(.isModal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// シートの地（板の `#161618`）
    private static let sheetColor = Color(red: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x18 / 255.0)

    /// メニューの1行。**押したらメニューを閉じてから動く**
    private func menuRow(symbol: String, title: String, danger: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button {
            showMenu = false
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 16))
                Spacer(minLength: 0)
            }
            .foregroundStyle(danger ? Self.storyDanger : WebTheme.text)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 削除の確認

    /// 板「25f」。**見た人の記録と返信も消える**ことを書く（`stories.ts` の
    /// deleteStory が返信と票を消してから行を消す）
    private func deleteConfirm(for story: Story) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showDeleteConfirm = false }
                .ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(L("このストーリーを削除しますか？", "Delete this story?"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(L("見た人の記録と返信も消えます。元に戻せません。",
                           "Viewers and replies are deleted too. This can't be undone."))
                        .font(.system(size: 13))
                        .foregroundStyle(WebTheme.muted2)
                        .lineSpacing(4)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 16)
                confirmButton(L("削除", "Delete"), color: Self.storyDanger, weight: .semibold) {
                    showDeleteConfirm = false
                    Task { await deleteStory(story) }
                }
                confirmButton(Labels.Common.cancel, color: .white, weight: .regular) {
                    showDeleteConfirm = false
                }
            }
            .frame(width: 280)
            .background(Color(red: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x20 / 255.0),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityAddTraits(.isModal)
    }

    private func confirmButton(_ title: String, color: Color, weight: Font.Weight,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: weight))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                }
        }
        .buttonStyle(.plain)
    }

    /// ブロックの手順は `UserProfileViewModel.block` と同じ
    /// （サーバー → 端末の控え → 公開一覧 → toast）。兄弟は全部同じ投稿者
    /// なので、成功したら画面ごと閉じる
    private func block(_ story: Story) async {
        guard let userId = story.userId else { return }
        let owner = hidden.owner
        do {
            try await environment.moderation.block(userId: userId)
            hidden.block(userId, for: owner)
            await environment.gallery.setHidden(hidden.snapshot)
            toasts.show(L("ブロックしました。設定から解除できます。",
                          "Blocked. You can undo this in Settings."))
            leaveGroup()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }

    /// 通報のシートが閉じたあと。**通報が成立した1本だけ**を並びから落とす
    /// （閉じただけなら何もしない）。中でブロックもしていれば画面ごと閉じる
    private func afterReport(_ story: Story) {
        if let userId = story.userId, hidden.blockedUserIds.contains(userId) {
            leaveGroup()
            return
        }
        guard hidden.reportedPhotoIds.contains(story.id) else { return }
        // **いま見ている1本を id で覚えてから外す**（`deleteStory` と同じ）。シートの
        // `onDismiss` は閉じる動きの後に走るので、その前に止めが解けて次の1本へ
        // 進んでいた回に、位置で詰めると1本飛ばしていた
        let viewingId = current?.id
        dropped.insert(story.id)
        onDropped?(story.id)
        let remaining = visible
        if remaining.isEmpty {
            leaveGroup()
            return
        } else if viewingId != story.id,
                  let stay = remaining.firstIndex(where: { $0.id == viewingId }) {
            index = stay
        } else {
            // 落とした位置に次の1本が詰まる。最後だったら1つ手前
            go(to: min(index, remaining.count - 1))
        }
        // **受け付けたことはここで伝える。** 通報シートのトーストは
        // 画面の外の知らせで、全画面の閲覧画面の上には出ない
        message = L("通報を受け付けました。ありがとうございます。", "Thanks — your report was received.")
    }

    // MARK: - 足元

    @ViewBuilder
    private func footer(for story: Story) -> some View {
        if isMine(story) {
            // **1行にまとめる**（owner が候補Bを選んだ・2026-09-29）。左に反応（顔と数・押すと
            // 反応の画面）、右に返信と「…」の丸。写真として残す・削除は「…」の中へ。
            // **高さは他の人のストーリーの返信欄と同じ**（上下 7 ＋ 46）——自分の投稿と
            // 人の投稿を行き来しても写真の枠が変わらない。以前は反応の札と丸の列の2段で
            // 足元が 134pt あり、写真が小さくなっていた
            HStack(spacing: 10) {
                // 期限が切れた投稿は見た人・返信の記録が無い（サーバーが期限で消す）
                if !isExpired(story) {
                    insightsButton
                    replyButton(for: story)
                } else {
                    Spacer(minLength: 0)
                }
                moreButton
            }
            .frame(height: 46)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        } else if story.acceptsReplies {
            // 返信欄（ガラスの丸）と ♡。**書いている間は ♡ が送信の白い丸に替わり、
            // 上に一言の候補と「だれに届くか」が出る**（板「25d 返信を書く」）
            VStack(alignment: .leading, spacing: 10) {
                if replyFocused {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(StoryPlayback.quickReplies.indices, id: \.self) { i in
                                let text = L(StoryPlayback.quickReplies[i], StoryPlayback.quickRepliesEnglish[i])
                                Button {
                                    Task { await sendReply(text, to: story) }
                                } label: {
                                    Text(text)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 36)
                                        .jpGlass(in: Capsule(), border: 0.14)
                                }
                                .buttonStyle(.plain)
                                .disabled(isSending)
                            }
                        }
                    }
                    Text(L("返信は \(story.authorName) さんにだけ届きます", "Only \(story.authorName) sees your reply"))
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.muted2)
                        .padding(.leading, 4)
                }
                HStack(spacing: 6) {
                    TextField(L("返信する", "Reply"), text: $reply)
                        // サーバーの上限（200）で止める——超えたぶんは黙って切られる
                        .onChange(of: reply) { old, value in
                            let kept = PostLimits.limited(old: old, new: value, limit: PostLimits.storyReply)
                            if kept != value { reply = kept }
                        }
                        .accessibilityLabel(L("\(story.authorName) さんに返信", "Reply to \(story.authorName)"))
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        // 打っている間は止める（打ち終わる前に次へ送られない）
                        .focused($replyFocused)
                        .submitLabel(.send)
                        // **空なら送らない**（送信キーは空でも押せる。空の本文は
                        // サーバーが 400 で断り、その間は再生も止まっていた）
                        .onSubmit { if canSend { Task { await sendReply(to: story) } } }
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .jpGlass(in: Capsule(), border: replyFocused ? 0.6 : 0.35)
                    if canSend || replyFocused {
                        Button {
                            Task { await sendReply(to: story) }
                        } label: {
                            Image(systemName: "paperplane")
                                .font(.system(size: 18))
                                .foregroundStyle(WebTheme.accentText)
                                .frame(width: 46, height: 46)
                                .background(WebTheme.accentBackground, in: Circle())
                        }
                        .disabled(isSending || !canSend)
                        .accessibilityLabel(Labels.Common.send)
                    } else {
                        // ♡ は定型の反応の ❤️ を送る（Web の ♡ と同じ `STORY_REACTIONS[0]`）
                        Button {
                            Task { await sendReaction(StoryService.reactions[0], to: story) }
                        } label: {
                            Image(systemName: "heart")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .webTappable()
                        }
                        .disabled(isSending)
                        .accessibilityLabel(L("いいね", "Like"))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        } else {
            // 返信を受けない投稿。**足元の場所は残す**（空にすると写真の枠が
            // 1本ごとに伸び縮みする）。**高さを決めて置く**——`Color.clear` は
            // 与えられた高さを全部取るので、決めないと写真と半分ずつ分け合う
            Color.clear.frame(height: Self.footerHeight)
        }
    }

    /// 送信の丸を出すか（送れるか）。**空白だけでない文字が入っているとき**
    private var canSend: Bool {
        !reply.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 出す返信の数。**文章の返信だけ**（反応は「いいね」に数える）。
    /// 一覧をまだ読めていなければサーバーの `replyCount`（反応も含む数）
    private func replyBadge(for story: Story) -> Int? {
        if repliesLoaded { return replies.textReplies.count }
        // 読めなかったときはサーバーの数（反応も含む）を残す。読み込み中は出さない
        return repliesFailed ? story.replyCount : nil
    }

    /// 「写真として残す」を出すか。動画とアーカイブの投稿は断られる
    nonisolated static func canKeepAsPhoto(_ story: Story) -> Bool {
        !story.isVideo && story.archive != true
    }

    /// 「返信 3」。数が分からないうちは「返信」だけ
    private func replyTitle(for story: Story) -> String {
        guard let n = replyBadge(for: story) else { return L("返信", "Replies") }
        return L("返信 \(n)", n == 1 ? "1 reply" : "\(n) replies")
    }

    /// 期限が切れた（ハイライト・アーカイブから開いた）。**見た人と返信の記録は
    /// サーバーが期限で消す**ので、「0 人が見ました」と言い切らない
    private func isExpired(_ story: Story) -> Bool {
        story.expiresAt != nil && StoryPlayback.remaining(until: story.expiresAt) == nil
    }

    /// 自分のストーリーの見出しの2行目（「2時間前 · あと 22 時間で消えます」）
    private func ownTimeLine(for story: Story) -> String? {
        let parts = [StoryPlayback.ago(from: story.createdAt),
                     StoryPlayback.remaining(until: story.expiresAt)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 見た人の顔を3つ重ねる（26pt・黒の縁・8pt ずつ重ねる）
    private var viewerFaces: some View {
        HStack(spacing: -8) {
            ForEach(Array(viewers.prefix(3))) { viewer in
                RemoteImage(url: UserProfile.profileAssetURL(userId: viewer.userId, suffix: nil, cacheBust: nil),
                            placeholderSymbol: "person.crop.circle.fill")
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }

    /// 反応（左）。顔と「見た人 N」、下に「いいね N」。押すと反応の画面。
    /// **読み込み中も場所を取る**——読み終えてから出すと、右の丸が押す直前にずれる。
    /// まだ誰も見ていないときは顔の代わりに目の印を置き、0 を並べない
    private var insightsButton: some View {
        Button {
            showInsights = true
        } label: {
            HStack(spacing: 10) {
                if viewersLoaded != true || viewers.isEmpty {
                    Image(systemName: "eye")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WebTheme.muted2)
                        .frame(width: 30, height: 30)
                        .background(WebTheme.raised, in: Circle())
                } else {
                    viewerFaces
                }
                VStack(alignment: .leading, spacing: 1) {
                    if viewersLoaded != true {
                        // 読み込み中・読めなかった。**数は言わない**（0 と言い切らない）
                        Text(L("反応を見る", "Insights"))
                            .font(.system(size: 14, weight: .medium))
                    } else if isQuiet {
                        Text(L("まだ誰も見ていません", "No views yet"))
                            .font(.system(size: 14, weight: .medium))
                    } else {
                        HStack(spacing: 0) {
                            Text(L("見た人 ", "Viewers "))
                            Text("\(viewers.count)").font(JPFont.mono(14, medium: true))
                        }
                        .font(.system(size: 14, weight: .medium))
                        // **返信を読めていなければ「いいね」の数は言わない**
                        // （読めなかった回に空の一覧から「いいね 0」と言い切っていた）
                        if repliesLoaded {
                            HStack(spacing: 0) {
                                Text(L("いいね ", "Likes "))
                                Text("\(replies.reactionCount)").font(JPFont.mono(12, medium: true))
                            }
                            // 本文系の最小は 12（デザインシステム「黒塗りの真鍮」02 書体）。
                            // **数は白のまま**——いいねは白、真鍮は合図と手がかりだけ（同 04）
                            .font(.system(size: 12))
                            .foregroundStyle(WebTheme.muted2)
                        }
                    }
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(insightsLabel)
        // 読み込み中・失敗は文そのものが「反応を見る」なので、同じ言葉を重ねない
        .accessibilityHint(viewersLoaded == true ? L("反応を見る", "Show insights") : "")
    }

    /// 誰も見ておらず、いいねも（読めた範囲で）無い
    private var isQuiet: Bool {
        viewers.isEmpty && (!repliesLoaded || replies.reactionCount == 0)
    }

    private var insightsLabel: String {
        // 画面に出している文と同じことを読む
        if viewersLoaded != true { return L("反応を見る", "Insights") }
        if isQuiet { return L("まだ誰も見ていません", "No views yet") }
        let seen = L("見た人 \(viewers.count)人", "\(viewers.count) viewers")
        guard repliesLoaded else { return seen }
        return seen + L("、いいね \(replies.reactionCount)", ", \(replies.reactionCount) likes")
    }

    /// 返信（届いた返信の一覧）。**丸い吹き出し**（`message`・メッセージの App と同じ形）。
    /// 以前の角の吹き出し（`bubble.left`）は安っぽく、封筒は四角いと言われた（owner・2026-09-29）
    private func replyButton(for story: Story) -> some View {
        Button {
            showReplies = true
        } label: {
            ownCircle(symbol: "message")
                .overlay(alignment: .topTrailing) {
                    if let badge = replyBadge(for: story), badge > 0 {
                        // **真鍮＝合図**（通知の未読の点と同じ）。黒の縁で丸から切り離す。
                        // 上の字は墨（真鍮に白は読めない・`BrandPalette.accentFill`）
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(JPFont.mono(10, medium: true))
                            .foregroundStyle(WebTheme.accentText)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(WebTheme.accent, in: Capsule())
                            .overlay(Capsule().strokeBorder(WebTheme.background, lineWidth: 2).padding(-2))
                            .offset(x: 4, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(replyTitle(for: story))
    }

    /// 「…」。写真として残す・削除をしまう（**削除の赤をふだん見せない**）。
    /// **標準の `Menu` は使わない**——開いているかを画面が知れず、開いている間も
    /// 再生が進んで次の1本へ移ってしまう。人の投稿の「…」と同じ下からのシート（止まる）
    private var moreButton: some View {
        Button {
            showMenu = true
        } label: {
            ownCircle(symbol: "ellipsis")
        }
        .buttonStyle(.plain)
        // 上の「…」と同じ名前（同じシートを開く）。残す・削除がこの奥にあることをヒントで言う
        .accessibilityLabel(L("その他の操作", "More actions"))
        .accessibilityHint(L("写真として残す・削除", "Keep as photo, delete"))
    }

    /// 操作の丸（写真の上の ✕ と同じガラス・他の人の送信の丸と同じ 46）
    private func ownCircle(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .jpGlass(in: Circle(), border: 0.14)
            .contentShape(Circle())
    }

    // MARK: - 返信の一覧（自分）

    /// 板「26b 返信（自分）」。**文章の返信だけ**を並べ、顔を押すとその人のページ
    private var repliesSheet: some View {
        let items = replies.textReplies
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if repliesFailed {
                        Text(Labels.Common.loadFailed)
                            .font(.subheadline)
                            .foregroundStyle(WebTheme.muted2)
                            .padding(.vertical, 16)
                    } else if items.isEmpty {
                        Text(L("まだ返信はありません", "No replies yet"))
                            .font(.subheadline)
                            .foregroundStyle(WebTheme.muted2)
                            .padding(.vertical, 16)
                    }
                    ForEach(items) { item in
                        replyRow(item)
                    }
                    Text(L("返信はあなたにだけ見えています。ストーリーが消えると、返信も一緒に消えます。",
                           "Only you can see replies. They disappear with the story."))
                        .font(.system(size: 12))
                        .lineSpacing(4)
                        .foregroundStyle(WebTheme.faint)
                        .padding(.vertical, 16)
                }
                .padding(.horizontal, 16)
            }
            .background(Self.repliesBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Text(L("返信", "Replies")).font(.system(size: 16, weight: .semibold))
                        Text("\(items.count)").font(JPFont.mono(16, medium: true))
                    }
                    .foregroundStyle(.white)
                }
            }
            .toolbarBackground(Self.repliesBackground, for: .navigationBar)
        }
        .presentationBackground(Self.repliesBackground)
        .presentationDragIndicator(.visible)
    }

    /// 返信のシートの地（板の `#0c0c0d`）
    private static let repliesBackground = Color(red: 0x0C / 255.0, green: 0x0C / 255.0, blue: 0x0D / 255.0)

    private func replyRow(_ item: StoryReply) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let uid = item.uid {
                NavigationLink {
                    UserProfileView(userId: uid)
                } label: {
                    RemoteImage(url: UserProfile.profileAssetURL(userId: uid, suffix: nil, cacheBust: nil),
                                placeholderSymbol: "person.crop.circle.fill")
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                }
                .accessibilityLabel(L("\(item.name ?? "") のプロフィール", "\(item.name ?? "")'s profile"))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.name ?? L("だれか", "Someone"))
                        .font(.system(size: 14, weight: .semibold))
                    if let ago = StoryPlayback.ago(from: item.t) {
                        Text(ago)
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.faint)
                    }
                }
                Text(item.body)
                    .font(.system(size: 14))
                    .lineSpacing(6)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    /// 投票スタンプに票を入れる。**入れたあとの数をすぐ見せる**（一覧の読み直しを待たない）
    private func sendVote(_ choice: String, to story: Story) async {
        guard !voting else { return }
        voting = true
        defer { voting = false }
        do {
            voteStates[story.id] = try await environment.stories.vote(id: story.id, choice: choice)
        } catch {
            // **いま出している1本のときだけ知らせる**（送っている間に移った先に出さない）
            guard visible.indices.contains(index), visible[index].id == story.id else { return }
            message = (error as? LocalizedError)?.errorDescription ?? L("投票できませんでした", "Couldn't vote")
        }
    }

    /// 定型の反応を送る。
    private func sendReaction(_ emoji: String, to story: Story) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await environment.stories.react(id: story.id, emoji: emoji)
            message = L("いいねを送りました", "Like sent")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("送れませんでした", "Couldn't send")
        }
    }

    private func sendReply(to story: Story) async {
        guard canSend else { return }
        await sendReply(reply, to: story, clearsDraft: true)
    }

    /// 返信を送る。候補の一言は**下書きを消さない**（書きかけの文を残す）
    private func sendReply(_ text: String, to story: Story, clearsDraft: Bool = false) async {
        guard !isSending, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await environment.stories.reply(id: story.id, text: text)
            if clearsDraft { reply = "" }
            replyFocused = false
            message = L("送りました", "Sent")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("送れませんでした", "Couldn't send")
        }
    }

    /// 残している間も止める（Web の `keeping`）。終わる前に次へ送られると
    /// 「残しました」が別の1本の画面に出る
    private func keep(_ story: Story) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await environment.stories.keep(id: story.id)
            message = L("自分の写真として残しました", "Kept as a photo")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("残せませんでした", "Couldn't keep it")
        }
    }

    private func deleteStory(_ story: Story) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await environment.stories.delete(id: story.id)
            onDeleted?(story.id)
            // 🔴 **残りがあれば閉じない。** 以前は1本消すと画面ごと閉じ、3本のうち
            // 1本を消しただけで残りの2本が見られなくなった。通報で落としたときと
            // 同じく並びから外し、次の1本へ詰める（一覧は閉じたときに読み直す）
            //
            // **いま見ている1本を id で覚えてから外す**（位置で詰めると、消している間に
            // 前後へ送っていた回に1本飛ばしたり、同じ1本の見た人・返信を空にしたりする）
            let viewingId = current?.id
            dropped.insert(story.id)
            onDropped?(story.id)
            let remaining = visible
            if remaining.isEmpty {
                leaveGroup()
            } else if viewingId != story.id,
                      let stay = remaining.firstIndex(where: { $0.id == viewingId }) {
                // 別の1本を見ている: その1本のまま、位置だけ直す（状態は空にしない）
                index = stay
                message = L("削除しました", "Deleted")
            } else {
                go(to: min(index, remaining.count - 1))
                message = L("削除しました", "Deleted")
            }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }
}
