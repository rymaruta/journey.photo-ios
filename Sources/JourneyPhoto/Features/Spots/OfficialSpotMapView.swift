import SwiftUI
import MapKit

/// 撮影スポットの頁の「地図で見る」（2026-10-11）。**アプリの中の地図**でそのスポットを開く。
///
/// 以前は頁の「地図で見る」だけ Apple のマップ（アプリの外）へ飛んでいた。マイページ
/// （`SavedSpotsMapView`）・探す（地図のタブ）の「地図で見る」はアプリの中の地図なので、
/// 同じ語で行き先が割れていた。外の地図へ出るのは下の「経路」だけ。
///
///  - ピンは地図のタブ・行きたい場所の地図と同じ印（`SpotMapMarker`・真鍮）。押す動きは無い
///    （このスポットの頁から来ているので、開く先が無い）
///  - 地図は動かせる（頁の頭の地図は押せない・`OfficialSpotView.heroMap`）。自分の位置の点は
///    位置の許可があるときだけ描かれる（ここでは尋ねない）
///  - 下の帯（黒地）に名前・地域と「経路」。写真の無い画面の主ボタンなので真鍮の塗りに墨（CLAUDE.md）
struct OfficialSpotMapView: View {

    let spot: OfficialSpot

    @State private var camera: MapCameraPosition = .automatic
    /// 「経路」を探している最中（連打で2つ開かない）・その仕事（画面を離れたら取り消す）
    @State private var opening = false
    @State private var directionsTask: Task<Void, Never>?
    /// 画面が出ているか（探している間に戻ったら開かない）
    @State private var onScreen = false

    var body: some View {
        Group {
            if let coords = spot.coords {
                Map(position: $camera) {
                    UserAnnotation()
                    // 題は MapKit がピンの下に字で描く（地図のタブの撮影スポットと同じ）
                    Annotation(spot.name, coordinate: Self.coordinate(coords)) {
                        SpotMapMarker(photoURL: spot.photo?.smallURL, fallbackURL: spot.photo?.smallFallbackURL)
                            // 読み上げはピンに名前ごと（`TripDayMapView` と同じ）
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(spot.name)
                    }
                }
                .onAppear {
                    camera = .region(MKCoordinateRegion(
                        center: Self.coordinate(coords),
                        // **約1km に丸めた座標**なので、頁の頭の地図（0.05）と同じ寄せ方
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                }
                .safeAreaInset(edge: .bottom) {
                    bottomBar(coords)
                }
            } else {
                // 座標の無いスポットには頁が「地図で見る」を出さない（`SpotScreen.officialActions`）。
                // 万一来ても空の地図にしない
                Text(L("地図の場所が分かりません", "No map location"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .webScreen()
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { onScreen = true }
        .onDisappear {
            onScreen = false
            directionsTask?.cancel()
        }
        // 入れ物として名前を付ける。`Group` に直に付けると中の「経路」の名前まで上書きされ、
        // 試験が「経路」を見つけられなかった（run 407）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spot.official.mapScreen")
    }

    private static func coordinate(_ coords: Photo.Coords) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
    }

    /// 下の帯: 名前・地域と「経路」（Apple のマップ・今いる場所から）
    private func bottomBar(_ coords: Photo.Coords) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name)
                    .font(.headline)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(2)
                if let region = spot.regionLabel {
                    Text(region)
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                }
            }
            Button {
                guard !opening else { return }
                opening = true
                let name = spot.name
                directionsTask = Task { @MainActor in
                    defer { opening = false }
                    await SpotDirections.openDirections(name: name, coords: coords, stillWanted: { onScreen })
                }
            } label: {
                Label(opening ? L("開いています…", "Opening…") : L("経路", "Directions"),
                      systemImage: "arrow.triangle.turn.up.right.diamond")
                    .jpPillButton(.accent)
            }
            .buttonStyle(.plain)
            .disabled(opening)
            .accessibilityLabel(L("\(spot.name)への経路", "Directions to \(spot.name)"))
            .accessibilityHint(L("Apple のマップで開きます", "Opens in Apple Maps"))
            .accessibilityIdentifier("spot.official.mapScreen.directions")
        }
        .jpBottomBar()
    }
}
