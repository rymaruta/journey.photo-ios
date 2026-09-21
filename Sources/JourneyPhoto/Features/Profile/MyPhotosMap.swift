import SwiftUI
import MapKit

/// プロフィールの「マップ」（モック11）。
///
/// **渡された写真だけの地図。** 全員の写真はマップのタブにある。
/// ここは「この人がどこで撮ったか」を見る場所。
///
/// 初期表示は `MapFraming` に任せる——世界全体を出さない（指示書 9-2）。
struct MyPhotosMap: View {

    let photos: [Photo]

    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: MapPin?

    private var pins: [MapPin] { MapPin.group(photos) }

    var body: some View {
        Group {
            if pins.isEmpty {
                // **「地図が空」と「撮影地を書いていない」を分ける**
                ErrorBanner(message: L("撮影地の分かる写真がありません。投稿するときに場所を入れると、ここに並びます。",
                                       "No photos with a place yet. Add a place when you post."))
            } else {
                Map(position: $camera) {
                    ForEach(pins) { pin in
                        Annotation(pin.title, coordinate: pin.coordinate) {
                            Button {
                                selected = pin
                            } label: {
                                RemoteImage(url: pin.photos.first?.gridImageURL,
                                            alignment: pin.photos.first?.gridAlignment ?? .center)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .onAppear { frame() }
                .sheet(item: $selected) { pin in
                    NavigationStack {
                        ScrollView {
                            PhotoGrid(photos: pin.photos) { photo in
                                PhotoDetailView(photo: photo, context: pin.photos)
                            }
                            .padding(.vertical, 16)
                        }
                        .webScreen()
                        .navigationTitle(pin.title)
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
    }

    private func frame() {
        guard let frame = MapFraming.frame(for: pins.map {
            (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }) else { return }
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: frame.latitude, longitude: frame.longitude),
            span: MKCoordinateSpan(latitudeDelta: frame.latitudeSpan,
                                   longitudeDelta: frame.longitudeSpan)
        ))
    }
}
