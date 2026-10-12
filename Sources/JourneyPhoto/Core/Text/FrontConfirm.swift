import Foundation

/// 戻るスワイプ途中の `onAppear` で一覧を差し替えないための印。
///
/// NavigationStack では、詳細から戻るスワイプの途中で親の `onAppear` が一度走り、
/// やめると親の `onDisappear` が来る。その一瞬でブロック後の絞りや読み直し結果を
/// 入れると、押した元が消えて詳細が閉じる（H-2 回帰2と同型）。
///
/// - 初回の `appear` はすぐ確定（`isConfirmed == true`）
/// - 戻りの `appear` は未確定のまま。View 側で短い待ちのあと `confirm()` する
/// - 待ちのあいだに `disappear` したら確定しない（スワイプキャンセル）
struct FrontConfirm: Equatable {
    private(set) var didAppear = false
    private(set) var isShown = false
    /// 前面が確定して、一覧の差し替えをしてよい状態か
    private(set) var isConfirmed = false

    enum AppearKind: Equatable {
        /// 初めて前に出た。呼び出し側はすぐ適用してよい
        case first
        /// 詳細などから戻ってきた（またはスワイプ途中）。`confirm()` まで待つ
        case returning
    }

    mutating func appear() -> AppearKind {
        isShown = true
        if !didAppear {
            didAppear = true
            isConfirmed = true
            return .first
        }
        isConfirmed = false
        return .returning
    }

    mutating func disappear() {
        isShown = false
        isConfirmed = false
    }

    /// 戻り後に前面が確定した。初めて確定できたら true（呼び出し側が遅延適用する）
    @discardableResult
    mutating func confirm() -> Bool {
        guard isShown, !isConfirmed else { return false }
        isConfirmed = true
        return true
    }

    /// 戻るスワイプのキャンセルが `onDisappear` に来るまで待つ長さ。
    /// 短すぎるとキャンセルでも確定し、長すぎると戻ったあとの絞りが遅れる
    static let settleNanoseconds: UInt64 = 350_000_000
}
