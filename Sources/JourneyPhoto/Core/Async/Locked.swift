import Foundation

/// **ロックで守った値**（2026-11-25 判断・Swift 6 へ移す作業）。
///
/// どのスレッドからも読み書きされる `static var`（試験の差し替えの口・使い回す書式器の控え・
/// 世代の数など）を、Swift 6 の確かめに通る形で持つ。中身の出し入れはいつも `lock` の中なので、
/// 同時に触っても壊れない。
///
/// `@unchecked Sendable` はここ1か所に集める（2026-11-25 判断）: iOS 17 では標準の `Mutex`
/// （iOS 18 から）が使えず、`OSAllocatedUnfairLock` は Linux の型検査に無い。`NSLock` で守る形は
/// コンパイラには確かめられないので、守り方をこの型の中だけに閉じ込める。
/// 中身を外へ持ち出すのは `value`（写しを返す）か `withLock`（ロックの中で触る）だけにする
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    /// 今の値の写し（読む・置き換える）
    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }

    /// ロックの中で値を読み書きする（読んでから書くまでを1つにまとめたいとき）
    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&stored)
    }
}
