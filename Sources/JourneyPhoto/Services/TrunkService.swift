import Foundation

/// 旅のトランクの口（`api-user/src/trunk.ts`・2026-10-17）。**本人だけが読める**
/// （行は JWT の `sub` からしか作らない）。
///
///     GET    /user/trunk                              → 状態＋posts
///     POST   /user/trunk/labels/{id}/stick            → 状態
///     DELETE /user/trunk/labels/{id}                  → 状態
///     POST   /user/trunk/labels/{id}/reroll           → 状態（pendingReroll に候補3つ）
///     POST   /user/trunk/labels/{id}/reroll/choose    → 状態
///     PUT    /user/trunk/model { model }              → 状態
///     PUT    /user/trunk/settings { receiveLabels }   → 状態
///
/// 次の版（2026-10-17 owner 承認）:
///
///     POST   /user/trunk/labels/{id}/stick { x?, y?, rot? }  → 状態（置き場つきで貼る）
///     PUT    /user/trunk/labels/{id}/place { x, y, rot }     → 状態（貼ったラベルを置き直す）
///     POST   /user/trunk/labels/{id}/unstick                 → 状態（はがして手持ちに戻す・いっぱいなら 409 full）
///     POST   /user/trunk/gacha                               → { part, duplicate, fragments, coins }（硬貨 0 は 409 noCoins）
///     POST   /user/trunk/parts/exchange { partId }           → 状態＋part（かけら5つ）
///     PUT    /user/trunk/equip { handle…key, pins[], patches[] } → 状態
///
/// 人のトランク（2026-10-18）:
///
///     GET    /users/{uid}/trunk                              → 人のトランク（見せないときは 404 → nil）
///     PUT    /user/trunk/settings { showTrunk? , ticket? }   → 状態（見せる設定・わたしの乗車券）
///
/// **書き込みの応答は、書いたあとの状態。** 画面は自分で足し引きせず、返ってきた状態をそのまま映す
/// （`TripPlanService` と同じ判断——断られた回に嘘の状態を残さない）。書き込みの応答には `posts` が
/// 無いので、前に読んだ数を引き継ぐ（`TrunkState.keepingPosts`）。
///
/// 断り（`{ error, code }`）は `Refused` で返す。`code` は英字の印（`proOnly`・`noRerollsLeft` など）
struct TrunkService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// サーバーの断り。`message` はサーバーの言い分、`code` は画面の言葉を選ぶ印
    struct Refused: LocalizedError, Equatable {
        let message: String
        let code: String?
        var errorDescription: String? { TrunkText.refusal(code: code, fallback: message) }
    }

    /// 4xx の断りを `Refused` に包む。`code` は失敗の本文（`{ error, code }`）から読む
    /// （`APIClient.errorBodySink`・`PurchaseService` と同じ受け取り方）。401 はログイン切れのまま返す
    private func refusing<T>(_ call: () async throws -> T) async throws -> T {
        let errorBody = APIErrorBody()
        do {
            return try await APIClient.$errorBodySink.withValue(errorBody) { try await call() }
        } catch let APIError.server(status, message) where (400..<500).contains(status) && status != 401 {
            throw Refused(message: message.isEmpty ? Labels.Common.loadFailed : message,
                          code: APIClient.errorCode(from: errorBody.data) ?? (status == 403 ? "proOnly" : nil))
        }
    }

    /// パスに入れる id。**英数字・`-`・`_` 以外は要求を出さずに失敗にする**（`PathID`）
    private func encoded(_ id: String) throws -> String {
        try PathID.segment(id)
    }

    func state() async throws -> TrunkState {
        try await api.authorized(.get, "/user/trunk", as: TrunkState.self)
    }

    func stick(_ id: String) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.post, "/user/trunk/labels/\(encoded(id))/stick", as: TrunkState.self)
        }
    }

    /// 置き場つきで貼る（自分の手で貼る画面）。置き場はサーバーの細かさに丸めて送る（`TrunkPlacement.clamp`）
    func stick(_ id: String, at pos: TrunkPos) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.post, "/user/trunk/labels/\(encoded(id))/stick",
                                     body: TrunkPlacement.clamp(pos), as: TrunkState.self)
        }
    }

    /// 貼ったラベルを置き直す（動かす・回す）
    func place(_ id: String, at pos: TrunkPos) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.put, "/user/trunk/labels/\(encoded(id))/place",
                                     body: TrunkPlacement.clamp(pos), as: TrunkState.self)
        }
    }

    /// はがして手持ちに戻す（手持ちが上限なら 409 `full`）
    func unstick(_ id: String) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.post, "/user/trunk/labels/\(encoded(id))/unstick", as: TrunkState.self)
        }
    }

    /// カプセルの機械を回す（硬貨1枚）。応答は状態を丸ごと返さない（`TrunkGachaResult.applied`）
    func gacha() async throws -> TrunkGachaResult {
        try await refusing {
            try await api.authorized(.post, "/user/trunk/gacha", as: TrunkGachaResult.self)
        }
    }

    private struct ExchangeBody: Encodable { let partId: String }

    /// かけら5つで、持っていない部品1つと交換
    func exchange(_ partId: String) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.post, "/user/trunk/parts/exchange", body: ExchangeBody(partId: partId), as: TrunkState.self)
        }
    }

    /// 付ける部品を全部まとめて送る（外した場所は null）
    func equip(_ equipped: TrunkEquipped) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.put, "/user/trunk/equip", body: equipped, as: TrunkState.self)
        }
    }

    /// 手持ちから削除（貼ったものは消せない）
    func remove(_ id: String) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.delete, "/user/trunk/labels/\(encoded(id))", as: TrunkState.self)
        }
    }

    /// 作り直す（Pro・月3回）。候補は応答の `pendingReroll`
    func reroll(_ id: String) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.post, "/user/trunk/labels/\(encoded(id))/reroll", as: TrunkState.self)
        }
    }

    private struct ChooseBody: Encodable { let seed: Int }

    /// 候補（またはいまの図柄）を選ぶ
    func choose(_ id: String, seed: Int) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.post, "/user/trunk/labels/\(encoded(id))/reroll/choose",
                                     body: ChooseBody(seed: seed), as: TrunkState.self)
        }
    }

    private struct ModelBody: Encodable { let model: String }

    func setModel(_ model: TrunkModel) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.put, "/user/trunk/model", body: ModelBody(model: model.rawValue), as: TrunkState.self)
        }
    }

    private struct SettingsBody: Encodable { let receiveLabels: Bool }

    func setReceiveLabels(_ on: Bool) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.put, "/user/trunk/settings", body: SettingsBody(receiveLabels: on), as: TrunkState.self)
        }
    }

    // MARK: 人のトランク（2026-10-18）

    /// `PUT /user/trunk/settings { showTrunk }` の本文（**送るのはこの1項目だけ**。ほかの設定は変えない）
    struct ShowTrunkBody: Encodable, Equatable { let showTrunk: Bool }

    /// ほかの人にトランクを見せるか（オフの間は人の口が 404）
    func setShowTrunk(_ on: Bool) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.put, "/user/trunk/settings", body: ShowTrunkBody(showTrunk: on), as: TrunkState.self)
        }
    }

    /// `PUT /user/trunk/settings { ticket }` の本文。**外すときは `null` を書く**（項目を落とすと「変えない」になる）
    struct TicketBody: Encodable, Equatable {
        let ticket: TrunkTicket?

        private enum CodingKeys: String, CodingKey { case ticket }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let ticket { try c.encode(ticket, forKey: .ticket) } else { try c.encodeNil(forKey: .ticket) }
        }
    }

    /// わたしの乗車券をサーバーに置く（人のトランクの中に出す1枚）。nil で外す。
    /// 写真が本人の公開写真でなければ 409 `ticketNotPublic`・字の形が違えば 400 `badTicket`
    func setTicket(_ ticket: TrunkTicket?) async throws -> TrunkState {
        try await refusing {
            try await api.authorized(.put, "/user/trunk/settings", body: TicketBody(ticket: ticket), as: TrunkState.self)
        }
    }

    /// 人のトランク（`GET /users/{uid}/trunk`・ログインした人だけ）。
    /// **見せていない（404）は nil**——見せない設定・ブロック・退会・行が無いを、サーバーは区別せずに返すので、
    /// 画面も区別しない（段ごと出さない）。人の id の形でない値は要求を出さずに nil（サーバーも 404 にする形）
    func theirs(_ userId: String) async throws -> TheirTrunk? {
        let segment: String
        do { segment = try encoded(userId) } catch { return nil }
        do {
            return try await api.authorized(.get, "/users/\(segment)/trunk", as: TheirTrunk.self)
        } catch let APIError.server(status, _) where status == 404 {
            return nil
        }
    }
}
