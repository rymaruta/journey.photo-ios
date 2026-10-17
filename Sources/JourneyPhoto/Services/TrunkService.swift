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
}
