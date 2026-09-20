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

    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var savedPhoto: Photo?

    private let uploads: UploadService

    init(uploads: UploadService) {
        self.uploads = uploads
    }

    var canSubmit: Bool { prepared != nil && !isWorking }

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
        draft.tags = Self.parseTags(tagsText)
        draft.published = published
        draft.coords = prepared.coords
        draft.date = prepared.takenOn
        draft.exif = prepared.exif

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
    }

    /// 読点・カンマ・空白のどれで区切っても同じに扱う。
    /// **重複は落とす**（同じタグが2つ付くと絞り込みの件数がずれる）。
    static func parseTags(_ text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for piece in text.components(separatedBy: CharacterSet(charactersIn: ",、 　\n")) {
            let tag = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, !seen.contains(tag.lowercased()) else { continue }
            seen.insert(tag.lowercased())
            result.append(tag)
        }
        return result
    }

    private static func image(from data: Data) -> Image? {
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }
}
