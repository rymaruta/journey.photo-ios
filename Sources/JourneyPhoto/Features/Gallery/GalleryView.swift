import SwiftUI

struct GalleryView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    /// **「見せない」が変わったら読み直すため**に見ている。
    /// この画面はタブの根なので一度出たら生き続け、`.task` は二度と走らない
    /// ——ブロックしても、戻ってくるとその人の写真がまだ並んでいた
    @EnvironmentObject private var hidden: ModerationStore
    @StateObject private var model = GalleryViewModel()
    /// タグの行を出しているか。**既定は畳む**——チップが2行あると
    /// ファーストビューが「ボタンだらけ」になり、写真が下へ押し下げられる
    @State private var showsTags = false
    /// ヘッダーのベル用（タブから外したので、ここから開く）
    var unread: Int = 0
    var onOpenNotifications: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // **タブは写真が0枚でも出す。** 中に入れると、1枚も無い人
            // （ログイン直後の既定は「自分」）に空の帯だけが出て、
            // **「すべて」に戻せない**——行き止まりを作らない
            if auth.userId != nil {
                scopePicker
            }
            switch model.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorBanner(message: message) {
                    Task { await model.load() }
                }
            case .loaded(let photos):
                if photos.isEmpty {
                    ErrorBanner(message: Labels.Gallery.empty)
                } else {
                    feed(photos)
                }
            }
        }
        .webScreen()
        // **Web のヘッダーと同じ名前を出す。** あちらは全ページ共通で
        // 「Journey Photo」を左上に出している（`app/layout.tsx` の
        // `<header>`・高さ64・`bg-black/60`・下辺 `border-white/10`）。
        // 大見出しで「ギャラリー」と出していたので、開いた瞬間に
        // 別のサイトに見えていた
        .navigationTitle("Journey Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onOpenNotifications()
                } label: {
                    Image(systemName: "bell")
                        .webToolbarIcon()
                        .overlay(alignment: .topTrailing) {
                            // 未読があることだけ伝える（数は開けば分かる）
                            if unread > 0 {
                                Circle().fill(Color.pink).frame(width: 8, height: 8)
                                    .offset(x: -8, y: 10)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("お知らせ", "Activity"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PhotoMapView() } label: {
                    Image(systemName: "map")
                        .webToolbarIcon()
                        .accessibilityLabel(Labels.Navigation.map)
                }
            }
        }
        .task {
            // **環境の1つに繋ぎ直してから読む。** 自前のを持ったままだと
            // `setHidden` が届かず、ブロックが一生効かない
            model.use(gallery: environment.gallery)
            await model.load()
        }
        // **ログイン状態が決まってから範囲を決める**（既定は「自分」）。
        // フォロー中の一覧は、その範囲を選ぶ人にだけ要る
        .task(id: auth.userId) {
            guard auth.userId != nil else {
                model.use(viewerId: nil, following: [])
                return
            }
            let ids = (try? await environment.social.myFollowingIds()) ?? []
            model.use(viewerId: auth.userId, following: Set(ids))
        }
        .refreshable { await model.load(force: true) }
        // **ブロック／通報の直後に消す。** 手元に読み終えた配列が残るので、
        // 読み直さないと画面は変わらない。
        //
        // **集合を自分で渡してから読む。** 呼んだ側（`ReportSheet`）は
        // 通報とブロックを挟んでから `setHidden` を呼ぶので、その中断中に
        // 走るとこちらは**古い集合のまま**取ってしまう。
        // 1本にまとめてあるのは、2本だと全件取得が同時に2回走るため
        .onChange(of: hidden.revision) { _, _ in
            Task {
                await environment.gallery.setHidden(userIds: hidden.blockedUserIds,
                                                    photoIds: hidden.reportedPhotoIds)
                await model.load()
            }
        }
    }

    /// 出す範囲（自分 / フォロー中 / すべて）。**ログイン中だけ出す**
    /// ——未ログインには絞る相手が無い（Web も同じ）。
    private var scopePicker: some View {
        Picker("", selection: Binding(
            get: { model.scope },
            set: { scope in
                model.select(scope: scope)
                // **選んだときに引き直す。** フォロー一覧は
                // `.task(id: auth.userId)` で一度しか引いていないので、
                // 誰かをフォローしても、この画面には一生出てこなかった
                guard scope == .following, auth.userId != nil else { return }
                Task {
                    // **取れなかった回に空で潰さない。** `?? []` にすると、
                    // 圏外でタブを押しただけで「フォロー中」が
                    // 何の知らせも無く空一覧になる
                    guard let ids = try? await environment.social.myFollowingIds() else { return }
                    model.refreshFollowing(Set(ids))
                }
            }
        )) {
            ForEach(GalleryScope.allCases) { scope in
                Text(scope.label).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// カテゴリの絞り込み。Web の `FilterBar` にあたる。
    /// **押し直すと外れる**（`role="switch"` と同じ振る舞い）。
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.categories, id: \.self) { category in
                    let selected = model.category == category
                    Button {
                        model.select(category: selected ? nil : category)
                    } label: {
                        Text(Labels.Category.name(category))
                            // **字も小さすぎた。** caption(13) → subheadline(15)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            // Web の `FilterBar`: 選択中は白地に黒字、
                            // それ以外は白7%の地に白70%の字
                            // 選択中は白地に黒字（Web の約束）。未選択は
                            // **すりガラス**——黒地に白7%のベタより、
                            // 写真の上を流れるときに馴染む
                            .background(
                                selected ? AnyShapeStyle(WebTheme.foreground)
                                         : AnyShapeStyle(.ultraThinMaterial),
                                in: Capsule()
                            )
                            .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted)
                            .overlay(
                                Capsule().strokeBorder(
                                    selected ? Color.clear : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }

                // タグの開け閉め。**選んでいる数を出す**——畳んだままでも
                // 「何かで絞っている」ことが分かるように
                if !model.tags.isEmpty {
                    Button {
                        showsTags.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                            if model.selectedTags.isEmpty {
                                Text(L("タグ", "Tags"))
                            } else {
                                Text("\(model.selectedTags.count)")
                            }
                            Image(systemName: showsTags ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .font(.subheadline)
                        .foregroundStyle(model.selectedTags.isEmpty ? WebTheme.muted2 : WebTheme.accentText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            model.selectedTags.isEmpty ? AnyShapeStyle(.ultraThinMaterial)
                                                       : AnyShapeStyle(WebTheme.foreground),
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(
                            model.selectedTags.isEmpty ? Color.white.opacity(0.12) : Color.clear,
                            lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("gallery.tagsToggle")
                }

                // 並び替え。**Web も同じ列に置いている**（`FilterBar` の
                // 右端のメニュー）。新しい順／古い順／人気順の3つ
                Menu {
                    ForEach(GallerySort.allCases) { option in
                        Button {
                            model.select(sort: option)
                        } label: {
                            if model.sort == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.sort.label)
                        Image(systemName: "chevron.down")
                    }
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                }
                .accessibilityIdentifier("gallery.sort")
            }
            .padding(.horizontal, 12)
        }
        // 端の見切れをぼかす（タグの行と同じ）
        .mask {
            LinearGradient(
                colors: [Color.black, Color.black, Color.black.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    /// タグのチップ。**Web の `FilterBar` にある側**（あちらは数も出す）。
    /// 複数選べて、**全部を持つ写真だけ**が残る。押し直すと外れる。
    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.tags, id: \.self) { tag in
                    let selected = model.selectedTags.contains { TagChoices.key($0) == TagChoices.key(tag) }
                    Button {
                        model.toggle(tag: tag)
                    } label: {
                        Text("#\(tag)")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(
                                selected ? AnyShapeStyle(WebTheme.foreground)
                                         : AnyShapeStyle(.ultraThinMaterial),
                                in: Capsule()
                            )
                            .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted2)
                            .overlay(
                                Capsule().strokeBorder(
                                    selected ? Color.clear : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
        }
        // **端の見切れをぼかす。** 横に続いていることが伝わり、
        // 切れ方が雑に見えない
        .mask {
            LinearGradient(
                colors: [Color.black, Color.black, Color.black.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    /// owner が選んだ「おすすめ」。Web はトップの一覧の上に、
    /// カテゴリごとの横並びで出している（`FeaturedSections`）。
    @ViewBuilder
    private var featuredSections: some View {
        ForEach(model.featured) { group in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(group.label)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WebTheme.foreground)
                    Spacer()
                    NavigationLink {
                        TagPhotosView(kind: .category(group.id))
                    } label: {
                        Text(L("すべて見る", "See all"))
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                    }
                }
                .padding(.horizontal, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WebTheme.gridSpacing) {
                        ForEach(group.photos) { photo in
                            NavigationLink {
                                PhotoDetailView(photo: photo, context: group.photos)
                            } label: {
                                PhotoTile(photo: photo, aspect: 3.0 / 4.0)
                                    .frame(width: 240)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 8)
        }
    }

    /// フィードの切り替え（おすすめ / フォロー中 / 新着）。
    ///
    /// **推薦の口は無い**ので、おすすめの規則を下に1行で出す
    /// （指示書 5-2——実装済みであるかのように見せない）。
    private var feedPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(HomeFeed.allCases) { feed in
                    let selected = model.feed == feed
                    Button {
                        model.select(feed: feed, viewerId: auth.userId)
                    } label: {
                        Text(feed.label)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(selected ? AnyShapeStyle(WebTheme.foreground)
                                                 : AnyShapeStyle(Color.clear),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(4)
            .background(WebTheme.surface, in: Capsule())

            if let note = model.feed.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 16)
    }

    /// ホームは**縦1列のフィード**（提案の絵・2026-09-21）。
    /// 格子は集約ページ（タグ・撮影地・機材）で使い続ける。
    private func feed(_ photos: [Photo]) -> some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // **ストーリーはホームの一番上**（モック1）。
                // 2026-09-20 に Web がトップから外してマイページへ移したが、
                // アプリの提案図では**ホームに戻っている**ので合わせる
                // ——「いま誰が旅に出ているか」は開いた瞬間に見たいもの
                StoriesRow()
                feedPicker
                featuredSections
                ForEach(photos) { photo in
                    HomeFeedCard(photo: photo, following: model.followingIds)
                }
            }
            .padding(.top, 8)
            // 最後のカードがタブバーに掛からないようにする
            .padding(.bottom, 24)
        }
    }

    private func grid(_ photos: [Photo]) -> some View {
        ScrollView {
            // **ストーリーはここに置かない。** 2026-09-20 に Web が
            // トップから外してマイページへ移した（投稿も閲覧もマイページに集める）
            if !model.categories.isEmpty {
                filterBar
            }
            if showsTags && !model.tags.isEmpty {
                tagBar
            }
            // チップの列と写真の間に息を入れる（実機の絵で詰まって見えた）
            Color.clear.frame(height: 4)
            featuredSections
            PhotoGrid(photos: photos) { photo in
                PhotoDetailView(photo: photo, context: photos)
            }
        }
    }
}
