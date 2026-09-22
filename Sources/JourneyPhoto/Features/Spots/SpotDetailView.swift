import SwiftUI
import MapKit

/// 撮影スポットの詳細（モック5）。
///
/// 出すのは**台帳に実際に入っているものと、数えられるものだけ**。
///
/// **モックにあって出さないもの**: ★評価・口コミ件数・「行きたい」人数。
/// どれも集計していないので、置けば嘘になる。「行きたい」は押せるが
/// **この端末にしか残らない**ので、数ではなく状態だけを出す。
struct SpotDetailView: View {

    let spot: Spot
    /// 突き合わせる写真。呼び出し側が持っている一覧をそのまま渡す
    let photos: [Photo]
    /// 近くのスポットを出すための台帳（無ければその棚は出ない）
    var ledger: [Spot] = []

    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter

    @State private var page = 0
    @State private var expanded = false
    @State private var camera: MapCameraPosition = .automatic

    private var linked: [Photo] { SpotDirectory.photos(of: spot, in: photos) }

    /// 見出しの写真。台帳の代表写真を先頭に、残りを新しい順
    private var hero: [Photo] {
        guard let cover = SpotDirectory.cover(of: spot, in: photos) else { return [] }
        return [cover] + linked.filter { $0.id != cover.id }
    }

    private var nearby: [Spot] {
        guard let coords = spot.coords else { return [] }
        return SpotDirectory.nearby(coords, in: ledger, radiusKm: 30, limit: 8)
            .filter { $0.spotId != spot.spotId }
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
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: spot.name) {
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
                    Text("\(min(page + 1, hero.count))/\(hero.count)")
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
            Text(spot.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(WebTheme.foreground)
            if let reading = spot.reading, !reading.isEmpty {
                Text(reading)
                    .font(.footnote)
                    .foregroundStyle(WebTheme.faint)
            }
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
            if let category = spot.category, !category.isEmpty {
                Text(category)
                    .font(.footnote.weight(.semibold))
                    .webChip()
            }
        }
        .padding(.horizontal, 16)
    }

    /// 住所があれば住所、無ければ地域の行。**両方出して同じことを2回言わない**
    private var placeLine: String? {
        if let address = spot.address?.trimmingCharacters(in: .whitespaces), !address.isEmpty {
            return address
        }
        let region = spot.region?.line ?? ""
        return region.isEmpty ? nil : region
    }

    @ViewBuilder
    private var summary: some View {
        if let text = spot.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted)
                    .lineSpacing(4)
                    .lineLimit(expanded ? nil : 3)
                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? L("閉じる", "Show less") : L("もっと見る", "Show more"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                }
                .buttonStyle(.plain)
                .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 操作

    private var actions: some View {
        HStack(spacing: 10) {
            let wanted = wishlist.contains(spot.spotId)
            Button {
                let now = wishlist.toggle(spot.spotId)
                toasts.show(now
                    ? L("「行きたい」に追加しました（この端末に保存）", "Added to your wishlist on this device")
                    : L("「行きたい」から外しました", "Removed from your wishlist"))
            } label: {
                actionLabel(icon: wanted ? "heart.fill" : "heart",
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
                actionLabel(icon: "square.and.arrow.up", title: L("シェア", "Share"), filled: false)
            }
            .buttonStyle(.plain)

            if let url = mapURL {
                Link(destination: url) {
                    actionLabel(icon: "map", title: L("地図で見る", "Open in Maps"), filled: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    /// 配る文。**名前と、あれば地図のリンク**。
    /// 住所は台帳にあるときだけ足す（無い行に空行を作らない）
    private var shareText: String {
        var parts = [spot.name]
        if let line = spot.region?.line, !line.isEmpty { parts.append(line) }
        if let url = mapURL { parts.append(url.absoluteString) }
        return parts.joined(separator: "\n")
    }

    private func actionLabel(icon: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(filled ? AnyShapeStyle(WebTheme.foreground) : AnyShapeStyle(WebTheme.surface),
                    in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(filled ? WebTheme.accentText : WebTheme.foreground)
    }

    /// 端末の地図アプリへ。**座標があるときだけ**
    private var mapURL: URL? {
        guard let coords = spot.coords else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(coords.lat),\(coords.lng)"),
            URLQueryItem(name: "q", value: spot.name),
        ]
        return components?.url
    }

    /// 数えられるものだけ。**評価・口コミ・行きたい人数は出さない**
    private var stats: some View {
        HStack(spacing: 8) {
            statPill(icon: "camera", value: "\(linked.count)",
                     label: L("この場所の写真", "Photos here"))
            // **「—」の数え札を並べない。** 数えていないものを数の形に
            // 置くと、読み込み中の 0 に見える。「行きたい」に入れたことは
            // 上のボタンが灯って伝えている
        }
        .padding(.horizontal, 16)
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption)
                Text(value).font(.headline)
            }
            .foregroundStyle(WebTheme.foreground)
            Text(label)
                .font(.caption2)
                .foregroundStyle(WebTheme.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 写真と近くのスポット

    @ViewBuilder
    private var spotPhotos: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(L("この場所の写真（\(linked.count)）", "Photos here (\(linked.count))"))
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
        if !near.isEmpty, let here = spot.coords {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("近くの撮影スポット", "Nearby places"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(near) { other in
                            NavigationLink {
                                SpotDetailView(spot: other, photos: photos, ledger: ledger)
                            } label: {
                                nearbyCard(other, from: here)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func nearbyCard(_ other: Spot, from here: Photo.Coords) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    RemoteImage(url: SpotDirectory.cover(of: other, in: photos)?.gridImageURL,
                                alignment: .center)
                }
                .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(other.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                // **距離は計算したもの。** 言い方は「近くの写真」と
                // 同じ関数に寄せる（`NearbyPhotos.label`）——2つ持つと、
                // 同じ距離が画面によって「約42.7km」と「約43km」に割れる
                Text(distanceText(from: here, to: other))
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 180)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 距離の言い方。**「近くの写真」と同じ関数**を通す。
    /// 座標が無い相手は測れないので、何も言わない（「0km」と書かない）
    private func distanceText(from: Photo.Coords, to other: Spot) -> String {
        guard let there = other.coords else { return "" }
        return NearbyPhotos.label(km: TravelDistance.kilometers(from: from, to: there))
    }

    @ViewBuilder
    private var map: some View {
        if let coords = spot.coords {
            let center = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(L("地図", "Map"))
                Map(position: $camera) {
                    Annotation(spot.name, coordinate: center) {
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
                .accessibilityLabel(L("\(spot.name) の地図", "Map of \(spot.name)"))
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(WebTheme.foreground)
            .padding(.horizontal, 16)
    }
}
