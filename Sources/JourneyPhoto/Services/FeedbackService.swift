import Foundation

// Linux では URLSession が別モジュールに居る（`ProfileService` と同じ。iOS では何も起きない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 意見箱（札 #546・2026-11-11 owner 承認「フォームまかせる」「形式は自由記述」）。
///
/// 送る口は api-user の `feedback.ts`:
///   - ログインしている → `POST /user/feedback`（返事が欲しいを受ける・送った人が分かる）
///   - していない → `POST /feedback`（IP ごとの上限。返事は約束しない）
///
/// 送るのは**自由に書いた本文**と、どの画面から・アプリの版・OS の版（機種名・端末の識別子は送らない）。
/// 写真を添えたときは、応答の署名つき URL へ JPEG を PUT する（`ImagePreparer` を通した＝位置と撮影情報を落とした1枚）。
///
/// **同じ id の送り直しは1件のまま**（サーバーが冪等）。圏外の下書き（`FeedbackOutbox`）は id を持ったまま送り直す。
struct FeedbackService {

    private let api: APIClient
    /// 写真の PUT（試験で差し替える）
    private let putPhoto: @Sendable (URLRequest, Data) async throws -> URLResponse

    init(api: APIClient,
         putPhoto: (@Sendable (URLRequest, Data) async throws -> URLResponse)? = nil) {
        self.api = api
        self.putPhoto = putPhoto ?? { request, body in
            try await URLSession.shared.upload(for: request, from: body).1
        }
    }

    /// 本文の上限（サーバーの `FEEDBACK_TEXT_MAX` と同じ。数え方は UTF-16＝`PostLimits`）
    static let textMax = 1000
    /// 添える写真の上限（サーバーの `FEEDBACK_PHOTO_MAX_BYTES`）
    static let photoMaxBytes = 10 * 1024 * 1024

    /// サーバーへ送る形（`parseFeedback` が読む欄）
    struct Body: Encodable, Equatable {
        struct Photo: Encodable, Equatable {
            let contentType: String
            let size: Int
        }
        let id: String
        let text: String
        let screen: String
        let appVersion: String
        let os: String
        let platform: String
        let wantsReply: Bool
        let photo: Photo?
    }

    struct Response: Decodable {
        struct Upload: Decodable {
            let url: String
            let contentType: String
        }
        let ok: Bool
        let id: String
        let upload: Upload?
    }

    /// 送る1件の本文を組む。**ログインしていない人は返事を約束しない**（宛先が無い）
    static func body(for draft: FeedbackDraft, photoSize: Int?, signedIn: Bool,
                     appVersion: String = FeedbackService.appVersion,
                     os: String = FeedbackService.osVersion) -> Body {
        Body(id: draft.id,
             text: draft.text,
             screen: draft.screen,
             appVersion: appVersion,
             os: os,
             platform: "ios",
             wantsReply: signedIn && draft.wantsReply,
             photo: photoSize.map { Body.Photo(contentType: "image/jpeg", size: $0) })
    }

    /// 送る口（ログインの有無で分ける）
    static func path(signedIn: Bool) -> String { signedIn ? "/user/feedback" : "/feedback" }

    /// 1件送る。写真があれば続けて PUT する。
    /// - Parameter signedIn: この下書きを書いた人が、いまもログインしているか（`FeedbackOutbox.signedIn`）
    func send(_ draft: FeedbackDraft, photo: Data?, signedIn: Bool) async throws {
        let body = Self.body(for: draft, photoSize: photo?.count, signedIn: signedIn)
        let response: Response
        // 口は文字のまま書く（`Tools/verify.sh` の Web 版との突き合わせが、アプリが叩く口を字面で拾う）
        if signedIn {
            response = try await api.authorized(.post, "/user/feedback", body: body, as: Response.self)
        } else {
            response = try await api.anonymous(.post, "/feedback", body: body, as: Response.self)
        }
        guard let photo, let upload = response.upload else { return }
        guard let url = URL(string: upload.url) else {
            throw APIError.decoding("署名付き URL を読めませんでした")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        // 署名に入っている種別と完全に同じ文字列で送る（違うと 403。`UploadService.put` と同じ）
        request.setValue(upload.contentType, forHTTPHeaderField: "Content-Type")
        let result: URLResponse
        do {
            result = try await putPhoto(request, photo)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw APIError.unreachable
        }
        guard let http = result as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: (result as? HTTPURLResponse)?.statusCode ?? 500,
                                  message: L("写真を送れませんでした", "Couldn't send the photo"))
        }
    }

    /// アプリの版（設定の最下部と同じ「1.1.20 (3)」の形）
    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// OS の版だけ（「iOS 18.1」。機種名・端末の識別子は送らない）
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    /// 送れなかった理由が「あとで送り直せば届く」ものか（圏外・混雑・サーバーの一時的な不調）。
    /// **違うもの（本文が空・形が違う・その日の上限）は送り直さない**——下書きに残すと、開くたびに同じ失敗を繰り返す
    static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case APIError.unreachable:
            return true
        case APIError.server(let status, _):
            return status >= 500 || status == 408
        case APIError.notAuthenticated:
            // ログインが切れた回は、次に送るときにログインしていない人の口で送る（`FeedbackOutbox.flush`）
            return true
        default:
            return false
        }
    }
}
