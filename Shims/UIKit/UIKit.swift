// UIKit の模型（Linux で型検査するためだけのもの）。
@_exported import SwiftUI

open class UIViewController {}

/// `@UIApplicationDelegateAdaptor` で繋ぐ側の模型。
public protocol UIApplicationDelegate: NSObjectProtocolShim {}
public extension UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}

open class UIApplication {
    /// 本物と同じ型を使う。**`[AnyHashable: Any]` で受けると別の関数になり、
    /// iOS では呼ばれないまま（コンパイルは通る）**——模型を緩く作ると、
    /// 実機で「何も起きない」形の間違いを作る
    public struct LaunchOptionsKey: Hashable {}
    public static let shared = UIApplication()
    public func registerForRemoteNotifications() {}
    public func unregisterForRemoteNotifications() {}
    public var applicationIconBadgeNumber: Int = 0
}
open class UINavigationController: UIViewController {}

public protocol UINavigationControllerDelegate: AnyObject {}
public protocol UIImagePickerControllerDelegate: AnyObject {}

open class UIImagePickerController: UIViewController {
    public enum SourceType { case camera, photoLibrary }
    public enum CameraCaptureMode { case photo, video }
    public struct InfoKey: Hashable {
        public static let originalImage = InfoKey()
        public static let editedImage = InfoKey()
    }
    public var sourceType: SourceType = .photoLibrary
    public var cameraCaptureMode: CameraCaptureMode = .photo
    public weak var delegate: (UIImagePickerControllerDelegate & UINavigationControllerDelegate)?
    public static func isSourceTypeAvailable(_ t: SourceType) -> Bool { false }
    public override init() {}
}

public protocol UIViewControllerRepresentable: View {
    associatedtype UIViewControllerType: UIViewController
    associatedtype Coordinator = Void
    func makeUIViewController(context: Context) -> UIViewControllerType
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context)
    func makeCoordinator() -> Coordinator
    typealias Context = UIViewControllerRepresentableContext<Self>
}
extension UIViewControllerRepresentable {
    public var body: Never { fatalError("模型") }
}
public struct UIViewControllerRepresentableContext<R: UIViewControllerRepresentable> {
    public var coordinator: R.Coordinator { fatalError("模型") }
}
