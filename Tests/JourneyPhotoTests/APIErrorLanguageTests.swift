import XCTest
@testable import JourneyPhoto

/// サーバーの断り文（日本語だけ）を、英語の画面にそのまま出さない（2026-10-21）。
///
/// 🔴 api-user の `{ error }` は日本語だけ（例: `comments.ts`「同じ写真へのコメントは10件までです」）。
/// `APIError` は 403 の本文・401 と 403 以外の本文をそのまま出していたので、英語の画面にも
/// 日本語が出ていた。英語の画面では状態の数ごとの文に替え、日本語の画面では今までどおり本文を出す。
final class APIErrorLanguageTests: XCTestCase {

    private let commentLimit = "同じ写真へのコメントは10件までです"

    /// 英語の画面: よく出る場面（上限・権限・無い・ぶつかる・サーバー側）で日本語を出さない
    func testEnglishScreenNeverShowsServerJapanese() {
        for status in [400, 403, 404, 409, 410, 413, 418, 429, 500, 502, 503] {
            let text = APIError.server(status: status, message: commentLimit).description(language: "en")
            XCTAssertFalse(APIError.containsJapanese(text), "\(status) で日本語が出た: \(text)")
            XCTAssertNotEqual(text, commentLimit)
            XCTAssertFalse(text.isEmpty)
        }
    }

    /// 英語の画面の文は、状態の数ごとに分かる言い方にする
    func testEnglishScreenUsesStatusSpecificText() {
        func en(_ status: Int, _ message: String = "上限です") -> String {
            APIError.server(status: status, message: message).description(language: "en")
        }
        XCTAssertTrue(en(429).contains("limit"), en(429))
        XCTAssertTrue(en(403).contains("limit"), "本文つきの 403 は上限か断り: \(en(403))")
        XCTAssertTrue(en(403, "").contains("permission"), "本文の無い 403 は門前払い: \(en(403, ""))")
        XCTAssertTrue(en(404).contains("found"), en(404))
        XCTAssertTrue(en(409).contains("conflicts"), en(409))
        XCTAssertTrue(en(500).contains("(500)"), en(500))
        XCTAssertTrue(en(503).contains("(503)"), en(503))
        XCTAssertEqual(en(410, APIError.accountGoneMessage), "This account has been deleted.")
        XCTAssertEqual(en(410, "この招待リンクは期限が切れています。送った人にもう一度もらってください"),
                       "This is no longer available.", "招待リンクの 410 を「アカウントは削除」と言わない")
        XCTAssertEqual(en(401), "Your session expired. Please sign in again.")
    }

    /// 日本語の画面: 本文があれば今までどおり本文を出す
    func testJapaneseScreenKeepsServerText() {
        for status in [400, 403, 404, 409, 410, 429, 500] {
            XCTAssertEqual(APIError.server(status: status, message: commentLimit).description(language: "ja"),
                           commentLimit, "\(status)")
        }
        // 既定（いまのアプリは日本語で固定）も同じ
        XCTAssertEqual(APIError.server(status: 429, message: commentLimit).errorDescription, commentLimit)
        // 本文の無い 403 は今までどおりの固定の文
        XCTAssertTrue(APIError.server(status: 403, message: "").description(language: "ja").contains("お問い合わせ"))
        XCTAssertEqual(APIError.server(status: 401, message: "Unauthorized").description(language: "ja"),
                       "ログインの有効期限が切れました。ログインし直してください")
    }

    /// 🔴 **本文の無い失敗の日本語の文（2026-10-21 に意図して変えた）。** 以前は 403 以外どれも
    /// 「サーバーエラー（404）」だった。API Gateway の門前払い（429 の絞り・5xx）などで本文が無い回に
    /// 何が起きたか分かる文にした。黙って戻ったり変わったりしないよう、文そのものを守る
    func testJapaneseTextWithoutServerBody() {
        func ja(_ status: Int) -> String { APIError.server(status: status, message: "").description(language: "ja") }
        XCTAssertEqual(ja(400), "送った内容を受け付けられませんでした。確かめてもう一度お試しください")
        XCTAssertEqual(ja(404), "見つかりませんでした。削除されたか、見られなくなった可能性があります")
        XCTAssertEqual(ja(409), "ほかの変更とぶつかりました。読み直してからもう一度お試しください")
        XCTAssertEqual(ja(410), "もう使えなくなっています")
        XCTAssertEqual(ja(413), "大きすぎて送れませんでした")
        XCTAssertEqual(ja(429), "回数の上限に達しました。しばらくしてからもう一度お試しください")
        XCTAssertEqual(ja(500), "サーバーで問題が起きました（500）。少し待ってからもう一度お試しください")
        XCTAssertEqual(ja(503), "サーバーで問題が起きました（503）。少し待ってからもう一度お試しください")
        XCTAssertEqual(ja(418), "サーバーエラー（418）", "知らない状態は今までどおり")
        XCTAssertEqual(ja(403), "この操作をする権限がありません。登録直後にこの状態になった場合は、お手数ですがお問い合わせください（ログインし直しても直りません）",
                       "本文の無い 403 は今までどおり")
    }

    /// アプリが `L()` で作った英語の文（`UploadService` など）は、英語の画面でそのまま出す
    func testAppMadeEnglishTextPassesThrough() {
        XCTAssertEqual(APIError.server(status: 400, message: "File is too large (50 MB max)").description(language: "en"),
                       "File is too large (50 MB max)")
        XCTAssertNil(APIError.displayableServerText(commentLimit, language: "en"))
        XCTAssertEqual(APIError.displayableServerText(commentLimit, language: "ja"), commentLimit)
        XCTAssertNil(APIError.displayableServerText("", language: "ja"))
    }

    func testContainsJapanese() {
        XCTAssertTrue(APIError.containsJapanese("ひらがな"))
        XCTAssertTrue(APIError.containsJapanese("カタカナ"))
        XCTAssertTrue(APIError.containsJapanese("漢字"))
        XCTAssertTrue(APIError.containsJapanese("Error（500）"))
        XCTAssertFalse(APIError.containsJapanese("Server error (500) — try again"))
        XCTAssertFalse(APIError.containsJapanese("You\u{2019}ve reached the limit"))
    }

    /// 日本語の固定文をそのまま `APIError.server` の本文に入れない（英語の画面に出る）。
    /// `L("日本語", "English")` で作る（`ProfileService.uploadProfileImage` がそうなっていなかった）
    func testNoFixedJapaneseServerMessagesInSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return XCTFail("Sources を読めない")
        }
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `message: "…"`（`L(` を通さない文字の本文）で、日本語を含むもの
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), let range = trimmed.range(of: "message: \"") else { continue }
                let rest = String(trimmed[range.upperBound...])
                let literal = rest.split(separator: "\"", maxSplits: 1).first.map(String.init) ?? ""
                if APIError.containsJapanese(literal) {
                    offenders.append("\(url.lastPathComponent): \(trimmed)")
                }
            }
        }
        XCTAssertEqual(offenders, [], "日本語の固定文を本文に入れている")
    }
}
