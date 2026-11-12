import SwiftUI

/// 探すの発見の顔の「撮影スポット」の段（札 #524・2026-11-11）。
///
/// **高さの決まった1段**（2026-11-11 owner「今のだと縦長になる」）: 上に地方のチップ（横に送る・探すの
/// 種類のチップと同じ `PillChip`）、下にその地方の県の写真の札を**横に1列**（`SearchView` の「人気の撮影地」の
/// 札と同じ 156×116・角 14）。地方を替えても段の高さは変わらない（チップの並びは同じ・札の高さは固定）。
///
/// 押す回数: 探す → 県の札（2）で、その県の撮影スポットの一覧（`OfficialSpotIndexView`）。
/// 見出しの右の「すべて見る」で全国の一覧（県ごとの見出し・地方へ跳ぶチップ・探す欄つき）。
///
/// 状態: 読み込み中は骨格（段と同じ高さ）・失敗（圏外も）は地図の「スポット」と同じ文と「もう一度試す」・
/// 公開中が0件なら地図と同じ「まだありません」
struct SearchSpotIndexSection: View {

    let groups: [SpotPrefectureIndex.Group]
    let load: SpotPrefectureIndex.Load
    /// 一覧へ渡す索引・写真
    let spots: [OfficialSpot]
    let photos: [Photo]
    let photosKnown: Bool
    var isRetrying = false
    let retry: () -> Void
    /// 選んでいる地方（`PrefectureRegions.Region.name`）。nil なら撮影スポットのいちばん多い地方
    @Binding var region: String?

    /// 札の大きさ（「人気の撮影地」の札と同じ・板 11 の 156×116）
    nonisolated static let cardWidth: CGFloat = 156
    nonisolated static let cardHeight: CGFloat = 116
    /// チップの行の高さ（`PillChip` の見た目 34 ＋ 押せる余白 5×2）
    nonisolated static let chipRowHeight: CGFloat = PillChip.height + PillChip.tapSlack * 2
    /// チップの行と札の行のあいだ
    nonisolated static let rowGap: CGFloat = JPSpace.xs
    /// 札と出典の帯のあいだ（帯の中で字を上下の真ん中に置くので、見た目のすき間は帯がつくる）
    nonisolated static let creditGap: CGFloat = 0
    /// 出典の帯の高さ＝押せる所（`CreditLink.tapHeight`・44）。字は 12pt の1行で帯の上下の真ん中。
    /// **写真の無い札も同じだけ空ける**（地方で段の高さを変えない）
    nonisolated static let creditHeight: CGFloat = CGFloat(CreditLink.tapHeight)
    /// 札の列（札＋出典の帯）の高さ
    nonisolated static let cardColumnHeight: CGFloat = cardHeight + creditGap + creditHeight
    /// 段の中身（チップ＋札＋出典）の高さ。**地方を替えても変わらない**（標準の字の大きさで 212）
    nonisolated static let bodyHeight: CGFloat = chipRowHeight + rowGap + cardColumnHeight

    /// 段を出すか。**圏外で読めなかった回は出さない**——上の電波なしの帯が言っている（帯を2本重ねない・2026-11-12）
    nonisolated static func shows(load: SpotPrefectureIndex.Load, offline: Bool) -> Bool {
        !(offline && load == .failed)
    }

    /// 節が読めなかったときの帯の字（第2章）
    static var failedTitle: String { L("撮影スポットを読み込めませんでした", "Couldn't load photo spots") }
    static var failedMessage: String { L("写真と撮影地はそのまま探せます", "You can still search photos and places") }

    var body: some View {
        let selected = SpotPrefectureIndex.selected(region, in: groups)
        VStack(alignment: .leading, spacing: JPSpace.s) {
            JPSectionHeading(eyebrow: "PHOTO SPOTS", spoken: L("撮影スポット", "Photo spots"),
                             title: L("撮影スポット", "Photo spots")) {
                if load == .ready, !groups.isEmpty {
                    NavigationLink {
                        OfficialSpotIndexView(scope: .all, spots: spots, photos: photos, photosKnown: photosKnown)
                    } label: {
                        MoreLink(text: L("すべて見る", "See all"),
                                 count: SpotPrefectureIndex.countLabel(groups.reduce(0) { $0 + $1.count }))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.spotIndex.all")
                }
            }
            switch load {
            case .loading:
                // **読み込み中に「無い」と言わない**。骨格は段と同じ高さ（届いたときに下の段を押し下げない）
                // 2026-11-12 判断（第2章）: 2本の線をやめ、**札の形**の灰（チップの行の下に県の札と同じ 156×116）
                JPLoadingState(kind: .cards(width: Self.cardWidth, height: Self.cardHeight))
                    .padding(.top, Self.chipRowHeight + Self.rowGap)
                    .frame(height: Self.bodyHeight, alignment: .top)
                    .clipped()
                    .padding(.horizontal, JPSpace.gutter)
            case .failed:
                // 2026-11-12 判断（第2章）: 節が読めないときは**帯**（画面は閉じない）。三角の大きな失敗が
                // 節いっぱいに出ていた。下の写真・撮影地はそのまま探せることを言う
                JPStateBand(kind: .partial, title: Self.failedTitle, message: Self.failedMessage,
                            isBusy: isRetrying, actionIdentifier: "search.spotIndex.retry", action: retry)
                    .padding(.horizontal, JPSpace.gutter)
            case .ready:
                if let selected {
                    strip(selected)
                } else {
                    EmptyState(icon: "mappin", message: L("公開中の撮影スポットはまだありません", "No photo spots yet"))
                }
            }
        }
    }

    /// 地方のチップと、その地方の県の札（どちらも横に送る）
    private func strip(_ selected: SpotPrefectureIndex.Group) -> some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groups) { group in
                        PillChip(title: group.title, count: group.count, selected: group.id == selected.id) {
                            region = group.id
                        }
                        .accessibilityIdentifier("search.spotIndex.region.\(group.id)")
                    }
                }
                .padding(.horizontal, JPSpace.gutter)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(selected.cards) { card in
                        VStack(alignment: .leading, spacing: Self.creditGap) {
                            NavigationLink {
                                OfficialSpotIndexView(scope: .prefecture(card.prefecture), spots: spots,
                                                      photos: photos, photosKnown: photosKnown)
                            } label: {
                                prefectureCard(card)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("search.spotIndex.prefecture")
                            credit(card)
                        }
                    }
                }
                .padding(.horizontal, JPSpace.gutter)
            }
            .frame(height: Self.cardColumnHeight)
            // 地方を替えたら札の列は頭から（前の地方の送った位置を持ち越さない）
            .id(selected.id)
        }
        // 実機の絵・UI テストが段の高さを測る目印（地方を替えた前後で同じか）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.spotIndex")
    }

    /// 県の札（写真・明朝の県名・件数）。写真が無ければ札の地に真鍮のピン（黒地の上）
    private func prefectureCard(_ card: SpotPrefectureIndex.Card) -> some View {
        Color.clear
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .overlay {
                if let cover = card.cover {
                    DownsampledRemoteImage(url: cover.url, contentMode: .fill,
                                           assumedRatioLimit: PhotoFrame.assumedRatioLimit)
                } else {
                    ZStack {
                        WebTheme.surface
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(WebTheme.accent)
                            .padding(.bottom, JPSpace.l)
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                // 写真の上なので白だけ（真鍮は写真の上では読めない）
                HStack(alignment: .firstTextBaseline, spacing: JPSpace.xxs) {
                    Text(card.prefecture)
                        .font(JPFont.rowTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text(SpotPrefectureIndex.countLabel(card.count))
                        .font(JPFont.meta)
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, JPSpace.s)
                .padding(.top, JPSpace.section)
                .padding(.bottom, SearchView.spotNameBottomInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SpotPrefectureIndex.spokenCard(card))
            .accessibilityAddTraits(.isButton)
    }

    /// 札の写真の出典。**写真と必ず一緒に**（CC BY・CC BY-SA の条件・156pt の札は `SpotImage.smallURL` の区分で
    /// 大きな枠＝ホームの札・旅の候補の札と同じ扱い）。札のリンクの**外**に置く（押す先が2つ重ならない）。
    ///
    /// 2026-11-11（確かめ役の見直し）: ホームの段と同じ `CreditLinksMenu` で包む——当たりは帯ぜんぶ（44pt）、
    /// 押すと出典の頁・ライセンス（名前つき）を選べる。幅 156 の1行には作者だけを出し（末尾で切る・長い名前の
    /// 頭を落とさない）、ライセンスはメニューへ。開ける先が無い写真だけは、ライセンスも字で出す（どこにも出ないのを避ける）。
    /// 読み上げは出典の全文（`SpotImage.credit`）。写真の無い札も同じ高さを空ける（段の高さを地方で変えない）
    @ViewBuilder
    private func credit(_ card: SpotPrefectureIndex.Card) -> some View {
        Group {
            if let cover = card.cover {
                CreditLinksMenu(links: cover.creditLinks, accessibilityLabel: cover.credit, alignment: .leading) {
                    Text(SpotPrefectureIndex.creditText(cover))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.faint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: Self.cardWidth, alignment: .leading)
                }
                .accessibilityIdentifier("search.spotIndex.credit")
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }
        .frame(width: Self.cardWidth, height: Self.creditHeight, alignment: .leading)
    }
}
