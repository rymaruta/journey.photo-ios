import Foundation

/// 送っていない変更がある画面から戻ろうとしたときの扱い。
///
/// 🔴 **送っていない変更があるまま黙って戻らせない。** 「保存」を右上に置く画面
/// （親しい友達・旅行プランの日程）は、戻るで下書きが黙って消える。
/// 変更がある間・送っている間は標準の戻る（と左端の払い）を隠し、自前の戻るで
/// 「保存して戻る／変更を捨てる／キャンセル」を確かめる（`unsavedLeaveGuard`）。
///
/// 以前は `CloseFriendsRows.leave` にあった。旅行プランの日程でも同じものが
/// 要るので、**2つ目の仕組みを作らずに**ここへ寄せた（判断も文言も1つ）。
///
/// **`@MainActor` の型に置かない**（テストから呼べなくなる）。
enum UnsavedLeave: Equatable {
    /// そのまま戻る（送っていない変更が無い）
    case now
    /// 「保存して戻る／変更を捨てる／キャンセル」を確かめる
    case confirm
    /// 送っている最中は戻らせない（途中の失敗が消えた画面に出る）
    case wait

    static func decide(hasChanges: Bool, isSaving: Bool) -> UnsavedLeave {
        if isSaving { return .wait }
        return hasChanges ? .confirm : .now
    }
}
