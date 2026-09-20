import Foundation

/// 通報とブロック。
///
/// **App Store の審査で見られる場所。** ユーザーが作った内容を載せるアプリは、
/// (1) 不適切な内容を通報できること、(2) 迷惑な相手をブロックできること、
/// (3) 規約への同意、が要る（ガイドライン 1.2 / UGC）。
/// 3つとも api-user 側に既にある口で満たせる。
struct ModerationService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    /// 通報の理由。**サーバーの許可リストと同じ並び**
    /// （`api-user/src/report.ts` の `REPORT_REASONS`）。
    /// ここに無い値を送ると 400「理由を選んでください」で返る。
    enum ReportReason: String, CaseIterable, Identifiable {
        case copyright, privacy, sexual, violence, harassment, spam, other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .copyright: return "自分の写真を無断で使われている"
            case .privacy: return "写っている人・場所の権利を害している"
            case .sexual: return "わいせつな内容"
            case .violence: return "暴力的・残虐な内容"
            case .harassment: return "特定の人への攻撃・いやがらせ"
            case .spam: return "広告・勧誘・スパム"
            case .other: return "その他"
            }
        }
    }

    /// 補足の上限。長い文章を溜めるところではない（サーバーも500で切る）。
    static let reportNoteMax = 500

    /// 通報する。**同じ人が押し直したら上書き**なので、二重送信を怖がらなくてよい。
    /// 自分の投稿は 400 で断られる。
    func report(photoId: String, reason: ReportReason, note: String?) async throws {
        struct Body: Encodable {
            let reason: String
            let note: String?
        }
        let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        try await api.authorizedVoid(
            .post, "/photos/\(encoded(photoId))/report",
            body: Body(
                reason: reason.rawValue,
                note: trimmed.isEmpty ? nil : String(trimmed.prefix(Self.reportNoteMax))
            )
        )
    }

    struct BlockResult: Decodable { let blocked: Bool }

    func block(userId: String) async throws {
        _ = try await api.authorized(.post, "/users/\(encoded(userId))/block", as: BlockResult.self)
    }

    func unblock(userId: String) async throws {
        _ = try await api.authorized(.delete, "/users/\(encoded(userId))/block", as: BlockResult.self)
    }

    struct BlockList: Decodable {
        let blockedIds: [String]
        let users: [FollowUser]
    }

    func blocks() async throws -> BlockList {
        try await api.authorized(.get, "/user/blocks", as: BlockList.self)
    }
}
