import SwiftUI

/// 探す。写真（題・撮影地・タグ）と人の両方を1画面で。
struct SearchView: View {

    /// 見出しはどの画面でも同じ（`AppHeaderItems`）。未読の数と、
    /// お知らせを開く口は `RootView` が持っている
    var unread: Int = 0
    var onOpenNotifications: () -> Void = {}

    @EnvironmentObject private var environment: AppEnvironment
    /// **「見せない」が変わったら控えを捨てるため**に見ている
    @EnvironmentObject private var hidden: ModerationStore
    @StateObject private var model = SearchViewModel()
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                scopeChips
                // **何も打っていないときは種類ごとの入口**（`SearchScope.entry`）。
                // 打ち始めたら結果に切り替わる。**空白だけは打っていない扱い**
                // （モデルの `search` も空白を落としてから判定している）
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    entry
                } else {
                    results
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationTitle(Labels.Navigation.searchTab)  // 見た目はロゴ（AppHeaderItems）。この字は次の画面の「戻る」と読み上げに使う
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { AppHeaderItems(unread: unread, onOpenNotifications: onOpenNotifications) }
        .task { await model.loadPhotos(environment: environment) }
        .onChange(of: query) { _, newValue in
            Task { await model.search(newValue, environment: environment) }
        }
        // **ブロック／通報の直後に消す。** `loadPhotos` は
        // `guard allPhotos.isEmpty` で二度と読まない作りなので、
        // 控えを捨ててから読み直す
        .onChange(of: hidden.revision) { _, _ in
            Task {
                await environment.gallery.setHidden(userIds: hidden.blockedUserIds,
                                                    photoIds: hidden.reportedPhotoIds)
                await model.reloadPhotos(environment: environment)
                await model.search(query, environment: environment)
            }
        }
    }

    // MARK: - 探す口

    /// 検索の欄（板 11: 高さ 44・角丸 12・白8% の地に白6% の縁・15px）。
    /// **並び替えの印は置かない**（板に無い・owner 了承済み。結果は新しい順）
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WebTheme.faint)
                .accessibilityHidden(true)
            TextField(model.scope.prompt, text: $query)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(WebTheme.foreground)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WebTheme.faint)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("消す", "Clear"))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, query.isEmpty ? 14 : 0)
        .frame(height: 44)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    /// 種類（板 11 の「すべて／写真／人／タグ／撮影地」）。
    /// **いまの検索の中身を種類で絞る**（`SearchScope`）——新しい検索は増やさない
    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { scope in
                    PillChip(title: scope.label, selected: model.scope == scope) {
                        model.select(scope: scope)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 何も打っていないとき

    @ViewBuilder
    private var entry: some View {
        if model.scope.showsPhotos {
            // 写真に頼る入口は、**読み込み中・失敗を「0枚」と言わない**
            photosLoaded { entryContent }
        } else {
            entryContent
        }
    }

    /// 写真の読み込みの状態で出し分ける。読み終えたときだけ中身を描く
    @ViewBuilder
    private func photosLoaded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        switch model.loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        case .failed:
            ErrorBanner(message: Labels.Common.loadFailed) {
                Task { await model.reloadPhotos(environment: environment) }
            }
        case .loaded:
            content()
        }
    }

    @ViewBuilder
    private var entryContent: some View {
        switch model.scope.entry {
        case .discovery:
            // 「発見」の顔（モック2）。段の並びは板 11（`SearchDiscovery`）・段の間は 20pt。
            // 読み終えて段が1つも無いときは真っ白にしない
            if model.discovery.isEmpty {
                hint(L("写真はまだありません", "No photos yet"))
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(model.discovery) { section in
                        discoverySection(section)
                    }
                }
            }
        case .photoGrid:
            // `shown` は打っていないとき全部（新しい順）。**読み込み前に切り替えても
            // 読み終えた時点で埋まる**——`allPhotos` と `query` から毎回導く
            if model.shown.isEmpty {
                hint(L("写真はまだありません", "No photos yet"))
            } else {
                SearchGrid(photos: model.shown)
            }
        case .peopleHint:
            hint(L("名前を入れると人を探せます", "Type a name to find people"))
        case .tagRows:
            if model.tagCounts.isEmpty {
                hint(L("タグの付いた写真はまだありません", "No tagged photos yet"))
            } else {
                cardBox {
                    ForEach(Array(model.tagCounts.enumerated()), id: \.element.tag) { index, row in
                        Button {
                            query = row.tag
                        } label: {
                            listRow(title: "#\(row.tag)", count: row.count, divider: index > 0)
                        }
                        .buttonStyle(.plain)
                        // 読み上げは「#」を除いて（「シャープ」と読ませない）
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("\(row.tag)、\(row.count)枚", "\(row.tag), \(row.count) photos"))
                        .accessibilityAddTraits(.isButton)
                    }
                }
            }
        case .placeRows:
            if model.places.isEmpty {
                hint(L("撮影地の分かる写真はまだありません", "No photos with a place yet"))
            } else {
                // 行き先は注目スポットと同じ（2枚以上の地点はスポットの画面）
                cardBox {
                    ForEach(Array(model.places.enumerated()), id: \.element.id) { index, spot in
                        spotLink(spot) {
                            listRow(title: spot.id, count: spot.count, divider: index > 0)
                        }
                    }
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(WebTheme.faint)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
    }

    // MARK: - 発見

    @ViewBuilder
    private func discoverySection(_ section: SearchDiscovery.Section) -> some View {
        switch section {
        case .spots: popularSpots
        case .featured: featured
        case .colors: colors
        case .seasonal: seasonal
        case .gear: gear
        }
    }

    /// 注目スポット（板 11: 156×116・角丸 14 の札を横に。下に黒へ溶かして名前 13px と
    /// 等幅 10px の枚数）。**写真から数えた件数**を出す。
    ///
    /// モックの「富士山 12,421件」のような数は、場所そのものの台帳が
    /// 無いので出せない（`api-user` に場所のマスタは無い）。
    /// **この写真たちの中で何枚あるか**なら正確に言える。
    @ViewBuilder
    private var popularSpots: some View {
        let spots = model.popularSpots
        if !spots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("注目スポット", "Featured places")) {
                    // 行き先はマップの札（板 11）。撮影地のピンが並ぶ
                    Button {
                        TabRouter.shared.openMap()
                    } label: {
                        moreLabel(L("地図で見る", "View on map"))
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(spots) { spot in
                            spotLink(spot) { spotCard(spot) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    /// 「注目スポット」の札の行き先。
    ///
    /// **2枚以上ある地点は、スポットの画面へ**（モック5）。この札が
    /// 指しているのは写真ではなく**場所**で、スポットの画面はその場所の
    /// 写真も並べる（`spotPhotos`）ので、集約へ行くより出るものが多い。
    ///
    /// 🔴 **ここを繋ぐまで、モック5 は誰にも出なかった。** 入口は
    /// 写真の詳細と地図のピンの2つだけで、どちらも「開いた写真の撮影地に
    /// 2枚以上あるか」「ピンをうまく押せるか」に左右される。実際 run 54 の
    /// 巡回では、いちばん新しい写真の撮影地（三条市, 日本）が1枚だったので
    /// 導線が出ず、**実機の絵を1枚も撮れなかった**。
    ///
    /// 1枚だけの地点は今までどおり集約（`TagPhotosView`）へ。
    @ViewBuilder
    private func spotLink<Label: View>(_ spot: DiscoverySections.Spot,
                                       @ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            if let place = DerivedSpot.openable(spot.id, in: model.everything) {
                SpotDetailView(spot: place, photos: model.everything)
            } else {
                TagPhotosView(kind: .location(spot.id))
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
        .accessibilityIdentifier("search.spot")
    }

    /// 季節のおすすめ（モック2）。**いまの季節のタグ**から新しい順に。
    /// 板 11: 3列×1段・端まで・隙間 4・角なし。「すべて →」で全部（形は板 12）
    @ViewBuilder
    private var seasonal: some View {
        let photos = model.seasonal
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // モックの「今週末に行きたい場所」にあたる棚。
                // **「おすすめ」とは書かない**——推薦の口は無く、
                // 中身は「いまの季節のタグが付いた写真」そのもの
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader(L("いまの季節の写真", "This season")) {
                        NavigationLink {
                            CollectionPhotosScreen(title: L("いまの季節の写真", "This season"),
                                                   note: model.seasonalNote,
                                                   photos: model.seasonalAll)
                        } label: {
                            moreLabel(L("すべて", "All"))
                        }
                        .buttonStyle(.plain)
                    }
                    Text(L("いまの季節のタグが付いた写真から", "Photos tagged for this season"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .padding(.horizontal, 20)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WebTheme.gridSpacing),
                                         count: 3),
                          spacing: WebTheme.gridSpacing) {
                    ForEach(photos) { photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo, context: model.seasonalAll)
                        } label: {
                            PhotoFrame(photo: photo, aspect: 1, corner: 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// おすすめ · [カテゴリ名]（板 11: 120×160 の写真を3枚・隙間 4・角なし）。
    /// **ホームと同じ塊**（`FeaturedGroups`）の先頭の1つ。
    /// 「すべて見る」の行き先もホームと同じそのカテゴリの集約
    @ViewBuilder
    private var featured: some View {
        if let group = model.featured {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("おすすめ · \(group.label)", "Picks · \(group.label)")) {
                    NavigationLink {
                        TagPhotosView(kind: .category(group.id))
                    } label: {
                        moreLabel(L("すべて見る", "See all"))
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WebTheme.gridSpacing) {
                        ForEach(group.photos.prefix(SearchDiscovery.featuredPreview)) { photo in
                            NavigationLink {
                                PhotoDetailView(photo: photo, context: group.photos)
                            } label: {
                                PhotoFrame(photo: photo, aspect: 3.0 / 4.0, corner: 0)
                                    .frame(width: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    /// 撮影地の札（板 11: 156×116・角丸 14）。**枚数は数えたもの**
    private func spotCard(_ spot: DiscoverySections.Spot) -> some View {
        Color.clear
            .frame(width: 156, height: 116)
            .overlay {
                RemoteImage(url: spot.cover.gridImageURL, alignment: spot.cover.gridAlignment)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.id)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(L("\(spot.count)枚の写真", "\(spot.count) photos"))
                        .font(JPFont.mono(10, relativeTo: .caption2))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .padding(.horizontal, 12)
                .padding(.top, 28)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 色から探す（モック9-5）。
    ///
    /// **色を持たない写真は出さない。** 代表色はアップロードのときに
    /// 計算して保存するもので、持っていない写真は「色が分からない」の
    /// であって「黒い」のではない。
    @ViewBuilder
    private var colors: some View {
        let sections = model.colors
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("色から探す", "Browse by colour"))
                // 丸い写真に名前（板 11）。**5つを横に割り付ける**——色味は最大5つ
                HStack(alignment: .top, spacing: 0) {
                    ForEach(sections) { section in
                        NavigationLink {
                            ColorPhotosView(section: section)
                        } label: {
                            colorCircle(section)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func colorCircle(_ section: ColorFamilies.Section) -> some View {
        VStack(spacing: 6) {
            RemoteImage(url: section.photos.first?.gridImageURL,
                        alignment: section.photos.first?.gridAlignment ?? .center)
                .frame(width: 56, height: 56)
                .background(WebTheme.surface, in: Circle())
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            Text(section.family.note)
                .font(.caption2)
                .foregroundStyle(WebTheme.muted2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ColorFamilies.accessibilityLabel(section.family, count: section.count))
    }

    /// 機材から探す（板 11: 行を束ねた札・印・名前・枚数・矢印）。
    ///
    /// **分け方は焦点距離のまま**（札の形だけ板に寄せた）。
    /// レンズ名で分けないのは、ズーム1本が広角も望遠も撮れるから。
    /// **分け方を隠さない**——名前の横に「〜35mm」を添える
    @ViewBuilder
    private var gear: some View {
        let sections = model.gear
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("機材から探す", "Browse by gear"))
                cardBox {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        NavigationLink {
                            GearPhotosView(section: section)
                        } label: {
                            listRow(title: L("\(section.group.label)（\(section.group.range)）",
                                             "\(section.group.label) (\(section.group.range))"),
                                    count: section.count, divider: index > 0,
                                    systemImage: "camera.aperture")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 行を束ねる札（板 11: 角丸 16・白7% の地・白8% の縁）
    private func cardBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
    }

    /// 1行（板 11: 高さ 54・15px の名前・等幅 13px の枚数・右に矢印・上に 8% の線）
    private func listRow(title: String, count: Int, divider: Bool,
                         systemImage: String? = nil) -> some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(WebTheme.muted2)
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(WebTheme.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L("\(count)枚", "\(count)"))
                .font(JPFont.mono(13, relativeTo: .footnote))
                .foregroundStyle(WebTheme.faint)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .overlay(alignment: .top) {
            if divider {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private func sectionHeader(_ title: String) -> some View {
        sectionHeader(title) { EmptyView() }
    }

    /// 段の見出し（板 11: 12px・medium・白60%・字間 0.04em）。
    /// 右端に「地図で見る →」「すべて見る →」を置ける
    private func sectionHeader<Trailing: View>(_ title: String,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .tracking(12 * 0.04)
                .foregroundStyle(WebTheme.faint)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        // 板は本文の 16 からさらに 4 内へ
        .padding(.horizontal, 20)
    }

    /// 見出しの右の「すべて見る →」（板 11: 12px・白72%）。
    /// 見た目は板の 28pt（見出しの行を段ごとに高くしない）、押せる高さは 44pt
    private func moreLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "arrow.right")
                .accessibilityHidden(true)
        }
        .font(.system(size: 12))
        .foregroundStyle(WebTheme.muted2)
        .frame(minHeight: 28)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .padding(.vertical, -8)
    }

    // MARK: - 結果

    @ViewBuilder
    private var results: some View {
        // 人は写真より先に出す（名前で探しているなら、それが目当て）。
        // ブロックした人は出さない（`/users/search` はブロックを知らない）
        let users = model.scope.showsPeople
            ? BlockFilter.users(model.users, blocked: hidden.blockedUserIds) : []
        if !users.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("人", "People"))
                    .font(.headline)
                    .foregroundStyle(WebTheme.foreground)
                ForEach(users) { user in
                    NavigationLink {
                        UserProfileView(userId: user.userId)
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: user.avatarURL(),
                                        placeholderSymbol: "person.crop.circle.fill")
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            Text(user.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WebTheme.foreground)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(WebTheme.faint)
                        }
                        .frame(minHeight: WebTheme.minTapTarget)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }

        if model.scope.showsPhotos {
            photosLoaded { photoResults }
        } else if users.isEmpty {
            // 人だけを探しているとき（打つ前の案内は `entry` の側）
            hint(model.isSearching ? L("探しています…", "Searching…") : L("見つかりませんでした", "No results"))
        }
    }

    @ViewBuilder
    private var photoResults: some View {
        // **件数は結果の上**。並び替えは置かない（板 11 に無い。新しい順）
        Text(L("検索結果: \(model.shown.count) 件", "\(model.shown.count) results"))
            .font(.subheadline)
            .foregroundStyle(WebTheme.muted2)
            .padding(.horizontal, 16)

        if model.shown.isEmpty {
            // 打つ前の顔は `entry` の側。ここは打ったあとだけ
            hint(L("見つかりませんでした", "No results"))
        } else {
            SearchGrid(photos: model.shown)
        }
    }
}

@MainActor
final class SearchViewModel: ObservableObject {

    @Published private(set) var users: [UserProfile] = []
    @Published private(set) var isSearching = false
    /// 写真の読み込みの状態。**読み込み前・失敗を「0枚」と取り違えない**
    enum LoadState: Equatable { case loading, failed, loaded }
    @Published private(set) var loadState: LoadState = .loading
    /// 「タグ」の入口: 決まったタグと枚数（`PhotoQuery.tagCounts`・多い順）
    @Published private(set) var tagCounts: [(tag: String, count: Int)] = []
    /// 「撮影地」の入口: 撮影地と枚数（写真の多い順）
    @Published private(set) var places: [DiscoverySections.Spot] = []
    /// 発見の塊（モック2）
    @Published private(set) var popularSpots: [DiscoverySections.Spot] = []
    /// 格子に出す数だけ（`SearchDiscovery.seasonalPreview`）
    @Published private(set) var seasonal: [Photo] = []
    /// 「すべて →」の先に並べる全部
    @Published private(set) var seasonalAll: [Photo] = []
    /// おすすめ · [カテゴリ名]（板 11）
    @Published private(set) var featured: FeaturedGroups.Group?
    /// 種類チップ（板 11）
    @Published private(set) var scope: SearchScope = .all
    /// 機材から探す（モック9）。**焦点距離で分ける**——レンズ名では
    /// ズーム1本が広角も望遠も含んでしまう
    @Published private(set) var gear: [GearGroups.Section] = []
    /// 色から探す（モック9-5）
    @Published private(set) var colors: [ColorFamilies.Section] = []

    /// 画面に出す写真。**打っていないときも空にしない**
    /// ——探しに来た人を手ぶらで帰さない。
    /// 打っていないときは全部（タグ／撮影地はその欄を持つ写真）、
    /// 打っているときは種類ごとの欄に当てる（`SearchScope`）。
    /// 並びは新しい順（並び替えは板 11 に無いので外した）
    var shown: [Photo] {
        GallerySort.new.apply(scope.photos(allPhotos, query: query))
    }

    /// いま打っている文字（`shown` の出し分けに使う）。
    /// **変わったら描き直す**——写真の絞り込みはここから導く
    @Published private var query = ""

    /// 発見の段（板 11 の並び）。中身の無い段は出さない
    var discovery: [SearchDiscovery.Section] {
        var present = Set<SearchDiscovery.Section>()
        if !popularSpots.isEmpty { present.insert(.spots) }
        if featured != nil { present.insert(.featured) }
        if !colors.isEmpty { present.insert(.colors) }
        if !seasonal.isEmpty { present.insert(.seasonal) }
        if !gear.isEmpty { present.insert(.gear) }
        return SearchDiscovery.sections(present: present)
    }

    /// 「いまの季節の写真」の先の小さい字（どのタグで集めたかを隠さない）
    var seasonalNote: String {
        DiscoverySections.seasonalTags().map { "#\($0)" }.joined(separator: " ")
    }

    func select(scope: SearchScope) { self.scope = scope }

    /// 読み込んだ写真そのもの。**スポットの画面に渡す**
    /// ——`shown` は絞り込んだあとなので、突き合わせ（近くの地点など）に
    /// 使うと、絞った瞬間に「近く」が消える
    var everything: [Photo] { allPhotos }

    private var allPhotos: [Photo] = []
    /// 打つたびに投げない。**最後の打鍵から少し待つ**
    private var searchTask: Task<Void, Never>?
    /// 何回目の検索か。**返事を反映してよいのは、いちばん新しい回だけ**
    /// ——取り消した回の返事が後から届いても捨てる
    private var searchGeneration = 0

    func loadPhotos(environment: AppEnvironment) async {
        guard allPhotos.isEmpty else { return }
        await reloadPhotos(environment: environment)
    }

    /// 控えがあっても読み直す。**ブロック／通報のあとに使う**
    /// ——`loadPhotos` は一度読んだら二度と読まないので、そのままだと
    /// ブロックした相手の写真が検索結果に残り続ける。
    func reloadPhotos(environment: AppEnvironment) async {
        let gallery = environment.gallery
        await reloadPhotos { try await gallery.fetchPhotos() }
    }

    /// 読み直しの本体。**引き先を差し替えられる**（テストで失敗を起こすため）。
    /// 失敗したら写真は空にしたうえで `.failed` にする——空のまま「まだありません」と
    /// 言わない。空にするのは、ブロックのあとの読み直しで古い写真を残さないため
    func reloadPhotos(fetch: @MainActor () async throws -> [Photo]) async {
        if allPhotos.isEmpty { loadState = .loading }
        do {
            apply(photos: try await fetch())
        } catch {
            apply(photos: [])
            loadState = .failed
        }
    }

    /// 読み込んだ写真から段を作る。**通信と切り離してある**（テストで中身を直接渡す）
    func apply(photos: [Photo]) {
        allPhotos = photos
        loadState = .loaded
        tagCounts = PhotoQuery.tagCounts(in: allPhotos, limit: .max)
        places = DiscoverySections.popularSpots(in: allPhotos, limit: SearchDiscovery.placeRows)
        popularSpots = DiscoverySections.popularSpots(in: allPhotos)
        seasonalAll = DiscoverySections.seasonal(in: allPhotos, limit: .max)
        seasonal = Array(seasonalAll.prefix(SearchDiscovery.seasonalPreview))
        featured = SearchDiscovery.featured(in: allPhotos)
        // **枚数で切らない**（`limit: .max`）。行の「N枚」と押した先の一覧は
        // この section の写真そのものなので、既定の12で切ると13枚目から先が
        // 数えられず、押しても出てこない
        gear = GearGroups.sections(in: allPhotos, limit: .max)
        colors = ColorFamilies.sections(in: allPhotos, limit: .max)
    }

    func search(_ query: String, environment: AppEnvironment) async {
        let service = environment.search
        await search(query) { try await service.search(query: $0) }
    }

    /// 人の検索の本体。**引き先を差し替えられる**（テストで返事の順を操るため）。
    ///
    /// - 待ちの間（打鍵のあとの 300ms）も**探している扱い**にする。
    ///   そうしないと、その間だけ「見つかりませんでした」がちらつく
    /// - 返事を反映するのは**いちばん新しい回だけ**。取り消した回の返事が
    ///   後から届いて人の一覧を上書きしたり、新しい回の途中で
    ///   「探しています…」を消したりしない
    /// - 空にしたら人の一覧も空にする（前の語の人を残さない）
    func search(_ query: String,
                debounce: Duration = .milliseconds(300),
                fetchUsers: @escaping @MainActor (String) async throws -> [UserProfile]) async {
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        self.query = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            users = []
            isSearching = false
            return
        }
        // 写真は手元の一覧から即座に絞る（往復しない・`shown` が `query` から導く）

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            let found = (try? await fetchUsers(trimmed)) ?? []
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            users = found
            isSearching = false
        }
    }

}
