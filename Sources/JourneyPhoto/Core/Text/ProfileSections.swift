import Foundation

/// マイページ（モック2）の、**出す／出さないの決まり**。
///
/// 🔴 **この画面は実機の絵で確かめられない**（CI の巡回はログインしない）。
/// 見なくても分かるように、判断だけを画面から出す
/// ——`Shims/` の模型では `View` の中を動かせないので、ここに置いたぶんだけが
/// Linux の `swift test` で確かめられる（`SpotScreen` と同じ判断）。
enum ProfileSections {

    /// ストーリーハイライトの輪を出すか（モック2-5）。
    ///
    /// - **読み終わるまで出さない。** 先に空の行を出すと、読み終わった
    ///   瞬間に入れ替わってちらつく
    /// - **他人のページで0件なら、行ごと消す。** サーバーは「追っていない人」にも
    ///   0件を返す（`canSeeHighlights`）ので、「見られません」と書くと
    ///   **在ることを教える**ことになる
    /// - 自分のページは0件でも出す（そこにしか「新規」が無い）
    static func showsHighlights(loaded: Bool, isMine: Bool, count: Int) -> Bool {
        guard loaded else { return false }
        return isMine || count > 0
    }

    /// 「行きたい場所」の札に何を出すか（モック2-6）。
    enum WishlistState: Equatable {
        /// 並べる
        case list
        /// まだ1つも入れていない
        case empty
        /// **入れてあるのに台帳が取れていない**（「無い」と言わない）
        case couldNotLoad
    }

    /// - Parameters:
    ///   - ledgerCount: 取れている台帳の件数
    ///   - wantedCount: 台帳と突き合わせて残った件数
    ///   - savedIdCount: この端末が覚えている id の数
    ///
    /// 🔴 **「まだ無い」と「取れていない」を分ける。** 入れた覚えがあるのに
    /// 「まだありません」と出ると、消えたように見える。
    static func wishlist(ledgerCount: Int, wantedCount: Int, savedIdCount: Int) -> WishlistState {
        if wantedCount > 0 { return .list }
        if ledgerCount == 0 && savedIdCount > 0 { return .couldNotLoad }
        return .empty
    }
}
