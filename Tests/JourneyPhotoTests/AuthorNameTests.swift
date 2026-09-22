import XCTest
@testable import JourneyPhoto

/// 投稿者の名前。**同じ写真に2つの名前を出さない**（run 55 の実機の絵）。
final class AuthorNameTests: XCTestCase {

    private func profile(_ json: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
    }

    /// 🔴 run 55 の形そのもの。プロフィールに名前が無く、写真には
    /// 「luzhj」が添えてある——**ホームと詳細で違う名前が出ていた**
    func testFallsBackToThePhotoName() throws {
        let empty = try profile("{\"userId\":\"u1\"}")
        XCTAssertEqual(AuthorName.shown(profile: empty, photoDisplayName: "luzhj"), "luzhj")
        XCTAssertEqual(AuthorName.shown(profile: nil, photoDisplayName: "luzhj"), "luzhj")
    }

    /// プロフィールの名前が本物なら、そちらが勝つ（新しい方）
    func testProfileNameWins() throws {
        let named = try profile("{\"userId\":\"u1\",\"displayName\":\"新しい名前\"}")
        XCTAssertEqual(AuthorName.shown(profile: named, photoDisplayName: "古い名前"), "新しい名前")
    }

    /// displayName が無ければ username
    func testUsernameIsARealName() throws {
        let u = try profile("{\"userId\":\"u1\",\"username\":\"luzhj\"}")
        XCTAssertEqual(AuthorName.real(u), "luzhj")
    }

    /// **空白だけの値は「無い」**（サーバーに空文字の行が実在する）
    func testBlankNamesAreTreatedAsMissing() throws {
        let blank = try profile("{\"userId\":\"u1\",\"displayName\":\"  \",\"username\":\"\"}")
        XCTAssertNil(AuthorName.real(blank))
        XCTAssertEqual(AuthorName.shown(profile: blank, photoDisplayName: " "), Labels.Common.unnamedUser)
    }

    /// **代わりの言葉は1つだけ**（「投稿者」と「ユーザー」が混ざっていた）
    func testOnlyOnePlaceholder() {
        XCTAssertEqual(AuthorName.shown(profile: nil, photoDisplayName: nil), Labels.Common.unnamedUser)
    }

    /// `UserProfile.name` は代わりの言葉を返す。**`real` は返さない**
    /// ——ここを混ぜたせいで、写真の名前まで降りてこなかった
    func testRealDoesNotReturnThePlaceholder() throws {
        let empty = try profile("{\"userId\":\"u1\"}")
        XCTAssertEqual(empty.name, Labels.Common.unnamedUser)
        XCTAssertNil(AuthorName.real(empty))
    }
}
