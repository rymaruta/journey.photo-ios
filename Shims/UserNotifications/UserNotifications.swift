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
}

public protocol UNUserNotificationCenterDelegate: AnyObject {}

public final class UNNotificationContent {
    public var userInfo: [AnyHashable: Any] { [:] }
}
public final class UNNotification {
    public var request: UNNotificationRequest { UNNotificationRequest() }
}
public final class UNNotificationRequest {
    public var content: UNNotificationContent { UNNotificationContent() }
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
