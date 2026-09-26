import SwiftUI

/// 探す。写真（題・撮影地・タグ）と人の両方を1画面で。
struct SearchView: View {

    /// 見出しはどの画面でも同じ（`AppHeaderItems`）。未読の数と、
    /// お知らせを開く口は `RootView` が持っている
    var unread: Int = 0
    var avatarURL: URL?
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
                // **何も打っていないときは、絞りごとの入口**（板 11）。
                // 「すべて」は発見の顔、「写真」は新しい順の全部、「タグ」「撮影地」は
                // 選べる一覧、「人」は探し方の案内。打ち始めたら結果に切り替わる
                if query.isEmpty {
                    browse
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
        .toolbar { AppHeaderItems(unread: unread, avatarURL: avatarURL, onOpenNotifications: onOpenNotifications) }
        .task { await model.loadPhotos(environment: environment) }
        .onChange(of: query) { _, newValue in
            Task { await model.search(newValue, environment: environment) }
        }
        // 絞りを変えたら、打ってある語で当て直す（人を聞きに行くかも変わる）
        .onChange(of: model.scope) { _, _ in
            Task { await model.search(query, environment: environment) }
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
    /// **並び替えの印は置かない**（板どおりに外した。結果は新しい順）
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WebTheme.faint)
                .accessibilityHidden(true)
            TextField(L("写真を検索（題・説明・タグなど）", "Search photos"),
                      text: $query)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(WebTheme.foreground)
                .submitLabel(.search)
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

    /// 絞り（板 11: すべて / 写真 / 人 / タグ / 撮影地）。選んでいる札は白地に墨の字
    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { scope in
                    let selected = model.scope == scope
                    Button {
                        model.scope = scope
                    } label: {
                        Text(scope.label)
                            .font(.footnote.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? WebTheme.accentText : Color.white.opacity(0.82))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(selected ? Color.white.opacity(0.92) : Color.white.opacity(0.05),
                                        in: Capsule())
                            .overlay(Capsule().strokeBorder(
                                selected ? Color.white.opacity(0.92) : Color.white.opacity(0.10),
                                lineWidth: 1))
                            // 見た目は 36pt、押せる高さは 44pt
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("search.scope.\(scope.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// 何も打っていないときの中身。**どの札を押しても何かが出る**（押して何も
    /// 変わらない札を作らない）
    @ViewBuilder
    private var browse: some View {
        switch model.scope {
        case .all:
            // 板 11 の並び: 注目スポット → おすすめ → 色 → いまの季節 → 機材（段の間 20pt）
            VStack(alignment: .leading, spacing: 20) {
                popularSpots
                featured
                colors
                seasonal
                gear
            }
        case .photos:
            SearchGrid(photos: model.shown)
        case .people:
            hint(L("名前やユーザー名で探せます", "Search by name or username"))
        case .tags:
            tagChips
        case .places:
            placeRows
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(WebTheme.faint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    /// 「タグ」の絞りで何も打っていないとき: 使われているタグを多い順に、枚数を添えて
    /// （押す前に手応えが分かる）。押すとそのタグで当てる
    @ViewBuilder
    private var tagChips: some View {
        if model.tagCounts.isEmpty {
            hint(L("タグの付いた写真はまだありません", "No tagged photos yet"))
        } else {
            listCard(model.tagCounts.map { (id: $0.tag, title: "#\($0.tag)", count: $0.count) }) { row in
                query = row.id
            }
        }
    }

    /// 「撮影地」の絞りで何も打っていないとき: 撮影地を写真の多い順に。押すと
    /// 注目スポットと同じ行き先（2枚以上の地点はスポットの画面）
    @ViewBuilder
    private var placeRows: some View {
        if model.places.isEmpty {
            hint(L("撮影地の分かる写真はまだありません", "No photos with a place yet"))
        } else {
            cardBox {
                ForEach(Array(model.places.enumerated()), id: \.element.id) { index, spot in
                    spotLink(spot) {
                        listRow(title: spot.id, count: spot.count, divider: index > 0)
                    }
                }
            }
        }
    }

    /// 札の中の行の並び（板 11 の「機材から探す」と同じ形）
    private func listCard(_ rows: [(id: String, title: String, count: Int)],
                          action: @escaping ((id: String, title: String, count: Int)) -> Void) -> some View {
        cardBox {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button { action(row) } label: {
                    listRow(title: row.title, count: row.count, divider: index > 0)
                }
                .buttonStyle(.plain)
                // 読み上げは「#」を除いて（「シャープ」と読ませない）
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("\(row.id)、\(row.count)枚", "\(row.id), \(row.count) photos"))
                .accessibilityAddTraits(.isButton)
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

    // MARK: - 発見

    /// 注目スポット（板 11: 156×116・角丸 14 の札を横に。下に黒へ溶かして名前 13px と
    /// 等幅 10px の枚数）。**写真から数えた件数**を出す——場所そのものの台帳の数
    /// （「富士山 12,421件」）は持っていない。この写真たちの中で何枚あるかなら正確に言える
    @ViewBuilder
    private var popularSpots: some View {
        let spots = model.popularSpots
        if !spots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("注目スポット", "Featured places"))
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

    /// おすすめ（板 11:「おすすめ · カテゴリ名」・120×160 の写真を3枚）。
    ///
    /// **中身は owner が手で選んだ写真**（`featured`・`FeaturedGroups`）。いちばん
    /// 多いカテゴリの塊を出す。カテゴリの丸い札を外したので、カテゴリの入口はここと
    /// 「すべて見る」の先（集約ページ）になる。選んだ写真が無ければ出さない
    @ViewBuilder
    private var featured: some View {
        if let group = model.featured {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("おすすめ · \(group.label)", "Picks · \(group.label)")) {
                    NavigationLink {
                        TagPhotosView(kind: .category(group.id))
                    } label: {
                        seeAll(L("すべて見る", "See all"))
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(group.photos.prefix(3)) { photo in
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

    /// いまの季節の写真（板 11: 3列の格子・端まで・隙間 4・角なし）。
    /// **「おすすめ」とは書かない**——推薦の口は無く、中身は「いまの季節のタグが
    /// 付いた写真」そのもの。4枚以上あれば「すべて」で全部を並べる
    @ViewBuilder
    private var seasonal: some View {
        let photos = model.seasonal
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("いまの季節の写真", "This season")) {
                    if photos.count > 3 {
                        NavigationLink {
                            SeasonalPhotosView(photos: photos)
                        } label: {
                            seeAll(L("すべて", "All"))
                        }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
                          spacing: 4) {
                    ForEach(photos.prefix(3)) { photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo, context: photos)
                        } label: {
                            PhotoFrame(photo: photo, corner: 0)
                        }
                        .buttonStyle(.plain)
                    }
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

    /// 色から探す（板 11: 56pt の丸に代表の写真・下に 11px の名前・5つを均等に）。
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
                HStack(alignment: .top, spacing: 0) {
                    ForEach(sections) { section in
                        NavigationLink {
                            ColorPhotosView(section: section)
                        } label: {
                            VStack(spacing: 6) {
                                RemoteImage(url: section.photos.first?.gridImageURL,
                                            alignment: section.photos.first?.gridAlignment ?? .center)
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                                // 板 11 の名前（空・海／森・自然…）は `note` の方
                                Text(section.family.note)
                                    .font(.caption2)
                                    .foregroundStyle(WebTheme.muted2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("\(section.family.note)、\(section.count)枚",
                                              "\(section.family.note), \(section.count) photos"))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// 機材から探す（板 11: 行を束ねた札・印・名前・枚数・矢印）。
    ///
    /// **分け方は焦点距離のまま**（owner の判断で札の形だけ板に寄せた）。
    /// レンズ名で分けないのは、ズーム1本が広角も望遠も撮れるから。
    /// 分け方を隠さないよう、名前の横に「〜35mm」を添える
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
                            listRow(title: "\(section.group.label)（\(section.group.range)）",
                                    count: section.count, divider: index > 0,
                                    systemImage: "camera.aperture")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 段の見出し（板 11: 12px・medium・白60%・字間 0.04em、右に小さな行き先）
    private func sectionHeader<Trailing: View>(_ title: String,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.medium))
                .tracking(0.5)
                .foregroundStyle(WebTheme.faint)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 20)
    }

    private func sectionHeader(_ title: String) -> some View {
        sectionHeader(title) { EmptyView() }
    }

    /// 見出しの右の「すべて見る」（板 11: 12px・白72%・矢印）
    private func seeAll(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium))
        }
        .font(.caption)
        .foregroundStyle(WebTheme.muted2)
        // 見た目は板の 28pt（見出しの行を段ごとに高くしない）、押せる高さは 44pt
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
            // **件数は結果の上**。並び替えは置かない（板 11。新しい順）
            Text(L("写真 \(model.shown.count) 件", "\(model.shown.count) photos"))
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
                .padding(.horizontal, 16)
            if model.shown.isEmpty {
                hint(L("見つかりませんでした", "No results"))
            } else {
                SearchGrid(photos: model.shown)
            }
        } else if users.isEmpty && model.peopleSearched {
            // **聞き終わってから言う**（待ちの間や取り消しの直後に一瞬出さない）
            hint(L("見つかりませんでした", "No results"))
        }
    }
}
@MainActor
final class SearchViewModel: ObservableObject {

    @Published private(set) var photos: [Photo] = []
    @Published private(set) var users: [UserProfile] = []
    @Published private(set) var isSearching = false
    /// いまの語で人を聞き終えたか（「見つかりませんでした」を出してよいか）
    @Published private(set) var peopleSearched = false
    /// 使われているタグと枚数（「タグ」の絞りの一覧）
    @Published private(set) var tagCounts: [(tag: String, count: Int)] = []
    /// 撮影地と枚数（「撮影地」の絞りの一覧）。写真の多い順
    @Published private(set) var places: [DiscoverySections.Spot] = []
    /// 発見の塊（モック2）
    @Published private(set) var popularSpots: [DiscoverySections.Spot] = []
    @Published private(set) var seasonal: [Photo] = []
    /// owner が選んだおすすめの、いちばん多いカテゴリの塊（板 11 の「おすすめ · カテゴリ」）
    @Published private(set) var featured: FeaturedGroups.Group?
    /// 機材から探す（モック9）。**焦点距離で分ける**——レンズ名では
    /// ズーム1本が広角も望遠も含んでしまう
    @Published private(set) var gear: [GearGroups.Section] = []
    /// 色から探す（モック9-5）
    @Published private(set) var colors: [ColorFamilies.Section] = []
    /// 絞り（板 11）
    @Published var scope: SearchScope = .all

    /// 画面に出す写真。**打っていないときは全部**（「写真」の絞りの一覧）。
    /// 並びは新しい順（並び替えは板どおりに外した）
    var shown: [Photo] {
        GallerySort.new.apply(query.isEmpty ? allPhotos : photos)
    }

    /// いま打っている文字（`shown` の出し分けに使う）
    private var query = ""

    /// 読み込んだ写真そのもの。**スポットの画面に渡す**
    /// ——`shown` は絞り込んだあとなので、突き合わせ（近くの地点など）に
    /// 使うと、絞った瞬間に「近く」が消える
    var everything: [Photo] { allPhotos }

    private var allPhotos: [Photo] = []
    /// 打つたびに投げない。**最後の打鍵から少し待つ**
    private var searchTask: Task<Void, Never>?

    func loadPhotos(environment: AppEnvironment) async {
        guard allPhotos.isEmpty else { return }
        await reloadPhotos(environment: environment)
    }

    /// 控えがあっても読み直す。**ブロック／通報のあとに使う**
    /// ——`loadPhotos` は一度読んだら二度と読まないので、そのままだと
    /// ブロックした相手の写真が検索結果に残り続ける。
    func reloadPhotos(environment: AppEnvironment) async {
        allPhotos = (try? await environment.gallery.fetchPhotos()) ?? []
        tagCounts = PhotoQuery.tagCounts(in: allPhotos, limit: 40)
        places = DiscoverySections.popularSpots(in: allPhotos, limit: 40)
        popularSpots = DiscoverySections.popularSpots(in: allPhotos)
        seasonal = DiscoverySections.seasonal(in: allPhotos, limit: 60)
        featured = FeaturedGroups.groups(from: allPhotos).first
        // **12枚で切らない**——行の「N枚」と、押した先の一覧を実際の枚数にする
        // （既定の 12 で切ると、13枚以上ある群でも「12枚」と出て先も12枚だった）
        gear = GearGroups.sections(in: allPhotos, limit: .max)
        colors = ColorFamilies.sections(in: allPhotos, limit: .max)
        photos = []
    }

    func search(_ query: String, environment: AppEnvironment) async {
        searchTask?.cancel()
        self.query = query
        peopleSearched = false
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            photos = []
            users = []
            return
        }
        // 写真は手元の一覧から即座に絞る（往復しない）。どの欄で当てるかは絞りで変わる
        photos = scope.match(allPhotos, query: trimmed)
        // **人を出さない絞りでは聞きに行かない**
        guard scope.showsPeople else {
            users = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = try? await environment.search.search(query: trimmed)
            // **取り消された回は書き込まない**（前の語の人が新しい語の下に出る）
            guard !Task.isCancelled else { return }
            isSearching = false
            users = found ?? []
            peopleSearched = true
        }
    }
}

