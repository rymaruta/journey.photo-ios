import SwiftUI

/// 曲の「Apple Music で聴く」のリンク（2026-11-26 判断・審査 5.2.5）。
///
/// iTunes の試聴を流す所には、曲の Apple Music の頁へのリンクを添える。押すと外の Music か Safari で開く。
/// 開く先は `SongPickerText.appleMusicURL`（保存した `trackUrl`、無ければ Apple Music の検索）。
///
/// 色は板どおり: 黒い地の上は真鍮（外へ出るリンク。スポットの「公式サイト」と同じ）、写真やガラスの上は白に影。
/// 見た目は小さな字のまま、**当たりだけ 44pt に広げる**（範囲の形だけ広げる。負の余白で張り出さない・2026-10-21 の決まり）
struct AppleMusicLink: View {

    let song: Photo.Song
    /// 置く地
    var ground: Ground = .dark
    /// 狭い所では「Apple Music」だけを見せる（読み上げは「Apple Music で聴く」）
    var compact = false

    enum Ground { case dark, photo }

    @Environment(\.openURL) private var openURL

    /// 字の高さ（caption 12pt で約 16pt）から 44pt まで、上下に広げる量
    static let verticalSlack: CGFloat = 14

    var body: some View {
        if let url = SongPickerText.appleMusicURL(for: song) {
            Button {
                openURL(url)
            } label: {
                HStack(spacing: 3) {
                    Text(compact ? SongPickerText.appleMusicShortLabel : SongPickerText.appleMusicLabel)
                        .font(JPFont.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(ground == .photo ? WebTheme.foreground : WebTheme.accent)
                .fixedSize()
                .frame(minWidth: WebTheme.minTapTarget)
                .contentShape(Rectangle().inset(by: -Self.verticalSlack))
            }
            .buttonStyle(.plain)
            // 写真やガラスの上は白の字に影（板: 写真の上の字は黒 60% の影）
            .shadow(color: .black.opacity(ground == .photo ? 0.6 : 0), radius: 2, x: 0, y: 1)
            .accessibilityLabel(SongPickerText.appleMusicLabel)
            .accessibilityHint(L("Apple Music で曲を開きます", "Opens the song in Apple Music"))
            .accessibilityIdentifier("song.appleMusic")
        }
    }
}
