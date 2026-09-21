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
    @State private var themeColor = ""

    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?

    @State private var isLoading = true
    @State private var isSaving = false
    /// いまの内容を読めたか。**読めるまで保存させない**
    /// ——読めていない空の欄で上書きすると、プロフィールが丸ごと消える
    @State private var loaded = false
    @State private var message: String?

    var body: some View {
        Form {
            Section(L("画像", "Images")) {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Label(L("アイコンを変える", "Change avatar"), systemImage: "person.crop.circle")
                }
                PhotosPicker(selection: $coverItem, matching: .images) {
                    Label(L("カバーを変える", "Change cover"), systemImage: "photo")
                }
            }

            Section(Labels.Navigation.profile) {
                TextField(L("表示名", "Display name"), text: $displayName)
                TextField(L("ユーザー名（半角英数）", "Username (letters and numbers)"), text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(L("自己紹介", "Bio"), text: $bio, axis: .vertical)
                    .lineLimit(2...6)
                TextField(L("ひとこと", "Status"), text: $statusText)
                ThemeColorField(themeColor: $themeColor)
            }

            Section(L("リンク", "Links")) {
                TextField(L("ウェブサイト", "Website"), text: $website)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField(L("Instagram（@なし）", "Instagram (without @)"), text: $instagram)
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
                        HStack { ProgressView(); Text(L("保存中…", "Saving…")) }
                    } else {
                        Text(Labels.Common.save)
                    }
                }
                // **読めるまで押させない。** 押せてしまうと、
                // 空の欄がそのまま「消す」として送られる
                .disabled(isSaving || !loaded)
            }
        }
        .navigationTitle(L("プロフィールの編集", "Edit profile"))
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
            message = L("いまの内容を読み込めませんでした。開き直してください（このまま保存すると消えてしまいます）",
                        "Couldn't load your current profile. Please reopen this screen (saving now would erase it).")
            return
        }
        displayName = profile.displayName ?? ""
        username = profile.username ?? ""
        bio = profile.bio ?? ""
        website = profile.website ?? ""
        instagram = profile.instagram ?? ""
        statusText = profile.statusText ?? ""
        themeColor = profile.themeColor ?? ""
        loaded = true
    }

    private func save() async {
        // **読めていない内容で上書きしない。**
        //
        // 読み込みに失敗すると欄は全部空のまま出る。サーバーは
        // 「キーがある＝指定した、値が空＝消す」で読む
        // （`api-user/src/userProfile.ts` の `apply`）ので、そのまま
        // 保存すると**表示名・ユーザー名・自己紹介・リンク・ひとこと・
        // テーマ色が全部消える**。取り返しがつかない。
        guard loaded else {
            message = L("いまの内容を読み込めていないので保存できません。開き直してください",
                        "Can't save before your current profile is loaded. Please reopen this screen.")
            return
        }
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
            themeColor: themeColor,
            pinnedPhotoIds: nil
        )
        do {
            try await environment.profiles.update(patch)
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("保存できませんでした", "Couldn't save")
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
            message = kind == .avatar ? L("アイコンを変えました", "Avatar updated") : L("カバーを変えました", "Cover updated")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("画像を変えられませんでした", "Couldn't update the image")
        }
    }
}
