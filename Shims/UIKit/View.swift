// UIView と、それを SwiftUI に置く包みの模型（2026-10-09・「作例を重ねて撮る」のカメラの映像）。
// 既存の UIKit.swift は別の枝が触ることがあるので、別ファイルに置く。
//
// 本物の UIKit は QuartzCore（`CALayer`）を再輸出する。同じ見え方にする
@_exported import QuartzCore
import SwiftUI

/// 画面の部品（本物と同じ名前）。**`layerClass` を上書きすると、その層の型で作られる**
/// （カメラの映像は `AVCaptureVideoPreviewLayer` を層にした UIView に出す）
open class UIView {
    public init() {}
    public init(frame: CGRect) {}
    /// 本物は読み取りだけの class プロパティ（上書きして層の型を替える）
    open class var layerClass: AnyClass { CALayer.self }
    /// 本物は `layerClass` の型で作られる。模型は作るだけ
    open var layer: CALayer { CALayer() }
    open var bounds: CGRect = .zero
    open var backgroundColor: UIColor?
    /// 指を受けるか（本物の既定は true）
    open var isUserInteractionEnabled: Bool = true
    open func layoutSubviews() {}
}

public protocol UIViewRepresentable: View {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void
    func makeUIView(context: Context) -> UIViewType
    func updateUIView(_ uiView: UIViewType, context: Context)
    func makeCoordinator() -> Coordinator
    typealias Context = UIViewRepresentableContext<Self>
}
extension UIViewRepresentable {
    public var body: Never { fatalError("模型") }
}
/// 本物と同じく、受け手を持たない包みは `makeCoordinator` を書かなくてよい
extension UIViewRepresentable where Coordinator == Void {
    public func makeCoordinator() {}
}
public struct UIViewRepresentableContext<R: UIViewRepresentable> {
    public var coordinator: R.Coordinator { fatalError("模型") }
}
