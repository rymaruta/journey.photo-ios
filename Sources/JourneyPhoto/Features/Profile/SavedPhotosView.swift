import SwiftUI

/// 保存した写真（板 35「お気に入り」・板 01d のメニューの「保存した写真」）。
///
/// 写真の詳細のしおり（保存）の行き先。**いいねとは別の入れ物**
/// （`SavedPhotosStore` と `FavoritesStore`）——以前はマイページの
/// 「お気に入り」（しおりの印・英語は "Saved"）の中身がいいねした写真で、
/// 保存した写真を見返す場所がどこにも無かった。
///
/// 並びは板どおり**先頭を大きく1枚、その下は2列**（`PhotoGrid`）。
/// 板の注記「この端末に覚えています」は**書かない**——保存はサーバーが本体で、
/// ほかの端末にも出る（`SaveService`）。事実と違う文を置かない。
struct SavedPhotosView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var savedPhotos: SavedPhotosStore
    @EnvironmentObject private var hidden: ModerationStore
    @State private var all: [Photo] = []
    /// 画面に出す分。**戻ってきたときに絞り直す**（`FavoritesView` と同じ理由——
    /// 見ている詳細でしおりを外した瞬間に元の行が消えると、詳細が閉じる）
    @State private var photos: [Photo] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ErrorBanner(message: Self.emptyMessage)
                }
            } else {
                PhotoGrid(photos: photos) { photo in
                    PhotoDetailView(photo: photo, context: photos)
                }
            }
        }
        .webScreen()
        .navigationTitle(ProfileTab.favorites.label)
        .task { await load() }
        .refreshable { await load(force: true) }
        .onAppear {
            all = hidden.visible(all)
            photos = LikedPhotos.resolve(savedPhotos.ids, in: [all])
        }
    }

    /// マイページの「お気に入り」タブでも使う
    static var emptyMessage: String {
        L("保存した写真はまだありません。写真の詳細のしおりで保存できます",
          "No saved photos yet. Tap the bookmark on a photo to save it.")
    }

    // 引き当ての決まり（id を手元の写真の束から探す・重複は1枚に）はいいねと同じ
    // （`LikedPhotos.resolve`）。保存のために同じ関数をもう1つ作らない
    private func load(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        all = hidden.visible((try? await environment.gallery.fetchPhotos(force: force)) ?? all)
        photos = LikedPhotos.resolve(savedPhotos.ids, in: [all])
    }
}
