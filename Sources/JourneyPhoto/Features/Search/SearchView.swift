import SwiftUI

/// 探す。写真（題・撮影地・タグ）と人の両方を1画面で。
struct SearchView: View {

    @EnvironmentObject private var environment: AppEnvironment
    /// **「見せない」が変わったら控えを捨てるため**に見ている
    @EnvironmentObject private var hidden: ModerationStore
    @StateObject private var model = SearchViewModel()
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                categoryChips
                tagChips
                // **何も打っていないときは「発見」の顔**（モック2）。
                // 打ち始めたら結果に切り替わる
                if query.isEmpty && model.category == nil {
                    popularSpots
                    seasonal
                    gear
                }
                results
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationTitle(L("さがす", "Search"))
        .navigationBarTitleDisplayMode(.inline)
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

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WebTheme.faint)
            TextField(L("写真を検索（題・説明・タグなど）", "Search photos"),
                      text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(WebTheme.foreground)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WebTheme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("消す", "Clear"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(WebTheme.surface, in: Capsule())
        .padding(.horizontal, 16)
    }

    /// カテゴリ。**「すべて」を先頭に置く**（戻れない絞り込みを作らない）
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(L("すべて", "All"), selected: model.category == nil) {
                    model.select(category: nil)
                }
                ForEach(model.categories, id: \.self) { category in
                    chip(Labels.Category.name(category),
                         selected: model.category.map {
                             CategoryChoices.isChosen(current: $0, choice: category)
                         } ?? false) {
                        model.select(category: category)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// タグ。**枚数を添える**（押す前に手応えが分かる）
    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.tagCounts, id: \.tag) { item in
                    chip("\(item.tag)  \(item.count)",
                         selected: TagChoices.key(query) == TagChoices.key(item.tag)) {
                        query = TagChoices.key(query) == TagChoices.key(item.tag) ? "" : item.tag
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(selected ? AnyShapeStyle(WebTheme.foreground)
                                     : AnyShapeStyle(WebTheme.surface),
                            in: Capsule())
                .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 発見

    /// 人気スポット（モック2）。**写真から数えた件数**を出す。
    ///
    /// モックの「富士山 12,421件」のような数は、場所そのものの台帳が
    /// 無いので出せない（`api-user` に場所のマスタは無い）。
    /// **この写真たちの中で何枚あるか**なら正確に言える。
    @ViewBuilder
    private var popularSpots: some View {
        let spots = model.popularSpots
        if !spots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("注目スポット", "Featured places"))
                // **大きく2枚**（モック9）。小さな正方形が並ぶより、
                // 「行ってみたい」が立ち上がる
                HStack(spacing: 10) {
                    ForEach(spots.prefix(2)) { spot in
                        NavigationLink {
                            TagPhotosView(kind: .location(spot.id))
                        } label: {
                            spotCard(spot)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                if spots.count > 2 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(spots.dropFirst(2)) { spot in
                                NavigationLink {
                                    TagPhotosView(kind: .location(spot.id))
                                } label: {
                                    spotCard(spot)
                                        .frame(width: 150)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    /// 季節のおすすめ（モック2）。**いまの季節のタグ**から新しい順に。
    @ViewBuilder
    private var seasonal: some View {
        let photos = model.seasonal
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // モックの「今週末に行きたい場所」にあたる棚。
                // **「おすすめ」とは書かない**——推薦の口は無く、
                // 中身は「いまの季節のタグが付いた写真」そのもの
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader(L("いまの季節の写真", "This season"))
                    Text(L("いまの季節のタグが付いた写真から", "Photos tagged for this season"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .padding(.horizontal, 16)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos) { photo in
                            NavigationLink {
                                PhotoDetailView(photo: photo, context: photos)
                            } label: {
                                PhotoFrame(photo: photo, aspect: 3.0 / 4.0, corner: 12)
                                    .frame(width: 128)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    /// 撮影地の札（モック9 の大きな絵）。**枚数は数えたもの**
    private func spotCard(_ spot: DiscoverySections.Spot) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                RemoteImage(url: spot.cover.gridImageURL, alignment: spot.cover.gridAlignment)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.id)
                        .font(.headline)
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(2)
                    Text(L("\(spot.count)枚の写真", "\(spot.count) photos"))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 機材から探す（モック9）。
    ///
    /// **分け方を隠さない**——見出しの下に「〜35mm」を出す。
    /// レンズ名で分けないのは、ズーム1本が広角も望遠も撮れるから。
    @ViewBuilder
    private var gear: some View {
        let sections = model.gear
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("機材から探す", "Browse by gear"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sections) { section in
                            NavigationLink {
                                GearPhotosView(section: section)
                            } label: {
                                gearCard(section)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func gearCard(_ section: GearGroups.Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    RemoteImage(url: section.photos.first?.gridImageURL,
                                alignment: section.photos.first?.gridAlignment ?? .center)
                }
                .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(section.group.label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WebTheme.foreground)
                Text(section.group.note)
                    .font(.caption)
                    .foregroundStyle(WebTheme.muted2)
                Text(L("\(section.group.range)・\(section.count)枚",
                       "\(section.group.range) · \(section.count)"))
                    .font(.caption2)
                    .foregroundStyle(WebTheme.faint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 200)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(WebTheme.foreground)
            .padding(.horizontal, 16)
    }

    // MARK: - 結果

    @ViewBuilder
    private var results: some View {
        // 人は写真より先に出す（名前で探しているなら、それが目当て）
        if !model.users.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("人", "People"))
                    .font(.headline)
                    .foregroundStyle(WebTheme.foreground)
                ForEach(model.users) { user in
                    NavigationLink {
                        UserProfileView(userId: user.userId)
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: user.avatarURL())
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

        // **件数と並び替えは結果の上**（提案の絵）
        HStack {
            Text(L("検索結果: \(model.shown.count) 件", "\(model.shown.count) results"))
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
            Spacer()
            Menu {
                ForEach(GallerySort.allCases) { option in
                    Button(option.label) { model.select(sort: option) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(model.sort.label)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
                .frame(minHeight: WebTheme.minTapTarget)
            }
        }
        .padding(.horizontal, 16)

        if model.shown.isEmpty {
            // **「まだ何も打っていない」と「見つからなかった」を分ける**
            Text(query.isEmpty
                 ? L("タグやカテゴリから探せます", "Start from a tag or a category")
                 : L("見つかりませんでした", "No results"))
                .font(.subheadline)
                .foregroundStyle(WebTheme.faint)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
        } else {
            SearchGrid(photos: model.shown)
        }
    }
}

@MainActor
final class SearchViewModel: ObservableObject {

    @Published private(set) var photos: [Photo] = []
    @Published private(set) var users: [UserProfile] = []
    @Published private(set) var popularTags: [String] = []
    @Published private(set) var isSearching = false
    /// 候補タグと枚数（提案の絵の「winter 13」）
    @Published private(set) var tagCounts: [(tag: String, count: Int)] = []
    @Published private(set) var categories: [String] = []
    /// 発見の塊（モック2）
    @Published private(set) var popularSpots: [DiscoverySections.Spot] = []
    @Published private(set) var seasonal: [Photo] = []
    /// 機材から探す（モック9）。**焦点距離で分ける**——レンズ名では
    /// ズーム1本が広角も望遠も含んでしまう
    @Published private(set) var gear: [GearGroups.Section] = []
    @Published private(set) var category: String?
    @Published private(set) var sort: GallerySort = .new

    /// 画面に出す写真。**打っていないときはカテゴリ／タグの結果を出す**
    /// ——空の画面にしない（探しに来た人を手ぶらで帰さない）
    var shown: [Photo] {
        let base = photos.isEmpty && query.isEmpty ? allPhotos : photos
        let byCategory: [Photo]
        if let category {
            let key = CategoryChoices.key(category)
            byCategory = base.filter { CategoryChoices.key($0.category ?? "") == key }
        } else {
            byCategory = base
        }
        return sort.apply(byCategory)
    }

    /// いま打っている文字（`shown` の出し分けに使う）
    private var query = ""

    func select(category: String?) {
        // 押し直したら外す
        if let category, let current = self.category,
           CategoryChoices.isChosen(current: current, choice: category) {
            self.category = nil
        } else {
            self.category = category
        }
    }

    func select(sort: GallerySort) { self.sort = sort }

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
        popularTags = PhotoQuery.topTags(in: allPhotos)
        tagCounts = PhotoQuery.tagCounts(in: allPhotos)
        popularSpots = DiscoverySections.popularSpots(in: allPhotos)
        seasonal = DiscoverySections.seasonal(in: allPhotos)
        gear = GearGroups.sections(in: allPhotos)
        categories = CategoryChoices.all.filter { choice in
            allPhotos.contains { CategoryChoices.isChosen(current: $0.category ?? "", choice: choice) }
        }
        photos = []
    }

    func search(_ query: String, environment: AppEnvironment) async {
        searchTask?.cancel()
        self.query = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            photos = []
            users = []
            return
        }
        // 写真は手元の一覧から即座に絞る（往復しない）
        photos = PhotoQuery.match(allPhotos, query: trimmed)

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            users = (try? await environment.search.search(query: trimmed)) ?? []
        }
    }

}
