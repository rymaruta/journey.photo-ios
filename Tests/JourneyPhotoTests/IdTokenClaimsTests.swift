import XCTest
@testable import JourneyPhoto

/// メニューの「管理」の出し分け（ID トークンの `cognito:groups`・Web と同じ判定）
final class IdTokenClaimsTests: XCTestCase {

    /// 本物の JWT と同じく base64url・埋め草なしで組む
    private func jwt(_ payload: String) -> String {
        let body = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(body).sig"
    }

    func testReadsAdminGroup() {
        XCTAssertTrue(IdTokenClaims.isAdmin(jwt: jwt(#"{"sub":"a","cognito:groups":["admin"]}"#)))
        XCTAssertEqual(IdTokenClaims.groups(fromJWT: jwt(#"{"cognito:groups":["user","admin"]}"#)), ["user", "admin"])
    }

    /// 一般の人・群の無い人・壊れたトークンは**管理を出さない**側へ倒す
    func testNonAdminAndBrokenTokensAreNotAdmin() {
        XCTAssertFalse(IdTokenClaims.isAdmin(jwt: jwt(#"{"cognito:groups":["user"]}"#)))
        XCTAssertFalse(IdTokenClaims.isAdmin(jwt: jwt(#"{"sub":"a"}"#)))
        XCTAssertFalse(IdTokenClaims.isAdmin(jwt: "not-a-jwt"))
        XCTAssertFalse(IdTokenClaims.isAdmin(jwt: "a.!!!.c"))
    }

    /// base64url の「-」「_」と、埋め草の無い長さを読める（読み違えると管理者に出ない）
    func testDecodesBase64URLWithoutPadding() {
        // 「?」「>」を含めて、base64 に + / が出る中身にする
        let token = jwt(#"{"x":"???>>>","cognito:groups":["admin"]}"#)
        XCTAssertTrue(token.contains("-") || token.contains("_"), "試験の前提（base64url の文字）が崩れた")
        XCTAssertTrue(IdTokenClaims.isAdmin(jwt: token))
    }
}
