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

// MARK: - 描画（写真に文字を焼き込むために要るぶんだけ）
//
// **本物の UIKit の同じ名前に合わせてある。** iOS では本物が使われるので、
// ここは「Linux で型検査を通すための形」だけ。中身は何も描かない。

// `UIImage` は SwiftUI 側の模型（`UIImageShim`）が既に名乗っている。
// 描画に要るぶんだけ足す
extension UIImageShim {
    public var size: CGSize { CGSize(width: 0, height: 0) }
    public func draw(in rect: CGRect) {}
}

public final class UIColor {
    public static let white = UIColor()
    public static let black = UIColor()
    public static let clear = UIColor()
    public init() {}
    public init(white: Double, alpha: Double) {}
    public init(red: Double, green: Double, blue: Double, alpha: Double) {}
    public func withAlphaComponent(_ alpha: Double) -> UIColor { self }
    public func setFill() {}
}

public final class UIFont {
    public struct Weight {
        public static let regular = Weight(), medium = Weight(), semibold = Weight(), bold = Weight(), heavy = Weight()
    }
    public static func systemFont(ofSize size: Double, weight: Weight) -> UIFont { UIFont() }
    public init() {}
    public init?(name: String, size: Double) {}
}

/// 描き込み先（回して描くのに使うぶんだけ）
public final class CGContext {
    public func saveGState() {}
    public func restoreGState() {}
    public func translateBy(x: Double, y: Double) {}
    public func rotate(by angle: Double) {}
}

public struct UIGraphicsImageRendererContext {
    public var cgContext: CGContext { CGContext() }
}

public final class UIGraphicsImageRendererFormat {
    public init() {}
    public var scale: Double = 3
}

public final class UIGraphicsImageRenderer {
    public init(size: CGSize) {}
    public init(size: CGSize, format: UIGraphicsImageRendererFormat) {}
    public func jpegData(withCompressionQuality quality: Double,
                         actions: (UIGraphicsImageRendererContext) -> Void) -> Data {
        actions(UIGraphicsImageRendererContext())
        return Data()
    }
}

public func UIRectFill(_ rect: CGRect) {}

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("font")
    public static let foregroundColor = NSAttributedString.Key("foregroundColor")
    public static let strokeColor = NSAttributedString.Key("strokeColor")
    public static let strokeWidth = NSAttributedString.Key("strokeWidth")
}

extension NSString {
    public func size(withAttributes attrs: [NSAttributedString.Key: Any]?) -> CGSize {
        CGSize(width: 0, height: 0)
    }
    public func draw(at point: CGPoint, withAttributes attrs: [NSAttributedString.Key: Any]?) {}
}
