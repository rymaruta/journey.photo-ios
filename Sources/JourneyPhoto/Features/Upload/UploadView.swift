import SwiftUI
import PhotosUI

struct UploadView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var joined: JoinedAlbumsStore
    /// 撮影スポットの索引を読むため（`model.fetchSpotIndex`）。撮影地の欄（`PlaceSearchField`）も同じものを読む
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model: UploadViewModel
    @State private var showCamera = false
    @State private var showSongPicker = false
    /// 「この写真を見て撮影」の元の写真を選ぶ画面（`InspiredPickerView`・2026-10-14）
    @State private var showInspiredPicker = false
    @State private var showLibrary = false
    @State private var appliedInitialSpot = false
    /// 「構図を重ねて撮る」で撮った1枚を入れたか（一度だけ・2026-10-10）
    @State private var appliedInitialCapture = false
    /// 「書きかけを捨てて閉じますか？」
    @State private var confirmDiscard = false
    /// 「下書きを続けますか？」（開いたときに一度だけ・`UploadDraftRules.asksRestore`・2026-10-11）
    @State private var showRestore = false
    /// 開いたときの問いをもう済ませたか（選ぶ画面・カメラから戻るたびに onAppear が走る）
    @State private var askedRestore = false
    /// 「書きかけの続きがあります」（自動で残した書きかけ・送れなかった投稿・2026-10-16）
    @State private var showRestoreAuto = false
    /// 「送れなかった投稿があります」で尋ねている控え（古い順に1件ずつ・2026-10-16）
    @State private var askingJournal: String?
    /// 裏に回ったら書きかけを黙って残す（`UploadViewModel.autoSaveDraft`）
    @Environment(\.scenePhase) private var scenePhase
    /// 編集画面を開いている写真（帯のサムネを押した）
    @State private var editing: EditTarget?
    /// 編集できない理由（再試行の鍵を控えている写真・`UploadEditRules.canEdit`）
    @State private var editLockMessage: String?

    /// 「写真を押すと編集できます」の案内（写真を選んだ直後に一度だけ・`UploadEditEntry.showsHint`）
    @State private var showEditHint = false
    /// 「詳しい設定」（公開範囲・曲・アルバム・SNS・カテゴリ）を開いているか。**畳んで始める**
    /// （2026-10-03 判断・`UploadDetails`）。畳んでいても今の値は行の右に出る
    @State private var showsDetails = false
    /// 写真を選ぶ画面を自動で開いたか（一度だけ・`UploadDetails.autoOpensLibrary`）
    @State private var offeredLibrary = false

    /// 編集画面の行き先（写真の id）
    private struct EditTarget: Identifiable { let id: UUID }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 最初から入れておくタグ（今日のテーマの「参加する」から来たとき）。
    /// **入れるだけで、消せる**——決めつけない
    private let initialTag: String?
    /// スポットの画面から開いたときの行き先
    private let initialSpot: UploadSpotTarget?
    /// スポットのページに並ぶ形で1枚上がるたび・全部上がって閉じるときに呼ぶ。
    /// 渡すのは**スポットのページに並ぶ形で上がった枚数**（スポットの画面が
    /// 「投稿しました」を出すか決める）。**何度呼ばれても同じ結果になる受け手に渡す**
    private let onPosted: ((Int) -> Void)?
    /// 最初から並べておく写真（旅の写真からまとめて来たとき・`LibraryTripFlowView`）。
    /// **整えてあるもの**（選ぶ画面が読みながら1枚ずつ `ImagePreparer` に通した）。**一度だけ入れる**
    private let initialPhotos: [ImagePreparer.Prepared]
    /// 非公開で始める（旅の写真から来たとき）。**変えられる**——決めつけない
    private let startPrivate: Bool
    /// 最初から入れておく、カメラで撮った1枚（投稿のシートの「構図を重ねて撮る」で撮って
    /// 「投稿」を押したとき・2026-10-10）。帯の「追加」→カメラと同じ道（`UploadViewModel.accept(capture:)`）で入れる
    private let initialCapture: CameraCapture?
    /// 起動のときの「送れなかった投稿があります」で「続きから」を押して来た。**もう一度尋ねずに戻す**（2026-10-16）
    private let resumeJournal: String?

    init(initialTag: String? = nil, spot: UploadSpotTarget? = nil, onPosted: ((Int) -> Void)? = nil,
         initialPhotos: [ImagePreparer.Prepared] = [], startPrivate: Bool = false,
         initialCapture: CameraCapture? = nil,
         resumeJournal: String? = nil,
         onSaved: ((Photo) -> Void)? = nil) {
        self.resumeJournal = resumeJournal
        // 画面写真の試験だけ: 見本の1枚を選んだ状態で開く（`PreviewSession.opensUploadSample`・Debug のみ。
        // 鍵の無いときは nil で、ふだんの投稿画面は変わらない）
        self.initialCapture = initialCapture ?? PreviewUploadSample.capture()
        self.initialTag = initialTag
        self.initialSpot = spot
        self.onPosted = onPosted
        self.initialPhotos = initialPhotos
        self.startPrivate = startPrivate
        // AppEnvironment を init で受け取れない（EnvironmentObject は body 以降）
        // ため、ここでは既定の組み立てを使う
        let api = APIClient.app()
        // （`StateObject` の引数は最初の1回だけ評価される。毎回の init でモデルを作らない）
        _model = StateObject(wrappedValue: {
            let model = UploadViewModel(
                // 見本の通信（UI テスト）では本体も端末の中の答え手へ（`UploadService.app`・ふだんは背景の転送）
                uploads: UploadService.app(api: api),
                albums: AlbumService(api: api),
                photos: PhotoService(api: api),
                discovery: DiscoveryService(api: api)
            )
            // 保存が通った行を外へ渡す（下の「投稿」から開いたときだけ・`TabRouter.notePosted`）
            model.onSaved = onSaved
            return model
        }())
    }

    var body: some View {
        Group {
            if auth.isResolving {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if auth.userId == nil {
                SignInView(reason: L("写真を投稿するにはログインしてください", "Sign in to post a photo"))
            } else {
                form
            }
        }
        .navigationTitle(L("新規投稿", "New post"))
        .navigationBarTitleDisplayMode(.inline)
        // **閉じる口を置く。** シートで出しているので、下に払う以外の
        // 出口が無いと戻れないと思う人が出る
        // 板 22: 左に ×、右に真鍮の「投稿する」（下の大きいボタンはやめる）
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // 🔴 **書きかけを黙って捨てない**（2026-09-30）。選んだ写真と書いた題・説明が
                // 確認なしで消えていた。写真を選び始めたら一度聞く（旅行プランの日程と同じ判断）
                // v2 Upload・Components 04「シート · 左に『キャンセル』/右に確定（真鍮の字）」。
                // 以前は ×。動き（書きかけがあれば確かめる）は同じ
                Button {
                    if model.hasDraft {
                        confirmDiscard = true
                    } else {
                        // 中身が無くなった自動の書きかけ・この画面の控えを片づけてから閉じる（モデルの注記）
                        model.closeWithoutDraft()
                        dismiss()
                    }
                } label: {
                    Text(Labels.Common.cancel)
                        .font(.body)
                        .foregroundStyle(WebTheme.text2)
                }
                .accessibilityLabel(Labels.Common.cancel)
                // 🔴 **送っている間は閉じさせない。** 閉じても送信は裏で続き、
                // 残りの写真が公開され、失敗の知らせは閉じた画面に書かれていた。
                // 途中でやめるのは送信中の「やめる」（`model.cancel()`）
                .disabled(model.isWorking)
            }
            if auth.userId != nil {
                ToolbarItem(placement: .confirmationAction) { submitButton }
            }
        }
        // 🔴 **人が替わったら、この画面の書きかけを誰の下書きにも保存しない**（前の人の写真が
        // 次の人の下書きに入る）。下書きは人ごと（`UploadDraftStore`）
        .onChange(of: auth.userId) { _, id in
            if model.draftOwner != id { model.draftOwner = nil }
            // 「撮影地の位置を付ける」も次の人の値に替える（前の人の値を使わない・2026-10-18）
            model.useLocationOwner(id)
        }
        // 書きかけがある間は、下へ払っても閉じない（× で確かめてから）
        .interactiveDismissDisabled(model.isWorking || model.hasDraft)
        // 2026-10-11: **「下書きに保存」を足した**（端末に残す・`UploadDraftStore`）。以前は
        // 「投稿をやめる」「書き続ける」の2択で、閉じると選んだ写真と題・説明が全部消えていた。
        // 保存できないとき（読み込み中・送りかけ）は出さずに理由を言う（`UploadDraftRules.closeDialog`）
        .confirmationDialog(closeDialog.title, isPresented: $confirmDiscard, titleVisibility: .visible) {
            if closeDialog.canSave {
                Button(L("下書きに保存", "Save draft")) { saveDraftAndClose() }
            }
            Button(L("投稿をやめる", "Stop posting"), role: .destructive) {
                // 閉じる確認で「下書きから外します」と言うので、閉じた時点で外す（モデルの注記）
                model.dropUnsureDraftPhotos()
                // やめると決めたので、黙って残した書きかけ・この画面の送信の控えも消す（次に開いて尋ねない）
                model.discardAutoDraft()
                model.discardJournal()
                dismiss()
            }
            Button(L("書き続ける", "Keep editing"), role: .cancel) { }
        } message: {
            Text(closeDialog.message)
        }
        // 開いたときに一度だけ。黙って戻すと、新しく投稿しに来た人が前の写真に驚く（ストーリーと同じ）
        .alert(L("下書きを続けますか？", "Continue your draft?"), isPresented: $showRestore) {
            Button(L("続ける", "Continue")) { restoreDraft() }
            Button(L("下書きを削除", "Delete draft"), role: .destructive) {
                model.discardDraft()
                openLibraryAfterRestorePrompt()
            }
        } message: {
            Text(L("この端末に保存した下書きがあります。続きから編集できます。",
                   "You have a draft saved on this device. You can pick up where you left off."))
        }
        // 🔴 **アプリが途中で終了した書きかけ**（2026-10-16）。裏に回ったときに黙って残した分
        // （`autoSaveDraft`）。本人の下書きとは別の枠なので、別に尋ねる
        .alert(L("書きかけの続きがあります", "Pick up where you left off?"), isPresented: $showRestoreAuto) {
            Button(L("続きから", "Continue")) { restoreDraft(from: .auto) }
            Button(L("削除", "Delete"), role: .destructive) {
                model.discardAutoDraft()
                openLibraryAfterRestorePrompt()
            }
        } message: {
            Text(L("前回、投稿の途中でアプリが終了しました。続きから編集できます。",
                   "The app closed while you were writing a post. You can pick up where you left off."))
        }
        // 🔴 **送れなかった投稿**（送信の控え・古い順に1件ずつ・2026-10-16）。残りは次に開いたとき
        .alert(L("送れなかった投稿があります", "A post didn\u{2019}t finish sending"),
               isPresented: Binding(get: { askingJournal != nil }, set: { if !$0 { askingJournal = nil } }),
               presenting: askingJournal) { id in
            Button(L("続きから", "Continue")) { restoreDraft(from: .send(id)) }
            Button(L("削除", "Delete"), role: .destructive) {
                if let owner = model.draftOwner { model.drafts?.sibling(.send(id)).clear(for: owner) }
                openLibraryAfterRestorePrompt()
            }
            // 「あとで」は控えに触らない（次に開いたとき・次の起動でまた尋ねる。起動時の知らせと同じ形）
            Button(L("あとで", "Later"), role: .cancel) { openLibraryAfterRestorePrompt() }
        } message: { _ in
            Text(L("送り終える前にアプリが終了した投稿です。続きから送り直せます。",
                   "This post didn\u{2019}t finish sending before the app closed. You can send it again."))
        }
        // 裏に回ったら書きかけを黙って残す（OS にアプリを終了されても消えない・2026-10-16）。
        // 裏の猶予は**裏に回ったこの瞬間に**取る（Task が走るのを待つと、その前に止められうる）
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                let window = BackgroundWindow(name: "upload-autosave")
                Task {
                    await model.autoSaveDraft()
                    window.end()
                }
            }
        }
        // **上がった時点で知らせる。** × や下に払って閉じる時点で知らせると、
        // 一部だけ上がった・曲だけ付かなかったまま下に払って閉じた回が漏れる
        .onChange(of: model.postedToSpot) { _, n in
            if n > 0 { onPosted?(n) }
        }
        .onChange(of: model.didPostAll) { _, posted in
            // **全部上がったときだけ閉じる。** 「待ち行列が空」で見ると、
            // 選び直しの読み込み中（一度空にする）にも閉じてしまい、
            // 打った文字ごと消える
            if posted {
                onPosted?(model.postedToSpot)
                // SNS にも載せる回は、共有の画面を閉じてから閉じる（`threadsBundle`）
                if model.threadsBundle == nil { dismiss() }
            }
        }
        .sheet(item: $model.threadsBundle, onDismiss: { dismiss() }) { bundle in
            ShareSheet(images: bundle.images, text: bundle.text)
                .ignoresSafeArea()
                // 共有の画面は半分の高さから（全高に広がると、後ろの投稿画面が見えず何が起きたか分からない）
                .presentationDetents([.medium, .large])
        }
    }

    /// 閉じる確認の中身（`UploadDraftRules.closeDialog`）
    private var closeDialog: UploadDraftRules.CloseDialog {
        UploadDraftRules.closeDialog(block: model.draftSaveBlock,
                                     replacesOther: !model.restoredDraft && model.storedDraft != nil,
                                     restored: model.restoredDraft,
                                     unsure: model.hasUnsureDraftPhotos)
    }

    /// 「下書きに保存」。**書けたときだけ閉じる**（書けなければ上に知らせを出して残る）
    private func saveDraftAndClose() {
        if model.saveDraft() {
            dismiss()
        } else {
            model.errorMessage = L("下書きを保存できませんでした（端末の空き容量を確かめてください）",
                                   "Couldn't save the draft. Check your device's free space.")
        }
    }

    /// 「続ける」。画像が読めなければ何も戻さず、そう言う（選ぶ画面を開く）
    private func restoreDraft(from slot: UploadDraftStore.Slot = .saved) {
        Task {
            guard await model.restoreDraft(from: slot) else {
                // 戻せる写真が無かった（届いたか分からない写真だけだった）ときは、モデルがもう知らせている
                if model.errorMessage == nil {
                    switch slot {
                    case .saved: model.discardDraft()
                    case .auto: model.discardAutoDraft()
                    case .send:
                        if let owner = model.draftOwner { model.drafts?.sibling(slot).clear(for: owner) }
                    }
                    model.errorMessage = L("下書きの写真を読み込めませんでした", "Couldn't load the draft's photos")
                }
                openLibraryAfterRestorePrompt()
                return
            }
        }
    }

    /// 問いに答えたあと、写真がまだ無ければ選ぶ画面を開く（自動で開くのは問いの間は待っている・`form` の task）
    private func openLibraryAfterRestorePrompt() {
        guard !offeredLibrary, model.items.isEmpty else { return }
        Task {
            // 問いが閉じきってから開く（閉じる途中に重ねると出ないことがある）。**開くときにだけ印を付ける**
            // （`form` の task と同じ——待っている間に閉じた回に印だけ残さない）
            try? await Task.sleep(nanoseconds: UploadDetails.autoOpenDelayNanoseconds)
            guard !offeredLibrary, model.items.isEmpty else { return }
            offeredLibrary = true
            openLibrary()
        }
    }

    /// **段ごとに割ってある。** 一本の長い式にすると、Swift の型検査が
    /// 現実的な時間で終わらなくなることがある
    /// （"unable to type-check this expression in reasonable time"）。
    /// 落ちたときに、どの段かがすぐ分かる利点もある。
    /// どのスポットの写真として上げるか。**外せる**（普通の投稿に戻る）。
    /// 撮影地は写真ごとに直せるが、スポットの紐付けは全部の写真に同じものが付く
    private func spotBanner(_ spot: UploadSpotTarget) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(WebTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("撮影スポットの写真として投稿", "Posting to a photo spot"))
                    .font(.caption)
                    .foregroundStyle(WebTheme.text2)
                Text(spot.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                model.removeSpot()
            } label: {
                Text(L("外す", "Remove"))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted)
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 送っている間は外せない——送信は1枚ごとに `spot` を読むので、束の途中で紐付けが割れる
            .disabled(model.isWorking)
            .accessibilityLabel(L("撮影スポットの紐付けを外す", "Don't link to this spot"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.border, lineWidth: 1))
    }

    /// 案内・帯・「写真を編集」・一言。**ひとまとめにしてある**——`form` の VStack に直に並べると
    /// 10 個を超えて型検査が通らない（ViewBuilder の上限）
    @ViewBuilder
    private var photosBlock: some View {
        if showEditHint { editHint }
        strip
        // 帯のすぐ下に「写真を編集」（押せる合図がサムネだけだと気づかれなかった）
        editButton
        if !model.items.isEmpty {
            // 見本 3 の一言。2026-10-03: 何ができるか（色や明るさ）を先に言い、短くした
            // （本文系の最小 12pt＝.caption）
            Text(L("写真を押すと、色や明るさを編集できます。元の写真は変わりません。",
                   "Tap a photo to adjust its color and light. The original stays as it is."))
                .font(.caption)
                .foregroundStyle(WebTheme.text3)
                .padding(.horizontal, 4)
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // **知らせは上に。** 投稿は右上で押すので、下に出すと画面の外になる
                progressAndErrors
                if let spot = model.spot { spotBanner(spot) }
                photosBlock
                // 旅の流れでは切り替えを出さない（いつもまとめる）。代わりに一言
                if let note = UploadGrouping.tripNote(fromTrip: model.fromTripImport, count: model.items.count) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(WebTheme.text3)
                        .padding(.horizontal, 4)
                } else if model.items.count > 1 {
                    groupChoice
                }
                // 撮影地の欄のすぐ上（2026-10-18 判断）。**写真を選ぶ前から出す**——撮影地は読み込んだ瞬間に
                // 写真の位置から引き始めるので、選んでから出しても遅い（Web の切り替えと同じ）
                locationToggle
                detailSection
                inspiredCard
                rowsCard
                tagsAndCategory
                // 板: 本文の最後に注記（板は 11px だが、本文系の最小は 12pt）
                Text(L("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地の座標は約1kmに丸めて保存します。", "Photo metadata (EXIF) is removed on your device before upload. Coordinates are rounded to about 1 km."))
                    .font(.caption)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .webScreen()
        .task(id: joined.entries) { await model.loadAlbums(joined: joined.entries) }
        // 画面写真の試験だけ: 公開一覧の1枚を元の写真に選んだ状態にする（`PreviewSession.showsInspiredSample`・
        // Debug のみ。画面の状態だけで、控えにもサーバーにも書かない）
        .task {
            guard PreviewSession.showsInspiredSample, model.inspired == nil,
                  let feed = try? await environment.gallery.fetchPhotos(),
                  let sample = InspiredBy.previewSample(feed: feed, excluding: nil),
                  model.inspired == nil else { return }
            model.inspired = InspiredBy.Pick(photo: sample)
        }
        // 2026-10-03 判断: **開いたらすぐ写真を選ぶ画面へ**（「追加」→「ライブラリから選ぶ」の2手を省く）。
        // 一度だけ。旅の写真から来た回（もう並んでいる）は開かない。カメラは帯の「追加」に残る
        .task {
            // シートが出きってから開く（出ている途中に重ねると出ないことがある）。待つのは長めに
            // （`UploadDetails.autoOpenDelay`）。それでも出なかった回は「ライブラリから選ぶ」が
            // 立て直す（`openLibrary`）
            try? await Task.sleep(nanoseconds: UploadDetails.autoOpenDelayNanoseconds)
            guard !Task.isCancelled else { return }
            // 「下書きを続けますか？」に答えている間は開かない（答えたあとに開く・`openLibraryAfterRestorePrompt`）
            guard !showRestore, !showRestoreAuto, askingJournal == nil, !model.isRestoringDraft else { return }
            let hasPhotos = !model.items.isEmpty || model.isLoadingPicked || !initialPhotos.isEmpty
                || initialCapture != nil
            guard UploadDetails.autoOpensLibrary(hasPhotos: hasPhotos, alreadyOffered: offeredLibrary,
                                                 isWorking: model.isWorking) else { return }
            // **開いたときにだけ印を付ける。** 待っている間に閉じた回は印を付けない（次に開いたらまた開く）
            offeredLibrary = true
            showLibrary = true
        }
        // 写真を選んだ直後（0枚 → 1枚以上）に、一度だけ案内を出す（旅の写真から来た回も同じ）
        .onChange(of: model.items.isEmpty) { _, empty in
            if !empty { offerEditHint() }
        }
        // 数秒で消す（押せば先に消える・`UploadEditEntry.hintSeconds`）
        .task(id: showEditHint) {
            guard showEditHint else { return }
            try? await Task.sleep(nanoseconds: UInt64(UploadEditEntry.hintSeconds * 1_000_000_000))
            hideEditHint()
        }
        .onAppear {
            // 「撮影地の位置を付ける」の持ち主（人ごとの値・2026-10-18）。**写真を並べるより先に**——
            // 旅の写真・撮った1枚は下で並べた瞬間に撮影地を引き始める（`UploadViewModel.startPlaceLookup`）
            model.useLocationOwner(auth.userId)
            // 投稿で「アルバムが無い」と分かったら、端末の控えからも外す
            model.onAlbumGone = { [joined] id in joined.forget(id: id) }
            // 撮影地が写真の近くのスポットを指すかを見る索引（送るときだけ読む・`PlaceCoordsRule`）。
            // **索引の行だけ**（区分の詳細を待つと、遅い通信で2秒の待ちを過ぎて座標を落とす）
            model.fetchSpotIndex = { [spots = environment.spots] in await spots.fetchIndexRows() }
            // **今日のテーマから来たときだけ、一度だけ。** 既に何か打っていれば触らない。
            // 選択画面などから戻ると onAppear はまた呼ばれるので、印が無いと
            // 利用者が空にしたタグがまた入る（印は model が持つ・送ったあとの reset で下ろす）
            model.initialTag = initialTag
            model.applyInitialTag()
            // 旅の写真と「非公開で始める」も一度だけ（印は model が持つ）
            model.applyInitialPhotos(initialPhotos, startPrivate: startPrivate)
            // **一度だけ入れる**（外したあとに戻さない）
            if let initialSpot, !appliedInitialSpot {
                appliedInitialSpot = true
                model.spot = initialSpot
            }
            // 撮った1枚も一度だけ（外したあとに戻さない）
            if let initialCapture, !appliedInitialCapture {
                appliedInitialCapture = true
                model.accept(capture: initialCapture)
            }
            // 端末の下書き（人ごと・2026-10-11）。開いたときに一度だけ尋ねる
            // 持ち主は**開いたときの人に決める**（途中で人が替わったら、下の onChange が外す）
            if model.drafts == nil { model.drafts = UploadDraftStore() }
            if !askedRestore { model.draftOwner = auth.userId }
            let opensWithContent = !initialPhotos.isEmpty || initialCapture != nil
                || initialTag != nil || initialSpot != nil
            // 送れなかった投稿（控え・古い順に1件）→ アプリが途中で終了した書きかけ → 本人の下書き
            let autoStore = UploadDraftStore(slot: .auto)
            let hasAuto = auth.userId.flatMap { autoStore.draft(for: $0) } != nil
            let journalIds = auth.userId.map { id in model.drafts?.journals(for: id).map(\.id) ?? [] } ?? []
            let action = UploadDraftRules.openAction(journalIds: journalIds, hasAutoDraft: hasAuto,
                                                     hasSavedDraft: model.storedDraft != nil,
                                                     opensWithContent: opensWithContent, alreadyAsked: askedRestore,
                                                     resumeJournal: resumeJournal)
            // 🔴 尋ねていない書きかけには触らない（`ownsAutoSlot`）。触らない回は書きかけの枠を渡さない
            // （送信の控えは投稿ごとの別の枠なので、この回も必ず書く）
            if !askedRestore, UploadDraftRules.ownsAutoSlot(hasAutoDraft: hasAuto, action: action) {
                model.autoDrafts = autoStore
            }
            switch action {
            case .resumeJournal(let id): restoreDraft(from: .send(id))
            case .askJournal(let id): askingJournal = id
            case .askAuto: showRestoreAuto = true
            case .askSaved: showRestore = true
            case .none: break
            }
            askedRestore = true
        }
        .sheet(isPresented: $showSongPicker) {
            NavigationStack {
                SongPickerView { song in model.song = song }
            }
        }
        .sheet(isPresented: $showInspiredPicker) {
            NavigationStack {
                InspiredPickerView(currentLocation: model.items.first?.location,
                                   selectedId: model.inspired?.id) { pick in model.inspired = pick }
            }
        }
        // 写真の編集（帯のサムネを押す）。**その写真だけ**にレシピを入れる（`applyEdit`）
        .fullScreenCover(item: $editing) { target in
            if let item = model.items.first(where: { $0.id == target.id }) {
                PhotoEditView(recipe: item.recipe, source: item.editSourceReader,
                              // 編集済みなら帯の編集後サムネを仮に出す（無編集なら nil）
                              placeholder: item.recipe.isIdentity ? nil : item.editedPreview,
                              onDone: { recipe in
                                  model.applyEdit(target.id, recipe: recipe)
                                  editing = nil
                              },
                              onCancel: { editing = nil })
            } else {
                // 開いている間に写真が無くなった（ふつうは起きない。送信中は開かせない）
                Color.black.ignoresSafeArea().onAppear { editing = nil }
            }
        }
        .alert(L("この写真は編集できません", "Can't edit this photo"),
               isPresented: Binding(get: { editLockMessage != nil }, set: { if !$0 { editLockMessage = nil } })) {
            Button(L("OK", "OK"), role: .cancel) { editLockMessage = nil }
        } message: {
            Text(editLockMessage ?? "")
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { capture in
                model.accept(capture: capture)
            }
            .ignoresSafeArea()
        }
        // **まとめて選べる**（Web の投稿画面と同じ）。一度に扱う数は
        // `maxSelection` まで——1枚ずつ題と説明を書く画面なので、
        // 多すぎるとどれを書いているか見失う
        // **元の形のまま受け取る（`.current`）**（2026-10-16・ストーリーの埋め込みの写真選びと同じ理由）。
        // 既定（`.automatic`）だと写真を JPEG などに作り直し終えるまで選択が知らされず、大きな写真・
        // iCloud の写真ほど長く待たされる。読み込みは `Data` で受けて `ImagePreparer` が整えるので HEIC のままで困らない
        .photosPicker(isPresented: $showLibrary,
                      selection: $model.pickerItems,
                      maxSelectionCount: UploadViewModel.maxSelection,
                      matching: .images,
                      preferredItemEncoding: .current,
                      // **前の選択に印を付けて開く。** 無いと毎回まっさらで開き、
                      // 「追加」が選び直しになる（前の写真と打った題が消える）
                      photoLibrary: .shared())
    }

    /// 右上の「投稿する」（板: 真鍮・15pt semibold）。送信中は何枚目かを出す
    private var submitButton: some View {
        Button {
            Task { await model.submit() }
        } label: {
            if let export = model.exportProgress {
                // 送り始める前の書き出し（「0/N」のまま止まって見えないように）
                HStack(spacing: 6) {
                    ProgressView().tint(WebTheme.accent)
                    Text(export.label)
                        .font(JPFont.mono(13, relativeTo: .footnote))
                }
            } else if model.isWorking {
                // **何枚目かを出す。** 5枚選んだときに、進んでいるのか
                // 止まっているのかが分からないのがいちばん不安
                HStack(spacing: 6) {
                    ProgressView().tint(WebTheme.accent)
                    if model.items.count > 1 {
                        Text("\(model.uploadingIndex)/\(model.items.count)")
                            .font(JPFont.mono(13, relativeTo: .footnote))
                    }
                }
            } else if model.isLoadingPicked {
                ProgressView().tint(WebTheme.accent)
            } else {
                Text(L("投稿する", "Post"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(model.canSubmit ? WebTheme.accent : WebTheme.text3)
        .disabled(!model.canSubmit)
        .accessibilityLabel(model.exportProgress?.accessibilityLabel ?? (model.isWorking
                            ? L("送信中 \(model.uploadingIndex) / \(model.items.count) 枚目",
                                "Sending \(model.uploadingIndex) of \(model.items.count)")
                            : (model.items.count > 1
                               ? L("\(model.items.count) 枚を投稿する", "Post \(model.items.count) photos")
                               : L("投稿する", "Post"))))
        // UI テストが名指しで押す（`CriticalFlowTests`・2026-10-22）
        .accessibilityIdentifier("upload.submit")
    }

    /// 選んだ写真の帯（v2 の板: 84×104・角丸12、右上に外す丸、左上に番号、最後に「追加」）。
    ///
    /// **サーバーは1行＝1枚**で、選んだ枚数ぶんの投稿になる（題も説明も1枚ずつ）。
    /// 「まとめる」は見せ方だけ（`groupChoice`）
    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UploadStripLayout.spacing) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    thumb(item, index: index)
                }
                addTile
            }
            // 外す丸の当たり（44pt）が上に 14pt はみ出すぶん。6 だと上の 8pt が
            // ScrollView の枠の外に出て押せなかった（縦 約36pt）
            .padding(.top, 14)
            .padding(.trailing, 6)
        }
        // 帯の見た目の位置は前のまま（上の余白を 6 → 14 にした 8pt を詰める）
        .padding(.top, -8)
    }

    /// 写真の編集を開く（帯のサムネ・「写真を編集」）。開けない写真なら理由を出す
    private func openEditor(_ id: UUID) {
        hideEditHint()
        if let reason = model.editLockReason(for: id) {
            editLockMessage = reason
        } else {
            editing = EditTarget(id: id)
        }
    }

    /// 案内を出すか決めて、出すなら出す（出した時点で覚える＝二度と出さない）
    private func offerEditHint() {
        let memory = UploadEditHintMemory()
        let hasEditable = model.items.contains { model.editLockReason(for: $0.id) == nil }
        guard UploadEditEntry.showsHint(alreadyShown: memory.shown, hasEditablePhoto: hasEditable) else { return }
        memory.shown = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { showEditHint = true }
    }

    private func hideEditHint() {
        guard showEditHint else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showEditHint = false }
    }

    /// 写真を選んだ直後に一度だけ出す案内（帯の上）。案内の帯なので accent-soft の地に
    /// 真鍮のアイコン（黒地の上の合図）と白の文字。押すと消える
    private var editHint: some View {
        Button { hideEditHint() } label: {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityHidden(true)
                Text(L("写真を押すと編集できます", "Tap a photo to edit it"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WebTheme.text2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .accessibilityLabel(L("写真を押すと編集できます", "Tap a photo to edit it"))
        .accessibilityHint(L("押すとこの案内を閉じます", "Dismisses this tip"))
        .accessibilityIdentifier("upload.editHint")
    }

    /// 帯の下の「写真を編集」（黒地の上の副ボタン・真鍮の文字）。開ける写真のうち最初の1枚を開く。
    /// 開ける写真が無ければ出さない（`UploadEditEntry.buttonTarget`）
    @ViewBuilder
    private var editButton: some View {
        let editable = model.items.map { model.editLockReason(for: $0.id) == nil }
        if let index = UploadEditEntry.buttonTarget(editable: editable), model.items.indices.contains(index) {
            let id = model.items[index].id
            Button { openEditor(id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(L("写真を編集", "Edit photo"))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(WebTheme.accent)
                .padding(.horizontal, 16)
                .frame(minHeight: WebTheme.minTapTarget)
                .background(WebTheme.raised, in: Capsule())
                .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("写真を編集", "Edit photo"))
            .accessibilityHint(model.items.count > 1
                               ? L("\(index + 1)枚目の色や明るさを編集します", "Adjusts the color and light of photo \(index + 1)")
                               : L("色や明るさを編集します", "Adjusts the color and light"))
            .accessibilityIdentifier("upload.editButton")
        }
    }

    /// 帯の1枚。**押すと編集画面**（写真ごと）。左下に一本の札（未編集は「編集」・編集済みは今の札）
    private func thumb(_ item: PendingPhoto, index: Int) -> some View {
        let canEdit = model.editLockReason(for: item.id) == nil
        let tag = UploadEditEntry.thumbTag(badge: item.editBadge, canEdit: canEdit)
        return Button {
            openEditor(item.id)
        } label: {
            Group {
                if let preview = item.stripPreview {
                    preview.resizable().aspectRatio(contentMode: .fill)
                } else {
                    WebTheme.surface
                }
            }
            .frame(width: UploadStripLayout.thumbWidth, height: UploadStripLayout.thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // 送っている間は開かせない（送信は1枚ごとにその時点の写真を読む）
        .disabled(model.isWorking)
        .accessibilityLabel(item.editBadge.map { L("\(index + 1)枚目・\($0)で編集済み", "Photo \(index + 1), edited: \($0)") }
                            ?? L("\(index + 1)枚目・未編集", "Photo \(index + 1), not edited"))
        .accessibilityHint(canEdit
                           ? L("押すと色や明るさを編集できます", "Opens the editor to adjust color and light")
                           : L("押すと、いま編集できない理由を表示します", "Shows why this photo can't be edited now"))
        .accessibilityIdentifier("upload.thumb.\(index)")
        .overlay(alignment: .topLeading) {
            // 送る順の番号。2026-10-02 判断: 左下は編集済みの札（見本 3 の位置）に譲り、左上に移した
            // （右上の外す丸とは 96pt の幅の両端で離れている）
            Text("\(index + 1)")
                .font(JPFont.number(JPTypeScale.caption, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 4)
                .frame(minWidth: UploadStripLayout.numberSize, minHeight: UploadStripLayout.numberSize)
                .background(Color.black.opacity(0.6), in: Capsule())
                .padding(6)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomLeading) {
            // 札（見本 3: 左下・黒 66% の地に白 12pt）。写真の上なので白。
            // 2026-10-03: **一本の札**——未編集なら「編集」、編集済みならプリセット名か「調整」
            // （`UploadEditEntry.thumbTag`）。押せる合図を常に見せる（owner「どこから入るのか」）。
            // 名前が読める幅に: サムネの幅いっぱい（左右 6pt を残す）まで・1行・入らなければ 0.8 まで縮める
            // （文字を詰めて「旅の葉…」にしない）
            if let badge = tag.text {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .bold))
                    Text(badge)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.66), in: Capsule())
                .frame(maxWidth: UploadStripLayout.thumbWidth - 12, alignment: .leading)
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                model.remove(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: UploadStripLayout.removeDot, height: UploadStripLayout.removeDot)
                    .background(WebTheme.surface7, in: Circle())
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                    // 丸は板の位置のまま、押せる範囲だけ左へずらす（`UploadStripLayout` の注記）
                    .offset(x: UploadStripLayout.removeDotNudge)
                    // 押せる範囲は 44pt（見た目は 28pt）
                    .frame(width: UploadStripLayout.removeHit, height: UploadStripLayout.removeHit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 送っている間は並びを変えさせない（送る順の番号がずれる）
            .disabled(model.isWorking)
            .offset(x: UploadStripLayout.removeHitOffsetX, y: -UploadStripLayout.removeOffset)
            .accessibilityLabel(L("\(index + 1)枚目を外す", "Remove photo \(index + 1)"))
        }
    }

    /// 写真を選ぶ画面を開く（「ライブラリから選ぶ」）。
    ///
    /// 🔴 **立ったままの印を立て直す。** 自動で開いた回に選ぶ画面が出なかった（シートの出る途中に
    /// 重なった）と、`showLibrary` が true のまま残り、もう一度 true を入れても変わらないので
    /// 二度と開かない。立っていたら一度下ろしてから立てる（`UploadDetails.libraryOpenSteps`）
    private func openLibrary() {
        let steps = UploadDetails.libraryOpenSteps(isPresented: showLibrary)
        guard steps.count > 1 else {
            showLibrary = true
            return
        }
        showLibrary = false
        Task {
            // 下ろしたのが反映されてから立てる（同じ描画の中で false → true にすると変化にならない）
            try? await Task.sleep(nanoseconds: 150_000_000)
            showLibrary = true
        }
    }

    /// 「追加」の点線の枠。**カメラを先に置く**（このアプリがネイティブである
    /// 理由＝4.2 で、旅先でいちばん使う入口でもある）
    private var addTile: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button { showCamera = true } label: {
                    Label(L("写真を撮る", "Take a photo"), systemImage: "camera")
                }
            }
            Button { openLibrary() } label: {
                Label(L("ライブラリから選ぶ", "Choose from library"), systemImage: "photo.on.rectangle")
            }
        } label: {
            // v2 Upload:「写真を追加で選ぶ」は**真鍮の点線と真鍮の字**（黒地の上・owner の好み
            // 「旅の写真からの『写真を追加で選ぶ』は真鍮」と同じ扱い）
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 22, weight: .light))
                Text(L("追加", "Add")).font(JPFont.caption)
            }
            .foregroundStyle(WebTheme.accent)
            .frame(width: UploadStripLayout.thumbWidth, height: UploadStripLayout.thumbHeight)
            .overlay(RoundedRectangle(cornerRadius: JPRadius.field)
                .strokeBorder(WebTheme.accent.opacity(UploadStripLayout.addBorderOpacity),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(L("写真を追加", "Add photos"))
        // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
        .accessibilityIdentifier("upload.add")
        // 🔴 **送っている間・下書きを戻している間は足させない。** 送信中に足すと
        // `reset()` で黙って消え、復元中に足すと `restoreDraft` が失敗して下書きごと消えていた
        .disabled(model.isWorking || model.isRestoringDraft)
    }

    /// 「1つの投稿にまとめる／それぞれ別の投稿」（板: 2択・選んでいる側は白）。
    ///
    /// **行は1枚ずつのまま。** まとめても個別ページとサイトマップは変わらない
    /// ——写真1枚＝1ページがこのサイトの検索での面積なので、1行にまとめると
    /// 出せるページが減る。束ねるのは見せ方だけ。
    private var groupChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                segment(L("1つの投稿にまとめる", "Post as one"), selected: model.groupsAsOnePost) {
                    model.groupsAsOnePost = true
                }
                segment(L("それぞれ別の投稿", "Separate posts"), selected: !model.groupsAsOnePost) {
                    model.groupsAsOnePost = false
                }
            }
            .padding(3)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            Text(model.groupsAsOnePost
                 ? L("一覧では1枚のカードにまとまり、左右に送れます（題と説明は1枚ずつ書きます）",
                     "Shown as one card you can swipe (each photo keeps its own title)")
                 : L("それぞれ別の投稿として並びます", "Shown as separate posts"))
                .font(.caption)
                .foregroundStyle(WebTheme.text3)
                .padding(.horizontal, 4)
        }
    }

    /// つながったセグメントの1つ（v2 Upload・Components 02「表示の切り替え」）。
    /// **選んだ側は一段明るい面（#2C2C2E）に白の太字**、選んでいない側は text-2。
    /// v1 は白の塗りに墨だったが、白の塗りは1画面に1つ（主ボタン）の決まりに合わせた
    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(JPFont.footnote.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? WebTheme.text : WebTheme.text2)
                // 押せるものは 44pt
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .background(selected ? Self.segmentSelectedFill : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9))
                .shadow(color: Color.black.opacity(selected ? 0.4 : 0), radius: 1.5, x: 0, y: 1)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 選んだセグメントの面（v2 の `#2C2C2E`）。土台の面の段 `surface8`
    private static let segmentSelectedFill = WebTheme.surface8

    /// 選んだ写真ごとの欄。**題・説明・撮影地は1枚ずつ**（Web と同じ）。
    private var detailSection: some View {
        ForEach($model.items) { $item in
            VStack(alignment: .leading, spacing: 14) {
                if model.items.count > 1 {
                    JPSectionTitle(L("\(indexOf(item)) 枚目", "Photo \(indexOf(item))"))
                }
                // 2026-10-03 判断: **撮影地を題・説明より先に**（いちばん多い道は 写真 → 撮影地 → 投稿。
                // 題と説明は任意）。撮影地は写真の位置から自動で入る（`fillPlaceName`）
                VStack(alignment: .leading, spacing: 6) {
                    // 見出しと枠はタイトル・説明と同じ形（`JPFieldTitle`・`jpFieldBox`・2026-10-21）
                    JPFieldTitle(L("撮影地", "Place"))
                    PlaceSearchField(location: $item.location, coords: $item.pickedCoords,
                                     near: item.prepared.coords, offersSpots: true,
                                     pickedSpot: $item.pickedSpot, boxed: true)
                    // 投稿が撮影地の作例になることを一言（実際に並ぶときだけ・`UploadDetails.showsSampleNote`）
                    if UploadDetails.showsSampleNote(location: item.location, published: model.published,
                                                     audience: model.audience) {
                        Label {
                            Text(UploadDetails.sampleNote)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            // 黒地の上の手がかりなので真鍮（板: 真鍮＝合図と手がかり）
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(WebTheme.accent)
                                .accessibilityHidden(true)
                        }
                        .font(.caption)
                        .foregroundStyle(WebTheme.text2)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("upload.sampleNote")
                    }
                }
                JPField(L("タイトル", "Title")) {
                    TextField(L("例: 高屋神社の雲海", "e.g. Sea of clouds at Takaya"),
                              text: $item.title)
                        // UI テストが名指しで打つ（`CriticalFlowTests`・2026-10-22）
                        .accessibilityIdentifier("upload.title")
                        .onChange(of: item.title) { old, value in
                            let kept = PostLimits.limited(old: old, new: value, limit: PostLimits.title)
                            if kept != value { item.title = kept }
                        }
                }
                count(item.title, limit: PostLimits.title)
                JPField(L("説明文", "Description"), multiline: true) {
                    TextField(L("どんな写真ですか", "What is this photo about?"),
                              text: $item.caption, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: item.caption) { old, value in
                            let kept = PostLimits.limited(old: old, new: value, limit: PostLimits.description)
                            if kept != value { item.caption = kept }
                        }
                }
                count(item.caption, limit: PostLimits.description)
            }
        }
    }

    /// 上限が近いときだけ文字数を出す。
    ///
    /// **数はいつも出さない。** 書いている最中に数字が目に入ると、
    /// 書ける文章を短く削ってしまう。2割を切ってから出す（`PostLimits`）
    @ViewBuilder
    private func count(_ text: String, limit: Int) -> some View {
        if PostLimits.shouldShowCount(text, limit: limit) {
            // 数え方はサーバーと同じ（`PostLimits.length`）——字で数えると、止まったのに
            // 「150/200」のように余っている数が出る
            Text("\(PostLimits.length(text))/\(limit)")
                .font(JPFont.mono(12))
                .foregroundStyle(PostLimits.length(text) >= limit ? WebTheme.danger : WebTheme.text3)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, -8)
        }
    }

    /// 見出しに出す番号（1始まり）。並びが変わっても id で引き直す。
    private func indexOf(_ item: PendingPhoto) -> Int {
        (model.items.firstIndex(where: { $0.id == item.id }) ?? 0) + 1
    }

    /// 「詳しい設定」の行の右に出す、いまの値（`UploadDetails.summary`）
    private var detailsSummary: String {
        UploadDetails.summary(
            published: model.published, audience: model.audience,
            songTitle: model.song?.title,
            albumTitle: model.albums.first { $0.id == model.selectedAlbumId }.map(albumTitle),
            sharesToSocial: model.shareToThreads, category: model.category)
    }

    /// 「詳しい設定」の開け閉めの行。**畳んでいても今の値を出す**（公開範囲はいつも先頭）
    private var detailsToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsDetails.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17))
                    .foregroundStyle(WebTheme.text2)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("詳しい設定", "More settings"))
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.text)
                    Text(detailsSummary)
                        .font(.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WebTheme.text3)
                    .rotationEffect(.degrees(showsDetails ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("詳しい設定", "More settings"))
        .accessibilityValue(detailsSummary)
        .accessibilityHint(showsDetails
                           ? L("押すと畳みます", "Collapses the settings")
                           : L("押すと公開範囲・曲・アルバムなどを変えられます",
                               "Shows visibility, song, album and more"))
        .accessibilityIdentifier("upload.details")
    }

    /// まとめて付く行（板: 札に 曲・入れるアルバム・公開範囲。カテゴリも同じ形で）。
    ///
    /// 2026-10-03 判断: **「詳しい設定」に畳む**（計画9・`UploadDetails`）。機能は消さない。
    /// 既定値（全体に公開・曲なし・アルバムなし）のまま投稿できるので、いちばん多い道では開かない
    private var rowsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            JPCard {
                detailsToggle
                if showsDetails {
                    JPCardDivider()
                    detailRows
                }
            }
            // 付けた曲は試し聴きできる形で出す（アートワーク・アーティスト・再生）
            if showsDetails, let song = model.song {
                SongRow(song: song)
            }
            // 公開範囲を変えられない理由（送りかけの写真がある間だけ）。**畳んでいても出す**
            if let reason = model.visibilityLockReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.horizontal, 4)
            }
            // 公開範囲の説明（何が起きるかを先に言う）。**畳んでいても出す**（レビュー 2026-10-03）
            // ——「ウェブサイトにも載り、検索から…」が見えないまま、意図せず公開させない
            Text(model.published
                 ? model.audience.photoNote
                 : L("非公開の写真は、あなた以外には見えません。あとから公開できます。",
                     "Private photos stay yours. You can publish them later."))
                .font(.caption)
                .foregroundStyle(WebTheme.text3)
                .padding(.horizontal, 4)
                .accessibilityIdentifier("upload.audienceNote")
        }
    }

    /// 「詳しい設定」の中身（前の札の行そのまま）
    @ViewBuilder
    private var detailRows: some View {
        // **送っている間は変えさせない**（公開範囲・カテゴリ・タグも同じ）。
        // 送信は1枚ごとにその時点の値を読むので、同じ束で割れる
        // （Web の AudiencePicker disabled={uploading} と同じ）。
        // アルバムは送信中に選び直せる作り（`onAlbumGone`）なので止めない
        songRow
            .disabled(model.isWorking)
        if !model.albums.isEmpty {
            JPCardDivider()
            albumRow
        }
        JPCardDivider()
        // 鍵を控えている写真がある間も変えさせない（`visibilityLocked` の注記）
        audienceRow
            .disabled(model.isWorking || model.visibilityLocked)
        // 公開・全体に公開のときだけ（外の SNS に絞った写真を流さない・`ThreadsShare`）
        if ThreadsShare.isEligible(published: model.published, audience: model.audience) {
            JPCardDivider()
            threadsRow
                .disabled(model.isWorking)
        }
        // **選ぶ先が空なら誰にも見えない。** 選びに行く口をここに置く
        if model.published && model.audience == .closeFriends {
            JPCardDivider()
            NavigationLink { CloseFriendsView() } label: {
                JPRowLabel(title: L("親しい友達を選ぶ", "Pick close friends"), systemImage: "star")
            }
            .buttonStyle(JPRowButtonStyle())
            // **送っている間は積ませない。** 積んだ画面は変更が無いとき「払って閉じてよい」
            // （`unsavedLeaveGuard`）を出すので、このシートの「送信中は払って閉じない」を
            // 打ち消すおそれがある（どちらが勝つかは SwiftUI 任せ）
            .disabled(model.isWorking)
        }
        JPCardDivider()
        NavigationLink {
            ScrollView {
                CategoryField(category: $model.category).padding(16)
            }
            .webScreen()
            .navigationTitle(L("カテゴリ", "Category"))
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            JPRowLabel(title: L("カテゴリ", "Category"), systemImage: "square.grid.2x2",
                       value: model.category.isEmpty ? L("選ぶ", "Choose") : model.category)
        }
        .buttonStyle(JPRowButtonStyle())
        .disabled(model.isWorking)
    }

    /// 「この写真を見て撮影」（2026-10-14・`InspiredBy`）。**詳しい設定に畳まない**——「写真から、次の旅が
    /// 始まる」の入口なので、いつも見える所に1行。任意（付けずに投稿できる）。
    /// 行の形は曲の行と同じ（板 Upload の札の行）。選んだら小さな写真と題・作者を出す
    private var inspiredCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            JPCard {
                inspiredRow
                    // 送っている間は変えない（1枚目に付けるかを送りながら決めている）
                    .disabled(model.isWorking)
            }
            if model.inspired != nil {
                Text(L("投稿のうち1枚に付きます。元の写真が非公開になっていたら付きません。",
                       "Attached to one photo of the post. It won't attach if the original is no longer public."))
                    .font(.caption)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var inspiredRow: some View {
        if let pick = model.inspired {
            Menu {
                Button { showInspiredPicker = true } label: {
                    Label(L("選び直す", "Choose another"), systemImage: "photo.on.rectangle")
                }
                Button(role: .destructive) { model.inspired = nil } label: {
                    Label(L("外す", "Remove"), systemImage: "xmark")
                }
            } label: {
                JPRowLabel(title: L("この写真を見て撮影", "Inspired by"),
                           detail: [pick.label, pick.authorName ?? ""].filter { !$0.isEmpty }
                               .joined(separator: PhotoMetaLine.separator),
                           icon: AnyView(inspiredThumb(pick)))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityLabel(L("この写真を見て撮影: \(pick.label)", "Inspired by: \(pick.label)"))
            .accessibilityHint(L("選び直す・外す", "Choose another or remove"))
            .accessibilityIdentifier("upload.inspired")
        } else {
            Button { showInspiredPicker = true } label: {
                JPRowLabel(title: L("この写真を見て撮影（任意）", "Inspired by (optional)"),
                           systemImage: "camera.viewfinder",
                           value: L("元の写真を付ける", "Add"))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("upload.inspired")
        }
    }

    /// 選んだ元の写真の小さな画像（行のアイコンの場所・24pt の枠に収める）
    private func inspiredThumb(_ pick: InspiredBy.Pick) -> some View {
        RemoteImage(url: pick.thumbURL.flatMap(URL.init(string:)))
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
    }

    @ViewBuilder
    private var songRow: some View {
        if let song = model.song {
            Menu {
                Button { showSongPicker = true } label: { Label(L("曲を変える", "Change song"), systemImage: "music.note") }
                Button(role: .destructive) { model.song = nil } label: { Label(L("曲を外す", "Remove song"), systemImage: "xmark") }
            } label: {
                JPRowLabel(title: L("曲（任意）", "Song (optional)"), systemImage: "music.note", value: song.title)
            }
            .buttonStyle(JPRowButtonStyle())
        } else {
            Button { showSongPicker = true } label: {
                JPRowLabel(title: L("曲（任意）", "Song (optional)"), systemImage: "music.note",
                           value: L("曲を付ける", "Add a song"))
            }
            .buttonStyle(JPRowButtonStyle())
        }
    }

    private var albumRow: some View {
        Menu {
            Button { model.selectedAlbumId = nil } label: {
                choiceLabel(L("入れない", "None"), selected: model.selectedAlbumId == nil)
            }
            ForEach(model.albums) { album in
                Button { model.selectedAlbumId = album.id } label: {
                    choiceLabel(albumTitle(album), selected: model.selectedAlbumId == album.id)
                }
            }
        } label: {
            JPRowLabel(title: L("入れるアルバム", "Add to album"), systemImage: "rectangle.stack",
                       value: model.albums.first { $0.id == model.selectedAlbumId }.map(albumTitle) ?? L("入れない", "None"))
        }
        .buttonStyle(JPRowButtonStyle())
    }

    private func albumTitle(_ album: Album) -> String {
        album.title.isEmpty ? L("無題のアルバム", "Untitled album") : album.title
    }

    /// 「撮影地の位置を付ける」（2026-10-18 判断・`UploadViewModel.attachesLocation`）。投稿の全部の写真に効く。
    /// 人ごとに端末に覚える（`UploadLocationPreference`）。軌道は「SNS にも載せる」と同じ暗い真鍮
    /// （板: Toggle のオン＝accent-deep。黒地の上）
    private var locationToggle: some View {
        JPCard {
            Toggle(isOn: Binding(get: { model.attachesLocation },
                                 set: { model.setAttachesLocation($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(UploadDetails.locationToggleTitle)
                        .font(.callout)
                        .foregroundStyle(WebTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(UploadDetails.locationToggleNote(attaches: model.attachesLocation))
                        .font(.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(WebTheme.accentDeep)
            // 送っている間は変えさせない（送る中身は1枚ずつ作り直すので、途中で変わると写真ごとに割れる）
            .disabled(model.isWorking)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: WebTheme.minTapTarget)
            .accessibilityIdentifier("upload.attachLocation")
        }
    }

    /// 投稿したら SNS にも載せる（共有の画面が開き、写真と文が入る）。入切は端末に覚える
    private var threadsRow: some View {
        Toggle(isOn: $model.shareToThreads) {
            VStack(alignment: .leading, spacing: 2) {
                // owner 2026-10-02「Threads だけでなく他の SNS でも同じようにできるようにしたい」。
                // 共有の画面なので、もとから X・Instagram・LINE なども選べる。名前と説明だけを広げた
                Text(L("SNS にも載せる", "Also share to social apps"))
                    .font(.callout)
                    .foregroundStyle(.white)
                Text(L("投稿のあと共有の画面が開きます。Threads・X・Instagram など載せたいアプリを選んでください。文はコピーされるので、入らないアプリでは貼り付けてください",
                       "After posting, the share sheet opens. Pick Threads, X, Instagram or any app. The caption is copied, so paste it if the app leaves it out."))
                    .font(.caption)
                    .foregroundStyle(WebTheme.text3)
            }
        }
        // **軌道は暗い真鍮**（ストーリーの入切と同じ。既定の白だと白い軌道に白いつまみが乗る）
        .tint(WebTheme.accentDeep)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// 公開範囲（板: 1行。全体・フォロワー・親しい友達・非公開の4択）
    private var audienceRow: some View {
        Menu {
            ForEach(Audience.allCases) { choice in
                Button {
                    model.chooseVisibility(published: true, audience: choice)
                } label: {
                    choiceLabel(choice.label, selected: model.published && model.audience == choice)
                }
            }
            Button { model.chooseVisibility(published: false, audience: nil) } label: {
                choiceLabel(L("非公開", "Private"), selected: !model.published)
            }
        } label: {
            JPRowLabel(title: L("公開範囲", "Visibility"),
                       systemImage: model.published ? model.audience.systemImage : "lock",
                       value: model.published ? model.audience.label : L("非公開", "Private"))
        }
        .buttonStyle(JPRowButtonStyle())
    }

    /// メニューの1項目（選んでいるものに印）
    @ViewBuilder
    private func choiceLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    /// タグ（まとめて同じものが付く）
    private var tagsAndCategory: some View {
        TagField(tagsText: $model.tagsText)
            .disabled(model.isWorking)
    }

    /// 送信の途中・失敗の知らせと、残りをやめる口
    @ViewBuilder
    private var progressAndErrors: some View {
        if let error = model.errorMessage {
            Text(error).foregroundStyle(WebTheme.danger).font(.callout)
        }
        if model.canRetryUnreadable {
            // 読めなかった写真（時間切れ・iCloud から落とせなかった）を読み直す口（2026-10-03）。
            // 隣の「残りをやめる」と同じ縁取りの丸ボタン（線のボタン・高さ 44pt）。文言は今日の一問の再試行と同じ
            Button { model.retryUnreadable() } label: {
                Text(L("もう一度読み込む", "Try again")).jpPillButton(.outline)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("upload.retryUnreadable")
        }
        if model.isWorking && model.items.count > 1 {
            // **やめられるようにする。** いま上げている1枚は最後まで通す
            // （途中で切ると S3 に迷子が残る）。残りは始めない
            Button(role: .destructive) { model.cancel() } label: {
                Text(L("残りをやめる", "Stop the rest")).jpPillButton(.outline)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 選んだ写真の帯の寸法（板 `project/Upload.dc.html`: v2 で 84×104・間 8（v1 は 96×120・間 10）、
/// 右上の外す丸は見た目 28・押せる所 44 で、写真の右上の角から右へ・上へ 14 はみ出す）。
///
/// 2026-10-14 判断: v2 の板は外す印を写真の角の内側（30 の枠に 18 の丸）に入れたが、**外す丸は v1 の形のまま**
/// にした——小さな丸は押し間違えやすく、下の押せる範囲の調整（2026-10-07）を保つため。帯の間が 8 になったので、
/// 押せる範囲を寄せる量は 6 になる（見た目の位置は同じ・下の式で決まる）
///
/// 🔴 **2026-10-07 判断: 丸は板の位置のまま、押せる範囲だけ左へずらす（間 10 のとき 4）。** 板どおりに
/// 押せる範囲を 14 はみ出させると、帯の間（10）を越えて隣の写真に 4 重なり、隣の写真の左上を
/// 押したつもりで1つ前の写真が外れた（2026-10-01 の既知の残り）。見た目（丸の位置と大きさ）は
/// 変えない——押せる範囲（見えない）を、丸が収まる範囲で寄せるだけ。44 も保つ
enum UploadStripLayout {
    /// 写真と写真の間（v2 の板 gap 8。v1 は 10）
    static let spacing: CGFloat = 8
    /// 1枚の大きさ（v2 の板 84×104。v1 は 96×120）。「追加」の枠も同じ
    static let thumbWidth: CGFloat = 84
    static let thumbHeight: CGFloat = 104
    /// 左上の順番の丸（v2: 最小 22・12pt の太字・黒 60%）
    static let numberSize: CGFloat = 22
    /// 「追加」の真鍮の点線の濃さ（v2 の板 `rgba(201,166,107,.6)`）
    static let addBorderOpacity = 0.6
    /// 外す丸の見た目の大きさ（板 28）
    static let removeDot: CGFloat = 28
    /// 外す丸が押せる範囲（CLAUDE.md の最小 44）
    static let removeHit: CGFloat = 44
    /// 丸（44 の枠の真ん中に置いたとき）を写真の右上の角から右へ・上へずらす量（板 right/top -14）
    static let removeOffset: CGFloat = 14
    /// 押せる範囲を右へずらす量。**帯の間を越えない**
    static let removeHitOffsetX: CGFloat = min(removeOffset, spacing)
    /// 押せる範囲を左へ寄せたぶん、丸を戻す（見た目の位置は `removeOffset` のまま）
    static let removeDotNudge: CGFloat = removeOffset - removeHitOffsetX

    /// 押せる範囲が写真の右の端から右へはみ出す量（隣の写真に重なってはいけない）
    static var hitOverhangRight: CGFloat { removeHitOffsetX }
    /// 丸の見た目の右の端が、写真の右の端から右へはみ出す量（板どおり 6）
    static var dotOverhangRight: CGFloat {
        removeHitOffsetX + removeDotNudge - (removeHit - removeDot) / 2
    }
    /// 丸が押せる範囲に収まっているか（ずらした丸の右の端が枠の中）
    static var dotInsideHit: Bool {
        (removeHit + removeDot) / 2 + removeDotNudge <= removeHit
    }
}
