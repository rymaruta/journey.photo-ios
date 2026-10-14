import SwiftUI

/// マイページの BGM の札（板 v2 MyPage）。地は v2 の札の面（`WebTheme.card`・#0E0E0F）・縁 白8%・角 14、
/// 40pt の絵（角 6）、「曲名 · アーティスト」と「BGM · 30秒の試聴」、右に再生の丸（白 8% の地・44pt）。
///
/// 2026-10-14 判断（v2）: 再生の丸は白の塗りから白 8% の地に替えた（板 v2）。白の塗りは
/// 写真のある画面の主ボタン1つに取っておく（マイページで白く塗るものは「フォローする」と同じく1つまで）
///
/// **再生器の見張りはこの札の中だけ。** 画面に持たせると、再生・一時停止の
/// たびにマイページ全体（格子まで）が描き直される
struct ProfileBgmCard: View {

    let song: Photo.Song

    @ObservedObject private var player = MusicPreviewPlayer.shared

    var body: some View {
        let playing = player.isPlaying(song.previewURL)
        HStack(spacing: JPSpace.s) {
            // 絵の無い曲は音符（「壊れた写真」の記号にしない）
            RemoteImage(url: song.artworkURL, placeholderSymbol: "music.note")
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(SongSticker.text(for: song) ?? song.title)
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                Text(L("BGM · 30秒の試聴", "BGM · 30-second preview"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                player.toggle(song.previewURL, song: song)
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? L("止める", "Stop") : L("再生", "Play"))
        }
        .padding(.leading, 10)
        .padding(.trailing, JPSpace.xs)
        .padding(.vertical, 10)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }
}
