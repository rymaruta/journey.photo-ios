import SwiftUI

/// **今週のお題**（札 #537 案2・2026-11-11。前は「今日のテーマ」・モック1 の「今日のミッション」）。
///
/// **通信をしない。** お題は日付から決まり（`WeeklyTheme`）、参加したかどうかは自分の写真を見て決める。
/// **みんなの参加**は公開の写真（今週お題のタグを付けて載せたもの）を横に並べる——数はその写真の数で、
/// サーバーで数えた値ではない（`WeeklyTheme.participants`）。押すとそのタグの写真の一覧へ
struct WeeklyThemeCard: View {

    /// 公開の写真（ブロックを落としたもの）。**背景と、みんなの参加**に使う
    let photos: [Photo]
    /// 自分の写真（参加したかの判定に使う）
    let myPhotos: [Photo]
    /// ホームの上段で横にめくる並びの中か（`HomeTopCardView`）。並びの中では
    /// 外の余白を持たず、隣の札と背を揃えるため高さいっぱいに伸びる
    var inCarousel = false

    private var theme: WeeklyTheme.Theme { WeeklyTheme.current() }
    private var joined: Bool { WeeklyTheme.hasJoined(theme, myPhotos: myPhotos) }

    /// 札に並べる参加の数の上限（幅 24 の写真。題の下の1行に収める）
    nonisolated static let participantThumbs = 4
    /// 参加の写真の大きさ（板の 1 行 12pt の字より一段大きく、札の背 116 に収まる）
    nonisolated static let participantSize: CGFloat = 24
    /// 参加の行の当たりを広げる量。**上は 4 だけ**——上の行の「参加する」の当たり（見た目 36＋上下 4）と、
    /// 行の間 4 で接するだけにして重ねない（札 #537 の確かめ役・2026-11-11。上下 10 ずつでは 6 重なっていた）。
    /// 下は 16 で、合わせて 24 ＋ 4 ＋ 16 ＝ 44
    nonisolated static let participantTapTop: CGFloat = 4
    nonisolated static let participantTapBottom: CGFloat = 16

    /// 背景に使う写真。**今週の参加があればその1枚目**、無ければそのタグの公開写真でいいねの多い1枚
    /// （無ければ背景なしで出す——別のお題の写真を当てない）
    private func backdrop(_ participants: [Photo]) -> Photo? {
        if let first = participants.first { return first }
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
    /// 板の「行の中の小ボタン」）、説明は1行。
    ///
    /// **#537 案2（2026-11-11）: 眉を「THIS WEEK」に。今週の参加があれば、説明の行を「みんなの参加」の行に替える**
    /// （24 の写真を最大4枚＋「今週 N件の投稿」。行は 24 なので札の背 116 に収まる）。参加が0件の週は説明のまま
    var body: some View {
        let participants = WeeklyTheme.participants(theme, photos: photos)
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            // 眉ラベル。札の地は黒なので真鍮。タグは右に添え書き
            JPEyebrowLine("THIS WEEK", spoken: L("今週のお題", "This week's theme"),
                          trailing: "#\(theme.tag)")

            HStack(alignment: .center, spacing: JPSpace.xs) {
                Text(theme.title)
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                joinControl
            }

            if participants.isEmpty {
                Text(theme.prompt)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
                    .lineLimit(1)
            } else {
                participantsRow(participants)
            }
        }
        .padding(.horizontal, JPSpace.m)
        .padding(.vertical, JPSpace.s)
        .frame(maxWidth: .infinity, minHeight: HomeTopCardView.cardHeight,
               maxHeight: inCarousel ? .infinity : nil, alignment: .topLeading)
        .background(alignment: .trailing) {
            if let backdrop = backdrop(participants) {
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

    /// **みんなの参加**の行（#537 案2）。押すとお題のタグの写真の一覧（`TagPhotosView`）へ。
    /// 見た目は 24 の行だが、当たりは上 4・下 16 に広げて 44（`contentShape`・上の「参加する」と重ねない）。読み上げは1つにまとめる
    private func participantsRow(_ participants: [Photo]) -> some View {
        NavigationLink {
            TagPhotosView(kind: .tag(theme.tag))
        } label: {
            HStack(spacing: JPSpace.xxs) {
                ForEach(participants.prefix(Self.participantThumbs)) { photo in
                    RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                        .frame(width: Self.participantSize, height: Self.participantSize)
                        .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
                }
                Text(WeeklyThemeText.participantsLine(participants.count))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
                    .lineLimit(1)
                    .padding(.leading, JPSpace.xxs)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WebTheme.text2)
            }
            .frame(height: Self.participantSize)
            // 当たりを上 4・下 16 広げて 44 に（並びの高さは 24 のまま・上の「参加する」と重ねない）
            .padding(.top, Self.participantTapTop)
            .padding(.bottom, Self.participantTapBottom)
            .contentShape(Rectangle())
            .padding(.top, -Self.participantTapTop)
            .padding(.bottom, -Self.participantTapBottom)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WeeklyThemeText.participantsSpoken(participants.count))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.theme.participants")
    }

    /// 題の右の小ボタン（見た目 36・当たり 44）。参加済みは**押せない印**（同じ週に何度も促さない）
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

/// 今週のお題の札の文（試験で読む）
enum WeeklyThemeText {
    /// 「今週 3件の投稿」
    static func participantsLine(_ count: Int) -> String {
        L("今週 \(count)件の投稿", count == 1 ? "1 post this week" : "\(count) posts this week")
    }

    /// 読み上げ: 「みんなの参加、今週 3件の投稿」
    static func participantsSpoken(_ count: Int) -> String {
        L("みんなの参加、\(participantsLine(count))", "Everyone's posts, \(participantsLine(count))")
    }
}
