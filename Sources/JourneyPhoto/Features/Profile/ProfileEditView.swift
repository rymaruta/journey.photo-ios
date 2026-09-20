import SwiftUI
import PhotosUI

/// プロフィールの編集。名前・自己紹介・リンクと、アイコン／カバー。
struct ProfileEditView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var website = ""
    @State private var instagram = ""
    @State private var statusText = ""

    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("画像") {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Label("アイコンを変える", systemImage: "person.crop.circle")
                }
                PhotosPicker(selection: $coverItem, matching: .images) {
                    Label("カバーを変える", systemImage: "photo")
                }
            }

            Section("プロフィール") {
                TextField("表示名", text: $displayName)
                TextField("ユーザー名（半角英数）", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("自己紹介", text: $bio, axis: .vertical)
                    .lineLimit(2...6)
                TextField("ひとこと", text: $statusText)
            }

            Section("リンク") {
                TextField("ウェブサイト", text: $website)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Instagram（@なし）", text: $instagram)
                    .textInputAutocapitalization(.never)
            }

            if let message {
                Section { Text(message).font(.callout) }
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
        .navigationTitle("プロフィールの編集")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
        .onChange(of: avatarItem) { _, item in
            Task { await upload(item, kind: .avatar) }
        }
        .onChange(of: coverItem) { _, item in
            Task { await upload(item, kind: .cover) }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let profile = try? await environment.profiles.myProfile() else {
            message = "読み込めませんでした"
            return
        }
        displayName = profile.displayName ?? ""
        username = profile.username ?? ""
        bio = profile.bio ?? ""
        website = profile.website ?? ""
        instagram = profile.instagram ?? ""
        statusText = profile.statusText ?? ""
    }

    private func save() async {
        isSaving = true
        message = nil
        defer { isSaving = false }
        // 空文字も「消す」として送る（nil は「触らない」）
        let patch = ProfilePatch(
            username: username,
            displayName: displayName,
            bio: bio,
            website: website,
            instagram: instagram,
            statusText: statusText,
            themeColor: nil,
            pinnedPhotoIds: nil
        )
        do {
            try await environment.profiles.update(patch)
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "保存できませんでした"
        }
    }

    private func upload(_ item: PhotosPickerItem?, kind: ProfileService.ImageKind) async {
        guard let item else { return }
        message = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            // アイコンにも同じ関所を通す。**EXIF の付いた自撮りを
            // そのまま上げない**（撮影地が入っていることがある）
            let prepared = try ImagePreparer.prepare(data: data, fileName: "profile")
            try await environment.profiles.uploadProfileImage(kind: kind, jpeg: prepared.data)
            message = kind == .avatar ? "アイコンを変えました" : "カバーを変えました"
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "画像を変えられませんでした"
        }
    }
}
