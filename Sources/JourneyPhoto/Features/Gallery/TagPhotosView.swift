import SwiftUI

/// タグ・撮影地・カテゴリで絞った一覧。
///
/// Web 側の `/tag/*`・`/location/*`・`/category/*` にあたる。あちらは
/// 検索に載せるための静的ページだが、アプリでは絞り込みの結果として出す。
struct TagPhotosView: View {

    /// 絞り込みの条件。中身は `PhotoQuery.Collection`（画面を持たない層に置いて、
    /// Linux 上の `swift test` で検証できるようにしてある）。
    let kind: PhotoQuery.Collection

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @State private var photos: [Photo] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if photos.isEmpty && !isLoading {
                ErrorBanner(message: Labels.Gallery.empty)
            } else {
                PhotoGrid(photos: photos) { photo in
                    PhotoDetailView(photo: photo, context: photos)
                }
            }
        }
        .webScreen()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // 詳細でブロック／通報して**戻ってきたとき**に落とす。
        // 見ている最中に絞ると、押した元が消えて詳細が閉じる
        .onAppear { photos = hidden.visible(photos) }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = (try? await environment.gallery.fetchPhotos()) ?? []
        // 読んでいる間に通報された回、古い集合で絞った結果で上書きしない
        photos = hidden.visible(PhotoQuery.photos(all, in: kind))
    }
}
