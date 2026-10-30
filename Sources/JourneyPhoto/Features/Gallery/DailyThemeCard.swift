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
    /// 「参加する」は**写真のある画面の主ボタン＝白**（CLAUDE.md・`JPPillStyle.main(onPhoto: true)` の塗りと字）。
    ///
    /// **#417 ③（2026-10-30 owner 採用）: 背を隣の札と同じ 116 に。** 「参加する」は題の右（見た目 36・当たり 44・
    /// 板の「行の中の小ボタン」）、説明は1行。以前は「参加する」が札の幅いっぱいの 44 の帯で下に積まれ、
    /// 並びの背が 156 に伸びていた。札の中の2段目（あなたの #タグ・きのうのテーマの写真）は板にだけあった案で、作らない
    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            // 眉ラベル（板の `TODAY'S THEME`）。札の地は黒なので真鍮。タグは右に添え書き
            JPEyebrowLine("TODAY'S THEME", spoken: L("今日のテーマ", "Today's theme"),
                          trailing: "#\(theme.tag)")

            HStack(alignment: .center, spacing: JPSpace.xs) {
                Text(theme.title)
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                joinControl
            }

            Text(theme.prompt)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
                .lineLimit(1)
        }
        .padding(.horizontal, JPSpace.m)
        .padding(.vertical, JPSpace.s)
        .frame(maxWidth: .infinity, minHeight: HomeTopCardView.cardHeight,
               maxHeight: inCarousel ? .infinity : nil, alignment: .topLeading)
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
        .jpCardFace()
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .padding(.horizontal, inCarousel ? 0 : JPSpace.gutter)
    }

    /// 題の右の小ボタン（見た目 36・当たり 44）。参加済みは**押せない印**（同じ日に何度も促さない）
    @ViewBuilder
    private var joinControl: some View {
        if joined {
            HStack(spacing: JPSpace.xxs) {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityHidden(true)
                Text(L("参加済み", "Joined"))
            }
            .jpCapsuleFace(font: JPOutlineSize.inline.font, text: WebTheme.text, fill: WebTheme.surface,
                           border: Color.clear, fullWidth: false, minHeight: JPOutlineSize.inline.height,
                           textInset: Self.joinInset)
            .fixedSize()
            .padding(.vertical, JPOutlineSize.inline.tapSlack)
        } else {
            Button {
                MissionRouter.shared.join(tag: theme.tag)
            } label: {
                HStack(spacing: JPSpace.xxs) {
                    Text(L("参加する", "Join"))
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                .jpCapsuleFace(font: JPOutlineSize.inline.font, text: WebTheme.accentText,
                               fill: JPPillStyle.main(onPhoto: true).fill, border: Color.clear, fullWidth: false,
                               minHeight: JPOutlineSize.inline.height, textInset: Self.joinInset)
                .fixedSize()
                // 当たりは 44（見た目 36 の上下に 4 ずつ）
                .padding(.vertical, JPOutlineSize.inline.tapSlack)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 「参加する」の字の左右（板 padding 0 14）
    nonisolated static let joinInset: CGFloat = 14

}
