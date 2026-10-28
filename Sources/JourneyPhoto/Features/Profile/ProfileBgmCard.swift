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
/// - 歌手名だけを表示し、「試聴」の文字は表示しない
///
/// **2026-10-28 判断（owner が細い縁の枠と輪の再生ボタンを選んだ・色は「A 真鍮だけ」）:**
/// 2026-10-21 判断（全画面の点検）の「札にしない」を**上書きする**。
/// - 枠: 白 12% の細い縁（`WebTheme.border`・`JPStroke.hairline`）・角 14（`JPRadius.m`）・内側の余白 12。
///   **地は塗らない**（札の地にすると見出しの中で重くなる）。「BGM」などのラベルも付けない
/// - 再生ボタン: 見た目 34pt の真鍮の輪（1px）＋真鍮の ▶（13pt）。**押せる範囲は 44 のまま**、行ぜんぶも押せるまま
/// - 再生中: ⏸ にし、輪が 30 秒の試聴の進みに合わせて満ちる（下地の輪は真鍮 28%・進みは真鍮 2pt・
///   端は丸め・12時から時計回り）。「動きを減らす」がオンなら 1 秒ごとに飛び飛びで進める
/// - 色はすべて真鍮 `WebTheme.accent`（新しい色を作らない）
///
/// **再生器の見張りはこの行の中だけ。** 画面に持たせると、再生・一時停止の
/// たびにマイページ全体（格子まで）が描き直される。進みも `@Published` にせず、
/// 鳴っている間だけこの行の `TimelineView` が読みに行く
struct ProfileBgmCard: View {

    let song: Photo.Song

    @ObservedObject private var player = MusicPreviewPlayer.shared

    /// ジャケットの辺と角（板 SongPicker の 48・8）
    nonisolated static let artworkSide: CGFloat = 48
    nonisolated static let artworkRadius: CGFloat = 8
    /// 再生の押せる範囲の辺（押せる 44 と同じ）
    nonisolated static let playSide: CGFloat = WebTheme.minTapTarget
    /// 再生の輪の見た目の辺（モック A の 34）。押せる範囲（`playSide`）より小さい
    nonisolated static let ringSide: CGFloat = 34
    /// ▶ ⏸ の大きさ（モック A の 13）
    nonisolated static let playIconSize: CGFloat = 13
    /// 止まっているときの輪・再生中の下地の輪の太さ（1px）
    nonisolated static let ringLineWidth: CGFloat = JPStroke.hairline
    /// 再生中の進みの太さ（2pt）
    nonisolated static let progressLineWidth: CGFloat = JPStroke.emphasis
    /// 再生中の下地の輪の濃さ（真鍮 28%）
    nonisolated static let ringTrackOpacity: Double = 0.28
    /// 進みを読み直す間隔（秒）。ふだんは 0.1 秒（34pt の輪で 1 回 0.4pt ほど・目には滑らか）、
    /// 「動きを減らす」がオンなら 1 秒ごとに飛び飛び
    nonisolated static let progressInterval: Double = 0.1
    nonisolated static let reducedProgressInterval: Double = 1

    /// 枠（2026-10-28 判断）: 白 12% の細い縁・角 14・内側の余白 12・地は塗らない
    nonisolated static let frameRadius: CGFloat = JPRadius.m
    nonisolated static let framePadding: CGFloat = JPSpace.s
    nonisolated static let frameLineWidth: CGFloat = JPStroke.hairline
    static let frameColor = WebTheme.border

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    if let artist = ProfileSongLine.artist(song) {
                        Text(artist)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                playRing(playing: playing)
                    .frame(width: Self.playSide, height: Self.playSide)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Self.artworkSide)
            .padding(Self.framePadding)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: Self.frameRadius)
                    .strokeBorder(Self.frameColor, lineWidth: Self.frameLineWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ProfileSongLine.accessibilityLabel(song))
        .accessibilityValue(playing ? L("再生中", "Playing") : "")
        .accessibilityHint(playing ? L("止める", "Stop") : L("30秒の試聴を再生", "Plays a 30-second preview"))
        .accessibilityIdentifier("mypage.bgm")
    }

    /// 見た目 34pt の真鍮の輪と ▶ ⏸。鳴っている間だけ `TimelineView` で進みを読み直す
    /// （止まっている間は読みに行かない）
    @ViewBuilder
    private func playRing(playing: Bool) -> some View {
        if playing {
            TimelineView(.animation(minimumInterval: reduceMotion ? Self.reducedProgressInterval
                                                                  : Self.progressInterval)) { _ in
                ring(playing: true, progress: player.previewProgress(for: song.previewURL))
            }
        } else {
            ring(playing: false, progress: 0)
        }
    }

    private func ring(playing: Bool, progress: Double) -> some View {
        ZStack {
            Circle()
                .strokeBorder(ProfileSongLine.brass.opacity(playing ? Self.ringTrackOpacity : 1),
                              lineWidth: Self.ringLineWidth)
            if playing {
                // 12時から時計回り（-90°）。2pt の線が輪の内側に収まるよう 1pt 内へ寄せる
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ProfileSongLine.brass,
                            style: StrokeStyle(lineWidth: Self.progressLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(Self.progressLineWidth / 2)
            }
            Image(systemName: ProfileSongLine.playSymbol(isPlaying: playing))
                .font(.system(size: Self.playIconSize, weight: .semibold))
                .foregroundStyle(ProfileSongLine.brass)
        }
        .frame(width: Self.ringSide, height: Self.ringSide)
        // 進みは飛び飛びでよい（間隔ごとに描き直すだけ。アニメーションを付けない）
        .animation(nil, value: progress)
    }
}

/// マイページの曲の行の言葉と印（画面を持たない計算・単体テスト用）
enum ProfileSongLine {

    /// ジャケットが無い・読めないときの印（♪）
    static let fallbackSymbol = "music.note"

    /// デザインシステムの真鍮アクセント（BrandPalette.accent = #C9A66B）。
    /// 黒地のアイコン・合図に使う既定色。独自の金色を増やさない。
    static let brass = WebTheme.accent

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
