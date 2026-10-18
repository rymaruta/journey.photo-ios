import Foundation

/// わたしの乗車券を旅のトランクに置く・外す（`PUT /user/trunk/settings { ticket }`・2026-10-18）。
///
/// - 置くのは `TrunkTicket.wanted` が返す1枚だけ（本人が「わたしの乗車券もトランクに入れる」をオンにし、
///   すれちがいがオンで、乗車券を選んであるとき）。どれかが外れたら `null` で外す
/// - サーバーに今ある1枚（最後に読んだ・書いた値）を人ごとに覚え、**同じなら送らない**
/// - 断られた中身（409 `ticketNotPublic` など）も覚え、**同じ中身で送り直さない**。断りは呼び手に一言で返す
/// - トランクの口が無い人・画面写真の見本では何もしない
@MainActor
final class TrunkTicketSync {

    static let shared = TrunkTicketSync()

    private typealias Rule = TrunkTicketSyncRule

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func read(_ key: String) -> TrunkTicket? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TrunkTicket.self, from: data)
    }

    private func write(_ ticket: TrunkTicket?, _ key: String) {
        if let ticket, let data = try? JSONEncoder().encode(ticket) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// サーバーに今ある1枚（読んだ・書いた値）を覚える
    func note(server ticket: TrunkTicket?, userId: String) {
        write(ticket, Rule.knownKey(userId))
    }

    func known(_ userId: String) -> TrunkTicket? { read(Rule.knownKey(userId)) }
    func refused(_ userId: String) -> TrunkTicket? { read(Rule.refusedKey(userId)) }

    /// 揃える。断られたら、その訳（画面に一行で出す）。それ以外（揃っている・送れた・圏外）は nil
    @discardableResult
    func sync(userId: String?, settings: PassSettings, service: TrunkService,
              available: Bool? = nil, preview: Bool? = nil) async -> String? {
        // 既定はトランクの口がある人だけ・見本では送らない
        let available = available ?? TrunkAvailability.shared.isAvailable
        let preview = preview ?? (PreviewSession.trunkSample != nil)
        guard let userId, available, !preview else { return nil }
        let action = Rule.action(wanted: TrunkTicket.wanted(settings), server: known(userId), refused: refused(userId))
        switch action {
        case .none:
            return nil
        case .remove:
            // 外す側は断られない（写真を確かめない）。圏外なら次に揃える
            let state = try? await service.setTicket(nil)
            if let state { note(server: state.ticket, userId: userId) }
            return nil
        case .put(let ticket):
            do {
                let state = try await service.setTicket(ticket)
                note(server: state.ticket, userId: userId)
                write(nil, Rule.refusedKey(userId))
                return nil
            } catch let refused as TrunkService.Refused {
                write(ticket, Rule.refusedKey(userId))
                return refused.errorDescription
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

    /// 何をするか（サーバーの1枚・置きたい1枚・断られた1枚から）
    static func action(wanted: TrunkTicket?, server: TrunkTicket?, refused: TrunkTicket?) -> Action {
        if wanted == server { return .none }
        guard let wanted else { return .remove }
        if wanted == refused { return .none }
        return .put(wanted)
    }

    static func knownKey(_ userId: String) -> String { "trunk.ticket.known.\(userId)" }
    static func refusedKey(_ userId: String) -> String { "trunk.ticket.refused.\(userId)" }

    /// 退会のとき（`AccountLocalData.remove`）
    static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: knownKey(userId))
        defaults.removeObject(forKey: refusedKey(userId))
    }
}
