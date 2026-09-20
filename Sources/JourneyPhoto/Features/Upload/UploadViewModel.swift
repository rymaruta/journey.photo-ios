import Foundation
import SwiftUI
import PhotosUI

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
    @Published var tagsText = ""
    @Published var published = true

    @Published private(set) var albums: [Album] = []
    @Published var selectedAlbumId: String?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var savedPhoto: Photo?

    private let uploads: UploadService
    private let albumService: AlbumService

    init(uploads: UploadService, albums: AlbumService) {
        self.uploads = uploads
        self.albumService = albums
    }

    /// アルバムは無いことの方が多い。**取れなくても投稿は止めない。**
    func loadAlbums() async {
        albums = (try? await albumService.list()) ?? []
    }

    var canSubmit: Bool { prepared != nil && !isWorking }

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
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "写真を読み込めませんでした"
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
                errorMessage = "写真を読み込めませんでした"
                return
            }
            // **`itemIdentifier` をファイル名にしない。** スラッシュを含む
            // 端末内部の ID で、キーの組み立てを壊す。拡張子は
            // `ImagePreparer` が .jpg に付け替える
            let prepared = try ImagePreparer.prepare(data: data, fileName: "photo")
            self.prepared = prepared
            self.previewImage = Self.image(from: prepared.data)
            // 撮影地は自動で埋めない（撮影地欄は検索で効く固有名詞を入れる場所で、
            // 座標とは別物。CLAUDE.md の「地名をタグに書いている」問題と同じ話）
        } catch {
            self.prepared = nil
            self.previewImage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "写真を読み込めませんでした"
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
        draft.published = published
        draft.coords = prepared.coords
        draft.date = prepared.takenOn
        draft.exif = prepared.exif
        draft.albumId = selectedAlbumId

        do {
            savedPhoto = try await uploads.upload(
                data: prepared.data,
                fileName: prepared.fileName,
                fileType: prepared.contentType,
                draft: draft
            )
            reset()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "投稿できませんでした"
        }
    }

    private func reset() {
        pickerItem = nil
        prepared = nil
        previewImage = nil
        title = ""
        caption = ""
        location = ""
        tagsText = ""
        published = true
        selectedAlbumId = nil
    }

    private static func image(from data: Data) -> Image? {
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }
}
