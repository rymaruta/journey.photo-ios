import SwiftUI

/// ホームの写真の並び（板 01c）。
///
/// **大きく1枚 → 2枚 → 2枚 の繰り返し**（`EditorialLayout` と同じリズム）を、
/// 端から端まで・隙間 4pt・角なしで組む。撮影地と撮った人は写真の上に重ね、
/// いいねは右下の黒い丸で押せる。
///
/// 以前は縦1列の札（作者・写真・題・説明・タグ・4つの操作）だった
/// （提案の絵・2026-09-21）。owner の「ホームをアーティファクト通りに・
/// 主に写真の表示部分」（2026-09-26）で板 01c の組みにした。
/// 題・説明・保存・共有・フォローは写真の詳細にある。**通報とブロックは
/// 各写真の「…」にも残す**（審査 1.2・審査メモの「各写真の『…』から」）
struct HomeMosaic: View {

    let groups: [PhotoGroups.Group]
    /// 「通報する」を押したとき。**シートは一覧（`GalleryView`）が出す。**
    /// 写真に付けると、通報で一覧が読み直されて写真ごと消え、
    /// 「受け付けました」やブロック失敗の文言を見る前にシートが閉じる
    var onReport: (Photo) -> Void = { _ in }
    /// 並びの最後の段に置くもの（「新着」の続きを読む目印・#426）。**この遅れて作る並びの中に置く**——画面に
    /// 入ったときだけ作られるので、目印の `onAppear` が下まで送ったときだけ走る
    var footer: AnyView? = nil

    /// 段どうし・段の中の隙間（板: 4px）
    private let gap: CGFloat = JPSpace.xxs

    /// **v2（2026-10-14・Main の板）: 写真は端 8 まで広げ、角 14 で丸める。**
    /// 板の付箋「フィードの1枚目は端 8 まで広げ」。ほかの中身（札・タブ）は端 16 なので、
    /// 写真だけが一段外へ出て主役に見える。1枚目だけ 8 にすると2段目から端が揃わないので、
    /// 並び全体を 8 にした（2026-10-14 判断）
    nonisolated static let edge: CGFloat = JPSpace.xs
    /// 写真の角（v2 の radius-m・写真の札）
    nonisolated static let corner: CGFloat = JPRadius.m

    var body: some View {
        let _ = PerfRecorder.shared.hit("home.mosaic.body")   // 起動直後の停止の切り分け（UI テストのときだけ・2026-11-07）
        let byCover = Dictionary(groups.map { ($0.cover.id, $0) }, uniquingKeysWith: { first, _ in first })
        LazyVStack(spacing: gap) {
            ForEach(EditorialLayout.rows(groups.map(\.cover))) { row in
                switch row {
                case .hero(let photo):
                    tile(photo, byCover: byCover, large: true)
                case .pair(let first, let second):
                    if let second {
                        HStack(spacing: gap) {
                            tile(first, byCover: byCover, large: false)
                            tile(second, byCover: byCover, large: false)
                        }
                    } else {
                        // **相方が無い段は1枚で横いっぱい**（半分だけ写真がある段を作らない）
                        tile(first, byCover: byCover, large: true)
                    }
                }
            }
            if let footer { footer }
        }
        // 長押しで運べることの、はじめての1回だけの案内（1枚目の写真の上に重ねる・並びの高さは変えない）
        .overlay(alignment: .top) {
            if !groups.isEmpty { PhotoLiftIntro().padding(.top, JPSpace.s) }
        }
        .padding(.horizontal, Self.edge)
    }

    @ViewBuilder
    private func tile(_ photo: Photo, byCover: [String: PhotoGroups.Group], large: Bool) -> some View {
        let group = byCover[photo.id]
        HomeFeedTile(photo: photo, siblings: group?.photos ?? [photo], large: large, onReport: onReport)
    }
}

/// ホームの1枚（板 01c）。写真・撮影地と撮った人の重ね・右下のいいね・複数枚の印
struct HomeFeedTile: View {

    let photo: Photo
    /// 同じ投稿の写真（`photo` を含む）。2枚以上なら右上に印
    var siblings: [Photo] = []
    /// 大きい段（16:9・撮影地 22pt・投稿した時期も出す）か、2枚の段（1:1・18pt）か
    var large = false
    var onReport: (Photo) -> Void = { _ in }

    /// **札そのものが見る store はログインだけ**（「…」を出すか・2026-10-28 判断・重さの直し）。
    /// いいね（`FavoritesStore`・`LikeCountStore`）とブロック（`ModerationStore`）は、それを使う小さな部品
    /// （`HomeTileLikeButton`・`HomeTileMoreMenu`）だけが見る。以前は札が全部を見ていたので、どこかで
    /// ♥を1つ押すたびに、ホームに並ぶ札が全部描き直されていた
    @EnvironmentObject private var auth: AuthStore
    /// この札の写真を手に取っている（2026-11-12 札 #543・`PhotoLift`）。**手に取っている間は開く押しを止める**
    /// （離したときに詳細が開かない）。指の位置は店（`PhotoLiftCenter`）へ書く——札は店を見張らない
    /// （指が動くたびにホームの札が全部描き直されないように）
    ///
    /// **身振りが続いている間だけ真になる（`@GestureState`）。** 着信・通知センター・裏に回る・一覧の読み直しで
    /// 身振りが取り消されると `onEnded` は来ないが、これは必ず戻る（2026-11-12 確かめ役: `@State` だと手に取ったまま
    /// 幕が残り、全体が押せなくなっていた）。戻ったときに店へ知らせる（`PhotoLiftCenter.gestureReset`）
    @GestureState private var lifted = false
    /// 押さえている最中（手に取る前）。この間だけ札の画面の座標を読む（ふだんは読まない・送るたびに走らせない）
    @GestureState private var pressing = false
    /// 札の画面の座標（指を動かさずに手に取ったときの位置）
    @State private var globalFrame: CGRect = .zero

    var body: some View {
        let _ = PerfRecorder.shared.hit("home.tile.body")
        ZStack(alignment: .bottomTrailing) {
            NavigationLink {
                PhotoDetailView(photo: photo, context: siblings.isEmpty ? [photo] : siblings)
            } label: {
                Color.clear
                    .aspectRatio(large ? 16.0 / 9.0 : 1, contentMode: .fit)
                    .overlay {
                        if large {
                            // 2026-10-21 判断: 大きい枠は**枠の大きさ×画面の倍率まで縮めて**読む（`DownsampledRemoteImage`）。
                            // `RemoteImage`（`AsyncImage`）は 1920px の元を縮めずに展開し、ホームを流すと段ごとに
                            // 約 11MB を抱えた。敷き方は `.fill` で、写真の縦横比から「枠を覆う大きさ」を出すので、
                            // 縦長の写真でもぼやけない（縦横比が無い写真は上限で読む）
                            DownsampledRemoteImage(url: photo.detailImageURL, contentMode: .fill,
                                                   aspectRatio: photo.aspectRatio.map { CGFloat($0) },
                                                   alignment: photo.gridAlignment)
                        } else {
                            DownsampledRemoteImage(url: photo.gridImageURL, contentMode: .fill,
                                                   aspectRatio: photo.aspectRatio.map { CGFloat($0) },
                                                   alignment: photo.gridAlignment,
                                                   appearAnimation: .easeOut(duration: 0.15))
                        }
                    }
                    .overlay(alignment: .bottomLeading) { caption }
                    .overlay(alignment: .topTrailing) {
                        // 「…」の丸と重ならないよう、印はその左
                        multipleMark.padding(.trailing, showsMore ? 44 : 0)
                    }
                    // v2: 角 14（`HomeMosaic.corner`）。下の暗がりも同じ角で切る
                    .clipShape(RoundedRectangle(cornerRadius: HomeMosaic.corner))
                    .contentShape(RoundedRectangle(cornerRadius: HomeMosaic.corner))
            }
            .buttonStyle(.plain)
            // 絵の上の文字（撮影地・撮った人・複数枚の印）も読む。題だけにすると、
            // 題のある写真では**画面に出ている撮影地と名前が読まれない**
            .accessibilityLabel(HomeTileText.readout(
                base: photo.accessibilityText,
                place: HomeTileText.place(photo.location),
                byline: byline,
                multiple: siblings.count > 1 ? L("複数枚の投稿", "Multiple photos") : nil))
            // **実機の絵の道しるべ。** 「一覧の1枚目」を位置で探すと、
            // 今日のテーマの「参加する」に当たって**ログイン画面を
            // 『写真の詳細』として撮って**いた（run 49 の絵で判明）
            .accessibilityIdentifier("feed.photo")
            // 手に取って運ぶ（読み上げの道）: 写真の操作の一覧に「とっておく・送る・ストーリーで紹介」
            .accessibilityAction(named: L("保存", "Save")) { liftByAction(.save) }
            .accessibilityAction(named: L("送る", "Send")) { liftByAction(nil) }
            // ストーリーで紹介は自分の写真だけ（2026-11-12 判断・`PhotoLift.allowsStory`）
            .modifier(HomeTileStoryAction(enabled: PhotoLift.allowsStory(ownerId: ownerId, me: auth.userId)) {
                liftByAction(.story)
            })
            .disabled(lifted)

            HomeTileLikeButton(photo: photo)
        }
        .overlay(alignment: .topTrailing) {
            if showsMore { HomeTileMoreMenu(photo: photo, ownerId: ownerId, onReport: onReport) }
        }
        .scaleEffect(lifted ? 0.96 : 1)
        .opacity(lifted ? 0.4 : 1)
        // 札の画面の座標は**押さえている間だけ**読む（2026-11-12 確かめ役: 全部の札で送るたびに読んでいた）
        .background {
            if pressing || lifted {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { globalFrame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, frame in globalFrame = frame }
                }
                .accessibilityHidden(true)
            }
        }
        // 身振りが終わった（離した・取り消された）。離したときは `onEnded` が先に店を進めているので何も起きない。
        // 取り消されたときだけ、手に取ったままの写真を戻す。札が一覧から消えたときも同じ
        .onChange(of: lifted) { _, now in
            guard !now else { return }
            // 次の回しで見る（離したときの `onEnded` が先に済んでいるように）
            let id = photo.id
            Task { @MainActor in PhotoLiftCenter.shared.gestureReset(photoId: id) }
        }
        .onDisappear { PhotoLiftCenter.shared.gestureReset(photoId: photo.id) }
        // 0.35秒押さえて手に取る（10pt 以上動いたらスクロール）。短く押せば今どおり開く。
        // ログインしていなければ手に取らない（保存・送る・ストーリーはログインが要る）
        // `-JPPreviewNoLift`（UI テストの事実取りだけ・Debug のみ）では身振りを付けない。
        // 1.1.84 は使わない（`PhotoLift.homeGestureEnabled`・ホームの払いを奪っていた）
        .simultaneousGesture(liftGesture, including: !PhotoLift.homeGestureEnabled || auth.userId == nil || PreviewSession.noLift
                                 ? .subviews : .all)
        .sensoryFeedback(.impact(weight: .medium), trigger: lifted) { _, new in new }
    }

    private var liftGesture: some Gesture {
        LongPressGesture(minimumDuration: PhotoLift.pressSeconds, maximumDistance: PhotoLift.moveTolerance)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($pressing) { value, state, _ in
                if case .first(true) = value { state = true }
            }
            .updating($lifted) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                let center = PhotoLiftCenter.shared
                if center.photo?.id != photo.id {
                    if let drag {
                        center.lift(photo, at: drag.location)
                    } else {
                        center.lift(photo, at: CGPoint(x: globalFrame.midX, y: globalFrame.midY), fingerKnown: false)
                    }
                }
                if let drag { center.move(to: drag.location) }
            }
            .onEnded { _ in
                let center = PhotoLiftCenter.shared
                guard center.photo?.id == photo.id else { return }
                center.end()
            }
    }

    /// 読み上げの操作から（指を使わない道）。行き先を直に選ぶ（送るは顔の段を開く）
    private func liftByAction(_ target: PhotoLift.Target?) {
        guard auth.userId != nil else { return }
        let center = PhotoLiftCenter.shared
        switch target {
        case nil:
            center.openFaces(for: photo)
        case let target?:
            center.choose(photo, target: target)
        }
    }

    /// **`userId` が無く `uploadedBy` だけの写真もある**（詳細の `ownerId` と同じ読み方）。
    /// `userId` だけを見ると、自分の写真に通報が出て、他人の写真でブロックが出なかった
    private var ownerId: String? { photo.userId ?? photo.uploadedBy }

    /// 自分の写真には出さない（編集は詳細で）
    private var showsMore: Bool { ownerId == nil || ownerId != auth.userId }

    private var byline: String {
        HomeTileText.byline(author: AuthorName.shown(profile: nil, photoDisplayName: photo.displayName),
                            ago: large ? StoryPlayback.ago(from: photo.createdAt) : nil)
    }

    /// 撮影地と撮った人（板: 明朝の撮影地、その下に 11pt。本文系の最小に合わせて 12pt）。**撮影地が無い写真は
    /// 文字を重ねず、下を薄く暗くするだけ**（いいねの丸を読ませるため）
    @ViewBuilder
    private var caption: some View {
        let place = HomeTileText.place(photo.location)
        if !place.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                // 写真の上は白だけ（CLAUDE.md）。明朝は字の段の 22（大きい段）と 18（2枚の段・明朝の下限）
                Text(place)
                    .font(large ? JPFont.cardTitle : JPFont.rowTitle)
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 1)
                    .lineLimit(1)
                // 写真の上の副文は透過の白（不透明の灰は明るい写真の上で沈む・`WebTheme.muted2` の注記）
                Text(byline)
                    .font(large ? JPFont.footnote : JPFont.caption)
                    .foregroundStyle(WebTheme.muted)
                    .lineLimit(1)
            }
            // いいねの丸と重ならないよう右を空ける
            .padding(.leading, JPSpace.m)
            .padding(.trailing, 70)
            .padding(.bottom, JPSpace.m)
            .padding(.top, JPSpace.emptyTop)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(stops: [
                    .init(color: Color.black.opacity(0), location: 0),
                    .init(color: Color.black.opacity(0.78), location: 0.6),
                    .init(color: Color.black.opacity(0.78), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .allowsHitTesting(false)
        } else {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 56)
                .allowsHitTesting(false)
        }
    }

    /// 複数枚の印（板: 右上の重なった四角）
    @ViewBuilder
    private var multipleMark: some View {
        if siblings.count > 1 {
            Image(systemName: "square.on.square")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.5), radius: 3)
                .padding(8)
                .accessibilityLabel(L("複数枚の投稿", "Multiple photos"))
        }
    }

}

/// ホームの札の「…」（通報・ブロック）。中身は写真詳細の「…」と同じ。見た目はいいねと
/// 同じ黒い丸（32pt）で、押せる範囲は 44pt。
///
/// **ブロックの store を見るのはこの部品だけ**（2026-10-28 判断・重さの直し）。札（`HomeFeedTile`）が見ると、
/// ブロックの帳が替わるたびにホームの札が全部描き直される
struct HomeTileMoreMenu: View {
    let photo: Photo
    let ownerId: String?
    var onReport: (Photo) -> Void = { _ in }

    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var environment: AppEnvironment
    /// 「…」のブロックの確認
    @State private var showBlockConfirm = false

    var body: some View {
        Menu {
            Button { onReport(photo) } label: {
                Label(L("通報する", "Report"), systemImage: "flag")
            }
            if ownerId != nil {
                Button(role: .destructive) { showBlockConfirm = true } label: {
                    Label(L("この人をブロック", "Block this person"), systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                // 2026-10-28 判断（重さの直し・owner 承認）: ガラス（`.ultraThinMaterial`）は外し、黒 55% の丸だけ。
                // 札ごとに背後の写真をぼかす層が1枚ずつ要り、流す時の重さの元になる。理由は `HomeTileLikeButton` と同じ
                .background(Color.black.opacity(0.55), in: Circle())
                .padding(6)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L("この写真の操作", "More actions"))
        // 確認は4か所で同じ部品（`blockConfirmation`・2026-10-11）
        .blockConfirmation(isPresented: $showBlockConfirm) { Task { await block() } }
    }

    private func block() async {
        guard let ownerId else { return }
        // 押した人。次の人の画面に「ブロックしました」「ブロックできませんでした」を出さない
        let sender = hidden.owner
        do {
            try await hidden.blockAndHide(ownerId, environment: environment)
            guard sender != nil, hidden.owner == sender else { return }
            toasts.show(L("ブロックしました", "Blocked"))
        } catch {
            guard sender != nil, hidden.owner == sender else { return }
            toasts.show((error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block"),
                        kind: .failure)
        }
    }
}

/// ホームの札のいいね（右下の黒い丸）。
///
/// **いいねの store（`FavoritesStore`・`LikeCountStore`）を見るのはこの部品だけ**（2026-10-28 判断・重さの直し）。
/// 札が見ていたころは、どこかで♥を1つ押す・数が1つ届くたびに、ホームに並ぶ札が全部（写真の読み直しの判定ごと）
/// 描き直されていた。いまは押した札の丸だけが描き直される
struct HomeTileLikeButton: View {
    let photo: Photo

    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var toasts: ToastCenter
    /// サーバーが答えたいいねの数（詳細画面で押したぶんもここに来る）
    @EnvironmentObject private var likeCounts: LikeCountStore
    @EnvironmentObject private var environment: AppEnvironment
    /// 未ログインで押した♥の「ログインする」とログイン画面（`SignInPrompt`・2026-10-11）
    @State private var signInAsk: SignInRequest?
    @State private var signInOpen: SignInRequest?

    var body: some View {
        likeButton
            .signInPrompt(ask: $signInAsk, open: $signInOpen)
    }

    /// いいね（板: 右下の丸・32pt・等幅の数。ぼかしは外した・2026-10-28）
    private var likeButton: some View {
        Button {
            Task { await toggleLike() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(likeCount)")
                    .font(JPFont.mono(12))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 32)
            // 2026-10-28 判断（重さの直し・owner 承認）: 板はガラスの丸（黒 55% ＋ぼかし）だが、ぼかし
            // （`.ultraThinMaterial`）は外した。ホームの札1枚に丸が2つ（いいね・「…」）あり、それぞれ背後の写真を
            // 毎コマぼかし直すので、流す時の重さの元になる。黒 55% の地はそのまま——写真の上の白い字は同じ地で読める
            .background(Color.black.opacity(0.55), in: Capsule())
            // **押せる範囲は丸の外まで広げる**（見た目は 32pt のまま、押せる高さは
            // 44pt）。丸の縁の少し上を押すと、背後の写真が拾って詳細が開いていた
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("いいね \(likeCount)", "Like, \(likeCount)"))
        // 色で分けないので、押したかどうかは形と読み上げで伝える
        .accessibilityAddTraits(liked ? .isSelected : [])
    }

    private var liked: Bool { favorites.contains(photo.id) }

    /// いいね。**サーバーへ送る。**
    ///
    /// 🔴 ここは長いあいだ端末の控えを反転するだけで、**押しても
    /// サーバーには一度も届いていなかった**（詳細画面を開くと
    /// 押していない状態に戻る）。控えは送れたときだけ合わせる。
    private func toggleLike() async {
        // **答えを待っている間は押させない。** 二度目が古い `liked` を見て
        // 逆向きに飛ぶと、ハートと数が押した結果と食い違う（詳細画面も
        // 同じ `LikeCountStore` の印で止める）
        // 待っている印はカードの外（`LikeCountStore`）に持つ——カードが作り直されても消えない
        // **ログインしていなければ送らずに「ログインする」を出す。** 送ると認証で断られて
        // 黙って戻り、一瞬灯って消えるだけのボタンになっていた（詳細画面も同じ扱い）。
        // 🔴 2026-10-11: 以前は3秒の知らせだけで、ログインする手段が無かった（`SignInPrompt`）
        switch HomeLikeGate.decide(auth) {
        case .send: break
        case .ignore: return
        case .askToSignIn:
            signInAsk = SignInPrompt.request(SignInPrompt.like, userId: auth.userId, isResolving: auth.isResolving)
            return
        }
        let photoId = photo.id
        guard pendingDelta == 0, likeCounts.beginSending(photoId) else { return }
        let wasLiked = liked
        // 答えは押した人の控えにだけ書く（待っている間に人が替わったら書かない）
        let owner = favorites.owner
        // 先に画面を変える（押した手応えを待たせない）
        favorites.set(photo.id, favorite: !wasLiked)
        pendingDelta = wasLiked ? -1 : 1
        defer {
            pendingDelta = 0
            likeCounts.endSending(photoId)
        }
        // 答えの書き方・届かなかったときの戻し方と一言は `HomeLikeGate.send`
        let social = environment.social
        await HomeLikeGate.send(photoId, wasLiked: wasLiked, owner: owner,
                                favorites: favorites, likeCounts: likeCounts, toasts: toasts) {
            wasLiked ? try await social.unlike(photoId: photoId) : try await social.like(photoId: photoId)
        }
    }

    /// 押して答えを待っている間だけの ±1。**答えが来たら 0 に戻す**
    @State private var pendingDelta = 0

    /// 出すいいねの数。
    ///
    /// 土台は、押した答え（`LikeCountStore`・ここで押した回も詳細で押した回も
    /// 入る）と一覧の数（いまの数に差し替え済み）の**新しい方**。
    /// 待っている間だけ ±1 を足す。
    ///
    /// 🔴 以前は「端末でいいね済みなら一覧の数に +1」だった。一覧の数には
    /// **自分のいいねが既に入っている**ので、押したことのある写真は
    /// いつも1つ多く出ていた（しかも一覧の数はサイトを建てた時点の古い数）。
    private var likeCount: Int {
        LiveLikes.displayCount(base: LiveLikes.base(for: photo, stored: likeCounts.entry(for: photo.id)),
                               pendingDelta: pendingDelta)
    }

}

/// ホームの1枚に重ねる文字（画面を持たない計算だけ）
enum HomeTileText {

    /// 撮影地の短い名前（板: 「金沢」）。**最初の区切りまで**
    /// （「パリ, フランス」→「パリ」）。無ければ空
    static func place(_ location: String?) -> String {
        let trimmed = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let head = trimmed.split(whereSeparator: { ",、，".contains($0) }).first.map(String.init) ?? trimmed
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 読み上げ（題 → 撮影地 → 撮った人 → 複数枚）。題が無い写真は
    /// `base` が既に撮影地を含む（「パリ, フランス の写真」）ので二度読まない
    static func readout(base: String, place: String, byline: String, multiple: String?) -> String {
        var parts = [base]
        if !place.isEmpty, !base.contains(place) { parts.append(place) }
        if !byline.isEmpty { parts.append(byline) }
        if let multiple, !multiple.isEmpty { parts.append(multiple) }
        return parts.joined(separator: ", ")
    }

    /// 撮影地の下の1行（板: 「名前 · 2日前」、2枚の段は名前だけ）
    static func byline(author: String, ago: String?) -> String {
        guard let ago, !ago.isEmpty else { return author }
        return "\(author)\u{2002}\(ago)"
    }
}

/// ホームのカードの♥を押したときに、送るか・黙るか・ログインを促すか。
enum HomeLikeGate {
    enum Decision: Equatable { case send, ignore, askToSignIn }

    /// **送るのはログイン済み（ID がある）ときだけ。** 黙るのは起動直後の確認中だけ
    /// ——確認中に促すと、ログイン済みの人にも出る。
    ///
    /// ID が取れなかった起動（`isSignedOutUncertain`）も**促す**。ほかのタブはログイン画面を
    /// 出し、詳細画面も同じ言葉で断る。黙らせると、その起動のあいだ♥が何も言わずに
    /// 効かなくなる（`RootView` の「ログインしていない回は黙らない」と同じ）。
    /// ID が無いまま送ると、ログアウトの表示のまま前の人のトークンでいいねが付くか、
    /// 一瞬灯って消える
    static func decide(userId: String?, isResolving: Bool) -> Decision {
        if userId != nil { return .send }
        return isResolving ? .ignore : .askToSignIn
    }

    /// 画面から呼ぶ形。**式を呼び出し側に置かない**（試験がそこを通らない）
    @MainActor
    static func decide(_ auth: AuthStore) -> Decision {
        decide(userId: auth.userId, isResolving: auth.isResolving)
    }

    /// 送って、答えを控えに書く（ホームのカードのハート）。
    ///
    /// - **返ってきた数と状態を使う。** 自分で数えない。
    ///   **数を返さない答え（見えなくなった写真の 404 を読み替えた回）は数を書かない。**
    ///   押している間の ±1 を含んだ数を「押した答え」として控えに残すと、
    ///   詳細・検索にも作った数が広がる（詳細の下のハートと同じ扱い）
    /// - **届かなかったら戻す。** 画面だけ「いいね済み」にしない
    /// - 🔴 **届かなかったと言う**（バグ探し 2026-10-03）。以前は戻すだけで、先に灯した
    ///   ハートが黙って消え、押せなかったのか押し損ねたのか分からなかった。
    ///   大きく見る画面と同じ一言（`ViewerLike.failureNotice`）を出す
    /// - `owner`: 押した人。答えはその人の控えにだけ書く（待っている間に人が替わったら書かない）
    @MainActor
    static func send(_ photoId: String, wasLiked: Bool, owner: String?,
                     favorites: FavoritesStore, likeCounts: LikeCountStore, toasts: ToastCenter,
                     request: () async throws -> SocialService.LikeResult) async {
        do {
            let result = try await request()
            // 数の無い答えでも答えた時刻は残す（詳細の♥の勝ち負けに使う。`LikeCountStore.recordAnswer`）
            likeCounts.recordAnswer(photoId, count: result.likes)
            favorites.set(photoId, favorite: result.liked, for: owner)
        } catch {
            favorites.set(photoId, favorite: wasLiked, for: owner)
            toasts.show(ViewerLike.failureNotice(error), kind: .failure)
        }
    }
}

/// 読み上げの操作「ストーリーで紹介」。**自分の写真のときだけ**付ける（2026-11-12 判断・他人の写真を作者名なしで
/// 自分のストーリーに出さない。owner の判断待ち）
private struct HomeTileStoryAction: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: L("ストーリーで紹介", "Share to story"), action)
        } else {
            content
        }
    }
}

/// 長押しで運べることの案内（2026-11-12 確かめ役「気づけるように」）。**はじめての1回だけ**・5秒で消える・押しても消える。
/// 写真の上なのでガラスに白（真鍮は黒地の上だけ・CLAUDE.md）。形はストーリーの作る画面の一度だけの案内と同じ丸い帯
private struct PhotoLiftIntro: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        Group {
            if visible {
                Button { hide() } label: {
                    HStack(spacing: JPSpace.xs) {
                        Image(systemName: "hand.point.up.left")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                        Text(PhotoLift.introText)
                            .font(.footnote.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(WebTheme.foreground)
                    .padding(.horizontal, 14)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .jpGlass(in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("押すとこの案内を閉じます", "Dismisses this tip"))
                .accessibilityIdentifier("home.liftIntro")
                .transition(.opacity)
            }
        }
        .onAppear {
            let defaults = UserDefaults.standard
            guard PhotoLift.homeGestureEnabled, PhotoLift.showsIntro(signedIn: auth.userId != nil,
                                       alreadyShown: defaults.bool(forKey: PhotoLift.introKey)) else { return }
            defaults.set(true, forKey: PhotoLift.introKey)
            visible = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(PhotoLift.introSeconds * 1_000_000_000))
                hide()
            }
        }
    }

    private func hide() {
        guard visible else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { visible = false }
    }
}
