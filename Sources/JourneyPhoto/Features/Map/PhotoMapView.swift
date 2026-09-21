import SwiftUI
import MapKit

/// 撮影地の地図。
///
/// **座標は約1km に丸めてある**ので、点が重なる。ピンを重ねて置くと
/// 数が分からなくなるため、同じ座標の写真はまとめて1つの印にする。
struct PhotoMapView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @State private var pins: [MapPin] = []
    /// 押したピン。**下の札に出す**（シートで画面を覆うと地図が見えない）
    @State private var selected: MapPin?
    /// 一覧を開くとき（札の「写真を見る →」）
    @State private var listing: MapPin?
    /// 地図の見ている場所。**写真に合わせてから開く**（指示書 9-2）
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera) {
            ForEach(pins) { pin in
                Annotation(pin.title, coordinate: pin.coordinate) {
                    Button {
                        selected = pin
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            RemoteImage(url: pin.photos.first?.gridImageURL,
                                        alignment: pin.photos.first?.gridAlignment ?? .center)
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
        // 押したピンの札。**地図を覆わない**ので、押したまま周りを見られる
        .overlay(alignment: .bottom) {
            if let selected {
                pinCard(selected)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .task { await load() }
        .sheet(item: $listing) { pin in
            NavigationStack {
                List(pin.photos) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo)
                    } label: {
                        HStack(spacing: 10) {
                            RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
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

    /// 押したピンの札（提案の絵）:
    ///
    ///     ┌──┐ 日本・宮城県
    ///     │📷│ この周辺の写真 12枚
    ///     └──┘ 写真を見る →
    private func pinCard(_ pin: MapPin) -> some View {
        Button {
            listing = pin
        } label: {
            HStack(spacing: 12) {
                RemoteImage(url: pin.photos.first?.gridImageURL,
                            alignment: pin.photos.first?.gridAlignment ?? .center)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(pin.title)
                        .font(.headline)
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(1)
                    Text(L("この周辺の写真 \(pin.photos.count)枚",
                           "\(pin.photos.count) photos nearby"))
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.faint)
                    Text(L("写真を見る →", "See photos →"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.98))
                }
                Spacer()
                Button {
                    selected = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WebTheme.muted2)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Common.close)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("map.pinCard")
    }

    private func load() async {
        let photos = (try? await environment.gallery.fetchPhotos()) ?? []
        pins = MapPin.group(photos)
        // **写真のある所に寄せてから開く。** 既定のままだと日本と
        // ヨーロッパを同時に収めようとして地球儀の縮尺になり、
        // 1枚ずつの写真が探せない（指示書 9-2）
        if let frame = MapFraming.frame(for: pins.map {
            (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }) {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: frame.latitude, longitude: frame.longitude),
                span: MKCoordinateSpan(latitudeDelta: frame.latitudeSpan,
                                       longitudeDelta: frame.longitudeSpan)
            ))
        }
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
