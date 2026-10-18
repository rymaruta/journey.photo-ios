import Foundation

// 本物の UIKit の色選び（`UIColorPickerViewController`）の模型（Linux のビルド用・2026-10-16）。
// 既存の shim ファイルは別の枝が触ることがあるので、別ファイルに置く。

/// 本物は `NSObjectProtocol` で、下の2つはどちらも任意の口
public protocol UIColorPickerViewControllerDelegate: AnyObject {}

/// 端末の色選びの画面（プロフィールの色の「自由に選ぶ」）
open class UIColorPickerViewController: UIViewController {
    public var selectedColor: UIColor = .white
    public var supportsAlpha: Bool = true
    public weak var delegate: UIColorPickerViewControllerDelegate?
    public override init() {}
}

// 色選びを UIKit で直接 modal に出すのに要る口（2026-10-16・スポイトで落ちる件）

/// 出し方（本物と同じ名前の一部）
public enum UIModalPresentationStyle { case automatic, fullScreen, pageSheet, formSheet, popover }

/// 本物は `NSObjectProtocol`。`presentationControllerDidDismiss(_:)` は任意の口
public protocol UIAdaptivePresentationControllerDelegate: AnyObject {}

open class UIPresentationController {
    public weak var delegate: UIAdaptivePresentationControllerDelegate?
}

open class UIPopoverPresentationController: UIPresentationController {
    public var sourceView: UIView?
    public var sourceRect: CGRect = .zero
}

extension UIViewController {
    /// 本物は暗黙に開く `UIView!`。模型は毎回作る
    public var view: UIView! { UIView() }
    public var presentingViewController: UIViewController? { nil }
    public var isBeingDismissed: Bool { false }
    public var modalPresentationStyle: UIModalPresentationStyle {
        get { .automatic }
        set {}
    }
    public var presentationController: UIPresentationController? { nil }
    public var popoverPresentationController: UIPopoverPresentationController? { nil }
    public func present(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {}
    public func dismiss(animated: Bool, completion: (() -> Void)? = nil) {}
}
