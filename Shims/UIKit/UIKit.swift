// UIKit の模型（Linux で型検査するためだけのもの）。
@_exported import SwiftUI
import ImageIO

open class UIViewController {
    /// 本物は読み取りだけ（このコントローラが出しているもの）
    open var presentedViewController: UIViewController? { nil }
}

/// 画面の場。本物は `UIResponder`（NSObject）の子なので Set に入る
open class UIScene: Hashable {
    public static func == (lhs: UIScene, rhs: UIScene) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
open class UIWindowScene: UIScene {
    public var windows: [UIWindow] { [] }
}
open class UIWindow {
    public var isKeyWindow: Bool { false }
    public var rootViewController: UIViewController?
}

/// `@UIApplicationDelegateAdaptor` で繋ぐ側の模型。
public protocol UIApplicationDelegate: NSObjectProtocolShim {}
public extension UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {}
    /// 背景の URLSession の転送が終わって起こされた（本物と同じ形）
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {}
}

open class UIApplication {
    /// 本物と同じ型を使う。**`[AnyHashable: Any]` で受けると別の関数になり、
    /// iOS では呼ばれないまま（コンパイルは通る）**——模型を緩く作ると、
    /// 実機で「何も起きない」形の間違いを作る
    public struct LaunchOptionsKey: Hashable {}
    public static let shared = UIApplication()
    /// このアプリの設定画面を開く URL（本物と同じ名前）
    public static let openSettingsURLString = "app-settings:"
    public func registerForRemoteNotifications() {}
    public func unregisterForRemoteNotifications() {}
    public var connectedScenes: Set<UIScene> { [] }
    public var applicationIconBadgeNumber: Int = 0
    /// 前面に居るか（本物と同じ名前）。模型はいつも前面
    public enum State: Int { case active, inactive, background }
    public var applicationState: State { .active }
    /// 裏に回っても少しだけ続けさせてもらう（本物と同じ形）
    public func beginBackgroundTask(withName taskName: String?,
                                    expirationHandler handler: (@MainActor @Sendable () -> Void)? = nil) -> UIBackgroundTaskIdentifier {
        .invalid
    }
    public func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {}
}

public struct UIBackgroundTaskIdentifier: Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let invalid = UIBackgroundTaskIdentifier(rawValue: 0)
}

/// 端末の写真に保存する（本物と同じ名前・引数の数）。模型は何もしない。
/// 本物の3つ目は `Selector?`——Linux に無い型なので、`nil` だけ渡す前提で `Any?` にしてある
public func UIImageWriteToSavedPhotosAlbum(_ image: UIImage, _ completionTarget: Any?,
                                           _ completionSelector: Any?, _ contextInfo: UnsafeMutableRawPointer?) {}
open class UINavigationController: UIViewController {}

public protocol UINavigationControllerDelegate: AnyObject {}
public protocol UIImagePickerControllerDelegate: AnyObject {}

open class UIImagePickerController: UIViewController {
    public enum SourceType { case camera, photoLibrary }
    public enum CameraCaptureMode { case photo, video }
    /// 本物は文字列の鍵（`RawRepresentable`）。**値で見分ける**——中身の無い struct だと
    /// どの鍵も同じに見え、取り違えても模型では通ってしまう
    public struct InfoKey: Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let originalImage = InfoKey(rawValue: "UIImagePickerControllerOriginalImage")
        public static let editedImage = InfoKey(rawValue: "UIImagePickerControllerEditedImage")
        /// 撮った1枚の撮影情報（`{Exif}`・`{TIFF}` などの辞書。カメラのときだけ）
        public static let mediaMetadata = InfoKey(rawValue: "UIImagePickerControllerMediaMetadata")
    }
    public var sourceType: SourceType = .photoLibrary
    public var cameraCaptureMode: CameraCaptureMode = .photo
    public weak var delegate: (UIImagePickerControllerDelegate & UINavigationControllerDelegate)?
    public static func isSourceTypeAvailable(_ t: SourceType) -> Bool { false }
    public override init() {}
}

/// クリップボード（本物と同じ形・中身は無い）
public final class UIPasteboard {
    public static let general = UIPasteboard()
    public var string: String?
    public struct OptionsKey: Hashable {
        public static let localOnly = OptionsKey(), expirationDate = OptionsKey()
    }
    public func setItems(_ items: [[String: Any]], options: [OptionsKey: Any] = [:]) {}
}

public enum CGBlendMode { case normal }

/// 書体の記述（serif＝New York を選ぶのに使うぶんだけ）
public final class UIFontDescriptor {
    public struct SystemDesign { public static let serif = SystemDesign(), `default` = SystemDesign() }
    public init() {}
    public func withDesign(_ design: SystemDesign) -> UIFontDescriptor? { self }
}

/// 共有の画面（本物と同じ形・中身は無い）
open class UIActivityViewController: UIViewController {
    public var completionWithItemsHandler: ((Any?, Bool, [Any]?, Error?) -> Void)?
    public init(activityItems: [Any], applicationActivities: [Any]?) {}
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
/// 本物と同じく、受け手を持たない包みは `makeCoordinator` を書かなくてよい
extension UIViewControllerRepresentable where Coordinator == Void {
    public func makeCoordinator() {}
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
    public init?(named: String) { return nil }
    public func draw(in rect: CGRect) {}
    public func draw(in rect: CGRect, blendMode: CGBlendMode, alpha: Double) {}
    public enum RenderingMode { case alwaysOriginal, alwaysTemplate }
    public func withTintColor(_ color: UIColor, renderingMode: RenderingMode) -> UIImageShim { self }
    /// 縮めて展開した画像（本物と同じ・iOS 15〜）
    public func preparingThumbnail(of size: CGSize) -> UIImageShim? { nil }
    /// 描いた画像から作る（写真の編集の見本・本物と同じ）
    public init(cgImage: CGImage) { self.init() }
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
    /// 本物は SwiftUI の `Color` から作る（`UIColor(_ color: Color)`）
    public init<T>(_ color: T) {}
    public func getRed(_ red: inout CGFloat, green: inout CGFloat, blue: inout CGFloat,
                       alpha: inout CGFloat) -> Bool { false }
}

public final class UIFont {
    public struct Weight {
        public static let regular = Weight(), medium = Weight(), semibold = Weight(), bold = Weight(), heavy = Weight()
    }
    public static func systemFont(ofSize size: Double, weight: Weight) -> UIFont { UIFont() }
    public static func monospacedSystemFont(ofSize size: Double, weight: Weight) -> UIFont { UIFont() }
    public static func monospacedDigitSystemFont(ofSize size: Double, weight: Weight) -> UIFont { UIFont() }
    public init() {}
    public init?(name: String, size: Double) {}
    public init(descriptor: UIFontDescriptor, size: Double) {}
    public var fontDescriptor: UIFontDescriptor { UIFontDescriptor() }
    /// 1行の高さ（複数行の焼き込みで行を送る）
    public var lineHeight: Double { 0 }
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
    /// 描いた絵（メダルの表・裏の貼り絵・本物と同じ）
    public func image(actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        actions(UIGraphicsImageRendererContext())
        return UIImage()
    }
}

public func UIRectFill(_ rect: CGRect) {}

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("font")
    public static let foregroundColor = NSAttributedString.Key("foregroundColor")
    public static let kern = NSAttributedString.Key("kern")
    public static let strokeColor = NSAttributedString.Key("strokeColor")
    public static let strokeWidth = NSAttributedString.Key("strokeWidth")
    public static let paragraphStyle = NSAttributedString.Key("paragraphStyle")
}

/// 行の揃え（複数行の焼き込み）。本物は UIKit が持つ
public enum NSTextAlignment { case left, center, right, justified, natural }

open class NSParagraphStyle: NSObject {
    open var alignment: NSTextAlignment { .natural }
}

open class NSMutableParagraphStyle: NSParagraphStyle {
    private var storedAlignment: NSTextAlignment = .natural
    open override var alignment: NSTextAlignment {
        get { storedAlignment }
        set { storedAlignment = newValue }
    }
}

public struct NSStringDrawingOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let usesLineFragmentOrigin = NSStringDrawingOptions(rawValue: 1)
    /// 枠に収まらない最後の行を「…」で切る（本物と同じ）
    public static let truncatesLastVisibleLine = NSStringDrawingOptions(rawValue: 2)
}

/// 描き込みの文脈（使わない・本物と同じ形のため）
public final class NSStringDrawingContext {}

extension NSAttributedString {
    public func boundingRect(with size: CGSize, options: NSStringDrawingOptions,
                             context: NSStringDrawingContext?) -> CGRect { .zero }
    public func draw(with rect: CGRect, options: NSStringDrawingOptions, context: NSStringDrawingContext?) {}
}

extension NSString {
    public func size(withAttributes attrs: [NSAttributedString.Key: Any]?) -> CGSize {
        CGSize(width: 0, height: 0)
    }
    public func draw(at point: CGPoint, withAttributes attrs: [NSAttributedString.Key: Any]?) {}
}
