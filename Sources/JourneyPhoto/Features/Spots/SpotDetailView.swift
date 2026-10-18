import SwiftUI
import MapKit

/// 撮影スポットの詳細（モック5）＝**撮影地の集まり**（`DerivedSpot`）。
///
/// ⚠️ 台帳の撮影スポット（Web の `content/spots.json`・運営未確認の下書き）は
/// **この画面では出さない**——全節が `spot.photos` に依存していて、台帳の
/// スポットに紐づく写真は今日0枚。あちらは `OfficialSpotView`（モック13）が
/// 別に出す。共用する部品は `SpotDetailParts`。
///
/// 出すのは**写真が実際に持っている値と、数えたものだけ**。
/// **モックにあって出さないもの**: ★評価・口コミ件数・「行きたい」人数。
/// どれも集計していないので、置けば嘘になる。
/// **ふりがな・概要も出さない**——Web は `content/spot-master.json` に
/// 人が書いたぶんだけ持つ形で、アプリへ配る経路がまだ無い（いまは空）。
struct SpotDetailView: View {

    let spot: DerivedSpot.Place
    /// 突き合わせる写真。呼び出し側が持っている一覧をそのまま渡す
    let photos: [Photo]

    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var environment: AppEnvironment
    /// 渡された写真は開いた時点の写しなので、ブロック／通報をここで反映する。
    /// **見ている最中には絞らない**（`FavoritesView` の `photos` の注記）——
    /// 押した元の `NavigationLink` が消えると、開いている詳細がその場で閉じ、
    /// 通報の「受け付けました」も見えない。戻ってきたとき（`onAppear`）に絞る
    @EnvironmentObject private var hidden: ModerationStore
    @State private var dropped = ModerationSnapshot()
    /// 戻るスワイプ途中の `onAppear` で写真を消さない印（`FrontConfirm`）
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?

    @State private var page = 0
    @State private var expanded = false
    @State private var camera: MapCameraPosition = .automatic
    /// この近くの撮影スポット（台帳・2026-10-16）。`spotId` の欄には読んだ座標の鍵を入れる（`nearbySpotKey`）
    @State private var nearbySpotLoaded: PhotoTrip.Loaded?

    private var linked: [Photo] { dropped.visible(spot.photos) }

    /// 画面に出す地点。**分類・より広い撮影地・座標も、見えている写真から作り直す。**
    ///
    /// 🔴 `spot` は開いた時点の一覧から作ったもので、ブロック・通報した人の
    /// 写真の分類チップ・撮影地・**撮影座標（地図のピンと「マップで開く」）**が
    /// 残っていた——その人の写真しか無い地点では、写真の節は空なのにピンだけ出た
    private var place: DerivedSpot.Place {
        DerivedSpot.Place(
            label: spot.label,
            slug: spot.slug,
            photos: linked,
            broader: DerivedSpot.broader(of: spot.label, in: dropped.visible(photos)),
            categories: DerivedSpot.categories(of: linked),
            coords: linked.compactMap(\.coords).first
        )
    }

    /// 見出しの写真。いちばん多く押された1枚を先頭に、残りを新しい順
    private var hero: [Photo] {
        // 表紙が落ちた回は、残りから同じ基準（いちばん押された1枚）で選び直す
        let cover = spot.cover.flatMap { c in linked.contains(where: { $0.id == c.id }) ? c : nil }
            ?? GallerySort.popular.apply(linked).first
        guard let cover else { return [] }
        return [cover] + linked.filter { $0.id != cover.id }
    }

    private var nearby: [(place: DerivedSpot.Place, km: Double)] {
        DerivedSpot.nearby(place, in: dropped.visible(photos))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroPager
                header
                summary
                actions
                stats
                nearbySpotRow
                spotPhotos
                nearbySpots
                map
            }
            .padding(.bottom, 32)
        }
        .onAppear {
            switch front.appear() {
            case .first:
                landSpotFront()
            case .returning:
                // スワイプ途中で絞ると、開いている写真の詳細が閉じる
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled, front.confirm() else { return }
                    landSpotFront()
                }
            }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
        }
        // この近くの撮影スポット（座標のある撮影地だけ）。写真の詳細と同じ索引の口（控えがあれば通信しない）
        .task(id: nearbySpotKey ?? "") { await loadNearbySpot() }
        .webScreen()
        .navigationTitle(LocationMatch.display(spot.label))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .webToolbarIcon()
                // 絵だけのボタン。名前を明示する（OS 任せにすると版によって読まれ方が揺れる）
                .accessibilityLabel(L("シェア", "Share"))
            }
        }
    }

    /// 前面が確定したときだけ写しを取り、ページ送りを範囲に戻す
    private func landSpotFront() {
        dropped = hidden.snapshot
        // 写真が減ったら、ページ送りを範囲に戻す（どの札にも当たらず空白になる）
        if page >= hero.count { page = max(0, hero.count - 1) }
    }

    // MARK: - 代表画像

    @ViewBuilder
    private var heroPager: some View {
        if hero.isEmpty {
            // 写真が1枚も紐づいていない地点。**灰色の枠で場所を取らない**
            EmptyView()
        } else {
            ZStack(alignment: .topTrailing) {
                TabView(selection: $page) {
                    ForEach(Array(hero.enumerated()), id: \.element.id) { index, photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo, context: hero)
                        } label: {
                            Color.clear
                                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                                // 表示する大きさに縮めて読む（ページを払うと隣の絵も抱えるので、
                                // 元の 1920px のまま展開しない・旅の一冊と同じ部品）
                                .overlay {
                                    DownsampledRemoteImage(url: photo.detailImageURL, contentMode: .fill,
                                                           aspectRatio: photo.aspectRatio.map { CGFloat($0) })
                                }
                                .clipped()
                                // `Color.clear` は読み上げの対象にならないので、1つの画像としてまとめて
                                // 名前を付ける（`OfficialSpotView` の代表写真と同じ）
                                .accessibilityElement(children: .ignore)
                                .accessibilityAddTraits(.isImage)
                                .accessibilityLabel(photo.accessibilityText)
                        }
                        .buttonStyle(.plain)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .aspectRatio(4.0 / 3.0, contentMode: .fit)

                // **「1/10」は数えた数**（紐づいた公開写真の枚数そのもの）
                if hero.count > 1 {
                    Text(SpotScreen.pagerLabel(page: page, count: hero.count) ?? "")
                        .font(JPFont.number(JPTypeScale.caption, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(12)
                }
            }
        }
    }

    // MARK: - 基本の情報

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 見出しは画面に出す形（郵便番号・国を落とす・`LocationMatch.display`）。
            // 鍵・突き合わせ・地図の検索は元の文字のまま
            // v2（2026-10-14）: 撮影スポットの頁と同じ明朝 32（`JPFont.photoTitle`）
            Text(LocationMatch.display(spot.label))
                .font(JPFont.photoTitle)
                .foregroundStyle(WebTheme.foreground)
            // ⚠️ **ふりがなは出さない。** Web は `content/spot-master.json` に
            // 人が書いたぶんだけ持つ形で（いまは空）、アプリへ配る経路が無い。
            // 空の行を置くより、**項目ごと出さない**
            if let line = placeLine, !line.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                    Text(line)
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.text2)
                }
            }
            // 分類のチップ。**写真が実際に持っているものだけ**（多い順）
            if !place.categories.isEmpty {
                HStack(spacing: 6) {
                    ForEach(place.categories.prefix(4), id: \.self) { category in
                        Text(Labels.Category.name(category))
                            .font(.footnote.weight(.semibold))
                            .webChip()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// より広い撮影地（「パリ, フランス」に対する「パリ」「フランス」）。
    ///
    /// **推測しない。** 同じ一覧に実際に在って、含む関係にあるものだけ
    /// （`DerivedSpot.broader`）。無ければ行ごと出さない。
    private var placeLine: String? {
        place.broader.isEmpty ? nil : place.broader.map { LocationMatch.display($0) }.joined(separator: " ・ ")
    }

    /// 概要。
    ///
    /// ⚠️ **いまは出せない。** Web は人が書いたぶんだけを
    /// `content/spot-master.json` に持つ形で（2026-09-22 時点で**空**）、
    /// アプリへ配る経路がまだ無い。**文章は生成しない**（owner の指示）ので、
    /// 空の枠も置かない——書かれたものが配られるようになったら出す。
    @ViewBuilder
    private var summary: some View {
        EmptyView()
    }

    private var actions: some View {
        // v2 の板 SpotDetail: 同じ幅の札を 8 のすき間で並べる（札は `SpotDetailParts.actionLabel`）
        HStack(spacing: JPSpace.xs) {
            // 🔴 **鍵（スラッグ）が空の地点には「行きたい」を出さない。** 記号だけの
            // 撮影地（「---」など）はスラッグが空になり、押しても `WishlistStore` は
            // 何も残さない——以前は押すと「追加しました」と知らせて、どこにも出なかった
            if !spot.slug.isEmpty {
                let wanted = wishlist.contains(spot.slug)
                Button {
                    // ログイン中はサーバーへ送る。失敗したら戻して知らせる（`WishlistSync`）
                    Task {
                        let outcome = await WishlistSync.toggle(spot.slug, store: wishlist, service: environment.savedSpots)
                        if let notice = WishlistSync.notice(for: outcome) { toasts.show(notice.text, kind: notice.kind) }
                    }
                } label: {
                    SpotDetailParts.actionLabel(icon: wanted ? "heart.fill" : "heart",
                                                title: L("行きたい", "Want to go"), filled: wanted)
                }
                .buttonStyle(.plain)
            }

            // **シェアは文字で配る**（モック5-6）。名前・地域・地図のリンクに加えて、
            // **公開の写真がある撮影地はサイトのページ（`/location/<スラッグ>`）も配る**
            // （2026-10-07。共有されたリンクが検索に強いページへ人を戻す）。
            // 公開の写真が無い撮影地には付けない（ページが建たない・`SpotScreen.locationPageURL`）
            ShareLink(item: shareText) {
                SpotDetailParts.actionLabel(icon: "square.and.arrow.up", title: L("シェア", "Share"), filled: false)
            }
            .buttonStyle(.plain)

            if let url = mapURL {
                Link(destination: url) {
                    SpotDetailParts.actionLabel(icon: "map", title: L("地図で見る", "Open in Maps"), filled: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    /// 配る文（`SpotScreen`）。**この画面は実機の絵で確かめられない**
    /// ので、決まりは外に出してテストで動かしている。
    /// 行動の札・数え札・節の見出し・近くの札は `SpotDetailParts`
    /// （台帳の撮影スポットの画面 `OfficialSpotView` と共用）
    private var shareText: String {
        SpotScreen.shareText(name: LocationMatch.display(spot.label), region: placeLine, mapURL: mapURL,
                             pageURL: SpotScreen.locationPageURL(slug: spot.slug, photos: linked,
                                                                 siteBase: AppConfig.siteBaseURL))
    }

    /// 端末の地図アプリへ。**座標があるときだけ**（`SpotScreen`）
    private var mapURL: URL? { SpotScreen.mapURL(name: spot.label, coords: place.coords) }

    /// 数えられるものだけ。**評価・口コミ・行きたい人数は出さない**
    private var stats: some View {
        HStack(spacing: 8) {
            SpotDetailParts.statPill(icon: "camera", value: "\(linked.count)",
                                     label: L("この撮影地の写真", "Photos here"))
            // **「—」の数え札を並べない。** 数えていないものを数の形に
            // 置くと、読み込み中の 0 に見える。「行きたい」に入れたことは
            // 上のボタンが灯って伝えている
        }
        .padding(.horizontal, 16)
    }

    // MARK: - この近くの撮影スポット（台帳）

    /// 撮影地の座標。**`place` を作らずに直に取る**（`place` は分類・広い撮影地を毎回数え直す・`place.coords` と同じ値）
    private var nearbyCoords: Photo.Coords? { linked.compactMap(\.coords).first }

    /// 読みに行く鍵（撮影地の座標）。座標の無い撮影地は nil（行を出さない）
    private var nearbySpotKey: String? {
        nearbyCoords.map { "near|\(spot.slug)|\($0.lat),\($0.lng)" }
    }

    /// 「この近くの撮影スポット · [名前] ›」（2026-10-16・行き止まりの直し）。撮影地の集まりの頁から、
    /// 台帳の撮影スポットの頁（撮り方・季節・経路）へ。選び方は写真の詳細と同じ（`PhotoTrip.nearbySpot`・2km）。
    /// 黒地の上なので、合図の字は真鍮・名前は白・矢印は白 50%（写真の詳細の「この写真を見て撮影」の行と同じ形）。当たり 44pt
    @ViewBuilder
    private var nearbySpotRow: some View {
        if let loaded = nearbySpotLoaded, loaded.spotId == nearbySpotKey, let official = loaded.spot {
            NavigationLink {
                OfficialSpotView(spot: official, spots: loaded.index, photos: dropped.visible(loaded.photos ?? []),
                                 photosKnown: loaded.photos != nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(WebTheme.accent)
                        .accessibilityHidden(true)
                    Text(PhotoTrip.nearbySpotTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(official.name)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("›")
                        .foregroundStyle(Color.white.opacity(0.5))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityLabel(PhotoTrip.nearbySpotTitle + ": " + official.name)
            .accessibilityIdentifier("spot.nearbySpot")
        }
    }

    /// 台帳の索引を読み、いちばん近い撮影スポットを引く。読めなかった回は覚えない
    private func loadNearbySpot() async {
        guard let key = nearbySpotKey else { return }
        let coords = nearbyCoords
        let stillHere = { !Task.isCancelled && nearbySpotKey == key }
        if nearbySpotLoaded?.spotId != key {
            guard let rows = await environment.spots.fetchIndexRows(), stillHere() else { return }
            nearbySpotLoaded = PhotoTrip.Loaded(spotId: key, spot: PhotoTrip.nearbySpot(to: coords, in: rows),
                                                index: rows, photos: nil)
        }
        guard let loaded = nearbySpotLoaded, loaded.spotId == key, loaded.spot != nil, loaded.photos == nil else { return }
        guard let feed = try? await environment.gallery.fetchPhotos(), stillHere(),
              nearbySpotLoaded?.spotId == key else { return }
        nearbySpotLoaded = loaded.withPhotos(feed)
    }

    // MARK: - 写真と近くのスポット

    @ViewBuilder
    private var spotPhotos: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpotDetailParts.sectionHeader(L("この撮影地の写真（\(linked.count)）", "Photos here (\(linked.count))"))
            if linked.isEmpty {
                // **空を隠さない。** 「まだ紐づいていない」と「読み込み中」は別
                Text(L("この撮影地に紐づいた公開写真はまだありません。投稿するときに場所を選ぶと、ここに並びます。",
                       "No public photos are linked to this place yet."))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text2)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(linked) { photo in
                            NavigationLink {
                                PhotoDetailView(photo: photo, context: linked)
                            } label: {
                                PhotoFrame(photo: photo, aspect: 3.0 / 4.0, corner: 12)
                                    .frame(width: 118)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var nearbySpots: some View {
        let near = nearby
        if !near.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SpotDetailParts.sectionHeader(L("近くの撮影地", "Nearby places"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(near, id: \.place.id) { item in
                            NavigationLink {
                                SpotDetailView(spot: item.place, photos: photos)
                            } label: {
                                SpotDetailParts.nearbyCard(item.place, km: item.km)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var map: some View {
        if let coords = place.coords {
            let center = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
            VStack(alignment: .leading, spacing: 10) {
                SpotDetailParts.sectionHeader(L("地図", "Map"))
                Map(position: $camera) {
                    Annotation(LocationMatch.display(spot.label), coordinate: center) {
                        // **地図のピンは真鍮**（owner の好み・CLAUDE.md）。地図のタブの撮影スポットと同じ印
                        SpotMapMarker(photoURL: nil)
                    }
                }
                .onAppear {
                    camera = .region(MKCoordinateRegion(
                        center: center,
                        // **約1km に丸めた座標**なので、これ以上寄せても精度は増えない
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
                .padding(.horizontal, JPSpace.m)
                .allowsHitTesting(false)
                .accessibilityLabel(L("\(LocationMatch.display(spot.label)) の地図", "Map of \(LocationMatch.display(spot.label))"))
            }
        }
    }
}
