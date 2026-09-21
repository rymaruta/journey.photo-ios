import SwiftUI

/// 画面の下に出る小さなプレイヤー。**Web の `MiniPlayer` と同じ役目。**
///
/// それまでは `SongRow` が `onDisappear` で止めていた——つまり
/// **曲を鳴らしたまま別の画面へ行けなかった**。Web は移動しても
/// 鳴り続け、下のバーから止められる。アプリだけ止まると、
/// 「写真を見ながら曲を聴く」という同じ体験にならない。
///
/// **出すのは鳴っているときだけ。** 何も鳴っていないのに場所を取らない。
struct MiniPlayerBar: View {

    @ObservedObject private var player = MusicPreviewPlayer.shared

    var body: some View {
        if let song = player.playingSong {
            HStack(spacing: 10) {
                if let artwork = song.artworkURL {
                    RemoteImage(url: artwork)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(1)
                    if let artist = song.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.footnote)
                            .foregroundStyle(WebTheme.faint)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    player.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(WebTheme.foreground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("止める", "Stop"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(WebTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WebTheme.border, lineWidth: 1))
            .padding(.horizontal, 12)
            .accessibilityIdentifier("mini.player")
        }
    }
}
