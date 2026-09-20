import SwiftUI
import PhotosUI

struct UploadView: View {

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model: UploadViewModel

    init() {
        // AppEnvironment を init で受け取れない（EnvironmentObject は body 以降）
        // ため、ここでは既定の組み立てを使う
        _model = StateObject(wrappedValue: UploadViewModel(
            uploads: UploadService(api: APIClient(tokenProvider: CognitoTokenProvider()))
        ))
    }

    var body: some View {
        Group {
            if auth.userId == nil {
                SignInView(reason: "写真を投稿するにはログインしてください")
            } else {
                form
            }
        }
        .navigationTitle("投稿")
    }

    private var form: some View {
        Form {
            Section {
                PhotosPicker(selection: $model.pickerItem, matching: .images, photoLibrary: .shared()) {
                    if let preview = model.previewImage {
                        preview
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 260)
                    } else {
                        Label("写真を選ぶ", systemImage: "photo.badge.plus")
                    }
                }
            } footer: {
                Text("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地の座標は約1kmに丸めて保存します。")
            }

            Section("この写真について") {
                TextField("題（例: 高屋神社の雲海）", text: $model.title)
                TextField("説明", text: $model.caption, axis: .vertical)
                    .lineLimit(3...8)
                TextField("撮影地（例: 高屋神社, 香川）", text: $model.location)
                TextField("タグ（カンマ区切り）", text: $model.tagsText)
                    .textInputAutocapitalization(.never)
            }

            Section {
                Toggle("すぐ公開する", isOn: $model.published)
            } footer: {
                Text("公開すると、数分後にサイトの個別ページとサイトマップにも載ります。")
            }

            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            }

            Section {
                Button {
                    Task { await model.submit() }
                } label: {
                    if model.isWorking {
                        HStack { ProgressView(); Text("送信中…") }
                    } else {
                        Text("投稿する")
                    }
                }
                .disabled(!model.canSubmit)
            }
        }
    }
}
