import SwiftUI
import MapKit

/// 台帳の撮影スポット（モック13）。
///
/// `SpotDetailView` が**撮影地の集まり**（写真から導く・モック5）を出すのに
/// 対して、こちらは Web の台帳 `content/spots.json` から落ちてきた索引の
/// 1件（`OfficialSpot`）を出す。写真との紐付けは `Photo.spotId` だけで、
/// 今日その写真は0枚——**全節が写真に依存する `SpotDetailView` を広げずに**
/// 別の画面にした。
///
/// 🔴 **下書きを「公式」と名乗らない。** 索引の全件が運営未確認の下書き
/// （2026-09-25）。小見出しと帯で最初にそう言う（`SpotScreen.eyebrow` /
/// `reviewNotice`）。**本文（見どころ・季節・アクセス）は出さない**——
/// v1 は索引しか読まず、出典の無い事実を画面に置かない（owner の判断）。
///
/// 並びはモック13: 地図 → 小見出し → 名前 → 地域と枚数 → 帯 → 行動3つ →
/// 概要 → この場所の写真 → 近くの撮影スポット。
struct OfficialSpotView: View {

    let spot: OfficialSpot
    /// 「近くの撮影スポット」を引く索引。呼び出し側が持っている一覧をそのまま渡す
    let spots: [OfficialSpot]
    /// 「この場所の写真」を引く公開写真。`spotId` で紐づいたものだけ数える
    let photos: [Photo]

    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter

    @State private var camera: MapCameraPosition = .automatic

    /// **確定した紐づけだけ**（`Photo.spotId`）。撮影地の文字列では当てない
    private var linked: [Photo] { photos.filter { $0.spotId == spot.spotId } }

    private var nearby: [(spot: OfficialSpot, km: Double)] {
        OfficialSpotIndex.nearby(spot, in: spots)
    }

    /// 「行きたい」の鍵。**撮影地の鍵と混ぜない**（`SavedSpotKey`）
    private var wishKey: String { SavedSpotKey.official(spot.slug) }

    /// 端末の地図アプリへ。**座標があるときだけ**（`SpotScreen`）
    private var mapURL: URL? { SpotScreen.mapURL(name: spot.name, coords: spot.coords) }

    /// 配る文。**サイトのリンクは入れない**（本番 main に `/spots` は無い）
    private var shareText: String {
        SpotScreen.shareText(name: spot.name, region: spot.regionLabel, mapURL: mapURL)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroMap
                header
                if let notice = SpotScreen.reviewNotice(review: spot.isDraft, draftedAt: spot.draftedAt) {
                    draftNotice(notice)
                }
                actions
                summary
                spotPhotos
                nearbySpots
            }
            .padding(.bottom, 32)
        }
        .webScreen()
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .webToolbarIcon()
            }
        }
        .accessibilityIdentifier("spot.official")
    }

    // MARK: - 地図（モックの代表画像の位置。写真が0枚なので地図を置く）

    /// **押せない地図**（`SpotDetailView.map` と同じ形）。動かしたい人は「地図で見る」へ
    @ViewBuilder
    private var heroMap: some View {
        if let coords = spot.coords {
            let center = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
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
            .frame(height: 232)
            .allowsHitTesting(false)
            .accessibilityLabel(L("\(spot.name) の地図", "Map of \(spot.name)"))
        }
    }

    // MARK: - 頭

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 小見出し（モックの "PHOTO SPOT"）。**下書きなら「下書き・未確認」**
            Text(SpotScreen.eyebrow(review: spot.isDraft))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(WebTheme.faint)
            Text(spot.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(WebTheme.foreground)
            // 「[都道府県] · [市区町村] · N枚の写真」。N は数えた値
            Text(SpotScreen.subtitle(region: spot.regionLabel, photoCount: linked.count))
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.muted2)
        }
        .padding(.horizontal, 16)
    }

    /// 下書きの帯。文は `SpotScreen.reviewNotice` が日付ごと組み立てる
    /// （生の `draftedAt` を `Text` に渡さない）
    private func draftNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
            Text(text)
                .font(.footnote)
                .foregroundStyle(WebTheme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("spot.official.draftNotice")
    }

    // MARK: - 行動（行きたい・地図で見る・シェア）

    private var actions: some View {
        HStack(spacing: 10) {
            let wanted = wishlist.contains(wishKey)
            Button {
                let now = wishlist.toggle(wishKey)
                toasts.show(now
                    ? L("「行きたい」に追加しました（この端末に保存）", "Added to your wishlist on this device")
                    : L("「行きたい」から外しました", "Removed from your wishlist"))
            } label: {
                SpotDetailParts.actionLabel(icon: wanted ? "heart.fill" : "heart",
                                            title: L("行きたい", "Want to go"), filled: wanted)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("spot.official.wish")

            if let url = mapURL {
                Link(destination: url) {
                    SpotDetailParts.actionLabel(icon: "map", title: L("地図で見る", "Open in Maps"), filled: false)
                }
                .buttonStyle(.plain)
            }

            ShareLink(item: shareText) {
                SpotDetailParts.actionLabel(icon: "square.and.arrow.up", title: L("シェア", "Share"), filled: false)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 概要（書かれたものだけ）

    @ViewBuilder
    private var summary: some View {
        if let text = spot.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - この場所の写真・近くの撮影スポット

    @ViewBuilder
    private var spotPhotos: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpotDetailParts.sectionHeader(L("この場所の写真（\(linked.count)）", "Photos here (\(linked.count))"))
            if linked.isEmpty {
                // **空を隠さない。** 紐づいた写真が無いことをそのまま言う
                Text(L("まだありません", "None yet"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .padding(.horizontal, 16)
            } else {
                PhotoGrid(photos: linked) { photo in
                    PhotoDetailView(photo: photo, context: linked)
                }
            }
        }
    }

    @ViewBuilder
    private var nearbySpots: some View {
        let near = nearby
        if !near.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SpotDetailParts.sectionHeader(L("近くの撮影スポット", "Nearby spots"))
                VStack(spacing: 0) {
                    ForEach(near, id: \.spot.id) { item in
                        NavigationLink {
                            OfficialSpotView(spot: item.spot, spots: spots, photos: photos)
                        } label: {
                            nearbyRow(item.spot, km: item.km)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }
        }
    }

    /// 近くの1行（モック13）: 印 → 名前 → 距離 → 矢印。表紙は無い（写真が無い）
    private func nearbyRow(_ other: OfficialSpot, km: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle")
                .foregroundStyle(WebTheme.muted2)
            VStack(alignment: .leading, spacing: 3) {
                Text(other.name)
                    .font(.system(size: 15))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                if other.isDraft {
                    Text(L("下書き", "Draft"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
            }
            Spacer(minLength: 8)
            // **距離は計算したもの。** 言い方は「近くの写真」と同じ関数（`NearbyPhotos.label`）
            Text(NearbyPhotos.label(km: km))
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.faint)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(WebTheme.placeholder)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}
