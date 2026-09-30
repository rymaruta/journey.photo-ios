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
        // **ベルの数も合わせる。** バナーだけ出してベルが古い数のままだと、
        // 前面に戻るかお知らせを開くまで届いたことが数に出なかった。
        // 見頃のお知らせ（端末の中の予約）はお知らせの出来事ではないので数え直さない
        if (notification.request.content.userInfo["kind"] as? String) != SeasonReminder.kind {
            await MainActor.run { NotificationRouter.shared.noteArrival() }
        }
        return [.banner, .list, .sound, .badge]
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
        // 見頃のお知らせ（端末の中で予約したもの）はお知らせ画面の出来事ではない——開くだけにする
        if (response.notification.request.content.userInfo["kind"] as? String) == SeasonReminder.kind { return }
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
    /// 押されたが、まだ画面が受け取っていない。
    ///
    /// **数の変化だけに頼らない。** 起動の途中（冷えた状態から押した回）や
    /// 規約の同意画面が出ている間は、数を見ている画面がまだ居ないので、
    /// 変化を見逃して押したことが落ちていた。画面が出てきたときに取りに来る
    private(set) var hasPendingActivity = false
    /// アプリを開いている間に届いた通知の数（ベルの数え直しの合図）
    @Published private(set) var arrivals = 0

    func openActivity() {
        hasPendingActivity = true
        openActivityRequests += 1
    }

    /// 押された分を受け取る。**受け取るのは1回だけ**（2回目は false）
    func takePendingActivity() -> Bool {
        defer { hasPendingActivity = false }
        return hasPendingActivity
    }

    func noteArrival() { arrivals += 1 }

    /// お知らせを既読にできた回の数（ベルを 0 にする合図）。
    /// **閉じたときの数え直しが圏外で落ちても、ベルが読む前の数のまま残らない**
    @Published private(set) var readMarks = 0
    /// 既読にした人。**替わった後に前の人の合図で次の人のベルを消さない**
    private(set) var readOwner: String?
    func noteRead(owner: String?) {
        readOwner = owner
        readMarks += 1
    }
}

/// いま何かが画面の上に出ているか（シート・確認の枠）。
///
/// **SwiftUI はシートを1つずつしか出せない。** 出ている間にお知らせを
/// 出そうとしても黙って無視されるので、閉じられたかをここで確かめる。
/// **読むだけで、閉じはしない**——書きかけを抱えたシート（投稿・ストーリー・
/// 写真の編集）を勝手に閉じると、書いたものが消える
@MainActor
enum ModalProbe {
    static func isPresenting() -> Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            // **キーの窓だけに絞らない。** 前面に戻る途中などでキーが外れている
            // 間に「何も出ていない」と答えると、出せないシートを true にしてしまう
            for window in windowScene.windows {
                if window.rootViewController?.presentedViewController != nil { return true }
            }
        }
        return false
    }
}
