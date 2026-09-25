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
                Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let artist = song.artist, !artist.isEmpty {
                    Text(artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button {
                player.toggle(song.previewURL, song: song)
            } label: {
                Image(systemName: player.isPlaying(song.previewURL) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .accessibilityLabel(player.isPlaying(song.previewURL)
                                        ? L("止める", "Pause") : L("試し聴き", "Preview"))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        // **画面を離れても止めない（2026-09-21 に改めた）。**
        // 以前はここで止めていたので、曲を鳴らしたまま別の画面へ行けなかった
        // ——Web は移動しても鳴り続け、下のバー（`MiniPlayer`）から止められる。
        // 鳴ったまま戻れなくなる心配は `MiniPlayerBar` が引き受ける
        // （鳴っている間はどの画面にも出て、そこから止められる）
    }
}
