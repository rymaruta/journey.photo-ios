import SwiftUI

/// 自分の写真を直す（題・説明・撮影地・タグ・撮影日・公開）。
struct EditPhotoView: View {

    let photo: Photo

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var caption: String
    @State private var location: String
    @State private var tagsText: String
    @State private var date: String
    @State private var published: Bool
    @State private var isSaving = false
    @State private var message: String?

    init(photo: Photo) {
        self.photo = photo
        _title = State(initialValue: photo.displayTitle)
        _caption = State(initialValue: photo.paragraphs.joined(separator: "\n"))
        _location = State(initialValue: photo.location ?? "")
        _tagsText = State(initialValue: (photo.tags ?? []).joined(separator: ", "))
        _date = State(initialValue: photo.exif?.dateTimeOriginal.flatMap(Self.isoDay) ?? "")
        _published = State(initialValue: photo.published != false)
    }

    var body: some View {
        Form {
            Section {
                RemoteImage(url: photo.detailImageURL, contentMode: .fit)
                    .frame(maxHeight: 200)
            }

            Section("この写真について") {
                TextField("題", text: $title)
                TextField("説明", text: $caption, axis: .vertical)
                    .lineLimit(3...8)
                TextField("撮影地", text: $location)
                TextField("タグ（カンマ区切り）", text: $tagsText)
                    .textInputAutocapitalization(.never)
                TextField("撮影日（YYYY-MM-DD）", text: $date)
                    .keyboardType(.numbersAndPunctuation)
            }

            Section {
                Toggle("公開する", isOn: $published)
            } footer: {
                Text("非公開にすると、サイトの一覧と個別ページから消えます（反映まで数分）。")
            }

            if let message {
                Section { Text(message).font(.callout).foregroundStyle(.red) }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        HStack { ProgressView(); Text("保存中…") }
                    } else {
                        Text("保存する")
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("写真を編集")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        isSaving = true
        message = nil
        defer { isSaving = false }

        var patch = PhotoPatch()
        patch.title = title
        patch.description = caption
        patch.location = location
        patch.tags = TagInput.parse(tagsText)
        patch.published = published
        // **空なら送らない。** 空文字を送ると api-user の日付検査に落ちる
        let day = date.trimmingCharacters(in: .whitespaces)
        patch.date = day.isEmpty ? nil : day

        do {
            try await environment.photos.update(photoId: photo.id, patch: patch)
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "保存できませんでした"
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
