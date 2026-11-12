import SwiftUI

/// ①現像の「投稿する」を送り出す係（2026-11-12・札 #543）。
///
/// **今の投稿の道（`UploadViewModel.submit`）をそのまま通す**——束ねる（`groupsForSubmit`・旅の流れの束）、
/// 送信の控え（途中でアプリが終わっても投稿の画面の「続きから」で戻せる）、撮影地の地名の自動入力、
/// トランクのラベル・硬貨まで、投稿の画面から送ったときと同じになる。画面は出さない。
///
/// 現像の画面を閉じても続く（画面ではなくこの係が持つ）。終わったらホーム・マイページに読み直しを知らせる
/// （`TabRouter.postSheetClosed`・投稿の画面を閉じたときと同じ）
@MainActor
final class DevelopPostCenter: ObservableObject {

    static let shared = DevelopPostCenter()

    /// 送っている最中（二重に送らない）
    @Published private(set) var isPosting = false

    /// 送っている投稿の型（送り終えるまで持つ）
    private var model: UploadViewModel?

    /// 送り出す。写真を読み・整え、投稿の型に並べて送る。
    ///
    /// - Parameters:
    ///   - ids: 送る写真（`DevelopTrips.uploadOrder`・表紙が先頭）
    ///   - published: 公開するか（2026-11-12 判断: 現像の「投稿する」は**みんなに公開**。表紙の画面に
    ///     「みんなに公開」と出し、5秒は取り消せる。変えたい人は「題・公開範囲を変える」で今の投稿の画面へ）
    func post(trip: LibraryTrip, ids: [String], published: Bool, userId: String,
              environment: AppEnvironment, toasts: ToastCenter, onDone: @escaping (Bool) -> Void = { _ in }) {
        guard !isPosting, !ids.isEmpty else { return }
        isPosting = true
        Task {
            let loaded = await DevelopPhotos.prepare(ids: ids, trip: trip)
            guard LibraryTrips.canAddToTrips(count: loaded.photos.count) else {
                isPosting = false
                toasts.show(L("写真を読み込めなかったため投稿できませんでした。通信できる場所でもう一度お試しください",
                              "Couldn't load the photos, so nothing was posted. Try again with a connection."),
                            kind: .failure)
                onDone(false)
                return
            }
            let api = APIClient.app()
            let made = UploadViewModel(uploads: UploadService.app(api: api), albums: AlbumService(api: api),
                                       photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
            model = made
            // 投稿の画面の `onAppear` と同じ順（持ち主 → 索引 → 写真）
            made.useLocationOwner(userId)
            made.fetchSpotIndex = { [spots = environment.spots] in await spots.fetchIndexRows() }
            made.fetchSpotMatchIndex = { [spots = environment.spots] in await spots.fetchMatchIndex() }
            made.drafts = UploadDraftStore(slot: .entry(UUID().uuidString))
            made.draftOwner = userId
            made.onSaved = { TabRouter.shared.notePosted($0) }
            made.applyInitialPhotos(loaded.photos, startPrivate: !published)
            // 撮影地の地名を引き終えるまで待つ（1枚5秒で諦める・`fillPlaceName`）。待たずに送ると地名が空で上がる
            for task in made.placeTasks.values { await task.value }
            await made.submit()
            let ok = made.didPostAll && loaded.failed == 0
            isPosting = false
            model = nil
            TabRouter.shared.postSheetClosed()
            if made.didPostAll {
                toasts.show(loaded.failed == 0
                            ? L("旅を投稿しました", "Your trip is posted")
                            : L("旅を投稿しました（\(loaded.failed)枚は読み込めませんでした）",
                                "Your trip is posted (\(loaded.failed) couldn't be loaded)"))
            } else {
                // 送れなかった写真は送信の控えに残る（投稿の画面を開くと「続きから」）
                toasts.show(made.errorMessage ?? L("投稿できなかった写真があります。投稿の画面から続きを送れます",
                                                   "Some photos weren't posted. You can continue from the post screen."),
                            kind: .failure)
            }
            onDone(ok)
        }
    }
}

/// 現像で選んだ写真を読み、整える（**「旅の写真からまとめて」の選ぶ画面と同じ手順**・`LibraryTripPickView.load`）。
/// 読めた写真から1枚ずつ縮め、EXIF と GPS を落とす（撮影日と約1kmに丸めた座標は残す）。原本は持ち続けない
enum DevelopPhotos {

    /// 「題・公開範囲を変える」: 選んだ写真を読んで整え、今の投稿の画面に並べて開く（現像の画面が閉じきってから呼ぶ）。
    /// 現像の続きなので**公開で始める**（表紙の画面で「みんなに公開」と見せた続き・変えられる）
    @MainActor
    static func openUploadScreen(ids: [String], trip: LibraryTrip) {
        Task {
            let loaded = await prepare(ids: ids, trip: trip)
            guard !loaded.photos.isEmpty else { return }
            TabRouter.shared.openDevelopUpload(loaded.photos, published: true)
        }
    }

    static func prepare(ids: [String], trip: LibraryTrip) async -> (photos: [ImagePreparer.Prepared], failed: Int) {
        let byId = Dictionary(trip.shots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let zone = trip.timeZone
        var photos: [ImagePreparer.Prepared] = []
        var failed = 0
        for id in ids {
            if Task.isCancelled { break }
            guard let shot = byId[id], let data = await PhotoLibrary.imageData(for: id) else {
                failed += 1
                continue
            }
            let prepared = try? await Task.detached(priority: .userInitiated) {
                ImagePreparer.fillingTakenDate(
                    try ImagePreparer.prepare(data: data, fileName: "photo", withThumbnail: true),
                    takenAt: shot.date, timeZone: zone)
            }.value
            if let prepared { photos.append(prepared) } else { failed += 1 }
        }
        return (photos, failed)
    }
}
