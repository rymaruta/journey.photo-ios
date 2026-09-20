import Foundation
import SwiftUI
import PhotosUI
// UIImage を使う（SwiftUI / PhotosUI から見えることに頼らない）
import UIKit

@MainActor
final class UploadViewModel: ObservableObject {

    @Published var pickerItem: PhotosPickerItem? {
        didSet { Task { await loadPicked() } }
    }
    @Published private(set) var prepared: ImagePreparer.Prepared?
    @Published private(set) var previewImage: Image?

    @Published var title = ""
    @Published var caption = ""
    @Published var location = ""
    /// 撮影地を候補から選んだときに入る座標（写真の EXIF より優先）
    @Published var pickedCoords: Photo.Coords?
    @Published var song: Photo.Song?
    @Published var tagsText = ""
    /// カテゴリ。**決まった選択肢から選ぶ**（`CategoryChoices`）
    @Published var category = ""
    @Published var published = true

    @Published private(set) var albums: [Album] = []
    @Published var selectedAlbumId: String?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var savedPhoto: Photo?

    private let uploads: UploadService
    private let albumService: AlbumService
    private let photoService: PhotoService
    private let discovery: DiscoveryService

    init(uploads: UploadService, albums: AlbumService, photos: PhotoService, discovery: DiscoveryService) {
        self.uploads = uploads
        self.albumService = albums
        self.photoService = photos
        self.discovery = discovery
    }

    /// アルバムは無いことの方が多い。**取れなくても投稿は止めない。**
    ///
    /// **参加しているアルバムも行き先に出す。** `GET /albums` は自分が
    /// 作ったものしか返さない（`albums.ts`）ので、端末が覚えている分
    /// （`JoinedAlbumsStore`）を足す。足さないと、招待された人は
    /// **そのアルバムに1枚も投稿できない**——サーバーは会員なら受け付ける
    /// （`upload.ts` の `isAlbumMember`）のに、選ぶ口が無いだけだった。
    func loadAlbums(joined: [JoinedAlbumsStore.Entry] = []) async {
        let mine = (try? await albumService.list()) ?? []
        let mineIds = Set(mine.map(\.id))
        let extra = joined
            .filter { !mineIds.contains($0.id) }
            .map { Album(id: $0.id, title: $0.title, createdAt: nil,
                         memberCount: nil, inviteToken: nil, inviteExpiresAt: nil) }
        albums = mine + extra
    }

    var canSubmit: Bool { prepared != nil && !isWorking }

    /// 写真の座標から撮影地を引いて、**空のときだけ**入れる。
    ///
    /// **なぜ埋めるか。** 撮影地 → 地図 → `/location/<スラッグ>` → 検索流入 が
    /// このサイトの価値で（CLAUDE.md）、実データでは 30枚中13枚が空だった。
    /// 手で打つ人は少ない。Web は 2026-08 からこれを埋めている。
    ///
    /// **5秒で諦める。** Web 側の `REVERSE_GEOCODE_TIMEOUT_MS` と同じ。
    /// あちらは返らないと公開ボタンが押せなくなる作りだったが、こちらは
    /// 押せるままなので、遅れて届いた地名が**打っている最中に割り込む**のを
    /// 止めるのが目的（書きかけを奪わない）。
    func fillPlaceName(lat: Double, lng: Double) async {
        // 引く前に一度（打ってあるなら、そもそも引かない）
        guard PlaceFill.value(current: location, found: "-") != nil else { return }
        let found = await withTaskGroup(of: String?.self) { group -> String? in
            group.addTask { [discovery] in try? await discovery.placeName(lat: lat, lng: lng) }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        // **待っている間に打ち始めていたら、入れない。** 書きかけを奪わない
        guard let next = PlaceFill.value(current: location, found: found) else { return }
        location = next
    }

    /// カメラで撮った画像を受ける。
    ///
    /// **`UIImage` を経由した時点で EXIF は残っていない**（撮影地も
    /// 機材名も付かない）。それでも `ImagePreparer` を通すのは、
    /// 1920px への縮小と「残っていないことの確認」を1か所に寄せるため。
    func accept(capturedJPEG data: Data) {
        do {
            let prepared = try ImagePreparer.prepare(data: data, fileName: "photo")
            self.prepared = prepared
            self.previewImage = Self.image(from: prepared.data)
            self.errorMessage = nil
        } catch {
            self.prepared = nil
            self.previewImage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("写真を読み込めませんでした", "Couldn't load the photo")
        }
    }

    /// 選ばれた写真を読み、**その場で EXIF を落とす**。
    /// 落とせなかったら受け付けない（`ImagePreparer` の関所）。
    private func loadPicked() async {
        guard let pickerItem else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                errorMessage = L("写真を読み込めませんでした", "Couldn't load the photo")
                return
            }
            // **`itemIdentifier` をファイル名にしない。** スラッシュを含む
            // 端末内部の ID で、キーの組み立てを壊す。拡張子は
            // `ImagePreparer` が .jpg に付け替える
            let prepared = try ImagePreparer.prepare(data: data, fileName: "photo")
            self.prepared = prepared
            self.previewImage = Self.image(from: prepared.data)
            // **撮影地を、写真の座標から先に埋めておく**（Web と同じ）。
            // `lib/utils/exif.ts` の `reverseGeocode` が同じことをしている。
            // 埋めるのは提案で、上から書き直せる
            if let coords = prepared.coords {
                await fillPlaceName(lat: coords.lat, lng: coords.lng)
            }
        } catch {
            self.prepared = nil
            self.previewImage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("写真を読み込めませんでした", "Couldn't load the photo")
        }
    }

    func submit() async {
        guard let prepared else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        var draft = PhotoDraft()
        draft.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.description = caption
        draft.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.tags = TagInput.parse(tagsText)
        // **空なら送らない**（空文字は「カテゴリ無し」ではなく空の属性になる）
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.category = trimmedCategory.isEmpty ? nil : trimmedCategory
        draft.published = published
        // **選んだ撮影地の座標を優先する。** 写真に残っていた位置より、
        // 本人が選んだ地名の方が正しい（丸めはどちらも約1km）
        draft.coords = pickedCoords ?? prepared.coords
        draft.date = prepared.takenOn
        draft.exif = prepared.exif
        draft.albumId = selectedAlbumId

        do {
            let photo = try await uploads.upload(
                data: prepared.data,
                fileName: prepared.fileName,
                fileType: prepared.contentType,
                draft: draft
            )
            savedPhoto = photo
            // **曲は保存のあと。** `POST /upload/save` は song を受け取らない
            // ので、`PUT /photos/{id}` で付ける。ここが落ちても写真は
            // 上がっているので、投稿そのものは失敗にしない
            if let song, let id = photo?.id {
                var patch = PhotoPatch()
                patch.song = song
                do {
                    try await photoService.update(photoId: id, patch: patch)
                } catch {
                    errorMessage = L("写真は投稿しましたが、曲を付けられませんでした", "Posted, but the song couldn't be attached")
                }
            }
            reset()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("投稿できませんでした", "Couldn't post")
        }
    }

    private func reset() {
        pickerItem = nil
        prepared = nil
        previewImage = nil
        title = ""
        caption = ""
        location = ""
        pickedCoords = nil
        song = nil
        tagsText = ""
        category = ""
        published = true
        selectedAlbumId = nil
    }

    private static func image(from data: Data) -> Image? {
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }
}
