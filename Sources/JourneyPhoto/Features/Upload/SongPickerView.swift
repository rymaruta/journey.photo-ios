import SwiftUI

/// 写真に付ける曲を選ぶ。30秒の試聴だけを保存する。
struct SongPickerView: View {

    /// 選ばれた曲。**閉じたときに呼び手へ渡す**
    let onSelect: (Photo.Song) -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = MusicPreviewPlayer.shared

    @State private var query = ""
    @State private var results: [DiscoveryService.Song] = []
    @State private var isSearching = false
    @State private var message: String?

    var body: some View {
        List {
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(results) { song in
                HStack(spacing: 10) {
                    RemoteImage(url: song.artworkURL)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title).font(.callout).lineLimit(1)
                        Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    // 試し聴きと「選ぶ」を分ける（押し間違いで曲が決まらない）
                    Button {
                        player.toggle(URL(string: song.previewUrl))
                    } label: {
                        Image(systemName: player.isPlaying(URL(string: song.previewUrl))
                              ? "pause.circle.fill" : "play.circle")
                            .accessibilityLabel(L("試し聴き", "Preview"))
                    }
                    .buttonStyle(.borderless)
                    Button(L("選ぶ", "Choose")) {
                        player.stop()
                        onSelect(song.asPhotoSong)
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .webScreen()
        .navigationTitle(L("曲を選ぶ", "Choose a song"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L("曲名・アーティスト", "Title or artist"))
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: query) { _, value in
            if value.isEmpty { results = [] }
        }
        .overlay { if isSearching { ProgressView() } }
        .onDisappear { player.stop() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Labels.Common.close) { dismiss() }
            }
        }
    }

    private func search() async {
        isSearching = true
        message = nil
        defer { isSearching = false }
        do {
            results = try await environment.discovery.searchSongs(query)
            if results.isEmpty { message = L("見つかりませんでした", "No results") }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? L("検索できませんでした", "Search failed")
        }
    }
}
