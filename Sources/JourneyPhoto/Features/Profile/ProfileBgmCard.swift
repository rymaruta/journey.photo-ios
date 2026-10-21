import SwiftUI

/// マイページの BGM の1行（見出しの中・ひとことの下）。
///
/// **2026-10-21 判断（全画面の点検）: 札を1行に畳んで見出しの中へ移した。** 以前は数の下に
/// 札（40pt の絵・2行の字・44pt の再生の丸・地と縁）を置いていて、旅の記録の線・ハイライトと
/// 合わせて自分の写真が最初の画面の一番下まで押し下げられていた（板 v2 MyPage の札からの変更）。
/// いま: 左に再生の丸（見た目 28・白 8% の地・白の印）→「♪ 曲名 · アーティスト」（13pt・text-2）
/// →「試聴」（12pt・text-3）。**行ぜんぶが再生の切り替え**で、押せる高さは 44pt
/// （並びの上では見た目の高さのまま・押せる範囲の形だけ広げる）。
///
/// 2026-10-14 判断（v2）の「再生の丸は白 8% の地」はそのまま（白の塗りは主ボタン1つに取っておく）。
///
/// **再生器の見張りはこの行の中だけ。** 画面に持たせると、再生・一時停止の
/// たびにマイページ全体（格子まで）が描き直される
struct ProfileBgmCard: View {

    let song: Photo.Song

    @ObservedObject private var player = MusicPreviewPlayer.shared

    /// 再生の丸の見た目の辺
    nonisolated static let playSide: CGFloat = 28
    /// 押せる高さ（44）に足りない分を上下に張り出す量
    nonisolated static let tapSlack: CGFloat = (WebTheme.minTapTarget - playSide) / 2

    var body: some View {
        let playing = player.isPlaying(song.previewURL)
        Button {
            player.toggle(song.previewURL, song: song)
        } label: {
            HStack(spacing: JPSpace.xs) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: Self.playSide, height: Self.playSide)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .accessibilityHidden(true)
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
                Text(SongSticker.text(for: song) ?? song.title)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(L("試聴", "Preview"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            // 押せる範囲だけを上下に広げる（並びの高さは見た目の 28 のまま）。
            // 2026-10-21 判断（確かめ役の見直し）: 負の余白で張り出すと、字を大きくして行が伸びたとき
            // 上下の行に重なる。範囲の形だけを広げれば、並びは字の大きさに合わせて伸びる
            .contentShape(Rectangle().inset(by: -Self.tapSlack))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("BGM \(SongSticker.text(for: song) ?? song.title)",
                              "Profile song \(SongSticker.text(for: song) ?? song.title)"))
        .accessibilityValue(playing ? L("再生中", "Playing") : "")
        .accessibilityHint(playing ? L("止める", "Stop") : L("30秒の試聴を再生", "Plays a 30-second preview"))
        .accessibilityIdentifier("mypage.bgm")
    }
}
