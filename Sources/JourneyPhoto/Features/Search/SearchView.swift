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
    @EnvironmentObject private var tabRouter: TabRouter
    @StateObject private var model = SearchViewModel()
    @State private var query = ""
    /// いまこの画面が出ているか。**詳細・人のページを上に積んでいる間は読み直さない**
    /// （`GalleryView` と同じ形）
    @State private var isOnScreen = false
    /// 出ていない間にブロック／通報があった。戻ってきたときに読み直す
    @State private var needsReload = false
    /// 人の結果から落とす「見せない」の写し。**画面に出ている間だけ取り直す**
    @State private var dropped = ModerationSnapshot()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 板 11 の見出しの帯: 探す口と種類のチップ（間 12）
                VStack(alignment: .leading, spacing: 12) {
                    searchField
                    scopeChips
                }
                if isDiscovering {
                    // **何も打っていないときは「発見」の顔**（板 11）。段の並びは
                    // `SearchDiscovery`、段の間は 20
                    ForEach(model.discovery) { section in
                        discoverySection(section)
                    }
                } else {
                    // 探し始めたら絞り込みを出す。**板 11（発見の顔）には無い**ので、
                    // 発見の間は置かない
                    // 人を探しているときは写真の絞り込みを出さない（効かない札を置かない）
                    if model.scope.showsPhotos {
                        categoryChips
                    }
                    // 撮影地ではタグのチップを出さない（押しても枚数と結果が合わない）
                    if model.scope.showsTagChips {
                        tagChips
                    }
                }
                results
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .webScreen()
        // 読み込めなかった回の出口（以前は一度読んだら二度と読まなかった）
        .refreshable {
            await model.reloadPhotos(environment: environment, force: true, hidden: hidden.snapshot)
            await model.search(query, environment: environment)
        }
        .navigationTitle(Labels.Navigation.searchTab)  // 見た目はロゴ（AppHeaderItems）。この字は次の画面の「戻る」と読み上げに使う
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { AppHeaderItems(unread: unread, onOpenNotifications: onOpenNotifications) }
        // 最初の読み込みと、**限定公開の読み出し口が替わったとき**（ログアウト・
        // 別の人のログイン）の読み直し。替わった後に届くので前の人の口を通らない
        .task {
            for await epoch in await environment.gallery.restrictedChanges() {
                await model.loadPhotos(environment: environment, epoch: epoch)
            }
        }
        .onChange(of: query) { _, newValue in
            Task { await model.search(newValue, environment: environment) }
        }
        // **ブロック／通報の直後に消す。** `loadPhotos` は
        // `guard allPhotos.isEmpty` で二度と読まない作りなので、
        // 控えを捨ててから読み直す
        //
        // 🔴 **詳細・人のページを開いている間は読み直さない。** 読み直すと押した元の
        // 写真・人が結果から消え、開いている画面がその場で閉じる（通報シートの
        // ブロック失敗の文言も一緒に消える）。戻ってきたとき（`onAppear`）に読み直す
        .onChange(of: hidden.revision) { _, _ in
            if isOnScreen {
                dropped = hidden.snapshot
                reloadHidden()
            } else {
                needsReload = true
            }
        }
        .onAppear {
            isOnScreen = true
            dropped = hidden.snapshot
            if needsReload { reloadHidden() }
        }
        .onDisappear { isOnScreen = false }
    }

    private func reloadHidden() {
        needsReload = false
        Task {
            await environment.gallery.setHidden(hidden.snapshot)
            await model.reloadPhotos(environment: environment, hidden: hidden.snapshot)
            await model.search(query, environment: environment)
        }
    }

    /// 何も打たず、種類もカテゴリも選んでいない＝「発見」の顔
    private var isDiscovering: Bool {
        query.isEmpty && model.category == nil && model.scope == .all
    }

    // MARK: - 探す口

    /// 探す口（板 11: 高さ44・角丸12・地 白8%・縁 白6%・虫眼鏡 白60%）。
    /// **並び替えの印は置かない**（板に無い）。並び替えは結果の上の札から
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(WebTheme.faint)
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("消す", "Clear"))
            }
        }
        .padding(.horizontal, 14)
        // 最小44（板）。大きな文字の設定では字に合わせて伸ばす（固定だと上下が欠ける）
        .frame(minHeight: 44)
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

    /// カテゴリ（モック9-2 の丸い札）。**絵はその分類でいちばん人気の1枚**
    /// ——決め打ちの絵を持たないので、写真が増えれば札の顔も変わる。
    /// **「すべて」を先頭に置く**（戻れない絞り込みを作らない）
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                circleChip(label: L("すべて", "All"), selected: model.category == nil) {
                    model.select(category: nil)
                } face: {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(model.category == nil ? WebTheme.accentText : WebTheme.muted2)
                }

                ForEach(model.categoryCovers) { item in
                    let selected = model.category.map {
                        CategoryChoices.isChosen(current: $0, choice: item.category)
                    } ?? false
                    circleChip(label: Labels.Category.name(item.category), selected: selected) {
                        model.select(category: item.category)
                    } face: {
                        RemoteImage(url: item.cover.gridImageURL, alignment: item.cover.gridAlignment)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    /// 丸い札。選んでいる間は**白い輪**で囲む（色だけだと分かりにくい）
    private func circleChip<Face: View>(label: String, selected: Bool,
                                        action: @escaping () -> Void,
                                        @ViewBuilder face: () -> Face) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                face()
                    .frame(width: 56, height: 56)
                    .background(selected ? AnyShapeStyle(WebTheme.foreground)
                                         : AnyShapeStyle(WebTheme.surface),
                                in: Circle())
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(
                        selected ? WebTheme.foreground : Color.white.opacity(0.15),
                        lineWidth: selected ? 2.5 : 1))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(selected ? WebTheme.foreground : WebTheme.muted2)
                    .lineLimit(1)
            }
            .frame(width: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// タグ。**枚数を添える**（押す前に手応えが分かる）
    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 0枚のチップは出さない。**ただし選んでいるものは残す**——カテゴリで
                // 0 になったとき、押して外す手立てが消える
                ForEach(model.tagChips.filter { $0.count > 0 || TagChoices.key(query) == TagChoices.key($0.tag) },
                        id: \.tag) { item in
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
                sectionHeader(L("注目スポット", "Featured places")) {
                    // 行き先はマップの札（板 11）。撮影地のピンが並ぶ
                    Button {
                        TabRouter.shared.openMap()
                    } label: {
                        moreLabel(L("地図で見る", "View on map"))
                    }
                    .buttonStyle(.plain)
                }
                // 156×116 の札を横に送る（板 11）
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
    /// 3列の格子に1段ぶん、「すべて →」で全部（形は板 12）
    @ViewBuilder
    private var seasonal: some View {
        let photos = model.seasonal
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // **「おすすめ」とは書かない**——推薦の口は無く、
                // 中身は「いまの季節のタグが付いた写真」そのもの。
                // どのタグで集めたかは「すべて」の先の注記に出す（板 11 はこの段に説明を置かない）
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

    /// おすすめ · [カテゴリ名]（板 11）。**ホームと同じ塊**（`FeaturedGroups`）の
    /// 先頭の1つ。「すべて見る」の行き先もホームと同じそのカテゴリの集約
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
                        ForEach(group.photos) { photo in
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

    /// 撮影地の札（板 11: 156×116・角丸14・名前 13 semibold・枚数は等幅 10）。
    /// **枚数は数えたもの**
    private func spotCard(_ spot: DiscoverySections.Spot) -> some View {
        Color.clear
            .frame(width: 156, height: 116)
            .overlay {
                RemoteImage(url: spot.cover.gridImageURL, alignment: spot.cover.gridAlignment)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(spot.id)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(1)
                    Text(L("\(spot.count)枚の写真", "\(spot.count) photos"))
                        .font(JPFont.mono(10, relativeTo: .caption2))
                        .foregroundStyle(WebTheme.muted)
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

    /// 機材から探す（板 11: 札の中の行・最小54・カメラの印・右に枚数と「›」）。
    ///
    /// **分け方を隠さない**——行の下の小さい字に「〜35mm」を出す。
    /// レンズ名で分けないのは、ズーム1本が広角も望遠も撮れるから。
    @ViewBuilder
    private var gear: some View {
        let sections = model.gear
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("機材から探す", "Browse by gear"))
                JPCard {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        if index > 0 { JPCardDivider() }
                        NavigationLink {
                            GearPhotosView(section: section)
                        } label: {
                            gearRow(section)
                        }
                        .buttonStyle(JPRowButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func gearRow(_ section: GearGroups.Section) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.system(size: 18))
                .foregroundStyle(WebTheme.muted2)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(section.group.label)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                Text(section.group.range)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
            }
            Spacer(minLength: 8)
            Text(L("\(section.count)枚", "\(section.count)"))
                .font(JPFont.mono(13, relativeTo: .footnote))
                .foregroundStyle(WebTheme.faint)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    private func sectionHeader(_ title: String) -> some View {
        sectionHeader(title) { EmptyView() }
    }

    /// 段の見出し（板 11: 12・medium・白60% の小さい見出し）。
    /// 右端に「地図で見る →」「すべて見る →」を置ける
    private func sectionHeader<Trailing: View>(_ title: String,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            JPSectionTitle(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
    }

    private func moreLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "arrow.right")
        }
        .font(.caption)
        .foregroundStyle(WebTheme.muted2)
        .padding(.trailing, 4)
        .frame(minHeight: WebTheme.minTapTarget)
        .contentShape(Rectangle())
    }

    // MARK: - 結果

    @ViewBuilder
    private var results: some View {
        // 人は写真より先に出す（名前で探しているなら、それが目当て）。
        // ブロックした人は出さない（`/users/search` はブロックを知らない）。
        // **写しで落とす**——描くたびに今の集合で絞ると、人のページでブロックした瞬間に
        // 元の行が消え、そのページが閉じる
        let users = model.scope.showsPeople ? dropped.users(model.users) : []
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
            photoResults
        } else if users.isEmpty {
            // 人だけを探しているとき。**打つ前と見つからなかったを分ける**
            Text(query.isEmpty
                 ? L("名前を入れると人を探せます", "Type a name to find people")
                 : (model.isSearching ? L("探しています…", "Searching…")
                    // **「読み込めなかった」と「見つからなかった」を分ける**（写真と同じ言い方）
                    : (model.usersFailed
                       ? L("人を読み込めませんでした。引き下げて読み直せます", "Couldn't load people. Pull to retry")
                       : (model.peopleQueryTooShort
                          ? L("英数字は2文字から探せます", "Type at least 2 letters or numbers")
                          : L("見つかりませんでした", "No results")))))
                .font(.subheadline)
                .foregroundStyle(WebTheme.faint)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private var photoResults: some View {
        // **件数と並び替えは結果の上**（提案の絵）
        HStack {
            Text(L("検索結果: \(model.shown.count) 件", "\(model.shown.count) results"))
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
            Spacer()
            Menu {
                ForEach(GallerySort.feedChoices) { option in
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

        if model.shown.isEmpty && !model.hasLoaded {
            // 最初の読み込みが返るまでは何も言わない（失敗とも0件とも言わない）
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if model.shown.isEmpty {
            // **「読み込めなかった」と「見つからなかった」を分ける。**
            // 0件なら検索語を捨てさせず、地図で同じ目的を続けられる出口を出す。
            VStack(spacing: 12) {
                Text(model.loadFailed && model.everything.isEmpty
                     ? L("写真を読み込めませんでした。引き下げて読み直せます", "Couldn't load photos. Pull to retry")
                     : L("見つかりませんでした", "No results"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.faint)
                if !(model.loadFailed && model.everything.isEmpty) {
                    Button { tabRouter.openMap() } label: {
                        Label(L("地図で撮影地を探す", "Explore shooting places on the map"), systemImage: "map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WebTheme.accent)
                            .frame(minHeight: WebTheme.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.emptyMap")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        } else {
            SearchGrid(photos: model.shown)
        }
    }
}

@MainActor
final class SearchViewModel: ObservableObject {

    @Published private(set) var users: [UserProfile] = []
    @Published private(set) var popularTags: [String] = []
    @Published private(set) var isSearching = false
    /// 人の検索が**通信などで失敗した**（「見つかりませんでした」と分ける）
    @Published private(set) var usersFailed = false
    /// 人の検索に**短すぎる語**（英数字1字・`@` だけ）。サーバーは探さずに空で返すので、
    /// 「見つかりませんでした」と言わずに何字から探せるかを出す
    @Published private(set) var peopleQueryTooShort = false
    /// いまの `users` を引いた語。**同じ語で失敗した回は一覧を残す**
    /// （通報・引き下げで読み直して圏外だった回に、開いているプロフィールの元の行を消さない）
    private var usersQuery: String?
    /// 写真の一覧を取れなかった（読み込み中・0枚と分ける）
    @Published private(set) var loadFailed = false
    /// 最初の読み込みが（成功でも失敗でも）返ったか
    @Published private(set) var hasLoaded = false
    /// 候補タグと枚数（提案の絵の「winter 13」）
    @Published private(set) var tagCounts: [(tag: String, count: Int)] = []
    @Published private(set) var categories: [String] = []
    /// 丸い札に出す分類と、その代表写真（モック9-2）
    @Published private(set) var categoryCovers: [CategoryCovers.Item] = []
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
    @Published private(set) var category: String?
    @Published private(set) var sort: GallerySort = .new

    /// 画面に出す写真。**打っていないときはカテゴリ／タグの結果を出す**
    /// ——空の画面にしない（探しに来た人を手ぶらで帰さない）
    var shown: [Photo] {
        // 打っていないときは全部（タグ／撮影地はその欄を持つ写真）、
        // 打っているときは種類ごとの欄に当てる（`SearchScope`）
        return sort.apply(filtered(query: query))
    }

    /// タグのチップと、**押したときに出る枚数**（0 もそのまま持つ。出すかどうかは画面）。
    ///
    /// 並びと候補は `tagCounts`（タグを持つ写真の数）で決め、数は押した後の
    /// 結果（`shown` と同じ絞り方）で出す。「すべて」「写真」はタグの語を題・
    /// 撮影地にも当てる（`SearchScope`）ので、タグの数を出すと「山 1」を押して
    /// 富士山・山中湖の写真まで出て数が合わなかった。
    /// **打鍵ごとには数え直さない**——一覧・種類・カテゴリが変わったときだけ
    /// （`refreshTagChips`）。描くたびに数えると、12語×全写真の文字の畳み込みが走る
    @Published private(set) var tagChips: [(tag: String, count: Int)] = []

    private func refreshTagChips() {
        tagChips = tagCounts.map { (tag: $0.tag, count: filtered(query: $0.tag).count) }
    }

    /// `shown` の絞り方（並べ替えの前まで）
    private func filtered(query: String) -> [Photo] {
        let base = scope.photos(allPhotos, query: query)
        guard let category else { return base }
        let key = CategoryChoices.key(category)
        return base.filter { CategoryChoices.key($0.category ?? "") == key }
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

    func select(scope: SearchScope) {
        self.scope = scope
        refreshTagChips()
    }

    func select(category: String?) {
        // 押し直したら外す
        if let category, let current = self.category,
           CategoryChoices.isChosen(current: current, choice: category) {
            self.category = nil
        } else {
            self.category = category
        }
        refreshTagChips()
    }

    func select(sort: GallerySort) { self.sort = sort }

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

    /// どの読み出し口の回で読んだか（`PublicGalleryService.restrictedEpoch`）
    /// 最後に知らされた読み出し口の回（`restrictedChanges`）
    private var loadedEpoch: Int?
    /// **手元の一覧を作った回**（サービスが返す）。画面が知らされた回ではなく、
    /// 一覧の中身が誰の読み出し口で読まれたかで「前の人の一覧か」を見分ける。
    /// 知らせより先に読み直しが終わると、画面の回は nil のままでも、中身は
    /// 前の人（切り替え前）の限定公開を含みうる
    private var listEpoch: Int?

    func loadPhotos(environment: AppEnvironment, epoch: Int) async {
        // **2つを分けて見る。**
        // - 人が替わった（知らされた回が進んだ）→ 画面の選択を片づける
        // - 一覧が古い（一覧を作った回が今の回より前）→ 一覧を捨てて読み直す
        // 新しい人の一覧が知らせより先に届くことがある（ブロックの差し替えで
        // 読み直しが先に走る）。一覧の古さだけで決めると、そのとき選択が残った
        // まだ知らされていない（最初の知らせ）ときは、手元の一覧の回と比べる
        // ——知らせより先に読み直しが一覧を埋め、その一覧でカテゴリを選んだ後に
        // 人が替わると、最初の知らせで選択が外れなかった
        let switched = (loadedEpoch ?? listEpoch).map { $0 < epoch } ?? false
        let stale = listEpoch.map { $0 < epoch } ?? false
        // 回は戻さない（2回続けて替わった後に古い知らせが届いても、古い一覧を通さない）
        loadedEpoch = max(loadedEpoch ?? epoch, epoch)
        if switched {
            // 選んでいたカテゴリを外す（次の人の一覧に無いと、0件で選択中の札も見えない）
            category = nil
        }
        guard allPhotos.isEmpty || stale else {
            if switched { rebuildDerived() }
            return
        }
        // 🔴 **一覧が古ければ、読み直しに失敗しても前の一覧を残さない**
        // （前の人の限定公開の写真が入っている）
        if stale {
            allPhotos = []
            listEpoch = nil
            // 読み直しが返るまでは「読み込み中」（前の結果で「見つかりません」を出さない）
            hasLoaded = false
            rebuildDerived()
        }
        await reloadPhotos(environment: environment)
    }

    /// 控えがあっても読み直す。**ブロック／通報のあとに使う**
    /// ——`loadPhotos` は一度読んだら二度と読まないので、そのままだと
    /// ブロックした相手の写真が検索結果に残り続ける。
    /// - Parameter hidden: いまの「見せない」。取れなかった回に手元の一覧を絞る
    ///   （公開一覧の絞り込みは返す値にしか掛からない——ブロックの直後に
    ///   読み直しが落ちると、ブロックした人の写真が手元に残っていた）
    func reloadPhotos(environment: AppEnvironment, force: Bool = false,
                      hidden: ModerationSnapshot? = nil) async {
        let startedAt = loadedEpoch
        do {
            let fetched = try await environment.gallery.fetchPhotosTagged(force: force)
            // **知らされた回より古い一覧は書かない**（人の切り替えの前に読んだもの）。
            // 新しい回の一覧は、知らせより先に届いても書く（中身は今の人のもの）
            // 一覧の回とも比べる（知らせより先に新しい一覧が入った後、古い取得が
            // 遅れて返っても上書きしない）
            let newest = max(loadedEpoch ?? .min, listEpoch ?? .min)
            if fetched.epoch < newest { return }
            allPhotos = fetched.photos
            listEpoch = fetched.epoch
            loadFailed = false
        } catch {
            // 失敗の知らせは、始めてから回が替わっていなければ出す
            // （替わっていれば、今の回の読み込みが状態を決める）
            guard startedAt == loadedEpoch else { return }
            // 取れなかった回は手元のぶんを残す（引き下げの失敗で一覧を消さない）
            if let hidden { allPhotos = hidden.visible(allPhotos) }
            loadFailed = true
        }
        hasLoaded = true
        rebuildDerived()
    }

    /// 一覧から作る段（チップ・発見の段・カテゴリ）を作り直す。
    /// **人が替わって一覧を空にしたときも呼ぶ**——呼ばないと、読み直しが返るまで
    /// 前の人の一覧（限定公開を含む）から作ったチップ・季節の写真・機材が残っていた
    private func rebuildDerived() {
        popularTags = PhotoQuery.topTags(in: allPhotos)
        tagCounts = PhotoQuery.tagCounts(in: allPhotos)
        refreshTagChips()
        popularSpots = DiscoverySections.popularSpots(in: allPhotos)
        seasonalAll = DiscoverySections.seasonal(in: allPhotos, limit: .max)
        seasonal = Array(seasonalAll.prefix(SearchDiscovery.seasonalPreview))
        featured = SearchDiscovery.featured(in: allPhotos)
        // **機材・色は枚数で切らない**（既定は12）。行の「N枚」と押した先の一覧は
        // 段の写真そのものなので、12で切ると13枚目から先が数えられず出てこなかった。
        // 行に描くのは先頭の1枚だけ。押した先の格子（`PhotoGrid`）は Lazy ではなく
        // 全部を一度に作るが、カテゴリ・タグの一覧や季節の「すべて」も同じ作り
        // （写真が増えて重くなったら、`PhotoGrid` の側でまとめて手当てする）
        gear = GearGroups.sections(in: allPhotos, limit: .max)
        categoryCovers = CategoryCovers.items(in: allPhotos)
        colors = ColorFamilies.sections(in: allPhotos, limit: .max)
        categories = CategoryChoices.present(in: allPhotos)
    }

    func search(_ query: String, environment: AppEnvironment) async {
        let service = environment.search
        await search(query) { try await service.search(query: $0) }
    }

    /// サーバーが探す語か（`userSearch.ts` の `normalizeQuery` と `isSearchableQuery` と同じ）
    nonisolated static func isSearchablePeopleQuery(_ raw: String) -> Bool {
        var q = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        while q.first == "@" { q = q.dropFirst() }
        let normalized = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if normalized.unicodeScalars.contains(where: { !$0.isASCII }) { return true }
        return normalized.utf16.count >= 2
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
        // **サーバーが探さない語は送らない。** `userSearch.ts` は先頭の `@` を落とし、英数字だけ
        // なら2字から探す（満たさないと探さずに空を返す）。空の答えを「見つかりませんでした」
        // と出すと、居る人を居ないと言う（Web は `isSearchableQuery` を満たすまで言わない）
        let searchable = Self.isSearchablePeopleQuery(trimmed)
        peopleQueryTooShort = !trimmed.isEmpty && !searchable
        guard searchable else {
            users = []
            usersQuery = nil
            isSearching = false
            usersFailed = false
            return
        }
        // 写真は手元の一覧から即座に絞る（往復しない・`shown` が `query` から導く）

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            // **失敗を0人にしない。** 圏外で「見つかりませんでした」と出すと、
            // 居る人を「居ない」と言うことになる
            let found: [UserProfile]?
            do {
                found = try await fetchUsers(trimmed)
            } catch {
                found = nil
            }
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            if let found {
                users = found
                usersQuery = trimmed
            } else if usersQuery != trimmed {
                // 別の語の人を残さない
                users = []
                usersQuery = nil
            }
            usersFailed = found == nil
            isSearching = false
        }
    }

}
