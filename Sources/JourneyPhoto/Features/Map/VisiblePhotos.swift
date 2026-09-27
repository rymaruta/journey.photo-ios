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

    var body: some View {
        content(dropped?.visible(photos) ?? photos)
            .onAppear { dropped = hidden.snapshot }
    }
}
