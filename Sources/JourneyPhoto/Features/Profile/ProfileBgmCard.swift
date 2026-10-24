import SwiftUI

/// マイページの BGM の1行（見出しの中・ひとことの下）。
///
/// **2026-10-24 判断（owner の要望「アルバムのジャケット・曲名・歌手名・再生ボタン」）:**
/// 音楽アプリの「いま流れている曲」の札の形にした。左に正方形のジャケット（48pt・角 8）→
/// 曲名（1行目・`JPFont.bodyEmphasis`・text）と歌手名（2行目・12pt・text-3）→ 右端に再生の丸（44pt）。
/// 寸法は板 SongPicker の曲の行（ジャケット 48・角 8・曲名 14/500・歌手 12・再生の丸 44・白 12% の縁）に
/// そろえた（同じ曲の行を、選ぶ画面とマイページで別の形にしない）。
/// - ジャケットはサーバーが曲と一緒に返している `artwork`（iTunes Search の `artworkUrl100` を
///   300x300 に差し替えたもの・`api-user/src/musicSearch.ts`）。**新しい口・新しい費用は無い**
/// - 読めない・入っていないときは ♪ の入った角丸の四角（`RemoteImage` の記号の代わり）
/// - 「試聴」は**控えめに残す**: 鳴るのは30秒の試聴だけで、板（MyPage・SongPicker）も試聴であることを
///   書いている。歌手名の後ろに「· 試聴」（12pt・text-3）。歌手名が長いときは歌手名から省く
///
/// **2026-10-21 判断（全画面の点検）の「札にしない」はそのまま**: 地と縁の札にせず、見出しの中の1行。
/// 行ぜんぶが再生の切り替え（押せる高さはジャケットの 48 で 44 を越える）。
/// 2026-10-14 判断（v2）の「白の塗りは主ボタン1つに取っておく」もそのまま——再生の丸は白 12% の縁だけ。
///
/// **再生器の見張りはこの行の中だけ。** 画面に持たせると、再生・一時停止の
/// たびにマイページ全体（格子まで）が描き直される
struct ProfileBgmCard: View {

    let song: Photo.Song

    @ObservedObject private var player = MusicPreviewPlayer.shared

    /// ジャケットの辺と角（板 SongPicker の 48・8）
    nonisolated static let artworkSide: CGFloat = 48
    nonisolated static let artworkRadius: CGFloat = 8
    /// 再生の丸の辺（押せる 44 と同じ）
    nonisolated static let playSide: CGFloat = WebTheme.minTapTarget

    var body: some View {
        let playing = player.isPlaying(song.previewURL)
        Button {
            player.toggle(song.previewURL, song: song)
        } label: {
            HStack(spacing: JPSpace.s) {
                RemoteImage(url: ProfileSongLine.artworkURL(song),
                            placeholderSymbol: ProfileSongLine.fallbackSymbol)
                    .frame(width: Self.artworkSide, height: Self.artworkSide)
                    .clipShape(RoundedRectangle(cornerRadius: Self.artworkRadius))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(JPFont.bodyEmphasis)
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 0) {
                        if let artist = ProfileSongLine.artist(song) {
                            Text(artist)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(" · ")
                                .fixedSize()
                        }
                        Text(ProfileSongLine.previewLabel)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                }
                Spacer(minLength: 0)
                Image(systemName: ProfileSongLine.playSymbol(isPlaying: playing))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: Self.playSide, height: Self.playSide)
                    .overlay(Circle().strokeBorder(WebTheme.border, lineWidth: JPStroke.hairline))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Self.artworkSide)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ProfileSongLine.accessibilityLabel(song))
        .accessibilityValue(playing ? L("再生中", "Playing") : "")
        .accessibilityHint(playing ? L("止める", "Stop") : L("30秒の試聴を再生", "Plays a 30-second preview"))
        .accessibilityIdentifier("mypage.bgm")
    }
}

/// マイページの曲の行の言葉と印（画面を持たない計算・単体テスト用）
enum ProfileSongLine {

    /// ジャケットが無い・読めないときの印（♪）
    static let fallbackSymbol = "music.note"

    /// 試聴であることの印（歌手名の後ろに小さく）
    static var previewLabel: String { L("試聴", "Preview") }

    /// ジャケットの URL。**https だけ**（サーバーも https の決まった配信元しか保存しない）。
    /// 空・壊れた値・http は nil ＝ ♪ の四角を出す
    static func artworkURL(_ song: Photo.Song) -> URL? {
        guard let raw = song.artwork?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// 2行目の歌手名。空なら nil（「· 試聴」だけを出す）
    static func artist(_ song: Photo.Song) -> String? {
        guard let artist = song.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty
        else { return nil }
        return artist
    }

    /// 再生の丸の印。鳴っている間は一時停止、止まっている間は再生
    static func playSymbol(isPlaying: Bool) -> String {
        isPlaying ? "pause.fill" : "play.fill"
    }

    /// 読み上げ（曲名と歌手名）
    static func accessibilityLabel(_ song: Photo.Song) -> String {
        let name = SongSticker.text(for: song) ?? song.title
        return L("BGM \(name)", "Profile song \(name)")
    }
}
