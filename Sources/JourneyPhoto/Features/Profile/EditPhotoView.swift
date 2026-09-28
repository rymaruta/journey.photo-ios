import SwiftUI
import PhotosUI

/// 自分の写真を直す（題・説明・撮影地・タグ・撮影日・公開）。
struct EditPhotoView: View {

    let photo: Photo

    @EnvironmentObject private var environment: AppEnvironment
    /// 非公開にした・公開に戻した写真を、公開一覧から落とす／戻す（`hideGone`）
    @EnvironmentObject private var hidden: ModerationStore
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
    /// 公開範囲。**既にある値から始める**——分からない値のときは
    /// 触らせない（`audienceKnown` が false のとき、この段を出さない）。
    /// 知らない値に上書きさせると、サーバーが選択肢を増やした直後に
    /// 古いアプリが**意図しない範囲へ広げる**。
    @State private var audience: Audience
    private let audienceKnown: Bool
    /// 開いたときの範囲（知らない値なら nil）。変えたときだけ送るために覚える
    private let openedAudience: Audience?
    @State private var isSaving = false
    @State private var message: String?
    /// 直近の知らせが「できた」か。**成功を赤で出さない**
    @State private var messageIsError = true
    /// 写真そのものの差し替え（Web の `/user/edit` と同じ操作）
    @State private var replaceItem: PhotosPickerItem?
    @State private var isReplacing = false

    init(photo: Photo) {
        self.photo = photo
        _title = State(initialValue: LocalizedEdit.titleField(photo.title))
        _caption = State(initialValue: LocalizedEdit.descriptionField(photo.description))
        _location = State(initialValue: photo.location ?? "")
        _tagsText = State(initialValue: (photo.tags ?? []).joined(separator: ", "))
        _category = State(initialValue: photo.category ?? "")
        _date = State(initialValue: EditDay.field(date: photo.date))
        _published = State(initialValue: photo.published != false)
        let raw = photo.audience ?? ""
        let known = raw.isEmpty ? Audience.everyone : Audience(rawValue: raw)
        _audience = State(initialValue: known ?? .everyone)
        audienceKnown = known != nil
        openedAudience = known
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
            .listRowBackground(Color.clear)

            Section(L("この写真について", "About this photo")) {
                // 投稿の画面と同じ上限で止める（超えたぶんはサーバーが黙って切る）
                TextField(L("題", "Title"), text: $title)
                    .onChange(of: title) { _, value in
                        let clamped = PostLimits.clamp(value, limit: PostLimits.title)
                        if clamped != value { title = clamped }
                    }
                TextField(L("説明", "Description"), text: $caption, axis: .vertical)
                    .lineLimit(3...8)
                    .onChange(of: caption) { _, value in
                        let clamped = PostLimits.clamp(value, limit: PostLimits.description)
                        if clamped != value { caption = clamped }
                    }
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
            .listRowBackground(Color.clear)

            Section {
                Toggle(L("公開する", "Public"), isOn: $published)
                // **軌道は暗い真鍮。** 既定の tint（白）だと、入れたときに白い軌道に
                // 白いつまみが乗り、入か切かが見えない
                .tint(WebTheme.accentDeep)
            } footer: {
                Text(L("非公開にすると、サイトの一覧と個別ページから消えます（反映まで数分）。", "Making it private removes it from the site within a few minutes."))
            }
            .listRowBackground(Color.clear)

            // 誰に見せるか。**公開しているときだけ**出す
            // （非公開は誰にも見えないので絞りようが無い）。
            // 知らない値が入っている写真では出さない——上書きで広げないため
            if published && audienceKnown {
                Section {
                    Picker(L("誰に見せるか", "Who can see it"), selection: $audience) {
                        ForEach(Audience.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    if audience == .closeFriends {
                        NavigationLink {
                            CloseFriendsView()
                        } label: {
                            Label(L("親しい友達を選ぶ", "Pick close friends"), systemImage: "star")
                                .font(.subheadline)
                        }
                    }
                } footer: {
                    Text(audience.photoNote)
                }
                .listRowBackground(Color.clear)
            }

            if let message {
                Section {
                    Text(message).font(.callout)
                        .foregroundStyle(messageIsError ? WebTheme.danger : WebTheme.faint)
                }
                .listRowBackground(Color.clear)
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
                // 差し替えの間も押させない（下の `save` の注記）
                .disabled(isSaving || isReplacing)
            }
            .listRowBackground(Color.clear)
        }
        .webScreen()
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
            // ピンの無い写真・この画面で撮影地を消した写真に、差し替えた写真の位置を書かない
            let keep = EditPlaceRules.keepsCoordsOnReplace(openedLocation: photo.location,
                                                           openedHasCoords: photo.coords != nil,
                                                           currentLocation: location)
            try await environment.photos.replace(photoId: photo.id, prepared: prepared,
                                                 uploads: environment.uploads,
                                                 keepCoords: keep)
            messageIsError = false
            message = L("差し替えました（反映まで数分かかります）", "Replaced. It takes a few minutes to appear.")
        } catch {
            messageIsError = true
            message = (error as? LocalizedError)?.errorDescription
                ?? L("差し替えられませんでした", "Couldn't replace it")
        }
    }

    private func save() async {
        // 🔴 **差し替えの途中は保存しない。** 差し替えは始めた時点の撮影地で「座標を残すか」を
        // 決めて送るので、途中で撮影地を消して保存すると、あとから届いた差し替えが
        // 写真の位置を書き戻していた（消したはずのピンが地図に戻る）
        guard !isSaving, !isReplacing else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }

        var patch = PhotoPatch()
        // **触った欄だけ、英語側を残して送る**（`LocalizedEdit`）。
        // 表示用の1言語を平文で送っていたので、`{ja, en}` の写真を
        // 保存するたびに英語の題と説明が消えていた
        patch.title = LocalizedEdit.title(original: photo.title, field: title)
        patch.description = LocalizedEdit.description(original: photo.description, field: caption)
        // **変えた項目だけ送る**（Web の `/user/edit` の `changedFields` と同じ）。
        // 開いた時点の値を毎回全部送っていたので、古い写し（公開 JSON は
        // 建て直しまで古い）から開いてタグだけ直すと、Web で直した説明や
        // 撮影地が黙って巻き戻っていた
        if location != (photo.location ?? "") || pickedCoords != nil {
            patch.location = location
        }
        // **選んだ回だけ載せる。** nil は「触らない」なので、
        // 地名を手で直しただけの回に既存の座標を壊さない
        patch.coords = pickedCoords
        // **本人が撮影地を空にしたら座標も消す。** nil だけでは「触らない」になり、
        // 地図とページにピンが残っていた（投稿画面の `locationClearedByUser` と同じ考え・`EditPlaceRules`）。
        // 開いたときから空の写真（圏外で投稿して撮影地が入らなかった等）は座標を残す
        patch.clearCoords = EditPlaceRules.clearsCoords(openedLocation: photo.location,
                                                        currentLocation: location,
                                                        pickedCoords: pickedCoords != nil)
        // タグは欄と同じ割り方で比べる（区切りの文字を含む古いタグは欄に出した
        // 時点で割れて見えるので、元の配列と直に比べると毎回「変わった」になる）
        let tags = TagInput.parse(tagsText)
        if tags != TagInput.parse((photo.tags ?? []).joined(separator: ", ")) {
            patch.tags = tags
        }
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCategory != (photo.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
            patch.category = trimmedCategory
        }
        // 公開と公開範囲も**変えたときだけ**（`EditVisibilityRules`）。知らない値の写真では
        // 範囲を送らない——キーを外せばサーバーは既にある印を残す
        let visibility = EditVisibilityRules.patch(openedPublished: photo.published != false,
                                                   openedAudience: openedAudience,
                                                   published: published, audience: audience)
        patch.published = visibility.published
        patch.audience = visibility.audience
        // **触っていなければ送らない**（時刻付きの撮影日を日付だけに落とさない）。
        // 入っていた日付を消したら空文字を送る（サーバーが撮影日を消す）
        patch.date = EditDay.toSend(opened: EditDay.field(date: photo.date),
                                    field: date)

        // **何も変えていなければ送らない。** 空の本文はサーバーが 400「更新項目が
        // ありません」で断る（公開を毎回送っていた頃はそれが覆っていた）
        if patch.isEmpty {
            dismiss()
            return
        }
        // 送る**前に**取る（待っている間に人が替わっていたら印を付けない）
        let owner = hidden.owner
        do {
            try await environment.photos.update(photoId: photo.id, patch: patch)
            // 🔴 **非公開にしたら公開一覧から落とす。** 一覧は建て直しまで古い
            // 静的 JSON なので、非公開にした写真がホーム・探す・地図に出続けていた。
            // **公開に戻したら印を外す**（外さないと、建て直した後もこの端末でだけ出ない）。
            // 公開を触っていない回（`visibility.published` が nil）は何もしない
            if let published = visibility.published {
                if published {
                    await hidden.unhideGone(photo.id, for: owner, environment: environment)
                } else {
                    await hidden.hideGone(photo.id, for: owner, environment: environment)
                }
            }
            dismiss()
        } catch {
            messageIsError = true
            message = (error as? LocalizedError)?.errorDescription ?? L("保存できませんでした", "Couldn't save")
        }
    }
}
