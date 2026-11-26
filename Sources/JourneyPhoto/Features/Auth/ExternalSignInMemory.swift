import Foundation

/// 外のアカウントの入口（Apple・Google）の種類
enum ExternalSignInProvider: String, CaseIterable, Sendable {
    case apple
    case google
}

/// 「Apple・Google のボタンを出すか」の**前回の答え**を端末に覚える（2026-11-23 判断）。
///
/// サーバーに「使えるか」を聞いてから出すと、答えが来たときに画面が組み変わる（模型で約 150pt のずれ）。
/// 前回の答えで最初から描き、答えが変わったときだけ静かに変える。
///
/// - 覚えるのは**サーバーがはっきり答えたときだけ**（使える・使えない・口が無い 404）。
///   圏外・サーバーの不調（答えが `nil`）では前の覚えも今の描き方も変えない
///   （電波の無い所で開いただけで、次からボタンが消えないように）
/// - 覚えが無い（初めて）ときは出さない形から始める
/// - ログアウト・退会で消す（`AuthStore.settleSignedOut`）
struct ExternalSignInMemory {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(_ provider: ExternalSignInProvider) -> String {
        "auth.externalSignIn.\(provider.rawValue)"
    }

    /// 前回の答え。覚えが無ければ nil
    func remembered(_ provider: ExternalSignInProvider) -> Bool? {
        defaults.object(forKey: Self.key(provider)) as? Bool
    }

    /// Google のボタンを出すか（2026-11-26 判断・審査 4.8）。**Apple のボタンを出せるときだけ出す。**
    /// ほかの会社のアカウントでログインできるなら、同じ大きさで Apple でサインインも並べる決まり。
    /// Apple が使えない回（サーバーが Apple を止めている、答えを覚えていない）に Google だけが出る形を作らない
    static func showsGoogle(google: Bool, apple: Bool) -> Bool {
        google && apple
    }

    /// 最初に描く形（覚えが無ければ出さない）
    func initiallyShown(_ provider: ExternalSignInProvider) -> Bool {
        remembered(provider) ?? false
    }

    /// サーバーの答えを覚える。nil（確かめられなかった）は覚えを変えない
    func remember(_ answer: Bool?, for provider: ExternalSignInProvider) {
        guard let answer else { return }
        defaults.set(answer, forKey: Self.key(provider))
    }

    /// ログアウト・退会で消す（次の人の画面は「覚えが無い」から始める）
    func forget() {
        for provider in ExternalSignInProvider.allCases {
            defaults.removeObject(forKey: Self.key(provider))
        }
    }

    /// 答えを受けたあとの描き方。nil（確かめられなかった）は今の形のまま
    static func shown(current: Bool, answer: Bool?) -> Bool {
        answer ?? current
    }

    /// 描き方が変わるときの動き。**動きを減らす設定なら動かさず、すぐ替える**。
    /// それ以外は短い溶け（0.25 秒）。ボタンの段は主ボタンより下にあるので、上の欄は動かない
    static func changeDuration(reduceMotion: Bool) -> Double? {
        reduceMotion ? nil : 0.25
    }
}

/// 「使えるか」を聞いて失敗したときの読み方（Apple・Google で同じ）
enum ExternalSignInAvailability {
    /// 404（口がまだ無い本番）と読めない答えは「使えない」とはっきり言えた扱い。
    /// 圏外・5xx・そのほかは「分からない」（nil）
    static func answer(for error: Error) -> Bool? {
        switch error as? APIError {
        case .server(status: 404, message: _), .decoding:
            return false
        default:
            return nil
        }
    }
}
