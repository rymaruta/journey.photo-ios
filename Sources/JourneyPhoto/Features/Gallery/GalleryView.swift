import SwiftUI

struct GalleryView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    /// **「見せない」が変わったら読み直すため**に見ている。
    /// この画面はタブの根なので一度出たら生き続け、`.task` は二度と走らない
    /// ——ブロックしても、戻ってくるとその人の写真がまだ並んでいた
    @EnvironmentObject private var hidden: ModerationStore
    @StateObject private var model = GalleryViewModel()

    // **Web と同じ組み方**（`GalleryGrid.tsx` の `grid-cols-2 gap-1`）。
    // 以前は3列・隙間2で、同じ写真でも1枚がだいぶ小さく見えていた
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: WebTheme.gridSpacing),
        count: WebTheme.gridColumns
    )

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
                    grid(photos)
                }
            }
        }
        .webScreen()
        .navigationTitle(Labels.Navigation.gallery)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PhotoMapView() } label: {
                    Image(systemName: "map")
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
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            // Web の `FilterBar`: 選択中は白地に黒字、
                            // それ以外は白7%の地に白70%の字
                            .background(
                                selected ? AnyShapeStyle(WebTheme.foreground)
                                         : AnyShapeStyle(WebTheme.surface),
                                in: Capsule()
                            )
                            .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
        }
    }

    /// 1枚ぶん。**Web の `GalleryGrid.tsx` と同じ形**——4:3（`paddingTop: 75%`）で、
    /// 下に黒のグラデーションを敷いて題と分類を重ねる。角は丸めない。
    ///
    /// 以前は正方形の写真だけで、題も分類も出していなかった。同じ写真でも
    /// 別のサイトに見える一番大きな差がここだった。
    private func tile(_ photo: Photo) -> some View {
        RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
            .aspectRatio(4.0 / 3.0, contentMode: .fill)
            .clipped()
            .overlay(alignment: .bottom) {
                // **題も分類も無い写真には帯を出さない。** 空の黒帯が
                // 乗るだけで、写真が欠けて見える
                let title = photo.displayTitle
                let category = photo.category.map { Labels.Category.name($0) } ?? ""
                if !title.isEmpty || !category.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        if !title.isEmpty {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WebTheme.foreground)
                                .lineLimit(1)
                        }
                        if !category.isEmpty {
                            Text(category)
                                .font(.caption)
                                .foregroundStyle(WebTheme.faint)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0), Color.black.opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
            .accessibilityLabel(photo.accessibilityText)
    }

    private func grid(_ photos: [Photo]) -> some View {
        ScrollView {
            // **ストーリーはここに置かない。** 2026-09-20 に Web が
            // トップから外してマイページへ移した（投稿も閲覧もマイページに集める）
            if !model.categories.isEmpty {
                filterBar
            }
            LazyVGrid(columns: columns, spacing: WebTheme.gridSpacing) {
                ForEach(photos) { photo in
                    NavigationLink(value: photo.id) {
                        tile(photo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: String.self) { id in
            if let photo = photos.first(where: { $0.id == id }) {
                PhotoDetailView(photo: photo, context: photos)
            }
        }
    }
}
