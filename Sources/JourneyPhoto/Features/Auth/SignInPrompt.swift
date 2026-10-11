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
struct SignInRequest: Identifiable, Equatable {
    let id = UUID()
    /// ログイン画面の上と確認に出す一言（「いいねするにはログインしてください」）
    let reason: String
}

/// 断りの文と、促すかどうか（画面を持たない計算だけ）
enum SignInPrompt {

    static var actionLabel: String { L("ログインする", "Sign in") }
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

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SignInView(reason: reason)
                .webScreen()
                // 閉じる口は画面に置く（ほかのシートと同じ `cancellationAction`）
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Labels.Common.close) { dismiss() }
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
                Button(SignInPrompt.actionLabel) { open = request }
                Button(Labels.Common.cancel, role: .cancel) {}
            } message: { request in
                Text(request.reason)
            }
            .sheet(item: $open) { request in
                SignInSheet(reason: request.reason)
            }
    }
}

extension View {
    /// 未ログインで押した操作から、ログイン画面へ進む口（`SignInPromptPresenter`）
    func signInPrompt(ask: Binding<SignInRequest?>, open: Binding<SignInRequest?>) -> some View {
        modifier(SignInPromptPresenter(ask: ask, open: open))
    }
}
