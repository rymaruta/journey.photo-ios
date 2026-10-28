import SwiftUI

/// 見る画面の名前の下の「♪ 曲名 · 歌手」の行（2026-10-28・`SongMarquee`）。
///
/// 写真の上なので白の透過だけ（真鍮は使わない）。12pt。長い曲名は横に流し、
/// **「動きを減らす」がオンなら流さない**（「…」で切る）。止めている間は流れも止める。
struct SongMarqueeLine: View {
    let text: String
    var reduceMotion = false
    /// 長押しで止めている・シートを開いている間
    var paused = false

    /// 字の幅（測ったもの）。測るまでは 0（流さない）
    @State private var textWidth: Double = 0

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            line
        }
        .foregroundStyle(Color.white.opacity(StoryViewerMetrics.metaOpacity))
        .jpPhotoTextShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("曲 \(text)", "Song \(text)"))
        .accessibilityIdentifier("story.songLine")
    }

    @ViewBuilder
    private var line: some View {
        if SongMarquee.scrolls(textWidth: textWidth, reduceMotion: reduceMotion) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
                let shift = SongMarquee.offset(time: context.date.timeIntervalSinceReferenceDate,
                                               textWidth: textWidth)
                HStack(spacing: CGFloat(SongMarquee.gap)) {
                    label
                    label
                }
                .offset(x: CGFloat(-shift))
                .frame(width: CGFloat(SongMarquee.maxWidth), alignment: .leading)
                .clipped()
            }
        } else {
            label
                .truncationMode(.tail)
                .frame(maxWidth: CGFloat(SongMarquee.maxWidth), alignment: .leading)
                .clipped()
        }
    }

    /// 字そのもの。流すときは折り返さず全幅で測る（動きを減らす設定では行の幅で「…」）
    private var label: some View {
        Text(text)
            .font(JPFont.caption)
            .lineLimit(1)
            .fixedSize(horizontal: !reduceMotion, vertical: false)
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { textWidth = Double(g.size.width) }
                        .onChange(of: g.size.width) { _, width in textWidth = Double(width) }
                }
            }
    }
}
