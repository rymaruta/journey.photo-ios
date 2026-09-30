import SwiftUI

struct PhotoDetailView: View {

    let photo: Photo
    /// 公開の一覧から開いたか。**個別ページが在るかの判断に使う**
    /// ——投稿直後の写真はまだページが無い（`PhotoLink`）
    var fromPublicFeed: Bool = true
    /// 同じ一覧に並んでいた写真。大きく見るときに左右へ送るのに使う
    var context: [Photo] = []

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoritesStore
    /// サーバーが答えたいいねの数。**ここで読んだ・押した数をホームにも出す**
    @EnvironmentObject private var likeCounts: LikeCountStore
    @EnvironmentObject private var savedPhotos: SavedPhotosStore
    @EnvironmentObject private var hidden: ModerationStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PhotoDetailViewModel
    /// 保存（しおり）を送っている最中
    @State private var isSavingBookmark = false
    @State private var showReport = false
    /// 通報シートを開いたときに、持ち主をもうブロックしていたか（閉じたときの後始末を分ける）
    @State private var ownerBlockedWhenReporting = false
    @State private var showDeleteConfirm = false
    @State private var showEdit = false
    @State private var showViewer = false
    @State private var actionError: String?
    /// 編集して保存したあとの姿。**`photo` は `let` で書き換えられない**
    /// ——編集シートを閉じても題も説明も古いままだった（保存はできていた
    /// ので、戻って入り直すまで「保存されていない」ように見えた）
    /// 写真ごとに持つ（束の別の1枚に、前の1枚の編集後の姿を出さない）
    @State private var edits: [String: Photo] = [:]
    /// **いま上に出ている1枚。** 束を左右に送ると替わる。
    ///
    /// 🔴 以前は開いた1枚（`photo`）のままで、2枚目へ送っても題・いいね・
    /// 削除・通報は1枚目が対象だった（「2/3枚」と出ているのに）
    @State private var current: Photo
    /// 「この近くで撮られた写真」（板 02）。座標の無い写真では空のまま
    @State private var nearby: [Photo] = []
    /// 「この場所のスポット」の行き先。**台帳にも写真にも辿り着けたときだけ入る**
    @State private var spotLead: SpotLead?
    /// フォローしているか。**分からない間は nil**——ボタンを出さない
    /// （取れなかった回に「フォロー」と出すと、フォロー中の人に二重に送る）
    @State private var isFollowing: Bool?
    /// フォロー一覧を**取りに行って失敗した**。このときはボタンを「フォロー」の姿で
    /// 出し、押されたら先に取り直してから判断する（`toggleFollow`）。
    /// 失敗を nil のまま放置すると、ボタンが二度と出なかった
    @State private var followLookupFailed = false
    /// 成功の知らせ（ブロックしました など）。**失敗の赤字（`actionError`）と分ける**
    @State private var actionNotice: String?
    /// 削除を確かめているコメント（押してすぐ消さない）
    @State private var commentPendingDelete: PhotoComment?
    @State private var isFollowWorking = false
    @State private var showUnfollowConfirm = false
    /// 大きく見る画面で、**この画面の1枚以外**のいいねを送っている写真。
    /// 写真ごとに持って再入を止める——ダブルタップの直後にハートを押すと、
    /// 2本目が1本目の答えの前に逆向きを送り、画面とサーバーが食い違う
    /// （この画面の1枚は `PhotoDetailViewModel.isLiking` が止めている）
    @State private var viewerLikesInFlight: Set<String> = []
    /// この画面が出ているか・裏にいる間にブロック／通報があったか（`hidden.revision`）
    @State private var isOnScreen = false
    @State private var needsRefilter = false
    /// コメントから落とす「見せない」の写し。**画面に出ている間だけ取り直す**
    /// ——コメントした人のページでブロックすると、描くたびに絞っていた元の行
    /// （`NavigationLink`）が消え、そのページが閉じていた
    @State private var dropped = ModerationSnapshot()

    /// スポット詳細に渡すもの一式。**撮影地から導いた地点**と、
    /// 突き合わせる公開写真（近くの地点もここから出す）
    private struct SpotLead {
        let spot: DerivedSpot.Place
        let photos: [Photo]
    }

    /// 画面に描く1枚。編集していれば新しい方。
    private var shown: Photo { edits[current.id] ?? current }
    /// コメント・いいねを受け付けるか（下書きは受け付けない・`PhotoDetailRules.acceptsReactions`）
    private var acceptsReactions: Bool { PhotoDetailRules.acceptsReactions(published: shown.published) }

    init(photo: Photo, fromPublicFeed: Bool = true, context: [Photo] = []) {
        self.photo = photo
        self.fromPublicFeed = fromPublicFeed
        self.context = context
        _current = State(initialValue: photo)
        // `AppEnvironment` は init で受け取れない（EnvironmentObject は body 以降）
        _model = StateObject(wrappedValue: PhotoDetailViewModel(
            photoId: photo.id,
            social: SocialService(api: APIClient(tokenProvider: CognitoTokenProvider())),
            initialLikes: photo.likes
        ))
    }

    /// 大きく見るときに送れる並び。**渡されていなければこの1枚だけ**
    /// ——「送れるはずなのに送れない」より、送りが出ない方がまし。
    var siblings: [Photo] { context.isEmpty ? [photo] : context }

    private var ownerId: String? { current.userId ?? current.uploadedBy }
    private var isMine: Bool { ownerId != nil && ownerId == auth.userId }

    /// コメントの節の目印。吹き出しを押したらここまで送る
    private static let commentsAnchor = "photo.comments"
    /// 写真の高さ（板 02 の 460pt）と、本文がその上に重なる深さ（板の 94pt）
    private static let heroHeight: CGFloat = 460
    private static let heroOverlap: CGFloat = 94
    /// コメントの「削除」の当たりを字の上下にはみ出させる幅（44pt − 12pt の字の高さ ≒ 28 の半分）
    private static let commentDeleteTapSlack: CGFloat = 14
    /// コメントした人の名前（`.caption` の太字・約 16pt）の当たりを上へはみ出させる幅。
    /// **下は本文との間（2pt）まで**——下へ広げると本文の1行目にかぶる。
    /// 上はひとつ前のコメントとの間（12 ＋ 2 ＋ 2）と、その本文の下の方にかかるが、
    /// 本文は押せないので奪うものは無い
    private static let commentNameTapSlackTop: CGFloat = 26
    private static let commentNameTapSlackBottom: CGFloat = 2
    /// カテゴリの札（`.caption` ＋ 上下 4 ≒ 24pt）の当たりを札の上下にはみ出させる幅
    /// （44 − 24 の半分）。上下の段との間は 16 あるので、隣の当たりに届かない
    private static let chipTapSlack: CGFloat = 10

    // **段ごとに割ってある。** 一本の長い `ScrollView { … }` にすると、Swift の
    // 型検査が現実的な時間で終わらなくなることがある
    // （"unable to type-check this expression in reasonable time"）。
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            imageButton
                            details(proxy)
                                // **題は写真の下の方に重ねる**（板 02: 写真 460pt の 366pt から）。
                                // 写真の裾は黒へ溶かしてあるので、白い字が沈まない
                                .padding(.top, -Self.heroOverlap)
                        }
                        .padding(.bottom, 32)
                    }
                    // **写真を画面の上端から敷く**（板 02）。戻る・「…」は上のバーに
                    // 残したまま、バーの地を消して写真の上に浮かせる
                    .ignoresSafeArea(edges: .top)
                }
                // **時計とバーの裏に黒のぼかし**（人のページ・マイページと同じ
                // `TopBarScrim`。流れずに上端に留まる）。バーの地を消しているので、
                // 敷かないと明るい写真の上で白い戻る「‹」・時計が沈み、下へ送ると
                // 本文が戻る・「…」・時計の真下を流れて重なる
                TopBarScrim(topInset: geo.safeAreaInsets.top)
            }
        }
        // **入力欄は画面の下に貼る**（モック6）。コメント欄が本文の
        // 途中にあると、長い説明の写真では入力欄まで辿り着く前に
        // 書く気が失せる。`safeAreaInset` はスクロールの底の余白も
        // 足してくれるので、最後のコメントが入力欄の下に隠れない
        .safeAreaInset(edge: .bottom) { composer }
        .navigationBarTitleDisplayMode(.inline)
        // **上のバーの地を消す**（板 02: 戻る・「…」は写真の上のガラスの丸）。
        //
        // 自前の丸ボタンに差し替えて上のバーごと隠す手もあるが、それをすると
        // **左端から払って戻る操作が効かなくなる**（SwiftUI の既知の挙動）。
        // 戻るは標準のボタンのまま——iOS 26 ではそれ自体がガラスの丸で出る
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { menu } }
        // **送った先の1枚でも読み直す**（鍵に今の1枚を入れる）
        .task(id: PhotoDetailRules.reloadKey(userId: auth.userId, photoId: current.id, published: shown.published)) {
            model.setSignedIn(auth.userId != nil)
            // 前の1枚の「ブロックしました」・保存の失敗を持ち越さない
            actionNotice = nil
            actionError = nil
            // **数はホームのカードと同じ出どころ**（`LiveLikes.base`）。一覧の数
            // （`current.likes`）のままだと、ホームで押した直後に開くと古い数が出た
            let stored = likeCounts.entry(for: current.id)
            model.show(photoId: current.id,
                       initialLikes: LiveLikes.base(for: current, stored: stored),
                       liked: favorites.contains(current.id),
                       answeredAt: stored?.at)
            await model.load()
        }
        .task(id: shown.location) { await loadSpotLead() }
        .task(id: shown.id) { await loadNearby() }
        // **ブロック・通報で絞り直す**（`hidden.revision`）。この画面で
        // その場でブロック／通報しても、近くの写真とスポットの行き先が
        // 古い一覧のまま残っていた。
        //
        // **通信はしない。** 手元の並びから落とすだけ——ブロック・通報は
        // 減らす向きにしか効かない。以前は鍵に `revision` を入れていて、
        // 押すたびに公開一覧を2本（通報＋ブロックで4本）取り直していた
        //
        // 🔴 **画面に出ている間だけ絞る。** 近くの写真から開いた先でブロックすると、
        // 裏にいるこの画面の `nearby` からその1枚が消え、押した元の
        // `NavigationLink` ごと開いている詳細が閉じていた（「ブロックしました」も
        // 見えない）。裏にいる間は印だけ付けて、戻ってきたときに絞る
        .onChange(of: hidden.revision) { _, _ in
            if isOnScreen {
                dropped = hidden.snapshot
                refilterHidden()
            } else {
                needsRefilter = true
            }
        }
        .onAppear {
            isOnScreen = true
            dropped = hidden.snapshot
            if needsRefilter {
                needsRefilter = false
                refilterHidden()
            }
        }
        .onDisappear { isOnScreen = false }
        // **ブロック中かどうかも鍵に入れる。** 解除して戻ったとき、ブロックで「分からない」に
        // 倒したフォローの状態を取り直す（入れないと、開き直すまでボタンが戻らない）
        .task(id: "\(ownerId ?? "")|\(auth.userId ?? "")|\(ownerId.map(hidden.blockedUserIds.contains) ?? false)") {
            await model.loadOwner(ownerId, profiles: environment.profiles)
            // **フォローしているかは、その人を見に行かずに知りたい。**
            // 自分のフォロー一覧から引く（相手のページを開かずに済む）
            followLookupFailed = false
            guard let me = auth.userId, let ownerId, me != ownerId else {
                isFollowing = false
                return
            }
            // 人が替わった・入り直した回は、答えが来るまで「分からない」
            isFollowing = nil
            // **取れなかった回は書かない。** 圏外で「フォロー」に戻すと、
            // フォロー中の人を押して二重に送る（`FollowListView` と同じ扱い）
            let ids = try? await environment.social.myFollowingIds()
            guard !Task.isCancelled else { return }
            guard let ids else {
                // 押されたら取り直す（`toggleFollow`）。ボタンが出る経路を残す
                followLookupFailed = true
                return
            }
            isFollowing = ids.contains(ownerId)
        }
        // **通報シートで「ブロックもする」を選んだ回は、`block()` と同じ後始末をする。**
        // シートは閉じるだけで、前の失敗の赤字と、ブロックした相手のフォローの状態が残っていた
        // **このシートでブロックした回だけ**（開く前からブロックしていた回に、閉じるたびに
        // 「ブロックしました」やいいねの失敗を消さない）
        .sheet(isPresented: $showReport, onDismiss: {
            guard let ownerId, !ownerBlockedWhenReporting,
                  hidden.blockedUserIds.contains(ownerId) else { return }
            clearNotices()
            isFollowing = nil
            followLookupFailed = false
        }) {
            ReportSheet(photoId: current.id, ownerId: ownerId)
        }
        // **閉じたら引き直す。** 保存はできているのに画面が古いままだと、
        // 保存できていないように見える
        .sheet(isPresented: $showEdit, onDismiss: { Task { await reloadPhoto() } }) {
            NavigationStack { EditPhotoView(photo: shown) }
        }
        .fullScreenCover(isPresented: $showViewer) {
            // **ブロック・通報した写真を落とした並びで開く**（`PhotoDetailRules.viewerLineup`）。
            // 編集して保存した写真は新しい姿で（題・撮影地が古いまま出ていた）
            let lineup = PhotoDetailRules.viewerLineup(siblings, current: shown,
                                                       hiding: dropped, edits: edits)
            PhotoViewerView(
                photos: lineup.photos,
                index: lineup.index,
                // **写真ごとに答える。** この画面の1枚は画面が持つ値、
                // 隣の写真は端末の控え（ホームのハートと同じ出どころ）
                isLiked: { shown in shown.id == current.id ? model.liked : favorites.contains(shown.id) },
                isSignedIn: auth.userId != nil,
                // 下書きにはハートを出さない（押すと灯ってから黙って消え、断りは画面の裏に出ていた）
                acceptsLike: { PhotoDetailRules.acceptsReactions(published: $0.published) },
                onDoubleTapLike: { shown in Task { await likeFromViewer(shown) } },
                onToggleLike: { shown in Task { await toggleLikeFromViewer(shown) } },
                shareURL: { shown in shareURL(for: shown) }
            )
        }
        .alert(L("この写真を削除しますか？", "Delete this photo?"), isPresented: $showDeleteConfirm) {
            Button(Labels.Common.delete, role: .destructive) { Task { await deletePhoto() } }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("元に戻せません。画像そのものも消えます。", "This cannot be undone. The image file is deleted too."))
        }
        // コメントの削除は確かめてから（押し間違いで他人の書き込みを消さない）
        //
        // **`presenting:` で押した時点の1件を受け取る。** 閉じるときの
        // `set(false)` が `commentPendingDelete` を先に nil にするので、
        // ボタンの中でそれを読むと消えないことがあった
        .alert(L("このコメントを削除しますか？", "Delete this comment?"),
               isPresented: Binding(get: { commentPendingDelete != nil },
                                    set: { if !$0 { commentPendingDelete = nil } }),
               presenting: commentPendingDelete) { comment in
            Button(Labels.Common.delete, role: .destructive) {
                Task { clearNotices(); await model.deleteComment(comment) }
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: { comment in
            Text(L("\(comment.name)さんのコメントを削除します。元に戻せません。",
                   "Deletes the comment by \(comment.name). This cannot be undone."))
        }
    }

    /// 押すと大きく見る（隣の写真へも送れる）。
    ///
    /// **板 02: 幅いっぱい・高さ 460pt で切り抜き、裾を黒へ溶かす。**
    /// 切り抜く中心は持ち主が選んだ位置（`gridAlignment`）。写真の全体は
    /// 押して大きく見る画面（板 14）で見られる。
    ///
    /// **同じ投稿が2枚以上なら、ここで左右に送れる**（モック6-1）。
    /// 何枚目かは題の下の1行（「1/3枚」）が言うので、写真の上には数も点も置かない。
    /// 束は `groupId` が作る——行は1枚ずつのままなので、個別ページは変わらない
    @ViewBuilder
    private var imageButton: some View {
        let group = heroGroup
        ZStack(alignment: .bottom) {
            if group.count > 1 {
                TabView(selection: heroPage) {
                    ForEach(Array(group.enumerated()), id: \.element.id) { index, item in
                        // 編集して保存した1枚は新しい姿で（切り抜きの中心など）
                        heroImage(edits[item.id] ?? item).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                heroImage(shown)
            }
            // 裾を黒へ（板: 下 140pt・`linear-gradient(to top, #000, transparent)`）
            LinearGradient(colors: [Color.black.opacity(0), WebTheme.background],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.heroHeight)
        .clipped()
    }

    private func heroImage(_ item: Photo) -> some View {
        Button {
            showViewer = true
        } label: {
            // 🔴 **写真は重ね（overlay）に置く。** 引き伸ばした写真（fill）を直に
            // `.frame(maxWidth: .infinity)` で包むと、横長の写真では包みの幅が
            // 写真の幅（画面より広い）になり、`.clipped()` は見た目を切るだけなので
            // 下の本文まで画面より広く組まれていた（説明・撮影情報・操作の列が
            // 右端で切れる。実機の絵で見つかった）。重ねは親の幅を変えない
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.heroHeight)
                .overlay {
                    RemoteImage(url: item.detailImageURL, alignment: item.gridAlignment)
                }
                .clipped()
                .contentShape(Rectangle())
                .accessibilityLabel(item.accessibilityText)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("拡大して見る", "Opens the photo full screen"))
    }

    /// 同じ投稿の束（1枚だけならこの1枚）。**大きく見る画面と同じく、ブロック・通報した
    /// 写真を落とす**（`PhotoDetailRules.heroGroup`・今の1枚は残す）
    private var heroGroup: [Photo] {
        PhotoDetailRules.heroGroup(siblings, current: shown, hiding: dropped, edits: edits).photos
    }

    /// 同じ投稿の中で、いま見ている1枚（モック6-1 の送り）。
    ///
    /// 🔴 **束の何枚目かは `current` から引く。** 別に番号を持つと、束から写真が
    /// 落ちたとき（ブロック・通報）に番号だけ古い並びのまま残り、上に出る写真と
    /// 題・いいね・削除の対象が食い違う。送ったら `current` をその1枚にする
    private var heroPage: Binding<Int> {
        Binding(
            get: { PhotoDetailRules.heroGroup(siblings, current: shown, hiding: dropped, edits: edits).index },
            set: { page in
                let group = heroGroup
                guard group.indices.contains(page) else { return }
                current = group[page]
            }
        )
    }

    /// 題の下の1行（板 02: 「2026.09.12 · 17:42 · 1/3枚」）
    private var headline: String? {
        let group = heroGroup
        return PhotoMetaLine.headline(date: shown.date,
                                      exifDateTime: shown.exif?.dateTimeOriginal,
                                      position: heroPage.wrappedValue + 1, of: group.count)
    }

    /// **板 02 の順。** 実装にだけある要素（公開範囲の印・カテゴリ・説明・曲・
    /// コメント一覧）は消さずに、読む流れの近いところへ差し込む。
    ///
    ///     撮影スポットの行（撮影地）          ← 題の上
    ///     題（明朝）
    ///     2026.09.12 · 17:42 · 1/3枚
    ///     ［公開範囲の印・カテゴリ］ 説明     ← 題の近く
    ///     作者 ＋ フォロー
    ///     いいね・コメント・保存・共有
    ///     撮影情報（開け閉め）
    ///     #タグ
    ///     曲
    ///     この近くで撮られた写真 ／ 地図で見る
    ///     コメント（N）                      ← 下
    private func details(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // **`Group` で束ねる。** `VStack` の中身は10個までで、
            // 印を足したところで溢れた（`extra argument in call`）
            Group {
                heading
                chips
                paragraphs
                authorRow
            }
            socialBar(proxy)
            Group {
                if let exif = shown.exif {
                    ExifRow(exif: exif)
                }
                if let tags = shown.tags, !tags.isEmpty {
                    TagRow(tags: tags)
                }
                if let song = shown.song {
                    SongRow(song: song)
                }
            }
            nearbySection
            commentsBlock
                .id(Self.commentsAnchor)
        }
        .padding(.horizontal, 20)
    }

    /// 題のかたまり（板 02）: 撮影スポットの行 → 題 → 日時と枚数。
    /// 写真の裾に重なるので、字に影を付ける（板の `text-shadow`）
    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            placeRow
            if !shown.displayTitle.isEmpty {
                // **題は写真の次に来る主役。** 明朝 32pt（板 02・文字サイズの設定で伸びる）。
                // 行送りは書体の自然値（1.45em）で足りるので、足さない
                Text(shown.displayTitle)
                    .font(JPFont.photoTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .jpPhotoTextShadow()
            }
            if let headline {
                Text(headline)
                    .font(JPFont.mono(12))
                    .foregroundStyle(WebTheme.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「フォロワーのみ」「親しい友達」の印。
    ///
    /// **出さないと、絞ったつもりが伝わらない。** 投稿した本人が
    /// 「ちゃんと絞れているか」を確かめられる場所がここしか無い。
    /// 知らない値のときは `RestrictedFeed.badge` がぼかす（広げない）。
    @ViewBuilder
    private var audienceBadge: some View {
        if let text = RestrictedFeed.badge(shown) {
            Label(text, systemImage: "lock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WebTheme.muted2)
                .webChip(prominent: true)
        }
    }

    /// 公開範囲の印とカテゴリ（板には無い・実装にだけある要素）。
    /// 題の下に小さく1列で。どちらも無ければ何も描かない
    @ViewBuilder
    private var chips: some View {
        let category = shown.category.map { Labels.Category.name($0) } ?? ""
        if RestrictedFeed.badge(shown) != nil || !category.isEmpty {
            HStack(spacing: 8) {
                audienceBadge
                if !category.isEmpty {
                    NavigationLink {
                        TagPhotosView(kind: .category(shown.category ?? ""))
                    } label: {
                        // 札の見た目はそのまま、当たりだけ 44pt（札の外に広げて負の余白で詰める）
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(WebTheme.muted2)
                            .webChip(prominent: true)
                            // 外へ広げてから同じだけ詰める——並びの高さは札のまま。
                            // 文字を大きくして札が伸びても、詰めすぎて上下に重ならない
                            .padding(.vertical, Self.chipTapSlack)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, -Self.chipTapSlack)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 題の上の「📍 撮影地 · 撮影スポットの詳細」（板 02）。
    ///
    /// **行き先は2通り。** 撮影地が `DerivedSpot.openable`（2枚以上）なら
    /// 撮影スポットの詳細（`SpotDetailView`）、そうでなければその撮影地の
    /// 写真の一覧（`TagPhotosView`）。以前は別々の2行だった。
    ///
    /// 「撮影スポットの詳細」の添え書きは**スポットへ行けるときだけ**。
    /// 行の文字は写真の撮影地——台帳の名前と綴りが違っても、題の上には
    /// 持ち主が書いた地名を出す（行き先の見出しが台帳の名前を出す）
    @ViewBuilder
    private var placeRow: some View {
        if let location = shown.location?.trimmingCharacters(in: .whitespaces), !location.isEmpty {
            if let lead = spotLead {
                NavigationLink {
                    SpotDetailView(spot: lead.spot, photos: lead.photos)
                } label: {
                    placeLabel(location, spotSuffix: true)
                }
                .buttonStyle(.plain)
                // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
                // ——今日それで「写真の詳細」としてログイン画面を撮っていた
                .accessibilityIdentifier("photo.spotLink")
            } else {
                NavigationLink {
                    TagPhotosView(kind: .location(location))
                } label: {
                    placeLabel(location, spotSuffix: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("photo.placeLink")
            }
        }
    }

    /// 板: 12pt・白・下線（白 60%）、添え書きは白 50%。写真の裾に乗るので影を付ける。
    /// **添え書きは白 72% に上げてある**——50% だと明るい写真の裾で読めなかった
    /// （影を付けても足りない）。本文の2次の字（`muted2`）と同じ濃さ
    private func placeLabel(_ location: String, spotSuffix: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin")
                .font(.caption)
            Text(location)
                .underline(true, color: Color.white.opacity(0.6))
                .lineLimit(1)
            if spotSuffix {
                Text(PhotoMetaLine.separator + L("撮影スポットの詳細", "Photo spot details"))
                    .foregroundStyle(WebTheme.muted2)
                    .lineLimit(1)
            }
        }
        // 板 02: 12px（`.caption`）
        .font(.caption)
        .foregroundStyle(WebTheme.foreground)
        .jpPhotoTextShadow()
        .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 説明。Web は `text-white/80` に `leading-relaxed`、段落の間は `mt-3`
    private var paragraphs: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(shown.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.callout)
                    .lineSpacing(4)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 作者（モック6-2）。アバター・名前・@ユーザー名・フォロー。
    ///
    /// **@ユーザー名は取れたときだけ。** 写真の行は表示名しか持っていない
    /// ので、投稿者の公開プロフィールを1回だけ引く。取れなければ名前だけ
    /// ——「@」だけの行を作らない。
    ///
    /// 認証の印は名前の横に出す（`VerifiedBadge`・名前 13 に合わせる。付けるのは運営だけ）。
    @ViewBuilder
    private var authorRow: some View {
        if let ownerId {
            HStack(spacing: 10) {
                NavigationLink {
                    UserProfileView(userId: ownerId)
                } label: {
                    HStack(spacing: 10) {
                        RemoteImage(url: UserProfile.profileAssetURL(
                            userId: ownerId, suffix: nil, cacheBust: nil),
                                    placeholderSymbol: "person.crop.circle.fill")
                            // 板 02: 34pt（押せる高さは行の 44pt）
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(AuthorName.shown(profile: model.owner, photoDisplayName: shown.displayName))
                                    // 板 02: 13px の太字
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(WebTheme.foreground)
                                    .lineLimit(1)
                                VerifiedBadge(isVerified: model.owner?.verified,
                                              nameSize: 13, relativeTo: .footnote)
                            }
                            if let username = model.owner?.username, !username.isEmpty {
                                Text("@\(username)")
                                    // 板 02 は 11px だが、本文系の最小は 12pt
                                    .font(.caption)
                                    .foregroundStyle(WebTheme.faint)
                                    .lineLimit(1)
                            }
                        }
                    }
                    // アイコンを 34pt にしても、押せる高さは 44pt を保つ
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // 実機の絵の道しるべ（`ScreenshotTests`）。
                // **マイページは CI では撮れない**（ログインしないため）が、
                // 人のページは同じ部品で組んである——ここから撮る
                .accessibilityIdentifier("photo.author")

                Spacer(minLength: 8)

                // 取れなかった回も「フォロー」で出す（押されたら取り直してから送る）
                if PhotoDetailRules.showsFollow(isMine: isMine, signedIn: auth.userId != nil,
                                                isFollowing: isFollowing, lookupFailed: followLookupFailed,
                                                ownerBlocked: hidden.blockedUserIds.contains(ownerId)) {
                    followButton(ownerId, following: isFollowing ?? false)
                }
            }
        }
    }

    private func followButton(_ userId: String, following isFollowing: Bool) -> some View {
        Button {
            // 外すときだけ確認を挟む（`unfollowConfirmation`）
            if isFollowing { showUnfollowConfirm = true } else { Task { await toggleFollow(userId, follow: true) } }
        } label: {
            // 板 02・31 と同じ札（人のページと共通の `FollowPill`）
            FollowPill(title: isFollowing ? L("フォロー中", "Following") : L("フォロー", "Follow"),
                       isFollowing: isFollowing)
        }
        .buttonStyle(.plain)
        .disabled(isFollowWorking)
        .opacity(isFollowWorking ? 0.6 : 1)  // 人のページと同じ薄さ
        .unfollowConfirmation(isPresented: $showUnfollowConfirm) {
            // **向きは押した時点で決める**（人のページと同じ）。確認が出ている間に取り直しが
            // 走って姿が変わっても、「外す」を選んだのに follow を送らない
            Task { await toggleFollow(userId, follow: false) }
        }
    }

    /// 知らせを消す。**操作を押した時点で両方消す**＝画面には最後に起きた操作の知らせだけが出る。
    /// 片方だけ消すと、消えずに残るもう片方が新しい知らせを隠すか、成功の直後に古い失敗が出てくる
    private func clearNotices() {
        actionError = nil
        model.errorMessage = nil
        // 成功の知らせ（ブロックしました）も同じ扱い——古いものを新しい失敗の後に残さない
        actionNotice = nil
    }

    /// **返ってきた状態を使う。** 自分で反転すると、失敗した回に
    /// 画面だけフォロー中になる
    /// - Parameter follow: 押したボタンの向き（フォローしたいか）
    private func toggleFollow(_ userId: String, follow wantsFollow: Bool) async {
        guard !isFollowWorking else { return }
        isFollowWorking = true
        defer { isFollowWorking = false }
        // 前の回の知らせを残さない（押し直して通ったのに赤字が残る）
        clearNotices()
        // **分からないままフォローを送らない。** 一覧が取れなかった回は、ここで取り直して
        // から決める——既にフォロー中なら送らずに姿だけ直す（二重に送らない）。
        // 外す方は取り直さない（外すのは何度送っても同じ）
        if isFollowing == nil && wantsFollow {
            guard followLookupFailed else { return }
            let ids: Set<String>
            do {
                ids = Set(try await environment.social.myFollowingIds())
            } catch is CancellationError {
                return
            } catch {
                // 待つ間に別の人の写真へ送っていたら、今の人に前の人の失敗を出さない
                guard ownerId == userId else { return }
                actionError = L("フォローの状態を確かめられませんでした", "Couldn't check follow status")
                return
            }
            // **待つ間に別の人の写真へ送ったら書かない**（前の人の状態が次の人のボタンに出る）
            guard ownerId == userId else { return }
            followLookupFailed = false
            if ids.contains(userId) {
                isFollowing = true
                return
            }
            isFollowing = false
        }
        // **失敗は黙らない**（圏外で押して何も起きないと、押せていないのか分からない）。
        // 知らせは、ブロックの失敗と同じ `actionError` に出す
        do {
            let result = wantsFollow
                ? try await environment.social.follow(userId: userId)
                : try await environment.social.unfollow(userId: userId)
            // 待つ間に別の人の写真へ送ったら書かない
            guard ownerId == userId else { return }
            isFollowing = result.following
        } catch is CancellationError {
            return
        } catch {
            // 待つ間に別の人の写真へ送っていたら、今の人に前の人の失敗を出さない
            guard ownerId == userId else { return }
            actionError = (error as? LocalizedError)?.errorDescription
                ?? L("うまくいきませんでした", "That didn't work")
        }
    }

    // MARK: - 操作

    private var menu: some View {
        Menu {
            // **共有するのは画像ではなくページ。** 生の画像を送ると、
            // 受け取った人に題も説明も撮影地も出ない。
            // モック6 の SNS 別ボタン（Instagram・X・LINE…）は作らない
            // ——各社の URL スキームを `LSApplicationQueriesSchemes` に
            // 登録し、入っていないアプリの分を隠す仕掛けが要る。標準の
            // 共有シートなら入っているアプリだけが並ぶ
            if let url = shareURL(for: current) {
                ShareLink(item: url) { Label(L("共有", "Share"), systemImage: "square.and.arrow.up") }
            }
            if isMine {
                // **Menu の中に NavigationLink を置かない。** メニューの中身は
                // ナビゲーションの外側に出るので押しても進まない。シートで出す
                Button { showEdit = true } label: {
                    Label(L("編集", "Edit"), systemImage: "pencil")
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label(Labels.Common.delete, systemImage: "trash")
                }
            } else {
                // **通報とブロックは1タップで届くところに置く**（審査で見られる）
                Button {
                    ownerBlockedWhenReporting = ownerId.map(hidden.blockedUserIds.contains) ?? false
                    showReport = true
                } label: {
                    Label(L("通報する", "Report"), systemImage: "flag")
                }
                if let ownerId {
                    Button(role: .destructive) { Task { await block(ownerId) } } label: {
                        Label(L("この人をブロック", "Block this person"), systemImage: "hand.raised")
                    }
                }
            }
        } label: {
            // 板 02: 写真の上のガラスの丸（44pt）に点3つ。**iOS 26 はバーの
            // ボタンを自分でガラスにする**ので、丸を重ねるのはそれより前だけ
            menuIcon
                .accessibilityLabel(L("この写真の操作", "More actions"))
        }
    }

    @ViewBuilder
    private var menuIcon: some View {
        let dots = Image(systemName: "ellipsis")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
        if #available(iOS 26, *) {
            dots
        } else {
            dots.jpGlass(in: Circle())
        }
    }

    /// 大きく見る画面でのダブルタップ。**いま見ている写真に**付ける。
    ///
    /// この画面の1枚なら下のハートと同じ道（数と状態を画面にも出す）。
    /// 隣の写真なら、その写真に直接送る——**解除はしない**ので `like` だけ
    private func likeFromViewer(_ shown: Photo) async {
        if shown.id == current.id {
            // 🔴 **ダブルタップは付けるだけ。** いいね済みの1枚で下のハートと同じ
            // 入れ替えを通すと、ダブルタップで外れていた（隣の写真は `like` だけ）
            guard !model.liked else { return }
            // 下のハートと同じく、端末の控えとホームの数にも渡す
            await toggleLikeHere()
            return
        }
        guard viewerLikesInFlight.insert(shown.id).inserted else { return }
        defer { viewerLikesInFlight.remove(shown.id) }
        // 先に灯す（押した手応えを待たせない）。届かなければ**押す前に**戻す
        // ——元からいいね済みの写真を「外した」扱いにしない
        let wasLiked = favorites.contains(shown.id)
        // 答えは押した人の控えにだけ書く（待っている間に人が替わったら書かない）
        let owner = favorites.owner
        favorites.set(shown.id, favorite: true)
        do {
            let result = try await environment.social.like(photoId: shown.id)
            favorites.set(shown.id, favorite: result.liked, for: owner)
            // 押した回の答えだけを渡す（`LikeCountStore` の注記）
            if let likes = result.likes { likeCounts.set(shown.id, count: likes) }
        } catch {
            favorites.set(shown.id, favorite: LiveLikes.likedAfterFailedDoubleTap(wasLiked: wasLiked),
                          for: owner)
        }
    }

    /// 大きく見る画面の下のハート（板 14）。**付け外しの両方**。
    ///
    /// この画面の1枚なら下のハートと同じ道。隣の写真は、先に灯して／消して
    /// から送り、届かなければ元に戻す（ダブルタップと同じ控え方）
    private func toggleLikeFromViewer(_ shown: Photo) async {
        if shown.id == current.id {
            await toggleLikeHere()
            return
        }
        guard viewerLikesInFlight.insert(shown.id).inserted else { return }
        defer { viewerLikesInFlight.remove(shown.id) }
        let wasLiked = favorites.contains(shown.id)
        let owner = favorites.owner
        favorites.set(shown.id, favorite: !wasLiked)
        do {
            let result = wasLiked
                ? try await environment.social.unlike(photoId: shown.id)
                : try await environment.social.like(photoId: shown.id)
            favorites.set(shown.id, favorite: result.liked, for: owner)
            if let likes = result.likes { likeCounts.set(shown.id, count: likes) }
        } catch {
            favorites.set(shown.id, favorite: wasLiked, for: owner)
        }
    }

    /// 共有するページ。**個別ページが在る写真だけ**（`PhotoLink`）。
    /// 隣の写真も同じ一覧から来ているので、同じ判断で足りる
    private func shareURL(for item: Photo) -> URL? {
        let latest = item.id == current.id ? shown : item
        // 🔴 **公開範囲を絞った写真は配らない（共有を出さない）。** 一覧には
        // `/feed/restricted` の写真も混ざる（`published: true`）が、`photos.json` に
        // 載らず個別ページが建たない。Web は絞った写真を読まないので、ホームの
        // `?photo=` に振り替えても「見つかりませんでした」になる——受け取った人
        // （フォロワー本人も）が開けない。自分のページから開いた自分の写真も同じ
        // 下書き（非公開）も同じ（Web が読む一覧に載らない）
        guard CollectionScreen.isShareable(latest) else { return nil }
        return PhotoLink.url(photoId: item.id,
                             isPublished: fromPublicFeed && latest.published != false)
    }

    /// **押した回の**答えを、ホームのカードと検索の格子にも渡す。
    /// 渡さないと、詳細で押して戻ったときに数が押す前のままになる
    /// （ホームは戻っても一覧を読み直さない）。
    ///
    /// 開いたときに読んだ数は渡さない（`LikeCountStore` の注記）。
    /// 答えが無かった回（失敗・数を返さない答え）も渡さない

    /// 上に出ている1枚のいいね。端末の控えとホームの数にも渡す。
    ///
    /// **押した1枚を先に覚える。** 送っている間に束の隣へ送ると、答えは
    /// 前の1枚のもの——今の1枚の控えに書かない
    private func toggleLikeHere() async {
        // 送っている間は押しても何もしないので、知らせも消さない
        guard !model.isLiking else { return }
        clearNotices()
        guard acceptsReactions else {
            model.errorMessage = L("下書きにはいいねできません。公開すると付けられます",
                                   "Drafts can't be liked. Publish the photo first.")
            return
        }
        // **届かなかった回は控えに書かない**（押す前のハートのまま）。
        // 答えは**押した1枚に**書く——送っている間に束の隣へ送っても
        let owner = favorites.owner
        let answer = await model.toggleLike()
        guard let answer else { return }
        favorites.set(answer.photoId, favorite: answer.liked, for: owner)
        // 押した回の答えだけを渡す（`LikeCountStore` の注記）
        if let likes = answer.likes { likeCounts.set(answer.photoId, count: likes) }
    }

    private func socialBar(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 板 02: 白い印を両端に揃えて並べ、数は等幅 12px の白。
            // 外に -6 は、各ボタンの横の余白 6pt ぶん（印の端を本文の端に揃える）
            HStack(spacing: 0) {
                Button {
                    // 端末側のハートも合わせる（圏外でも一覧が出る）
                    Task { await toggleLikeHere() }
                } label: {
                    // **いちばん押されるボタンがいちばん小さかった。**
                    // 既定の字のままで 20pt ほどしか無く、指では狙いにくい
                    // **分からない数は出さない**（読み込み前・圏外に「0」と描かない。
                    // `actionLabel` は数が nil なら印だけ）
                    actionLabel(systemImage: model.liked ? "heart.fill" : "heart",
                                count: model.likes)
                }
                .buttonStyle(.plain)
                // 読み上げは「いいね、N」（印の名前と数字を連ねない）
                .accessibilityLabel(L("いいね", "Like"))
                .accessibilityValue(model.likes.map { "\($0)" } ?? "")
                .accessibilityAddTraits(model.liked ? .isSelected : [])
                Spacer(minLength: 0)

                // 吹き出しを押すと下のコメントへ送る。**数は取れたときだけ**
                // ——読み込み前・圏外に「0」を出すと「まだ無い」と読まれる
                Button {
                    withAnimation { proxy.scrollTo(Self.commentsAnchor, anchor: .top) }
                } label: {
                    actionLabel(systemImage: "bubble.right", count: model.commentCount)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CommentsHeading.label(commentCount: model.commentCount))
                Spacer(minLength: 0)

                // **保存**。いいねとは別の入れ物（`saves#<uid>`）。
                //
                // 🔴 以前はいいねの控え（`FavoritesStore`）を共用していたので、
                // 保存を押すとハートが灯り、マイページの「いいねした写真」に
                // **保存しただけの写真が並んで**いた。
                Button {
                    Task { await toggleSave() }
                } label: {
                    actionLabel(systemImage: savedPhotos.contains(current.id) ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("保存", "Save"))
                .accessibilityAddTraits(savedPhotos.contains(current.id) ? .isSelected : [])

                // **シェア**（配るのは画像ではなくページ）。個別ページが無い写真では
                // 出さない——そのときは3つが両端揃えで並ぶ
                if let url = shareURL(for: current) {
                    Spacer(minLength: 0)
                    ShareLink(item: url) {
                        actionLabel(systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel(L("共有", "Share"))
                }
            }
            .padding(.horizontal, -6)
            // **いま押した操作の知らせを先に出す。** 前に出た `model.errorMessage`
            // （いいね・コメントの失敗）は消えないので、先に見るとフォローの失敗が隠れる
            if let message = actionError ?? model.errorMessage {
                Text(message).font(.footnote).foregroundStyle(WebTheme.danger)
            } else if let actionNotice {
                Text(actionNotice).font(.footnote).foregroundStyle(WebTheme.muted)
            }
        }
    }

    /// 4つの操作の中身（板 02: 24px の白い印＝SF の `.title2`（約 22pt）で同じ見た目の大きさ・
    /// 数は等幅 12px の白・押せる大きさ 44×44 以上）。
    /// 数は**取れたときだけ**（読み込み前・圏外に「0」を出すと「まだ無い」と読まれる）
    private func actionLabel(systemImage: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                // 文字サイズの設定で伸びる
                .font(.title2)
            if let count {
                Text("\(count)")
                    .font(JPFont.mono(12, relativeTo: .caption))
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .webTappable()
    }

    /// 「この近くで撮られた写真」（板 02）。**座標の無い写真、近くに1枚も
    /// 無い写真では節ごと出さない**——「0枚」の見出しを置かない。
    ///
    /// 拾うのは読み込み済みの公開写真だけ（`NearbyPhotos.around`・通信しない）。
    /// 「地図で見る」はこの写真と近くの写真だけの地図（`MyPhotosMap` を流用）
    @ViewBuilder
    private var nearbySection: some View {
        if !nearby.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("この近くで撮られた写真", "Taken nearby"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                    Spacer()
                    NavigationLink {
                        NearbyMapScreen(opened: shown, nearby: nearby, openedFromPublicFeed: fromPublicFeed)
                    } label: {
                        HStack(spacing: 4) {
                            Text(L("地図で見る", "View on map"))
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(nearby) { item in
                            NavigationLink {
                                PhotoDetailView(photo: item, context: nearby)
                            } label: {
                                RemoteImage(url: item.gridImageURL, alignment: item.gridAlignment)
                                    .frame(width: 108, height: 108)
                                    .clipped()
                                    .accessibilityLabel(item.accessibilityText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// 画面の下に貼る入力欄（板 02: 自分のアイコン・丸い欄・送信）。**ログイン中だけ**
    @ViewBuilder
    private var composer: some View {
        if let me = auth.userId, acceptsReactions {
            HStack(spacing: 10) {
                RemoteImage(url: UserProfile.profileAssetURL(userId: me, suffix: nil, cacheBust: nil),
                            placeholderSymbol: "person.crop.circle.fill")
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                TextField(L("コメントを書く", "Write a comment"), text: $model.draftComment, axis: .vertical)
                    // **サーバーの上限で止める。** 超えたぶんは黙って切られ、送った文と同じとして
                    // 下書きも消えるので、後ろが二度と戻らなかった（Web は maxLength=500）
                    .onChange(of: model.draftComment) { old, value in
                        let kept = PostLimits.limited(old: old, new: value, limit: PostLimits.comment)
                        if kept != value { model.draftComment = kept }
                    }
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(minHeight: 44)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                Button {
                    Task { clearNotices(); await model.postComment() }
                } label: {
                    // 白。下の帯は写真の上を流れるガラスなので真鍮を置かない（デザインシステム「黒塗りの真鍮」）
                    Image(systemName: "paperplane")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Common.send)
                // コメントを読み直している間も押せない（`postComment` は黙って断るので、押せる形にしない）
                .disabled(model.isPosting || model.isReloadingComments
                          // 空の判定は `postComment` と同じ（改行だけでも押せない）
                          || model.draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Color.black.opacity(0.55))
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
        }
    }

    /// 見出しに出すコメントの数。サーバーの総数から、**読めた一覧のうち
    /// ブロックした人の分**を引く（`CommentsHeading.visibleCount`）
    private var visibleCommentCount: Int? {
        CommentsHeading.visibleCount(total: model.commentCount, loaded: model.comments.count,
                                     shown: dropped.comments(model.comments).count)
    }

    /// コメントの節（板には無いが、読んで書く場所なので下に残す）。
    /// 見出しは以前の札と同じ言い方（数は取れたときだけ）
    private var commentsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CommentsHeading.label(commentCount: visibleCommentCount))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
            if acceptsReactions {
                commentSection
            } else {
                Text(L("下書きにはコメントできません。公開すると受け付けます",
                       "Drafts can't receive comments. Publish the photo first."))
                    .font(.callout)
                    .foregroundStyle(WebTheme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var commentSection: some View {
        // **空かどうかは絞った後の一覧で決める。** すべてブロックした人のコメントだと、
        // 下が空白のまま「まだありません」も出なかった
        let visible = dropped.comments(model.comments)
        if visible.isEmpty {
            // **空の理由を分ける。** 引けなかった回に「まだありません」と
            // 出すと、書いてあるコメントが消えたように見える
            if model.commentsUnavailable {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("コメントを読み込めませんでした", "Couldn't load comments"))
                        .font(.callout)
                        .foregroundStyle(WebTheme.faint)
                    // 詳細には引き下げが無いので、読み直す手段をここに置く
                    Button(Labels.Common.retry) { Task { await model.reloadComments() } }
                        .buttonStyle(.bordered)
                        // 投稿している間も押せない（`reloadComments` は黙って断る）
                        .disabled(model.isReloadingComments || model.isPosting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else if visibleCommentCount == 0 {
                Text(L("まだコメントはありません", "No comments yet"))
                    .font(.callout)
                    .foregroundStyle(WebTheme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            // ブロックした人のコメントは出さない。見出しの数も落とした分を引く
            // （`visibleCommentCount`）。**写しで落とす**（`dropped`）
            ForEach(visible) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        // **退会した人にはプロフィールへの導線を出さない**
                        if comment.isFromDeletedUser {
                            Text(comment.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        } else {
                            NavigationLink {
                                UserProfileView(userId: comment.uid)
                            } label: {
                                // 当たりだけ 44pt（行の高さは字のまま・「削除」と同じ形）
                                Text(comment.name).font(.caption.weight(.semibold))
                                    .padding(.top, Self.commentNameTapSlackTop)
                                    .padding(.bottom, Self.commentNameTapSlackBottom)
                                    .frame(minWidth: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .padding(.top, -Self.commentNameTapSlackTop)
                                    .padding(.bottom, -Self.commentNameTapSlackBottom)
                            }
                        }
                        Spacer()
                        // **写真の持ち主も消せる。** サーバーは持ち主にも
                        // 許している（`comments.ts` の `ownerId !== uid`）のに、
                        // アプリは自分が書いたぶんしか出していなかった
                        // ——UGC のアプリは「不快な書き込みを持ち主が取り除ける」
                        // ことを審査（1.2）で見られる
                        if comment.uid == auth.userId || isMine {
                            // **押してすぐ消さない**（確かめてから）。読み上げには誰のコメントかを入れる
                            // 押せる広さは 44pt（字は本文の最小 12pt）。広げるのはラベルの内側で
                            // （ボタンの外に frame を付けても当たりは広がらない）。
                            // **行の高さは字のまま**——当たりだけ上下にはみ出させる
                            // （44pt の枠で並べると、コメントの行が間延びした）
                            Button { commentPendingDelete = comment } label: {
                                Text(Labels.Common.delete)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                                    .padding(.vertical, -Self.commentDeleteTapSlack)
                            }
                                .font(.caption)
                                // 読み直している間・消している途中は押せない（`deleteComment` は黙って断る）
                                .disabled(model.isReloadingComments || model.deletingCommentIds.contains(comment.id))
                                .accessibilityLabel(L("\(comment.name)さんのコメントを削除",
                                                      "Delete comment by \(comment.name)"))
                        }
                    }
                    Text(comment.text).font(.callout)
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// 「この場所のスポット」の行き先＝この写真の撮影地を**撮影地の集まり**
    /// （`DerivedSpot.openable`・2枚以上）として引く。撮影地が書かれて
    /// いない写真には、この行を出さない。
    ///
    /// ⚠️ 台帳の撮影スポット（Web の `content/spots.json`・アプリは
    /// `OfficialSpot` として別に読む）は**ここでは引かない**。紐付けは
    /// `Photo.spotId` だけで、本番の公開写真はまだ1枚も持っていない
    /// （持つ写真が出てきたら `OfficialSpotView` への行を足す）。
    private func loadSpotLead() async {
        // 途中で消さずに、答えが出てから入れ替える（絞り直しで行がちらつかない）
        let label = (shown.location ?? "").trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else {
            spotLead = nil
            return
        }
        let fetched = try? await environment.gallery.fetchPhotos()
        // **取り消された回は何も書かない。** `try?` が取り消しを nil に
        // 変えるので、書くと後の回が入れた行き先を消しうる
        guard !Task.isCancelled else { return }
        guard let fetched else {
            spotLead = nil
            return
        }
        // 見せない写真を落としてから数える（`ModerationStore.visible`）。
        // `blockAndHide` は一覧の側（`setHidden`）より先に `revision` を
        // 進めるので、一覧から取った直後でもここで落とす
        spotLead = Self.makeSpotLead(label, in: hidden.visible(fetched))
    }

    /// **1枚しか無い地点には出さない**（`DerivedSpot.openable`）。
    /// この写真の個別ページと中身が同じになる
    private static func makeSpotLead(_ label: String, in photos: [Photo]) -> SpotLead? {
        DerivedSpot.openable(label, in: photos).map { SpotLead(spot: $0, photos: photos) }
    }

    /// ブロック・通報のあと、**手元の並びだけ**を絞り直す（通信しない）。
    /// スポットの行き先は落としたあとで**数え直す**——2枚を割れば行を消す
    private func refilterHidden() {
        nearby = hidden.visible(nearby)
        if let lead = spotLead {
            let label = (shown.location ?? "").trimmingCharacters(in: .whitespaces)
            spotLead = Self.makeSpotLead(label, in: hidden.visible(lead.photos))
        }
    }

    /// 近くの写真を、読み込み済みの公開写真から拾う（通信は一覧の控えだけ）。
    ///
    /// 見せない写真（ブロック・通報）は落とす。上の束（`heroGroup`）と同じ
    /// 並び（`siblings`）を渡し、**上に出ている写真だけ**を除く
    private func loadNearby() async {
        guard shown.coords != nil else {
            nearby = []
            return
        }
        let fetched = try? await environment.gallery.fetchPhotos()
        guard !Task.isCancelled else { return }
        guard let fetched else {
            nearby = []
            return
        }
        nearby = NearbyPhotos.around(shown, in: hidden.visible(fetched), context: siblings)
    }

    private func block(_ userId: String) async {
        clearNotices()
        do {
            // 押したあと実際に消す（公開一覧は静的なので端末で落とす）
            try await hidden.blockAndHide(userId, environment: environment)
            // **成功は赤字で出さない**（失敗の欄 `actionError` は空けたまま）。
            // ブロックするとフォローも外れるので、ボタンも外した姿にする
            actionNotice = L("ブロックしました。おたがいの投稿が見えなくなります。", "Blocked. You won't see each other's posts.")
            // **ブロックした相手にフォローボタンを出さない**（false だと「フォロー」が出る）
            if userId == ownerId {
                isFollowing = nil
                followLookupFailed = false
            }
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }

    /// 編集の帰りに、自分の一覧から1枚だけ引き直す。
    ///
    /// **引けなくても画面は壊さない**（圏外なら古いまま出す方がまし）。
    /// 保存を入れ替える。**サーバーが本体**で、控えは送れたときだけ合わせる
    private func toggleSave() async {
        // **送っている間は受けない**（いいねの `isLiking` と同じ）。連打で save と
        // unsave が並んで飛ぶと、着く順や失敗の巻き戻しで画面とサーバーが食い違う
        guard !isSavingBookmark else { return }
        clearNotices()
        // **未ログインは送らずに知らせる**（いいねと同じ扱い）。以前は押せて、
        // 失敗を黙って巻き戻すだけだった
        guard auth.userId != nil else {
            actionError = L("保存するにはログインしてください", "Sign in to save photos")
            return
        }
        isSavingBookmark = true
        defer { isSavingBookmark = false }
        let id = current.id
        let wasSaved = savedPhotos.contains(id)
        // 戻すのは押した人の控えだけ（待っている間に人が替わったら書かない）
        let owner = savedPhotos.owner
        savedPhotos.set(id, saved: !wasSaved)
        do {
            if wasSaved {
                try await environment.saves.unsave(photoId: id)
            } else {
                try await environment.saves.save(photoId: id)
            }
        } catch is CancellationError {
            savedPhotos.set(id, saved: wasSaved, for: owner)
        } catch {
            savedPhotos.set(id, saved: wasSaved, for: owner)
            // 待っている間に束の隣へ送っていたら、今の1枚に前の1枚の失敗を出さない
            guard id == current.id else { return }
            // **黙らない**（いいね・フォローと同じ）。404 で保存が残っている回は
            // `SaveService.save` が成功として返すのでここには来ない。残る 404 は
            // 下書き（公開していない写真）——サーバーの「見つかりません」では分からない
            if !wasSaved, SocialService.isNotFound(error) {
                actionError = L("公開中の写真だけ保存できます", "Only published photos can be saved")
            } else {
                actionError = (error as? LocalizedError)?.errorDescription
                    ?? L("保存できませんでした", "Couldn't save")
            }
        }
    }

    private func reloadPhoto() async {
        guard isMine else { return }
        let id = current.id
        guard let fresh = try? await environment.photos.myPhoto(id: id) else { return }
        edits[id] = fresh
    }

    private func deletePhoto() async {
        clearNotices()
        let photoId = current.id
        // 送る**前に**取る（待っている間に人が替わっていたら印を付けない）
        let owner = hidden.owner
        do {
            try await environment.photos.delete(photoId: photoId)
            // 🔴 **公開一覧からも落とす。** 一覧は建て直しまで古い静的 JSON で、
            // 控えも残るので、消した写真がホーム・探す・地図に出続け、押すと
            // いいね・保存・コメントが 404 になっていた（`ModerationStore.goneMarks`）
            await hidden.hideGone(photoId, for: owner, environment: environment)
            // **消した写真の画面に留まらせない。** 残ると、もう無いものを
            // 編集したり、もう一度削除を押したりできてしまう
            dismiss()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }
}

/// 「地図で見る」の行き先: この写真と近くの写真だけの地図。
///
/// 地図の部品はプロフィールの「マップ」（`MyPhotosMap`）をそのまま使う
/// ——初期の枠取り（`MapFraming`）もピンを押したときの一覧も同じでよい
private struct NearbyMapScreen: View {
    let opened: Photo
    let nearby: [Photo]
    /// **開いた1枚にだけ**引き継ぐ（`NearbyPhotos.fromPublicFeed`）。
    /// 既定の `true` に戻ると、個別ページの無い自分の写真（マイページから
    /// 開いた下書きなど）に共有が出る。逆に全ピンへ渡すと、近くの他人の
    /// 公開写真まで共有がトップ（`/?photo=`）に落ちる
    let openedFromPublicFeed: Bool

    var body: some View {
        ScrollView {
            // 近くの写真は他人のものも混ざる（「投稿するときに…」と言わない）
            MyPhotosMap(photos: [opened] + nearby, isMine: false, fromPublicFeed: { photo in
                NearbyPhotos.fromPublicFeed(photo, openedId: opened.id,
                                            openedFromPublicFeed: openedFromPublicFeed)
            })
                .padding(.vertical, 16)
        }
        .webScreen()
        .navigationTitle(L("この近くで撮られた写真", "Taken nearby"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TagRow: View {
    let tags: [String]
    var body: some View {
        // 横に流さず折り返す。タグは59種あり、長い並びは画面外に出る
        FlowLayout(spacing: 6) {
            ForEach(TagInput.uniqueChips(tags), id: \.self) { tag in
                NavigationLink {
                    TagPhotosView(kind: .tag(tag))
                } label: {
                    // Web: `bg-white/5 ring-1 ring-white/10 text-xs text-white/50`
                    // 板 02: 「#夕焼け」。**頭の「#」は描くときだけ**——保存する値には
                    // 付けない（`TagPhotosView` にも素の値を渡す）。打った人が既に
                    // 「#」「＃」を付けていた行は畳んでから1つ付ける（`TagInput.chipText`）
                    //
                    // 札は板どおり横 12・高さ 32・地 5%・縁 10%（字の色は `muted` のまま）
                    Text(TagInput.chipText(tag))
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Color.white.opacity(0.05), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                        // 見た目は 32pt、押せる高さは 44pt（上下 6pt ずつ広げ、並びは詰めたまま）。
                        // 行の間（6pt）より広げるので、上下の行の押せる範囲が少し重なる
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .padding(.vertical, -6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 撮影情報の札。
///
/// **提案どおりの二段構え**（2026-09-21・owner から絵で）:
///
///     撮影情報                              📷
///     絞り        シャッター      ISO
///     f/1.8       1/277s         64        ← 大きく（28pt）
///     ──────────────────────────
///     CAMERA
///     Apple iPhone 16 Pro Max              ← 22pt
///     LENS
///     iPhone 16 Pro Max back triple camera
///     FOCAL LENGTH
///     7mm
///
/// **撮った条件（絞り・シャッター・ISO）を主役にする。** 写真を見て
/// 「どう撮ったか」を知りたい人がまず探すのはこの3つで、機材名は
/// その次。以前は6項目を同じ大きさで並べていたので、**どれも目に
/// 入らなかった**。
private struct ExifRow: View {
    let exif: Photo.Exif

    /// **畳んでおく。** 指示書 7-3:「一般ユーザーにとって情報が多すぎない
    /// よう、折りたたみ可能な撮影情報セクションにまとめてください」。
    /// 写真を見に来た人には要らないが、**カメラ好きには外せない**ので
    /// 消しはしない。開いた状態は画面を離れるまで覚える
    @State private var expanded = false

    /// 機種名。**`CameraName.deduped` を通す**——保存済みの値には
    /// メーカー名が二重に残っている行があり（実データ）、そのまま出すと
    /// 「Hasselblad Hasselblad X2D II 100C」と画面に見える
    var camera: String? { CameraName.deduped(exif.camera) }

    private struct Item: Identifiable {
        let id: String
        let value: String
    }

    /// 上段（大きく出す3つ）。**無いものは詰める**——空の柱を立てない
    private var primary: [Item] {
        [
            (L("絞り", "Aperture"), exif.aperture),
            (L("シャッター", "Shutter"), exif.exposure),
            ("ISO", exif.iso.map { String($0) }),
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return Item(id: label, value: value)
        }
    }

    /// 下段（機材）。長い値があるので縦に積む
    private var secondary: [Item] {
        [
            (L("カメラ", "CAMERA"), camera),
            (L("レンズ", "LENS"), exif.lens),
            (L("焦点距離", "FOCAL LENGTH"), exif.focalLength),
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return Item(id: label, value: value)
        }
    }

    var body: some View {
        if !primary.isEmpty || !secondary.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack {
                        Text(L("撮影情報", "Shot with"))
                            .font(JPFont.rowTitle)
                            .foregroundStyle(WebTheme.foreground)
                        Spacer()
                        Image(systemName: "camera")
                            .font(.title3)
                            .foregroundStyle(Color.white.opacity(0.4))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WebTheme.muted2)
                    }
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? L("撮影情報を閉じる", "Hide camera info")
                                             : L("撮影情報を開く", "Show camera info"))

                if expanded, !primary.isEmpty {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(primary) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.id)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white.opacity(0.5))
                                Text(item.value)
                                    // **ここがいちばん読まれる。** 数字なので等幅（f/8・1/125・ISO 100）
                                    .font(JPFont.mono(24, medium: true, relativeTo: .title))
                                    .foregroundStyle(WebTheme.foreground)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    // **大きい文字の設定で「1/4000s」が切れないように上限を置く。**
                    // 3列で1列 約89pt。等幅 24pt の .title は AX2 で 43pt まで伸び、
                    // 縮小の下限 0.6 をかけても 93pt で「1/40…」と切れる（レビューの見積もり）。
                    // xxxLarge（.title = 34pt）なら 7字 × 0.6em × 34 × 0.6 ≈ 86pt で収まる
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }

                if expanded, !primary.isEmpty, !secondary.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 16) {
                    ForEach(secondary) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.id.uppercased())
                                .font(.subheadline)
                                .tracking(0.8)
                                .foregroundStyle(Color.white.opacity(0.5))
                            // **機材だけリンクにする**（`/camera/*` の集約がある）
                            if item.id == L("カメラ", "CAMERA"), let camera {
                                NavigationLink {
                                    TagPhotosView(kind: .camera(camera))
                                } label: {
                                    // 字の見た目・行の高さはそのまま、当たりだけ 44pt
                                    // （`.title3` ≒ 24pt の上下に 10 ずつ。外へ広げて同じだけ詰める。
                                    // 長い機種名が2行になっても並びは縮まない）
                                    Text(item.value)
                                        .font(.title3)
                                        .foregroundStyle(WebTheme.foreground)
                                        .underline(true, color: Color.white.opacity(0.25))
                                        .padding(.vertical, 10)
                                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .padding(.vertical, -10)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(item.value)
                                    .font(.title3)
                                    .foregroundStyle(WebTheme.foreground)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 詳細画面の判断のうち、画面を建てずに確かめられるもの
enum PhotoDetailRules {

    /// コメント・いいねを受け付ける写真か。**下書き（`published == false`）は受け付けない**
    /// ——サーバーが断る（`comments.ts` の getComments・postComment、`likes.ts` の条件
    /// `published = :pub`）。出したままだと、下書きを開くたびに「コメントを読み込めません
    /// でした」が直らず、送ると「写真が見つかりません」になっていた
    static func acceptsReactions(published: Bool?) -> Bool { published != false }

    /// コメント・いいねを読み直す鍵。**受け付けるかどうかも入れる**——編集で下書きを
    /// 公開しても、人と写真が同じなので読み直さず、開いたときの「コメントを読み込めません
    /// でした」と空のいいねの数が残っていた
    static func reloadKey(userId: String?, photoId: String, published: Bool?) -> String {
        "\(userId ?? "")|\(photoId)|\(acceptsReactions(published: published))"
    }

    /// 持ち主の横にフォローのボタンを出すか。
    ///
    /// 取れなかった回（`lookupFailed`）も出す（押されたら取り直してから送る）。
    /// 🔴 **ブロックした相手には出さない。** 通報シートから「ブロックもする」を選んだ回は
    /// `block()` を通らないので、前に取ったフォローの状態が残り、ブロックした相手に
    /// フォロー・フォロー解除を送れていた
    static func showsFollow(isMine: Bool, signedIn: Bool, isFollowing: Bool?,
                            lookupFailed: Bool, ownerBlocked: Bool) -> Bool {
        guard !isMine, signedIn, !ownerBlocked else { return false }
        return isFollowing != nil || lookupFailed
    }

    /// 詳細の上で左右に送る束と、いま見ている位置。**大きく見る画面（`viewerLineup`）と
    /// 同じ絞り方**——ブロック・通報した写真を落とし、今の1枚は残す。
    /// 落としていなかったので、通報した写真が上の送りにだけ残っていた
    static func heroGroup(_ siblings: [Photo], current: Photo, hiding: ModerationSnapshot,
                          edits: [String: Photo] = [:]) -> (photos: [Photo], index: Int) {
        let photos = PhotoGroups.siblings(of: current,
                                          in: viewerLineup(siblings, current: current,
                                                           hiding: hiding, edits: edits).photos)
        return (photos, photos.firstIndex(where: { $0.id == current.id }) ?? 0)
    }

    /// 大きく見る画面に渡す並びと、開く位置。
    ///
    /// 🔴 **ブロック・通報した写真を落とす**（`ModerationSnapshot.visible`）。
    /// 以前は素の並び（`siblings`）を渡していて、この画面でブロックしたあとも
    /// 大きく見る画面で左右に送るとその人の写真が出てきた。
    ///
    /// **押した1枚（`current`）は残す。** 詳細の上にはその1枚が出ていて、
    /// 押して開いた先が別の写真になる・何も出ない方がおかしい。落とすと
    /// 位置が引けず、並びが空になる回もある。位置は必ず並びの中に収める
    ///
    /// 🔴 **編集して保存した姿（`edits`）はここで差し替える**（詳細の上の束も通る1か所）。
    /// 上の束だけ素の並びで絞っていたので、束の1枚を非公開にして隣へ送ると、
    /// 消した印（`gone`）と古い `published` で上の送りからだけその1枚が消えていた
    static func viewerLineup(_ siblings: [Photo], current: Photo, hiding: ModerationSnapshot,
                             edits: [String: Photo] = [:]) -> (photos: [Photo], index: Int) {
        let siblings = siblings.map { edits[$0.id] ?? $0 }
        let kept = Set(hiding.visible(siblings).map(\.id))
        // 束の写真は詳細の上（`PhotoGroups.siblings`）と同じ選んだ順に。渡された順のままだと
        // 上では右へ送る写真が、大きく見る画面では左にあった
        let photos = PhotoGroups.inPostOrderWithinGroups(siblings)
            .filter { $0.id == current.id || kept.contains($0.id) }
        guard !photos.isEmpty else { return ([current], 0) }
        return (photos, photos.firstIndex(where: { $0.id == current.id }) ?? 0)
    }
}
