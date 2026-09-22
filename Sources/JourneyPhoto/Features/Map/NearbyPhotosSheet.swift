import SwiftUI

/// 現在地の周りの写真（モック3-7）。
///
/// **現在地は端末の中だけ。** 送らないし、残さない（`CurrentLocation` の
/// 約束をここでも守る）。距離は手元の座標どうしで測る。
///
/// ⚠️ 座標は保存時に**約1kmへ丸めてある**ので、モックの「500m以内」は
/// 出せない。**持っていない精度を言わない**——出すのは「約Nkm」と件数。
struct NearbyPhotosSheet: View {

    let center: Photo.Coords
    let photos: [Photo]

    @Environment(\.dismiss) private var dismiss
    @State private var radius = NearbyPhotos.defaultRadius

    private var found: [(photo: Photo, km: Double)] {
        NearbyPhotos.photos(photos, near: center, withinKm: radius)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L("範囲", "Range"), selection: $radius) {
                        ForEach(NearbyPhotos.radiusChoices, id: \.self) { km in
                            Text(L("約\(Int(km))km", "about \(Int(km)) km")).tag(km)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(L("撮影地はおよそ1kmの粗さで保存されています。距離は目安です。",
                           "Shooting spots are stored at about 1 km precision, so distances are approximate."))
                }
                .listRowBackground(Color.clear)

                Section {
                    if found.isEmpty {
                        // **「無い」と「取れない」を分ける。** ここは手元の
                        // 配列を測っただけなので、無いときは本当に無い
                        Text(L("この範囲には、まだ写真がありません。", "No photos in this range yet."))
                            .font(.callout)
                            .foregroundStyle(WebTheme.muted2)
                    } else {
                        ForEach(found, id: \.photo.id) { item in
                            NavigationLink {
                                PhotoDetailView(photo: item.photo, context: found.map(\.photo))
                            } label: {
                                row(item)
                            }
                        }
                    }
                } header: {
                    Text(NearbyPhotos.heading(radiusKm: radius, count: found.count))
                }
                .listRowBackground(Color.clear)
            }
            .webScreen()
            .navigationTitle(L("近くの写真", "Photos near me"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("閉じる", "Close")) { dismiss() }
                }
            }
        }
    }

    private func row(_ item: (photo: Photo, km: Double)) -> some View {
        HStack(spacing: 10) {
            RemoteImage(url: item.photo.gridImageURL, alignment: item.photo.gridAlignment)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.photo.displayTitle.isEmpty
                     ? (item.photo.location ?? L("写真", "Photo"))
                     : item.photo.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                Text(NearbyPhotos.label(km: item.km))
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
            }
        }
    }
}
