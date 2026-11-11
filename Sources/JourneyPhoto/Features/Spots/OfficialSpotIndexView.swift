import SwiftUI

/// 撮影スポットの一覧（探すの「撮影スポット」の段から開く・札 #524・2026-11-11）。
///
/// - **県の一覧**（`.prefecture`）: 段の県の札から。その県の撮影スポットを並べる
/// - **全国の一覧**（`.all`）: 段の「すべて見る」から。県ごとの見出しで区切り、上の地方のチップで跳べる
///   （県は北から・`SpotPrefectureIndex.nationalSections`）
///
/// どちらも上に探す欄（`SearchBox`）を置き、**名前・読み・別名**で絞る（地図・探すと同じ
/// `OfficialSpotIndex.matches`。`RegionList.sections` の `query`・`aliases` から通す）。
/// 県の決め方・行の部品（`OfficialSpotRow`）・行き先（`OfficialSpotView`）は地図の「スポット」「リスト」と同じ。
///
/// 並び: 位置を**もう許している人だけ**近い順（`CurrentLocation.locateIfAllowed`・尋ねない）。
/// 許していない人は名前の順（`OfficialSpotList.rows`）。
///
/// 行の写真（丸）の詳細は、頭から見えた所までだけ読む（`SpotDetailNeeds.ListDepth`・地図の一覧と同じ）
struct OfficialSpotIndexView: View {

    enum Scope: Hashable {
        case prefecture(String)
        case all
    }

    let scope: Scope
    /// 探すが持っている撮影スポットの索引（`OfficialSpotService.fetchIndex`）
    let spots: [OfficialSpot]
    /// 写真の枚数を数える公開写真（探すの一覧）
    let photos: [Photo]
    /// 写真の数を言ってよいか（`SpotScreen.photosKnown`）
    let photosKnown: Bool

    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var location = CurrentLocation()
    @State private var query = ""
    @State private var aliases: [String: [String]] = [:]
    @State private var links = SpotPhotoLinks.empty
    /// 詳細を重ねた索引（最初は受け取ったまま）
    @State private var detailed: [OfficialSpot]?
    @State private var depth = SpotDetailNeeds.ListDepth()
    /// 最後に跳んだ地方（チップの選んだ印）
    @State private var jumped: String?

    private var here: Photo.Coords? {
        if case .located(let latitude, let longitude) = location.state {
            return Photo.Coords(lat: latitude, lng: longitude)
        }
        return nil
    }

    private var title: String {
        switch scope {
        case .prefecture(let name): return name
        case .all: return L("撮影スポット", "Photo spots")
        }
    }

    var body: some View {
        let source = detailed ?? spots
        let all = RegionList.sections(photos: photos, spots: source, query: query,
                                      aliases: aliases, links: links, from: here)
        let sections = Self.shown(all, scope: scope)
        let rows = sections.flatMap(\.spots)
        let needs = SpotDetailNeeds.mapSpotList(rows, through: depth.depth(query: query, category: nil))
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: JPSpace.s) {
                    SearchBox(prompt: L("撮影スポットの名前で絞る", "Filter photo spots by name"),
                              text: $query, identifier: "spotIndex.field")
                        .padding(.horizontal, JPSpace.gutter)
                    if scope == .all {
                        jumpChips(SpotPrefectureIndex.jumps(sections), proxy: proxy)
                    }
                }
                .padding(.top, JPSpace.xs)
                .padding(.bottom, JPSpace.s)
                .background(WebTheme.background)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if spots.isEmpty {
                            EmptyState(message: L("公開中の撮影スポットはまだありません", "No photo spots yet"))
                        } else if sections.isEmpty {
                            EmptyState(message: L("見つかりませんでした", "No results"))
                        } else {
                            if case .prefecture = scope {
                                JPEyebrowLine(here != nil ? L("撮影スポット · 近い順", "Photo spots · nearest first")
                                                          : L("撮影スポット", "Photo spots"),
                                              trailing: SpotPrefectureIndex.countLabel(rows.count))
                                    .padding(.bottom, JPSpace.xs)
                            }
                            ForEach(sections) { section in
                                if scope == .all {
                                    // 県の見出し（真鍮の眉と消える線・黒地の上）。跳ぶ先の目印
                                    JPEyebrowLine(section.title, trailing: SpotPrefectureIndex.countLabel(section.spots.count))
                                        .padding(.top, JPSpace.l)
                                        .padding(.bottom, JPSpace.xs)
                                        .id(section.id)
                                }
                                ForEach(section.spots) { row in
                                    NavigationLink {
                                        OfficialSpotView(spot: row.spot, spots: source, photos: photos,
                                                         photosKnown: photosKnown)
                                    } label: {
                                        OfficialSpotRow(row: row, photosKnown: photosKnown)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("spotIndex.row")
                                    .onAppear {
                                        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
                                        let next = depth.seen(index, query: query, category: nil)
                                        if next != depth { depth = next }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, JPSpace.gutter)
                    .padding(.top, JPSpace.xs)
                    .padding(.bottom, JPSpace.xl)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .webScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { location.locateIfAllowed() }
        .task {
            // 別名と写真の結びは控えから返る（無ければ1度だけ取る）。取れなければ名前と spotId だけで当てる
            links = await environment.spots.fetchPhotoLinks()
            aliases = await environment.spots.fetchAliases()
        }
        // 見えた所までの行の詳細（丸の写真）。重ねたら鍵が空になって止まる
        .task(id: SpotDetailNeeds.key(needs)) {
            guard !needs.isEmpty else { return }
            let merged = await environment.spots.withDetails(source, for: needs)
            guard !Task.isCancelled else { return }
            detailed = SpotDetailNeeds.overlay(detailed ?? spots, with: merged)
        }
    }

    /// この画面に出す段（県の一覧はその県だけ、全国は撮影スポットのある段を北から）
    nonisolated static func shown(_ sections: [RegionList.Section], scope: Scope) -> [RegionList.Section] {
        let national = SpotPrefectureIndex.nationalSections(sections)
        switch scope {
        case .all: return national
        case .prefecture(let name): return national.filter { $0.key == .prefecture(name) }
        }
    }

    /// 地方へ跳ぶチップ（探すの種類のチップと同じ `PillChip`・横に送る）
    private func jumpChips(_ jumps: [SpotPrefectureIndex.Jump], proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(jumps) { jump in
                    PillChip(title: jump.title, selected: jumped == jump.id) {
                        jumped = jump.id
                        withAnimation { proxy.scrollTo(jump.target, anchor: .top) }
                    }
                    .accessibilityIdentifier("spotIndex.jump")
                }
            }
            .padding(.horizontal, JPSpace.gutter)
        }
        .padding(.vertical, -PillChip.tapSlack)
    }
}
