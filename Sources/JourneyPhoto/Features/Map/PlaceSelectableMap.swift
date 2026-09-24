import SwiftUI
import MapKit

/// 地図で選んだ地点（Apple の地図が描く POI——大学・美術館・駅など）。
///
/// **iOS 17 の型だけで持つ。** 選択の仕組み（`MapFeature` / `MapSelection`）は
/// iOS 18 からなので、それを `PhotoMapView` の `@State` に置くと
/// iOS 17 で組めない。iOS 18 の部分は `PlaceSelectableMap` に閉じ込め、
/// 外にはこの値だけを渡す。
struct ChosenPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let coords: Photo.Coords
    /// Apple の詳細カード・経路に使う。**引けるまで（引けなければずっと）nil**
    /// ——nil の間はその2つのボタンを押せなくする
    let mapItem: MKMapItem?

    static func == (lhs: ChosenPlace, rhs: ChosenPlace) -> Bool {
        lhs.id == rhs.id && (lhs.mapItem == nil) == (rhs.mapItem == nil)
    }
}

/// 地点を押せる地図（iOS 18 以降）。
///
///     地点を押す → `chosen` に名前と座標 → 裏で MKMapItem を引いて差し替える
///
/// 写真のピン（`pins`）は**選択に乗せない**——今まで通り中のボタンで
/// 選ばれる（`PhotoMapView.selected`）。ここで拾うのは Apple の地点だけ。
@available(iOS 18.0, *)
struct PlaceSelectableMap<Pins: MapContent>: View {

    @Binding var camera: MapCameraPosition
    @Binding var chosen: ChosenPlace?
    /// Apple の詳細カードに出す地点。nil で閉じる
    @Binding var detail: MKMapItem?
    let onCameraChange: (MapCameraUpdateContext) -> Void
    let pins: () -> Pins

    /// 何も tag していないので、中に入るのは地点（feature）だけ
    @State private var selection: MapSelection<String>?

    init(camera: Binding<MapCameraPosition>,
         chosen: Binding<ChosenPlace?>,
         detail: Binding<MKMapItem?>,
         onCameraChange: @escaping (MapCameraUpdateContext) -> Void,
         @MapContentBuilder pins: @escaping () -> Pins) {
        _camera = camera
        _chosen = chosen
        _detail = detail
        self.onCameraChange = onCameraChange
        self.pins = pins
    }

    var body: some View {
        Map(position: $camera, selection: $selection) {
            pins()
        }
        // **押せるのは地点だけ。** 地名（都市・国）や山・川を押しても
        // 「この付近の写真」の範囲（約1km）と噛み合わない
        .mapFeatureSelectionDisabled { feature in
            feature.kind != .pointOfInterest
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            onCameraChange(context)
        }
        .onChange(of: selection) { _, newValue in
            guard let feature = newValue?.feature else {
                chosen = nil
                return
            }
            choose(feature)
        }
        // 札の「閉じる」やピンを押して外れたら、地図の選択も外す
        // （外さないと、同じ地点をもう一度押しても何も起きない）
        .onChange(of: chosen) { _, newValue in
            if newValue == nil, selection != nil {
                selection = nil
            }
        }
        .mapItemDetailSheet(item: $detail, displaysMap: false)
    }

    /// **名前と座標はすぐ出す。** MKMapItem は通信で引くので、
    /// 待たせずに札を出して、引けたら差し替える
    private func choose(_ feature: MapFeature) {
        let coordinate = feature.coordinate
        let name = feature.title ?? L("名前のない場所", "Unnamed place")
        let id = "\(coordinate.latitude),\(coordinate.longitude),\(name)"
        let coords = Photo.Coords(lat: coordinate.latitude, lng: coordinate.longitude)
        chosen = ChosenPlace(id: id, name: name, coords: coords, mapItem: nil)

        Task {
            let item = try? await MKMapItemRequest(feature: feature).mapItem
            // **引いている間に別の地点へ移っていたら捨てる**
            guard let item, chosen?.id == id else { return }
            chosen = ChosenPlace(id: id, name: name, coords: coords, mapItem: item)
        }
    }
}
