import XCTest
@testable import JourneyPhoto

/// プロフィールのBGM（モック2-4）。
final class ProfileBgmTests: XCTestCase {

    private func profile(_ json: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
    }

    /// サーバーは前から `songs` を返していた。**復号すること**
    /// （していなかったので ⛔ に見えていた）
    func testSongsAreDecoded() throws {
        let p = try profile("""
        {"userId":"u1","songs":[{"title":"A New Horizon","artist":"Forest Mood",
        "previewUrl":"https://audio.example/a.m4a"}]}
        """)
        XCTAssertEqual(p.bgm?.title, "A New Horizon")
        XCTAssertEqual(p.bgm?.artist, "Forest Mood")
    }

    /// **鳴らせない曲はカードに出さない。** 題だけの行が来ても、
    /// 押しても何も起きない札を置かない
    func testUnplayableSongIsNotShown() throws {
        let p = try profile("""
        {"userId":"u1","songs":[{"title":"","previewUrl":"https://audio.example/a.m4a"},
        {"title":"鳴る曲","previewUrl":"https://audio.example/b.m4a"}]}
        """)
        XCTAssertEqual(p.bgm?.title, "鳴る曲")
    }

    func testNoSongsMeansNoCard() throws {
        XCTAssertNil(try profile(#"{"userId":"u1"}"#).bgm)
        XCTAssertNil(try profile(#"{"userId":"u1","songs":[]}"#).bgm)
    }

    /// 🔴 **Web の2曲目以降を消さない。** アプリは先頭しか触らないが、
    /// 送るのは一覧ごとなので、持っているぶんを全部入れないと
    /// **保存した瞬間に残りが消える**
    func testPatchCarriesTheWholePlaylist() {
        let kept = Photo.Song(title: "B", artist: nil, artwork: nil,
                              previewUrl: "https://audio.example/b.m4a", trackUrl: nil)
        let picked = Photo.Song(title: "A", artist: nil, artwork: nil,
                                previewUrl: "https://audio.example/a.m4a", trackUrl: nil)
        var patch = ProfilePatch()
        patch.songs = [picked, kept]
        XCTAssertEqual(patch.songs?.count, 2)
        XCTAssertEqual(patch.songs?.first?.title, "A")
    }

    /// **`nil` は「触らない」。** ログイン直後の名前だけの保存で
    /// BGM が消えないこと
    func testNilSongsMeansUntouched() {
        var patch = ProfilePatch()
        patch.displayName = "ゆき"
        XCTAssertNil(patch.songs)
    }
}

/// プロフィールの項目（モック2-1 / 2-9）。
final class ProfileFieldsTests: XCTestCase {

    private func profile(_ json: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
    }

    /// 居住地を復号する（モック2-1 の「📍Tokyo, Japan」）
    func testHomeLocationIsDecoded() throws {
        let p = try profile(#"{"userId":"u1","homeLocation":"Tokyo, Japan"}"#)
        XCTAssertEqual(p.homeLocation, "Tokyo, Japan")
    }

    /// 🔴 **写真の撮影地とは別の項目。** 同じ名前にすると、住んでいる場所が
    /// `/location/*` と地図に混ざる
    func testHomeLocationIsNotThePhotoLocationField() throws {
        let p = try profile(#"{"userId":"u1","location":"サントリーニ島"}"#)
        XCTAssertNil(p.homeLocation, "写真の location を居住地として読んでいる")
    }

    /// **`nil` は「触らない」。** 名前だけの保存で居住地が消えない
    func testNilHomeLocationMeansUntouched() {
        var patch = ProfilePatch()
        patch.displayName = "ゆき"
        XCTAssertNil(patch.homeLocation)
    }

    /// 空文字は「消す」（消す手段を残す）
    func testEmptyStringClearsIt() {
        var patch = ProfilePatch()
        patch.homeLocation = ""
        XCTAssertEqual(patch.homeLocation, "")
    }
}
