// この下は **Linux で型検査するためだけの模型**。実機では一切使わない。
//
// iOS SDK が無い環境でも、画面のコードを `swiftc` に通したい。SwiftUI の
// 「形」だけを宣言しておけば、**自分たちのコードの誤り**——綴り違い、
// 無いプロパティ、引数ラベルの不一致、型の取り違え——はコンパイラが捕まえる。
//
// **これが通っても「SwiftUI として正しい」とは言えない。** 修飾子はどれも
// 素通し（`Self` を返すだけ）なので、SwiftUI 側の制約（ViewBuilder の枝の数、
// `some View` の同一性、修飾子の順序、実行時の挙動）は見ていない。
//
// 作りの決めごと:
//   - **部品は総称にしない。** `init` の方を総称にする。`Label<Title, Icon>`
//     のように型に総称を置くと `Label("x", systemImage: "y")` で推論できない
//   - **Foundation を再輸出する。** 本物の SwiftUI もそうしていて、画面の
//     ファイルは `import Foundation` を書いていない
@_exported import Foundation

@resultBuilder
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<C: View>(_ c: C) -> C { c }
    // **可変長パックにしない。** 1個の場合の overload と曖昧になり、
    // 枝が2つ以上あるところで型推論が落ちる（本物の SwiftUI も arity ごとの
    // overload で組んである）
    public static func buildBlock<C1: View, C2: View>(_ c1: C1, _ c2: C2) -> AnyView { AnyView() }
    public static func buildBlock<C1: View, C2: View, C3: View>(_ c1: C1, _ c2: C2, _ c3: C3) -> AnyView { AnyView() }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> AnyView { AnyView() }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> AnyView { AnyView() }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View, C6: View>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> AnyView { AnyView() }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> AnyView { AnyView() }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> AnyView { AnyView() }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> AnyView { AnyView() }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View, C10: View>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9, _ c10: C10) -> AnyView { AnyView() }
    // **Optional をそのまま返す。** `AnyView` に潰すと、else の無い `if` で
    // `nil` から型を決められず「generic parameter 'C' could not be inferred」に
    // なる（本物の SwiftUI も `C?` を返す）
    public static func buildIf<C: View>(_ c: C?) -> C? { c }
    public static func buildOptional<C: View>(_ c: C?) -> C? { c }
    public static func buildEither<T: View>(first: T) -> AnyView { AnyView() }
    public static func buildEither<F: View>(second: F) -> AnyView { AnyView() }
    public static func buildArray<C: View>(_ c: [C]) -> AnyView { AnyView() }
    public static func buildExpression<C: View>(_ c: C) -> C { c }
    public static func buildLimitedAvailability<C: View>(_ c: C) -> AnyView { AnyView() }
    public static func buildFinalResult<C: View>(_ c: C) -> C { c }
}

/// **`@MainActor`。** Swift 6 の SwiftUI はこの形で、適合した型の中身は
/// まとめてメインアクタに載る。ここを外すと、画面の補助プロパティから
/// `@MainActor` の値を触るだけで落ちる（実機では起きない）。
@MainActor
public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor var body: Self.Body { get }
}

extension Never: View {
    nonisolated public var body: Never { fatalError("模型") }
}

extension Optional: View where Wrapped: View {
    nonisolated public var body: Never { fatalError("模型") }
}

public struct AnyView: View {
    // **`nonisolated`。** `ViewBuilder` の各メソッドはアクタに属さないので、
    // ここが MainActor だと模型自身がコンパイルできない
    nonisolated public init() {}
    nonisolated public init<V: View>(_ view: V) {}
    public var body: Never { fatalError("模型") }
}

public struct EmptyView: View {
    nonisolated public init() {}
    public var body: Never { fatalError("模型") }
}
