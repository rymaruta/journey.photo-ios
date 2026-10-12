import SwiftUI

/// シートの中の写真の一覧を、**その画面が出たとき**にブロック／通報で絞る。
///
/// 🔴 地図のピンの一覧・近くの写真・人のページの地図のシートは、渡された
/// 写真をそのまま描いていた。シートの中の詳細で持ち主をブロックして戻っても、
/// その人の行が押せるまま残っていた（下の地図は閉じたときに落とすが、
/// シートの一覧は誰も絞っていなかった）。
///
/// **見ている最中には絞らない**（`SpotDetailView` の `dropped` と同じ）——押した元の
/// `NavigationLink` が消えると、開いている詳細がその場で閉じる。戻ってきたとき
/// （`onAppear`）に写しを取り直す
struct VisiblePhotos<Content: View>: View {
    let photos: [Photo]
    @ViewBuilder let content: ([Photo]) -> Content

    @EnvironmentObject private var hidden: ModerationStore
    @State private var dropped: ModerationSnapshot?
    /// 戻るスワイプ途中の `onAppear` で行を消さない印（`FrontConfirm`）
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?

    var body: some View {
        content(dropped?.visible(photos) ?? photos)
            .onAppear {
                switch front.appear() {
                case .first:
                    dropped = hidden.snapshot
                case .returning:
                    frontSettle?.cancel()
                    frontSettle = Task {
                        try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                        guard !Task.isCancelled, front.confirm() else { return }
                        dropped = hidden.snapshot
                    }
                }
            }
            .onDisappear {
                frontSettle?.cancel()
                frontSettle = nil
                front.disappear()
            }
    }
}
