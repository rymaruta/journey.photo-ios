import UIKit
import UserNotifications

/// UIKit を繋ぐのはここ1本だけ。
///
/// **APNs のトークンは `UIApplicationDelegate` にしか返ってこない。**
/// SwiftUI の `App` には受け口が無いので、`@UIApplicationDelegateAdaptor` で
/// この1つだけ繋ぐ（画面まわりは全部 SwiftUI のまま）。
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// アプリ本体が持っている受け口。**`AppDelegate` は SwiftUI の
    /// `@StateObject` を作れない**ので、起動後に本体から渡してもらう。
    /// 渡る前に APNs が返ってきた回のために、トークンは取っておく。
    nonisolated(unsafe) static var push: PushCenter? {
        didSet {
            guard let pending = pendingToken, let push else { return }
            pendingToken = nil
            Task { @MainActor in push.accept(deviceToken: pending) }
        }
    }
    nonisolated(unsafe) private static var pendingToken: Data?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // **押したときの行き先のために、自分を受け手にしておく。**
        // 許可を取るのは設定画面（`PushCenter.enable`）——起動時に聞かない
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if let push = Self.push {
            Task { @MainActor in push.accept(deviceToken: deviceToken) }
        } else {
            Self.pendingToken = deviceToken
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // 実機以外では必ずここに来る（シミュレータは APNs に繋がらない）
        Task { @MainActor in Self.push?.acceptFailure(error) }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// **アプリを開いている間も出す。** 出さないと、見ている画面と関係のない
    /// 出来事（別の写真へのコメント）に気づけない。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    /// 通知を押した。**行き先はお知らせ画面**。
    ///
    /// 写真の個別画面へ直接飛ばすには写真そのものを引く必要があり、
    /// 圏外や削除済みだと**押しても何も起きない**に落ちる。お知らせ画面は
    /// どの種類の通知でも意味が通り、そこから1タップで目的地へ行ける。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { NotificationRouter.shared.openActivity() }
    }
}

/// 通知を押したときに、どの画面へ行くか。
///
/// **画面の外から画面を動かす唯一の口**。`RootView` がこれを見てタブを変える。
@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()
    /// 押されるたびに増える。**真偽値にしない**——2回続けて押したときに
    /// 「変わっていない」と見なされて2回目が効かなくなる
    @Published private(set) var openActivityRequests = 0
    func openActivity() { openActivityRequests += 1 }
}
