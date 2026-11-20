import Foundation

/// 「AI に頼む」の1往復（札 #652）。答えは**アプリの部品**で返す（観光スポットの札、地図のピン、みんなの写真、
/// 行きたい、旅行プランにする）。文は短い1かたまりだけ。
///
/// 端末の中だけに置く（`AskHistoryStore`）。サーバーに残さない。
struct AskExchange: Identifiable, Equatable, Codable {
    var id: String = UUID().uuidString
    let question: String
    var answer: AskAnswer
}

struct AskAnswer: Equatable, Codable {

    /// どこで答えたか（答えの下の1行に出す）
    enum Engine: String, Codable {
        /// この iPhone の中の AI（Foundation Models）
        case device
        /// サーバー（東京）の AI。Pro で、端末の AI が無い iPhone だけ
        case server
        /// AI を使わず、言葉の表と観光スポットの台帳で答えた
        case table
        /// 断った（AI を呼んでいない・回数も使っていない）
        case refused
    }

    /// 答えの状態（Components 06 の4つの状態に合わせる）
    enum State: String, Codable {
        case answered
        /// 合う観光スポットが無い
        case empty
        /// 台帳を読めなかった
        case failed
        /// 圏外（前に見た分だけで答えた）
        case offline
    }

    /// 引いたもの（答えの下の札。押しても使い方の頁は開かない・入口は設定の1か所だけ `HelpLink`）
    struct Source: Equatable, Codable, Hashable {
        enum Kind: String, Codable { case spots, photos, wishlist, trips, help }
        let kind: Kind
        let label: String
    }

    var engine: Engine
    var state: State = .answered
    /// 答えの文。観光スポットの札だけの答えでは空
    var text: String = ""
    /// 引けるものが無い質問に、一般的な知識で答えた（「一般的な答え」の印）
    var general = false
    /// 札に出す観光スポット（`spotId`・アプリが選んだ順）
    var spotIds: [String] = []
    /// 観光スポットごとの現在地からの距離（km・近さで探したときだけ）
    var distances: [String: Double] = [:]
    /// みんなの写真（`Photo.id`・公開の写真だけ。押すと持ち主の写真の詳細へ）
    var photoIds: [String] = []
    var sources: [Source] = []
    /// 読み取りの札（「現在地から 30km」「夕方」）
    var chips: [String] = []
    /// 札の上の見出し（「夕方の案内がある観光スポット（3か所）」）
    var heading: String? = nil
    /// 1行の添え書き（台帳に無いこと、近さを使えなかったこと、AI を使えなかった理由）
    var note: String? = nil
    /// 「旅行プランにする」を出すか
    var offersPlan = false
    /// 答えの上の帯（回数を使い切った・サーバーの AI を休んでいる）
    var limit: AskLimitReason? = nil
    /// 空のときの言い替え（押すと条件を1つ外して、アプリが選び直す。AI は呼ばない）
    var relaxedQuery: String? = nil

    /// AI を使った答えか（「AI の答えは間違うことがあります」を出す）
    var usedAI: Bool { engine == .device || engine == .server }

    /// 答えの下の1行（どこで答えたか）
    var engineLine: String {
        switch engine {
        case .device:
            return L("この iPhone の中で答えました", "Answered on this iPhone")
        case .server:
            return L("サーバー（東京）で答えました。送ったのは、打った文と直前の2往復、引いた観光スポットの行と使い方の頁の抜き書きだけです",
                     "Answered on our server in Tokyo. Only your words, the last two exchanges, the spot rows and help excerpts were sent.")
        case .table:
            return L("この iPhone の中で言葉を読み、観光スポットから選びました", "Read your words on this iPhone and picked from the spots")
        case .refused:
            return ""
        }
    }

    /// 断りの答え（回数を使わない・何も引かない）
    static func refused(care: Bool) -> AskAnswer {
        AskAnswer(engine: .refused, text: care ? AskGuard.refusal + "\n" + AskGuard.careLine : AskGuard.refusal)
    }
}

/// 「AI の答えは間違うことがあります」（答えの下にいつも）
enum AskText {
    static var disclaimer: String { L("AI の答えは間違うことがあります", "AI answers can be wrong") }
    static var generalBadge: String { L("一般的な答え", "General answer") }
    static var sourcesHead: String { L("引いたもの", "Looked up") }
    static var followUp: String { L("続けて聞く", "Ask a follow-up") }
    static var makePlan: String { L("旅行プランにする", "Make a trip plan") }
    static var loading: String { L("答えを用意しています", "Preparing an answer") }
    static var emptyTitle: String { L("合う観光スポットがありません", "No matching spots") }
    static var failedTitle: String { L("観光スポットを読み込めませんでした", "Couldn't load the spots") }
    static var failedDetail: String { L("通信が途切れたようです。前に見た分はそのまま残っています。", "The connection seems to have dropped. What you've seen is still here.") }
    static var offlineLine: String { L("圏外なので AI に聞けません。言葉で読んで、前に見た観光スポットから選びました", "You're offline, so AI isn't available. Picked from spots you've already seen.") }
    static var signedOutLine: String { L("ログインすると AI に聞けます。いまは言葉で読んで探しました", "Sign in to ask AI. This time we searched by reading your words.") }
    static var noDeviceAILine: String { L("この iPhone では AI に聞けないため、言葉で探しました", "AI isn't available on this iPhone, so we searched by your words.") }
    static var unansweredLine: String { L("この質問は AI でないと答えられません。", "Only AI can answer this question.") }
    static var silentLine: String { L("AI が答えなかったので、言葉で読んで探しました", "AI didn't answer, so we searched by reading your words.") }
    static var noLocationLine: String { L("現在地が分からないので、近さでは絞っていません", "Couldn't get your location, so results aren't sorted by distance.") }
    static var weeklyLine: String { L("観光スポットの情報に週ごとの見頃は無いので、季節の案内がある所を出しました", "Spot info has no weekly timing, so these have notes for the season.") }

    /// 「現在地から 30km」
    static func nearChip(km: Int) -> String { L("現在地から \(km)km", "Within \(km) km") }
    /// 「8km」（札の距離）
    static func distance(_ km: Double) -> String {
        km < 1 ? L("1km 未満", "< 1 km") : L("\(Int(km.rounded()))km", "\(Int(km.rounded())) km")
    }
}
