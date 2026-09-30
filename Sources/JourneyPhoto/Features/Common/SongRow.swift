import SwiftUI

/// 写真に付いた曲。押すと30秒だけ鳴る。
struct SongRow: View {

    let song: Photo.Song

    @ObservedObject private var player = MusicPreviewPlayer.shared

    /// 再生ボタンの当たりを外へ広げる幅（行の余白 10pt と同じ・丸と合わせて 44pt を越える）
    private static let tapSlack: CGFloat = 10

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
                    .accessibilityLabel(SongPickerText.previewButtonLabel(
                        isPlaying: player.isPlaying(song.previewURL)))
                    // **当たりだけ 44pt に広げる。** 丸（title2 で約 26pt）の外へ広げて
                    // 同じだけ詰めるので、行の高さも見た目も変わらない
                    .padding(Self.tapSlack)
                    .contentShape(Rectangle())
                    .padding(-Self.tapSlack)
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
