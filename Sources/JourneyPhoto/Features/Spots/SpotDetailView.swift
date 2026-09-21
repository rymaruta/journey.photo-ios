import SwiftUI
import MapKit

/// 撮影スポットの詳細（Phase 1）。
///
/// 出すのは**台帳に実際に入っているものだけ**——名前・住所・地域・種別・
/// 代表写真・地図・紐づいた公開写真。
///
/// **出さないもの**: 保存数・人気順位・訪問者数・レビュー。どれも
/// 集計していないので、置けば嘘になる（指示書 15）。枚数だけは
/// 「いま画面に並んでいる写真の数」なので、数えて出してよい。
struct SpotDetailView: View {

    let spot: Spot
    /// 突き合わせる写真。呼び出し側が持っている一覧をそのまま渡す
    let photos: [Photo]

    @State private var camera: MapCameraPosition = .automatic

    private var linked: [Photo] { SpotDirectory.photos(of: spot, in: photos) }
    private var cover: Photo? { SpotDirectory.cover(of: spot, in: photos) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                coverImage
                header
                map
                related
            }
            .padding(.bottom, 32)
        }
        .webScreen()
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var coverImage: some View {
        if let cover {
            Color.clear
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .overlay { RemoteImage(url: cover.detailImageURL, alignment: .center) }
                .clipped()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(spot.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(WebTheme.foreground)

            if let category = spot.category, !category.isEmpty {
                Text(category)
                    .font(.footnote.weight(.semibold))
                    .webChip()
            }

            // 住所と地域は**持っているものだけ**出す（空の行を作らない）
            if let address = spot.address, !address.trimmingCharacters(in: .whitespaces).isEmpty {
                row(icon: "mappin.and.ellipse", text: address)
            }
            if let line = spot.region?.line, !line.isEmpty {
                row(icon: "globe.asia.australia", text: line)
            }
        }
        .padding(.horizontal, 16)
    }

    private func row(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(WebTheme.faint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted)
        }
    }

    @ViewBuilder
    private var map: some View {
        if let coords = spot.coords {
            let center = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
            // **印は `Annotation`**（マップのタブ・マイページと同じ作り）。
            // 見ている場所は `onAppear` で合わせる——`@State` は `let` から
            // 初期化できないので、`MyPhotosMap` と同じ手順に揃える
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
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
            .accessibilityLabel(L("\(spot.name) の地図", "Map of \(spot.name)"))
        }
    }

    @ViewBuilder
    private var related: some View {
        VStack(alignment: .leading, spacing: 12) {
            // **「この場所の写真」の数は数えたもの。** 並んでいる枚数そのもの
            Text(L("この場所の写真（\(linked.count)）", "Photos here (\(linked.count))"))
                .font(.headline)
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, 16)

            if linked.isEmpty {
                // **空を隠さない。** 「まだ紐づいた写真が無い」と「読み込み中」は別
                Text(L("この場所に紐づいた公開写真はまだありません。投稿するときに場所を選ぶと、ここに並びます。",
                       "No public photos are linked to this place yet."))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .padding(.horizontal, 16)
            } else {
                // 押したら**今まで通りの写真詳細**へ（別の詳細画面を作らない）
                PhotoGrid(photos: linked) { photo in
                    PhotoDetailView(photo: photo, context: linked)
                }
            }
        }
    }
}
