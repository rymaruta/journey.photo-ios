import SwiftUI

/// いいねした写真。**サーバーの一覧と、この端末の控えの和**
/// （以前マイページの「お気に入り」タブにあった決まりをここへ移した・2026-09-26。
/// タブの中身は保存した写真＝`SavedPhotosView` になった）。
/// 控えがあるので**圏外でも一覧は出る**（画像そのものは一度見たものだけ）。
struct FavoritesView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var hidden: ModerationStore
    /// 取ってきた全部。
    @State private var all: [Photo] = []
    /// 画面に出す分。**描画のたびに絞らない。**
    ///
    /// 絞りを計算に変えると、詳細画面でハートを外した瞬間に
    /// 元の `NavigationLink` が `ForEach` から消え、**見ている詳細画面が
    /// その場で閉じる**（SwiftUI は押した先を、押した元の存在に紐付ける）。
    /// 絞り直すのは**戻ってきたとき**（`.onAppear`）。
    @State private var photos: [Photo] = []
    @State private var isLoading = true
    /// サーバーのいいねの ID。取れなければ nil（端末の控えだけ出す）
    @State private var serverLikeIds: [String]?
    /// サーバーに聞けなかった回（端末のぶんは消さない。足りないことだけ伝える）
    @State private var partial = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        ScrollView {
            if partial {
                ErrorBanner(message: L("サーバーのいいねを取れませんでした。この端末に覚えているぶんだけ出しています",
                                       "Couldn't reach the server — showing what's on this device")) {
                    Task { await load(force: true) }
                }
            }
            if photos.isEmpty && !isLoading {
                ErrorBanner(message: L("まだお気に入りがありません", "No liked photos yet"))
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        NavigationLink { PhotoDetailView(photo: photo, context: photos) } label: {
                            PhotoFrame(photo: photo)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .webScreen()
        .navigationTitle(Labels.Navigation.favorites)
        .task { await load() }
        .refreshable { await load(force: true) }
        // **戻ってきたら絞り直す。** 詳細画面でハートを外したぶんは、
        // その画面を閉じたこの時点で消える（見ている最中には消さない）
        // ブロック／通報したぶんも、同じく戻ってきたときに落とす（`all` ごと）
        .onAppear {
            all = hidden.visible(all)
            photos = liked()
        }
    }

    /// いいねした写真。**押した瞬間の控えも拾う**（サーバーの一覧は開いた時点のもの）
    private func liked() -> [Photo] {
        LikedPhotos.resolve(LikedPhotos.ids(serverIds: serverLikeIds, deviceIds: favorites.ids), in: [all])
    }

    private func load(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        async let feedTask = environment.gallery.fetchPhotos(force: force)
        // **未ログインなら聞きに行かない**（端末の控えが答え）
        if auth.userId != nil {
            serverLikeIds = try? await environment.social.myLikedPhotoIds()
            partial = serverLikeIds == nil
        } else {
            serverLikeIds = nil
            partial = false
        }
        all = hidden.visible((try? await feedTask) ?? all)
        photos = liked()
    }
}
