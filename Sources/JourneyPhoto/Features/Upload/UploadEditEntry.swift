import Foundation

/// 投稿画面から写真の編集へ入る口の決まり（純。画面に触らない）。
///
/// 🔴 **2026-10-03 owner（実機 1.0.58）「写真編集の仕方がわからなかった。どこから入るのか」。**
/// 入口は帯のサムネを押すことだけで、見た目に「押せる・編集できる」合図が無かった。
/// そこで3つ足す: サムネに常に見える札（未編集は「編集」）、帯の下の「写真を編集」、
/// 写真を選んだ直後に一度だけの案内。どれを出すかをここで決める
enum UploadEditEntry {

    /// 帯のサムネの左下の札。**一本の札**にする——未編集なら「編集」、編集済みなら今の札
    /// （プリセット名か「調整」・`PhotoEditBadge`）。同じ位置に2枚重ねない
    enum ThumbTag: Equatable {
        /// 未編集で、開ける——「編集」
        case edit
        /// 編集済み——プリセット名か「調整」（開けない写真でも、編集してある事実は出す）
        case edited(String)
        /// 未編集で、開けない（再試行の鍵を控えている写真・送っている間）——札を出さない。
        /// 「編集」と書いて押せないと、押した人に嘘をつく
        case none

        /// 札の文字。出さないなら nil
        var text: String? {
            switch self {
            case .edit: return L("編集", "Edit")
            case .edited(let name): return name
            case .none: return nil
            }
        }
    }

    /// 札を決める。`badge` は `PendingPhoto.editBadge`、`canEdit` は `editLockReason == nil`
    static func thumbTag(badge: String?, canEdit: Bool) -> ThumbTag {
        if let badge, !badge.isEmpty { return .edited(badge) }
        return canEdit ? .edit : .none
    }

    /// 帯の下の「写真を編集」で開く写真の位置。**開ける写真のうち最初の1枚。**
    /// 1枚も開けなければ nil（ボタンを出さない）。写真が無いときも nil
    static func buttonTarget(editable: [Bool]) -> Int? {
        editable.firstIndex(of: true)
    }

    /// 「写真を押すと編集できます」の案内を出すか。**一度出したら二度と出さない**
    /// （出した時点で覚える。押して消したか、時間で消えたかは問わない）。
    /// 開ける写真が1枚も無いとき（再試行の鍵を控えた写真だけ）は出さない——押しても開かない
    static func showsHint(alreadyShown: Bool, hasEditablePhoto: Bool) -> Bool {
        !alreadyShown && hasEditablePhoto
    }

    /// 案内を出しておく長さ（秒）。押せば先に消える
    static let hintSeconds: Double = 4
}

/// 「写真を押すと編集できます」の案内を出したか。**端末ごと**に覚える
/// （使い方の案内で、アカウントの中身ではない——ログアウトで消す `AccountLocalData` の対象にしない）
struct UploadEditHintMemory {

    static let key = "journey-photo-upload-edit-hint-shown"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 出したか。覚えが無ければ「まだ」
    var shown: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
