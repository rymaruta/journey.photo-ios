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
