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

    // MARK: - コメントの通報（2026-10-11 判断）
    //
    // サーバーにコメントを通報する口は無い。**写真の通報の口に載せる**——送れるのは
    // `reason` と `note`（500字・制御文字は落とされる＝改行は消える）だけなので、
    // 誰のどのコメントかを `note` の頭に書く。運営は写真の通報として読む。
    //
    // ⚠️ 通報の行は「1人1写真に1件」（`report.ts` の `reportId`）。同じ写真を前に通報して
    // いれば、コメントの通報で上書きされる。自分の写真には送れない（400）ので、
    // 自分の写真のコメントには通報を出さない（持ち主は消せる）

    /// 通報するコメント（誰の・どの・何と書いたか）
    struct ReportedComment: Equatable {
        let id: String
        let authorId: String
        let authorName: String
        let text: String

        init(_ comment: PhotoComment) {
            self.init(id: comment.id, authorId: comment.uid, authorName: comment.name, text: comment.text)
        }

        init(id: String, authorId: String, authorName: String, text: String) {
            self.id = id
            self.authorId = authorId
            self.authorName = authorName
            self.text = text
        }
    }

    /// コメントを通報するときの、本人が書く補足の上限（残りにコメントの本文を入れる）
    static let commentReportUserNoteMax = 200

    /// コメントの通報で送る `note`。**500字（UTF-16）に必ず収める**——頭（誰の・どのコメントか）と
    /// 本人の補足は切らずに入れ、コメントの本文を残りに詰める。改行はサーバーで消えるので空白にする
    static func commentReportNote(_ comment: ReportedComment, note: String?) -> String {
        func oneLine(_ text: String) -> String {
            text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        let name = PostLimits.clamp(oneLine(comment.authorName), limit: 60)
        var head = "[コメントの通報] 投稿者: \(name) (\(comment.authorId)) / コメントID: \(comment.id)"
        let extra = PostLimits.clamp(oneLine(note ?? ""), limit: commentReportUserNoteMax)
        if !extra.isEmpty { head += " / 補足: \(extra)" }
        head = PostLimits.clamp(head, limit: reportNoteMax)
        let label = " / 本文: "
        let room = reportNoteMax - PostLimits.length(head) - PostLimits.length(label)
        guard room > 0 else { return head }
        return head + label + PostLimits.clamp(oneLine(comment.text), limit: room)
    }

    // MARK: - すれちがいのカードのひとことの通報（2026-10-16 判断）
    //
    // ひとことは**署名が無い**（Bluetooth の中身は誰でも書ける）。写真の通報として送ると、書いていないかも
    // しれない写真の持ち主が罰されうる。コメントの通報と同じく写真の通報の口に載せるが、頭に
    // 「すれちがいのカードのひとこと」の印と「写真の持ち主が書いたとは限らない」を書き、本文を添える。
    // 運営はこの印を見て、写真ではなくひとことの通報として読む

    /// ひとことの通報の補足の頭の印（テストで見張る）
    /// 2026-10-16: 乗車券の発・着の字も同じ通報に入れる（ひとこと・発・着＝相手が書いた字）
    static let passNoteMarker = "[すれちがいのカードに書かれた字]"

    static func passNoteReportNote(_ text: String, note: String?) -> String {
        func oneLine(_ text: String) -> String {
            text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        var head = "\(passNoteMarker) 署名なし（写真の持ち主が書いたとは限らない・写真の通報ではない）"
        let extra = PostLimits.clamp(oneLine(note ?? ""), limit: commentReportUserNoteMax)
        if !extra.isEmpty { head += " / 補足: \(extra)" }
        head = PostLimits.clamp(head, limit: reportNoteMax)
        let label = " / 本文: "
        let room = reportNoteMax - PostLimits.length(head) - PostLimits.length(label)
        guard room > 0 else { return head }
        return head + label + PostLimits.clamp(oneLine(text), limit: room)
    }

    /// 写真の通報に、前に送ったひとことの通報を一緒に入れる（2026-10-16 の読み直し）。
    ///
    /// **サーバーの通報は「1人1写真に1件」で上書き**（`report.ts` の `reportId`）。同じカードのひとことを
    /// 先に通報してから写真を通報すると、ひとことの通報が消える。写真の通報の補足の後ろに、前のひとことの通報
    /// （印と本文）を足して送る。500 字に収める（写真の補足を先に・ひとことは残りに）
    static func photoReportWithPassNote(_ note: String?, passNote: String) -> String {
        let head = PostLimits.clamp((note ?? "").trimmingCharacters(in: .whitespacesAndNewlines), limit: commentReportUserNoteMax)
        let label = head.isEmpty ? "" : " / 前に送った通報: "
        let room = reportNoteMax - PostLimits.length(head) - PostLimits.length(label)
        guard room > 0 else { return head }
        return head + label + PostLimits.clamp(passNoteReportNote(passNote, note: nil), limit: room)
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
