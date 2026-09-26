import SwiftUI

/// マイページの BGM の札（板 05c）。高さ 48pt（地 白7%・縁 白8%・角丸12）、
/// 36pt の絵、「曲名 · アーティスト」と「BGM · 30秒の試聴」、右に白い 40pt の再生の丸。
///
/// **再生器の見張りはこの札の中だけ。** 画面に持たせると、再生・一時停止の
/// たびにマイページ全体（格子まで）が描き直される
struct ProfileBgmCard: View {

    let song: Photo.Song

    @ObservedObject private var player = MusicPreviewPlayer.shared

    var body: some View {
        let playing = player.isPlaying(song.previewURL)
        HStack(spacing: 10) {
            // 絵の無い曲は音符（「壊れた写真」の記号にしない）
            RemoteImage(url: song.artworkURL, placeholderSymbol: "music.note")
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(SongSticker.text(for: song) ?? song.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                Text(L("BGM · 30秒の試聴", "BGM · 30-second preview"))
                    .font(.caption2)
                    .foregroundStyle(WebTheme.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                player.toggle(song.previewURL, song: song)
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(width: 40, height: 40)
                    .background(WebTheme.accentBackground, in: Circle())
                    // 見た目は 40pt、押せる範囲は 44pt
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? L("止める", "Pause") : L("再生", "Play"))
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}
