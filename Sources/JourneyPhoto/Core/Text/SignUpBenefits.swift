import Foundation

/// **登録するとできること**（札 #618「離脱防止」の案1・2026-11-15）。
///
/// 2026-11-15 判断（owner「アカウント登録画面は何も変えたくない」→ 案C）: 札はログインと登録の画面（`SignInView`）
/// には出さない。**ログインしていない人のホームの並びの途中に、札4枚の段を1回だけ出す**（`HomeSignUpBenefitsView`）。
/// 札を押すと今の `SignInSheet`（中身は今のログイン画面のまま）が登録の側で開く（札 #630）。押す回数は増えない（1回で登録の画面）。
/// マイページの手前に札の画面をはさむ案は、ログインまでの押す回数が1回増えるので取らない。
///
/// 4枚は輪の順（載せる → 行きたい場所 → 旅行プランを仲間と → 話す）。Web のトップと写真の頁の案内
/// （`lib/auth/signupBenefits.ts`）と同じ言葉・同じ順にそろえる。
///
/// ここは画面を持たない計算だけ（Linux で試験する）。
enum SignUpBenefit: String, CaseIterable, Identifiable {
    case post
    case wantToGo
    case tripPlan
    case message

    var id: String { rawValue }

    /// 札の名前（Web の `SIGNUP_BENEFITS` と同じ字）
    var title: String {
        switch self {
        case .post: return L("写真を載せる", "Post photos")
        case .wantToGo: return L("行きたい場所を保存", "Save places to go")
        case .tripPlan: return L("旅行プランを仲間と作る", "Plan trips with friends")
        case .message: return L("メッセージで話す", "Chat in messages")
        }
    }

    /// 札の絵の印（SF Symbols。模型の絵と同じ形: ＋、ピン、暦、吹き出し）
    var symbol: String {
        switch self {
        case .post: return "plus"
        case .wantToGo: return "mappin"
        case .tripPlan: return "calendar"
        case .message: return "bubble.left"
        }
    }

    /// 押したときにログイン画面の上に出す一言（今の `SignInView(reason:)` に渡すだけ。画面は変えない）
    var signInReason: String {
        switch self {
        case .post: return L("写真を投稿するにはログインしてください", "Sign in to post a photo")
        case .wantToGo: return L("行きたい場所を保存するにはログインしてください", "Sign in to save places to go")
        case .tripPlan: return L("旅行プランを作るにはログインしてください", "Sign in to plan a trip.")
        case .message: return L("メッセージを見るにはログインしてください", "Sign in to see your messages")
        }
    }

    /// 札を押して**登録の側**で開くときの一言（登録の欄の上に出す・札 #630。「〜にはログインしてください」を出さない）
    var signUpReason: String {
        switch self {
        case .post: return L("登録すると、写真を載せられます", "Sign up to post photos")
        case .wantToGo: return L("登録すると、行きたい場所を保存できます", "Sign up to save places to go")
        case .tripPlan: return L("登録すると、旅行プランを作れます", "Sign up to plan trips")
        case .message: return L("登録すると、メッセージで話せます", "Sign up to chat in messages")
        }
    }

    /// 段の眉ラベル（黒地の上なので真鍮）
    static var heading: String { L("登録するとできること", "What you can do with an account") }
    /// 札の下の「新規登録」と「ログイン」から開くときの一言（どの札でもない）。
    /// ボタンの字は `SignInPrompt.signUpLabel` と `loginLabel`（ほかのお願いと同じ・札 #630）
    /// 下の「新規登録」から開くときの一言（`SignInPrompt.signUpGeneric` と同じ字）
    static var signUpActionReason: String { SignInPrompt.signUpGeneric }
    static var actionReason: String {
        L("ログインすると、写真を載せたり旅行プランを作ったりできます", "Sign in to post photos and plan trips.")
    }

    /// ホームに段を出すか。**ログインしていないと分かってから**（起動直後の確かめ中は、ログイン済みの人にも
    /// 出てしまう。`SignInPrompt.request` と同じ考え）。写真が0枚の日は出さない（空の知らせの下に並べない）
    static func showsOnHome(userId: String?, isResolving: Bool, feedIsEmpty: Bool) -> Bool {
        userId == nil && !isResolving && !feedIsEmpty
    }
}
