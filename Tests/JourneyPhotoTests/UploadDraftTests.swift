import XCTest
@testable import JourneyPhoto

final class UploadDraftTests: XCTestCase {

    /// **座標は端末側でも丸めてから送る。** サーバーも丸めるが、
    /// 丸める前の値を電波に乗せる理由が無い。
    func testCoordsAreRoundedToAboutOneKilometer() throws {
        var draft = PhotoDraft()
        draft.location = "高屋神社"
        draft.coords = Photo.Coords(lat: 34.123456, lng: 133.987654)
        let body = draft.saveBody(key: "uploads/u/1.jpg", publicUrl: "https://x/1.jpg")
        XCTAssertEqual(body.coords?.lat, 34.12)
        XCTAssertEqual(body.coords?.lng, 133.99)
    }

    /// **撮影地を消したら座標も送らない。** 撮影地は写真の位置から自動で入るので、
    /// 自宅の地名を消しても座標（約1km）が送られて地図に出ていた
    func testCoordsAreNotSentWithoutLocation() throws {
        var draft = PhotoDraft()
        draft.coords = Photo.Coords(lat: 34.123456, lng: 133.987654)
        draft.location = ""
        XCTAssertNil(draft.saveBody(key: "k", publicUrl: "u").coords)
        draft.location = "高屋神社"
        XCTAssertNotNil(draft.saveBody(key: "k", publicUrl: "u").coords)
    }

    /// **押し直しでも束の印を変えない。** 送るたびに作り直すと、5枚のうち2枚が
    /// 失敗して押し直したとき 3枚と2枚の2つの束に割れ、1枚だけ残ると印が消えていた
    func testGroupIdIsKeptAcrossRetries() {
        var made = 0
        let make = { () -> String in made += 1; return "g\(made)" }
        let first = UploadViewModel.groupIdForSubmit(current: nil, grouping: true, count: 5, make: make)
        XCTAssertEqual(first, "g1")
        // 2枚失敗して押し直す／1枚だけ残って押し直す
        XCTAssertEqual(UploadViewModel.groupIdForSubmit(current: first, grouping: true, count: 2, make: make), "g1")
        XCTAssertEqual(UploadViewModel.groupIdForSubmit(current: first, grouping: true, count: 1, make: make), "g1")
        XCTAssertEqual(made, 1)
        // 最初から1枚なら印は付けない。まとめない設定なら付けない
        XCTAssertNil(UploadViewModel.groupIdForSubmit(current: nil, grouping: true, count: 1, make: make))
        XCTAssertNil(UploadViewModel.groupIdForSubmit(current: "g1", grouping: false, count: 5, make: make))
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
            InviteLink.token(from: "https://journey-photo.com/j?t=abc123"),
            "abc123"
        )
    }

    func testAcceptsBareToken() {
        XCTAssertEqual(InviteLink.token(from: "  abc123 "), "abc123")
    }

    /// トークンを持たない URL は「読み取れなかった」にする——
    /// URL 全体をトークンとして送ると、サーバーに無意味な問い合わせが飛ぶ。
    func testRejectsURLWithoutToken() {
        XCTAssertEqual(InviteLink.token(from: "https://journey-photo.com/"), "")
    }
}
