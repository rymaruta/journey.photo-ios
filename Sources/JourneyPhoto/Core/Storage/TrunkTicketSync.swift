import Foundation
import Combine

/// わたしの乗車券を旅のトランクに置く・外す（`PUT /user/trunk/settings { ticket }`・2026-10-18）。
///
/// - 置くのは `TrunkTicket.wanted` が返す1枚だけ（本人が「わたしの乗車券もトランクに入れる」をオンにし、
///   すれちがいがオンで、乗車券を選んであるとき）。どれかが外れたら `null` で外す
/// - 呼ばれるのは**すれちがいの設定が変わったとき**（`PassStore.update` の後ろ・`onSettingsChanged`）と、設定を開いたとき
/// - サーバーに今ある1枚（最後に読んだ・書いた値）を人ごとに覚え、**同じなら送らない**
/// - **中身が理由の断り**（`ticketNotPublic`・`badTicket`・`badRequest`）だけを、訳ごと人ごとに覚える
///   （起動し直しても設定に訳が出る）。同じ中身では送り直さない。ただし:
///   - 切り替えを外した（置きたい1枚が無くなった）ら忘れる → 入れ直せば送る
///   - 中身（写真・ひとこと・区間）を変えたら、別の1枚なので送る
///   - `ticketNotPublic`（写真が公開でない）は、本人があとで写真を公開にできるので、**設定を開いたときに1回だけ送り直す**
///     （`retryRefused`。`badTicket` は中身が同じなら何度送っても同じなので送り直さない）
/// - 一時的な断り（429 など、中身が理由でない 4xx）・5xx・圏外は覚えない。次の機会にまた送る
/// - 送っている途中に呼ばれたら、**終わってから最後の望みでもう一度揃える**（すぐオンにしてすぐオフにしても、
///   サーバーに残さない）
/// - トランクの口が無い人・画面写真の見本・ログインしていないときは何もしない
@MainActor
final class TrunkTicketSync: ObservableObject {

    static let shared = TrunkTicketSync()

    /// 断りの記憶が変わった合図（設定の行が読み直す）
    @Published private(set) var revision = 0

    private typealias Rule = TrunkTicketSyncRule

    private let defaults: UserDefaults
    /// 送っている途中か
    private(set) var isSending = false
    /// 送っている途中に来た、最後の頼み
    private var pending: Request?

    private struct Request {
        let userId: String
        let settings: PassSettings
        let service: TrunkService
        let retryRefused: Bool
    }

    /// いまログインしている人（すれちがいの帳の人・`PassStore.userId`）。送る直前に頼みの人と比べる
    private let currentUser: () -> String?

    /// 設定の「わたしの乗車券もトランクに入れる」の行のうち、いま出ているもの（行の id の集合）。出ている間は断りの訳を
    /// 行に出すので、知らせの帯は出さない（同じ訳が2か所に出ないように・`shouldToast`）。**数で数えない**——
    /// 出る合図が2回来ても、消える合図1回で「出ていない」に戻る（2026-10-18 4回目の見直し）
    private(set) var inlineShown: Set<String> = []

    /// 置けた・外せた答えを入れる入口の店（設定を開いたときに古い中身で記憶を戻さないように）
    private let entry: TrunkEntryStore

    init(defaults: UserDefaults = .standard, currentUser: (() -> String?)? = nil, entry: TrunkEntryStore? = nil) {
        self.defaults = defaults
        self.currentUser = currentUser ?? { PassStore.shared.userId }
        self.entry = entry ?? .shared
    }

    /// 行が出た・消えた（同じ行の合図は何度来ても1つ）
    func setInline(_ id: String, shown: Bool) {
        if shown { inlineShown.insert(id) } else { inlineShown.remove(id) }
    }

    /// 断りの訳を知らせの帯で出すか（設定の行が出ていなければ）
    var shouldToast: Bool { inlineShown.isEmpty }

    // MARK: 覚えている物

    private func readTicket(_ key: String) -> TrunkTicket? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TrunkTicket.self, from: data)
    }

    /// サーバーに今ある1枚（読んだ・書いた値）を覚える。`at` はその値をサーバーから得た時刻で、
    /// **覚えている値より古ければ上書きしない**（入口の店に残った書く前の中身で、置けた1枚の記憶を戻さない）
    func note(server ticket: TrunkTicket?, userId: String, at: Date = Date()) {
        if let knownAt = defaults.object(forKey: Rule.knownAtKey(userId)) as? Date, at < knownAt { return }
        defaults.set(at, forKey: Rule.knownAtKey(userId))
        if let ticket, let data = try? JSONEncoder().encode(ticket) {
            defaults.set(data, forKey: Rule.knownKey(userId))
        } else {
            defaults.removeObject(forKey: Rule.knownKey(userId))
        }
    }

    func known(_ userId: String) -> TrunkTicket? { readTicket(Rule.knownKey(userId)) }

    /// 覚えている断り（中身が理由のものだけ）
    func refusal(_ userId: String) -> TrunkTicketSyncRule.Refusal? {
        guard let data = defaults.data(forKey: Rule.refusedKey(userId)) else { return nil }
        return try? JSONDecoder().decode(TrunkTicketSyncRule.Refusal.self, from: data)
    }

    func refused(_ userId: String) -> TrunkTicket? { refusal(userId)?.ticket }

    /// 設定の行に出す断りの訳（置きたい1枚が、覚えている断りの中身と同じ間だけ）
    func refusalReason(_ userId: String?, settings: PassSettings) -> String? {
        guard let userId, let refusal = refusal(userId), let wanted = TrunkTicket.wanted(settings),
              wanted == refusal.ticket else { return nil }
        return refusal.reason
    }

    private func remember(_ refusal: TrunkTicketSyncRule.Refusal?, userId: String) {
        if let refusal, let data = try? JSONEncoder().encode(refusal) {
            defaults.set(data, forKey: Rule.refusedKey(userId))
        } else {
            guard defaults.object(forKey: Rule.refusedKey(userId)) != nil else { return }
            defaults.removeObject(forKey: Rule.refusedKey(userId))
        }
        revision += 1
    }

    // MARK: 揃える

    /// 揃える。新しく断られたら、その訳（画面に一行で出す）。それ以外（揃っている・送れた・一時の失敗）は nil
    @discardableResult
    func sync(userId: String?, settings: PassSettings, service: TrunkService,
              available: Bool? = nil, preview: Bool? = nil, retryRefused: Bool = false) async -> String? {
        // 既定はトランクの口がある人だけ・見本では送らない
        let available = available ?? TrunkAvailability.shared.isAvailable
        let preview = preview ?? (PreviewSession.trunkSample != nil)
        guard let userId, available, !preview else { return nil }
        let request = Request(userId: userId, settings: settings, service: service, retryRefused: retryRefused)
        // 送っている途中なら、最後の頼みとして覚えて、今の送りが終わってから揃え直す
        guard !isSending else {
            pending = request
            return nil
        }
        isSending = true
        defer { isSending = false }
        var reason = await once(request)
        while let next = pending {
            pending = nil
            if let again = await once(next) { reason = again }
        }
        return reason
    }

    /// 置けた・外せた答え（書いたあとの状態）を覚え、入口の店にも入れる（店の古い中身で記憶を戻さない）
    private func written(_ state: TrunkState, userId: String) {
        let now = Date()
        note(server: state.ticket, userId: userId, at: now)
        entry.apply(state, userId: userId, now: now)
    }

    private func once(_ r: Request) async -> String? {
        let wanted = TrunkTicket.wanted(r.settings)
        // 切り替えを外した（置きたい1枚が無い）ら断りは忘れる（入れ直したら送る）
        if wanted == nil { remember(nil, userId: r.userId) }
        let refusal = refusal(r.userId)
        let refused = Rule.blocks(refusal, retry: r.retryRefused) ? refusal?.ticket : nil
        let action = Rule.action(wanted: wanted, server: known(r.userId), refused: refused)
        // 送る直前に、頼みの人がいまログインしている人か確かめる（待っている間にログアウト・人の切り替えがあったら、
        // 前の人の乗車券を次の人のトランクに置かない・外さない）。違えば送らずに捨てる
        guard action == .none || currentUser() == r.userId else { return nil }
        switch action {
        case .none:
            return nil
        case .remove:
            // 外す側は写真を確かめないので断られない。届かなければ次に揃える
            let state = try? await r.service.setTicket(nil)
            if let state { written(state, userId: r.userId) }
            return nil
        case .put(let ticket):
            do {
                let state = try await r.service.setTicket(ticket)
                written(state, userId: r.userId)
                remember(nil, userId: r.userId)
                return nil
            } catch let refused as TrunkService.Refused {
                // 中身が理由の断りだけ覚える（一時の断りは覚えず、次にまた送る）
                guard Rule.isContentRefusal(refused.code) else { return nil }
                let reason = refused.errorDescription ?? refused.message
                remember(.init(ticket: ticket, code: refused.code ?? "", reason: reason), userId: r.userId)
                return reason
            } catch {
                return nil
            }
        }
    }
}

/// 揃え方の決まり（画面の流れに縛られない部分・テストから直に呼ぶ）
enum TrunkTicketSyncRule {

    enum Action: Equatable {
        case none
        case put(TrunkTicket)
        case remove
    }

    /// 覚えている断り（中身・サーバーの印・画面に出す訳）
    struct Refusal: Codable, Equatable {
        let ticket: TrunkTicket
        let code: String
        let reason: String
    }

    /// 中身が理由の断り（同じ中身で送っても同じ答えになる）。それ以外の 4xx（429 など）は一時の断り
    static let contentCodes: Set<String> = ["ticketNotPublic", "badTicket", "badRequest"]

    static func isContentRefusal(_ code: String?) -> Bool { code.map(contentCodes.contains) ?? false }

    /// 覚えている断りで送るのを止めるか。`ticketNotPublic` は、送り直しの機会（設定を開いた）には止めない
    static func blocks(_ refusal: Refusal?, retry: Bool) -> Bool {
        guard let refusal else { return false }
        return !(retry && refusal.code == "ticketNotPublic")
    }

    /// 何をするか（サーバーの1枚・置きたい1枚・断られた1枚から）
    static func action(wanted: TrunkTicket?, server: TrunkTicket?, refused: TrunkTicket?) -> Action {
        if wanted == server { return .none }
        guard let wanted else { return .remove }
        if wanted == refused { return .none }
        return .put(wanted)
    }

    static func knownKey(_ userId: String) -> String { "trunk.ticket.known.\(userId)" }
    static func knownAtKey(_ userId: String) -> String { "trunk.ticket.knownAt.\(userId)" }
    static func refusedKey(_ userId: String) -> String { "trunk.ticket.refusal.\(userId)" }

    /// 退会のとき（`AccountLocalData.remove`）
    static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: knownKey(userId))
        defaults.removeObject(forKey: knownAtKey(userId))
        defaults.removeObject(forKey: refusedKey(userId))
    }
}
