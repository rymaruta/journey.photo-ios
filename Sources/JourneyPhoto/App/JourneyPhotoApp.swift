import SwiftUI
import UIKit
import UserNotifications
// Linux では URLCache が別モジュールに居る（iOS では何も起きない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// **`@main` は Xcode のビルドだけ。** SPM（Linux での型検査）では
// ライブラリとして読むので、付いたままだとテスト実行子の `main` と衝突する。
// `SWIFT_PACKAGE` は SwiftPM が自動で定義し、Xcode は定義しない
#if !SWIFT_PACKAGE
@main
#endif
struct JourneyPhotoApp: App {

    @StateObject private var auth = AuthStore()
    @StateObject private var environment = AppEnvironment()
    @StateObject private var consent = LegalConsent()
    @StateObject private var favorites = FavoritesStore()
    /// サーバーが答えたいいねの数。**詳細で押した数をホームにも出す**
    @StateObject private var likeCounts = LikeCountStore()
    /// 保存（ブックマーク）の控え。**いいねとは別の入れ物**
    @StateObject private var savedPhotos = SavedPhotosStore()
    @StateObject private var hidden = ModerationStore()
    @StateObject private var joinedAlbums = JoinedAlbumsStore()
    /// 「行きたい」スポット。**この端末にしか残らない**（サーバーに口が無い）
    @StateObject private var wishlist = WishlistStore()
    /// ストーリーの書きかけ。**この端末にだけ残る**（サーバーに口が無い）
    @StateObject private var storyDrafts = StoryDraftStore()
    /// 見たストーリー（輪の色）。**サーバーに口が無いので端末に覚える**
    @StateObject private var seenStories = SeenStoriesStore()
    @StateObject private var push = PushCenter()
    /// 短い知らせ（Web の `useToast`）。**1つだけ出す**
    @StateObject private var toasts = ToastCenter()
    /// **APNs のトークンは `UIApplicationDelegate` にしか返ってこない。**
    /// SwiftUI だけでは受け取れないので、この1本だけ UIKit を繋ぐ
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var configurationError: String? = nil

    init() {
        JourneyPhotoApp.configureImageCache()
        do {
            try AuthGateway.configure()
        } catch {
            // ここで落とさない。ログインが要らない画面（公開ギャラリー）は
            // 出せるので、**アプリを起動できなくする方が損**
            _configurationError = State(initialValue: String(describing: error))
        }
    }

    /// 一度見た写真は圏外でも出したい。
    ///
    /// `AsyncImage` は `URLSession.shared`（＝`URLCache.shared`）を使うので、
    /// ここを広げるだけで効く。**Web 側の Service Worker が画像を別の
    /// 入れ物に 80件だけ控えているのと同じ役目**（`public/sw.js`）。
    /// 端末側は容量で押し出してくれるので、件数ではなく容量で切る。
    private static func configureImageCache() {
        // Linux の corelibs は `diskPath` が必須。iOS では省略できる
        #if canImport(Darwin)
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        #else
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: nil
        )
        #endif
    }

    /// 「見せない」を公開一覧の側へ渡す。
    ///
    /// 出すところ（`PublicGalleryService`）で落とすので、ギャラリー・検索・
    /// 地図・近くの写真・お気に入りの**全部に一度に効く**。
    private func applyModeration() async {
        await environment.gallery.setHidden(
            userIds: hidden.blockedUserIds,
            photoIds: hidden.reportedPhotoIds
        )
    }

    /// 公開範囲を絞った写真の取り口を、公開一覧へ渡す。
    ///
    /// **ログアウトしたら外す。** 外さないと、次にこの端末を使う人の画面に
    /// 前の人あての「フォロワーのみ」が出る（控えも `setRestrictedLoader`
    /// が捨てる）。未ログインでは口そのものが 401 なので、入れない。
    private func applyRestrictedFeed() async {
        guard auth.userId != nil else {
            await environment.gallery.setRestrictedLoader(nil)
            return
        }
        let photos = environment.photos
        await environment.gallery.setRestrictedLoader { try await photos.restrictedFeed() }
    }

    /// いいねした写真をサーバーに合わせる。
    ///
    /// **取れた回だけ入れ替える。** 足すのではなく入れ替えるのは、
    /// 保存といいねが同じ入れ物を使っていた頃の端末に、**保存しただけの
    /// 写真の id が残っている**ため（足すだけだと出続ける）。
    ///
    /// **返ってくる間に人が替わっていたら書かない**（`replace(with:for:since:)`）。
    /// 書くと、前の人のいいねが次の人の控えに入る
    ///
    /// - Parameter mark: 控えを次の人に切り替えた直後（`use` の後、次の await の前）に取った `syncMark`。
    ///   **その後に押した分は残す**——起動直後にホームで押したいいねが、押す前の
    ///   一覧で消えていた
    private func syncLikes(since mark: LocalEdits.Mark) async {
        guard let owner = auth.userId else { return }
        let ids = try? await environment.social.myLikedPhotoIds()
        // **いまのログインとも照らす。** ストアはまだ前の人を指していることがある
        // （退会で控えを消した直後、`.task` が取り消される前に続きが戻る回）
        guard !Task.isCancelled, auth.userId == owner, let ids else { return }
        favorites.replace(with: ids, for: owner, since: mark)
    }

    /// 保存した写真をサーバーに合わせる。
    ///
    /// **取れた回だけ上書きする。** 圏外で空にすると、端末の控えごと
    /// 消えて「保存した写真が全部消えた」になる。
    /// ログアウトしたら控えは鍵ごと切り替わる（`use(userId:)`）ので、
    /// ここでは何もしない。
    private func syncSaves(since mark: LocalEdits.Mark) async {
        guard let owner = auth.userId else { return }
        let ids = try? await environment.saves.mySaves()
        guard !Task.isCancelled, auth.userId == owner, let ids else { return }
        savedPhotos.replace(with: ids, for: owner, since: mark)
    }

    var body: some Scene {
        WindowGroup {
            RootView(configurationError: configurationError)
                .environmentObject(auth)
                .environmentObject(environment)
                .environmentObject(consent)
                .environmentObject(favorites)
                .environmentObject(likeCounts)
                .environmentObject(savedPhotos)
                .environmentObject(hidden)
                .environmentObject(joinedAlbums)
                .environmentObject(wishlist)
                .environmentObject(storyDrafts)
                .environmentObject(seenStories)
                .environmentObject(push)
                .environmentObject(toasts)
                .task { await auth.restore() }
                // **ログイン状態が変わるたびに読み直す。** `.task` のままだと
                // 起動時に1回しか走らず、あとからログインした人には
                // **未ログインのときの鍵で読んだ控え**が見えたままになる
                // （同じ端末を別の人が使うと、その人のハートとブロックが
                //  こちらに出る——`FavoritesStore` が warn している事故そのもの）
                // 🔴 **投稿した本人でなくなったら、裏で送っている残りを捨てる**
                // （別の人のアカウントで前の人のストーリーを出さない）。
                // **ログインの確認が終わるまでは照らさない**——送り終えていない並びは
                // 端末から戻るので、起動直後の「まだ分からない（nil）」で捨てると、
                // 強制終了から戻した投稿が毎回消える。ログアウト（確認中→未ログイン）
                // は `userId` が nil のまま変わらないので、`state` で見る
                .task(id: auth.state) {
                    let stories = environment.stories
                    let auth = auth
                    let drafts = storyDrafts
                    StoryUploadCenter.shared.configure(
                        currentUserId: { auth.userId },
                        send: { job, record in
                            guard let ownerId = auth.userId else { throw APIError.notAuthenticated }
                            try await stories.post(job, ownerId: ownerId, record: record)
                        },
                        discardUpload: { key in await stories.discardUpload(key: key) },
                        // 起動し直して送り終えたら、その投稿の元の下書きを片づける
                        // （送っている間に保存し直した別の下書きは消さない）
                        clearDraft: { stamp in
                            if drafts.draft?.savedAt == stamp { drafts.clear() }
                        })
                    // 起動時に本人の ID が取れなかっただけのログアウト（`isSignedOutUncertain`）
                    // でも捨てない——通知の宛先と同じ扱い。捨てると、圏外で起動した
                    // だけで強制終了から戻した送信待ちが消え、「もう一度送る」も出ない
                    guard !auth.isResolving, !auth.isSignedOutUncertain else { return }
                    // **期限切れのログアウトでも捨てない**（同じ人が入り直せば送り直せる）。
                    // 別の人が入ったときは、その人の ID で `userChanged` が捨てる
                    if auth.userId == nil, auth.signedOutByExpiry { return }
                    StoryUploadCenter.shared.userChanged(to: auth.userId)
                }
                // **`userId` ではなく状態で見る。** 起動直後の確認中（unknown）も
                // ログアウト（signedOut）も `userId` は nil で、確認が
                // 「ログインしていない」に決まったときに走り直さない
                .task(id: auth.state) {
                    // 🔴 **限定写真の口は、`hidden.use` より先に差し替える。**
                    // `hidden.use` が数を進めると検索・ホーム・地図が公開一覧を
                    // 読み直す。差し替えが後だと、その読み直しが**前の人の口と控え**
                    // で行われ（ログアウト後は取れずに前の人の控えを返す）、
                    // 前の人あての「フォロワーのみ」が残ったままになる
                    await applyRestrictedFeed()
                    // **アカウントごとの控えは、ログイン状態が決まってから。**
                    // 先に読むと未ログインぶんが見える
                    favorites.use(userId: auth.userId)
                    savedPhotos.use(userId: auth.userId)
                    hidden.use(userId: auth.userId)
                    joinedAlbums.use(userId: auth.userId)
                    wishlist.use(userId: auth.userId)
                    storyDrafts.use(userId: auth.userId)
                    seenStories.use(userId: auth.userId)
                    // **通知の宛先も、人が変わったら預け直す**
                    // （外さないと、次にこの端末を使う人へ前の人あての
                    //  通知が届く）
                    AppDelegate.push = push
                    // **同期の印は最初の await の前に取る**（`LocalEdits`）。この後の
                    // 待ちの間に押したいいね・保存・ブロックを、同期の一覧で消さない
                    let likesMark = favorites.syncMark
                    let savesMark = savedPhotos.syncMark
                    let blocksFetch = hidden.beginBlockFetch()
                    // **確認中は通知の宛先に触らない。** まだ誰か分からないのに
                    // 「前の人の宛先が残っている」と見なして端末ごと外していた
                    // 起動時に本人の ID が取れなかっただけのログアウトも同じ
                    // （`AuthStore.isSignedOutUncertain`）
                    if !auth.isResolving && !auth.isSignedOutUncertain {
                        await push.use(userId: auth.userId)
                    }
                    await applyModeration()
                    await syncSaves(since: savesMark)
                    await syncLikes(since: likesMark)
                    // ログイン中なら、ブロック一覧をサーバーに合わせる
                    // （同期を始めた後にブロック・解除した分は残す・後に始まった取得の答えは上書きしない——`blocksFetch`）
                    if let owner = auth.userId {
                        let blocks = try? await environment.moderation.blocks()
                        if !Task.isCancelled, auth.userId == owner, let blocks {
                            hidden.replaceBlocked(with: blocks.blockedIds, for: owner, fetch: blocksFetch)
                            await applyModeration()
                        }
                    }
                }
        }
    }
}
