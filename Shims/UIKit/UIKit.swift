// UIKit の模型（Linux で型検査するためだけのもの）。
@_exported import SwiftUI

open class UIViewController {}
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
