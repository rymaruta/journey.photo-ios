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
    public var body: Never { fatalError("模型") }
}

/// 地図がどこを見ているか。
public struct MapCameraPosition {
    public static let automatic = MapCameraPosition()
    public static func region(_ region: MKCoordinateRegion) -> MapCameraPosition { MapCameraPosition() }
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
