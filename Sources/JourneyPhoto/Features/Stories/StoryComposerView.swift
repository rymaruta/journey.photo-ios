import SwiftUI
import PhotosUI
// UIImage を使う（SwiftUI / PhotosUI から見えることに頼らない）
import UIKit

/// ストーリーを投稿する。24時間で消える。
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
    @State private var location = ""
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

    // 板 24b「文字と札」の編集
    /// 文字と札を編集している（写真を暗くし、上に札の種類、下に操作欄）
    @State private var textMode = false
    /// 選んでいる札
    @State private var selectedId: UUID?
    /// **写真の上で直接打っている札**（`StoryTextTypingView`）。nil なら打っていない。
    /// 「文字と札」の中からも外からも開く（owner・2026-09-30「使いづらい」）
    @State private var typingId: UUID?
    /// 打っている札が載っている写真。**写真の読み込みで表示中の写真が移っても、打つ先を取り違えない**
    /// （移った先には札が無く、打った字が消え、元の写真に見えない空の札が残った・4ffb74f のレビュー）
    @State private var typingShotId: UUID?
    /// 写真の枠の大きさ（**キーボードで縮む前**）。打つ画面の文字を焼き込みと同じ大きさで見せる
    @State private var canvasSize: CGSize = .zero
    /// 打ち始めた瞬間の `canvasSize`（打っている間はキーボードで枠が縮むので、こちらで測る）
    @State private var typingCanvas: CGSize = .zero
    /// 札を指で動かしている最中（周りの道具を隠し、下のゴミ箱を見せる）
    @State private var draggingOverlay = false
    /// 投票の札を選んでいる（札の `selectedId` とはどちらか一方）
    @State private var voteSelected = false
    /// 編集に入ったときの投票（「キャンセル」で戻す）
    @State private var voteSnapshot: StoryVoteDraft?
    /// スタンプ（絵文字）の列を開いているか
    @State private var showStamps = false
    /// 編集に入ったときの写し（「やめる」で戻す）と、**どの写真の編集か**。
    /// 編集中に並びが増えて表示中の写真が移っても、戻す先を取り違えない
    @State private var overlaySnapshot: [TextOverlay] = []
    /// 編集に入ったときの写真の合わせ方（「キャンセル」で戻す。編集中も札を選んでいなければ
    /// 写真を合わせられる——写真を押すと選んでいる札が外れる）
    @State private var framingSnapshot: PhotoFraming = .identity
    @State private var editingShotId: UUID?
    /// ひとことを打っている（上に「完了」を出す。複数行なので Return では閉じない）
    @FocusState private var captionFocused: Bool
    /// 撮影地を打つ（右の列の「撮影地」）
    @State private var showPlaceEditor = false
    /// 写真を選ぶ画面（「＋」のメニューと、写真が無いときの入口から開く）
    @State private var showLibrary = false
    @State private var placeDraft = ""
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
                        caption: caption, location: location, song: song,
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
            VStack(spacing: 0) {
                photoArea
                    .ignoresSafeArea(edges: .top)
                if !textMode {
                    footer
                }
            }
            // 打っている間は後ろを読ませない（VoiceOver で投稿・他の札へ移れた）
            .accessibilityHidden(typingId != nil)
            if typingId == nil {
                topBar
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
            if textMode && typingId == nil {
                VStack(spacing: 8) {
                    kindChips
                    Text(L("指で動かす・2本指で回す・つまんで大きさを変える", "Drag to move · twist to rotate · pinch to resize"))
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.muted2)
                }
                .padding(.top, 56)
            }
            // 写真の上で直接打つ（開いたらすぐキーボード）
            if let typingId {
                StoryTextTypingView(overlay: typingBinding(id: typingId),
                                    photoShortSide: photoShortSide,
                                    canvas: typingCanvas,
                                    photo: TextOverlay.filledRect(
                                        image: shots.first { $0.id == typingShotId }?.imageSize ?? typingCanvas,
                                        in: typingCanvas)) { finishTyping() }
            }
        }
        // 見出しのバーは使わない（板 24 は写真の上に ✕ と「下書き保存」を重ねる）
        .toolbar(.hidden, for: .navigationBar)
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
        .alert(L("撮影地", "Place"), isPresented: $showPlaceEditor) {
            // サーバーが 200 で切る（`sanitizeText(location, 200)`）。画面で止める
            TextField(L("撮影地（任意）", "Place (optional)"), text: Binding(
                get: { placeDraft },
                set: { placeDraft = PostLimits.limited(old: placeDraft, new: $0, limit: PostLimits.location) }))
            Button(L("決める", "Set")) { location = placeDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !location.isEmpty {
                Button(L("外す", "Remove"), role: .destructive) { location = "" }
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
            CameraPicker { data in accept(data) }
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
        .unsavedCloseGuard(leave, isPresented: $showLeaveConfirm,
                           title: canSaveDraft ? L("下書きに保存しますか？", "Save as a draft?")
                                               : L("閉じますか？", "Close?"),
                           canSave: canSaveDraft,
                           saveTitle: L("下書きに保存", "Save draft"),
                           discardTitle: restoredContent != nil ? L("変更を捨てる", "Discard changes")
                                                                : L("捨てる", "Discard"),
                           message: !canSaveDraft
                               ? L("選んだ写真と置いた文字は消えます。前の下書きはそのまま残ります（下書きは1件だけです）。",
                                   "The photos and text you added will be lost. Your earlier draft stays (only one draft is kept).")
                               : restoredContent != nil
                               ? L("閉じると、下書きを開いてからの変更は消えます（前の下書きは残ります）。",
                                   "If you close now, your changes since opening the draft will be lost. The draft itself stays.")
                               : L("閉じると、選んだ写真と置いた文字は消えます。下書きはこの端末にだけ残ります。",
                                   "If you close now, the photos and text you added will be lost. Drafts stay on this device only."),
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
                            selectedId: textMode ? selectedId : nil,
                            // 打っている札は打つ画面の真ん中に出す（写真の上に二重に出さない）
                            hiddenId: typingShotId == shots[current].id ? typingId : nil,
                            onTap: { overlay in
                                // **打ち直せる札（文字・撮影地・タグ・曲）は、押したらすぐ打つ画面へ**
                                if StoryTextEditing.opensTyping(overlay) {
                                    startTyping(overlay.id)
                                    return
                                }
                                // 押したら文字と札の編集へ（その札を選んだ状態で）。
                                // **編集中に押したときは写しを取り直さない**（「やめる」の戻り先が変わる）
                                if !textMode { enterTextMode() }
                                selectedId = overlay.id
                                voteSelected = false
                            },
                            // 写真を押したら選んでいる札を外す（写真を合わせられるように戻る）
                            onTapPhoto: { if textMode { selectedId = nil; voteSelected = false } },
                            // ゴミ箱へ運んで離した（VoiceOver の「消す」も）。**表示中の写真の札**
                            onDelete: { id in
                                overlays.wrappedValue.removeAll { $0.id == id }
                                if selectedId == id { selectedId = nil }
                            },
                            onDraggingChange: { draggingOverlay = $0 },
                            vote: vote,
                            voteSelected: textMode && voteSelected,
                            onTapVote: {
                                if !textMode { enterTextMode() }
                                selectedId = nil
                                voteSelected = true
                            },
                            photoId: shots.indices.contains(current) ? shots[current].id : nil)
            } else {
                emptyPhoto
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
        // 文字と札の編集中は写真を30%暗くする（板 24b）
        .overlay {
            if textMode {
                Color.black.opacity(0.3).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !textMode && typingId == nil && preview != nil {
                toolColumn
                    .padding(.trailing, 12)
                    .padding(.top, 120)
                    // 札を動かしている間は**隠すだけ**（消すと、打っている欄が外れてキーボードが閉じ、
                    // 枠が伸びて札が指から外れた・81cbd07 のレビュー）
                    .opacity(draggingOverlay ? 0 : 1)
                    .allowsHitTesting(!draggingOverlay)
                .accessibilityHidden(draggingOverlay)
                    .accessibilityHidden(draggingOverlay)
            }
        }
        .overlay(alignment: .leading) {
            if !textMode && typingId == nil && preview != nil {
                captionBlock
                    .padding(.leading, 36)
                    .padding(.trailing, 70)
                    // 札を動かしている間は**隠すだけ**（消すと、打っている欄が外れてキーボードが閉じ、
                    // 枠が伸びて札が指から外れた・81cbd07 のレビュー）
                    .opacity(draggingOverlay ? 0 : 1)
                    .allowsHitTesting(!draggingOverlay)
                .accessibilityHidden(draggingOverlay)
                    .accessibilityHidden(draggingOverlay)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !textMode && typingId == nil && preview != nil {
                mediaStrip
                    .padding(.leading, 16)
                    .padding(.bottom, 20)
                    // 札を動かしている間は**隠すだけ**（消すと、打っている欄が外れてキーボードが閉じ、
                    // 枠が伸びて札が指から外れた・81cbd07 のレビュー）
                    .opacity(draggingOverlay ? 0 : 1)
                    .allowsHitTesting(!draggingOverlay)
                .accessibilityHidden(draggingOverlay)
                    .accessibilityHidden(draggingOverlay)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !textMode && typingId == nil && preview != nil {
                durationMenu
                    .padding(.trailing, 16)
                    .padding(.bottom, 30)
                    // 札を動かしている間は**隠すだけ**（消すと、打っている欄が外れてキーボードが閉じ、
                    // 枠が伸びて札が指から外れた・81cbd07 のレビュー）
                    .opacity(draggingOverlay ? 0 : 1)
                    .allowsHitTesting(!draggingOverlay)
                .accessibilityHidden(draggingOverlay)
                    .accessibilityHidden(draggingOverlay)
            }
        }
        .overlay(alignment: .bottom) {
            if textMode, voteSelected, vote.wrappedValue != nil {
                VotePanel(vote: Binding(
                    get: { vote.wrappedValue ?? .new() },
                    set: { vote.wrappedValue = $0 }
                )) {
                    vote.wrappedValue = nil
                    voteSelected = false
                }
            } else if textMode, let selectedId, selectedIndex != nil {
                OverlayPanel(overlay: overlayBinding(id: selectedId)) {
                    overlays.wrappedValue.removeAll { $0.id == selectedId }
                    self.selectedId = nil
                }
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
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: textMode ? 0 : 24,
                                          bottomTrailingRadius: textMode ? 0 : 24))
    }

    /// まだ1枚も選んでいないとき。**写真の道具だけを真ん中に**
    private var emptyPhoto: some View {
        VStack(spacing: 14) {
            Text(L("写真を選ぶ", "Choose a photo"))
                .font(JPFont.display(26, relativeTo: .title))
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                Button { showLibrary = true } label: {
                    glassPill(L("ライブラリ", "Library"), systemImage: "photo")
                }
                .buttonStyle(.plain)
                if CameraPicker.isAvailable {
                    Button { showCamera = true } label: {
                        glassPill(L("カメラ", "Camera"), systemImage: "camera")
                    }
                    .buttonStyle(.plain)
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(WebTheme.muted2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 右の縦の列（文字と札・曲・撮影地・表示秒数。44のガラスの丸）
    private var toolColumn: some View {
        VStack(spacing: 10) {
            // 「Aa」は**押したらすぐ打つ**（以前は「文字と札」→「文字」→下の欄、の3段だった）
            toolButton(symbol: "textformat", label: L("文字を入れる", "Add text")) { startNewText() }
            toolButton(symbol: "face.smiling", label: L("札とスタンプ", "Stickers")) { enterTextMode() }
            if song == nil {
                toolButton(symbol: "music.note", label: L("曲を付ける", "Add a song")) { showSongPicker = true }
            } else {
                // 付けた曲は変える・外すを選ぶ（外す口が無かった）
                Menu {
                    Button(L("曲を変える", "Change song")) { showSongPicker = true }
                    // 流し始め（Web の「好きな部分」と同じ `startSec`）。いまの位置をメニューに出す
                    Button(L("流し始め（\(Photo.Song.startLabel(song?.startSec))）",
                             "Start point (\(Photo.Song.startLabel(song?.startSec)))")) { showSongStart = true }
                    Button(L("曲を外す", "Remove song"), role: .destructive) { applySong(nil) }
                } label: {
                    toolIcon("music.note")
                }
                .accessibilityLabel(L("曲", "Song"))
            }
            // 写真を拡大・移動・回転したら、元へ戻す口（写真を2回押しても戻る）
            if !framing.wrappedValue.isIdentity {
                toolButton(symbol: "arrow.counterclockwise", label: L("写真の合わせ方を戻す", "Reset photo framing")) {
                    framing.wrappedValue = .identity
                }
            }
            toolButton(symbol: "mappin", label: L("撮影地", "Place")) {
                placeDraft = location
                showPlaceEditor = true
            }
            // 表示秒数は右下の札から選ぶ（ここは同じ札を開く入口）
            Menu {
                durationOptions
            } label: {
                toolIcon("timer")
            }
            .accessibilityLabel(L("表示秒数", "Duration"))
        }
    }

    private func toolButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolIcon(symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func toolIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .jpGlass(in: Circle())
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
            if !location.isEmpty {
                photoChip(symbol: "mappin", text: location)
            }
            // **曲が付いていることは必ず見せる。** 札はいまの1枚にしか置かないので、
            // 札を消した・別の写真に切り替えた・札が上限で置けなかったときに、
            // 曲が付いているのに画面から何も分からなくなる
            if let song, !currentHasSongSticker, let text = SongSticker.text(for: song) {
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
            Image(systemName: symbol).font(.system(size: 12))
            Text(text).font(.system(size: 12)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .jpGlass(in: Capsule(), border: 0)
    }

    /// 右下の「表示 5 秒」（等幅・ガラスの札）。押すと 3〜15秒から選ぶ
    private var durationMenu: some View {
        Menu {
            durationOptions
        } label: {
            Text(L("表示 \(durationSec) 秒", "\(durationSec)s"))
                .font(JPFont.mono(12))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .jpGlass(in: Capsule(), border: 0)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L("表示 \(durationSec) 秒", "\(durationSec) seconds"))
    }

    /// 3〜15秒（3秒未満は読み切れず、15秒を超えると見る側が飽きる。Web と同じ範囲）
    @ViewBuilder
    private var durationOptions: some View {
        ForEach(Array(StoryService.durationRange), id: \.self) { sec in
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

    @ViewBuilder
    private var topBar: some View {
        if textMode {
            // 板 24b: キャンセル／文字と札／完了（owner: 「やめる・できた」は幼い）
            HStack {
                Button {
                    // **入ったときの写真へ戻す**（表示中の写真が移っていても取り違えない）
                    if let id = editingShotId, let i = shots.firstIndex(where: { $0.id == id }) {
                        shots[i].overlays = overlaySnapshot
                        shots[i].framing = framingSnapshot
                        shots[i].vote = voteSnapshot
                    }
                    leaveTextMode()
                } label: {
                    // 44 と余白は label の中に置き、`contentShape` で枠ごと押せる所にする
                    // （`.plain` は描いた字しか押せない）
                    Text(L("キャンセル", "Cancel"))
                        .font(.system(size: 16))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                Spacer()
                Text(L("文字と札", "Text and stickers"))
                    .font(.system(size: 13))
                    .foregroundStyle(WebTheme.muted2)
                Spacer()
                Button {
                    // 空のまま閉じたら置かない（見えない物を焼き込まない）
                    if let id = editingShotId, let i = shots.firstIndex(where: { $0.id == id }) {
                        shots[i].overlays.removeAll { $0.isEmpty }
                    }
                    leaveTextMode()
                } label: {
                    Text(L("完了", "Done"))
                        .font(.system(size: 16, weight: .semibold))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("story.overlay.done")
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)
        } else {
            HStack {
                Button {
                    switch leave {
                    case .now: dismiss()
                    case .confirm: showLeaveConfirm = true
                    case .wait: break
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .jpGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(leave == .wait)
                .accessibilityLabel(Labels.Common.close)
                Spacer()
                if captionFocused {
                    // ひとことのキーボードを閉じる（複数行なので Return では閉じない）
                    Button { captionFocused = false } label: {
                        Text(L("完了", "Done"))
                            .font(.system(size: 13, weight: .semibold))
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
                // **写真が無ければ下書きにできない。** 文字だけ残しても
                // 「続きから」で出すものが無い
                Button { saveDraft() } label: {
                    Text(L("下書き保存", "Save draft"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .jpGlass(in: Capsule())
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(prepared == nil || !canSaveDraft)
                .opacity(prepared == nil ? 0.4 : 1)
                }
            }
        }
    }

    /// 札の種類（文字・撮影地・曲・時刻・日付・タグ・スタンプ）。押すと足して選ぶ。
    /// **スタンプだけは押すと絵文字の列を開く**（どれを置くか選ぶ）
    private var kindChips: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // 投票（写真1枚に1つ・焼き込まずに送る）。置いてあれば選び直すだけ
                    OverlayChip(title: L("投票", "Poll"), systemImage: "chart.bar.xaxis",
                                selected: voteSelected) {
                        if vote.wrappedValue == nil { vote.wrappedValue = .new() }
                        selectedId = nil
                        voteSelected = true
                        showStamps = false
                    }
                    .accessibilityIdentifier("story.add.vote")
                    ForEach(TextOverlay.Kind.allCases, id: \.rawValue) { kind in
                        OverlayChip(title: kind.toolLabel, systemImage: kind.toolSymbol,
                                    selected: kind == .stamp && showStamps) {
                            if kind == .stamp {
                                showStamps.toggle()
                            } else if kind == .text {
                                // 文字は足したらすぐ打つ画面へ
                                showStamps = false
                                startNewText()
                            } else {
                                add(kind: kind)
                            }
                        }
                        // スタンプは列を開け閉めするだけなので上限でも押せる（閉じられなくなる）
                        .disabled(kind != .stamp && overlays.wrappedValue.count >= TextOverlay.maxCount)
                        .accessibilityIdentifier("story.add.\(kind.rawValue)")
                    }
                }
                .padding(.horizontal, 12)
            }
            if showStamps {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(TextOverlay.stamps, id: \.self) { emoji in
                            Button {
                                addStamp(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 28))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(overlays.wrappedValue.count >= TextOverlay.maxCount)
                            .accessibilityLabel(L("スタンプ \(emoji)", "Sticker \(emoji)"))
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    // MARK: - 足元

    /// 「フォロワーが見られます」・自分用に残す・投稿ボタン（板 24）
    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message, prepared != nil {
                Text(message).font(.footnote).foregroundStyle(WebTheme.muted2)
            }
            if let songNote, prepared != nil {
                Text(songNote).font(.footnote).foregroundStyle(WebTheme.muted2)
            }
            HStack(spacing: 8) {
                // 🔴 **ストーリーはフォロワーだけが見る**（2026-09-22・owner の
                // 判断。`api-user/src/storyVisibility.ts`）。選ぶ口は置かない
                Image(systemName: "eye").font(.system(size: 14))
                Text(L("フォロワーが見られます", "Your followers can see it"))
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                // 24時間のあとも残すか。**ハイライトに入れられるのは残したものだけ**
                // （`api-user/src/highlights.ts`）。既定は残さない——消えることが
                // ストーリーの約束なので、残す方を選ばせる
                Toggle(isOn: $keepInArchive) {
                    Text(L("自分用に残す", "Keep for me"))
                        .font(.system(size: 13))
                }
                .fixedSize()
                // **軌道は暗い真鍮。** 既定（白）だと白い軌道に白いつまみが乗る
                .tint(WebTheme.accentDeep)
            }
            .foregroundStyle(WebTheme.muted2)
            // 返信を受けるか（Web の「返信を許可」）。切ると見る人に返信欄と ♡ が出ない
            // （サーバーも断る）。既定は入
            HStack(spacing: 8) {
                Spacer(minLength: 8)
                Toggle(isOn: $allowReplies) {
                    Text(L("返信を許可", "Allow replies"))
                        .font(.system(size: 13))
                }
                .fixedSize()
                .tint(WebTheme.accentDeep)
            }
            .foregroundStyle(WebTheme.muted2)

            Button {
                post()
            } label: {
                // 押したら画面を閉じる。**送信中は自分の輪に出る**（板 27）
                Text(L("ストーリーに投稿", "Post story"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WebTheme.accentText)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(WebTheme.accentBackground, in: Capsule())
                .opacity(prepared == nil ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(prepared == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - 文字と札の出入り

    private func enterTextMode() {
        guard shots.indices.contains(current) else { return }
        captionFocused = false
        overlaySnapshot = shots[current].overlays
        framingSnapshot = shots[current].framing
        voteSnapshot = shots[current].vote
        editingShotId = shots[current].id
        textMode = true
    }

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

    /// いま表示中の写真の札を打ち始める。**打つ先の写真を覚える**
    private func startTyping(_ id: UUID) {
        guard shots.indices.contains(current) else { return }
        // 別の札を打っている最中に呼ばれたら（VoiceOver など）、前の札を先に確定する
        if typingId != nil { finishTyping() }
        captionFocused = false
        selectedId = nil
        voteSelected = false
        // キーボードが出る前の枠で文字の大きさを決める（`photoShortSide`）
        typingCanvas = canvasSize
        typingShotId = shots[current].id
        typingId = id
    }

    /// 打ち終えた。**空なら置かない**（新しく足した札も、打ち直して消した札も）。
    /// 片付ける先は**打ち始めた写真**（表示中の写真ではない）
    private func finishTyping() {
        if let id = typingId, let shotId = typingShotId,
           let i = shots.firstIndex(where: { $0.id == shotId }) {
            shots[i].overlays = StoryTextEditing.finish(shots[i].overlays, id: id)
        }
        typingId = nil
        typingShotId = nil
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
    /// 「文字と札」に入るとフッターが消えて枠が高くなり、その値に張り付いて、打つ画面の文字が
    /// 置いたあとより2割ほど大きく見えた（4ffb74f のレビュー）。キーボードの分は、打ち始めた瞬間の
    /// 枠を `typingCanvas` に写して避ける（キーボードは打ち始めた後に出る）
    private func rememberCanvas(_ size: CGSize) {
        // ひとことのキーボードで縮んだ枠は覚えない（そのまま「Aa」を押すと、縮んだ枠で大きさを決める）
        guard !captionFocused else { return }
        canvasSize = size
    }

    private func leaveTextMode() {
        textMode = false
        showStamps = false
        selectedId = nil
        voteSelected = false
        editingShotId = nil
    }

    private var selectedIndex: Int? {
        guard let selectedId else { return nil }
        return overlays.wrappedValue.firstIndex { $0.id == selectedId }
    }

    /// 選んだ札への窓。**位置ではなく id で引く**（消した直後に変換中の文字が
    /// 確定して書き込みが走っても、隣の札を書き換えない）
    private func overlayBinding(id: UUID) -> Binding<TextOverlay> {
        Binding(
            get: { overlays.wrappedValue.first { $0.id == id } ?? TextOverlay(text: "") },
            set: { value in
                var list = overlays.wrappedValue
                if let i = list.firstIndex(where: { $0.id == id }) { list[i] = value; overlays.wrappedValue = list }
            }
        )
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

    /// スタンプを置く。**文字より大きく、真ん中に**（どこに置いたか分かるように）
    private func addStamp(_ emoji: String) {
        guard overlays.wrappedValue.count < TextOverlay.maxCount else { return }
        let overlay = TextOverlay(text: emoji, x: 0.5, y: 0.5, size: TextOverlay.stampSize, kind: .stamp)
        overlays.wrappedValue.append(overlay)
        selectedId = overlay.id
        voteSelected = false
        // 置いたら列を閉じる。開いたままだと写真の上の方を覆い、そこの札を掴めない
        showStamps = false
    }

    private func add(kind: TextOverlay.Kind) {
        // **真ん中より少し上に置く。** 真ん中だと写真の主役に重なりやすい。
        // 場所と曲は少し下（文字の札と重なりにくい）
        let y = kind == .text ? 0.35 : 0.6
        // 新しい文字は明朝から（板 24b の既定の選択）。札（撮影地・曲など）はゴシックの帯
        let overlay = TextOverlay(text: kind.initialText(), x: 0.5, y: y, kind: kind,
                                  face: kind == .text ? .mincho : .gothic)
        overlays.wrappedValue.append(overlay)
        selectedId = overlay.id
        // 投票を選んでいたら外す（下の欄が投票のまま残り、足した文字を直せなかった）
        voteSelected = false
    }

    // MARK: - 共通

    private func glassPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .jpGlass(in: Capsule())
    }

    /// 選ばれたぶんを順に足す。**1枚も読めなかったときだけ断りを出す**
    /// ——何枚か読めた回に「読み込めませんでした」だけ出すと、
    /// 並んでいるものが見えているのに失敗したように読める。
    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var failed = 0
        for item in items {
            let data = try? await item.loadTransferable(type: Data.self)
            if let data {
                accept(data)
            } else {
                failed += 1
            }
        }
        if failed > 0 {
            message = failed == items.count
                ? L("写真を読み込めませんでした", "Couldn't load the photos")
                : L("\(failed)枚を読み込めませんでした", "Couldn't load \(failed) of them")
        }
        // **選び終えたら空にする。** 残すと、次に同じ写真を選んでも
        // `onChange` が動かない（同じ値なので知らせが来ない）
        pickerItems = []
    }

    /// 1枚受け取る。**足す**（選び直しではない）。
    ///
    /// 文字は写真ごとに持つので、足した写真には何も付いていない状態で
    /// 始まる——前の写真の文字が別の絵に残ると、置いた場所の意味が変わる。
    private func accept(_ data: Data) {
        do {
            let prepared = try ImagePreparer.prepare(data: data, fileName: "story")
            guard shots.count < StoryQueue.maxShots else {
                message = L("一度に出せるのは\(StoryQueue.maxShots)枚までです",
                            "You can post up to \(StoryQueue.maxShots) at once")
                return
            }
            let shot = StoryShot(prepared: prepared, image: UIImage(data: prepared.data))
            shots.append(shot)
            // 足したらそれを編集する（選んだ直後に文字を置ける）。
            // **文字と札の編集中は移らない**（編集している写真が入れ替わる）
            // **打っている間も移らない**（打つ先は `typingShotId` で引くが、見えている写真と打っている
            // 写真が違うと、完了した後に別の写真が出て驚く）
            if !textMode && typingId == nil { current = shots.count - 1 }
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
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 56)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .accessibilityLabel(L("写真を追加", "Add a photo"))
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
        guard shots.indices.contains(index) else { return }
        shots.remove(at: index)
        current = StoryQueue.currentAfterRemoving(index, current: current, count: shots.count)
    }

    /// 下書きにする。**焼き込む前の文字のまま残す**
    /// ——焼いてしまうと位置も色も直せなくなる（投稿と同じ片道になる）。
    /// **並べた写真を全部残す。** 以前は表示中の1枚だけを渡していて、
    /// 3枚並べて保存しても開き直すと1枚になっていた
    private func saveDraft() {
        guard !shots.isEmpty else { return }
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
            location: location,
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
        location = draft.location
        // 流し始めは表示秒数に収めてから戻す（`restoredContent` もその値で撮る）。
        // 収まっていない下書きをそのまま戻すと、表示秒数が変わらない回は上限を越えたまま
        // 送られ、変わる回は何も触らずに閉じても「変更あり」になった（c15a415 のレビュー）
        song = draft.song?.fitting(window: draft.durationSec)
        durationSec = draft.durationSec
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
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        // **焼き込んでから渡す。** 文字が無ければ元のデータをそのまま渡す
        // （読み書きの往復で画質を落とさない）
        // 撮影地は全部で1つなので、基準の写真から遠い写真の座標は送らない（`StoryQueue.coordsToSend`）
        let coords = StoryQueue.coordsToSend(shots.map(\.prepared.coords))
        let jobs = zip(shots, coords).map { shot, shotCoords in
            StoryUploadCenter.Job(
                imageData: TextOverlayRenderer.burn(shot.overlays, framing: shot.framing, into: shot.prepared.data),
                caption: caption, location: place, coords: shotCoords,
                song: song, durationSec: durationSec, archive: keepInArchive,
                allowReplies: allowReplies,
                texts: StoryPostText.list(vote: shot.vote, caption: caption))
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
