import SwiftUI

@main
struct JourneyPhotoApp: App {

    @StateObject private var auth = AuthStore()
    @StateObject private var environment = AppEnvironment()
    @State private var configurationError: String? = nil

    init() {
        do {
            try AuthGateway.configure()
        } catch {
            // ここで落とさない。ログインが要らない画面（公開ギャラリー）は
            // 出せるので、**アプリを起動できなくする方が損**
            _configurationError = State(initialValue: String(describing: error))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(configurationError: configurationError)
                .environmentObject(auth)
                .environmentObject(environment)
                .task { await auth.restore() }
        }
    }
}
