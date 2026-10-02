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
    /// 読み込んだ時点の欄。🔴 **保存ではこれと比べて、変えた欄だけを送る**
    /// （`ProfileDraft.patch`）——全部送ると、開いている間に別の端末で直した
    /// 表示名・BGM などを開いた時点の値へ巻き戻す
    @State private var original: ProfileDraft?
    @State private var message: String?
    /// 保存の失敗。**アラートで出す**——保存は右上なので、フォームの中に出すと
    /// 下に流していれば上の画面外、上にいれば下の画面外になる
    @State private var saveError: String?
    /// アイコン／カバーを送っている間（`upload`）。**その間は保存も戻るも止める**——
    /// 戻れてしまうと送り終わる前の古い画像が前の画面に出たままになり、
    /// 保存と重なると後から来た方がどちらかを上書きする
    @State private var uploadingImage: ProfileService.ImageKind?

    var body: some View {
        Form {
            imagesHeader

            // **知らせは上に出す。** 保存は右上なので、下に出すと失敗しても
            // 「押しても何も起きない」に見える（読めなかった警告も同じ）
            if let message {
                Section { Text(message).font(.callout) }
                    .listRowBackground(Color.clear)
            }

            Section {
                labeled(L("表示名", "Display name"), over: PostLimits.overLimitNote(displayName, limit: PostLimits.Profile.displayName)) {
                    TextField("", text: $displayName)
                        .onChange(of: displayName, limitLength($displayName, to: PostLimits.Profile.displayName, loaded: \.displayName))
                }
                labeled(L("ユーザー名（半角英数）", "Username (letters and numbers)")) {
                    TextField("", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                labeled(L("自己紹介", "Bio"), over: PostLimits.overLimitNote(bio, limit: PostLimits.Profile.bio)) {
                    // 板の下書き「ひとこと」は付けない——下の「そのほか」に同じ名前の欄
                    // （statusText）があり、どちらに書くのか紛れる
                    TextField("", text: $bio, axis: .vertical)
                        .lineLimit(2...6)
                        .onChange(of: bio, limitLength($bio, to: PostLimits.Profile.bio, loaded: \.bio))
                }
                // 板は居住地と Instagram を横に2つ並べる
                HStack(alignment: .top, spacing: 10) {
                    labeled(L("居住地", "Where you're based"), over: PostLimits.overLimitNote(homeLocation, limit: PostLimits.Profile.homeLocation)) {
                        TextField("", text: $homeLocation)
                            .onChange(of: homeLocation, limitLength($homeLocation, to: PostLimits.Profile.homeLocation, loaded: \.homeLocation))
                    }
                    labeled(L("Instagram（@なし）", "Instagram (without @)"), over: PostLimits.overLimitNote(instagram, limit: PostLimits.Profile.instagram)) {
                        TextField("", text: $instagram)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: instagram, limitLength($instagram, to: PostLimits.Profile.instagram, loaded: \.instagram))
                    }
                }
            }
            .listRowBackground(Color.clear)

            bgmSection

            // **板に無い3つ。** 消すとアプリから直せなくなるので、最後にまとめて残す
            Section(L("そのほか", "More")) {
                labeled(L("ひとこと", "Status"), over: PostLimits.overLimitNote(statusText, limit: PostLimits.Profile.statusText)) {
                    TextField("", text: $statusText)
                        .onChange(of: statusText, limitLength($statusText, to: PostLimits.Profile.statusText, loaded: \.statusText))
                }
                ThemeColorField(themeColor: $themeColor)
                labeled(L("ウェブサイト", "Website"), over: PostLimits.overLimitNote(website, limit: PostLimits.Profile.website)) {
                    TextField("", text: $website)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .onChange(of: website, limitLength($website, to: PostLimits.Profile.website, loaded: \.website))
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
                if isSaving || uploadingImage != nil {
                    ProgressView()
                } else {
                    Button(L("保存", "Save")) {
                        // 🔴 **門は押したその場で閉じる。** `isSaving` を Task の中で立てて
                        // いたので、描き直しの前に2回押すと保存が2本走った
                        // （`HighlightEditorView`・`DeleteAccountView` と同じ）
                        guard !isSaving else { return }
                        isSaving = true
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
        // 画像の送信中・保存中は戻らせない（戻れると保存の結果を見届けられない）
        .navigationBarBackButtonHidden(uploadingImage != nil || isSaving)
        .interactiveDismissDisabled(uploadingImage != nil || isSaving)
        .alert(L("保存できませんでした", "Couldn't save"),
               isPresented: Binding(get: { saveError != nil },
                                    set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
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
                // 写真は重ね（overlay）に置く——引き伸ばした写真を直に包むと、横長の
                // カバーで行の幅が画面より広くなる（写真の詳細で踏んだのと同じ）
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .overlay {
                        RemoteImage(url: (userId ?? auth.userId).flatMap { UserProfile.profileAssetURL(userId: $0, suffix: "cover", cacheBust: imageBust) })
                    }
                    .background(WebTheme.surface)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        PhotosPicker(selection: $coverItem, matching: .images) {
                            Label(L("カバーを変える", "Change cover"), systemImage: "photo")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(Color.black.opacity(0.55), in: Capsule())
                                // 見た目は 36pt、押せる高さは 44pt（下の余白を 4pt 減らして位置は変えない）
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                        }
                        // **行の中に押せるものが2つある。** 既定の形だと行全体が
                        // 1つのボタンになり、押した方と違う選択が開く（`ThemeColorField` と同じ手当て）
                        .buttonStyle(.borderless)
                        // **保存中・送信中は選ばせない**（保存と画像の送信を重ねない）
                        .disabled(isSaving || uploadingImage != nil)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
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
                .disabled(isSaving || uploadingImage != nil)
                .accessibilityLabel(L("アイコンを変える", "Change avatar"))
                .padding(.leading, 20)
                .padding(.top, 92)
            }
            .frame(height: 178, alignment: .top)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// **上限で止める**（`PostLimits.Profile`）。サーバーは超えたぶんを黙って切るので、
    /// 保存してから縮んでいたことに気づけなかった。止め方は `HighlightEditorView` の名前の欄と同じ
    /// （`PostLimits.limited`: 入れようとした字のほうを削る・UTF-16 の単位で数える）。
    /// **読み込んだ値を入れた回は切らない**（`PostLimits.limitedEdit`）
    private func limitLength(_ text: Binding<String>, to limit: Int,
                             loaded field: KeyPath<ProfileDraft, String>) -> (String, String) -> Void {
        { old, new in
            let kept = PostLimits.limitedEdit(old: old, new: new, limit: limit,
                                              loaded: original?[keyPath: field])
            if kept != new { text.wrappedValue = kept }
        }
    }

    /// 欄の上に小さい見出し（板の「表示名」などの置き方）
    /// - Parameter over: 保存されていた値が上限を超えているときの知らせ（`PostLimits.overLimitNote`）。
    ///   超えていなければ nil で、何も出さない
    private func labeled<Field: View>(_ title: String, over: String? = nil,
                                      @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.muted)
                // 欄そのものに同じ名前を付けてあるので、見出しは読まない（2回読まれる）
                .accessibilityHidden(true)
            // 見出しは別の Text なので、欄そのものに名前を付ける（無いと読み上げが「テキストフィールド」だけになる）
            field()
                .accessibilityLabel(title)
            // **読み込んだ値が上限を超えている欄だけ**、保存で切れることを知らせる（危険の色・12pt）
            if let over {
                Text(over)
                    .font(.caption)
                    .foregroundStyle(WebTheme.danger)
            }
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
                    // 危険の色はテーマの赤（無指定だと系統の赤 #FF453A になる）
                    Text(L("BGM を外す", "Remove BGM"))
                        .foregroundStyle(WebTheme.danger)
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
            // **包む。** シートは呼び手の `NavigationStack` を引き継がないので、
            // 包まないと見出し・閉じる・検索欄（`searchable`）が出ない
            // （写真の投稿・ストーリーの呼び手は前から包んでいる）
            NavigationStack {
                SongPickerView { picked in
                    songs = ProfileSongs.replacingFirst(songs, with: picked)
                }
            }
        }
    }

    private func load() async {
        // **読めた後は読み直さない。** タブを替えて戻るなどで `.task` が走り直すと、
        // まだ保存していない入力がサーバーの値で上書きされていた
        guard !loaded else { return }
        isLoading = true
        defer { isLoading = false }
        guard let profile = try? await environment.profiles.myProfile() else {
            message = L("いまの内容を読み込めませんでした。開き直してください（このまま保存すると消えてしまいます）",
                        "Couldn't load your current profile. Please reopen this screen (saving now would erase it).")
            return
        }
        userId = profile.userId
        let draft = ProfileDraft(profile: profile)
        original = draft
        displayName = draft.displayName
        username = draft.username
        bio = draft.bio
        website = draft.website
        instagram = draft.instagram
        statusText = draft.statusText
        homeLocation = draft.homeLocation
        themeColor = draft.themeColor
        songs = draft.songs
        loaded = true
    }

    /// いま欄に入っている姿
    private var edited: ProfileDraft {
        ProfileDraft(username: username, displayName: displayName, bio: bio,
                     website: website, instagram: instagram, statusText: statusText,
                     homeLocation: homeLocation, themeColor: themeColor, songs: songs)
    }

    /// 呼ぶ前に `isSaving` を立てておくこと（ボタンが同期で立てる）。戻るときは必ず下ろす
    private func save() async {
        defer { isSaving = false }
        // **読めていない内容で上書きしない。**
        //
        // 読み込みに失敗すると欄は全部空のまま出る。サーバーは
        // 「キーがある＝指定した、値が空＝消す」で読む
        // （`api-user/src/userProfile.ts` の `apply`）ので、そのまま
        // 保存すると**表示名・ユーザー名・自己紹介・リンク・ひとこと・
        // テーマ色が全部消える**。取り返しがつかない。
        guard loaded, let original else {
            message = L("いまの内容を読み込めていないので保存できません。開き直してください",
                        "Can't save before your current profile is loaded. Please reopen this screen.")
            return
        }
        // 🔴 **変えた欄だけを送る**（`ProfileDraft.patch`）。開いた時点の値を全部
        // 送っていたので、開いている間に Web で直した表示名・BGM が巻き戻り、
        // ユーザー名も毎回送るので、いまの規則に合わない古い名前の人は
        // 何を直しても 400 で保存できなかった。
        // **何も変えていなければ送らずに閉じる**（Web も投げずに「保存しました」。
        // サーバーは空の変更でも rev を進めるので、別の端末の保存を無駄に競合させる）
        guard let patch = ProfileDraft.patch(from: original, to: edited) else {
            dismiss()
            return
        }
        message = nil
        do {
            try await environment.profiles.update(patch)
            // マイページに読み直させる（ログイン直後の表示名と同じ知らせ）
            auth.noteProfileChanged()
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? L("もう一度お試しください", "Please try again")
        }
    }

    private func upload(_ item: PhotosPickerItem?, kind: ProfileService.ImageKind) async {
        guard let item else { return }
        // 送っている最中に次を選ばれたら、選択だけ戻して受け付けない
        guard uploadingImage == nil else {
            if kind == .avatar { avatarItem = nil } else { coverItem = nil }
            return
        }
        uploadingImage = kind
        // 送っている間の表示（知らせの欄・右上は ProgressView）
        message = kind == .avatar ? L("アイコンを送っています…", "Uploading avatar…")
                                  : L("カバーを送っています…", "Uploading cover…")
        // **選択を戻す。** 戻さないと、同じ写真をもう一度選んでも `onChange` が
        // 起きず何も起きない（`EditPhotoView` の差し替えと同じ）
        defer {
            uploadingImage = nil
            if kind == .avatar { avatarItem = nil } else { coverItem = nil }
        }
        do {
            // 中身を取り出せなかった（iCloud から落とせない等）ときは
            // **「送っています…」を残さず、黙りもしない**
            guard let data = try await item.loadTransferable(type: Data.self) else {
                message = L("画像を読み込めませんでした", "Couldn't load the image")
                return
            }
            // アイコンにも同じ関所を通す。**EXIF の付いた自撮りを
            // そのまま上げない**（撮影地が入っていることがある）
            // **縮小・EXIF の書き直しは画面の処理の外で**（`EditPhotoView` の差し替えと同じ）。
            // 1枚に数百ミリ秒かかり、その間「送っています…」の表示ごと画面が止まっていた
            let prepared = try await Task.detached(priority: .userInitiated) {
                try ImagePreparer.prepare(data: data, fileName: "profile")
            }.value
            try await environment.profiles.uploadProfileImage(kind: kind, jpeg: prepared.data)
            imageBust = UUID().uuidString
            message = kind == .avatar ? L("アイコンを変えました", "Avatar updated") : L("カバーを変えました", "Cover updated")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("画像を変えられませんでした", "Couldn't update the image")
        }
    }
}

