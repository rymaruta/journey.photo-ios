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
    /// 地図がまだ読めていない・読むのに失敗した。**「無い」と分けるため**
    var couldNotLoad = true

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hidden: ModerationStore
    @State private var radius = NearbyPhotos.defaultRadius
    /// 🔴 シートの中の詳細でブロック／通報して戻ったら落とす。**戻ったとき
    /// （`onAppear`）だけ**写しを取り直す（見ている最中に絞ると詳細が閉じる）
    @State private var dropped: ModerationSnapshot?

    private var found: [(photo: Photo, km: Double)] {
        NearbyPhotos.photos(dropped?.visible(photos) ?? photos, near: center, withinKm: radius)
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
                    if photos.isEmpty && couldNotLoad {
                        // 🔴 **「無い」と「取れていない」を分ける。**
                        // 地図が1枚も持っていないのは「この範囲に無い」では
                        // なく「まだ読めていない」——同じ文で出すと、
                        // 圏外の人に「近くには何も無い」と言うことになる
                        // 地図に引き下げの読み直しは無い——開き直すと読む（地図の帯と同じ文）
                        Text(L("写真をまだ読み込めていません。地図を開き直すと読み直します。",
                               "Photos haven't loaded yet. Reopen the map to retry."))
                            .font(.callout)
                            .foregroundStyle(WebTheme.muted2)
                    } else if found.isEmpty {
                        // ここまで来たら、測った結果として本当に無い
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
            .onAppear { dropped = hidden.snapshot }
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
