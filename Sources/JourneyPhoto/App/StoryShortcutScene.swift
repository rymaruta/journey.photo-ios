#if canImport(Darwin)
import UIKit

/// アイコン長押しの項目を受ける場面の係（札 #500）。
///
/// SwiftUI の `App` には受け口が無いので、`AppDelegate.application(_:configurationForConnecting:options:)` で
/// この型を場面の係に指定する。**起動のときに選ばれた項目**は `options.shortcutItem`（そこで拾う）、
/// **起動中に選ばれた項目**はこの型の `windowScene(_:performActionFor:)` に来る。
final class StorySceneDelegate: UIResponder, UIWindowSceneDelegate {

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let handled = shortcutItem.type == StoryCameraRules.shortcutType
        if handled { Task { @MainActor in StoryShortcutCenter.shared.request() } }
        completionHandler(handled)
    }
}
#endif
