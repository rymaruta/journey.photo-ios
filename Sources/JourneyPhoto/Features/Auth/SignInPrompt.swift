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
/// - 押した操作の断りは `ask` に入れる → すぐ登録の側のログイン画面（2026-11-22・札 #628 で確かめの窓をやめた）
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
    /// 確認（`ask`）の「新規登録」から開くときに、登録の画面の上に出す一言（「登録すると、いいねできます」）。
    /// **呼ぶ側が渡す**（2026-11-15 確かめ役の指摘: ログインの文「〜にはログインしてください」を登録の欄の上に出していた）。
    /// 無ければ一般の一言（`SignInPrompt.signUpGeneric`）
    var signUpReason: String? = nil
    /// ログインできたら済ませる続き（いいね・保存・フォロー・2026-11-16 判断 A4・`SignInFollowUp`）。
    /// 無ければ今までどおり、ログインしたら閉じるだけ
    var followUp: SignInFollowUp? = nil
}

/// ログイン画面（`SignInView`）を開いたときの側。画面は1つで、上の一言と欄はそのまま
enum SignInEntry: Equatable {
    case signIn
    case signUp
}

/// ログインの画面が覚えている続きを、ログインできた瞬間に渡すか（2026-11-16 判断 A4）
enum SignInFollowUpHandOver {
    /// ログインできた（`userId` が入った）ときだけ渡す。ログアウトの向きでは渡さない
    static func take(_ waiting: SignInFollowUp?, userId: String?) -> SignInFollowUp? {
        guard userId != nil else { return nil }
        return waiting
    }
}

/// 断りの文と、促すかどうか（画面を持たない計算だけ）
enum SignInPrompt {

    static var actionLabel: String { L("ログインする", "Sign in") }
    /// 新規登録のボタン（Web の `SIGNUP_BENEFITS_SIGNUP` と同じ字）。英語は「Sign up」と「Sign in」にそろえる
    static var signUpLabel: String { L("新規登録", "Sign up") }
    /// ボタンの並びのログイン（Web の `SIGNUP_BENEFITS_LOGIN` と同じ字）
    static var loginLabel: String { L("ログイン", "Sign in") }
    static var like: String { L("いいねするにはログインしてください", "Sign in to like photos") }
    static var save: String { L("保存するにはログインしてください", "Sign in to save photos") }
    static var comment: String { L("コメントするにはログインしてください", "Sign in to comment") }
    /// 通知を押したがログインしていないときの知らせ（`RootView`）
    static var notifications: String { L("お知らせを見るにはログインしてください", "Sign in to see your notifications") }

    // MARK: 登録の側で開くときの一言（札 #630・2026-11-15）。登録の欄の上に出すので「登録すると、〜」で言う

    static var likeSignUp: String { L("登録すると、いいねできます", "Sign up to like photos") }
    static var saveSignUp: String { L("登録すると、写真を保存できます", "Sign up to save photos") }
    static var commentSignUp: String { L("登録すると、コメントできます", "Sign up to comment") }
    /// フォロー（2026-11-16 判断 A4: ログインしていなくても「フォローする」を出し、押したら登録の側で開く）
    static var followSignUp: String { L("登録すると、フォローできます", "Sign up to follow people") }
    static var notificationsSignUp: String { L("登録すると、お知らせを見られます", "Sign up to see your notifications") }
    /// どの操作でもないとき
    static var signUpGeneric: String {
        L("登録すると、写真を載せたり旅行プランを作ったりできます", "Sign up to post photos and plan trips.")
    }
    /// コメントの欄の代わりに出す1行
    static var commentLine: String { L("ログインするとコメントできます", "Sign in to comment") }

    /// 押した操作に「ログインする」を出すか。**起動直後の確認中は出さない**
    /// （ログイン済みの人にも出る・`HomeLikeGate.decide` と同じ考え）
    static func request(_ reason: String, signUpReason: String, userId: String?, isResolving: Bool) -> SignInRequest? {
        HomeLikeGate.decide(userId: userId, isResolving: isResolving) == .askToSignIn
            ? SignInRequest(reason: reason, signUpReason: signUpReason) : nil
    }

    /// 確認の「新規登録」から開く頼み（登録の側・登録の一言）
    static func signUpRequest(from request: SignInRequest) -> SignInRequest {
        SignInRequest(reason: request.signUpReason ?? signUpGeneric, entry: .signUp, followUp: request.followUp)
    }

    /// 押した操作から**すぐ登録の側で開く**頼み（2026-11-16 判断 A4）。確かめの「ログインしてください」を挟まない
    /// ——開いた画面に「ログインに戻る」があるので、登録済みの人も1回で入れる（押す回数 2 → 1）。
    /// 起動直後の確認中は開かない（ログイン済みの人にも出る・`request` と同じ）
    static func direct(signUpReason: String, followUp: SignInFollowUp, userId: String?,
                       isResolving: Bool) -> SignInRequest? {
        HomeLikeGate.decide(userId: userId, isResolving: isResolving) == .askToSignIn
            ? SignInRequest(reason: signUpReason, entry: .signUp, followUp: followUp) : nil
    }

    /// コメントの欄の代わりに「ログインするとコメントできます」を出すか
    /// （未ログインと分かっていて、コメントを受け付ける写真のときだけ）
    static func showsCommentLine(userId: String?, isResolving: Bool, acceptsReactions: Bool) -> Bool {
        acceptsReactions && userId == nil && !isResolving
    }
}

/// 押した操作の断り（`ask`）から開くログインの画面（札 #628・2026-11-22 判断）。確かめの窓を挟まず、
/// 登録の側で、登録の一言と続き（いいね・保存など）を持ったまま開く
enum SignInPromptOpening {
    static func opened(from request: SignInRequest) -> SignInRequest {
        SignInPrompt.signUpRequest(from: request)
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
    /// ログインできたら、開いた頼みの続き（`SignInRequest.followUp`）を渡す（2026-11-16 判断 A4）
    var onSignedIn: ((SignInFollowUp) -> Void)? = nil

    @EnvironmentObject private var auth: AuthStore
    /// いま開いているログインの画面の続き。閉じたらログインしていないぶんは忘れる
    @State private var waiting: SignInFollowUp?

    func body(content: Content) -> some View {
        content
            .onChange(of: open?.id) { _, _ in
                if let open { waiting = open.followUp }
            }
            // **ログインできた瞬間に渡す**（ログインの画面は自分で閉じる・`SignInSheet`）
            .onChange(of: auth.userId) { _, userId in
                guard let followUp = SignInFollowUpHandOver.take(waiting, userId: userId) else { return }
                waiting = nil
                onSignedIn?(followUp)
            }
            // 2026-11-22 判断（札 #628）: **確かめの窓（「ログインが必要です」）を挟まず、すぐログインの画面を開く。**
            // 取り消せない操作ではないので確かめは要らない（押す回数 2 → 1）。開くのは登録の側（新規登録が主・札 #630）。
            // 画面に「ログインに戻る」があるので、登録済みの人も1回で入れる（`SignInPrompt.direct` と同じ形）
            .onChange(of: ask?.id) { _, _ in
                guard let request = ask else { return }
                ask = nil
                open = SignInPromptOpening.opened(from: request)
            }
            .sheet(item: $open, onDismiss: {
                // ログインせずに閉じたら、続きは忘れる（次に別の人がログインしたときに勝手に送らない）
                if auth.userId == nil { waiting = nil }
            }) { request in
                SignInSheet(reason: request.reason, entry: request.entry)
            }
    }
}

extension View {
    /// 未ログインで押した操作から、ログイン画面へ進む口（`SignInPromptPresenter`）
    func signInPrompt(ask: Binding<SignInRequest?>, open: Binding<SignInRequest?>,
                      onSignedIn: ((SignInFollowUp) -> Void)? = nil) -> some View {
        modifier(SignInPromptPresenter(ask: ask, open: open, onSignedIn: onSignedIn))
    }
}

/// お願いの中に並べる「新規登録」と「ログイン」（札 #630・2026-11-15 判断: 新規登録が主）。
/// 主ボタン（50）と線のボタン（44）を縦に積む——ログイン画面の「ログイン」「アカウントを作る」と同じ並べ方。
/// 主ボタンの色はデザインの板の決まり（写真のある画面は白、無い画面は真鍮の塗りに墨・`JPPillStyle.main`）
struct SignInAskButtons: View {

    let reason: String
    /// 「新規登録」から開くときの一言（「登録すると、〜」）
    let signUpReason: String
    let onPhoto: Bool
    /// 読み上げと UI テストの名前の頭（`<頭>.signUp`、`<頭>.signIn`）
    let identifier: String
    let open: (SignInRequest) -> Void

    var body: some View {
        VStack(spacing: JPSpace.s) {
            Button {
                open(SignInRequest(reason: signUpReason, entry: .signUp))
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
