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

    @State private var pickerItem: PhotosPickerItem?
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
    /// ストーリーのBGM（30秒の試聴だけ）と、表示秒数
    @State private var song: Photo.Song?
    @State private var durationSec = StoryService.defaultDurationSec
    @State private var showSongPicker = false
    @State private var message: String?
    /// 前に書きかけて閉じたもの。**開いた直後に一度だけ尋ねる**
    @State private var showRestore = false
    /// 公開範囲（モック4-7）。**サーバーが守れるものだけ出す**

    /// いま編集している写真。**無ければ nil**（まだ1枚も選んでいない）
    private var prepared: ImagePreparer.Prepared? {
        shots.indices.contains(current) ? shots[current].prepared : nil
    }

    private var preview: Image? {
        shots.indices.contains(current) ? shots[current].preview : nil
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
        Form {
            Section {
                if let preview {
                    // **写真の上を直接つまんで文字を置く。**
                    // 入力欄で座標を打たせない。道具は1列に並べる（モック4-6）
                    TextOverlayEditor(preview: preview, overlays: overlays) {
                        photoTools
                    }
                    // 2枚以上あるときだけ並びを出す（1枚のときは邪魔なだけ）
                    if shots.count > 1 { mediaStrip }
                } else {
                    // まだ1枚も選んでいないときは、写真の道具だけ
                    HStack(spacing: 10) { photoTools }
                }
            } footer: {
                Text(L("ストーリーは24時間で消えます。撮影情報（EXIF）は端末で取り除いてから送ります。", "Stories disappear after 24 hours. Photo metadata is removed on your device."))
            }
            .listRowBackground(Color.clear)

            Section {
                TextField(L("ひとこと", "Caption"), text: $caption)
                TextField(L("撮影地（任意）", "Place (optional)"), text: $location)
            } footer: {
                // 座標は地名とセットのときだけ送る（名前の無い点は画面に出しようがない）
                Text(L("撮影地を入れると、写真に残っていた位置（約1kmに丸めたもの）も一緒に送ります。", "Adding a place also sends the photo's rounded coordinates (about 1 km)."))
            }
            .listRowBackground(Color.clear)

            // **`Section(_:content:footer:)` は本物の SwiftUI に無い**
            // （題付きは `init(_:content:)` だけ）。header / footer で書く
            Section {
                if let song {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.callout)
                            if let artist = song.artist, !artist.isEmpty {
                                Text(artist).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(L("外す", "Remove")) { self.song = nil }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                } else {
                    Button { showSongPicker = true } label: {
                        Label(L("曲を付ける", "Add a song"), systemImage: "music.note")
                    }
                }
                Stepper(value: $durationSec, in: StoryService.durationRange) {
                    Text(L("表示 \(durationSec) 秒", "\(durationSec) seconds"))
                }
            } header: {
                Text(L("音と長さ", "Sound and length"))
            } footer: {
                // 3秒未満は読み切れず、15秒を超えると見る側が飽きる（Web と同じ範囲）
                Text(L("3〜15秒。曲は30秒の試聴だけを使います。",
                       "3–15 seconds. Songs use the 30-second preview only."))
            }
            .listRowBackground(Color.clear)

            // 24時間のあとも残すか。**ハイライトに入れられるのは残したものだけ**
            // （`api-user/src/highlights.ts`）。既定は残さない——消えることが
            // ストーリーの約束なので、残す方を選ばせる
            Section {
                Toggle(isOn: $keepInArchive) {
                    Label(L("24時間のあとも自分用に残す", "Keep it for myself after 24 hours"),
                          systemImage: "archivebox")
                        .font(.subheadline)
                }
            } footer: {
                Text(L("残すと、消えたあとも自分だけが見られます。ハイライトに入れられるのは残したものだけです。",
                       "Kept stories stay visible to you alone, and only kept stories can go into a highlight."))
            }
            .listRowBackground(Color.clear)

            // 🔴 **ストーリーはフォロワーだけが見る**（2026-09-22・owner の
            // 判断。`api-user/src/storyVisibility.ts`）。選択そのものが
            // 無くなったので、**選ばせない**——サーバーが読まない値を
            // 選ばせると、押しても効かない切り替えになる。
            // 代わりに「誰に届くか」を1行で言う
            Section {
                Label(L("フォロワーが見られます", "Your followers can see it"),
                      systemImage: "person.2")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
            } footer: {
                Text(L("ストーリーは24時間で消えます。フォローしていない人には届きません。",
                       "Stories vanish after 24 hours. People who don't follow you won't see them."))
            }
            .listRowBackground(Color.clear)

            if let message {
                Section { Text(message).font(.callout) }
            }

            Section {
                Button {
                    Task { await post() }
                } label: {
                    if isWorking {
                        HStack { ProgressView(); Text(L("送信中…", "Sending…")) }
                    } else {
                        Text(L("ストーリーに投稿", "Post story"))
                    }
                }
                .disabled(isWorking || prepared == nil)
            }
            .listRowBackground(Color.clear)
        }
        .webScreen()
        .sheet(isPresented: $showSongPicker) {
            NavigationStack {
                SongPickerView { picked in song = picked }
            }
        }
        .navigationTitle(L("ストーリー", "Story"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Labels.Common.close) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // **写真が無ければ下書きにできない。** 文字だけ残しても
                // 「続きから」で出すものが無い
                Button(L("下書き保存", "Save draft")) { saveDraft() }
                    .disabled(prepared == nil || isWorking)
            }
        }
        // **開いた直後に一度だけ尋ねる。** 黙って書きかけを復元すると、
        // 新しく作りにきた人が前の写真に驚く
        .onAppear {
            drafts.use(userId: auth.userId)
            if drafts.draft != nil, prepared == nil { showRestore = true }
        }
        .alert(L("書きかけの下書きがあります", "You have a saved draft"), isPresented: $showRestore) {
            Button(L("続きから", "Continue")) { restoreDraft() }
            Button(L("捨てる", "Discard"), role: .destructive) { drafts.clear() }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("この端末に残しておいたものです。続きから編集できます。",
                   "Kept on this device. You can pick up where you left off."))
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in accept(data) }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            Task { await load(item) }
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let data = try? await item.loadTransferable(type: Data.self)
        guard let data else {
            message = L("写真を読み込めませんでした", "Couldn't load the photo")
            return
        }
        accept(data)
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
            let shot = StoryShot(prepared: prepared,
                                 preview: UIImage(data: prepared.data).map { Image(uiImage: $0) })
            shots.append(shot)
            // 足したらそれを編集する（選んだ直後に文字を置ける）
            current = shots.count - 1
            self.message = nil
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("写真を読み込めませんでした", "Couldn't load the photo")
        }
    }


    /// 並び（モック4-5）。**順番がそのまま出る順**。
    private var mediaStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                    Button {
                        current = index
                    } label: {
                        thumb(shot, index: index)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func thumb(_ shot: StoryShot, index: Int) -> some View {
        let isCurrent = index == current
        return Group {
            if let preview = shot.preview {
                preview.resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: 56, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isCurrent ? AnyShapeStyle(WebTheme.accentBackground)
                                    : AnyShapeStyle(Color.white.opacity(0.15)),
                          lineWidth: isCurrent ? 2 : 1))
        .overlay(alignment: .topLeading) {
            // **何番目に出るか**を出す（並びが出る順そのものなので）
            Text("\(index + 1)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white)
                .shadow(radius: 2)
                .padding(4)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.white)
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("この写真を外す", "Remove this photo"))
        }
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
        shots = [StoryShot(prepared: restored,
                           preview: UIImage(data: data).map { Image(uiImage: $0) },
                           overlays: draft.overlays)]
        current = 0
        caption = draft.caption
        location = draft.location
        song = draft.song
        durationSec = draft.durationSec
        message = nil
    }


    /// 写真そのものの道具（モック4-6 の「カメラ」「ライブラリ」）。
    /// 文字の道具と同じ見た目・同じ行に並べる
    @ViewBuilder
    private var photoTools: some View {
        if CameraPicker.isAvailable {
            Button { showCamera = true } label: {
                TextOverlayEditor<EmptyView>.toolLabel(L("カメラ", "Camera"), systemImage: "camera")
            }
            .buttonStyle(.plain)
        }
        PhotosPicker(selection: $pickerItem, matching: .images) {
            TextOverlayEditor<EmptyView>.toolLabel(
                shots.isEmpty ? L("ライブラリ", "Library") : L("追加", "Add"),
                systemImage: "photo.badge.plus")
        }
        .buttonStyle(.plain)
    }

    /// 出す。**並びの順に、1枚ずつ**。
    ///
    /// 🔴 **途中で失敗したら、そこで止める。** 残りを出し続けると、
    /// 「何本出たのか」が誰にも分からなくなる。出たぶんはそのまま残し
    /// （消しに行かない——消す方が失敗したときに二重に分からなくなる）、
    /// **何枚出て何枚残ったか**を画面に出す。
    private func post() async {
        guard !shots.isEmpty else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        var posted = 0
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
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? L("投稿できませんでした", "Couldn't post")
                message = StoryQueue.partialFailure(posted: posted, total: shots.count, reason: reason)
                // **出せたぶんは並びから外す。** 押し直したときに
                // 同じ写真をもう一度出さないため
                shots.removeFirst(posted)
                current = 0
                return
            }
        }
        // 出したら下書きは要らない（残すと次に開いたときにまた尋ねる）
        drafts.clear()
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
    var overlays: [TextOverlay] = []
}
