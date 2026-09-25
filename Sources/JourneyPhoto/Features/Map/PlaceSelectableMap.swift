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
    /// Apple の地点情報がどこまで引けたか
    let lookup: Lookup

    enum Lookup {
        /// 引いている途中。経路・詳細はまだ押せない
        case loading
        /// Apple の地点情報が引けた（住所・電話・Web・詳細カード）
        case found(MKMapItem)
        /// 引けなかった。**経路だけは座標から出せる**——ボタンを押せないまま
        /// 残すと「押しても中身が見えない」になる（2026-09-25 owner）
        case coordinateOnly(MKMapItem)
    }

    /// 経路に使う地点（引けなかったときも座標から起こしたものがある）
    var mapItem: MKMapItem? {
        switch lookup {
        case .loading: return nil
        case .found(let item), .coordinateOnly(let item): return item
        }
    }

    /// Apple の詳細カードに出せる地点。**座標だけの地点は出さない**（中身が空のカードになる）
    var detailItem: MKMapItem? {
        if case .found(let item) = lookup { return item }
        return nil
    }

    var isLoading: Bool {
        if case .loading = lookup { return true }
        return false
    }

    static func == (lhs: ChosenPlace, rhs: ChosenPlace) -> Bool {
        lhs.id == rhs.id && lhs.stage == rhs.stage
    }

    private var stage: Int {
        switch lookup {
        case .loading: return 0
        case .found: return 1
        case .coordinateOnly: return 2
        }
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
    /// 方位磁針を地図の外に置くための名前（`PhotoMapView.mapScope`）
    let scope: Namespace.ID
    @Binding var chosen: ChosenPlace?
    /// Apple の詳細カードに出す地点。nil で閉じる
    @Binding var detail: MKMapItem?
    let onCameraChange: (MapCameraUpdateContext) -> Void
    let pins: () -> Pins

    /// 何も tag していないので、中に入るのは地点（feature）だけ
    @State private var selection: MapSelection<String>?

    init(camera: Binding<MapCameraPosition>,
         scope: Namespace.ID,
         chosen: Binding<ChosenPlace?>,
         detail: Binding<MKMapItem?>,
         onCameraChange: @escaping (MapCameraUpdateContext) -> Void,
         @MapContentBuilder pins: @escaping () -> Pins) {
        _camera = camera
        self.scope = scope
        _chosen = chosen
        _detail = detail
        self.onCameraChange = onCameraChange
        self.pins = pins
    }

    var body: some View {
        Map(position: $camera, selection: $selection, scope: scope) {
            pins()
        }
        .mapControls {
            // 既定の方位磁針は消す——`PhotoMapView.mapControls` の列に置いた方を使う
            MapCompass().mapControlVisibility(.hidden)
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
        chosen = ChosenPlace(id: id, name: name, coords: coords, lookup: .loading)

        Task {
            let lookup = await Self.lookUp(feature: feature, name: name, coords: coords)
            // **引いている間に別の地点へ移っていたら捨てる**
            guard chosen?.id == id else { return }
            chosen = ChosenPlace(id: id, name: name, coords: coords, lookup: lookup)
        }
    }

    /// 地点情報を引く。**Apple の地点 → 名前で検索し直す → 座標だけ** の順に落とす。
    ///
    /// `MKMapItemRequest` は地点によって失敗する。失敗したまま待たせると札の
    /// ボタンが永久に押せない。名前で検索し直した結果は、押した場所の
    /// すぐ近く（`PlaceLookup.sameSpotKm`）のものだけを同じ地点とみなす
    private static func lookUp(feature: MapFeature, name: String, coords: Photo.Coords) async -> ChosenPlace.Lookup {
        let requested = try? await MKMapItemRequest(feature: feature).mapItem
        if let requested {
            return .found(requested)
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.region = MKCoordinateRegion(center: feature.coordinate,
                                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        let searched = try? await MKLocalSearch(request: request).start()
        if let items = searched?.mapItems {
            let candidates = items.map {
                Photo.Coords(lat: $0.placemark.coordinate.latitude, lng: $0.placemark.coordinate.longitude)
            }
            if let index = PlaceLookup.nearestIndex(of: candidates, to: coords) {
                return .found(items[index])
            }
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: feature.coordinate))
        item.name = name
        return .coordinateOnly(item)
    }
}
