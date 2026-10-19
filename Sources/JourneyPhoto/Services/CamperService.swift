import Foundation

/// とおまわり号の口（photo-gallery `api-user/src/trunk.ts`・2026-10-18 段2・配り始めは 2026-10-19T04:00Z）。
/// 書くのも読むのも JWT の本人。相手は道の `{uid}` だけで、本文は送らない（何を贈るかはサーバーが決める）。
///
///     GET    /user/camper                  → CamperServerState（1日1回の数え直し）
///     GET    /users/{uid}/camper           → CamperVisitState（友達の車・訪ねた記録を足す）
///     POST   /users/{uid}/camper/gift      → { given, part? }
///     POST   /users/{uid}/camper/firewood  → { added, count, part? }
///
/// 断り（`{ error, code }`）は `Refused` で返す。`code` は英字の印: self（400）・notFriend / blocked / newAccount /
/// noPost（403）・notFound / tombstone（404）・already / notLaunched / storage（409）・deleted（410）・daily（429）。
/// 4xx の包み方は旅のトランクの口（`TrunkService.refusing`）と同じ（`APIClient.errorBodySink`）
struct CamperService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// サーバーの断り。`code` で画面の言葉を選ぶ（`CamperText.refusal`）
    struct Refused: LocalizedError, Equatable {
        let status: Int
        let message: String
        let code: String?
        var errorDescription: String? { CamperText.refusal(code: code, status: status, fallback: message) }
    }

    private func refusing<T>(_ call: () async throws -> T) async throws -> T {
        let errorBody = APIErrorBody()
        do {
            return try await APIClient.$errorBodySink.withValue(errorBody) { try await call() }
        } catch let APIError.server(status, message) where (400..<500).contains(status) && status != 401 {
            throw Refused(status: status, message: message, code: APIClient.errorCode(from: errorBody.data))
        }
    }

    /// 自分の車の部品（`launched: false` なら画面は端末の数え方のまま）
    func mine() async throws -> CamperServerState {
        try await refusing { try await api.authorized(.get, "/user/camper", as: CamperServerState.self) }
    }

    /// 友達の車を開く（訪ねた記録は友達×日で1回）。人の id の形でない値は要求を出さずに `notFound`
    func visit(_ userId: String) async throws -> CamperVisitState {
        let segment = try segment(userId)
        return try await refusing { try await api.authorized(.get, "/users/\(segment)/camper", as: CamperVisitState.self) }
    }

    /// 友達に部品を贈る（同じ相手に一度きり・1日1回）
    func gift(_ userId: String) async throws -> CamperGiftResult {
        let segment = try segment(userId)
        return try await refusing { try await api.authorized(.post, "/users/\(segment)/camper/gift", as: CamperGiftResult.self) }
    }

    /// 友達の焚き火に薪をくべる（同じ友達に1日1回）
    func firewood(_ userId: String) async throws -> CamperFirewoodResult {
        let segment = try segment(userId)
        return try await refusing {
            try await api.authorized(.post, "/users/\(segment)/camper/firewood", as: CamperFirewoodResult.self)
        }
    }

    private func segment(_ userId: String) throws -> String {
        do { return try PathID.segment(userId) } catch {
            throw Refused(status: 404, message: "", code: "notFound")
        }
    }
}
