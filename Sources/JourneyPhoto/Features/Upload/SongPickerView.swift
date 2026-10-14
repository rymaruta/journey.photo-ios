import SwiftUI

/// 写真に付ける曲を選ぶ。30秒の試聴だけを保存する。
struct SongPickerView: View {

    /// 選ばれた曲。**閉じたときに呼び手へ渡す**
    let onSelect: (Photo.Song) -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = MusicPreviewPlayer.shared

    @State private var query = ""
    @State private var results: [DiscoveryService.Song] = []
    /// この端末で最近選んだ曲。**欄が空のときだけ出す**（`SongPickerText` の説明）
    @State private var recent: [Photo.Song] = []
    @State private var isSearching = false
    /// 検索の回の番号。くるくるを戻すのは最新の回だけ
    @State private var searchRuns = SongPickerText.SearchRuns()
    @State private var message: String?

    private let recentStore = RecentSongsStore()

    private var rows: [Photo.Song] {
        SongPickerText.rows(query: query, results: results.map(\.asPhotoSong), recent: recent)
    }

    var body: some View {
        List {
            if let message {
                Text(message)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text2)
                    .listRowBackground(Color.clear)
            }
            ForEach(rows, id: \.previewUrl) { song in
                row(song)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(WebTheme.hairline)
            }
            // 板 23 の一覧の下の注記
            Text(SongPickerText.previewNote)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .webScreen()
        .navigationTitle(L("曲を選ぶ", "Choose a song"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L("曲名・アーティスト", "Title or artist"))
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: query) { _, value in
            // 空に戻したら最近選んだ曲に戻す。前の「見つかりませんでした」も消す
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results = []
                message = nil
            }
        }
        .overlay { if isSearching { ProgressView() } }
        // **シートの中に再生バーを置く**（板 23）。全体のバーは `RootView` の
        // 上に重なっていて、シートがそれを覆うので、ここでは見えない。
        // 部品と再生の係は全体のバーと同じもの（二重に作らない）
        .safeAreaInset(edge: .bottom) {
            // 鳴っていないときは場所を取らない（余白ごと出さない）。
            // 前から鳴っていた曲も出す（全体のバーはシートの下で見えない）
            if SongPickerText.showsBar(playingFrom: player.origin, inSongPicker: true) {
                MiniPlayerBar(inSongPicker: true)
                    .padding(.bottom, 8)
            }
        }
        .onAppear { recent = recentStore.songs(userId: auth.userId) }
        // 止めるのは曲選びで鳴らした曲だけ（前から鳴っていた曲は止めない）
        .onDisappear {
            if SongPickerText.stopsOnClose(playingFrom: player.origin) { player.stop() }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
        }
    }

    /// 1曲の行（v2 SongPicker: 最小 68・アートワーク 48 が試し聴きの口・曲名 15 の太字・
    /// 歌い手 12 の灰・右に「選ぶ」の小さなカプセル）。
    ///
    /// **試し聴きと「選ぶ」を分ける**（押し間違いで曲が決まらない）。鳴っている曲は
    /// アートワークに止める印を重ね、「選ぶ」を白の塗りにする（どの曲を聴いているかが形で分かる）
    private func row(_ song: Photo.Song) -> some View {
        let playing = player.isPlaying(song.previewURL)
        return HStack(spacing: JPSpace.s) {
            Button {
                // **曲も渡す。** 渡さないと再生の係が何の曲か知らず、
                // 下の再生バー（`MiniPlayerBar`）が出ない
                player.toggle(song.previewURL, song: song, origin: .songPicker)
            } label: {
                RemoteImage(url: song.artworkURL)
                    .frame(width: Self.artworkSize, height: Self.artworkSize)
                    .overlay {
                        // アートワークは写真なので、上の印は白（真鍮を置かない）
                        Color.black.opacity(playing ? 0.45 : 0.3)
                        Image(systemName: playing ? "stop.fill" : "play.fill")
                            .font(.system(size: playing ? 14 : 16))
                            .foregroundStyle(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    // 押せる広さは 48pt（44 を越える）
                    .contentShape(Rectangle())
                    .accessibilityLabel(SongPickerText.previewButtonLabel(isPlaying: playing))
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                if let artist = song.artist, !artist.isEmpty {
                    Text(artist)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                player.stop()
                recent = recentStore.remember(song, userId: auth.userId)
                onSelect(song)
                dismiss()
            } label: {
                Text(L("選ぶ", "Choose"))
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(playing ? WebTheme.accentText : WebTheme.text)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Self.pickHeight)
                    .background(playing ? WebTheme.accentBackground : Color.clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(playing ? Color.clear : WebTheme.line, lineWidth: JPStroke.hairline))
                    // 見た目は 34、押せる所は 44
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .frame(minHeight: Self.rowHeight)
    }

    /// 行（板 68）・アートワーク（板 48）・「選ぶ」の見た目（板 34）
    static let rowHeight: CGFloat = 68
    static let artworkSize: CGFloat = 48
    static let pickHeight: CGFloat = 34
    private func search() async {
        isSearching = true
        message = nil
        // **最新の回だけが戻す。** 古い検索が遅れて終わったとき、新しい検索の
        // 途中のくるくるを消さない
        let run = searchRuns.begin()
        defer { if searchRuns.isLatest(run) { isSearching = false } }
        // 送ったときの語。**返事が届いたとき欄が変わっていたら捨てる**
        let sent = query
        do {
            let found = try await environment.discovery.searchSongs(sent)
            guard SongPickerText.isCurrent(sent: sent, now: query) else { return }
            results = found
            if found.isEmpty { message = L("見つかりませんでした", "No results") }
        } catch {
            guard SongPickerText.isCurrent(sent: sent, now: query) else { return }
            message = (error as? LocalizedError)?.errorDescription ?? L("検索できませんでした", "Search failed")
        }
    }
}
