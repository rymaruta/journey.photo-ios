// 本物の SDK で Sendable の型を、模型でも Sendable にする（2026-11-25・Swift 6 へ移す作業）。
//
// 模型の public な型は、Sendable と書かないと Sendable にならない。本物で Sendable の型が模型で
// そうでないと、本物では出ない並行処理の警告が Linux で出る（例: `static let` の `Font`）。
// 本物で Sendable と分かっている型だけを並べる。分からない型は足さない（本物で出る警告を隠さないため）
extension Font: @unchecked Sendable {}
extension Font.Weight: @unchecked Sendable {}
extension Font.TextStyle: @unchecked Sendable {}
extension Color: @unchecked Sendable {}
extension UIImageShim: @unchecked Sendable {}
extension UIColorShim: @unchecked Sendable {}
extension DynamicTypeSize: @unchecked Sendable {}
extension ColorScheme: @unchecked Sendable {}
extension ScenePhase: @unchecked Sendable {}
extension ContentMode: @unchecked Sendable {}
extension Axis: @unchecked Sendable {}
extension TextAlignment: @unchecked Sendable {}
extension Alignment: @unchecked Sendable {}
extension HorizontalAlignment: @unchecked Sendable {}
extension VerticalAlignment: @unchecked Sendable {}
extension Edge: @unchecked Sendable {}
extension Animation: @unchecked Sendable {}
extension Angle: @unchecked Sendable {}
extension EdgeInsets: @unchecked Sendable {}
extension Font.Design: @unchecked Sendable {}

// Apple の Dispatch では Sendable（Linux の Dispatch では書かれていない）。模型の側でそろえる
import Dispatch
extension DispatchSpecificKey: @unchecked @retroactive Sendable {}
