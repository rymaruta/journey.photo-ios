import XCTest
@testable import JourneyPhoto

/// ハイライトの保存・削除に失敗したときの一文（`HighlightService.failureMessage`）。
///
/// **サーバーの断り文を捨てない**（バグ探し 2026-09-27 #15）。以前はどの失敗でも
/// 「保存できませんでした。もう一度お試しください。」で、20個の上限に当たった人が
/// 何度押しても同じ文だった。
final class HighlightFailureTests: XCTestCase {

    private let fallback = "保存できませんでした"

    /// 上限（403）は本文を出す。汎用の「権限がありません」にしない
    func testLimitRefusalShowsTheServerText() {
        let error = APIError.server(status: 403, message: "ハイライトは20個までです。使わないものを消してください")
        XCTAssertEqual(HighlightService.failureMessage(for: error, fallback: fallback),
                       "ハイライトは20個までです。使わないものを消してください")
    }

    /// 400・404 も本文を出す（直し方が書いてある）
    func testValidationRefusalsShowTheServerText() {
        for (status, text) in [(400, "表紙は選んだストーリーの中から選んでください"),
                               (404, "ハイライトが見つかりません")] {
            XCTAssertEqual(HighlightService.failureMessage(for: APIError.server(status: status, message: text),
                                                           fallback: fallback), text)
        }
    }

    /// 認証切れ・圏外は `APIError` の文（サーバーの「認証が必要です」を出さない）
    func testAuthAndNetworkUseTheSharedText() {
        XCTAssertEqual(HighlightService.failureMessage(for: APIError.server(status: 401, message: "認証が必要です"),
                                                       fallback: fallback),
                       APIError.server(status: 401, message: "").errorDescription)
        XCTAssertEqual(HighlightService.failureMessage(for: APIError.unreachable, fallback: fallback),
                       APIError.unreachable.errorDescription)
    }

    /// 本文の無い 403（ゲートウェイが断った回など）は汎用の文に任せる
    func testEmptyBodyFallsBackToTheSharedText() {
        let error = APIError.server(status: 403, message: "")
        XCTAssertEqual(HighlightService.failureMessage(for: error, fallback: fallback), error.errorDescription)
    }

    /// `APIError` でない失敗は呼び手の文
    func testUnknownErrorUsesTheFallback() {
        struct Other: Error {}
        XCTAssertEqual(HighlightService.failureMessage(for: Other(), fallback: fallback), fallback)
    }
}
