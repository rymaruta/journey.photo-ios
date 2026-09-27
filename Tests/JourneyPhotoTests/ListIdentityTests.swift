import XCTest
@testable import JourneyPhoto

/// 人の一覧の2行目「@ユーザー名」と「名前で探す」（板 34・39・45）。
final class ListIdentityTests: XCTestCase {

    private func decode(_ json: String) throws -> FollowUser {
        try JSONDecoder().decode(FollowUser.self, from: Data(json.utf8))
    }

    /// サーバーが各行に付ける `username` を読む（2026-09-26 から）
    func testDecodesUsernameFromTheListResponse() throws {
        let user = try decode(#"{"id":"u1","name":"旅人B","username":"tabibito_b"}"#)
        XCTAssertEqual(user.handle, "@tabibito_b")
    }

    /// 付かない行（ユーザー名を決めていない人）は2行目を出さない
    func testNoHandleWithoutUsername() throws {
        XCTAssertNil(try decode(#"{"id":"u1","name":"旅人B"}"#).handle)
        XCTAssertNil(try decode(#"{"id":"u1","username":"  "}"#).handle)
    }

    /// 退会した人は、万一ユーザー名が付いていても出さない
    func testDeletedUserHasNoHandle() throws {
        let user = try decode(#"{"id":"u1","name":"退会したユーザー","deleted":true,"username":"old"}"#)
        XCTAssertNil(user.handle)
    }

    private let people = [
        FollowUser(id: "a", name: "山田 花子", deleted: nil, username: "hanako"),
        FollowUser(id: "b", name: "Taro", deleted: nil, username: "tabi_taro"),
        FollowUser(id: "c", name: nil, deleted: nil, username: nil),
        FollowUser(id: "d", name: "退会したユーザー", deleted: true, username: nil),
    ]

    /// 表示名でも @ユーザー名でも当たる
    func testFiltersByNameOrUsername() {
        XCTAssertEqual(ListIdentity.filter(people, query: "花子").map(\.id), ["a"])
        XCTAssertEqual(ListIdentity.filter(people, query: "tabi").map(\.id), ["b"])
    }

    /// 頭の「@」・大文字小文字・全角は区別しない
    func testIgnoresAtSignCaseAndWidth() {
        XCTAssertEqual(ListIdentity.filter(people, query: "@HANAKO").map(\.id), ["a"])
        XCTAssertEqual(ListIdentity.filter(people, query: "ｔａｒｏ").map(\.id), ["b"])
    }

    /// 空の入力は絞らない（並びもそのまま）
    func testEmptyQueryKeepsEveryone() {
        XCTAssertEqual(ListIdentity.filter(people, query: "  ").map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(ListIdentity.filter(people, query: "@").map(\.id), ["a", "b", "c", "d"])
    }

    /// 名前の無い人の代わりの言葉では当たらない（全員が当たってしまう）
    func testFallbackNameIsNotSearched() {
        XCTAssertFalse(ListIdentity.filter(people, query: Labels.Common.unnamedUser).map(\.id).contains("c"))
    }
}
