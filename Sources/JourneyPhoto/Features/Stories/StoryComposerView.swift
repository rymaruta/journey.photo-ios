import SwiftUI
import PhotosUI
// UIImage を使う（SwiftUI / PhotosUI から見えることに頼らない）
import UIKit

/// ストーリーを投稿する。24時間で消える。
struct StoryComposerView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var drafts: StoryDraftStore
    @EnvironmentObject private var auth: AuthStore
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
    @State private var showCamera = false
    @State private var isWorking = false
    /// 開いたときの「書きかけの下書き」で「キャンセル（残す）」を選んだか
    @State private var keepExistingDraft = false
    /// ストーリーのBGM（30秒の試聴だけ）と、表示秒数
    @State private var song: Photo.Song?
    @State private var durationSec = StoryService.defaultDurationSec
    @State private var showSongPicker = false
    @State private var message: String?
    /// 曲の札を置けなかったときの一言（`message` とは別。曲を選び直すと消える）
    @State private var songNote: String?
    /// 前に書きかけて閉じたもの。**開いた直後に一度だけ尋ねる**
    @State private var showRestore = false

    // 板 24b「文字と札」の編集
    /// 文字と札を編集している（写真を暗くし、上に札の種類、下に操作欄）
    @State private var textMode = false
    /// 選んでいる札
    @State private var selectedId: UUID?
    /// 編集に入ったときの写し（「やめる」で戻す）と、**どの写真の編集か**。
    /// 編集中に並びが増えて表示中の写真が移っても、戻す先を取り違えない
    @State private var overlaySnapshot: [TextOverlay] = []
    @State private var editingShotId: UUID?
    /// ひとことを打っている（上に「完了」を出す。複数行なので Return では閉じない）
    @FocusState private var captionFocused: Bool
    /// 撮影地を打つ（右の列の「撮影地」）
    @State private var showPlaceEditor = false
    /// 写真を選ぶ画面（「＋」のメニューと、写真が無いときの入口から開く）
    @State private var showLibrary = false
    @State private var placeDraft = ""

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
            topBar
                .padding(.horizontal, 8)
                .padding(.top, 2)
            if textMode {
                VStack(spacing: 8) {
                    kindChips
                    Text(L("指で動かす・2本指で回す", "Drag to move · twist with two fingers to rotate"))
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.muted2)
                }
                .padding(.top, 56)
            }
        }
        // 見出しのバーは使わない（板 24 は写真の上に ✕ と「下書き保存」を重ねる）
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSongPicker) {
            NavigationStack {
                SongPickerView { picked in applySong(picked) }
            }
        }
        .alert(L("撮影地", "Place"), isPresented: $showPlaceEditor) {
            TextField(L("撮影地（任意）", "Place (optional)"), text: $placeDraft)
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
        // 🔴 **送っている間は下へ払っても閉じない**（✕ と同じ。閉じても送信は裏で続く）
        .interactiveDismissDisabled(isWorking)
        // **開いた直後に一度だけ尋ねる。** 黙って書きかけを復元すると、
        // 新しく作りにきた人が前の写真に驚く
        .onAppear {
            drafts.use(userId: auth.userId)
            if drafts.draft != nil, prepared == nil { showRestore = true }
        }
        .alert(L("書きかけの下書きがあります", "You have a saved draft"), isPresented: $showRestore) {
            Button(L("続きから", "Continue")) { restoreDraft() }
            Button(L("捨てる", "Discard"), role: .destructive) { drafts.clear() }
            // 「キャンセル」は**残す**。この回の投稿が成功しても消さない
            Button(Labels.Common.cancel, role: .cancel) { keepExistingDraft = true }
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
    }

    // MARK: - 写真

    /// 写真を画面いっぱいに（下の角だけ半径24）。上下の暗がり、右の道具の列、
    /// 写真の上のひとこと・撮影地（曲は動かせる札）、左下の並び、右下の秒数（板 24）
    private var photoArea: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0x0A / 255.0, green: 0x10 / 255.0, blue: 0x30 / 255.0).opacity(preview == nil ? 0 : 1)
            if let preview {
                StoryCanvas(preview: preview, imageSize: previewSize, overlays: overlays,
                            selectedId: textMode ? selectedId : nil,
                            onTap: { overlay in
                                // 押したら文字と札の編集へ（その札を選んだ状態で）。
                                // **編集中に押したときは写しを取り直さない**（「やめる」の戻り先が変わる）
                                if !textMode { enterTextMode() }
                                selectedId = overlay.id
                            })
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
            if !textMode && preview != nil {
                toolColumn
                    // 送っている間は触らせない（失敗すると並びが詰め直される）
                    .disabled(isWorking)
                    .padding(.trailing, 12)
                    .padding(.top, 120)
            }
        }
        .overlay(alignment: .leading) {
            if !textMode && preview != nil {
                captionBlock
                    .padding(.leading, 36)
                    .padding(.trailing, 70)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !textMode && preview != nil {
                mediaStrip
                    .padding(.leading, 16)
                    .padding(.bottom, 20)
                    // 🔴 **送っている間は並びを変えさせない。** 送信は始めたときの写しを
                    // 回すので、外した写真も出てしまい、失敗時の片付けが範囲外で落ちていた
                    .disabled(isWorking)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !textMode && preview != nil {
                durationMenu
                    .padding(.trailing, 16)
                    .padding(.bottom, 30)
            }
        }
        .overlay(alignment: .bottom) {
            if textMode, let selectedId, selectedIndex != nil {
                OverlayPanel(overlay: overlayBinding(id: selectedId)) {
                    overlays.wrappedValue.removeAll { $0.id == selectedId }
                    self.selectedId = nil
                }
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
            toolButton(symbol: "textformat", label: L("文字と札", "Text and stickers")) { enterTextMode() }
            if song == nil {
                toolButton(symbol: "music.note", label: L("曲を付ける", "Add a song")) { showSongPicker = true }
            } else {
                // 付けた曲は変える・外すを選ぶ（外す口が無かった）
                Menu {
                    Button(L("曲を変える", "Change song")) { showSongPicker = true }
                    Button(L("曲を外す", "Remove song"), role: .destructive) { applySong(nil) }
                } label: {
                    toolIcon("music.note")
                }
                .accessibilityLabel(L("曲", "Song"))
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
                set: { caption = String($0.replacingOccurrences(of: "\n", with: " ").prefix(200)) }
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
                .font(JPFont.mono(11))
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
                Button(L("キャンセル", "Cancel")) {
                    // **入ったときの写真へ戻す**（表示中の写真が移っていても取り違えない）
                    if let id = editingShotId, let i = shots.firstIndex(where: { $0.id == id }) {
                        shots[i].overlays = overlaySnapshot
                    }
                    leaveTextMode()
                }
                .font(.system(size: 16))
                .frame(minHeight: 44)
                .padding(.horizontal, 10)
                Spacer()
                Text(L("文字と札", "Text and stickers"))
                    .font(.system(size: 13))
                    .foregroundStyle(WebTheme.muted2)
                Spacer()
                Button(L("完了", "Done")) {
                    // 空のまま閉じたら置かない（見えない物を焼き込まない）
                    if let id = editingShotId, let i = shots.firstIndex(where: { $0.id == id }) {
                        shots[i].overlays.removeAll { $0.isEmpty }
                    }
                    leaveTextMode()
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(minHeight: 44)
                .padding(.horizontal, 10)
                .accessibilityIdentifier("story.overlay.done")
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)
        } else {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .jpGlass(in: Circle())
                }
                .buttonStyle(.plain)
                // 送っている間は閉じさせない（閉じても送信は裏で続く）
                .disabled(isWorking)
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
                }
                .buttonStyle(.plain)
                .disabled(prepared == nil || isWorking)
                .opacity(prepared == nil ? 0.4 : 1)
                }
            }
        }
    }

    /// 札の種類（文字・撮影地・曲・時刻・日付・タグ）。押すと足して選ぶ
    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TextOverlay.Kind.allCases, id: \.rawValue) { kind in
                    OverlayChip(title: kind.toolLabel, systemImage: kind.toolSymbol) {
                        add(kind: kind)
                    }
                    .disabled(overlays.wrappedValue.count >= TextOverlay.maxCount)
                    .accessibilityIdentifier("story.add.\(kind.rawValue)")
                }
            }
            .padding(.horizontal, 12)
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

            Button {
                Task { await post() }
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().tint(WebTheme.accentText)
                        Text(L("送信中…", "Sending…"))
                    } else {
                        Text(L("ストーリーに投稿", "Post story"))
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WebTheme.accentText)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(WebTheme.accentBackground, in: Capsule())
                .opacity(isWorking || prepared == nil ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isWorking || prepared == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - 文字と札の出入り

    private func enterTextMode() {
        guard shots.indices.contains(current) else { return }
        captionFocused = false
        overlaySnapshot = shots[current].overlays
        editingShotId = shots[current].id
        textMode = true
    }

    private func leaveTextMode() {
        textMode = false
        selectedId = nil
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
        songNote = nil
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
            // 黙って置かないと「曲の札が出ない」と読める。曲はチップで見せている。
            // **写真や投稿の知らせ（`message`）とは別の欄**——投稿の途中失敗の知らせ
            // （何本出たか）を上書きしない
            songNote = L("文字と札がいっぱいなので、曲の札は置けませんでした",
                         "Couldn't add the song sticker — too many stickers on this photo")
            return
        }
        shots[current].overlays.append(sticker)
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
            if !textMode { current = shots.count - 1 }
            self.message = nil
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("写真を読み込めませんでした", "Couldn't load the photo")
        }
    }


    /// 左下の並び（板 24。44×56・選んでいる1枚は白の輪・他は薄く、最後に「＋」）。
    /// **順番がそのまま出る順**。長押しで外せる
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
                    Button(role: .destructive) { remove(at: index) } label: {
                        Label(L("この写真を外す", "Remove this photo"), systemImage: "trash")
                    }
                }
                // 読み上げからも外せる（長押しのメニューは見つけにくい）
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

    /// 1枚外す。**編集中の位置がずれないように直す**
    /// ——直さないと、外した瞬間に別の写真の文字を触ることになる
    private func remove(at index: Int) {
        guard shots.indices.contains(index) else { return }
        shots.remove(at: index)
        current = StoryQueue.currentAfterRemoving(index, current: current, count: shots.count)
    }

    /// 下書きにする。**焼き込む前の文字のまま残す**
    /// ——焼いてしまうと位置も色も直せなくなる（投稿と同じ片道になる）
    private func saveDraft() {
        guard let prepared else { return }
        let ok = drafts.save(
            imageData: prepared.data,
            fileName: prepared.fileName,
            contentType: prepared.contentType,
            coords: prepared.coords,
            caption: caption,
            location: location,
            overlays: shots.indices.contains(current) ? shots[current].overlays : [],
            song: song,
            durationSec: durationSec,
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

    /// 「続きから」。**画像が読めなければ何も戻さない**
    private func restoreDraft() {
        guard let draft = drafts.draft, let data = drafts.imageData() else {
            drafts.clear()
            message = L("下書きの写真を読み込めませんでした", "Couldn't load the draft photo")
            return
        }
        let restored = ImagePreparer.Prepared(data: data, fileName: draft.fileName,
                                              contentType: draft.contentType,
                                              // EXIF は下書きに残していない（ストーリーは送らない）
                                              exif: nil, coords: draft.coords, takenOn: nil)
        // **下書きは1枚だけ**（端末に1件）。戻すときは並びを作り直す
        shots = [StoryShot(prepared: restored, image: UIImage(data: data),
                           overlays: draft.overlays)]
        current = 0
        caption = draft.caption
        location = draft.location
        song = draft.song
        durationSec = draft.durationSec
        message = nil
    }


    /// 出す。**並びの順に、1枚ずつ**。
    ///
    /// 🔴 **途中で失敗したら、そこで止める。** 残りを出し続けると、
    /// 「何本出たのか」が誰にも分からなくなる。出たぶんはそのまま残し
    /// （消しに行かない——消す方が失敗したときに二重に分からなくなる）、
    /// **何枚出て何枚残ったか**を画面に出す。
    private func post() async {
        // 🔴 **二度押しで二重に出さない。** ボタンの `.disabled(isWorking)` は
        // 次の描画まで効かないので、素早く2回押すと `post()` が2本走り、
        // 同じストーリーが2本出ていた（2026-09-25 owner「2重投稿」）。
        // ここは主アクタの上で `await` より前なので、2本目は必ず止まる
        guard !isWorking, !shots.isEmpty else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        var posted = 0
        var postedIds: Set<StoryShot.ID> = []
        for shot in shots {
            do {
                _ = try await environment.stories.create(
                    // **焼き込んでから送る。** 文字が無ければ元のデータを
                    // そのまま渡す（読み書きの往復で画質を落とさない）
                    imageData: TextOverlayRenderer.burn(shot.overlays, into: shot.prepared.data),
                    caption: caption,
                    location: place,
                    coords: shot.prepared.coords,
                    song: song,
                    durationSec: durationSec,
                    archive: keepInArchive
                )
                posted += 1
                postedIds.insert(shot.id)
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? L("投稿できませんでした", "Couldn't post")
                message = StoryQueue.partialFailure(posted: posted, total: shots.count, reason: reason)
                // **出せたぶんは並びから外す。** 押し直したときに
                // 同じ写真をもう一度出さないため
                // **数ではなく id で外す**——並びが変わっていると
                // `removeFirst(posted)` は範囲外で落ちる
                shots = StoryQueue.dropPosted(shots, posted: postedIds)
                current = 0
                return
            }
        }
        // 出したら下書きは要らない（残すと次に開いたときにまた尋ねる）。
        // 🔴 **ただし復元を保留した古い下書きは消さない**——この回の投稿とは別物で、
        // 「残す」を選んだのに黙って消えていた
        if !keepExistingDraft { drafts.clear() }
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

    init(prepared: ImagePreparer.Prepared, image: UIImage?, overlays: [TextOverlay] = []) {
        self.prepared = prepared
        self.preview = image.map { Image(uiImage: $0) }
        self.imageSize = image?.size
        self.overlays = overlays
    }
}
