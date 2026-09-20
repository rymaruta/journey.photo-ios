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

public struct Map: View {
    public init<C>(@MapContentBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}

@resultBuilder
public struct MapContentBuilder {
    public static func buildBlock<C>(_ c: C) -> C { c }
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildExpression<C>(_ c: C) -> C { c }
}

public struct Annotation: View {
    public init<C: View>(_ title: String, coordinate: CLLocationCoordinate2D,
                         @ViewBuilder content: () -> C) {}
    public var body: Never { fatalError("模型") }
}
