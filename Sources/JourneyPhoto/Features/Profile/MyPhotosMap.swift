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
    /// 自分の写真の地図か。**空のときの言い方が変わる**（`emptyMessage`）
    let isMine: Bool
    /// 開いた写真に個別ページが在るか（`PhotoDetailView.fromPublicFeed`）。
    /// **写真ごとに決める**——写真の詳細の「地図で見る」から来たとき、
    /// 個別ページの無い自分の写真に共有を出さず、近くの公開写真には出す
    /// （`NearbyPhotos.fromPublicFeed`）
    var fromPublicFeed: (Photo) -> Bool = { _ in true }
    /// ピンの一覧のシートを閉じた。**下の画面が絞り直す合図**——シートを
    /// 閉じても下の画面に `onAppear` は来ない
    var onSheetDismiss: () -> Void = {}

    @EnvironmentObject private var hidden: ModerationStore
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: MapPin?
    /// 🔴 シートの中の詳細でブロック／通報して閉じたら、ピンからも落とす
    /// （閉じたとき・出たときだけ取り直す）
    @State private var dropped: ModerationSnapshot?

    private var pins: [MapPin] { MapPin.group(dropped?.visible(photos) ?? photos) }

    /// 空の地図の案内。🔴 **「投稿するときに場所を入れると」は本人にだけ言う**——
    /// 人のページで、見ている人を投稿した人として扱っていた。ほかは地図のタブ
    /// （`PhotoMapView`）と同じ言い方
    nonisolated static func emptyMessage(isMine: Bool) -> String {
        isMine
            ? L("撮影地の分かる写真がありません。投稿するときに場所を入れると、ここに並びます。",
                "No photos with a place yet. Add a place when you post.")
            : L("撮影地の分かる写真がありません", "No photos with a place yet")
    }

    var body: some View {
        Group {
            if pins.isEmpty {
                // **「地図が空」と「撮影地を書いていない」を分ける**
                ErrorBanner(message: Self.emptyMessage(isMine: isMine))
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
                .sheet(item: $selected, onDismiss: {
                    dropped = hidden.snapshot
                    onSheetDismiss()
                }) { pin in
                    NavigationStack {
                        VisiblePhotos(photos: pin.photos) { photos in
                        ScrollView {
                            PhotoGrid(photos: photos) { photo in
                                PhotoDetailView(photo: photo, fromPublicFeed: fromPublicFeed(photo), context: photos)
                            }
                            .padding(.vertical, 16)
                        }
                        }
                        .webScreen()
                        .navigationTitle(pin.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                        }
                    }
                }
            }
        }
        .onAppear { dropped = hidden.snapshot }
    }

    private func frame() {
        guard let frame = MapFraming.frame(for: pins.map {
            (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }, weights: pins.map(\.photos.count)) else { return }
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: frame.latitude, longitude: frame.longitude),
            span: MKCoordinateSpan(latitudeDelta: frame.latitudeSpan,
                                   longitudeDelta: frame.longitudeSpan)
        ))
    }
}
