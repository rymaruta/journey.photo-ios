import SwiftUI
import PhotosUI

/// プロフィールの編集。名前・自己紹介・リンクと、アイコン／カバー。
///
/// **並びはアーティファクト 32 の「プロフィールの編集」**（2026-09-26）:
/// カバーとアイコンの見本 → 表示名 → ユーザー名 → 自己紹介 → 居住地・Instagram
/// → BGM、保存は右上。板に無い「ひとこと・テーマ色・ウェブサイト」は
/// **消さずに最後の「そのほか」へ**（プロフィールに値が入っている人がいて、
/// 消すとアプリから直せなくなる）。
struct ProfileEditView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var website = ""
    @State private var instagram = ""
    @State private var statusText = ""
    /// 居住地（モック2-9 の「居住地」の行）
    @State private var homeLocation = ""
    @State private var themeColor = ""
    /// いま持っている曲。**丸ごと覚えておく**——Web 版は5曲まで持てるので、
    /// 1曲だけ送ると残りが消える。アプリが触るのは**先頭だけ**
    @State private var songs: [Photo.Song] = []
    @State private var showSongPicker = false

    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?
    /// いまのアイコン・カバーを見せるための持ち主の ID（読めたら入る）
    @State private var userId: String?
    /// 画像を変えたら URL の末尾を変える（同じ URL だと古い絵の控えが出る）
    @State private var imageBust = UUID().uuidString

    @State private var isLoading = true
    @State private var isSaving = false
    /// いまの内容を読めたか。**読めるまで保存させない**
    /// ——読めていない空の欄で上書きすると、プロフィールが丸ごと消える
    @State private var loaded = false
    @State private var message: String?

    var body: some View {
        Form {
            imagesHeader

            // **知らせは上に出す。** 保存は右上なので、下に出すと失敗しても
            // 「押しても何も起きない」に見える（読めなかった警告も同じ）
            if let message {
                Section { Text(message).font(.callout) }
            }

            Section {
                labeled(L("表示名", "Display name")) {
                    TextField("", text: $displayName)
                }
                labeled(L("ユーザー名（半角英数）", "Username (letters and numbers)")) {
                    TextField("", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                labeled(L("自己紹介", "Bio")) {
                    // 板の下書き「ひとこと」は付けない——下の「そのほか」に同じ名前の欄
                    // （statusText）があり、どちらに書くのか紛れる
                    TextField("", text: $bio, axis: .vertical)
                        .lineLimit(2...6)
                }
                // 板は居住地と Instagram を横に2つ並べる
                HStack(alignment: .top, spacing: 10) {
                    labeled(L("居住地", "Where you're based")) {
                        TextField("", text: $homeLocation)
                    }
                    labeled(L("Instagram（@なし）", "Instagram (without @)")) {
                        TextField("", text: $instagram)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }
            .listRowBackground(Color.clear)

            bgmSection

            // **板に無い3つ。** 消すとアプリから直せなくなるので、最後にまとめて残す
            Section(L("そのほか", "More")) {
                labeled(L("ひとこと", "Status")) {
                    TextField("", text: $statusText)
                }
                ThemeColorField(themeColor: $themeColor)
                labeled(L("ウェブサイト", "Website")) {
                    TextField("", text: $website)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
            }
            .listRowBackground(Color.clear)

        }
        .webScreen()
        .navigationTitle(L("プロフィールの編集", "Edit profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // **保存は右上**（板）。以前はフォームの一番下にあり、長い画面では見えなかった
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(L("保存", "Save")) {
                        Task { await save() }
                    }
                    .font(.body.weight(.semibold))
                    // 押せない間は真鍮にしない（明示した色は disabled でも薄くならない）
                    .foregroundStyle(loaded ? WebTheme.accent : WebTheme.muted2)
                    // **読めるまで押させない。** 押せてしまうと、
                    // 空の欄がそのまま「消す」として送られる
                    .disabled(!loaded)
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
        .onChange(of: avatarItem) { _, item in
            Task { await upload(item, kind: .avatar) }
        }
        .onChange(of: coverItem) { _, item in
            Task { await upload(item, kind: .cover) }
        }
    }

    /// カバーとアイコンの見本（板の上端）。**押すとそのまま選び直せる**
    private var imagesHeader: some View {
        Section {
            ZStack(alignment: .topLeading) {
                RemoteImage(url: (userId ?? auth.userId).flatMap { UserProfile.profileAssetURL(userId: $0, suffix: "cover", cacheBust: imageBust) })
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .background(WebTheme.surface)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        PhotosPicker(selection: $coverItem, matching: .images) {
                            Label(L("カバーを変える", "Change cover"), systemImage: "photo")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(Color.black.opacity(0.55), in: Capsule())
                        }
                        // **行の中に押せるものが2つある。** 既定の形だと行全体が
                        // 1つのボタンになり、押した方と違う選択が開く（`ThemeColorField` と同じ手当て）
                        .buttonStyle(.borderless)
                        .padding(12)
                    }
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    RemoteImage(url: (userId ?? auth.userId).flatMap { UserProfile.profileAssetURL(userId: $0, suffix: nil, cacheBust: imageBust) })
                        .frame(width: 84, height: 84)
                        .background(WebTheme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 3))
                        .overlay {
                            Image(systemName: "camera")
                                .font(.footnote)
                                .frame(width: 32, height: 32)
                                .background(Color.black.opacity(0.55), in: Circle())
                        }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("アイコンを変える", "Change avatar"))
                .padding(.leading, 20)
                .padding(.top, 92)
            }
            .frame(height: 178, alignment: .top)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// 欄の上に小さい見出し（板の「表示名」などの置き方）
    private func labeled<Field: View>(_ title: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.muted)
            // 見出しは別の Text なので、欄そのものに名前を付ける（無いと読み上げが「テキストフィールド」だけになる）
            field()
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// BGM（モック2-9 の「BGM」の行）。**先頭の1曲だけを触る。**
    /// Web 版の2曲目以降は残したまま送り返す
    private var bgmSection: some View {
        Section {
            if let song = songs.first {
                SongRow(song: song)
                Button(L("別の曲にする", "Pick another")) { showSongPicker = true }
                Button(role: .destructive) {
                    // **先頭だけ外す。** 丸ごと消すと Web のプレイリストを壊す
                    if !songs.isEmpty { songs.removeFirst() }
                } label: {
                    Text(L("BGM を外す", "Remove BGM"))
                }
            } else {
                Button {
                    showSongPicker = true
                } label: {
                    Label(L("BGM を選ぶ", "Choose BGM"), systemImage: "music.note")
                }
            }
        } header: {
            Text(L("BGM", "BGM"))
        } footer: {
            Text(songs.count > 1
                 ? L("マイページには先頭の1曲が出ます。ほかに\(songs.count - 1)曲あります（ウェブで並べ替えられます）。",
                     "Your page shows the first track. \(songs.count - 1) more are saved (reorder them on the web).")
                 : L("30秒の試聴が、あなたのマイページで流せるようになります。",
                     "A 30-second preview people can play on your page."))
        }
        .listRowBackground(Color.clear)
        .sheet(isPresented: $showSongPicker) {
            SongPickerView { picked in
                // 先頭に据える。**同じ曲が下に残らないように**取り除いてから
                songs.removeAll { $0.previewUrl == picked.previewUrl }
                songs.insert(picked, at: 0)
            }
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
        userId = profile.userId
        displayName = profile.displayName ?? ""
        username = profile.username ?? ""
        bio = profile.bio ?? ""
        website = profile.website ?? ""
        instagram = profile.instagram ?? ""
        statusText = profile.statusText ?? ""
        homeLocation = profile.homeLocation ?? ""
        themeColor = profile.themeColor ?? ""
        songs = profile.songs ?? []
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
            homeLocation: homeLocation,
            themeColor: themeColor,
            songs: songs,
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
            imageBust = UUID().uuidString
            message = kind == .avatar ? L("アイコンを変えました", "Avatar updated") : L("カバーを変えました", "Cover updated")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("画像を変えられませんでした", "Couldn't update the image")
        }
    }
}
