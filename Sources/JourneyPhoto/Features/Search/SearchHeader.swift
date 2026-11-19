import Foundation

/// 探すの頭（明朝の「探す」・探す欄・範囲のチップ）の出し方（2026-11-16 判断・使い勝手の見直し A10）。
///
/// 以前は「探す」の大見出しと範囲のチップ（すべて・写真・人・タグ・撮影地）が常に出ていて、最初の画面の
/// 上の約 80pt を占めていた。範囲のチップは字を打つ前に押しても効く中身が無い。
/// - 大見出しは、**下へ送ったら・字を打ったら畳む**（頭に戻って空なら出し直す）
/// - 範囲のチップは**字を打ってから**出す。範囲を選んだまま字を消したら、外せるように残す
enum SearchHeader {

    /// 畳み始める送りの量（頭の印が見えている枠の上からこれだけ上へ出たら畳む）
    static let collapseAfter: CGFloat = 24
    /// 出し直す送りの量（畳んだ・出したを行き来して頭がちらつかないよう、戻すのはほぼ頭まで戻ってから）
    static let expandBefore: CGFloat = 4

    /// 下へ送ったか。`top` は結果の頭の印の、送りの枠の中での上端（下へ送るほど負に大きい）
    static func scrolledDown(top: CGFloat, was: Bool) -> Bool {
        was ? top < -expandBefore : top < -collapseAfter
    }

    static func showsTitle(scrolledDown: Bool, query: String) -> Bool {
        !scrolledDown && isBlank(query)
    }

    static func showsScopeChips(query: String, scopeIsAll: Bool) -> Bool {
        !isBlank(query) || !scopeIsAll
    }

    private static func isBlank(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
