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

    @State private var page = 0
    @State private var expanded = false
    @State private var camera: MapCameraPosition = .automatic

    private var linked: [Photo] { spot.photos }

    /// 見出しの写真。いちばん多く押された1枚を先頭に、残りを新しい順
    private var hero: [Photo] {
        guard let cover = spot.cover else { return [] }
        return [cover] + linked.filter { $0.id != cover.id }
    }

    private var nearby: [(place: DerivedSpot.Place, km: Double)] {
        DerivedSpot.nearby(spot, in: photos)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroPager
                header
                summary
                actions
                stats
                spotPhotos
                nearbySpots
                map
            }
            .padding(.bottom, 32)
        }
        .webScreen()
        .navigationTitle(spot.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .webToolbarIcon()
            }
        }
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
                                .overlay { RemoteImage(url: photo.detailImageURL, alignment: .center) }
                                .clipped()
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
                        .font(.caption.weight(.semibold))
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
            Text(spot.label)
                .font(JPFont.display(28, relativeTo: .title))
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
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.muted)
                }
            }
            // 分類のチップ。**写真が実際に持っているものだけ**（多い順）
            if !spot.categories.isEmpty {
                HStack(spacing: 6) {
                    ForEach(spot.categories.prefix(4), id: \.self) { category in
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
        spot.broader.isEmpty ? nil : spot.broader.joined(separator: " ・ ")
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
        HStack(spacing: 10) {
            let wanted = wishlist.contains(spot.slug)
            Button {
                let now = wishlist.toggle(spot.slug)
                toasts.show(now
                    ? L("「行きたい」に追加しました（この端末に保存）", "Added to your wishlist on this device")
                    : L("「行きたい」から外しました", "Removed from your wishlist"))
            } label: {
                SpotDetailParts.actionLabel(icon: wanted ? "heart.fill" : "heart",
                                            title: L("行きたい", "Want to go"), filled: wanted)
            }
            .buttonStyle(.plain)

            // **シェアは文字で配る**（モック5-6）。
            //
            // 🔴 **journey-photo.com のリンクは付けない。** スポットの
            // ページ（`/spots/<スラッグ>`）はまだ作っていない（Phase 1.5）ので、
            // 付けると**開けないリンクを配る**ことになる。代わりに
            // 名前と地図のリンクを配る——受け取った人がその場所へ行ける。
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
        SpotScreen.shareText(name: spot.label, region: placeLine, mapURL: mapURL)
    }

    /// 端末の地図アプリへ。**座標があるときだけ**（`SpotScreen`）
    private var mapURL: URL? { SpotScreen.mapURL(name: spot.label, coords: spot.coords) }

    /// 数えられるものだけ。**評価・口コミ・行きたい人数は出さない**
    private var stats: some View {
        HStack(spacing: 8) {
            SpotDetailParts.statPill(icon: "camera", value: "\(linked.count)",
                                     label: L("この場所の写真", "Photos here"))
            // **「—」の数え札を並べない。** 数えていないものを数の形に
            // 置くと、読み込み中の 0 に見える。「行きたい」に入れたことは
            // 上のボタンが灯って伝えている
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 写真と近くのスポット

    @ViewBuilder
    private var spotPhotos: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpotDetailParts.sectionHeader(L("この場所の写真（\(linked.count)）", "Photos here (\(linked.count))"))
            if linked.isEmpty {
                // **空を隠さない。** 「まだ紐づいていない」と「読み込み中」は別
                Text(L("この場所に紐づいた公開写真はまだありません。投稿するときに場所を選ぶと、ここに並びます。",
                       "No public photos are linked to this place yet."))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
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
                SpotDetailParts.sectionHeader(L("近くの撮影スポット", "Nearby places"))
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
        if let coords = spot.coords {
            let center = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
            VStack(alignment: .leading, spacing: 10) {
                SpotDetailParts.sectionHeader(L("地図", "Map"))
                Map(position: $camera) {
                    Annotation(spot.label, coordinate: center) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(WebTheme.foreground)
                    }
                }
                .onAppear {
                    camera = .region(MKCoordinateRegion(
                        center: center,
                        // **約1km に丸めた座標**なので、これ以上寄せても精度は増えない
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .allowsHitTesting(false)
                .accessibilityLabel(L("\(spot.label) の地図", "Map of \(spot.label)"))
            }
        }
    }
}
