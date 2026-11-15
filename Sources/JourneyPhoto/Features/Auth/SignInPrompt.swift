import SwiftUI

/// 未ログインで押した操作から、**ログイン画面へ進む口**（2026-10-11 判断）。
///
/// 🔴 以前は、いいね・保存を押すと赤い字か3秒の知らせで「ログインしてください」と
/// 言うだけで、**ログインする手段がその場に無かった**（マイページのタブまで行かないと
/// 入れない行き止まり）。ここでは「ログインする」を出し、押したら既存のログイン画面
/// （`SignInView`）をシートで出す。**ログインの仕組みは作らない**——中身はタブの
/// ログイン画面と同じもので、ログインできたらシートを閉じる。
///
/// 使い方: 画面に `.signInPrompt(ask: $ask, open: $open)` を付け、
/// - 押した操作の断り（確かめてから進む）は `ask` に入れる → 「ログインする」の確認
/// - 「ログインする」のボタンから直接進むときは `open` に入れる → すぐログイン画面
///
/// **新規登録も同じお願いに出す（札 #630・2026-11-15 判断）。** owner「ログインのお願いあるけど、会員登録してない人には
/// 有効ではないので、会員登録もそこに出したい」。確認にもボタンの並びにも「新規登録」を足し、押したら今のログイン画面を
/// **登録の側で開く**（`entry: .signUp`。画面そのものは変えない。開いたときの側を選ぶだけ）。押す回数は1回のまま。
/// 新規登録を主にする——本番の会員は約7人（Cognito の見積もり・2026-11-15）で、お願いを見る人の多くはまだ登録していない
struct SignInRequest: Identifiable, Equatable {
    let id = UUID()
    /// ログイン画面の上と確認に出す一言（「いいねするにはログインしてください」）
    let reason: String
    /// 開いたときの側（ログインか、新規登録か）
    var entry: SignInEntry = .signIn
}

/// ログイン画面（`SignInView`）を開いたときの側。画面は1つで、上の一言と欄はそのまま
enum SignInEntry: Equatable {
    case signIn
    case signUp
}

/// 断りの文と、促すかどうか（画面を持たない計算だけ）
enum SignInPrompt {

    static var actionLabel: String { L("ログインする", "Sign in") }
    /// 新規登録のボタン（Web の `SIGNUP_BENEFITS_SIGNUP` と同じ字）
    static var signUpLabel: String { Labels.Navigation.signup }
    /// ボタンの並びのログイン（Web の `SIGNUP_BENEFITS_LOGIN` と同じ字）
    static var loginLabel: String { Labels.Navigation.login }
    static var like: String { L("いいねするにはログインしてください", "Sign in to like photos") }
    static var save: String { L("保存するにはログインしてください", "Sign in to save photos") }
    static var comment: String { L("コメントするにはログインしてください", "Sign in to comment") }
    /// コメントの欄の代わりに出す1行
    static var commentLine: String { L("ログインするとコメントできます", "Sign in to comment") }

    /// 押した操作に「ログインする」を出すか。**起動直後の確認中は出さない**
    /// （ログイン済みの人にも出る・`HomeLikeGate.decide` と同じ考え）
    static func request(_ reason: String, userId: String?, isResolving: Bool) -> SignInRequest? {
        HomeLikeGate.decide(userId: userId, isResolving: isResolving) == .askToSignIn
            ? SignInRequest(reason: reason) : nil
    }

    /// コメントの欄の代わりに「ログインするとコメントできます」を出すか
    /// （未ログインと分かっていて、コメントを受け付ける写真のときだけ）
    static func showsCommentLine(userId: String?, isResolving: Bool, acceptsReactions: Bool) -> Bool {
        acceptsReactions && userId == nil && !isResolving
    }
}

/// ログイン画面をシートで出す（中身はタブのログイン画面 `SignInView` そのもの）
struct SignInSheet: View {

    let reason: String?
    /// 開いたときの側（お願いの「新規登録」から来たら登録の側）
    var entry: SignInEntry = .signIn

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SignInView(reason: reason, entry: entry)
                .webScreen()
                // 閉じる口は画面に置く（ほかのシートと同じ `cancellationAction`）
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCloseButton(action: { dismiss() })
                    }
                }
        }
        // **ログインできたら閉じる**（元の画面へ戻り、押し直せば届く）
        .onChange(of: auth.userId) { _, userId in
            if userId != nil { dismiss() }
        }
    }
}

/// 「ログインする」の確認と、ログイン画面のシート
struct SignInPromptPresenter: ViewModifier {

    @Binding var ask: SignInRequest?
    @Binding var open: SignInRequest?

    func body(content: Content) -> some View {
        content
            .alert(Labels.Common.signInRequired,
                   isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } }),
                   presenting: ask) { request in
                // 新規登録を先（主）に置く（札 #630・2026-11-15 判断）。押したら今のログイン画面を登録の側で開く
                Button(SignInPrompt.signUpLabel) { open = SignInRequest(reason: request.reason, entry: .signUp) }
                Button(SignInPrompt.actionLabel) { open = request }
                Button(Labels.Common.cancel, role: .cancel) {}
            } message: { request in
                Text(request.reason)
            }
            .sheet(item: $open) { request in
                SignInSheet(reason: request.reason, entry: request.entry)
            }
    }
}

extension View {
    /// 未ログインで押した操作から、ログイン画面へ進む口（`SignInPromptPresenter`）
    func signInPrompt(ask: Binding<SignInRequest?>, open: Binding<SignInRequest?>) -> some View {
        modifier(SignInPromptPresenter(ask: ask, open: open))
    }
}

/// お願いの中に並べる「新規登録」と「ログイン」（札 #630・2026-11-15 判断: 新規登録が主）。
/// 主ボタン（50）と線のボタン（44）を縦に積む——ログイン画面の「ログイン」「アカウントを作る」と同じ並べ方。
/// 主ボタンの色はデザインの板の決まり（写真のある画面は白、無い画面は真鍮の塗りに墨・`JPPillStyle.main`）
struct SignInAskButtons: View {

    let reason: String
    let onPhoto: Bool
    /// 読み上げと UI テストの名前の頭（`<頭>.signUp`、`<頭>.signIn`）
    let identifier: String
    let open: (SignInRequest) -> Void

    var body: some View {
        VStack(spacing: JPSpace.s) {
            Button {
                open(SignInRequest(reason: reason, entry: .signUp))
            } label: {
                Text(SignInPrompt.signUpLabel).jpPillButton(.main(onPhoto: onPhoto))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(identifier).signUp")
            Button {
                open(SignInRequest(reason: reason))
            } label: {
                Text(SignInPrompt.loginLabel).jpPillButton(.outline)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(identifier).signIn")
        }
    }
}
