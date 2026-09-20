// MapKit の模型。
import Foundation
import SwiftUI

public struct CLLocationCoordinate2D {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// **地図の中身は `View` ではなく `MapContent`。** 本物と同じ形にしておく。
public protocol MapContent {}

public struct Map: View {
    public init<C: MapContent>(@MapContentBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
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
