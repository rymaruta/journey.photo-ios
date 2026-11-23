import Foundation

/// 確認コードの6桁の箱の決まり（登録の確認とパスワードの再設定で同じものを使う・模型 NL2x「登録の確認コード」
/// 「確認コードの状態」「パスワードの再設定」・2026-11-23 owner「これでいいよ」）。
///
/// 画面（`VerificationCodeField`）から切り離し、単体テスト（`VerificationCodeTests`）で見張る:
/// - **入力の整え方**: 中身は1つの欄（`.oneTimeCode`・数字のキーボード）。キーボードの候補・貼り付けで入った字から
///   数字だけを拾い（「123-456」「123 456」も6桁になる。数字以外で全体を捨てない）、7桁目からは入れない。
///   全角の数字（「１２３」）も半角にそろえる
/// - **自動で確かめる条件**: 6桁そろった・確かめ中でない・同じコードをまだ送っていない・電波がある（二重に送らない）
/// - **状態**: 入力中 → 確かめ中 → 成功／違うコード（空に戻して打ち直し）／期限切れ（新しいコードを送る）／圏外（電波が戻ったら確かめ直す）
struct VerificationCodeEntry: Equatable {

    /// 桁の数（Cognito の確認コードは6桁）
    static let length = 6
    /// 1組の箱の数（3つずつ2組）
    static let groupSize = 3

    enum Phase: Equatable {
        /// 打っている（違うコードのあと空に戻した所も、ここへ戻る）
        case typing
        /// 送って答えを待っている（打った字を受けない・二重に送らない）
        case checking
        /// 違うコードだった（箱の上に文。打ち始めたら消える）
        case wrong
        /// 期限が切れた（「新しいコードを送る」を主ボタンに）
        case expired
        /// 電波が無くて送れなかった（打ったコードは残し、戻ったら確かめ直す）
        case offline
        /// 確かめられた
        case verified
    }

    /// 確かめた結果
    enum Outcome: Equatable {
        case verified
        case wrong
        case expired
        /// 電波が無かった
        case offline
        /// そのほかの失敗（回数の上限など。文は `AuthStore.errorMessage`）
        case failed

        /// Cognito の失敗の種類から。`isOffline` は端末が「電波なし」と知っているか——
        /// 電波はあるのにサーバーに届かなかった回は「圏外」にしない（戻るのを待っても戻らない）
        static func from(_ failure: AuthFailure, isOffline: Bool) -> Outcome {
            switch failure {
            case .none: return .verified
            case .codeMismatch: return .wrong
            case .codeExpired: return .expired
            case .network: return isOffline ? .offline : .failed
            default: return .failed
            }
        }
    }

    private(set) var code = ""
    private(set) var phase: Phase = .typing
    /// 確かめに出したコード。**同じコードを二度送らない**（失敗のあとに同じ6桁で送り続けない）
    private(set) var submitted: String?

    init(code: String = "") {
        self.code = Self.normalize(code)
    }

    /// 欄に入った字を箱の6桁に整える。数字だけを拾い（全角は半角に）、先頭から6桁まで
    static func normalize(_ raw: String) -> String {
        var digits = ""
        for scalar in raw.unicodeScalars {
            guard digits.count < length else { break }
            switch scalar.value {
            case 0x30...0x39: digits.unicodeScalars.append(scalar)
            // 全角の「０」〜「９」（日本語のキーボードで打った数字）
            case 0xFF10...0xFF19:
                if let ascii = Unicode.Scalar(scalar.value - 0xFF10 + 0x30) { digits.unicodeScalars.append(ascii) }
            default: continue
            }
        }
        return digits
    }

    var isComplete: Bool { code.count == Self.length }

    /// 打った字を受ける（欄の字が変わるたび）。確かめ中・成功の後は受けない（二重に送らない）
    mutating func input(_ raw: String) {
        guard phase != .checking, phase != .verified else { return }
        let next = Self.normalize(raw)
        guard next != code else { return }
        code = next
        // 打ち直したら、違う・期限切れ・圏外の知らせを下げる（板 06「打ち直したら知らせを消す」）。
        // 違うコードの後の空に戻すところ（`clearWrong`）は、まだ何も打っていないので文を残す
        if phase == .wrong || phase == .expired, !code.isEmpty { phase = .typing }
        if phase == .offline { phase = .typing }
        // 打ち直したコードは、まだ送っていない
        if submitted != code { submitted = nil }
    }

    /// 自動で確かめてよいか（登録の確認。6桁そろった・確かめ中でない・まだ送っていないコード・電波がある）
    func shouldSubmit(isOffline: Bool) -> Bool {
        isComplete && !isOffline && submitted != code && (phase == .typing || phase == .wrong)
    }

    /// 確かめに出す（送るコードを返す）。出せないときは nil
    mutating func beginCheck() -> String? {
        guard isComplete, phase != .checking, phase != .verified else { return nil }
        submitted = code
        phase = .checking
        return code
    }

    /// 確かめの答え
    mutating func finish(_ outcome: Outcome) {
        switch outcome {
        case .verified:
            phase = .verified
        case .wrong:
            // 箱を揺らしてから空に戻す（`clearWrong`）。それまで打ったコードは赤で見せる
            phase = .wrong
        case .expired:
            phase = .expired
            code = ""
            submitted = nil
        case .offline:
            // 打ったコードは残す。電波が戻ったら送り直す（`reconnected`）
            phase = .offline
            submitted = nil
        case .failed:
            // 同じコードで送り続けない（`submitted` は残す）。1桁でも打ち直せば、また送れる
            phase = .typing
        }
    }

    /// 違うコードのあと、箱を空に戻して1つ目から打ち直せるようにする（文は打ち始めるまで残す）
    mutating func clearWrong() {
        guard phase == .wrong else { return }
        code = ""
        submitted = nil
    }

    /// 電波が戻った。圏外で止めていたコードを、もう一度確かめられる形に戻す
    mutating func reconnected() {
        guard phase == .offline else { return }
        phase = .typing
        submitted = nil
    }

    /// 新しいコードを送った（前のコードは使えない）。空の箱から打つ
    mutating func restart() {
        code = ""
        phase = .typing
        submitted = nil
    }

    /// i 番目の箱の字（空なら nil）
    func digit(at index: Int) -> Character? {
        guard index >= 0, index < code.count else { return nil }
        return code[code.index(code.startIndex, offsetBy: index)]
    }

    /// いま打つ箱（真鍮の縁）。そろった・確かめ中・成功では無い
    var currentIndex: Int? {
        guard !isComplete, phase != .checking, phase != .verified else { return nil }
        return code.count
    }

    // MARK: - 文（模型 NL2x のとおり）

    /// 箱のすぐ上の文（違う・期限切れ）。ほかの失敗は `AuthStore.errorMessage` を出す
    var errorText: String? {
        switch phase {
        case .wrong: return Self.wrongText
        case .expired: return Self.expiredText
        default: return nil
        }
    }

    static var wrongText: String { L("コードが違います。もう一度入れてください", "That code isn't right. Please enter it again.") }
    static var expiredText: String { L("このコードは期限が切れました", "This code has expired") }
    static var checkingText: String { L("確かめています", "Checking") }
    static var verifiedText: String { L("確認できました", "Verified") }
    static var offlineText: String { L("電波が戻ったら、そのまま確かめます", "We'll check it as soon as you're back online") }
    static var resendText: String { L("コードを送り直す", "Send a new code") }
    static var newCodeText: String { L("新しいコードを送る", "Send a new code") }
    static var changeEmailText: String { L("メールアドレスを変える", "Change email address") }
    static func waitText(_ seconds: Int) -> String {
        L("\(seconds)秒後に送り直せます", "You can resend in \(seconds)s")
    }
    /// 送り先の一文の前と後ろ（間にメールアドレスを太字の白で置く。日本語は「（アドレス） に／6桁のコードを送りました」）
    static var sentBefore: String { L("", "We sent a 6-digit code to\n") }
    static var sentAfter: String { L(" に\n6桁のコードを送りました", "") }

    /// 読み上げで伝える状態（変わったときに1回だけ言う）
    var announcement: String? {
        switch phase {
        case .typing: return nil
        case .checking: return Self.checkingText
        case .wrong: return Self.wrongText
        case .expired: return Self.expiredText
        case .offline: return L("電波が届いていません。", "No connection.") + Self.offlineText
        case .verified: return Self.verifiedText
        }
    }
}

/// 箱の下の1行（模型 NL2x「確認コードの状態」）。どの状態でも同じ箱のまま、ここだけが替わる
enum VerificationCodeLine: Equatable {
    /// 「60秒後に送り直せます」（灰）
    case wait(Int)
    /// 「コードを送り直す」（真鍮・押せる）
    case resend
    /// 回る印＋「確かめています」
    case checking
    /// 真鍮の丸にチェック＋「確認できました」
    case verified
    /// 「電波が戻ったら、そのまま確かめます」
    case offline
    /// 出さない（期限切れは主ボタンを出す）
    case none

    static func line(for entry: VerificationCodeEntry, isOffline: Bool, remaining: Int) -> VerificationCodeLine {
        switch entry.phase {
        case .verified: return .verified
        case .checking: return .checking
        case .expired: return .none
        case .offline: return .offline
        case .typing, .wrong:
            if isOffline && entry.isComplete { return .offline }
            return remaining > 0 ? .wait(remaining) : .resend
        }
    }

    var text: String? {
        switch self {
        case .wait(let seconds): return VerificationCodeEntry.waitText(seconds)
        case .resend: return VerificationCodeEntry.resendText
        case .checking: return VerificationCodeEntry.checkingText
        case .verified: return VerificationCodeEntry.verifiedText
        case .offline: return VerificationCodeEntry.offlineText
        case .none: return nil
        }
    }
}

/// 送り直しの待ち時間（模型 NL2x: 送った直後から 60 秒は「60秒後に送り直せます」、過ぎたら「コードを送り直す」）。
/// 60 秒はアプリで決める値（Cognito の送り直しの回数の上限とは別・2026-11-23 判断）
struct ResendCooldown: Equatable {

    static let seconds = 60

    /// 最後に送った時刻（まだ送っていない・送れなかったときは nil＝すぐ送り直せる）
    private(set) var sentAt: Date?

    init(sentAt: Date? = nil) { self.sentAt = sentAt }

    /// 残りの秒（切り上げ）。0 なら送り直せる
    func remaining(now: Date) -> Int {
        guard let sentAt else { return 0 }
        let left = Double(Self.seconds) - now.timeIntervalSince(sentAt)
        guard left > 0 else { return 0 }
        return min(Self.seconds, Int(left.rounded(.up)))
    }

    func canResend(now: Date) -> Bool { remaining(now: now) == 0 }

    mutating func start(now: Date) { sentAt = now }

    mutating func clear() { sentAt = nil }
}

/// 確認コードの画面の寸法（模型 NL2x の「詳しく」）
enum VerificationCodeLayout {
    /// 箱の高さ・角・箱の間・組の間
    static let boxHeight: CGFloat = 58
    static let boxCorner: CGFloat = 12
    static let boxGap: CGFloat = 8
    static let groupGap: CGFloat = 16
    /// 数字（SF 600 28pt の等幅数字）
    static let digitSize: Double = 28
    /// 確かめ中・圏外で箱を薄くする
    static let waitingOpacity: Double = 0.55
    /// 違うコードで揺らす幅（左右に小さく 0.32 秒）と、揺らし終えて空に戻すまで
    static let shakeOffsets: [CGFloat] = [-8, 7, -5, 3, 0]
    static let shakeStep: Double = 0.064
    static let clearDelay: Double = 0.6
    /// 動きを減らす設定では揺らさず、赤の箱を少し長く見せてから空に戻す
    static let clearDelayReduced: Double = 0.9
    /// 成功を見せてからアプリへ進むまでの最短の間
    static let verifiedHold: Double = 0.6
    /// 写真の無い画面なので主ボタンは真鍮の塗り＋墨（CLAUDE.md の owner の好み）
    static let primaryStyle = JPPillStyle.main(onPhoto: false)
}
