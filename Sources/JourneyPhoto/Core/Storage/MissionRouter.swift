import Foundation
import Combine

/// 「今日のテーマに参加する」を押したことを、投稿画面を持っている
/// `RootView` まで届ける道。
///
/// **押した回数で伝える。** 真偽値にすると、投稿をやめて同じ日に
/// もう一度押したときに「変わっていない」と見なされて効かなくなる
/// （`NotificationRouter` が同じ理由で回数にしてある）。
@MainActor
final class MissionRouter: ObservableObject {

    static let shared = MissionRouter()

    @Published private(set) var requests = 0
    /// 最後に押されたテーマのタグ
    private(set) var tag: String?

    func join(tag: String) {
        self.tag = tag
        requests += 1
    }
}
