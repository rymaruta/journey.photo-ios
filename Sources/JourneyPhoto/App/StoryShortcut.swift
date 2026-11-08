import SwiftUI

/// アプリのアイコン長押しの「ストーリーを撮る」（札 #500）を、画面（`RootView`）へ渡す口。
///
/// 起動の途中で届くので**持ち越す**（`pending`）。受けてよいときだけ開く（`StoryCameraRules.canOpenCamera`）。
/// **タブの選択（`selection`）には触らない**（#435: 起動直後に選択が戻される不具合の原因が未特定のため、
/// 起動直後の画面の切り替えと競わせない）。
@MainActor
final class StoryShortcutCenter: ObservableObject {
    static let shared = StoryShortcutCenter()
    @Published private(set) var requests = 0
    private(set) var pending = false

    /// 依頼を持ち越す。**持ち越し中の2回目は数えない**(冷えた起動は `AppDelegate` と場面の係の両方から届く)
    func request() {
        guard !pending else { return }
        pending = true
        requests += 1
    }

    /// 持ち越しを1回だけ受け取る（二重に開かない）
    func take() -> Bool {
        defer { pending = false }
        return pending
    }
}

/// `RootView` の修飾子の鎖を伸ばさないよう、1つにまとめた受け口
struct StoryShortcutOpener: ViewModifier {
    @ObservedObject private var center = StoryShortcutCenter.shared
    let signedIn: Bool
    /// 投稿・お知らせなど、ほかの画面が出ているか
    let anotherScreenShown: () -> Bool
    let open: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: center.requests) { _, _ in
                Task { await deliver() }
            }
            .task(id: signedIn) { await deliver() }
    }

    /// 受けてよくなるまで持ち越す（最長およそ12秒。過ぎたら捨てる——何分も経って突然開かない）
    @MainActor
    private func deliver() async {
        guard center.pending else { return }
        let wait = StoryCameraRules.settleWait(sinceLaunch: Date().timeIntervalSince(StoryCameraRules.launchedAt))
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        for _ in 0..<40 {
            guard center.pending, !Task.isCancelled else { return }
            if StoryCameraRules.canOpenCamera(signedIn: signedIn, tabsShown: true,
                                              anotherScreenShown: anotherScreenShown()) {
                if center.take() { open() }
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        _ = center.take()
    }
}
