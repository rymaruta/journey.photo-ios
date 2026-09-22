import Foundation
import Combine

/// 下の札を外から切り替える道（見出しの自分のアイコン → マイページ）。
///
/// **押した回数で伝える。** 真偽値にすると、マイページから別の札へ移って
/// もう一度押したときに「変わっていない」と見なされて効かない
/// （`NotificationRouter` / `MissionRouter` と同じ理由）。
@MainActor
final class TabRouter: ObservableObject {

    static let shared = TabRouter()

    @Published private(set) var myPageRequests = 0

    func openMyPage() { myPageRequests += 1 }
}
