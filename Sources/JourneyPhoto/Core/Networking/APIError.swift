import Foundation

/// api-user / 静的サイトへの通信で起きうる失敗。
///
/// **「通信できなかった」と「ログインしていない」を混ぜない。** Web 側は
/// 一度これを混ぜていて、圏外なだけの利用者に「ログインしてください」と
/// 出していた（`lib/utils/api.ts` の `NETWORK_UNREACHABLE_MESSAGE`）。
enum APIError: LocalizedError, Equatable {
    /// 認証が必要なのにトークンが無い（＝ログインしていない）
    case notAuthenticated
    /// 通信そのものが届かなかった（圏外・タイムアウト）
    case unreachable
    /// サーバーが 4xx / 5xx を返した。message は api-user の `{ error }`
    case server(status: Int, message: String)
    /// 応答の形が想定と違う
    case decoding(String)
    /// パスに入れる ID・トークンの形が違う（`PathID`）。**要求は出していない**
    case invalidIdentifier

    var errorDescription: String? { description(language: Locale.preferredAppLanguage) }

    /// 画面に出す一文（言語を渡せる形。試験が英語の画面を作るため）
    func description(language: String) -> String {
        switch self {
        case .notAuthenticated:
            return Labels.Common.signInRequired
        case .unreachable:
            return Labels.Common.unreachable
        case .server(let status, let message):
            // **認証切れは「サーバーエラー」と言わない。** 直し方が違う
            // ——押し直しても直らず、ログインし直すしかない
            if status == 401 {
                return L("ログインの有効期限が切れました。ログインし直してください",
                         "Your session expired. Please sign in again.", language: language)
            }
            // 🔴 **本文があれば本文を出す（日本語の画面だけ）。** api-user の 403 は上限（写真の枚数・
            // アルバム・ハイライト・ブロック）や「返信を受け付けていません」を
            // `{ error }` で返す。固定の文に置き換えると、上限の人に
            // 「お問い合わせください」と出て、何が起きたか伝わらなかった。
            // 固定の文は本文の無い 403（API Gateway の門前払い）だけ
            if let text = Self.displayableServerText(message, language: language) {
                return text
            }
            if isAccountGone {
                return L("このアカウントは削除されています", "This account has been deleted.", language: language)
            }
            return Self.statusText(status, hadServerText: !message.isEmpty, language: language)
        case .decoding:
            return L("応答を読み取れませんでした", "Couldn't read the response", language: language)
        case .invalidIdentifier:
            return L("この項目を開けませんでした", "Couldn't open this item", language: language)
        }
    }

    /// サーバーの `{ error }` の文を、いまの画面にそのまま出してよいか。出せないなら nil。
    ///
    /// 🔴 **2026-10-21 判断: サーバーの本文は日本語の画面でだけ出す。** api-user の文は
    /// 日本語だけ（例: `comments.ts`「同じ写真へのコメントは10件までです」）で、英語の画面に
    /// そのまま出ていた。英語の画面では、**日本語（かな・漢字）を含む文**を出さず、
    /// 状態の数ごとの文（`statusText`）に置き換える。アプリが自分で `L()` で作った文
    /// （`UploadService` の「Image upload failed」など）は英語なので、そのまま通る
    static func displayableServerText(_ message: String,
                                      language: String = Locale.preferredAppLanguage) -> String? {
        guard !message.isEmpty else { return nil }
        if language != "en" { return message }
        return containsJapanese(message) ? nil : message
    }

    /// かな・漢字・全角の約物を含むか（英語の画面に出せない文か）
    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x303F,   // 全角の約物（、。「」）
                 0x3040...0x30FF,   // ひらがな・カタカナ
                 0x31F0...0x31FF,   // カタカナの小書き
                 0x3400...0x4DBF,   // 漢字（拡張A）
                 0x4E00...0x9FFF,   // 漢字
                 0xF900...0xFAFF,   // 互換漢字
                 0xFF01...0xFF60,   // 全角の英数・記号（（）！）
                 0xFF61...0xFF9F:   // 半角カナ
                return true
            default:
                return false
            }
        }
    }

    /// 本文を出せない回（本文が無い・英語の画面）の、状態の数ごとの一文。
    ///
    /// `hadServerText` は「サーバーは理由を書いていた（英語の画面だから出せなかった）」。
    /// api-user の 403 は本文つきなら上限か断り、本文が無いのは API Gateway の門前払い
    /// （上の注記）なので、文を分ける。
    ///
    /// **サーバーの `code` では選ばない。** `APIError.server` は `code` を持たない
    /// （足すと、状態と本文の2つで分けている呼び手のパターンが全部変わる）。`code` で文を選ぶ口は
    /// それぞれ持っている（とおまわり号 `CamperText.refusal`・トランク `TrunkText.refusal`・購入 `PurchaseDelivery`）
    static func statusText(_ status: Int, hadServerText: Bool,
                           language: String = Locale.preferredAppLanguage) -> String {
        func t(_ ja: String, _ en: String) -> String { L(ja, en, language: language) }
        switch status {
        case 400:
            return t("送った内容を受け付けられませんでした。確かめてもう一度お試しください",
                     "That couldn't be accepted. Please check and try again.")
        case 403 where hadServerText:
            return t("この操作はできません。上限に達しているか、許可されていない操作です",
                     "You can't do this. You may have reached a limit, or it isn't allowed.")
        case 403:
            // **403 を「ログインし直して」と言わない。** 401 と混ぜていたが、
            // 403 は**ログインできているのに権限が無い**状態で、
            // ログインし直しても直らない（登録直後に権限を配る処理が
            // 落ちたときに起きる。Cognito 側に無いので本人には直せない）。
            // Web は同じ取り違えで**ログイン画面と元の画面を無限に往復**
            // させていた（`lib/hooks/useMemberGate.ts` の経緯）。
            return t("この操作をする権限がありません。登録直後にこの状態になった場合は、お手数ですがお問い合わせください（ログインし直しても直りません）",
                     "You don't have permission for this. If this started right after signing up, please contact us — signing in again won't fix it.")
        case 404:
            return t("見つかりませんでした。削除されたか、見られなくなった可能性があります",
                     "This couldn't be found. It may have been deleted or is no longer visible.")
        case 409:
            return t("ほかの変更とぶつかりました。読み直してからもう一度お試しください",
                     "This conflicts with another change. Reload and try again.")
        case 410:
            // 退会した本人の 410 は `description` が先に分ける。ここは招待リンクの期限切れなど
            return t("もう使えなくなっています", "This is no longer available.")
        case 413:
            return t("大きすぎて送れませんでした", "This is too large to send.")
        case 429:
            return t("回数の上限に達しました。しばらくしてからもう一度お試しください",
                     "You've reached the limit for now. Please wait a while and try again.")
        case 500...599:
            return t("サーバーで問題が起きました（\(status)）。少し待ってからもう一度お試しください",
                     "Something went wrong on our side (\(status)). Please try again in a moment.")
        default:
            return t("サーバーエラー（\(status)）", "Server error (\(status))")
        }
    }

    /// 認証が切れている（再ログインを促すべき）応答か。
    ///
    /// **403 は含めない。** あちらはログインできているのに権限が無い状態で、
    /// ログインし直しても直らない（上の注記）。
    var isAuthExpired: Bool {
        if case .server(let status, _) = self { return status == 401 }
        return false
    }

    /// **道（ルート）がまだデプロイされていない** 404 か。新しい口へ切り替える途中で、
    /// 古い口に戻ってよい回だけを見分ける（`SocialService.comments`）。
    ///
    /// api-user の 404 は必ず `{ "error": "..." }` を持つ（`http.ts` の `jsonError`）。
    /// API Gateway の「道が無い」は `{"message":"Not Found"}` で `error` が無く、
    /// `APIClient.errorMessage` が空にする——**本文の読み方を増やさず、空の 404 で見分ける。**
    /// 本文の無い 404 もこちらに入るが、戻り先は同じか狭い答えしか返さないので害は無い
    /// （Web の `isMissingRouteResponse` は `message` まで見る。`APIError` は本文を持ち歩かない）
    var isMissingRoute: Bool {
        if case .server(404, let message) = self { return message.isEmpty }
        return false
    }

    /// 410 Gone（もう無い）。**退会済みとは限らない**——招待リンクの期限切れ・取り消しも 410
    /// （api-user の `invite.ts` の `inviteRejection`）。退会かどうかは `isAccountGone` で見る
    var isGone: Bool {
        if case .server(410, _) = self { return true }
        return false
    }

    /// api-user が退会した本人に返す 410 の本文（`liveCaller.ts` の `ACCOUNT_GONE_MESSAGE`。
    /// `userProfile.ts`・`trunk.ts` の 410 も同じ文）
    static let accountGoneMessage = "このアカウントは削除されています"

    /// **退会した本人**への 410（サーバーは 2026-10-18 から書く口を 410 で塞ぐ・`liveCaller.ts`）。
    ///
    /// 🔴 **2026-10-21 判断: 410 だけでは決めない。本文で見分ける。** 招待リンクの期限切れも
    /// 認証つきの口（`POST /invites/{token}/join`）から 410 で返る。そこで「退会の途中」に
    /// 倒すと、生きている人に「退会の手続きが途中です」が出て、「完了する」で**本当に
    /// アカウントを消してしまう**。文が変わったら退会の扱いに入らない側へ倒れる（消す側へは倒れない）
    var isAccountGone: Bool {
        if case .server(410, let message) = self { return message == Self.accountGoneMessage }
        return false
    }

    /// ログイン済みなのに権限が無い（Web の `MemberOnlyNotice` が出る状態）
    var isForbidden: Bool {
        if case .server(let status, _) = self { return status == 403 }
        return false
    }
}
