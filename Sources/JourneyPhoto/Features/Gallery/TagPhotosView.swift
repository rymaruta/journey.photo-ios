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
    /// 公開一覧を引けなかった（控えも無かった）。**0枚と分ける**
    @State private var loadFailed = false

    var body: some View {
        // 形は色・機材・いまの季節と同じ（板 12）
        CollectionPhotosScreen(title: kind.title, photos: photos, kind: kind, isLoading: isLoading,
                               retry: loadFailed ? { Task { await load() } } : nil)
            .task { await load() }
            // 詳細でブロック／通報して**戻ってきたとき**に落とす。
            // 見ている最中に絞ると、押した元が消えて詳細が閉じる
            .onAppear { photos = hidden.visible(photos) }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = try? await environment.gallery.fetchPhotos()
        // **取り消された回は書かない**（失敗の印も立てない）。戻ると `.task` が走り直し、
        // 読み終わる前に次の写真を開くと取り消される。空で上書きすると押した元が
        // 消え、開いたばかりの詳細が閉じた（`GalleryViewModel.load` と同じ）
        guard !Task.isCancelled else { return }
        // 引けなかった回を「該当する写真がありません」にしない（控えがあれば
        // `fetchPhotos` がそれを返すので、ここに来るのは控えも無いときだけ）
        // **手元の一覧は空で潰さない**（読めていたぶんは出し続ける）
        loadFailed = all == nil
        guard let all else { return }
        // 読んでいる間に通報された回、古い集合で絞った結果で上書きしない
        photos = hidden.visible(PhotoQuery.photos(all, in: kind))
    }
}
