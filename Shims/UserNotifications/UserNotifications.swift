// UserNotifications の模型（Linux で型検査を通すためだけのもの）。
import Foundation

public struct UNAuthorizationOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 2)
}

public enum UNAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case denied = 1
    case authorized = 2
    case provisional = 3
    case ephemeral = 4
}

public final class UNNotificationSettings: @unchecked Sendable {
    public var authorizationStatus: UNAuthorizationStatus { .notDetermined }
}

public final class UNUserNotificationCenter: @unchecked Sendable {
    public static func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }
    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { false }
    public func notificationSettings() async -> UNNotificationSettings { UNNotificationSettings() }
    public var delegate: UNUserNotificationCenterDelegate?
    /// iOS 16 以降の口（`applicationIconBadgeNumber` は iOS 17 で非推奨）
    public func setBadgeCount(_ count: Int) async throws {}
    public func removeAllDeliveredNotifications() {}
    public func add(_ request: UNNotificationRequest) async throws {}
    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}

public protocol UNUserNotificationCenterDelegate: AnyObject {}

public class UNNotificationContent {
    public init() {}
    public var userInfo: [AnyHashable: Any] { [:] }
}
/// 端末の中で予約する通知の中身（見頃のお知らせ）
public final class UNMutableNotificationContent: UNNotificationContent {
    public override init() {}
    public var title: String = ""
    public var body: String = ""
    public var sound: UNNotificationSound?
    private var info: [AnyHashable: Any] = [:]
    public override var userInfo: [AnyHashable: Any] { get { info } set { info = newValue } }
}
public final class UNNotificationSound: @unchecked Sendable {
    public static let `default` = UNNotificationSound()
}
public class UNNotificationTrigger {}
public final class UNCalendarNotificationTrigger: UNNotificationTrigger {
    public let dateComponents: DateComponents
    public let repeats: Bool
    public init(dateMatching dateComponents: DateComponents, repeats: Bool) {
        self.dateComponents = dateComponents
        self.repeats = repeats
    }
}
public final class UNNotification {
    public var request: UNNotificationRequest { UNNotificationRequest() }
}
public final class UNNotificationRequest {
    public let identifier: String
    public let content: UNNotificationContent
    public let trigger: UNNotificationTrigger?
    init() { identifier = ""; content = UNNotificationContent(); trigger = nil }
    public init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
    }
}
public final class UNNotificationResponse {
    public var notification: UNNotification { UNNotification() }
}
public struct UNNotificationPresentationOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let banner = UNNotificationPresentationOptions(rawValue: 1 << 0)
    public static let list = UNNotificationPresentationOptions(rawValue: 1 << 1)
    public static let sound = UNNotificationPresentationOptions(rawValue: 1 << 2)
    public static let badge = UNNotificationPresentationOptions(rawValue: 1 << 3)
}
