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

    /// パスに入れる ID。**英数字・`-`・`_` 以外は要求を出さずに失敗にする**（`PathID`）
    private func encoded(_ value: String) throws -> String {
        try PathID.segment(value)
    }

    /// 通報の理由。**サーバーの許可リストと同じ並び**
    /// （`api-user/src/report.ts` の `REPORT_REASONS`）。
    /// ここに無い値を送ると 400「理由を選んでください」で返る。
    enum ReportReason: String, CaseIterable, Identifiable {
        case copyright, privacy, sexual, violence, harassment, spam, other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .copyright: return L("自分の写真を無断で使われている", "My photo is used without permission")
            case .privacy: return L("写っている人・場所の権利を害している", "Violates someone's privacy or rights")
            case .sexual: return L("わいせつな内容", "Sexually explicit")
            case .violence: return L("暴力的・残虐な内容", "Violent or graphic")
            case .harassment: return L("特定の人への攻撃・いやがらせ", "Harassment of a person")
            case .spam: return L("広告・勧誘・スパム", "Spam or advertising")
            case .other: return L("その他", "Something else")
            }
        }
    }

    /// 補足の上限。長い文章を溜めるところではない（サーバーも500で切る・`report.ts` の
    /// `REPORT_NOTE_MAX`。数え方は UTF-16 の単位——`PostLimits.length`）。
    /// **欄で止める**（`ReportSheet`）。ここで切るのは欄を通らずに来たときの支えだけ
    static let reportNoteMax = 500

    /// 送る補足。空なら送らない。**サーバーと同じ単位で切る**——字（書記素）で `prefix` を取ると、
    /// 絵文字の多い補足は上限内に見えてもサーバーで黙って切られた
    static func reportNote(_ note: String?) -> String? {
        let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : PostLimits.clamp(trimmed, limit: reportNoteMax)
    }

    /// 通報する。**同じ人が押し直したら上書き**なので、二重送信を怖がらなくてよい。
    /// 自分の投稿は 400 で断られる。
    func report(photoId: String, reason: ReportReason, note: String?) async throws {
        struct Body: Encodable {
            let reason: String
            let note: String?
        }
        try await api.authorizedVoid(
            .post, "/photos/\(encoded(photoId))/report",
            body: Body(reason: reason.rawValue, note: Self.reportNote(note))
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
