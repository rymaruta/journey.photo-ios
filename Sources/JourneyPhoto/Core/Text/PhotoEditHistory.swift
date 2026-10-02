import Foundation

/// 写真の編集の履歴: 取り消し・やり直し・リセット・「編集前と比べる」。
///
/// - **つまみを動かしている途中の値は1手にまとめる。** 動かしている間は `preview(_:)` で
///   見えている値だけを変え、指を離したら `commit()` で1手にする（途中の値を全部積むと、
///   取り消しを何十回も押すことになる）
/// - プリセットを押す・リセットのような1回で終わる操作は `apply(_:)`（preview＋commit）
/// - 取り消せるのは最大 `limit`（50）手。古いものから捨てる
/// - リセットは「無編集に戻す」**1手**（取り消せる）。編集前（`original`）へ戻すのではない
///   ——下書きを開き直したとき、前回の編集まで消えるのは困るので、戻し先は無編集
/// - 「編集前と比べる」は押している間だけ `original` を見せる（履歴は動かさない）
struct PhotoEditHistory: Equatable {

    static let limit = 50

    /// 編集を始めたときのレシピ（比べる相手）
    let original: PhotoRecipe
    /// 今見せている値（つまみの途中を含む）
    private(set) var current: PhotoRecipe
    /// 最後に1手として確定した値
    private(set) var committed: PhotoRecipe
    private(set) var undoStack: [PhotoRecipe] = []
    private(set) var redoStack: [PhotoRecipe] = []
    /// 「編集前と比べる」を押している間 true
    private(set) var isComparing = false

    init(original: PhotoRecipe = .identity) {
        let start = original.sanitized
        self.original = start
        self.current = start
        self.committed = start
    }

    /// 画面に描くレシピ。比べている間は編集前
    var displayed: PhotoRecipe { isComparing ? original : current }

    var canUndo: Bool { !undoStack.isEmpty || current != committed }
    var canRedo: Bool { !redoStack.isEmpty && current == committed }
    /// リセットできるか（今が無編集でない）
    var canReset: Bool { !current.isIdentity }
    /// 編集前から変わっているか（「破棄しますか」を出すかどうか）
    var hasChanges: Bool { current != original }

    /// つまみを動かしている途中。手は増やさない
    mutating func preview(_ recipe: PhotoRecipe) {
        current = recipe.sanitized
    }

    /// 指を離した。途中の値を1手にする。変わっていなければ何もしない
    mutating func commit() {
        guard current != committed else { return }
        undoStack.append(committed)
        if undoStack.count > Self.limit {
            undoStack.removeFirst(undoStack.count - Self.limit)
        }
        redoStack.removeAll()
        committed = current
    }

    /// 1回で終わる操作（プリセットを押す等）
    mutating func apply(_ recipe: PhotoRecipe) {
        preview(recipe)
        commit()
    }

    /// 無編集に戻す（1手として。取り消せる）
    mutating func reset() {
        apply(.identity)
    }

    /// 取り消し。動かしている途中なら、まずその値を1手にしてから戻す（やり直しで戻せる）
    mutating func undo() {
        commit()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(committed)
        committed = previous
        current = previous
    }

    mutating func redo() {
        guard current == committed, let next = redoStack.popLast() else { return }
        undoStack.append(committed)
        committed = next
        current = next
    }

    /// 「編集前と比べる」を押した・離した
    mutating func setComparing(_ comparing: Bool) {
        isComparing = comparing
    }
}
