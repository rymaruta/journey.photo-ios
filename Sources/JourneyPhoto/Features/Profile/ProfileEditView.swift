import SwiftUI
import PhotosUI
import UIKit

/// プロフィールの編集。名前・自己紹介・リンクと、アイコン／カバー。
///
/// アーティファクト 32 の写真見本と右上の保存を保ち、
/// 入力欄は基本情報・場所とリンク・ひとこと／テーマ色などに分ける。
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
    @State private var pendingAvatar: Data?
    @State private var pendingCover: Data?
    @State private var avatarPreview: UIImage?
    @State private var coverPreview: UIImage?
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
    /// 写真の準備中は保存と戻るを止める。
    @State private var preparingImage: ProfileService.ImageKind?
    /// 変えた欄があるときの戻るの確認（`unsavedLeaveGuard`）
    @State private var showLeaveConfirm = false
    /// 読めたプロフィール（名前の横の画面に渡す）
    @State private var loadedProfile: UserProfile?
    /// 名前の横の画面（メダルを1つ選ぶ）。**入口はここ**（2026-10-09 owner:「入り口はプロフィールを編集の中でいい」）
    @State private var showNameSide = false

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
                labeled(L("ユーザー名", "Username")) {
                    TextField(L("半角英数字", "Letters and numbers"), text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                labeled(L("自己紹介", "Bio"), over: PostLimits.overLimitNote(bio, limit: PostLimits.Profile.bio),
                        multiline: true) {
                    // 板の下書き「ひとこと」は付けない——下の演出欄に同じ名前の欄
                    // （statusText）があり、どちらに書くのか紛れる
                    // 行数は `bioLines` の注記（owner 2026-10-12: 枠が小さい）
                    TextField(L("好きな写真や旅について", "Tell people about your photography and travels"), text: $bio, axis: .vertical)
                        .lineLimit(Self.bioLines)
                        .onChange(of: bio, limitLength($bio, to: PostLimits.Profile.bio, loaded: \.bio))
                }
            } header: {
                Text(L("基本情報", "About you"))
            }
            .listRowBackground(Color.clear)

            Section {
                labeled(L("居住地", "Where you're based"), over: PostLimits.overLimitNote(homeLocation, limit: PostLimits.Profile.homeLocation)) {
                    TextField(L("例：東京都", "e.g. Tokyo"), text: $homeLocation)
                        .onChange(of: homeLocation, limitLength($homeLocation, to: PostLimits.Profile.homeLocation, loaded: \.homeLocation))
                }
                labeled(L("Instagram", "Instagram"), over: PostLimits.overLimitNote(instagram, limit: PostLimits.Profile.instagram)) {
                    TextField(L("ユーザー名（@なし）", "Username without @"), text: $instagram)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: instagram, limitLength($instagram, to: PostLimits.Profile.instagram, loaded: \.instagram))
                }
                labeled(L("ウェブサイト", "Website"), over: PostLimits.overLimitNote(website, limit: PostLimits.Profile.website)) {
                    TextField(L("https://", "https://"), text: $website)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: website, limitLength($website, to: PostLimits.Profile.website, loaded: \.website))
                }
            } header: {
                Text(L("場所とリンク", "Location and links"))
            }
            .listRowBackground(Color.clear)

            Section {
                labeled(L("ひとこと", "Status"), over: PostLimits.overLimitNote(statusText, limit: PostLimits.Profile.statusText)) {
                    TextField(L("短いひとこと", "A short status"), text: $statusText)
                        .onChange(of: statusText, limitLength($statusText, to: PostLimits.Profile.statusText, loaded: \.statusText))
                }
                ThemeColorField(themeColor: $themeColor)
                    .listRowInsets(EdgeInsets(top: 8, leading: ProfileV2.gutter, bottom: 8, trailing: ProfileV2.gutter))
            }
            .listRowBackground(Color.clear)

            bgmSection

            nameSideSection

        }
        .disabled(isSaving)
        .webScreen()
        .navigationTitle(L("プロフィールの編集", "Edit profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // **保存は右上**（板）。以前はフォームの一番下にあり、長い画面では見えなかった
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving || preparingImage != nil {
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
                    .disabled(!loaded || preparingImage != nil)
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        // 写真も含め、保存前の変更を戻る確認に含める。
        // 変えた欄がある間は標準の戻るを隠し、自前の戻るで「保存して戻る／変更を捨てる」を
        // 確かめる（親しい友達・旅行プランと同じ `unsavedLeaveGuard`）。画像の準備中・保存中は
        // 戻らせない（戻れると保存の結果を見届けられない。以前の戻るを隠す門と同じ）
        .unsavedLeaveGuard(leave, isPresented: $showLeaveConfirm, canSave: loaded,
                           // 自前の戻るにも前の画面の題を添える（標準の「‹ マイページ」と同じ見た目・旅行プランと同じ形）
                           backTitle: Labels.Navigation.mypage,
                           message: L("保存しないで戻ると、直した内容は残りません。",
                                      "If you go back without saving, your edits will be lost."),
                           onSave: {
                               // 右上の「保存」と同じ門（押したその場で閉じる）。成功したら `save` が閉じる
                               guard loaded, !isSaving, preparingImage == nil else { return }
                               isSaving = true
                               Task { await save() }
                           },
                           onDiscard: { dismiss() })
        .alert(L("保存できませんでした", "Couldn't save"),
               isPresented: Binding(get: { saveError != nil },
                                    set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task { await load() }
        // 名前の横の画面（板 61）。🔴 **Form の欄（Section）に付けない**（2026-10-09 owner「メダルを回す
        // 全画面で戻れなくなった」）。一覧の中の欄に付けたシートから、さらに全画面（メダルを回す）を
        // 開くと、閉じる操作が届かなくなった。マイページと同じく画面の外側に付ける
        // 閉じたら**バッジの値だけ**読み直す（入力中の欄は触らない）。読み直さないと、
        // 名前の横の画面で決めたあとにもう一度開くと、決める前の選択で開いていた
        // （2026-10-09 バグ調査 高-2: 「なし」にして決める → 開き直すと前のバッジが選ばれて見える）
        .sheet(isPresented: $showNameSide, onDismiss: { Task { await reloadBadgeState() } }) {
            if let loadedProfile {
                NameSideBadgeView(profile: loadedProfile)
            }
        }
        .onChange(of: avatarItem) { _, item in
            Task { await stage(item, kind: .avatar) }
        }
        .onChange(of: coverItem) { _, item in
            Task { await stage(item, kind: .cover) }
        }
    }

    /// カバーとアイコンの見本（板 v2 ProfileEdit の上端）。**見える場所でそのまま選び直せる**。
    ///
    /// v2: カバーは端 16・高さ 150・角 16 の札で、右下にガラスの「カバーを変える」（写真の上なので白の字）。
    /// アイコンは 84pt を札の下端に 40pt 重ね（黒い 4pt の縁）、右下に白い 28pt のカメラの丸（墨の印・
    /// 黒 3pt の縁）——どこを押せば変わるかを絵で言う
    private var imagesHeader: some View {
        Section {
            ZStack(alignment: .topLeading) {
                // 写真は重ね（overlay）に置く——引き伸ばした写真を直に包むと、横長の
                // カバーで行の幅が画面より広くなる（写真の詳細で踏んだのと同じ）
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.coverHeight)
                    .overlay {
                        if let coverPreview {
                            Image(uiImage: coverPreview).resizable().scaledToFill()
                        } else {
                            RemoteImage(url: (userId ?? auth.userId).flatMap { UserProfile.profileAssetURL(userId: $0, suffix: "cover", cacheBust: imageBust) })
                        }
                    }
                    .background(WebTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
                    .overlay(alignment: .bottomTrailing) {
                        PhotosPicker(selection: $coverItem, matching: .images) {
                            Label(L("カバーを変える", "Change cover"), systemImage: "camera")
                                .font(JPFont.footnote.weight(.semibold))
                                .foregroundStyle(WebTheme.foreground)
                                .padding(.horizontal, 14)
                                .frame(minHeight: JPHeight.inlineButton)
                                .jpGlass(in: Capsule())
                                // 見た目は 36pt、押せる高さは 44pt
                                .padding(.vertical, ProfileV2.tapSlack(visible: JPHeight.inlineButton))
                                .contentShape(Rectangle())
                        }
                        // **行の中に押せるものが2つある。** 既定の形だと行全体が
                        // 1つのボタンになり、押した方と違う選択が開く（`ThemeColorField` と同じ手当て）
                        .buttonStyle(.borderless)
                        // 保存中・写真の準備中は選ばせない
                        .disabled(!loaded || isSaving || preparingImage != nil)
                        .padding(.trailing, 10)
                        .padding(.bottom, 6)
                    }
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Group {
                        if let avatarPreview {
                            Image(uiImage: avatarPreview).resizable().scaledToFill()
                        } else {
                            RemoteImage(url: (userId ?? auth.userId).flatMap { UserProfile.profileAssetURL(userId: $0, suffix: nil, cacheBust: imageBust) })
                        }
                    }
                        .frame(width: Self.avatarSide, height: Self.avatarSide)
                        .background(WebTheme.card)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: ProfileCover.cutoutWidth)
                            .padding(-ProfileCover.cutoutWidth))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WebTheme.accentText)
                                .frame(width: 28, height: 28)
                                .background(Color.white, in: Circle())
                                .overlay(Circle().strokeBorder(Color.black, lineWidth: 3).padding(-3))
                                .offset(x: 2, y: 2)
                        }
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!loaded || isSaving || preparingImage != nil)
                .accessibilityLabel(L("アイコンを変える", "Change avatar"))
                .padding(.leading, JPSpace.m)
                .padding(.top, Self.coverHeight - 40)
            }
            .frame(height: Self.coverHeight - 40 + Self.avatarSide + ProfileCover.cutoutWidth, alignment: .top)
        } footer: {
            Text(L("写真・文字・BGMは右上の「保存」で反映されます。バッジは選択画面で決定します。",
                   "Save photos, text and BGM with the button above. Confirm badges on their selection screen."))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: ProfileV2.gutter, bottom: 0, trailing: ProfileV2.gutter))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// 板 v2 ProfileEdit: カバーの札の高さ 150・アイコン 84
    nonisolated static let coverHeight: CGFloat = 150
    nonisolated static let avatarSide: CGFloat = 84
    /// 名前の列の幅（板 v2 の `.fr`: 104）。値がどの行でも同じ所から始まる
    nonisolated static let labelColumn: CGFloat = 104
    /// 自己紹介の欄の行数。板は高さ 88（2〜3行）だが、owner（2026-10-12）が「枠が小さい」と言ったので、
    /// 空でも5行分を開け、300字（`PostLimits.Profile.bio`）までは12行まで伸ばす。
    /// 2026-10-17 判断: v2 の行は `labeled` が上下 14 を取るので、欄に余白や最小の高さは足さない
    /// （行数の下限だけで5行分が開く）
    nonisolated static let bioLines: ClosedRange<Int> = 5...12

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

    /// 名前と値の2列の行（板 v2 ProfileEdit「名前と値を2列の表にして欄の縁を消した」）。
    /// 左に 104 の名前（13・text-2）、右に値（16）。行は 52 以上・下に白 8% の区切り。
    /// 複数行（自己紹介）は名前を上にそろえる
    /// - Parameter over: 保存されていた値が上限を超えているときの知らせ（`PostLimits.overLimitNote`）。
    ///   超えていなければ nil で、何も出さない
    private func labeled<Field: View>(_ title: String, over: String? = nil, multiline: Bool = false,
                                      @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            HStack(alignment: multiline ? .firstTextBaseline : .center, spacing: 0) {
                Text(title)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .frame(width: Self.labelColumn, alignment: .leading)
                    // 欄そのものに同じ名前を付けてあるので、見出しは読まない（2回読まれる）
                    .accessibilityHidden(true)
                // 見出しは別の Text なので、欄そのものに名前を付ける（無いと読み上げが「テキストフィールド」だけになる）
                field()
                    .font(.callout)
                    .foregroundStyle(WebTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(title)
            }
            .padding(.vertical, 14)
            .frame(minHeight: JPHeight.row)
            // **読み込んだ値が上限を超えている欄だけ**、保存で切れることを知らせる（危険の色・12pt）
            if let over {
                Text(over)
                    .font(.caption)
                    .foregroundStyle(WebTheme.danger)
                    .padding(.leading, Self.labelColumn)
                    .padding(.bottom, JPSpace.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: ProfileV2.gutter, bottom: 0, trailing: ProfileV2.gutter))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// 札の中の行（BGM・名前の横）。板 v2 ProfileEdit の BGM の行: 左に真鍮の線の印（黒地の上）、
    /// 15 の名前と 12 の text-3 の説明、右に矢印。64 以上・下に白 8% の区切り
    private func linkRow(title: String, detail: String?, systemImage: String) -> some View {
        HStack(spacing: JPSpace.s) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(WebTheme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                if let detail {
                    Text(detail)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .frame(minHeight: JPHeight.tallRow)
        .contentShape(Rectangle())
    }

    /// 名前の横のバッジ（持っているメダルから1つ・Pro マークの形）。板 32 の BGM の行と同じ形の行で、
    /// 押すと名前の横の画面（板 61）。マイページで名前を押しても同じ画面が開く
    private var nameSideSection: some View {
        Section {
            Button {
                showNameSide = true
            } label: {
                linkRow(title: L("名前の横のバッジ", "Badge beside your name"), detail: nil, systemImage: "medal")
            }
            .buttonStyle(.plain)
            .disabled(loadedProfile == nil)
            .accessibilityIdentifier("profileEdit.nameSide")
            .listRowInsets(EdgeInsets(top: 0, leading: ProfileV2.gutter, bottom: 0, trailing: ProfileV2.gutter))
        } header: {
            Text(L("バッジ", "Badges"))
        } footer: {
            Text(L("持っているメダルから1つ選んで、名前の横に飾れます。",
                   "Pick one of your medals to show beside your name."))
        }
        .listRowBackground(Color.clear)
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
                    // 板 v2: 真鍮の音符の行・説明は行の中に
                    linkRow(title: L("BGM を選ぶ", "Choose BGM"),
                            detail: L("30秒の試聴が、あなたのマイページで流せるようになります。",
                                      "A 30-second preview people can play on your page."),
                            systemImage: "music.note")
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: ProfileV2.gutter, bottom: 0, trailing: ProfileV2.gutter))
            }
        } header: {
            Text(L("BGM", "BGM"))
        } footer: {
            // 曲を選ぶ前の説明は行の中（`linkRow`）に移した。選んだあとは同じ説明をここに
            Text(songs.count > 1
                 ? L("マイページには先頭の1曲が出ます。ほかに\(songs.count - 1)曲あります（ウェブで並べ替えられます）。",
                     "Your page shows the first track. \(songs.count - 1) more are saved (reorder them on the web).")
                 : songs.isEmpty ? "" : L("30秒の試聴が、あなたのマイページで流せるようになります。",
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

    /// 名前の横の画面を閉じたあと、プロフィールのバッジの値だけ読み直す（`loadedProfile`）。
    /// 表示名などの入力中の欄・比べる元（`original`）は触らない
    private func reloadBadgeState() async {
        guard loaded, let fresh = try? await environment.profiles.myProfile() else { return }
        loadedProfile = fresh
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
        loadedProfile = profile
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

    /// 写真も保存待ちの変更として数える。
    private var leave: UnsavedLeave {
        let textChanged = original.map { ProfileDraft.patch(from: $0, to: edited) != nil } ?? false
        return UnsavedLeave.decide(
            hasChanges: textChanged || pendingAvatar != nil || pendingCover != nil,
            isSaving: isSaving || preparingImage != nil
        )
    }

    /// 成功した項目だけを保存済みにする。残りは次の保存で再試行できる。
    private func save() async {
        defer { isSaving = false }
        // 押した人。🔴 **次の人のプロフィールに書かない**（2026-10-17）。
        // 名前の保存のあとにアイコンを上げるので、その間にアカウントが替わると、
        // 前の人が選んだ絵が次の人のアイコンになる（置き場所は今のログインの `profiles/<uid>`）
        let sender = auth.userId
        guard Self.keepsSave(sender: sender, viewer: auth.userId) else { return }
        guard loaded, let original else {
            message = L("いまの内容を読み込めていないので保存できません。開き直してください",
                        "Can't save before your current profile is loaded. Please reopen this screen.")
            return
        }

        let draft = edited
        let patch = ProfileDraft.patch(from: original, to: draft)
        guard patch != nil || pendingAvatar != nil || pendingCover != nil else {
            dismiss()
            return
        }
        message = nil

        if let patch {
            do {
                try await environment.profiles.update(patch)
                guard Self.keepsSave(sender: sender, viewer: auth.userId) else { return }
                self.original = draft
                auth.noteProfileChanged()
            } catch {
                guard Self.keepsSave(sender: sender, viewer: auth.userId) else { return }
                saveError = (error as? LocalizedError)?.errorDescription ?? L("もう一度お試しください", "Please try again")
                return
            }
        }

        for kind in [ProfileService.ImageKind.avatar, .cover] {
            let data = kind == .avatar ? pendingAvatar : pendingCover
            guard let data else { continue }
            guard Self.keepsSave(sender: sender, viewer: auth.userId) else { return }
            do {
                try await environment.profiles.uploadProfileImage(kind: kind, jpeg: data)
                guard Self.keepsSave(sender: sender, viewer: auth.userId) else { return }
                if kind == .avatar {
                    pendingAvatar = nil
                    avatarPreview = nil
                } else {
                    pendingCover = nil
                    coverPreview = nil
                }
                if let uid = userId ?? auth.userId {
                    ProfileImageVersions.shared.bump(uid)
                    imageBust = ProfileImageVersions.shared.token(for: uid)
                } else {
                    imageBust = UUID().uuidString
                }
                auth.noteProfileChanged()
            } catch {
                guard Self.keepsSave(sender: sender, viewer: auth.userId) else { return }
                let name = kind == .avatar ? L("アイコン", "Avatar") : L("カバー", "Cover")
                let reason = (error as? LocalizedError)?.errorDescription ?? L("通信を確認してください", "Check your connection")
                saveError = L("\(name)を保存できませんでした。保存済みの項目は反映されています。もう一度「保存」で残りを試せます。\n\(reason)",
                              "Couldn't save \(name). Completed changes are already applied. Tap Save to retry the remaining changes.\n\(reason)")
                return
            }
        }
        guard Self.keepsSave(sender: sender, viewer: auth.userId) else { return }
        dismiss()
    }

    /// 保存の答えを書くか。**押した人が、まだその人のときだけ**
    nonisolated static func keepsSave(sender: String?, viewer: String?) -> Bool {
        sender != nil && sender == viewer
    }

    private func stage(_ item: PhotosPickerItem?, kind: ProfileService.ImageKind) async {
        guard let item else { return }
        guard preparingImage == nil, !isSaving else {
            if kind == .avatar { avatarItem = nil } else { coverItem = nil }
            // 黙って選択だけ消すと壊れているように見える——忙しい理由を出す
            message = isSaving
                ? L("保存が終わるまでお待ちください", "Please wait until saving finishes")
                : L("いま準備中です。終わってから選んでください", "Still preparing. Please choose again when it finishes")
            return
        }
        preparingImage = kind
        message = kind == .avatar ? L("アイコンを準備しています…", "Preparing avatar…")
                                  : L("カバーを準備しています…", "Preparing cover…")
        defer {
            preparingImage = nil
            if kind == .avatar { avatarItem = nil } else { coverItem = nil }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                message = L("画像を読み込めませんでした", "Couldn't load the image")
                return
            }
            // GPS/EXIF を除去できた JPEG だけをプレビューと送信に使う。
            let prepared = try await Task.detached(priority: .userInitiated) {
                try ImagePreparer.prepare(data: data, fileName: "profile")
            }.value
            guard let preview = UIImage(data: prepared.data) else {
                message = L("画像を表示できませんでした", "Couldn't preview the image")
                return
            }
            if kind == .avatar {
                pendingAvatar = prepared.data
                avatarPreview = preview
            } else {
                pendingCover = prepared.data
                coverPreview = preview
            }
            message = L("写真を選びました。右上の「保存」で反映されます。",
                        "Photo selected. Tap Save to apply it.")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("画像を準備できませんでした", "Couldn't prepare the image")
        }
    }
}
