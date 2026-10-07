import SwiftUI
import PhotosUI
// UIImage を使う（SwiftUI / PhotosUI から見えることに頼らない）
import UIKit

/// ストーリーを投稿する。24時間で消える。
///
/// **かんたん版**（owner・2026-10-02 に候補を見て「めっちゃいい」）。3つの段:
///  1. 写真を選ぶ — 写真が0枚なら、開いてすぐ最近の写真の格子（埋め込みの写真選び）。下の白い「次へ（N枚）」
///  2. 仕上げる — 写真を大きく、その下に名前つきの道具4つ（文字・スタンプ・曲・場所・`StoryTool`）。
///     表示秒数・写真の合わせ方を戻す・下書き保存は右上の「…」
///  3. 誰に見せる — 下の「フォロワー ▾」でシート（`StoryAudienceSheet`）、右の白い「シェアする」で投稿
///
/// 段は**写真の有無で決める**（`shots.isEmpty` なら1）。段の状態は新しく持たない——
/// 下書き・送信・文字のデータ・写真の合わせ方の中身は前のまま、置き場所だけを変えた。
struct StoryComposerView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var drafts: StoryDraftStore
    /// 送るのは裏の係（画面を閉じても続く・板 27）
    @ObservedObject private var uploads = StoryUploadCenter.shared
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    /// ライブラリから選んだもの。**まとめて選べる**（モック4-5）
    /// ——1枚ずつしか選べないと、10枚出すのに10回開くことになる
    @State private var pickerItems: [PhotosPickerItem] = []
    /// 読み込んでいる最中の回数（`load` の始めで足し、終わりで引く）。
    /// **0 より大きい間は投稿・下書き保存を止める**——届いていない写真が黙って落ちる
    @State private var loadingPicks = 0
    /// 選んだ写真の並び（モック4-5 のメディアストリップ）。
    ///
    /// **1枚＝1本のストーリー。** サーバーは `POST /stories` に1枚ずつ渡す形で、
    /// 複数枚を1本に入れる口は無い。閲覧側は同じ人のストーリーを順に流すので、
    /// **並びの順に出せば、モックの「スライドショー」になる**。
    /// 文字は**写真ごと**に持つ（焼き込みは写真ごとに起きるため）。
    @State private var shots: [StoryShot] = []
    /// いま編集している写真の位置
    @State private var current = 0
    @State private var caption = ""
    /// 撮影地と、その候補（`StorySpotSuggestion.Place`）。撮影地が変わるのは本人が決めたときだけ
    @State private var place = StorySpotSuggestion.Place()
    /// 24時間のあとも残すか（ハイライトの材料になる）
    @State private var keepInArchive = false
    /// 返信を受けるか（Web の「返信を許可」。既定は入）
    @State private var allowReplies = true
    @State private var showCamera = false
    /// 開いたときの「書きかけの下書き」で「キャンセル（残す）」を選んだか
    /// 「続きから」で**残すと決めた下書きの印**（`savedAt`）。真偽では持たない——
    /// 裏の送信や人の替わりでその下書きが消えた後まで「守る下書きがある」ことにしていた
    @State private var keptDraftStamp: String?
    /// 開いたときに在った下書きで、**まだ問いに答えていない**ものの印。
    /// 「送れなかったストーリー」の問いが先に出ると下書きの問いは出ないので、
    /// 答えていない下書きをこの回の投稿のついでに消さない
    @State private var unansweredDraftStamp: String?
    /// 前に送れなかったストーリーが残っているときの問い（開いた直後に1回）
    @State private var showPendingFailure = false
    /// ストーリーのBGM（30秒の試聴だけ）と、表示秒数
    @State private var song: Photo.Song?
    @State private var durationSec = StoryService.defaultDurationSec
    @State private var showSongPicker = false
    /// 曲の流し始めを選ぶ（30秒の試聴のどこから鳴らすか）
    @State private var showSongStart = false
    @State private var message: String?
    /// 前に書きかけて閉じたもの。**開いた直後に一度だけ尋ねる**
    @State private var showRestore = false
    /// 開いたときの問いを済ませた（`onAppear` はカメラを閉じたときにも走る）
    @State private var askedOnOpen = false

    // 写真の上の文字と札（owner・2026-09-30「使いづらい」で「文字と札」の編集モードを外した。
    // 文字は写真の上で直接打ち、札はトレイから選び、置いたものは指で直接動かす）
    /// **写真の上で直接打っている札**（`StoryTextTypingView`）。nil なら打っていない
    @State private var typingId: UUID?
    /// 打っている札が載っている写真。**写真の読み込みで表示中の写真が移っても、打つ先を取り違えない**
    /// （移った先には札が無く、打った字が消え、元の写真に見えない空の札が残った・4ffb74f のレビュー）
    @State private var typingShotId: UUID?
    /// 写真の枠の大きさ（**キーボードで縮む前**）。打つ画面の文字を焼き込みと同じ大きさで見せる
    @State private var canvasSize: CGSize = .zero
    /// 打ち始めた瞬間の `canvasSize`（打っている間はキーボードで枠が縮むので、こちらで測る）
    @State private var typingCanvas: CGSize = .zero
    /// 写真の枠を**キーボードで縮めない**か。打ち始めで立て、ひとことの欄・投票の欄（どちらも
    /// キーボードを避けたい欄）にピントが入るまで下ろさない。`typingId` だけで切り替えると、
    /// 「完了」の瞬間はキーボードがまだ出ているので、枠が一度縮んで写真が切り直された（b40f96dd のレビュー）
    @State private var photoIgnoresKeyboard = false
    /// 打っている札が**付けた曲の札**だったか（打ち始めの時点）。空にして閉じたら曲も外す
    @State private var typingSongSticker = false
    /// 札を指で動かしている最中（周りの道具を隠し、下のゴミ箱を見せる）
    @State private var draggingOverlay = false
    /// 投票の札を選んでいる（下に投票の欄を出す）
    @State private var voteSelected = false
    /// 札とスタンプのトレイ（`StickerTray`）
    @State private var showStickerTray = false
    /// トレイで選んだもの。**トレイが閉じ切ってから置く**（閉じる動きの最中に打つ画面を開くと、
    /// キーボードが出ないことがある・bf7bb00 のレビュー）
    @State private var pendingPick: StickerTray.Pick?

    /// 投票の欄を開いている（足元と右の列を隠す——残すとキーボードで写真の枠が縮み、小さい画面で
    /// 欄が上のバーに潜った・bf7bb00 のレビュー）
    private var votePanelOpen: Bool { voteSelected && typingId == nil && vote.wrappedValue != nil }
    /// ひとことを打っている（上に「完了」を出す。複数行なので Return では閉じない）
    @FocusState private var captionFocused: Bool
    /// 撮影地を打つ（写真の下の道具の「場所」）
    @State private var showPlaceEditor = false
    /// 写真を選ぶ画面（並びの帯の「＋」から開く・足すとき）
    @State private var showLibrary = false
    /// 埋め込みの写真選び（写真が0枚のとき）で選んでいるもの。**「次へ」まで読み込まない**
    /// （`pickerItems` は変わった瞬間に読み込むので別に持つ）
    @State private var librarySelection: [PhotosPickerItem] = []
    /// 「誰に見せる？」のシート
    @State private var showAudience = false
    @State private var placeDraft = ""
    /// 撮影スポットの索引（静的な JSON・一度だけ読む）。**取れなかった回は空**＝候補を出さないだけ
    @State private var spotIndex: [OfficialSpot] = []
    /// ✕ で閉じる前の「下書きに保存／捨てる／キャンセル」
    @State private var showLeaveConfirm = false
    /// 「続きから」で戻した直後の中身。**ここから何も変えていなければ**、
    /// 閉じても失うものは無い（同じものが下書きに残っている）
    @State private var restoredContent: StoryComposerContent?

    /// いま編集している写真。**無ければ nil**（まだ1枚も選んでいない）
    private var prepared: ImagePreparer.Prepared? {
        shots.indices.contains(current) ? shots[current].prepared : nil
    }

    private var preview: Image? {
        shots.indices.contains(current) ? shots[current].preview : nil
    }

    /// いま編集している写真の大きさ（文字を焼き込みと同じ基準で置くため）
    private var previewSize: CGSize? {
        shots.indices.contains(current) ? shots[current].imageSize : nil
    }

    /// いま編集している写真の文字。**`shots` の中を直に書き換える**
    /// ——別に持つと、写真を切り替えた瞬間にどちらが本物か分からなくなる
    private var overlays: Binding<[TextOverlay]> {
        Binding(
            get: { shots.indices.contains(current) ? shots[current].overlays : [] },
            set: { if shots.indices.contains(current) { shots[current].overlays = $0 } }
        )
    }

    /// いま編集している写真の投票。文字と同じく `shots` の中を直に書き換える
    private var vote: Binding<StoryVoteDraft?> {
        Binding(
            get: { shots.indices.contains(current) ? shots[current].vote : nil },
            set: { if shots.indices.contains(current) { shots[current].vote = $0 } }
        )
    }

    /// いま編集している写真の合わせ方（拡大・位置・回し）。文字と同じく `shots` の中を直に書き換える
    private var framing: Binding<PhotoFraming> {
        Binding(
            get: { shots.indices.contains(current) ? shots[current].framing : .identity },
            set: { if shots.indices.contains(current) { shots[current].framing = $0 } }
        )
    }

    /// 下書きに残る中身（写真の並び・写真ごとの文字と合わせ方・ひとこと・撮影地・曲・秒数・残すか）
    private var content: StoryComposerContent {
        StoryComposerContent(shotIds: shots.map(\.id), overlays: shots.map(\.overlays),
                        framings: shots.map(\.framing), votes: shots.map(\.vote),
                        caption: caption, location: place.location, song: song,
                        durationSec: durationSec, archive: keepInArchive,
                        allowReplies: allowReplies)
    }

    /// ✕ と下へ払うのを通すか（`UnsavedLeave`）
    private var leave: UnsavedLeave {
        Self.leave(content, restored: restoredContent)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            // 写真が0枚なら写真を選ぶ段。全部外したときもここへ戻る
            // 写真の上・黒い面の上の飾りは文字の大きさに付いてくるが、xxLarge で止める
            // （`StoryViewerView.chromeTypeLimit`。広さが決まっている）。シートは止めない
            if shots.isEmpty {
                pickStage
                    .dynamicTypeSize(...StoryViewerView.chromeTypeLimit)
            } else {
                VStack(spacing: 0) {
                    photoArea
                        .dynamicTypeSize(...StoryViewerView.chromeTypeLimit)
                        .ignoresSafeArea(edges: .top)
                    if !votePanelOpen {
                        footer
                            .dynamicTypeSize(...StoryViewerView.chromeTypeLimit)
                            // 打っている間は**隠すだけ**（枠の大きさは変えない——変えると写真の枠が伸びて、
                            // 打ち始めに測った枠とずれる）。暗幕越しに「ストーリーに投稿」が
                            // 書体の列の下に透けて重なっていた（2026-09-30 の owner の画面）
                            .opacity(typingId == nil ? 1 : 0)
                            .allowsHitTesting(typingId == nil)
                    }
                }
                // **打っている間はキーボードで写真の枠を縮めない。** 縮めると写真が縮んだ枠に合わせて
                // 切り直され、下に（隠した足元の分の）黒い帯が残った（2026-09-30 の owner の画面
                // 「画面の上の方おかしい」）。キーボードを避けるのは上に重ねた打つ画面だけ。
                // ひとことを打つ間は今まで通り避ける（欄がキーボードの下に隠れないように）
                .ignoresSafeArea(.keyboard, edges: photoIgnoresKeyboard ? .bottom : [])
                // 打っている間は後ろを読ませない（VoiceOver で投稿・他の札へ移れた）
                .accessibilityHidden(typingId != nil)
                if typingId == nil {
                    topBar
                        .dynamicTypeSize(...StoryViewerView.chromeTypeLimit)
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                }
                // 写真の上で直接打つ（開いたらすぐキーボード）
                if let typingId {
                    StoryTextTypingView(overlay: typingBinding(id: typingId),
                                        photoShortSide: photoShortSide,
                                        canvas: typingCanvas,
                                        photo: TextOverlay.filledRect(
                                            image: shots.first { $0.id == typingShotId }?.imageSize ?? typingCanvas,
                                            in: typingCanvas),
                                        onDelete: { deleteTyping() }) { finishTyping() }
                }
            }
        }
        // 見出しのバーは使わない（板 24 は写真の上に ✕ と「下書き保存」を重ねる）
        .toolbar(.hidden, for: .navigationBar)
        // 写真が入ったら、埋め込みの写真選びの選択は空にする（全部外して戻ったとき、前の選択のまま
        // 「次へ」を押すと同じ写真がもう一度入る）
        .onChange(of: shots.isEmpty) { _, empty in if !empty { librarySelection = [] } }
        // 誰に見せる（前は足元にあった「フォロワーが見られます」と2つのスイッチ）
        .sheet(isPresented: $showAudience) {
            StoryAudienceSheet(allowReplies: $allowReplies, keepInArchive: $keepInArchive) {
                showAudience = false
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(WebTheme.background)
        }
        .sheet(isPresented: $showStickerTray, onDismiss: {
            if let pick = pendingPick {
                pendingPick = nil
                place(pick)
            }
        }) {
            StickerTray(count: overlays.wrappedValue.count, hasVote: vote.wrappedValue != nil) { pick in
                pendingPick = pick
                showStickerTray = false
            }
            .presentationDetents([.medium, .large])
        }
        // 写真を切り替えたら投票の欄を閉じる（別の写真の投票の欄が出たままになった）
        .onChange(of: current) { _, _ in voteSelected = false }
        // キーボードを避けたい欄に移ったら、写真の枠もキーボードを避ける側へ戻す
        .onChange(of: captionFocused) { _, focused in if focused { photoIgnoresKeyboard = false } }
        .onChange(of: votePanelOpen) { _, open in if open { photoIgnoresKeyboard = false } }
        .sheet(isPresented: $showSongPicker) {
            NavigationStack {
                SongPickerView { picked in applySong(picked) }
            }
        }
        .sheet(isPresented: $showSongStart) {
            if let song {
                NavigationStack {
                    // **曲の札は変えない**（題と歌い手は同じ）。流し始めだけを入れ替える
                    SongStartSheet(song: song, durationSec: durationSec) { picked in self.song = picked }
                }
                // 中身は短い（画面いっぱいにしない）。大きな文字の人は引き上げられる
                .presentationDetents([.medium, .large])
            }
        }
        // **表示秒数を延ばしたら、流し始めを収まる所まで引き戻す**（Web と同じ）。
        // そのままだと、見る人には試聴の終わりの数秒がくり返し鳴る
        .onChange(of: durationSec) { _, window in
            if let song, song.fitting(window: window) != song {
                self.song = song.fitting(window: window)
            }
        }
        // 撮影地の候補のための索引。**写真を選んでから**読む（選ぶ段では使わない）
        .task(id: shots.isEmpty) {
            guard !shots.isEmpty, spotIndex.isEmpty else { return }
            let fetched = try? await environment.spots.fetchIndex()
            guard !Task.isCancelled, let fetched else { return }
            spotIndex = fetched
        }
        // 候補は**写真の位置か索引が変わったときだけ**解く（描き直しのたびに全件を当てない）
        .task(id: SuggestionKey(coords: shots.map(\.prepared.coords), spots: spotIndex.count)) {
            place.resolve(coords: shots.map(\.prepared.coords), spots: spotIndex)
        }
        .alert(L("撮影地", "Place"), isPresented: $showPlaceEditor) {
            // サーバーが 200 で切る（`sanitizeText(location, 200)`）。画面で止める
            TextField(L("撮影地（任意）", "Place (optional)"), text: Binding(
                get: { placeDraft },
                set: { placeDraft = PostLimits.limited(old: placeDraft, new: $0, limit: PostLimits.location) }))
            Button(L("決める", "Set")) { place.location = placeDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !place.location.isEmpty {
                Button(L("外す", "Remove"), role: .destructive) { place.location = "" }
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            // 座標は地名とセットのときだけ送る（名前の無い点は画面に出しようがない）
            Text(L("撮影地を入れると、写真に残っていた位置（約1kmに丸めたもの）も一緒に送ります。",
                   "Adding a place also sends the photo's rounded coordinates (about 1 km)."))
        }
        // **開いた直後に一度だけ尋ねる。** 黙って書きかけを復元すると、
        // 新しく作りにきた人が前の写真に驚く
        .onAppear {
            drafts.use(userId: auth.userId)
            // **尋ねるのは開いた回だけ。** カメラ（fullScreenCover）を閉じると onAppear が
            // もう一度走り、開いたときの問いがまた出ていた
            guard !askedOnOpen else { return }
            askedOnOpen = true
            // **送れなかった残りが先。** 片付くまで新しい投稿は受けないので、
            // ここでも出口を出す（ホームの輪が見えない人のため）
            if case .failed = uploads.phase {
                showPendingFailure = true
                // 下書きの問いは出ない＝答えていない。消さずに次へ持ち越す
                if prepared == nil { unansweredDraftStamp = drafts.draft?.savedAt }
            } else if Self.asksRestore(draftStamp: drafts.draft?.savedAt, hasShot: prepared != nil,
                                       sendingDraftStamp: uploads.pendingDraftStamp) {
                showRestore = true
            }
        }
        .confirmationDialog(L("送れなかったストーリーがあります", "A story didn't finish sending"),
                            isPresented: $showPendingFailure, titleVisibility: .visible) {
            Button(L("もう一度送る", "Try again")) {
                uploads.retry()
                dismiss()
            }
            Button(L("やめる", "Discard"), role: .destructive) { uploads.discard() }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            if case .failed(let message, _) = uploads.phase {
                Text(message)
            }
        }
        .alert(L("書きかけの下書きがあります", "You have a saved draft"), isPresented: $showRestore) {
            Button(L("続きから", "Continue")) { restoreDraft() }
            Button(L("捨てる", "Discard"), role: .destructive) { drafts.clear() }
            // 「キャンセル」は**残す**。この回の投稿が成功しても消さない
            Button(Labels.Common.cancel, role: .cancel) { keptDraftStamp = drafts.draft?.savedAt }
        } message: {
            Text(L("この端末に残しておいたものです。続きから編集できます。",
                   "Kept on this device. You can pick up where you left off."))
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { capture in acceptFromCamera(capture) }
                .ignoresSafeArea()
        }
        // **まとめて選べる**（モック4-5）。メニューの中に `PhotosPicker` を置くと
        // 開かないことがあるので、旗で開く
        .photosPicker(isPresented: $showLibrary, selection: $pickerItems,
                      maxSelectionCount: max(1, StoryQueue.maxShots - shots.count),
                      matching: .images)
        .onChange(of: pickerItems) { _, items in
            Task { await load(items) }
        }
        // 🔴 **選んだ写真・置いた文字を黙って消さない。** 以前は ✕ も下へ払うのも
        // 確かめずに閉じ、下書きにも残らなかった。「下書きに保存」は上の
        // 「下書き保存」と同じ道（`saveDraft`）で、**書けたときだけ閉じる**
        //
        // 🔴 **前の下書きを残すと決めた（「続きから」でキャンセル・まだ答えていない）間は
        // 「下書きに保存」を出さない。** 下書きは1件だけなので、保存すると残すと決めた
        // 下書きを黙って置き換える（投稿の `keepsDraft` と同じ判断）。
        // 戻した下書きを直した回の「捨てる」は**変更だけ**を捨てる（前の下書きは残る）ので、
        // そう言う（「続きから」の「捨てる」は下書きごと消すので、言葉を分ける）
        //
        // 🔴 **写真の読み込み中は「下書きに保存」を出さない**（`leaveDialog`）。右上の「…」の
        // 下書き保存と同じ条件——片方だけ止めると、読み込み中の写真を落とした下書きが別の口から書けた
        .unsavedCloseGuard(leave, isPresented: $showLeaveConfirm,
                           title: leaveDialog.title,
                           canSave: leaveDialog.canSave,
                           saveTitle: L("下書きに保存", "Save draft"),
                           discardTitle: restoredContent != nil ? L("変更を捨てる", "Discard changes")
                                                                : L("捨てる", "Discard"),
                           message: leaveDialog.message,
                           onSave: { saveDraft() },
                           onDiscard: { dismiss() })
    }

    // MARK: - 写真

    /// 写真を画面いっぱいに（下の角だけ半径24）。上下の暗がり、右の道具の列、
    /// 写真の上のひとこと・撮影地（曲は動かせる札）、左下の並び、右下の秒数（板 24）
    private var photoArea: some View {
        ZStack(alignment: .bottomLeading) {
            // 写真の後ろの地は黒（紺はパレットに無い）（デザインシステム「黒塗りの真鍮」）
            WebTheme.background.opacity(preview == nil ? 0 : 1)
            if let preview {
                StoryCanvas(preview: preview, imageSize: previewSize, overlays: overlays, framing: framing,
                            // 打っている札は打つ画面の真ん中に出す（写真の上に二重に出さない）
                            hiddenId: typingShotId == shots[current].id ? typingId : nil,
                            onTap: { overlay in
                                // **押したらすぐ打つ画面へ**（時刻・日付は書体・色・大きさだけ）。スタンプは何もしない
                                if StoryTextEditing.opensTyping(overlay) { startTyping(overlay.id) }
                            },
                            // 写真を押したら投票の欄を閉じる
                            onTapPhoto: { voteSelected = false },
                            // ゴミ箱へ運んで離した（VoiceOver の「消す」も）。**表示中の写真の札**
                            onDelete: { id in deleteOverlay(id) },
                            onDraggingChange: { draggingOverlay = $0 },
                            vote: vote,
                            voteSelected: voteSelected,
                            onTapVote: { voteSelected = true },
                            photoId: shots.indices.contains(current) ? shots[current].id : nil,
                            // 「ひとこと」の欄は**写真と札の間**に敷く（札の上に重ねると、真ん中の札を
                            // 欄が先に取って動かせなかった）
                            underOverlays: AnyView(captionLayer))
            } else {
                // 写真を読めなかった1枚（並びには居る）。黒のまま
                Color.black
            }
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 170)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            if typingId == nil && !votePanelOpen && preview != nil {
                mediaStrip
                    .padding(.leading, 16)
                    .padding(.bottom, 20)
                    // 札を動かしている間は**隠すだけ**（消すと、打っている欄が外れてキーボードが閉じ、
                    // 枠が伸びて札が指から外れた・81cbd07 のレビュー）
                    .opacity(draggingOverlay ? 0 : 1)
                    .allowsHitTesting(!draggingOverlay)
                .accessibilityHidden(draggingOverlay)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if typingId == nil && !votePanelOpen && preview != nil && shots.count > 1 {
                // 何枚目か（等幅）。表示秒数は右上の「…」へ移した
                shotCounter
                    .padding(.trailing, 16)
                    .padding(.bottom, 30)
                    // 札を動かしている間は**隠すだけ**（消すと、打っている欄が外れてキーボードが閉じ、
                    // 枠が伸びて札が指から外れた・81cbd07 のレビュー）
                    .opacity(draggingOverlay ? 0 : 1)
                    .allowsHitTesting(!draggingOverlay)
                .accessibilityHidden(draggingOverlay)
            }
        }
        .overlay(alignment: .bottom) {
            if votePanelOpen {
                VotePanel(vote: Binding(
                    get: { vote.wrappedValue ?? .new() },
                    set: { vote.wrappedValue = $0 }
                )) {
                    vote.wrappedValue = nil
                    voteSelected = false
                }
                // 札を運んでいる間は隠す（下のゴミ箱が欄の下に隠れた）
                .opacity(draggingOverlay ? 0 : 1)
                .allowsHitTesting(!draggingOverlay)
                .accessibilityHidden(draggingOverlay)
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rememberCanvas(geometry.size) }
                    .onChange(of: geometry.size) { _, size in rememberCanvas(size) }
            }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    // MARK: - 写真を選ぶ段

    /// 写真が0枚のとき。**開いてすぐ最近の写真の格子**（iOS 17 の埋め込みの写真選び）。
    /// 写真ライブラリの許可は求めない（`photoLibrary` を渡さない形は、選んだものだけを受け取る）。
    /// 開いたときの問い（送れなかった・続きから）は前のまま、この上に先に出る
    private var pickStage: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(L("ストーリー", "Story"))
                    .font(JPFont.display(18, relativeTo: .headline))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Button {
                        switch leave {
                        case .now: dismiss()
                        case .confirm: showLeaveConfirm = true
                        case .wait: break
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Labels.Common.close)
                    Spacer()
                    if CameraPicker.isAvailable {
                        // 撮って入れる（前のカメラの流れ。撮ったら `accept` で並びに入り、仕上げる段へ）
                        Button { showCamera = true } label: {
                            Image(systemName: "camera")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                                .background(WebTheme.surface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        // 印が上限まで付いていたら押せない（撮った1枚が上限で入らず失われる）
                        .disabled(loadingPicks > 0 || !cameraAllowed)
                        .opacity(loadingPicks > 0 || !cameraAllowed ? 0.4 : 1)
                        .accessibilityLabel(L("カメラ", "Camera"))
                        .accessibilityHint(cameraAllowed ? ""
                            : L("選べるのは\(StoryQueue.maxShots)枚までです。印を外すと撮れます",
                                "Up to \(StoryQueue.maxShots) photos. Unmark one to use the camera"))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 6)

            // 選んだ順に並ぶ（`.ordered`）。「キャンセル」「追加」を止めると、押すたびに選択が変わる
            PhotosPicker(selection: $librarySelection,
                         maxSelectionCount: StoryQueue.maxShots,
                         selectionBehavior: .ordered,
                         matching: .images) {
                Text(L("写真を選ぶ", "Choose photos"))
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .photosPickerAccessoryVisibility(.hidden, edges: .all)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            pickFooter
        }
    }

    /// 写真を選ぶ段のカメラを押せるか（印が上限まで付いていれば押せない）
    private var cameraAllowed: Bool {
        StorySimpleRules.canUseCameraOnPickStage(selected: librarySelection.count)
    }

    /// 写真を選ぶ段の下（知らせと白い「次へ（N枚）」）
    private var pickFooter: some View {
        let next = StorySimpleRules.nextButton(selected: librarySelection.count, loading: loadingPicks > 0)
        return VStack(spacing: 10) {
            if let message {
                Text(message).font(.footnote).foregroundStyle(WebTheme.muted2)
            }
            Button {
                // 読み込みは前の `load`（読めたものから並びに入り、1枚入ると仕上げる段に移る）
                let items = librarySelection
                Task { await load(items) }
            } label: {
                Group {
                    if loadingPicks > 0 {
                        ProgressView().tint(WebTheme.accentText)
                    } else {
                        Text(next.title)
                    }
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(WebTheme.accentText)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(WebTheme.accentBackground, in: Capsule())
                .opacity(next.enabled || loadingPicks > 0 ? 1 : 0.5)
                .accessibilityLabel(next.title)
                .accessibilityValue(loadingPicks > 0 ? L("写真を読み込んでいます", "Loading photos") : "")
            }
            .buttonStyle(.plain)
            .disabled(!next.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - 道具（写真の下の4つ）

    /// 文字・スタンプ・曲・場所を横に等分（面 #121212・角丸・高さ 64・アイコン＋名前 13pt）。
    /// 形と色は `StoryTool` の1か所から
    private var toolRow: some View {
        HStack(spacing: 8) {
            ForEach(StoryTool.allCases) { tool in
                toolControl(tool)
            }
        }
    }

    @ViewBuilder
    private func toolControl(_ tool: StoryTool) -> some View {
        let used = StoryTool.isUsed(tool, overlays: overlays.wrappedValue, hasVote: vote.wrappedValue != nil,
                                    hasSong: song != nil, location: place.location)
        switch tool {
        case .text:
            // 押したらすぐ写真の上で打つ（前の右の列の「Aa」と同じ）
            Button { startNewText() } label: { toolCell(tool, used: used) }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.accessibilityLabel(used: used))
        case .sticker:
            // 札とスタンプのトレイ。投票もここ（前の右の列と同じ）
            Button {
                captionFocused = false
                showStickerTray = true
            } label: { toolCell(tool, used: used) }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.accessibilityLabel(used: used))
        case .song:
            if song == nil {
                Button { showSongPicker = true } label: { toolCell(tool, used: used) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.accessibilityLabel(used: used))
            } else {
                // 付けた曲は変える・流し始め・外す（前の右の列のメニューと同じ）
                Menu {
                    Button(L("曲を変える", "Change song")) { showSongPicker = true }
                    // 流し始め（Web の「好きな部分」と同じ `startSec`）。いまの位置をメニューに出す
                    Button(L("流し始め（\(Photo.Song.startLabel(song?.startSec))）",
                             "Start point (\(Photo.Song.startLabel(song?.startSec)))")) { showSongStart = true }
                    Button(L("曲を外す", "Remove song"), role: .destructive) { applySong(nil) }
                } label: {
                    toolCell(tool, used: used)
                }
                .accessibilityLabel(tool.accessibilityLabel(used: used))
            }
        case .place:
            Button {
                placeDraft = place.location
                showPlaceEditor = true
            } label: { toolCell(tool, used: used) }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.accessibilityLabel(used: used))
        }
    }

    /// 道具の1つ。**使ったらアイコンを真鍮にし、右上に真鍮の点**（黒地の面の上なので真鍮を置ける）
    private func toolCell(_ tool: StoryTool, used: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: tool.symbol)
                .font(.title3.weight(StoryTool.symbolWeight))
                .foregroundStyle(used ? StoryTool.usedColor : StoryTool.idleColor)
                .frame(height: 24)
                .overlay(alignment: .topTrailing) {
                    if used {
                        Circle()
                            .fill(StoryTool.usedColor)
                            .frame(width: StoryTool.dotSize, height: StoryTool.dotSize)
                            .offset(x: 7, y: -3)
                    }
                }
            Text(tool.label)
                .font(.footnote)
                .foregroundStyle(WebTheme.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 写真の上の「ひとこと」の層（左寄せ・縦は真ん中）。**`StoryCanvas` が写真と札の間に敷く**
    /// ——札が欄より上で指を取る（描く順も同じなので、札は欄の文字の上に重なって見える）
    @ViewBuilder
    private var captionLayer: some View {
        if typingId == nil && !votePanelOpen && preview != nil {
            captionBlock
                .padding(.leading, 36)
                .padding(.trailing, 70)
                // 札を動かしている間は**隠すだけ**（消すと、打っている欄が外れてキーボードが閉じ、
                // 枠が伸びて札が指から外れた・81cbd07 のレビュー）
                .opacity(draggingOverlay ? 0 : 1)
                .allowsHitTesting(!draggingOverlay)
                .accessibilityHidden(draggingOverlay)
        }
    }

    /// 写真の上のひとこと（明朝32・影）と撮影地の札。**ひとことはその場で打つ**。
    /// 曲は動かせる札として写真に置く（`SongSticker`）
    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L("ひとことを書く", "Write a caption"), text: Binding(
                get: { caption },
                // サーバーが 200字で切る（`stories.ts`）。**改行は入れない**（見る画面は1段落）
                // 数え方はサーバーと同じ UTF-16（`PostLimits.limited`）。字で数えると絵文字の入った文が
                // 黙って切られた。改行の置き換えは先に（置き換えたあとの長さで止める）
                set: { caption = PostLimits.limited(old: caption,
                                                    new: $0.replacingOccurrences(of: "\n", with: " "),
                                                    limit: PostLimits.storyCaption) }
            ), axis: .vertical)
                .focused($captionFocused)
                .font(JPFont.display(32, relativeTo: .largeTitle))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .jpPhotoTextShadow()
            if !place.location.isEmpty {
                photoChip(symbol: "mappin", text: place.location)
            } else if let spot = place.chip {
                spotSuggestionChip(spot)
            }
            // 曲は**動かせる札で見せる**。帯は**どの写真にも札が無いときだけ**（札が上限で置けなかった・
            // 札の文字を打ち直した・札を置いた写真を外した・前の動きの下書き）。以前は表示中の写真に
            // 札が無ければ出していて、札のある写真と二重に見え、札をゴミ箱に入れると帯が代わりに出て
            // 「消せない」になった（2026-09-30 の owner）。最後の札を消すと曲も外れる（`deleteOverlay`）
            if let song, let text = SongSticker.text(for: song),
               !shots.contains(where: { SongSticker.isOnPhoto($0.overlays, song: song) }) {
                photoChip(symbol: "music.note", text: text)
            }
        }
    }

    /// 曲の札を置けない理由の一言。**状態から毎回決める**（覚えておくと、写真を
    /// 切り替えた・札を消したあとも「置けませんでした」が残る）。写真や投稿の
    /// 知らせ（`message`）とは別の欄——投稿の途中失敗の知らせを上書きしない
    /// **どの写真にもいまの曲の札が無いときだけ出す**（札は1枚にしか置かないので、
    /// 別の写真に置いてあれば足りている）
    private var songNote: String? {
        guard let song, let text = SongSticker.text(for: song), !currentHasSongSticker,
              overlays.wrappedValue.count >= TextOverlay.maxCount else { return nil }
        let placed = String(text.prefix(TextOverlay.maxLength))
        guard !shots.contains(where: { $0.overlays.contains { $0.kind == .song && $0.text == placed } })
        else { return nil }
        return L("文字と札がいっぱいなので、曲の札は置けません",
                 "No room for the song sticker on this photo")
    }

    /// いまの1枚に、付けた曲の札が置いてあるか
    private var currentHasSongSticker: Bool {
        guard let song, let text = SongSticker.text(for: song) else { return false }
        let placed = String(text.prefix(TextOverlay.maxLength))
        return overlays.wrappedValue.contains { $0.kind == .song && $0.text == placed }
    }

    private func photoChip(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption)
            Text(text).font(.caption).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .jpGlass(in: Capsule(), border: 0)
    }

    /// 撮影地の候補（`StorySpotSuggestion`）。**押したときだけ**撮影地に入る。
    /// 付けた札（`photoChip`）と見分けるため、破線の縁と「＋」（板の「写真を追加」と同じ破線）。
    /// 写真の上なので白だけ（真鍮は置かない）
    private func spotSuggestionChip(_ spot: OfficialSpot) -> some View {
        Button {
            place.pick()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.caption.weight(.semibold))
                Image(systemName: "mappin").font(.caption)
                Text(StorySpotLink.shortened(spot.name)).font(.caption).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .jpGlass(in: Capsule(), border: 0)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.45),
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            // **押せる所だけ上下に広げて 44pt に、並びは変えない**（見る画面の撮影地の行と同じ作り）
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .padding(.vertical, -9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("撮影地の候補 \(spot.name)。付ける", "Suggested place \(spot.name). Add"))
        .accessibilityHint(L("撮影スポットの名前と位置を見る人に見せます", "Shows the photo spot's name and location to viewers"))
    }

    /// 撮影地の候補を解き直す鍵（写真の座標の並びと索引の数）
    private struct SuggestionKey: Equatable {
        let coords: [Photo.Coords?]
        let spots: Int
    }

    /// 右下の「1 / 2」（等幅・ガラスの札）。並べた写真の何枚目を直しているか
    private var shotCounter: some View {
        Text("\(current + 1) / \(shots.count)")
            .font(JPFont.mono(12))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .jpGlass(in: Capsule(), border: 0)
            .frame(minHeight: 44)
            .accessibilityLabel(L("\(shots.count)枚のうち\(current + 1)枚目", "Photo \(current + 1) of \(shots.count)"))
    }

    /// 5・10・15 秒（`StoryService.durationChoices`・owner「細かい時間いらない」）。受けて読む幅は 3〜15 のまま
    @ViewBuilder
    private var durationOptions: some View {
        ForEach(StoryService.durationChoices, id: \.self) { sec in
            Button {
                durationSec = sec
            } label: {
                if sec == durationSec {
                    Label(L("\(sec) 秒", "\(sec)s"), systemImage: "checkmark")
                } else {
                    Text(L("\(sec) 秒", "\(sec)s"))
                }
            }
        }
    }

    // MARK: - 上のバー

    /// 左上は ✕（閉じる・確認つき）、右上は「…」（表示秒数・写真の合わせ方を戻す・下書き保存）。
    /// 投票の欄・ひとことを打っている間は、右上は「完了」（前のまま）
    private var topBar: some View {
        HStack {
            // **閉じる。** この段は写真がある間だけ出るので、前の ✕ と同じ確認（下書きに保存しますか）を通す。
            // 写真を全部外すと、ここを押さなくても写真を選ぶ段へ戻る
            Button {
                switch leave {
                case .now: dismiss()
                case .confirm: showLeaveConfirm = true
                case .wait: break
                }
            } label: {
                // 押すと画面ごと閉じる（確認つき）ので、見た目は ✕・読み上げは「閉じる」
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .jpGlass(in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(leave == .wait)
            .accessibilityLabel(Labels.Common.close)
            Spacer()
            if votePanelOpen {
                // 投票の欄を閉じる（欄の間は投稿ボタンが隠れるので、閉じる口を見える所に出す）
                Button { voteSelected = false } label: {
                    Text(L("完了", "Done"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(WebTheme.accentBackground, in: Capsule())
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("投票の編集を終える", "Finish editing poll"))
            } else if captionFocused {
                // ひとことのキーボードを閉じる（複数行なので Return では閉じない）
                Button { captionFocused = false } label: {
                    Text(L("完了", "Done"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(WebTheme.accentBackground, in: Capsule())
                        // 見た目は 36 の札のまま、押せる所は 44（CLAUDE.md の最小）
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                moreMenu
            }
        }
    }

    /// 右上の「…」。前は右の列（表示秒数・合わせ方を戻す）・右下の札（表示秒数）・右上（下書き保存）に
    /// 散っていたものをまとめた。中身の動きは前のまま
    private var moreMenu: some View {
        Menu {
            // 5・10・15 秒（前の右下の「表示 5 秒」と同じ選び方）
            Menu {
                durationOptions
            } label: {
                Label(L("表示秒数（\(durationSec) 秒）", "Duration (\(durationSec)s)"), systemImage: "timer")
            }
            // 写真を拡大・移動・回転したら、元へ戻す口（写真を2回押しても戻る）
            if !framing.wrappedValue.isIdentity {
                Button {
                    framing.wrappedValue = .identity
                } label: {
                    Label(L("写真の合わせ方を戻す", "Reset photo framing"), systemImage: "arrow.counterclockwise")
                }
            }
            // **写真が無ければ下書きにできない。** 文字だけ残しても「続きから」で出すものが無い。
            // 残すと決めた下書きがある間・読み込み中も止める（前の「下書き保存」と同じ条件）
            Button {
                saveDraft()
            } label: {
                Label(L("下書き保存", "Save draft"), systemImage: "square.and.arrow.down")
            }
            .disabled(prepared == nil || !canSaveDraft || loadingPicks > 0)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .jpGlass(in: Circle())
        }
        .accessibilityLabel(L("その他", "More"))
    }

    // MARK: - 足元

    /// 写真の下: 知らせ・道具4つ・「フォロワー ▾」と白い「シェアする」
    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message, prepared != nil {
                Text(message).font(.footnote).foregroundStyle(WebTheme.muted2)
            }
            if let songNote, prepared != nil {
                Text(songNote).font(.footnote).foregroundStyle(WebTheme.muted2)
            }
            toolRow
            HStack(spacing: 10) {
                // 誰に見せる（シート）。🔴 **ストーリーはフォロワーだけが見る**（2026-09-22・owner の
                // 判断。`api-user/src/storyVisibility.ts`）ので、いまは「フォロワー」だけ
                Button { showAudience = true } label: {
                    HStack(spacing: 6) {
                        Text(L("フォロワー", "Followers"))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.text)
                    .fixedSize()
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("見せる相手: フォロワー", "Audience: Followers"))
                .accessibilityHint(L("返信と、24時間後も残すかもここで決めます",
                                     "Also set replies and whether to keep it after 24 hours"))

                Button {
                    post()
                } label: {
                    // 押したら画面を閉じる。**送信中は自分の輪に出る**（板 27）
                    Group {
                        if loadingPicks > 0 {
                            ProgressView().tint(WebTheme.accentText)
                        } else {
                            Text(L("シェアする", "Share"))
                        }
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WebTheme.accentBackground, in: Capsule())
                    .opacity(prepared == nil ? 0.5 : 1)
                    // 輪を出している間も読み上げは空にしない
                    .accessibilityLabel(L("シェアする", "Share"))
                    .accessibilityValue(loadingPicks > 0 ? L("写真を読み込んでいます", "Loading photos") : "")
                }
                .buttonStyle(.plain)
                .disabled(prepared == nil || loadingPicks > 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - 文字と札

    /// 新しい文字を足して、**すぐ打つ画面を開く**。上限なら断りを出す
    private func startNewText() {
        guard shots.indices.contains(current) else { return }
        guard let overlay = StoryTextEditing.newText(in: overlays.wrappedValue) else {
            message = L("文字と札は1枚に\(TextOverlay.maxCount)個までです",
                        "Up to \(TextOverlay.maxCount) text items per photo")
            return
        }
        overlays.wrappedValue.append(overlay)
        startTyping(overlay.id)
    }

    /// 打つ画面のゴミ箱。**空にして、打ち終えたときと同じ片付けを通す**（`finishTyping` が空の札を
    /// 取り除き、付けた曲の最後の札なら曲も外す——ゴミ箱へ運んだときと同じ扱い）
    private func deleteTyping() {
        guard let id = typingId else { return }
        typingBinding(id: id).wrappedValue.text = ""
        finishTyping()
    }

    /// いま表示中の写真の札を打ち始める。**打つ先の写真を覚える**
    private func startTyping(_ id: UUID) {
        guard shots.indices.contains(current) else { return }
        // 別の札を打っている最中に呼ばれたら（VoiceOver など）、前の札を先に確定する
        if typingId != nil { finishTyping() }
        captionFocused = false
        voteSelected = false
        // キーボードが出る前の枠で文字の大きさを決める（`photoShortSide`）
        typingCanvas = canvasSize
        typingShotId = shots[current].id
        typingSongSticker = overlays.wrappedValue.first { $0.id == id }.map { SongSticker.isSticker($0, of: song) } ?? false
        photoIgnoresKeyboard = true
        typingId = id
    }

    /// 打ち終えた。**空なら置かない**（新しく足した札も、打ち直して消した札も）。
    /// 片付ける先は**打ち始めた写真**（表示中の写真ではない）
    private func finishTyping() {
        if let id = typingId, let shotId = typingShotId,
           let i = shots.firstIndex(where: { $0.id == shotId }) {
            let before = shots[i].overlays.first { $0.id == id }
            shots[i].overlays = StoryTextEditing.finish(shots[i].overlays, id: id)
            // 曲の札を空にして閉じた＝札を消した（ゴミ箱と同じ扱い）
            let removed = shots[i].overlays.contains { $0.id == id } ? nil : before
            if typingSongSticker, removed != nil,
               SongSticker.shouldDetach(removedSticker: true, remaining: shots.map(\.overlays), song: song) {
                applySong(nil)
            }
        }
        typingId = nil
        typingShotId = nil
        typingSongSticker = false
    }

    /// 打っている札への窓。**打ち始めた写真の中を id で引く**（表示中の写真が移っても同じ札）
    private func typingBinding(id: UUID) -> Binding<TextOverlay> {
        Binding(
            get: {
                shots.first { $0.id == typingShotId }?.overlays.first { $0.id == id } ?? TextOverlay(text: "")
            },
            set: { value in
                guard let s = shots.firstIndex(where: { $0.id == typingShotId }),
                      let o = shots[s].overlays.firstIndex(where: { $0.id == id }) else { return }
                shots[s].overlays[o] = value
            }
        )
    }

    /// 画面上の写真の短い辺（打つ画面の文字の大きさ・焼き込みと同じ基準）。
    /// 枠は**打ち始めた瞬間の枠**（キーボードが出る前・`typingCanvas`）
    private var photoShortSide: Double {
        let shot = shots.first { $0.id == typingShotId }
        return StoryTextEditing.photoShortSide(canvas: typingCanvas, image: shot?.imageSize)
    }

    /// 写真の枠の大きさ（いまの配置のまま）。**高い方を覚える形にはしない**——
    /// 高い方を覚えると、枠が一時的に高くなった値（以前の「文字と札」モードでフッターが消えたとき）に
    /// 張り付いて、打つ画面の文字が置いたあとより2割ほど大きく見えた（4ffb74f のレビュー）。キーボードの分は、打ち始めた瞬間の
    /// 枠を `typingCanvas` に写して避ける（キーボードは打ち始めた後に出る）
    private func rememberCanvas(_ size: CGSize) {
        // ひとことのキーボードで縮んだ枠は覚えない（そのまま「Aa」を押すと、縮んだ枠で大きさを決める）。
        // 投票の欄の間（足元が消えて伸びた枠・欄のキーボードで縮んだ枠）も覚えない——札を押すと
        // 欄が閉じて足元が戻るので、打つ画面の文字が置いたあとより2割大きく見えた（f38d404 のレビュー）
        guard !captionFocused && !votePanelOpen else { return }
        canvasSize = size
    }

    /// 表示中の写真の札を消す（ゴミ箱・VoiceOver の「消す」）。**付けた曲の最後の札なら曲も外す**
    /// （Instagram と同じ。札だけ消えて曲が黙って残ると、画面から曲が付いていると分からない）。
    /// 別の写真にも同じ曲の札があれば、曲はそちらで見えているので外さない
    private func deleteOverlay(_ id: UUID) {
        let removed = overlays.wrappedValue.first { $0.id == id }
        overlays.wrappedValue.removeAll { $0.id == id }
        let wasSticker = removed.map { SongSticker.isSticker($0, of: song) } ?? false
        if SongSticker.shouldDetach(removedSticker: wasSticker, remaining: shots.map(\.overlays), song: song) {
            applySong(nil)
        }
    }

    /// 曲を付ける・変える・外す。**写真の上の曲の札も合わせる**——付けたら
    /// いま見ている1枚に動かせる札を置き、変えたら札の文字を差し替え、外したら消す。
    /// 曲は全部の写真に共通なので、差し替えと削除は全部の写真で行う
    private func applySong(_ new: Photo.Song?) {
        let old = song
        song = new
        var found = false
        for i in shots.indices {
            let result = SongSticker.retext(shots[i].overlays, from: old, to: new)
            shots[i].overlays = result.overlays
            found = found || result.found
        }
        // 前の札が無ければ（初めて付けた・自分で消していた）いまの1枚に置く。
        // 札が上限なら置かない（曲は投稿の項目として送られ、閲覧画面の ♪ に出る）
        guard !found, let new, let sticker = SongSticker.make(for: new),
              shots.indices.contains(current) else { return }
        guard shots[current].overlays.count < TextOverlay.maxCount else {
            return
        }
        shots[current].overlays.append(sticker)
    }

    /// トレイで選んだものを置く（`StickerTray`）。**撮影地・タグ・曲は置いたらすぐ打つ画面へ**
    /// （空のまま打つ画面を閉じれば置かない）。時刻・日付・スタンプはそのまま置く
    private func place(_ pick: StickerTray.Pick) {
        guard shots.indices.contains(current) else { return }
        switch pick {
        case .vote:
            // 写真1枚に1つ。置いてあれば選び直すだけ
            if vote.wrappedValue == nil { vote.wrappedValue = .new() }
            voteSelected = true
        case .stamp(let emoji):
            guard overlays.wrappedValue.count < TextOverlay.maxCount else { return }
            // 文字より大きく、真ん中に（どこに置いたか分かるように）
            overlays.wrappedValue.append(TextOverlay(text: emoji, x: 0.5, y: 0.5, size: TextOverlay.stampSize,
                                                     kind: .stamp))
            voteSelected = false
        case .kind(let kind):
            guard overlays.wrappedValue.count < TextOverlay.maxCount else { return }
            // 曲を付けてあれば、その曲の札（右の列の「曲」と同じ札・打たなくてよい）
            if kind == .song, let song, let sticker = SongSticker.make(for: song) {
                // 同じ写真に付けた曲の札が既にあれば置かない（右の列の「曲」と同じく1枚）
                if !SongSticker.retext(overlays.wrappedValue, from: song, to: song).found {
                    overlays.wrappedValue.append(sticker)
                }
                voteSelected = false
                return
            }
            // 札（撮影地・曲など）は真ん中より少し下・ゴシックの帯（文字の札と重なりにくい）
            let overlay = TextOverlay(text: kind.initialText(), x: 0.5, y: 0.6, kind: kind, face: .gothic)
            overlays.wrappedValue.append(overlay)
            voteSelected = false
            if kind.isEditable { startTyping(overlay.id) }
        }
    }

    // MARK: - 共通

    /// 選ばれたぶんを順に足す。**1枚も読めなかったときだけ断りを出す**
    /// ——何枚か読めた回に「読み込めませんでした」だけ出すと、
    /// 並んでいるものが見えているのに失敗したように読める。
    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        loadingPicks += 1
        defer { loadingPicks -= 1 }
        // **1枚ごとに上限時間**（`StorySimpleRules.pickLoadTimeout`）。返らない1枚で
        // 読み込み中が解けず、「シェアする」・「＋」が止まったままにならないように
        let failed = await StorySimpleRules.readPicks(items, read: { item in
            try await item.loadTransferable(type: Data.self)
        }, accept: { data in
            await accept(data)
        })
        if failed > 0 {
            message = failed == items.count
                ? L("写真を読み込めませんでした", "Couldn't load the photos")
                : L("\(failed)枚を読み込めませんでした", "Couldn't load \(failed) of them")
        }
        // **選び終えたら空にする。** 残すと、次に同じ写真を選んでも
        // `onChange` が動かない（同じ値なので知らせが来ない）
        pickerItems = []
    }

    /// カメラで撮った1枚。**写真を選ぶ段で印を付けていた写真があれば、先にそれを読み込む**
    /// （「次へ」と同じ `load`）。撮った1枚は最後。以前は印を付けた写真が黙って消えた
    ///
    /// **JPEG にするのは画面の処理の外で**（`CameraCapture` の注記）。その間は読み込み中に数える
    /// （「次へ」・投稿を押させない）
    private func acceptFromCamera(_ capture: CameraCapture) {
        let pending = StorySimpleRules.picksToLoadBeforeCamera(librarySelection, hasShots: !shots.isEmpty)
        loadingPicks += 1
        Task {
            defer { loadingPicks -= 1 }
            await load(pending)
            // 読み込めなかった断り（`load` の知らせ）は、撮った1枚が入っても消さない
            // （先に読むものが無かった回は、前の知らせを持ち越さない——以前と同じ）
            let note = pending.isEmpty ? nil : message
            guard let data = await Task.detached(priority: .userInitiated, operation: { capture.jpegData() }).value else {
                message = L("写真を読み込めませんでした", "Couldn't load the photo")
                return
            }
            await accept(data)
            if message == nil { message = note }
        }
    }

    /// 1枚受け取る。**足す**（選び直しではない）。
    ///
    /// 文字は写真ごとに持つので、足した写真には何も付いていない状態で
    /// 始まる——前の写真の文字が別の絵に残ると、置いた場所の意味が変わる。
    private func accept(_ data: Data) async {
        do {
            // **縮小・EXIF の書き直しは画面の処理の外で**（投稿の `prepareOffMain`・`EditPhotoView` と同じ）。
            // 1枚に数百ミリ秒かかり、選んだ枚数ぶん画面が止まっていた
            let prepared = try await Task.detached(priority: .userInitiated) {
                try ImagePreparer.prepare(data: data, fileName: "story")
            }.value
            guard shots.count < StoryQueue.maxShots else {
                message = L("一度に出せるのは\(StoryQueue.maxShots)枚までです",
                            "You can post up to \(StoryQueue.maxShots) at once")
                return
            }
            let shot = StoryShot(prepared: prepared, image: UIImage(data: prepared.data))
            shots.append(shot)
            // 足したらそれを編集する（選んだ直後に文字を置ける）。
            // **打っている間も移らない**（打つ先は `typingShotId` で引くが、見えている写真と打っている
            // 写真が違うと、完了した後に別の写真が出て驚く）
            // 投票の欄を打っている間も移らない（移ると欄が閉じてキーボードも消えた）
            // 札とスタンプのトレイ（閉じてから置く `pendingPick` の間も）・曲を選ぶシートを開いている間も
            // 移らない（選んだ札や曲の札が、開いたときの写真でなく届いた写真に置かれた）
            if typingId == nil && !votePanelOpen && !showStickerTray && pendingPick == nil && !showSongPicker {
                current = shots.count - 1
            }
            self.message = nil
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("写真を読み込めませんでした", "Couldn't load the photo")
        }
    }


    /// 左下の並び（板 24。44×56・選んでいる1枚は白の輪・他は薄く、最後に「＋」）。
    /// **順番がそのまま出る順**。長押しで前後へ移す・外す
    private var mediaStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                Button {
                    current = index
                } label: {
                    thumb(shot, index: index)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    // 並べ替え（出る順を変える）。端では出さない（押しても動かない項目を置かない）
                    if index > 0 {
                        Button { move(from: index, to: index - 1) } label: {
                            Label(L("前へ移す", "Move earlier"), systemImage: "arrow.left")
                        }
                    }
                    if index < shots.count - 1 {
                        Button { move(from: index, to: index + 1) } label: {
                            Label(L("後ろへ移す", "Move later"), systemImage: "arrow.right")
                        }
                    }
                    Button(role: .destructive) { remove(at: index) } label: {
                        Label(L("この写真を外す", "Remove this photo"), systemImage: "trash")
                    }
                    // 読み込み中は外さない（全部外れて写真を選ぶ段へ戻り、届いた写真でまた仕上げる段へ、と行き来する）
                    .disabled(!StorySimpleRules.canRemoveShot(loading: loadingPicks > 0))
                }
                // 読み上げからも移す・外す（長押しのメニューは見つけにくい）
                .accessibilityAction(named: L("前へ移す", "Move earlier")) { move(from: index, to: index - 1) }
                .accessibilityAction(named: L("後ろへ移す", "Move later")) { move(from: index, to: index + 1) }
                .accessibilityAction(named: L("この写真を外す", "Remove this photo")) { remove(at: index) }
            }
            if shots.count < StoryQueue.maxShots {
                Menu {
                    Button { showLibrary = true } label: {
                        Label(L("ライブラリ", "Library"), systemImage: "photo")
                    }
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: {
                            Label(L("カメラ", "Camera"), systemImage: "camera")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 56)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .accessibilityLabel(L("写真を追加", "Add a photo"))
                // 読み込み中は足さない（投稿・下書き保存と同じ条件）。2本の読み込みが混ざって並び、
                // 10枚を超えた分が落ちた
                .disabled(loadingPicks > 0)
                .accessibilityValue(loadingPicks > 0 ? L("写真を読み込んでいます", "Loading photos") : "")
                .opacity(loadingPicks > 0 ? 0.4 : 1)
            }
        }
    }

    private func thumb(_ shot: StoryShot, index: Int) -> some View {
        let isCurrent = index == current
        return Group {
            if let preview = shot.preview {
                Color.clear.overlay { preview.resizable().aspectRatio(contentMode: .fill) }
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: 44, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.white, lineWidth: isCurrent ? 2 : 0))
        .opacity(isCurrent ? 1 : 0.7)
        .accessibilityLabel(L("\(index + 1)枚目", "Photo \(index + 1)"))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// 1枚を前後へ移す。**編集している写真を追いかける**（`StoryQueue.currentAfterMoving`）。
    /// 範囲の外へは移さない（読み上げの操作は端でも呼べる）
    private func move(from: Int, to: Int) {
        guard shots.indices.contains(from), shots.indices.contains(to), from != to else { return }
        let shot = shots.remove(at: from)
        shots.insert(shot, at: to)
        current = StoryQueue.currentAfterMoving(from: from, to: to, current: current)
    }

    /// 1枚外す。**編集中の位置がずれないように直す**
    /// ——直さないと、外した瞬間に別の写真の文字を触ることになる
    private func remove(at index: Int) {
        guard shots.indices.contains(index),
              StorySimpleRules.canRemoveShot(loading: loadingPicks > 0) else { return }
        shots.remove(at: index)
        current = StoryQueue.currentAfterRemoving(index, current: current, count: shots.count)
    }

    /// 閉じる確認の中身（`unsavedCloseGuard`）
    private var leaveDialog: LeaveDialog {
        Self.leaveDialog(canSaveDraft: canSaveDraft, loading: loadingPicks > 0,
                         restored: restoredContent != nil)
    }

    /// 閉じる確認の題・「下書きに保存」を出すか・説明
    struct LeaveDialog: Equatable {
        let title: String
        let canSave: Bool
        let message: String
    }

    /// 閉じる確認の中身を決める。
    ///
    /// 🔴 **2026-10-07 判断: 写真の読み込み中は「下書きに保存」を出さない。** 右上の「…」の
    /// 下書き保存は読み込み中は押せないのに、閉じる確認からは通り、読み込み中の写真を
    /// 落とした下書きを書いて閉じていた。待てば読み込みは終わる（上限は
    /// `StorySimpleRules.pickLoadTimeout`）ので、「キャンセル」して待ってもらう
    nonisolated static func leaveDialog(canSaveDraft: Bool, loading: Bool, restored: Bool) -> LeaveDialog {
        guard canSaveDraft else {
            return LeaveDialog(
                title: L("閉じますか？", "Close?"), canSave: false,
                message: L("選んだ写真と置いた文字は消えます。前の下書きはそのまま残ります（下書きは1件だけです）。",
                           "The photos and text you added will be lost. Your earlier draft stays (only one draft is kept)."))
        }
        guard !loading else {
            return LeaveDialog(
                title: L("閉じますか？", "Close?"), canSave: false,
                message: L("写真を読み込んでいる間は下書きに保存できません。保存するならキャンセルして、読み込み終わるまでお待ちください。閉じると、選んだ写真と置いた文字は消えます。",
                           "You can't save a draft while photos are loading. To save, tap Cancel and wait for them to finish. If you close now, the photos and text you added will be lost."))
        }
        return LeaveDialog(
            title: L("下書きに保存しますか？", "Save as a draft?"), canSave: true,
            message: restored
                ? L("閉じると、下書きを開いてからの変更は消えます（前の下書きは残ります）。",
                    "If you close now, your changes since opening the draft will be lost. The draft itself stays.")
                : L("閉じると、選んだ写真と置いた文字は消えます。下書きはこの端末にだけ残ります。",
                    "If you close now, the photos and text you added will be lost. Drafts stay on this device only."))
    }

    /// 下書きに保存できないときの一言（`saveDraft`）。保存できるなら nil
    nonisolated static func draftSaveBlockedNote(loading: Bool) -> String? {
        loading ? L("写真の読み込み中は下書きに保存できません。読み込み終わってからお試しください",
                    "You can't save a draft while photos are loading. Try again when they finish.")
                : nil
    }

    /// 下書きにする。**焼き込む前の文字のまま残す**
    /// ——焼いてしまうと位置も色も直せなくなる（投稿と同じ片道になる）。
    /// **並べた写真を全部残す。** 以前は表示中の1枚だけを渡していて、
    /// 3枚並べて保存しても開き直すと1枚になっていた
    private func saveDraft() {
        guard !shots.isEmpty else { return }
        // 読み込み中は書かない（閉じる確認・「…」の両方で止めているが、確認を出した後に
        // 読み込みが始まった回の念のため）。書かずに閉じもしないが、**黙って戻らない**——
        // 押した人には何も起きないように見える。理由を知らせに出す
        if let blocked = Self.draftSaveBlockedNote(loading: loadingPicks > 0) {
            message = blocked
            return
        }
        let ok = drafts.save(
            shots: shots.map { shot in
                StoryDraftStore.ShotInput(imageData: shot.prepared.data,
                                          fileName: shot.prepared.fileName,
                                          contentType: shot.prepared.contentType,
                                          coords: shot.prepared.coords,
                                          overlays: shot.overlays,
                                          framing: shot.framing.isIdentity ? nil : shot.framing,
                                          vote: shot.vote)
            },
            caption: caption,
            location: place.location,
            song: song,
            durationSec: durationSec,
            archive: keepInArchive,
            allowReplies: allowReplies,
            savedAt: ISO8601DateFormatter().string(from: Date())
        )
        // **書けなかったことを黙らない。** 「保存しました」とだけ出して
        // 実際は消えている、が いちばん困る
        message = ok
            ? L("下書きに保存しました（この端末にだけ残ります）", "Saved as a draft on this device")
            : L("下書きを保存できませんでした（端末の空き容量を確かめてください）",
                "Couldn't save the draft — check your device's free space")
        if ok { dismiss() }
    }

    /// 送り終えたときに下書きを**残す**か。「キャンセル（残す）」を選んだか、
    /// **問いに答えていない**下書き（送れなかった問いが先に出た回）なら残す。
    /// 同じ回に保存し直した下書き（印が変わった）は、この回の投稿のもの
    nonisolated static func keepsDraft(stamp: String?, keptStamp: String?, unansweredStamp: String?) -> Bool {
        guard let stamp else { return false }   // 守る下書きがもう無い
        return stamp == keptStamp || stamp == unansweredStamp
    }

    /// 開いたときに「続きから」を尋ねるか。**裏で送っている最中の下書きには尋ねない**
    /// ——送り終えるまで下書きは残るので、尋ねると同じ投稿をもう1本出しやすい
    nonisolated static func asksRestore(draftStamp: String?, hasShot: Bool, sendingDraftStamp: String?) -> Bool {
        guard let draftStamp, !hasShot else { return false }
        return draftStamp != sendingDraftStamp
    }

    /// この画面から下書きに保存してよいか。**残すと決めた（まだ答えていない）下書きがある
    /// 間は保存しない**——下書きは1件だけなので、保存すると黙って置き換える。
    /// 閉じる確認と上の「下書き保存」の両方がこれを見る（片方だけ守ると別の口から素通りした）
    private var canSaveDraft: Bool {
        !Self.keepsDraft(stamp: drafts.draft?.savedAt, keptStamp: keptDraftStamp,
                         unansweredStamp: unansweredDraftStamp)
    }

    /// ✕・下へ払ったときの扱い。**写真が1枚でもあれば確かめる**
    /// ——文字・ひとこと・撮影地・曲は写真の上にしか置けない（写真が無い間は
    /// 出ていない）うえ、下書きも写真が無ければ作れないので、写真の有無が境目。
    /// ただし「続きから」で戻したまま何も変えていなければそのまま閉じる
    /// （同じものが下書きに残っている）。
    ///
    /// 送るのは裏の係で、この画面に「送っている最中」は無い（投稿で即座に閉じる）
    /// ——`.wait` はここからは出ない。
    nonisolated static func leave(_ content: StoryComposerContent, restored: StoryComposerContent?) -> UnsavedLeave {
        UnsavedLeave.decide(hasChanges: !content.shotIds.isEmpty && content != restored,
                            isSaving: false)
    }

    /// 「続きから」。**画像が読めなければ何も戻さない**
    private func restoreDraft() {
        let saved = drafts.shotImages()
        guard let draft = drafts.draft, !saved.isEmpty else {
            drafts.clear()
            message = L("下書きの写真を読み込めませんでした", "Couldn't load the draft photo")
            return
        }
        // **並びごと戻す**（下書きは端末に1件。その中に並べた写真が全部入っている）
        shots = saved.map { item in
            let restored = ImagePreparer.Prepared(data: item.data, fileName: item.shot.fileName,
                                                  contentType: item.shot.contentType,
                                                  // EXIF は下書きに残していない（ストーリーは送らない）
                                                  exif: nil, coords: item.shot.coords, takenOn: nil)
            return StoryShot(prepared: restored, image: UIImage(data: item.data),
                             overlays: item.shot.overlays, framing: item.shot.framing ?? .identity,
                             vote: item.shot.vote)
        }
        current = 0
        // 古い下書き（字で数えていた頃）は 200 単位を超えていることがある。欄は超えたぶんを
        // 減らす変更しか受けないので、読み込むときに一度だけ収める
        caption = PostLimits.clamp(draft.caption, limit: PostLimits.storyCaption)
        place.location = draft.location
        // 流し始めは表示秒数に収めてから戻す（`restoredContent` もその値で撮る）。
        // 収まっていない下書きをそのまま戻すと、表示秒数が変わらない回は上限を越えたまま
        // 送られ、変わる回は何も触らずに閉じても「変更あり」になった（c15a415 のレビュー）
        // 前に選べた秒数（3・7 など）の下書きは、いま選べる近い秒数へ寄せる（メニューで
        // どれにも印が付かず、選び直すと戻せない形を作らない・686566d のレビュー）
        let window = StoryService.nearestDurationChoice(draft.durationSec)
        song = draft.song?.fitting(window: window)
        durationSec = window
        keepInArchive = draft.archive == true
        allowReplies = draft.allowReplies != false
        message = nil
        restoredContent = content
    }


    /// 出す。**送るのは裏の係（`StoryUploadCenter`）**——画面はすぐ閉じ、
    /// ホームの自分の輪が進み具合と「送信中…」を出す（板 27「投稿した直後」）。
    ///
    /// 以前はここで送り終えるまで待ち、その間は画面を閉じられなかった。
    /// 途中で失敗したときの決まり（止める・出たぶんは残す・残りを持つ）は
    /// 係の側へそのまま移した。
    private func post() {
        // 🔴 **二度押しで二重に出さない**（2026-09-25 owner「2重投稿」）。
        // ここは同期で、1回目で画面を閉じ係に渡す。2回目は係が「片付いていない
        // 並びがある」で受けない
        guard !shots.isEmpty, let ownerId = auth.userId else { return }
        // **欠けた投票は送らない**（サーバーが黙って落とす＝置いたのに出ない）。どの写真かを言う
        if let index = shots.firstIndex(where: { $0.vote.map { !$0.isComplete } ?? false }) {
            current = index
            message = L("\(index + 1)枚目の投票に、問いと2つの選択肢を入れてください",
                        "Fill in the question and both options of the poll on photo \(index + 1)")
            return
        }
        message = nil
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeText = place.location.trimmingCharacters(in: .whitespacesAndNewlines)
        // **焼き込んでから渡す。** 文字が無ければ元のデータをそのまま渡す
        // （読み書きの往復で画質を落とさない）
        // 撮影地は全部で1つなので、基準の写真から遠い写真の座標は送らない（`StoryQueue.coordsToSend`）。
        // 手で書いた撮影地が写真の近くのスポットを指さなければ、座標を送らない（`Place.coordsToSend`・2026-10-07）
        let coords = place.coordsToSend(shots.map(\.prepared.coords), spots: spotIndex)
        let jobs = zip(shots, coords).map { shot, shotCoords in
            StoryUploadCenter.Job(
                imageData: TextOverlayRenderer.burn(shot.overlays, framing: shot.framing, into: shot.prepared.data),
                caption: caption, location: placeText, coords: shotCoords,
                song: song, durationSec: durationSec, archive: keepInArchive,
                allowReplies: allowReplies,
                texts: StoryPostText.list(vote: shot.vote, caption: caption),
                // 曲の札を焼き込んだ1枚は、見る画面の ♪ の行を出さない（曲名が2か所に出ない）
                songOnPhoto: SongSticker.isOnPhoto(shot.overlays, song: song))
        }
        let stories = environment.stories
        let drafts = drafts
        let keepExistingDraft = Self.keepsDraft(stamp: drafts.draft?.savedAt,
                                                keptStamp: keptDraftStamp,
                                                unansweredStamp: unansweredDraftStamp)
        // 🔴 **押した時点の下書きの印。** 送り終えたときに下書きが入れ替わって
        // いたら（送信中にもう一度開いて保存した）、それは消さない
        let draftStamp = drafts.draft?.savedAt
        let auth = auth
        let toasts = toasts
        let started = uploads.start(jobs, ownerId: ownerId,
                                    currentUserId: { auth.userId },
                                    // 起動し直して送り終えたときの片づけ（下の onAllSent と同じ条件）
                                    draftToClear: keepExistingDraft ? nil : draftStamp,
                                    send: { job, record in
            // 送り直しで二重に出さない手順は `StoryService.post` にある
            try await stories.post(job, ownerId: ownerId, record: record)
        }, onAllSent: {
            // 出し終えたら下書きは要らない（残すと次に開いたときにまた尋ねる）。
            // 🔴 **ただし復元を保留した古い下書きは消さない**——この回の投稿とは別物
            if !keepExistingDraft, drafts.draft?.savedAt == draftStamp { drafts.clear() }
        }, onFailed: { message in
            toasts.show(message, kind: .failure)
        })
        guard started else {
            // 係が片付いていない。**送っている最中か、失敗した残りを持っているか**で言い分けを変える
            if case .failed = uploads.phase {
                message = L("送れなかったストーリーが残っています。ホームの自分の輪から、送り直すかやめるかを選んでください",
                            "A story that failed to send is waiting. Retry or discard it from your ring on Home.")
            } else {
                message = L("前のストーリーをまだ送っています。ホームの自分の輪で進み具合を確かめてください",
                            "Your previous story is still sending. Check your ring on Home.")
            }
            return
        }
        dismiss()
    }
}

/// 出す写真1枚ぶん（モック4-5 のストリップの1コマ）。
///
/// **文字を写真ごとに持つ。** 焼き込みは写真ごとに起きるので、
/// まとめて1つ持つと、切り替えた瞬間に別の絵へ前の文字が乗る。
struct StoryShot: Identifiable {
    let id = UUID()
    var prepared: ImagePreparer.Prepared
    var preview: Image?
    /// 写真の大きさ。**焼き込みと同じ `UIImage(data:)` から採る**ので、
    /// 編集画面の文字は投稿される画像と同じ基準で置かれる
    var imageSize: CGSize?
    var overlays: [TextOverlay] = []
    /// 写真の合わせ方（拡大・位置・回し）。**写真ごと**（文字と同じ理由）
    var framing: PhotoFraming = .identity
    /// 投票（写真1枚＝1本に1つ）。**焼き込まずにデータで送る**
    var vote: StoryVoteDraft?

    init(prepared: ImagePreparer.Prepared, image: UIImage?, overlays: [TextOverlay] = [],
         framing: PhotoFraming = .identity, vote: StoryVoteDraft? = nil) {
        self.prepared = prepared
        self.preview = image.map { Image(uiImage: $0) }
        self.imageSize = image?.size
        self.overlays = overlays
        self.framing = framing
        self.vote = vote
    }
}

/// 投稿画面を閉じると失うものの比べ物（`StoryComposerView.leave`）。
/// 写真は並びの id で見る（画像そのものは比べない——戻した写真は id ごと
/// 作り直すので、外して足し直せば別物になる）。
///
/// **`@MainActor` の型の中に置かない**（テストから呼べなくなる）。
struct StoryComposerContent: Equatable {
    var shotIds: [UUID]
    var overlays: [[TextOverlay]]
    /// 写真ごとの合わせ方。前の呼び手・テストは持たない（どれも合わせていない）
    var framings: [PhotoFraming] = []
    /// 写真ごとの投票（置いていなければ nil）
    var votes: [StoryVoteDraft?] = []
    var caption: String
    var location: String
    var song: Photo.Song?
    var durationSec: Int
    var archive: Bool
    /// 前の版の呼び手・テストは持たない（既定の「許可」）
    var allowReplies: Bool = true
}
