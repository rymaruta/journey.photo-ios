import SwiftUI
import PhotosUI

/// 自分の写真を直す（題・説明・撮影地・タグ・撮影日・公開）。
struct EditPhotoView: View {

    let photo: Photo

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var caption: String
    @State private var location: String
    /// 候補から選んだときに入る座標。**選んだ回だけ送る**
    @State private var pickedCoords: Photo.Coords?
    @State private var tagsText: String
    @State private var category: String
    @State private var date: String
    @State private var published: Bool
    @State private var isSaving = false
    @State private var message: String?
    /// 直近の知らせが「できた」か。**成功を赤で出さない**
    @State private var messageIsError = true
    /// 写真そのものの差し替え（Web の `/user/edit` と同じ操作）
    @State private var replaceItem: PhotosPickerItem?
    @State private var isReplacing = false

    init(photo: Photo) {
        self.photo = photo
        _title = State(initialValue: photo.displayTitle)
        _caption = State(initialValue: photo.paragraphs.joined(separator: "\n"))
        _location = State(initialValue: photo.location ?? "")
        _tagsText = State(initialValue: (photo.tags ?? []).joined(separator: ", "))
        _category = State(initialValue: photo.category ?? "")
        _date = State(initialValue: photo.exif?.dateTimeOriginal.flatMap(Self.isoDay) ?? "")
        _published = State(initialValue: photo.published != false)
    }

    var body: some View {
        Form {
            Section {
                RemoteImage(url: photo.detailImageURL, contentMode: .fit)
                    .frame(maxHeight: 200)
                if isReplacing {
                    HStack { ProgressView(); Text(L("差し替えています…", "Replacing…")) }
                } else {
                    PhotosPicker(selection: $replaceItem, matching: .images) {
                        Label(L("写真を差し替える", "Replace the photo"), systemImage: "photo.on.rectangle.angled")
                    }
                }
            } footer: {
                // 派生（AVIF・小さい版）はサーバーが消して作り直す
                Text(L("題や説明はそのままで、写真だけを入れ替えます。反映まで数分かかります。",
                       "Swaps the image only, keeping the title and description. It takes a few minutes to appear."))
            }

            Section(L("この写真について", "About this photo")) {
                TextField(L("題", "Title"), text: $title)
                TextField(L("説明", "Description"), text: $caption, axis: .vertical)
                    .lineLimit(3...8)
                // **候補から選べるようにする**（投稿画面と同じ）。
                // ただの入力欄だと座標が付かず、直した瞬間に
                // サーバーが `geoApprox` の座標を消す＝地図から消える。
                // アプリには戻す口が無かった（Web の `/user/edit` にはある）
                PlaceSearchField(location: $location, coords: $pickedCoords)
                TagField(tagsText: $tagsText)
                CategoryField(category: $category)
                TextField(L("撮影日（YYYY-MM-DD）", "Date taken (YYYY-MM-DD)"), text: $date)
                    .keyboardType(.numbersAndPunctuation)
            }

            Section {
                Toggle(L("公開する", "Public"), isOn: $published)
            } footer: {
                Text(L("非公開にすると、サイトの一覧と個別ページから消えます（反映まで数分）。", "Making it private removes it from the site within a few minutes."))
            }

            if let message {
                Section {
                    Text(message).font(.callout)
                        .foregroundStyle(messageIsError ? Color.red : Color.secondary)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        HStack { ProgressView(); Text(L("保存中…", "Saving…")) }
                    } else {
                        Text(Labels.Common.save)
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle(L("写真を編集", "Edit photo"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: replaceItem) { _, item in
            Task { await replace(item) }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Labels.Common.close) { dismiss() }
            }
        }
    }

    /// 写真そのものを差し替える。**EXIF は端末で落としてから送る**（投稿と同じ関所）。
    private func replace(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isReplacing = true
        message = nil
        defer {
            isReplacing = false
            // **選択を戻す。** 戻さないと、同じ写真をもう一度選んでも
            // `onChange` が起きず、何も起きない
            replaceItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let prepared = try ImagePreparer.prepare(data: data, fileName: "photo")
            try await environment.photos.replace(photoId: photo.id, prepared: prepared,
                                                 uploads: environment.uploads)
            messageIsError = false
            message = L("差し替えました（反映まで数分かかります）", "Replaced. It takes a few minutes to appear.")
        } catch {
            messageIsError = true
            message = (error as? LocalizedError)?.errorDescription
                ?? L("差し替えられませんでした", "Couldn't replace it")
        }
    }

    private func save() async {
        isSaving = true
        message = nil
        defer { isSaving = false }

        var patch = PhotoPatch()
        patch.title = title
        patch.description = caption
        patch.location = location
        // **選んだ回だけ載せる。** nil は「触らない」なので、
        // 地名を手で直しただけの回に既存の座標を壊さない
        patch.coords = pickedCoords
        patch.tags = TagInput.parse(tagsText)
        patch.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        patch.published = published
        // **空なら送らない。** 空文字を送ると api-user の日付検査に落ちる
        let day = date.trimmingCharacters(in: .whitespaces)
        patch.date = day.isEmpty ? nil : day

        do {
            try await environment.photos.update(photoId: photo.id, patch: patch)
            dismiss()
        } catch {
            messageIsError = true
            message = (error as? LocalizedError)?.errorDescription ?? L("保存できませんでした", "Couldn't save")
        }
    }

    /// EXIF の "2026:09:13 08:21:05" を "2026-09-13" にする。
    static func isoDay(_ raw: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = parser.date(from: raw) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: date)
    }
}
