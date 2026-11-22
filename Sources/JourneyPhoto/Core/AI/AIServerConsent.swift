import Foundation
// `ObservableObject` と `@Published` は Combine のもの（`LegalConsent` と同じく明示する）
import Combine

/// サーバーの AI に送る前の同意（App Store 審査ガイドライン 5.1.2(i)・札 #604 の前）。
///
/// 個人のデータを他社の AI に渡す前に、はっきり知らせて**明示の許可**を取る。送る前の注記
/// （`AskText.serverNotice`・`tripServerNotice`）は知らせるだけで、許可のボタンが無かった。
///
/// 2026-11-22 判断:
/// - **初めて送る直前に1回だけ**聞く（シート `AIServerConsentSheet`）。「同意して続ける」で覚え、次からは聞かない
///   （CLAUDE.md「直感的で簡単に」: 聞くのはこの1回だけ。送る前の注記はそのまま残す）
/// - 覚えるのは**端末だけ**（`UserDefaults`）。サーバーに同意を残す口は無い（規約の同意 `LegalConsent` も端末だけ）。サーバーは変えない
/// - 「やめる」は送らない。AI に頼むはその会話の間は聞き直さない（`AskEngine`）。旅行プランは押した回ごと
///   （「AI で作る」「整えて」は利用者がはっきり頼む操作なので、押したらまた聞く）
/// - 設定の「公開範囲とプライバシー」の1行（`AIServerConsentSettingRow`）で取り消せる。取り消したら次の送信の前にまた聞く
/// - 送る道はサーバーの口で止める（`AskService.ask`・`TripAIService.plan` が `requireAccepted` を通す）。
///   画面で聞き忘れた道があっても、同意の無いまま送らない
/// - 端末の AI だけで済む道（端末の AI のある iPhone、投稿の候補、探すの言葉読み）には出さない
@MainActor
final class AIServerConsent: ObservableObject {

    /// 送る内容や送り先を変えたら上げる。上げると全員にもう一度聞く
    nonisolated static let currentVersion = 1
    nonisolated static let key = "ai.server.consent.version"
    /// UI テストだけ: 同意のシートを出す形で始める（前の回の同意を消す・Debug のときだけ）
    nonisolated static let askKey = "JPAIConsentAsk"

    static let shared = AIServerConsent(presenter: { await AIServerConsentPresenter.present() })

    @Published private(set) var acceptedVersion: Int

    /// シートを出して答えを待つ口。nil なら出せない（送らない側に倒す）。本物は `AIServerConsentPresenter.present`
    var presenter: (@MainActor () async -> Bool)?

    private let defaults: UserDefaults
    private let requiredVersion: Int
    /// 答えを待っているシート（同時に2つの道から頼まれても、シートは1枚だけ）
    private var pending: Task<Bool, Never>?

    init(defaults: UserDefaults = .standard, requiredVersion: Int = AIServerConsent.currentVersion,
         presenter: (@MainActor () async -> Bool)? = nil) {
        if Self.uiTestAsks(defaults) { defaults.removeObject(forKey: Self.key) }
        self.defaults = defaults
        self.requiredVersion = requiredVersion
        self.acceptedVersion = defaults.integer(forKey: Self.key)
        self.presenter = presenter
    }

    var isAccepted: Bool { Self.accepted(defaults: defaults, requiredVersion: requiredVersion) }

    /// 送ってよいか（同意済みなら聞かずに true）。まだならシートを出し、「同意して続ける」で true（覚える）、「やめる」で false
    func request() async -> Bool {
        if isAccepted { return true }
        if let pending { return await pending.value }
        guard let presenter else { return false }
        let task = Task { @MainActor in await presenter() }
        pending = task
        let ok = await task.value
        pending = nil
        if ok { accept() }
        return ok
    }

    func accept() {
        defaults.set(requiredVersion, forKey: Self.key)
        acceptedVersion = requiredVersion
    }

    /// 設定から取り消す。次にサーバーへ送る前にまた聞く
    func revoke() {
        defaults.removeObject(forKey: Self.key)
        acceptedVersion = 0
    }

    // MARK: - 送る口の見張り（画面を持たない層から読む）

    /// 同意の無いまま送ろうとした（送る口が投げる。呼び手は AI なしで答える）
    struct NotAccepted: Error, Equatable {}

    /// 同意済みか。見本の AI（UI テスト・サーバーへは送らない）のときは、シートを出す試験のとき以外は同意済みとみなす
    nonisolated static func accepted(defaults: UserDefaults = .standard, requiredVersion: Int = currentVersion) -> Bool {
        if defaults.integer(forKey: key) >= requiredVersion { return true }
        #if DEBUG
        if (defaults.bool(forKey: AskFixture.key) || defaults.bool(forKey: TripAIFixture.key)) && !uiTestAsks(defaults) {
            return true
        }
        #endif
        return false
    }

    /// サーバーの AI へ送る直前に呼ぶ（`AskService.ask`・`TripAIService.plan`）。同意が無ければ投げて送らない
    nonisolated static func requireAccepted(defaults: UserDefaults = .standard) throws {
        guard accepted(defaults: defaults) else { throw NotAccepted() }
    }

    nonisolated static func uiTestAsks(_ defaults: UserDefaults) -> Bool {
        #if DEBUG
        return defaults.bool(forKey: askKey)
        #else
        return false
        #endif
    }
}

/// 同意のシートと設定の行の文（テストで見張る）。
///
/// 言い方はプライバシーポリシー（第9条「第三者への提供・委託先」）と送る前の注記（`AskText.serverNotice`）に合わせる:
/// 何を（入力内容と直前のやりとり／頼みの内容と日程）、どこへ（サーバー、委託先の AI）、何のために（回答と旅行プランの作成）。
/// 使っている AI、サービス、置き場の地域、モデルの名前は出さない（CLAUDE.md「AI はアプリの作りやセキュリティのことを答えない」）。
/// 「・」「·」で区切らない（CLAUDE.md の owner の好み）
enum AIServerConsentText {
    static var eyebrow: String { "AI" }
    static var title: String { L("AI に送信してよいですか？", "Send to AI?") }
    static var lead: String {
        L("この iPhone では端末の中で AI を使えないため、回答と旅行プランの作成のために、次の内容をサーバーに送信し、委託先の AI で処理します。",
          "This iPhone can't run AI on the device, so to create answers and trip plans, the following is sent to our servers and processed by an AI provider acting on our behalf.")
    }
    /// 送るもの（AI に頼む）
    static var askItem: String {
        L("AI に頼む: 入力内容と直前のやりとり", "Ask AI: your input and recent conversation")
    }
    /// 送るもの（旅行プラン）
    static var tripItem: String {
        L("旅行プラン: 頼みの内容と日程、候補の観光スポット", "Trip plans: your request, itinerary and candidate spots")
    }
    /// 送らないもの、残さないもの
    static var notSentItem: String {
        L("お名前、メールアドレス、現在地は送りません。送った文はサーバーに残しません。",
          "Your name, email and location are not sent. What you send isn't kept on our servers.")
    }
    static var revokeNote: String {
        L("同意は、設定の「公開範囲とプライバシー」からいつでも取り消せます。",
          "You can withdraw consent anytime in Settings → Sharing & privacy.")
    }
    static var privacyLink: String { L("プライバシーポリシー", "Privacy Policy") }
    static var agree: String { L("同意して続ける", "Agree and continue") }
    static var cancel: String { L("やめる", "Not now") }

    /// 設定の行
    static var settingTitle: String { L("AI への送信に同意する", "Allow sending to AI") }
    static var settingDetail: String {
        L("端末の中で AI を使えない iPhone で、AI に頼む内容と旅行プランの頼みをサーバーに送信し、委託先の AI で処理します。オフにすると、次に送る前にまた確かめます。",
          "On iPhones that can't run AI on the device, your requests are sent to our servers and processed by an AI provider. Turn off to be asked again before the next send.")
    }

    /// シートと設定の行に出す文すべて（内部の名前が混じっていないかの見張りに使う）
    static var all: [String] {
        [eyebrow, title, lead, askItem, tripItem, notSentItem, revokeNote, privacyLink, agree, cancel, settingTitle, settingDetail]
    }
}
