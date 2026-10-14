import SwiftUI

/// 今日のテーマ（モック1 の「今日のミッション」）。
///
/// **通信をしない。** テーマは日付から決まり（`DailyTheme`）、参加したか
/// どうかは自分の写真を見て決める。サーバーにテーマを配る口も、参加を
/// 数える口も無いので、**参加人数のような数は出さない**。
struct DailyThemeCard: View {

    /// 背景に使う写真。**そのテーマのタグが付いた公開写真**から1枚
    /// （無ければ背景なしで出す——別のテーマの写真を当てない）
    let photos: [Photo]
    /// 自分の写真（参加したかの判定に使う）
    let myPhotos: [Photo]
    /// ホームの上段で横にめくる並びの中か（`HomeTopCardView`）。並びの中では
    /// 外の余白を持たず、隣の札と背を揃えるため高さいっぱいに伸びる
    var inCarousel = false

    private var theme: DailyTheme.Theme { DailyTheme.today() }
    private var joined: Bool { DailyTheme.hasJoined(theme, myPhotos: myPhotos) }

    private var backdrop: Photo? {
        let key = TagChoices.key(theme.tag)
        let matched = photos.filter { photo in
            (photo.tags ?? []).contains { TagChoices.key($0) == key }
        }
        return GallerySort.popular.apply(matched).first
    }

    /// **v2（2026-10-14・Main の板の「TODAY'S THEME」の札）**: 隣の札（`HomeTopCardView`）と同じ
    /// 地（#0E0E0F）・白 8% の縁・角 16。眉は真鍮＋消える線、題は明朝、説明は text-2。
    /// 写真は右に薄く敷いたまま（字は写真に重ねない側＝黒地の上）。
    /// 「参加する」は**写真のある画面の主ボタン＝白**（CLAUDE.md・`JPPillStyle.main(onPhoto: true)`）。
    /// 札の中なので高さは副ボタンの 44
    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            // 眉ラベル（板の `TODAY'S THEME`）。札の地は黒なので真鍮。タグは右に添え書き
            JPEyebrowLine("TODAY'S THEME", spoken: L("今日のテーマ", "Today's theme"),
                          trailing: "#\(theme.tag)")

            Text(theme.title)
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.text)

            Text(theme.prompt)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)

            if joined {
                // **参加済みは「押せない印」にする。** 同じ日に何度も
                // 促さない（写真は自分の写真から確かめたもの）
                HStack(spacing: JPSpace.xxs) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(L("参加済み", "Joined"))
                        .font(JPFont.bodyEmphasis)
                }
                .foregroundStyle(WebTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: JPHeight.secondaryButton)
                .background(WebTheme.surface, in: Capsule())
            } else {
                Button {
                    MissionRouter.shared.join(tag: theme.tag)
                } label: {
                    HStack(spacing: JPSpace.xxs) {
                        Text(L("参加する", "Join"))
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                    }
                    .jpPillButton(.main(onPhoto: true), height: JPHeight.secondaryButton)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(JPSpace.m)
        .frame(maxHeight: inCarousel ? .infinity : nil, alignment: .top)
        .background(alignment: .trailing) {
            if let backdrop {
                // **写真は脇役。** 文字が読めなくならないよう、右側だけに薄く
                RemoteImage(url: backdrop.gridImageURL, alignment: backdrop.gridAlignment)
                    .frame(width: 160)
                    .opacity(0.35)
                    .mask {
                        LinearGradient(colors: [Color.black.opacity(0), Color.black],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .accessibilityHidden(true)
            }
        }
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.l))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .padding(.horizontal, inCarousel ? 0 : JPSpace.gutter)
    }
}
