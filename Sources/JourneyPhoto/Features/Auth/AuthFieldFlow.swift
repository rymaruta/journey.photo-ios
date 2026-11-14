import SwiftUI

/// ログイン・登録・パスワードの再設定と変更の欄を、**キーボードの右下のキーで順に進める**決まり。
///
/// 2026-11-14 判断（人間工学の点検・owner「今ある機能を更に使いやすく」）: 前は欄に `onSubmit`・`submitLabel`・
/// `FocusState` が無く、メールを打って右下のキーを押してもキーボードが閉じるだけだった。パスワードの欄へ指で移り、
/// 打ち終えたらキーボードを閉じて「ログイン」を押していた（欄ごとに押す回数が1つ多い）。
///
/// - 右下のキーは、次の欄があれば「次へ」で次の欄へ、最後の欄なら送る（ログイン・登録・コードを送る・変える）
/// - 最後の欄で押したとき、まだ空の欄（要る欄）があれば送らずにそこへ戻す（送ってから断られない）
/// - 表示名（登録）は任意の欄なので空でも送る
/// - 確認コードは数字のキーボードで右下のキーが無い。並びには入れておき、続く欄へは指で移る
///
/// 決まりは画面から切り離し、単体テスト（`AuthFieldFlowTests`）で見張る。
enum AuthFieldFlow {

    /// どの欄か（`@FocusState` の値）
    enum Field: Hashable {
        case email
        case password
        case displayName
        case code
        case currentPassword
        case newPassword
    }

    /// どの入力の画面か
    enum Form: Equatable {
        case signIn
        case signUp
        /// 再設定: 確認コードを送る前（メールアドレスだけ）
        case resetRequest
        /// 再設定: コードと新しいパスワード
        case resetConfirm
        /// ログインしたままパスワードを変える（`ChangePasswordView`）
        case changePassword
    }

    /// 右下のキーを押したあと
    enum Step: Equatable {
        case focus(Field)
        case submit
    }

    /// 右下のキーの文言（SwiftUI の `SubmitLabel` は比べられないので、ここで持って写す）
    enum Key: Equatable {
        case next
        case send
        case done

        var label: SubmitLabel {
            switch self {
            case .next: return .next
            case .send: return .send
            case .done: return .done
            }
        }
    }

    /// 上から下への欄の並び
    static func order(_ form: Form) -> [Field] {
        switch form {
        case .signIn: return [.email, .password]
        case .signUp: return [.email, .password, .displayName]
        case .resetRequest: return [.email]
        case .resetConfirm: return [.code, .newPassword]
        case .changePassword: return [.currentPassword, .newPassword]
        }
    }

    /// 送るのに要る欄（表示名は任意）
    static func required(_ form: Form) -> [Field] {
        order(form).filter { $0 != .displayName }
    }

    /// `field` で右下のキーを押した。`filled` は字が入っている欄
    static func step(after field: Field, in form: Form, filled: Set<Field>) -> Step {
        let fields = order(form)
        if let i = fields.firstIndex(of: field), i + 1 < fields.count {
            return .focus(fields[i + 1])
        }
        if let missing = required(form).first(where: { !filled.contains($0) }) {
            return .focus(missing)
        }
        return .submit
    }

    /// `field` の右下のキー。最後の欄だけ送るキー（コードを送るは「送信」、ほかは「完了」）
    static func key(for field: Field, in form: Form) -> Key {
        guard order(form).last == field else { return .next }
        return form == .resetRequest ? .send : .done
    }
}
