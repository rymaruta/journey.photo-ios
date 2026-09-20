import SwiftUI
import MapKit

/// 撮影地の地図。
///
/// **座標は約1km に丸めてある**ので、点が重なる。ピンを重ねて置くと
/// 数が分からなくなるため、同じ座標の写真はまとめて1つの印にする。
struct PhotoMapView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @State private var pins: [MapPin] = []
    @State private var selected: MapPin?

    var body: some View {
        Map {
            ForEach(pins) { pin in
                Annotation(pin.title, coordinate: pin.coordinate) {
                    Button {
                        selected = pin
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            RemoteImage(url: pin.photos.first?.gridImageURL)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            if pin.photos.count > 1 {
                                Text("\(pin.photos.count)")
                                    .font(.caption2.weight(.bold))
                                    .padding(4)
                                    .background(.thinMaterial, in: Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(Labels.Navigation.map)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $selected) { pin in
            NavigationStack {
                List(pin.photos) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo)
                    } label: {
                        HStack(spacing: 10) {
                            RemoteImage(url: photo.gridImageURL)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(photo.displayTitle.isEmpty ? (photo.location ?? L("写真", "Photo")) : photo.displayTitle)
                        }
                    }
                }
                .navigationTitle(pin.title)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func load() async {
        let photos = (try? await environment.gallery.fetchPhotos()) ?? []
        pins = MapPin.group(photos)
    }
}

struct MapPin: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let photos: [Photo]

    static func == (lhs: MapPin, rhs: MapPin) -> Bool { lhs.id == rhs.id }

    /// 同じ座標の写真をまとめる。丸めてあるので、そのまま文字列にして鍵にできる。
    static func group(_ photos: [Photo]) -> [MapPin] {
        var buckets: [String: [Photo]] = [:]
        for photo in photos {
            guard let coords = photo.coords else { continue }
            let key = "\(coords.lat),\(coords.lng)"
            buckets[key, default: []].append(photo)
        }
        return buckets.compactMap { key, photos in
            guard let coords = photos.first?.coords else { return nil }
            let title = photos.first(where: { !($0.location ?? "").isEmpty })?.location ?? L("撮影地", "Place")
            return MapPin(
                id: key,
                coordinate: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng),
                title: title,
                photos: photos
            )
        }
        .sorted { $0.id < $1.id }
    }
}
