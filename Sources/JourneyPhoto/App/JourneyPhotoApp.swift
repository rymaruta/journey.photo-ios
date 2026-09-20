import SwiftUI

@main
struct JourneyPhotoApp: App {

    @StateObject private var auth = AuthStore()
    @StateObject private var environment = AppEnvironment()
    @StateObject private var consent = LegalConsent()
    @StateObject private var favorites = FavoritesStore()
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
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(configurationError: configurationError)
                .environmentObject(auth)
                .environmentObject(environment)
                .environmentObject(consent)
                .environmentObject(favorites)
                .task {
                    await auth.restore()
                    // **ハートはアカウントごと。** ログイン状態が決まってから
                    // 読み込む（先に読むと未ログインぶんが見える）
                    favorites.use(userId: auth.userId)
                }
        }
    }
}
