import SwiftUI

/// 写真に付いた曲。押すと30秒だけ鳴る。
struct SongRow: View {

    let song: Photo.Song

    @ObservedObject private var player = MusicPreviewPlayer.shared

    var body: some View {
        HStack(spacing: 10) {
            if let artwork = song.artworkURL {
                RemoteImage(url: artwork)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).font(.footnote.weight(.medium)).lineLimit(1)
                if let artist = song.artist, !artist.isEmpty {
                    Text(artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button {
                player.toggle(song.previewURL)
            } label: {
                Image(systemName: player.isPlaying(song.previewURL) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .accessibilityLabel(player.isPlaying(song.previewURL)
                                        ? L("止める", "Pause") : L("試し聴き", "Preview"))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        // 画面を離れたら止める。**鳴ったまま戻れなくしない**
        .onDisappear {
            if player.isPlaying(song.previewURL) { player.stop() }
        }
    }
}
