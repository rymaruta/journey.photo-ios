import SwiftUI
import PhotosUI
// 差し替えた画像を見本に出す（UIImage・SwiftUI / PhotosUI から見えることに頼らない）
import UIKit

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
    /// この画面で差し替えた画像（送った本体から作る）。**見本はこちらを出す**（`EditPreview`）
    @State private var replacedPreview: Image?
    /// 未保存の変更があるときの「閉じる」・下へ払うの確認（`unsavedCloseGuard`）
    @State private var showLeaveConfirm = false
    /// 色を編集し直す元（公開中の画像）を読んでいる最中（`PhotoRecolor`）
    @State private var isLoadingRecolor = false
    /// 色を編集し直す元を読む仕事。**閉じたら取り消す**（読み込み中も「閉じる」で抜けられる）
    @State private var recolorLoad: Task<Void, Never>?
    /// 色の編集画面を開いている元の画像と、始めるレシピ（全画面・`PhotoEditView`）
    @State private var recolorSource: RecolorSource?
    /// 差し替えに失敗した・止まった回の、元の画像と最後の調整内容（「もう一度」で開き直す）
    @State private var recolorRetry: PhotoRecolor.Retry?
    /// この画面で差し替えた本体。**続けて色を編集するときはこちらを元にする**
    /// （`photo.src` は開いたときの前の画像のまま）
    @State private var replacedData: Data?

    init(photo: Photo) {
        self.photo = photo
        // 開いたときの欄は `EditPhotoChanges.Fields(opening:)`（閉じるときの「変えたか」と同じ起点）
        let opened = EditPhotoChanges.Fields(opening: photo)
        _title = State(initialValue: opened.title)
        _caption = State(initialValue: opened.caption)
        _location = State(initialValue: opened.location)
        _tagsText = State(initialValue: opened.tagsText)
        _category = State(initialValue: opened.category)
        _date = State(initialValue: opened.date)
        _published = State(initialValue: opened.published)
        _audience = State(initialValue: opened.audience)
        let known = EditPhotoChanges.openedAudience(photo)
        audienceKnown = known != nil
        openedAudience = known
    }

    var body: some View {
        Form {
            Section {
                // 差し替えた回は送った画像を出す（開いたときの URL は前の写真・`EditPreview`）
                switch EditPreview.source(replaced: replacedPreview, original: photo.detailImageURL) {
                case .replaced(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .accessibilityLabel(L("差し替えた写真", "Replaced photo"))
                case .original(let url):
                    // 周りに押す操作の無い1枚なので、押して読み直せる（`RemoteImage.allowsManualRetry`）
                    RemoteImage(url: url, contentMode: .fit, allowsManualRetry: true)
                        .frame(maxHeight: 200)
                }
                if isReplacing {
                    HStack { ProgressView(); Text(L("差し替えています…", "Replacing…")) }
                } else if isLoadingRecolor {
                    HStack { ProgressView(); Text(L("写真を読み込んでいます…", "Loading the photo…")) }
                } else {
                    PhotosPicker(selection: $replaceItem, matching: .images) {
                        Label(L("写真を差し替える", "Replace the photo"), systemImage: "photo.on.rectangle.angled")
                    }
                    // 保存の途中は差し替えさせない（保存ボタンと同じ門）
                    .disabled(isSaving)
                    // 投稿した写真の色を編集し直す（`PhotoRecolor`）。**隣の行と同じ形・白のまま**
                    // ——写真のある画面の欄なので真鍮にしない（デザインの板「黒塗りの真鍮」）
                    Button {
                        startRecolorLoad()
                    } label: {
                        Label(L("色を編集", "Edit colors"), systemImage: "slider.horizontal.3")
                    }
                    .disabled(isSaving)
                    .accessibilityHint(L("投稿した写真の上に重ねて、色を編集し直します",
                                         "Re-edit the colors, layered on top of the posted photo"))
                    .accessibilityIdentifier("editPhoto.recolor")
                }
            } footer: {
                // 派生（AVIF・小さい版）はサーバーが消して作り直す
                Text(L("題や説明はそのままで、写真だけを入れ替えます。反映まで数分かかります。",
                       "Swaps the image only, keeping the title and description. It takes a few minutes to appear."))
            }
            .listRowBackground(Color.clear)

            Section(L("この写真について", "About this photo")) {
                // 題は投稿の画面と同じ上限で止める（超えたぶんはサーバーが黙って切る）
                TextField(L("題", "Title"), text: $title)
                    .onChange(of: title) { old, value in
                        let kept = PostLimits.limited(old: old, new: value, limit: PostLimits.title)
                        if kept != value { title = kept }
                    }
                // 🔴 **説明は欄で止めない**（Web の `/user/edit` と同じ）。送る形で上限が変わり、
                // 全体を 2000 で切ると英語の説明がある写真で後ろの段落が消えた。超えていれば
                // 保存の前に知らせる（`LocalizedEdit.descriptionOverLimit`）
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
                        // 保存・差し替えの最中は先へ進ませない（右上の「閉じる」と同じ）
                        .disabled(isBusy)
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
                    // 色の差し替えが失敗した・止まった回は、最後の調整内容から開き直せる
                    if let retry = recolorRetry {
                        Button {
                            recolorSource = RecolorSource(data: retry.source, recipe: retry.recipe)
                        } label: {
                            Label(L("もう一度", "Try again"), systemImage: "arrow.clockwise")
                        }
                        .disabled(isBusy)
                        .accessibilityHint(L("最後に調整した内容から、色の編集を開き直します",
                                             "Reopens the color editor with your last adjustments"))
                        .accessibilityIdentifier("editPhoto.recolorRetry")
                    }
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
                .disabled(isBusy)
            }
            .listRowBackground(Color.clear)
        }
        .webScreen()
        .navigationTitle(L("写真を編集", "Edit photo"))
        .navigationBarTitleDisplayMode(.inline)
        // 🔴 **直した欄を黙って捨てさせない**（バグ探し 2026-10-03）。以前は保存・差し替えの
        // 最中しか止めず、題や撮影地を直したあと下へ払う・「閉じる」で確かめもなく消えた。
        // 変更がある間は払っても閉じず、「閉じる」で確かめる（ストーリー作成と同じ `unsavedCloseGuard`）。
        // 保存・差し替えの最中は払っても閉じない（`.wait`）
        .unsavedCloseGuard(leave, isPresented: $showLeaveConfirm,
                           title: L("変更を保存しますか？", "Save your changes?"),
                           // 説明が上限を超えている間は出さない（保存と同じ関所・`canSaveAndClose`）。
                           // 保存・差し替えの最中は `.wait` で確認そのものが出ない
                           canSave: EditPhotoChanges.canSaveAndClose(photo: photo, fields: fields),
                           saveTitle: L("保存して閉じる", "Save and close"),
                           discardTitle: L("変更を捨てる", "Discard changes"),
                           message: L("保存しないで閉じると、直した内容は残りません。",
                                      "If you close without saving, your edits will be lost."),
                           // 保存は成功したときだけ閉じる（失敗なら開いたまま知らせを出す・`save`）
                           onSave: { Task { await save() } },
                           onDiscard: { dismiss() })
        .onChange(of: replaceItem) { _, item in
            Task { await replace(item) }
        }
        // 色の編集（投稿のときと同じ画面を全画面で・`UploadView` と同じ出し方）。
        // レシピは無編集から始める——投稿時の編集は公開中の画像にもう焼き込まれている
        .fullScreenCover(item: $recolorSource) { target in
            let source = target.data
            PhotoEditView(recipe: target.recipe, source: { source }, note: PhotoRecolor.note,
                          onDone: { recipe in
                              recolorSource = nil
                              Task { await finishRecolor(source: source, recipe: recipe) }
                          },
                          onCancel: { recolorSource = nil })
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // 保存・差し替えの最中は閉じさせない。閉じると詳細が古い姿のまま残り、
                // 失敗の知らせも見えない
                // 色の編集の元を読んでいる間は閉じられる（読み込みは取り消す・`blocksClosing`）
                Button(Labels.Common.close) {
                    switch leave {
                    case .now:
                        recolorLoad?.cancel()
                        dismiss()
                    case .confirm: showLeaveConfirm = true
                    case .wait: break
                    }
                }
                .disabled(PhotoRecolor.blocksClosing(isSaving: isSaving, isReplacing: isReplacing,
                                                    isLoadingRecolor: isLoadingRecolor))
            }
        }
        // 下へ払って閉じた回・「変更を捨てる」で閉じた回も、読み込みを残さない
        .onDisappear { recolorLoad?.cancel() }
    }

    /// 保存・差し替え・色の編集の元を読んでいる最中か（閉じる・保存・先へ進むを止める門）
    private var isBusy: Bool { isSaving || isReplacing || isLoadingRecolor }

    /// いま欄に入っている姿（`EditPhotoChanges`）
    private var fields: EditPhotoChanges.Fields {
        EditPhotoChanges.Fields(title: title, caption: caption, location: location,
                                pickedCoords: pickedCoords, tagsText: tagsText, category: category,
                                date: date, published: published, audience: audience)
    }

    /// 「閉じる」・下へ払うの扱い（`EditPhotoChanges.leave`）
    private var leave: UnsavedLeave {
        EditPhotoChanges.leave(photo: photo, openedAudience: openedAudience, fields: fields,
                               isSaving: PhotoRecolor.blocksClosing(isSaving: isSaving, isReplacing: isReplacing,
                                                    isLoadingRecolor: isLoadingRecolor))
    }

    /// 写真そのものを差し替える。**EXIF は端末で落としてから送る**（投稿と同じ関所）。
    private func replace(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isReplacing = true
        message = nil
        // 写真そのものを替えるので、前の画像に重ねる「もう一度」は残さない
        recolorRetry = nil
        defer {
            isReplacing = false
            // **選択を戻す。** 戻さないと、同じ写真をもう一度選んでも
            // `onChange` が起きず、何も起きない
            replaceItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            // **縮小・EXIF の書き直しは主スレッドの外で**（投稿の `prepareOffMain` と同じ）。
            // 大きい写真だと、差し替え中の表示ごと画面が固まっていた
            let prepared = try await Task.detached(priority: .userInitiated) {
                try ImagePreparer.prepare(data: data, fileName: "photo", withThumbnail: true)
            }.value
            // ピンの無い写真・この画面で撮影地を消した写真に、差し替えた写真の位置を書かない
            let spots = await PlaceCoordsRule.index(
                current: [],
                needed: photo.coords != nil && EditPlaceRules.needsSpotIndex(
                    openedLocation: photo.location, currentLocation: location, pickedCoords: false,
                    photoCoords: prepared.coords),
                fetch: { [spots = environment.spots] in try? await spots.fetchIndex() })
            let keep = EditPlaceRules.keepsCoordsOnReplace(openedLocation: photo.location,
                                                           openedHasCoords: photo.coords != nil,
                                                           currentLocation: location,
                                                           newPhotoCoords: prepared.coords, spots: spots)
            let keptOldDate = try await environment.photos.replace(photoId: photo.id, prepared: prepared,
                                                                   uploads: environment.uploads,
                                                                   keepCoords: keep)
            // 続けて色を編集するときの元（`photo.src` は前の画像のまま）
            replacedData = prepared.data
            // 見本を差し替えた画像に替える（サーバーの小さい版は作り直しに数分かかる）
            if let image = UIImage(data: prepared.data) {
                replacedPreview = Image(uiImage: image)
            }
            messageIsError = false
            message = L("差し替えました（反映まで数分かかります）", "Replaced. It takes a few minutes to appear.")
            // 撮影日を載せなかった回は、前の撮影日が残ることを言う（黙って古い日付を残さない）
            if keptOldDate {
                message = (message ?? "") + "\n" + L("撮影日は前のままです（1990年より前・未来の日付は入れられません）",
                                                     "The date taken is unchanged (dates before 1990 or in the future can't be set).")
            }
        } catch {
            messageIsError = true
            message = (error as? LocalizedError)?.errorDescription
                ?? L("差し替えられませんでした", "Couldn't replace it")
        }
    }

    /// 「色を編集」。読み込みの仕事を持っておく（閉じたら取り消す）
    private func startRecolorLoad() {
        guard !isBusy else { return }
        if let replacedData {
            recolorSource = RecolorSource(data: replacedData, recipe: .identity)
            return
        }
        // **仕事を作る前に印を立てる**（二度押しで読み込みが2本走らない・`isBusy` が次の押下を止める）
        isLoadingRecolor = true
        message = nil
        recolorRetry = nil
        recolorLoad = Task { await openRecolor() }
    }

    /// 公開中の画像（この画面で差し替えたならその本体）を読んで、編集画面を開く。
    /// 403（URL の期限切れ）なら写真を取り直して1回だけ読み直す（`PhotoRecolor.loadSource`）
    @MainActor
    private func openRecolor() async {
        // 印は `startRecolorLoad` が立てた。下ろすのはここ（取り消された回も）
        defer { isLoadingRecolor = false }
        do {
            let photos = environment.photos
            let id = photo.id
            let data = try await PhotoRecolor.loadSource(
                url: photo.detailImageURL,
                refreshURL: { try await photos.myPhoto(id: id)?.detailImageURL },
                fetch: { try await PhotoRecolor.fetchSource(from: $0) })
            // 閉じた後に読み終えた回は開かない
            guard !Task.isCancelled else { return }
            recolorSource = RecolorSource(data: data, recipe: .identity)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            messageIsError = true
            message = (error as? LocalizedError)?.errorDescription
                ?? L("写真を読み込めませんでした", "Couldn't load the photo")
        }
    }

    /// 色の編集の「完了」（`PhotoRecolor.finish`）。無編集なら何も送らない。
    /// 変えていれば書き出して差し替える——**撮影情報は載せず**（今の値を残す）、代表色を載せる。
    /// 差し替えの印は `isReplacing` を使い回す（保存・閉じる・写真の差し替えと重ならない）。
    /// 失敗した・止まった回は最後の調整内容を残す（「もう一度」）
    @MainActor
    private func finishRecolor(source: Data, recipe: PhotoRecipe) async {
        let result = await PhotoRecolor.finish(
            recipe: recipe,
            source: source,
            isBusy: { isBusy },
            setReplacing: { on in
                isReplacing = on
                if on {
                    message = nil
                    recolorRetry = nil
                }
            },
            export: { recipe in
                // 書き出し（Core Image・JPEG・EXIF の関所）は主スレッドの外で
                try await Task.detached(priority: .userInitiated) {
                    try PhotoRenderer.shared.exportPrepared(source: source, recipe: recipe,
                                                            base: PhotoRecolor.base(source: source))
                }.value
            },
            send: { prepared in
                _ = try await environment.photos.replace(photoId: photo.id, prepared: prepared,
                                                         uploads: environment.uploads,
                                                         keepCurrentMetadata: true)
            })
        switch result {
        case .unchanged:
            break
        case .busy(let retry), .failed(_, let retry):
            // 409（ストーリーから残した写真）はサーバーの文言そのまま（`PhotoRecolor.finish`）
            recolorRetry = retry
        case .replaced(let prepared):
            recolorRetry = nil
            replacedData = prepared.data
            // 見本を書き出した画像に替える（写真の差し替えと同じ・`EditPreview`）
            if let image = UIImage(data: prepared.data) {
                replacedPreview = Image(uiImage: image)
            }
        }
        if let notice = PhotoRecolor.notice(for: result) {
            messageIsError = notice.isError
            message = notice.text
        }
    }

    private func save() async {
        // 🔴 **差し替えの途中は保存しない。** 差し替えは始めた時点の撮影地で「座標を残すか」を
        // 決めて送るので、途中で撮影地を消して保存すると、あとから届いた差し替えが
        // 写真の位置を書き戻していた（消したはずのピンが地図に戻る）
        // **色の編集の元を読んでいる間は止めない**（確認の「保存して閉じる」が何もしなかった）。
        // 読み込みは取り消してから保存する（`PhotoRecolor.blocksSaving`）
        guard !PhotoRecolor.blocksSaving(isSaving: isSaving, isReplacing: isReplacing,
                                         isLoadingRecolor: isLoadingRecolor) else { return }
        recolorLoad?.cancel()
        // 送るとサーバーが黙って切る長さなら、保存させずに知らせる
        if let over = LocalizedEdit.descriptionOverLimit(original: photo.description, field: caption) {
            messageIsError = true
            message = over
            return
        }
        isSaving = true
        message = nil
        defer { isSaving = false }

        // 差分の決まりは `EditPhotoChanges.patch`（閉じるときの確認と同じ判断）
        // 書き換えた撮影地が写真の近くのスポットを指すか（`PlaceCoordsRule`）を見る索引。要るときだけ少し待つ
        let spots = await PlaceCoordsRule.index(
            current: [],
            needed: EditPlaceRules.needsSpotIndex(openedLocation: photo.location, currentLocation: location,
                                                  pickedCoords: pickedCoords != nil, photoCoords: photo.coords),
            fetch: { [spots = environment.spots] in try? await spots.fetchIndex() })
        let patch = EditPhotoChanges.patch(photo: photo, openedAudience: openedAudience, fields: fields, spots: spots)

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
            // 公開を触っていない回（`patch.published` が nil）は何もしない
            if let published = patch.published {
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

/// 色の編集画面を開く元（`fullScreenCover(item:)` の鍵）
private struct RecolorSource: Identifiable {
    let id = UUID()
    let data: Data
    /// 始めるレシピ。ふつうは無編集、「もう一度」は最後の調整内容
    let recipe: PhotoRecipe
}
