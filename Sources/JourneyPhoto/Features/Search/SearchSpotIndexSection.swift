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
    /// 選んでいる地方（`PrefectureRegions.Region.name`）。nil なら撮影スポットのいちばん多い地方。
    /// **写真の札・地方のチップ・地図で1つ**（どれで選んでも同じ地方）
    @Binding var region: String?
    /// 「写真｜地図」（2026-11-11 owner「タブ切り替えとかでもいいから縦に長くならないように」）
    @Binding var mode: SpotIndexMode
    /// 地図をなぞっている区分（離すまで札がこれに替わる）。**探すの画面が持つ**——なぞっている間は外側の
    /// スクロールを止める（`SearchView` の `.scrollDisabled`・確かめ役の指摘 2026-11-11）
    @Binding var tracing: String?
    /// 出している地図の id（地図が2つ以上のとき、地図の右上の切り替えで替える）
    @State private var mapId: String?
    /// 地方のチップと選択を分けない地図（日本以外）で選んでいる区分（地図の id → 区分の id）
    @State private var otherSelections: [String: String] = [:]
    /// 読み上げのダブルタップで開く一覧（地図の区分の「すべて見る」と同じ行き先）
    @State private var openArea: SpotIndexScope?

    /// 出せる地図（いまは日本だけ・`SpotRegionMap.available`）。無ければ「地図」の札を出さない
    private var maps: [SpotRegionMap] { SpotRegionMap.available(japan: PrefectureMapGeometry.bundled) }

    /// 地図の幅（段の中の高さ `cardColumnHeight` に地図の縦横比を合わせる）
    nonisolated static func mapWidth(for shapes: SpotMapShapes) -> CGFloat {
        guard shapes.size.height > 0 else { return cardColumnHeight }
        return (cardColumnHeight * shapes.size.width / shapes.size.height).rounded(.up)
    }

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
                    VStack(alignment: .leading, spacing: 0) {
                        // 「写真｜地図」。地図の形が読めなければ札を出さない（写真だけ）
                        if !maps.isEmpty {
                            ProfileTabBar(tabs: SpotIndexMode.allCases, selection: $mode, movesContent: false)
                                .padding(.bottom, JPSpace.xs)
                        }
                        strip(selected)
                    }
                    // UI テストが「写真」と「地図」で段ぜんたいの高さが同じかを測る目印
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("search.spotIndex.block")
                    .navigationDestination(item: $openArea) { scope in
                        OfficialSpotIndexView(scope: scope, spots: spots, photos: photos, photosKnown: photosKnown)
                    }
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
            if mode == .map, let map = maps.first(where: { $0.id == mapId }) ?? maps.first {
                mapRow(selected, map: map)
                    .frame(height: Self.cardColumnHeight)
            } else {
                cardsRow(selected)
            }
        }
        // **写真と地図で同じ高さ**（替えても下の段が動かない・`bodyHeight`）
        .frame(height: Self.bodyHeight, alignment: .top)
        // 実機の絵・UI テストが段の高さを測る目印（地方を替えた前後・写真と地図で同じか）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.spotIndex")
    }

    /// 地図と、選んでいる（なぞっている）区分の札（Web のホームの地図の下の札と同じ中身）。**地図の型に依らない**
    private func mapRow(_ selected: SpotPrefectureIndex.Group, map: SpotRegionMap) -> some View {
        let areas = map.areas(SpotMapSource(spots: spots, japanGroups: groups))
        // 日本の地方は上のチップ・写真の札の列と同じ選択。ほかの地図は地図ごとに覚える（無ければ件数のいちばん多い区分）
        let chosen = map.sharesRegionChips ? selected.region.name
            : otherSelections[map.id] ?? areas.max { $0.count < $1.count }?.id
        let shown = areas.first { $0.id == (tracing ?? chosen) }
        return HStack(alignment: .top, spacing: JPSpace.s) {
            SpotRegionMapView(map: map, areas: areas, selected: chosen, tracing: $tracing, onSelect: { id in
                if map.sharesRegionChips { region = id } else { otherSelections[map.id] = id }
            }, onActivate: {
                // 読み上げのダブルタップ: いまの区分の一覧へ（右の札の「すべて見る」と同じ行き先）
                openArea = areas.first { $0.id == chosen }?.scope
            })
            .frame(width: Self.mapWidth(for: map.shapes), height: Self.cardColumnHeight)
            // 地図が2つ以上のときだけ、地図の右上に重ねて切り替え（段の高さは変えない・`SpotRegionMap.showsSwitcher`）
            .overlay(alignment: .topTrailing) {
                if SpotRegionMap.showsSwitcher(maps) { mapSwitcher(current: map) }
            }
            if let shown { areaCard(shown) }
        }
        .padding(.horizontal, JPSpace.gutter)
    }

    /// 地図の切り替え（「日本｜世界」）。地図の枠の中に重ねる小さな札。**地図が1つの間は出さない**
    private func mapSwitcher(current: SpotRegionMap) -> some View {
        HStack(spacing: 0) {
            ForEach(maps) { map in
                Button {
                    tracing = nil
                    mapId = map.id
                } label: {
                    Text(map.title)
                        .font(JPFont.caption.weight(map.id == current.id ? .semibold : .regular))
                        .foregroundStyle(map.id == current.id ? WebTheme.accent : WebTheme.text2)
                        .padding(.horizontal, JPSpace.xs)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(map.id == current.id ? .isSelected : [])
                .accessibilityIdentifier("search.spotIndex.mapKind.\(map.id)")
            }
        }
    }

    /// 地図の右の札: 区分の名前・件数・上位の名前・「すべて見る」（その区分の撮影スポットの一覧へ）
    private func areaCard(_ area: SpotMapArea) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            Text(area.title)
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Text(L("撮影スポット \(area.count)件", area.count == 1 ? "1 photo spot" : "\(area.count) photo spots"))
                .font(JPFont.meta)
                .foregroundStyle(WebTheme.text2)
                .lineLimit(1)
            // 名前の行は**切れる側**（大きな字では先に縮む・2行まで）
            Text(area.namesLine)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .lineLimit(2)
                .layoutPriority(-1)
            Spacer(minLength: 0)
            NavigationLink {
                OfficialSpotIndexView(scope: area.scope, spots: spots, photos: photos, photosKnown: photosKnown)
            } label: {
                // 「北海道をすべて見る ›」（見出しの全国の「すべて見る」と分ける）。**切れない側**（大きな字でも残す）。
                // 読み上げは「北海道の撮影スポットをすべて見る」
                MoreLink(text: area.seeAllLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel(area.seeAll)
            .accessibilityIdentifier("search.spotIndex.mapSeeAll")
        }
        .padding(.horizontal, JPSpace.s)
        .padding(.top, JPSpace.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .jpCardFace()
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.spotIndex.regionCard")
    }

    /// その地方の県の札の列（横に送る）
    private func cardsRow(_ selected: SpotPrefectureIndex.Group) -> some View {
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
