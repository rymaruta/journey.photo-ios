import XCTest
@testable import JourneyPhoto

final class UploadDraftTests: XCTestCase {

    /// **座標は端末側でも丸めてから送る。** サーバーも丸めるが、
    /// 丸める前の値を電波に乗せる理由が無い。
    func testCoordsAreRoundedToAboutOneKilometer() throws {
        var draft = PhotoDraft()
        draft.coords = Photo.Coords(lat: 34.123456, lng: 133.987654)
        let body = draft.saveBody(key: "uploads/u/1.jpg", publicUrl: "https://x/1.jpg")
        XCTAssertEqual(body.coords?.lat, 34.12)
        XCTAssertEqual(body.coords?.lng, 133.99)
    }

    /// 空の項目は送らない（api-user は「未指定＝触らない」と読む）。
    func testEmptyFieldsAreOmitted() throws {
        let body = PhotoDraft().saveBody(key: "k", publicUrl: "u")
        XCTAssertNil(body.title)
        XCTAssertNil(body.location)
        XCTAssertNil(body.tags)
    }

    /// 区切りは読点・カンマ・空白のどれでもよい。重複は落とす
    /// （同じタグが2つ付くと絞り込みの件数がずれる）。
    func testTagParsing() {
        XCTAssertEqual(TagInput.parse("雲海, sunrise 雲海"), ["雲海", "sunrise"])
        XCTAssertEqual(TagInput.parse("  "), [])
        XCTAssertEqual(TagInput.parse("a、b"), ["a", "b"])
    }
}

final class InviteTokenTests: XCTestCase {

    /// **リンクをそのまま貼れること。** 受け取った人に `?t=` の後ろだけを
    /// 取り出させない（URL を貼って弾かれるのがいちばん多い失敗）。
    func testTakesTokenFromInviteURL() {
        XCTAssertEqual(
            AlbumsViewModel.token(from: "https://journey-photo.com/j?t=abc123"),
            "abc123"
        )
    }

    func testAcceptsBareToken() {
        XCTAssertEqual(AlbumsViewModel.token(from: "  abc123 "), "abc123")
    }

    /// トークンを持たない URL は「読み取れなかった」にする——
    /// URL 全体をトークンとして送ると、サーバーに無意味な問い合わせが飛ぶ。
    func testRejectsURLWithoutToken() {
        XCTAssertEqual(AlbumsViewModel.token(from: "https://journey-photo.com/"), "")
    }
}
