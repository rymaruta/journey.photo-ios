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
    @StateObject private var hidden = ModerationStore()
    @StateObject private var joinedAlbums = JoinedAlbumsStore()
    /// 「行きたい」スポット。**この端末にしか残らない**（サーバーに口が無い）
    @StateObject private var wishlist = WishlistStore()
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
    /// 地図・関連写真・お気に入りの**全部に一度に効く**。
    private func applyModeration() async {
        await environment.gallery.setHidden(
            userIds: hidden.blockedUserIds,
            photoIds: hidden.reportedPhotoIds
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(configurationError: configurationError)
                .environmentObject(auth)
                .environmentObject(environment)
                .environmentObject(consent)
                .environmentObject(favorites)
                .environmentObject(hidden)
                .environmentObject(joinedAlbums)
                .environmentObject(wishlist)
                .environmentObject(push)
                .environmentObject(toasts)
                .task { await auth.restore() }
                // **ログイン状態が変わるたびに読み直す。** `.task` のままだと
                // 起動時に1回しか走らず、あとからログインした人には
                // **未ログインのときの鍵で読んだ控え**が見えたままになる
                // （同じ端末を別の人が使うと、その人のハートとブロックが
                //  こちらに出る——`FavoritesStore` が warn している事故そのもの）
                .task(id: auth.userId) {
                    // **アカウントごとの控えは、ログイン状態が決まってから。**
                    // 先に読むと未ログインぶんが見える
                    favorites.use(userId: auth.userId)
                    hidden.use(userId: auth.userId)
                    joinedAlbums.use(userId: auth.userId)
                    wishlist.use(userId: auth.userId)
                    // **通知の宛先も、人が変わったら預け直す**
                    // （外さないと、次にこの端末を使う人へ前の人あての
                    //  通知が届く）
                    AppDelegate.push = push
                    await push.use(userId: auth.userId)
                    await applyModeration()
                    // ログイン中なら、ブロック一覧をサーバーに合わせる
                    if auth.userId != nil {
                        let blocks = try? await environment.moderation.blocks()
                        if let blocks {
                            hidden.replaceBlocked(with: blocks.blockedIds)
                            await applyModeration()
                        }
                    }
                }
        }
    }
}
