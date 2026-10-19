import SwiftUI

/// 自分の写真を自分で読んでから `CamperGarageView` を出す入れ物（2026-10-18・設定の「旅の道具」から開く口）。
///
/// 設定の画面は自分の写真を持たない。マイページと同じ口（`ProfileImageFromPhoto.myPhotos`＝`PhotoService.myPhotos()`、
/// 見本の入り方では公開一覧から自分のぶん）で読む。**読めるまでは `photosLoaded = false`** のまま渡す——
/// 車の画面はそのあいだ「届いた」の判定も保存もしない（#312 の見直しの守り）。読めなかったら false のまま。
/// マイページからは今までどおり読み終えた写真を渡す（ここを通さない＝二重に読まない）
struct CamperGarageLoader: View {
    let ownerName: String?
    let userId: String?

    @EnvironmentObject private var environment: AppEnvironment
    @State private var photos: [Photo] = []
    /// 写真を読めた人（入っている人が替わったら、前の人の写真では数えない）
    @State private var loadedFor: String?

    var body: some View {
        CamperGarageView(ownerName: ownerName, userId: userId, photos: photos,
                         photosLoaded: CamperLoaderRule.isLoaded(loadedFor: loadedFor, userId: userId))
            .task(id: userId) {
                guard let userId, loadedFor != userId else { return }
                guard let fresh = await ProfileImageFromPhoto.myPhotos(environment: environment),
                      !Task.isCancelled else { return }
                photos = fresh
                loadedFor = userId
            }
    }
}

/// 読めたかの決まり（テストで見る）: 今の人の写真を読み終えたときだけ true
enum CamperLoaderRule {
    static func isLoaded(loadedFor: String?, userId: String?) -> Bool {
        guard let userId else { return false }
        return loadedFor == userId
    }
}
