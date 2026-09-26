import SwiftUI

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
    /// 通報して落とした1本。**兄弟の並びから消す**（左タップで戻れないように）
    @State private var dropped: Set<String> = []

    // 進行
    @State private var elapsed: TimeInterval = 0
    @State private var pressing = false
    @State private var paused = false
    @State private var muted = false
    @State private var captionHidden = false
    /// 絵が出た（動画は出どころが無いので最初から true）
    @State private var mediaReady: Bool

    // メニューと確認
    @State private var showMenu = false
    @State private var showReport = false
    @State private var showBlockConfirm = false
    /// 見出しの名前を押して開く投稿者のページ
    @State private var showAuthor = false

    // 返信と反応
    @State private var reply = ""
    @FocusState private var replyFocused: Bool
    @State private var message: String?
    @State private var viewers: [StoryViewer] = []
    @State private var showInsights = false
    @State private var showViewers = false
    @State private var replies: [StoryReply] = []
    @State private var showReplies = false
    /// 返信を読めなかった。**空の一覧と区別する**（数は出ているのに
    /// 何も無い画面は「消えた」に見える）
    @State private var repliesFailed = false
    /// 送っている最中。**二度押しで2件送らない**。自動送りも止める
    @State private var isSending = false

    /// 見終えた1本を知らせる。**送るたびに呼ぶ**——次へ送ったぶんも
    /// 既読にしないと、閉じたときに輪が点いたまま残る
    let onSeen: ((String) -> Void)?

    init(stories: [Story], startIndex: Int, viewerId: String?,
         onSeen: ((String) -> Void)? = nil) {
        self.stories = stories
        self.viewerId = viewerId
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
            sheetOpen: showReplies || showInsights || showViewers || showReport || showBlockConfirm
                || showAuthor,
            replyFocused: replyFocused,
            isSending: isSending,
            mediaReady: mediaReady,
            // 前面に居ない間は止める（動画も止まり、戻ると続きから）
            inBackground: !isForeground
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let story = current {
                content(for: story)
            }
        }
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
            VStack(spacing: 0) {
                photoArea(for: story)
                    .ignoresSafeArea(edges: .top)
                footer(for: story)
                    .frame(minHeight: Self.footerHeight)
            }
            VStack(spacing: 9) {
                progressBar(for: story)
                header(for: story)
            }
            .padding(.top, 5)
        }
        .task(id: story.id) {
            // 端末の既読（輪の色）。**サーバーの応答を待たない**
            // ——圏外でも、見たものは見たことにする
            onSeen?(story.id)
            // **見たことを伝えるのは1回。** 失敗しても画面は止めない
            await environment.stories.markViewed(id: story.id)
            if isMine(story) {
                viewers = (try? await environment.stories.viewers(id: story.id)) ?? []
                // **返信は本人だけが読める。** 読めないと、送られた返信が
                // どこにも出ない（送る側の画面だけあった）
                do {
                    replies = try await environment.stories.replies(id: story.id)
                    repliesFailed = false
                } catch {
                    repliesFailed = true
                }
            }
        }
        // 時計は読み込みと別に回す。同じ task に入れると、見た人の一覧を
        // 待っている間、写真が出ているのに秒数が始まらない
        .task(id: story.id) { await runClock(for: story) }
        .onAppear { isForeground = scenePhase == .active }
        .onChange(of: scenePhase) { _, phase in isForeground = phase == .active }
        .confirmationDialog(L("ストーリーの操作", "Story options"), isPresented: $showMenu,
                            titleVisibility: .hidden) {
            menuButtons(for: story)
        }
        .alert(L("この人をブロックしますか？", "Block this person?"), isPresented: $showBlockConfirm) {
            Button(L("ブロック", "Block"), role: .destructive) {
                Task { await block(story) }
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("おたがいの投稿・ストーリー・通知が見えなくなります。設定からいつでも解除できます。", "You won't see each other's posts, stories or notifications. You can undo this in Settings."))
        }
        .sheet(isPresented: $showReport, onDismiss: { afterReport(story) }) {
            // **写真の通報と同じ口。** サーバーの `report.ts` は id で行を引き、
            // ストーリー行（`story-<uuid>`）も `src` を持つので通る
            ReportSheet(photoId: story.id, ownerId: story.userId)
        }
        .sheet(isPresented: $showReplies) {
            NavigationStack {
                List {
                    if repliesFailed {
                        Text(Labels.Common.loadFailed).foregroundStyle(.secondary)
                    } else if replies.isEmpty {
                        Text(L("まだ返信はありません", "No replies yet")).foregroundStyle(.secondary)
                    }
                    ForEach(replies) { reply in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reply.name ?? L("だれか", "Someone"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(reply.body)
                        }
                    }
                }
                .navigationTitle(L("返信 \(replies.count)", "\(replies.count) replies"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                }
            }
        }
        .sheet(isPresented: $showAuthor) {
            if let userId = story.userId {
                NavigationStack {
                    UserProfileView(userId: userId)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                        }
                }
            }
        }
        .sheet(isPresented: $showInsights) {
            NavigationStack {
                StoryInsightsView(story: story)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                    }
            }
        }
        .sheet(isPresented: $showViewers) {
            NavigationStack {
                List(viewers) { viewer in
                    Text(viewer.name)
                        .foregroundStyle(WebTheme.foreground)
                        .listRowBackground(Color.clear)
                }
                .webScreen()
                .navigationTitle(L("見た人 \(viewers.count)", "\(viewers.count) viewers"))
                .navigationBarTitleDisplayMode(.inline)
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
                isMuted: muted,
                isPaused: frozen,
                onEnded: { advance() },
                // 出せないと分かった回も進める——止めたままだと永久に固まる
                // （Web の `!mediaReady && !mediaError` と同じ）
                onSettled: { _ in mediaReady = true }
            )
            // 🔴 **1本ごとに作り直す。** 同じ型・同じ場所のままだと SwiftUI は
            // 部品を使い回し、動画の再生器（`StoryVideo` の `@State`）が前の1本の
            // まま残る——動画が2本続くと、2本目は1本目の終わりの絵で止まり、
            // 鳴り終わりの合図も来ないので先へ進めなかった
            .id(story.id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // 上と下の暗がり（白い文字を写真の明るさに負けさせない。板は上180・下200）
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.black.opacity(0.65), Color.black.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                Spacer(minLength: 0)
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
            }
            .allowsHitTesting(false)

            tapZones

            captionBlock(for: story)
                .padding(.horizontal, 32)
                .padding(.bottom, 96)
                .allowsHitTesting(false)

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
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    /// ひとこと（明朝30・影）・撮影地・曲。**写真の左下に重ねる**（板の配置）。
    /// 撮影地は以前は見出しの2行目にあった
    @ViewBuilder
    private func captionBlock(for story: Story) -> some View {
        let caption = captionHidden ? nil : story.caption.flatMap { $0.isEmpty ? nil : $0 }
        let place = story.location.flatMap { $0.isEmpty ? nil : $0 }
        let song = story.songLine
        if caption != nil || place != nil || song != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let caption {
                    Text(caption)
                        .font(JPFont.display(30, relativeTo: .largeTitle))
                        .lineSpacing(6)
                        .foregroundStyle(.white)
                        .jpPhotoTextShadow()
                }
                if let place {
                    photoMeta(symbol: "mappin", text: place)
                }
                if let song {
                    photoMeta(symbol: "music.note", text: song)
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
    private func progressBar(for story: Story) -> some View {
        let fills = StoryPlayback.segmentFills(
            count: visible.count,
            current: index,
            elapsed: elapsed,
            duration: StoryPlayback.duration(seconds: story.durationSec),
            isVideo: story.isVideo
        )
        return HStack(spacing: 4) {
            ForEach(fills.indices, id: \.self) { i in
                segment(fill: fills[i], isCurrent: i == index)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 10)
        .accessibilityLabel(L("\(visible.count)本中\(index + 1)本目", "\(index + 1) of \(visible.count)"))
    }

    private func segment(fill: Double?, isCurrent: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(isCurrent && fill == nil ? 0.6 : 0.3))
                if let fill {
                    Capsule().fill(Color.white)
                        .frame(width: geo.size.width * fill)
                        // **刻みの間を線でつなぐ。** 時計は `clockStep` ごとにしか
                        // 進まないので、そのままでは1秒に20回の段差で伸びる
                        // （owner「進行バーが滑らかになってない」2026-09-25）。
                        // 0 へ戻るとき（次の1本・前へ戻る）はつながず、すぐ戻す
                        .animation(fill > 0 ? Animation.linear(duration: Self.clockStep) : nil, value: fill)
                }
            }
        }
    }

    // MARK: - 見出し

    /// アバター34・名前14・経過時間12を1行に。右に「…」と ✕（地なし・44）。
    /// 名前を押すと投稿者のページ（板のリンク）
    private func header(for story: Story) -> some View {
        HStack(spacing: 10) {
            Button {
                showAuthor = true
            } label: {
                HStack(spacing: 10) {
                    if let userId = story.userId {
                        RemoteImage(url: UserProfile.profileAssetURL(userId: userId, suffix: nil, cacheBust: nil),
                                    placeholderSymbol: "person.crop.circle.fill")
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                    }
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
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(story.userId == nil)
            Spacer(minLength: 0)
            Button {
                showMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .webTappable()
                    .accessibilityLabel(L("その他の操作", "More actions"))
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

    // MARK: - 指の操作

    /// 左半分は前へ（始まってすぐ）か最初から、右半分は次へ。
    /// **押している間は止まる**（離すと再開）。
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { leftTap() }
                .onLongPressGesture(minimumDuration: 0.35, perform: {}, onPressingChanged: { pressing = $0 })
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { advance() }
                .onLongPressGesture(minimumDuration: 0.35, perform: {}, onPressingChanged: { pressing = $0 })
        }
        // **払っても動く。** 他のアプリのストーリーは全部そうなので、
        // タップしか効かないと「反応しない」と受け取られる。
        // 行き先はタップと同じに寄せた（`StoryPlayback.swipe`）——同じ画面で
        // 「押すと進む」と「払うと別の動き」が並ぶと、人が覚えられない
        .simultaneousGesture(
            DragGesture(minimumDistance: StoryPlayback.swipeThreshold)
                .onEnded { value in
                    switch StoryPlayback.swipe(
                        dx: value.translation.width, dy: value.translation.height) {
                    case .next: advance()
                    case .back: leftTap()
                    case .close: dismiss()
                    case .ignore: break
                    }
                }
        )
    }

    private func leftTap() {
        switch StoryPlayback.leftTap(index: index, elapsed: elapsed) {
        case .restart:
            elapsed = 0
        case .previous(let target):
            go(to: target)
        }
    }

    /// 次へ。**最後なら閉じる**
    private func advance() {
        if let target = StoryPlayback.next(after: index, count: visible.count) {
            go(to: target)
        } else {
            dismiss()
        }
    }

    /// 別の1本へ移る。**前の1本の状態を持ち越さない**——返信の下書き・
    /// 「送りました」・見た人・返信の一覧が別のストーリーの画面に出ないように
    private func go(to target: Int) {
        guard visible.indices.contains(target) else { return }
        index = target
        elapsed = 0
        mediaReady = visible[target].isVideo
        captionHidden = false
        reply = ""
        message = nil
        viewers = []
        replies = []
        repliesFailed = false
    }

    /// 時計の刻み。進行バーの動きもこの長さで次の刻みへつなぐ
    private static let clockStep: TimeInterval = 0.05

    /// 写真の時計。**動画は回さない**（鳴り終わりが送る）。
    /// 経過は実際の時刻の差で進める——`sleep` は指定より遅れることがある。
    /// **差は `StoryPlayback.tickDelta` で抑える**（アプリが止まっていた時間を足さない）
    private func runClock(for story: Story) async {
        guard !story.isVideo else { return }
        let duration = StoryPlayback.duration(seconds: story.durationSec)
        while !Task.isCancelled {
            let before = Date()
            try? await Task.sleep(for: .milliseconds(Int(Self.clockStep * 1000)))
            if Task.isCancelled { return }
            let dt = StoryPlayback.tickDelta(Date().timeIntervalSince(before))
            var progress = StoryPlayback.Progress(elapsed: elapsed, duration: duration)
            let tick = progress.tick(dt, frozen: frozen)
            elapsed = progress.elapsed
            if tick == .advance {
                advance()
                return
            }
        }
    }

    // MARK: - 「…」のメニュー

    /// 出す項目は `StoryPlayback.menuItems` が決める（押しても何も起きない
    /// 項目は出さない）。
    @ViewBuilder
    private func menuButtons(for story: Story) -> some View {
        let items = StoryPlayback.menuItems(
            isMine: isMine(story),
            isVideo: story.isVideo,
            hasCaption: story.caption?.isEmpty == false,
            hasOwner: story.userId != nil
        )
        if items.contains(.pause) {
            Button(paused ? L("再開", "Resume") : L("一時停止", "Pause")) { paused.toggle() }
        }
        if items.contains(.mute) {
            Button(muted ? L("ミュート解除", "Unmute") : L("ミュート", "Mute")) { muted.toggle() }
        }
        if items.contains(.hideCaption) {
            Button(captionHidden ? L("テキストを表示", "Show text") : L("テキストを非表示", "Hide text")) {
                captionHidden.toggle()
            }
        }
        if items.contains(.block) {
            // 「非表示」とは書かない。サーバーにあるのは両向きのブロックだけで、
            // 片向きに隠す口は無い（相手からも見えなくなる）
            Button(L("この人をブロック", "Block this person"), role: .destructive) { showBlockConfirm = true }
        }
        if items.contains(.report) {
            Button(L("ストーリーを報告", "Report story")) { showReport = true }
        }
    }

    /// ブロックの手順は `UserProfileViewModel.block` と同じ
    /// （サーバー → 端末の控え → 公開一覧 → toast）。兄弟は全部同じ投稿者
    /// なので、成功したら画面ごと閉じる
    private func block(_ story: Story) async {
        guard let userId = story.userId else { return }
        do {
            try await environment.moderation.block(userId: userId)
            hidden.block(userId)
            await environment.gallery.setHidden(
                userIds: hidden.blockedUserIds,
                photoIds: hidden.reportedPhotoIds
            )
            toasts.show(L("ブロックしました。設定から解除できます。",
                          "Blocked. You can undo this in Settings."))
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }

    /// 通報のシートが閉じたあと。**通報が成立した1本だけ**を並びから落とす
    /// （閉じただけなら何もしない）。中でブロックもしていれば画面ごと閉じる
    private func afterReport(_ story: Story) {
        if let userId = story.userId, hidden.blockedUserIds.contains(userId) {
            dismiss()
            return
        }
        guard hidden.reportedPhotoIds.contains(story.id) else { return }
        dropped.insert(story.id)
        let remaining = visible
        if remaining.isEmpty {
            dismiss()
        } else {
            // 落とした位置に次の1本が詰まる。最後だったら1つ手前
            go(to: min(index, remaining.count - 1))
        }
    }

    // MARK: - 足元

    @ViewBuilder
    private func footer(for story: Story) -> some View {
        if isMine(story) {
            HStack(spacing: 16) {
                // **反応はまとめて1画面に**（提案の絵）。見た人・いいね・返信が
                // 別々のシートに割れていると、全体がどうだったか分からない
                Button(L("反応を見る", "Insights")) { showInsights = true }
                Button(L("返信 \(replyBadge(for: story))", "\(replyBadge(for: story)) replies")) { showReplies = true }
                // 24時間で消える前に、自分の写真として残す
                Button(L("残す", "Keep")) { Task { await keep(story) } }
                    .disabled(isSending)
                Button(Labels.Common.delete, role: .destructive) { Task { await deleteStory(story) } }
                    .disabled(isSending)
            }
            .font(.footnote)
            .padding(16)
        } else {
            // 返信欄（ガラスの丸）と ♡。**打ち始めたら ♡ が送信の白い丸に替わる**
            HStack(spacing: 6) {
                TextField(L("返信する", "Reply"), text: $reply)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    // 打っている間は止める（打ち終わる前に次へ送られない）
                    .focused($replyFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await sendReply(to: story) } }
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .jpGlass(in: Capsule(), border: replyFocused ? 0.6 : 0.35)
                if canSend {
                    Button {
                        Task { await sendReply(to: story) }
                    } label: {
                        Image(systemName: "paperplane")
                            .font(.system(size: 18))
                            .foregroundStyle(WebTheme.accentText)
                            .frame(width: 46, height: 46)
                            .background(WebTheme.accentBackground, in: Circle())
                    }
                    .disabled(isSending)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }

    /// 送信の丸を出すか。**打っている間か、文字が入っているとき**
    private var canSend: Bool {
        !reply.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 出す返信の数。一覧を読めていればその数、まだなら `replyCount`。
    private func replyBadge(for story: Story) -> Int { max(replies.count, story.replyCount ?? 0) }

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
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await environment.stories.reply(id: story.id, text: reply)
            reply = ""
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
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }
}
