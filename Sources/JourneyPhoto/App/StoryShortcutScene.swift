#if canImport(Darwin)
import UIKit

/// アイコン長押しの項目を受ける場面の係(札 #500)。
///
/// SwiftUI の `App` には受け口が無いので、`AppDelegate.application(_:configurationForConnecting:options:)` で
/// この型を場面の係に指定する(SwiftUI + `UIApplicationDelegateAdaptor` で長押しの項目を受ける定石の形。
/// `UISceneConfiguration(name: nil, sessionRole:)` の `delegateClass` に指す)。
///
/// 届く道は3つあり、**どれが来ても同じ依頼になる**(`StoryShortcutCenter.request` は、持ち越し中の2回目を数えない):
/// - 冷えた起動: `AppDelegate` の `options.shortcutItem` と、ここの `scene(_:willConnectTo:options:)` の `connectionOptions.shortcutItem`
/// - 起動中(裏から戻る): `windowScene(_:performActionFor:completionHandler:)`
final class StorySceneDelegate: UIResponder, UIWindowSceneDelegate {

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem, item.type == StoryCameraRules.shortcutType {
            Task { @MainActor in StoryShortcutCenter.shared.request() }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let handled = shortcutItem.type == StoryCameraRules.shortcutType
        if handled { Task { @MainActor in StoryShortcutCenter.shared.request() } }
        completionHandler(handled)
    }
}
#endif
