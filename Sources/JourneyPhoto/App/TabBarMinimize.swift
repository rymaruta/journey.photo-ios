import SwiftUI

/// 下の札（タブバー）を、下へ送ったときに縮める（2026-11-14 判断・人間工学の点検 7）。
///
/// 写真が主役（板の決まり）なので、写真を流して見るホームと探すの 2 つのタブだけ、下へ送ると札を縮めて写真の面を広げる。
/// 上へ戻すか、縮んだ札を押すと元に戻る（OS の動き）。地図・マイページは縮めない（地図は送りで動かない・マイページは札で行き来する）。
/// iOS 26 から（`tabBarMinimizeBehavior`）。iOS 17〜25 は今のまま
enum TabBarMinimize {

    /// このタブで、下へ送ったときに札を縮めるか
    static func minimizesOnScrollDown(_ tab: RootView.Tab) -> Bool {
        switch tab {
        case .home, .search: return true
        case .post, .map, .mypage: return false
        }
    }
}

/// `RootView` の TabView に付ける。選んでいるタブで縮めるかを替える
struct TabBarMinimizeOnScroll: ViewModifier {
    let tab: RootView.Tab

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(TabBarMinimize.minimizesOnScrollDown(tab) ? .onScrollDown : .never)
        } else {
            content
        }
    }
}
