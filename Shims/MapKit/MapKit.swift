// MapKit の模型。
import Foundation
import SwiftUI
// `CLLocationCoordinate2D` は CoreLocation の型。本物も MapKit を読めば
// 透けて見えるので、同じ見え方にしておく
@_exported import CoreLocation

/// **地図の中身は `View` ではなく `MapContent`。** 本物と同じ形にしておく。
public protocol MapContent {}

public struct Map: View {
    public init<C: MapContent>(@MapContentBuilder content: () -> C) {}
    /// 見ている場所を持たせる版（初期表示を写真に合わせるのに使う）
    public init<C: MapContent>(position: Binding<MapCameraPosition>,
                               @MapContentBuilder content: () -> C) {}
    /// 操作部品（方位磁針など）を地図の外に置く版（iOS 17）
    public init<C: MapContent>(position: Binding<MapCameraPosition>, scope: Namespace.ID,
                               @MapContentBuilder content: () -> C) {}
    /// Apple の地点を押して選ぶ版（iOS 18・`MapSelection`）
    public init<V: Hashable, C: MapContent>(position: Binding<MapCameraPosition>,
                                            selection: Binding<MapSelection<V>?>,
                                            scope: Namespace.ID? = nil,
                                            @MapContentBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}

/// 地図がどこを見ているか。
public struct MapCameraPosition {
    public static let automatic = MapCameraPosition()
    public static func region(_ region: MKCoordinateRegion) -> MapCameraPosition { MapCameraPosition() }
    /// 自分の位置を追う（iOS 17）。`followsHeading` で向きにも合わせて地図を回す
    public static func userLocation(followsHeading: Bool = false,
                                    fallback: MapCameraPosition) -> MapCameraPosition {
        MapCameraPosition()
    }
    /// 本物は利用者が地図を動かすと false に戻る
    public var followsUserLocation: Bool { false }
    public var followsUserHeading: Bool { false }
    /// 自分の位置が取れないときに代わりに見る所
    public var fallbackPosition: MapCameraPosition? { nil }
}

/// `onMapCameraChange` が知らせる頻度。**動かし終わったとき**（`.onEnd`）だけを
/// 使う——動かすたびに絞ると「消えた」に見える
public enum MapCameraUpdateFrequency {
    case continuous, onEnd
}

/// カメラが動いたときに渡ってくるもの。本物は `camera` / `rect` も持つが、
/// 使う `region` だけを写している
public struct MapCameraUpdateContext {
    public let region: MKCoordinateRegion
}

/// 本物は MapKit が `View` に生やしている iOS 17 の口
extension View {
    public func onMapCameraChange(frequency: MapCameraUpdateFrequency = .onEnd,
                                  _ action: @escaping (MapCameraUpdateContext) -> Void)
        -> ModifiedContent<Self, Mod.Lifecycle> { ModifiedContent() }
}

public struct MKCoordinateSpan {
    public var latitudeDelta: Double
    public var longitudeDelta: Double
    public init(latitudeDelta: Double, longitudeDelta: Double) {
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}

public struct MKCoordinateRegion {
    public var center: CLLocationCoordinate2D
    public var span: MKCoordinateSpan
    public init(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        self.center = center
        self.span = span
    }
}

@resultBuilder
public struct MapContentBuilder {
    public static func buildBlock() -> EmptyMapContent { EmptyMapContent() }
    public static func buildBlock<C: MapContent>(_ c: C) -> C { c }
    public static func buildIf<C: MapContent>(_ c: C?) -> C? { c }
    public static func buildOptional<C: MapContent>(_ c: C?) -> C? { c }
    public static func buildExpression<C: MapContent>(_ c: C) -> C { c }
    /// 2つ・3つ並べる（本物は任意個）。自分の位置・写真のピン・撮影スポットのピン
    public static func buildBlock<C0: MapContent, C1: MapContent>(_ c0: C0, _ c1: C1) -> TupleMapContent { TupleMapContent() }
    public static func buildBlock<C0: MapContent, C1: MapContent, C2: MapContent>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleMapContent { TupleMapContent() }
}

public struct TupleMapContent: MapContent {}

/// 自分の位置の青い点（iOS 17）。**権限があるときだけ描かれ、自分では
/// 権限を尋ねない**（本物と同じ）
public struct UserAnnotation: MapContent {
    public init() {}
}

public struct EmptyMapContent: MapContent {
    public init() {}
}
extension Optional: MapContent where Wrapped: MapContent {}

/// `ForEach` は地図の中でも使える。**中身を `MapContent` として組む口**が
/// 要る（本物にも `@MapContentBuilder` を取る初期化子がある）。
extension ForEach: MapContent {
    public init<D: RandomAccessCollection, C: MapContent>(
        _ data: D, @MapContentBuilder content: @escaping (D.Element) -> C
    ) where D.Element: Identifiable {
        self.init(data) { _ in EmptyView() }
    }
}

public struct Annotation: MapContent {
    public init<C: View>(_ title: String, coordinate: CLLocationCoordinate2D,
                         @ViewBuilder content: () -> C) {}
}

// MARK: - 地図の操作部品（iOS 17）

/// 方位磁針。`scope` を渡すと地図の外（`mapScope` を付けた範囲）に置ける
public struct MapCompass: View {
    public init(scope: Namespace.ID? = nil) {}
    public var body: Never { fatalError("模型") }
}

extension View {
    /// 地図の既定の操作部品を差し替える
    public func mapControls<C: View>(@ViewBuilder _ content: () -> C) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    public func mapControlVisibility(_ visibility: VisibilityShim) -> ModifiedContent<Self, Mod.Style> { ModifiedContent() }
    /// この範囲の中なら、地図の外に置いた操作部品が地図とつながる
    public func mapScope(_ scope: Namespace.ID) -> ModifiedContent<Self, Mod.Layout> { ModifiedContent() }
}

// MARK: - 地点（iOS 18）

/// Apple の地図が描く地点（POI・地名・山や川）
public struct MapFeature: Hashable {
    public enum FeatureKind { case pointOfInterest, territory, physicalFeature }
    public var coordinate: CLLocationCoordinate2D
    public var title: String?
    public var kind: FeatureKind
    private let token = UUID()
    public static func == (a: MapFeature, b: MapFeature) -> Bool { a.token == b.token }
    public func hash(into h: inout Hasher) { h.combine(token) }
}

/// 地図で選ばれたもの。自分で tag した値か、Apple の地点のどちらか
public struct MapSelection<Value: Hashable>: Hashable {
    public var value: Value?
    public var feature: MapFeature?
}

/// 座標だけの地点（本物は `CLPlacemark` の子。使う口は `init(coordinate:)` だけ）
open class MKPlacemark: NSObject {
    public let coordinate: CLLocationCoordinate2D
    public init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

open class MKMapItem: NSObject {
    public var name: String?
    public override init() {}
    /// 座標から起こす（経路を Apple の地図に頼むとき）
    public init(placemark: MKPlacemark) {}
    @discardableResult
    open func openInMaps(launchOptions: [String: Any]? = nil) -> Bool { true }
}

public let MKLaunchOptionsDirectionsModeKey = "MKLaunchOptionsDirectionsMode"
public let MKLaunchOptionsDirectionsModeDefault = "MKLaunchOptionsDirectionsModeDefault"

/// 地点から `MKMapItem`（名前・住所・Apple の詳細カード用）を引く（iOS 18）
public final class MKMapItemRequest {
    public init(feature: MapFeature) {}
    public var mapItem: MKMapItem { get async throws { MKMapItem() } }
}

extension View {
    /// 押せる地点を絞る（iOS 18）
    public func mapFeatureSelectionDisabled(_ isDisabled: @escaping (MapFeature) -> Bool) -> ModifiedContent<Self, Mod.Input> { ModifiedContent() }
    /// Apple の詳細カード（iOS 18）。`item` が nil で閉じる
    public func mapItemDetailSheet(item: Binding<MKMapItem?>, displaysMap: Bool = true) -> ModifiedContent<Self, Mod.Navigation> { ModifiedContent() }
}
