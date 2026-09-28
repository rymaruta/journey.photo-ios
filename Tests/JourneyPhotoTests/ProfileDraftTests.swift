import XCTest
@testable import JourneyPhoto

/// プロフィールの保存で送るもの（`ProfileDraft.patch`）。
/// Web の `app/user/profile/__tests__/page.partialSave.test.tsx` と同じ場面を見る。
final class ProfileDraftTests: XCTestCase {

    private let songA = Photo.Song(title: "A", artist: nil, artwork: nil,
                                   previewUrl: "https://audio.example/a.m4a", trackUrl: nil)
    private let songB = Photo.Song(title: "B", artist: "x", artwork: nil,
                                   previewUrl: "https://audio.example/b.m4a", trackUrl: nil)

    private var loaded: ProfileDraft {
        ProfileDraft(username: "yuki", displayName: "ゆき", bio: "こんにちは",
                     website: "https://example.com", instagram: "yuki_ig",
                     statusText: "旅の途中", homeLocation: "東京", themeColor: "#c9a86a",
                     songs: [songA, songB])
    }

    /// 実際に送る JSON のキー（`nil` の項目は載らない——載ると「触った」になる）
    private func keys(_ patch: ProfilePatch?) throws -> Set<String> {
        let patch = try XCTUnwrap(patch)
        let data = try JSONEncoder().encode(patch)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(json.keys)
    }

    /// 何も変えずに保存したら、そもそも送らない
    func testNothingChangedSendsNothing() {
        XCTAssertNil(ProfileDraft.patch(from: loaded, to: loaded))
    }

    /// 🔴 **自己紹介だけ直したら、送るのは bio だけ。** 表示名・ユーザー名・曲を
    /// 開いた時点の値で送り返すと、別の端末で直した分を巻き戻す
    func testOnlyTheEditedFieldIsSent() throws {
        var edited = loaded
        edited.bio = "旅の記録"
        let patch = ProfileDraft.patch(from: loaded, to: edited)
        XCTAssertEqual(try keys(patch), ["bio"])
        XCTAssertEqual(patch?.bio, "旅の記録")
        XCTAssertNil(patch?.displayName, "触っていない表示名を送っている（Web で直した名前が巻き戻る）")
        XCTAssertNil(patch?.username, "触っていないユーザー名を送っている（古い名前の人は毎回 400 になる）")
        XCTAssertNil(patch?.songs, "触っていない曲を送っている（別の端末で足した曲が消える）")
    }

    /// 読み込んだ値と同じ文字を打ち直しただけ・前後に空白を足しただけなら送らない
    /// （サーバーは trim して保存する）
    func testTrimmedEqualCountsAsUnchanged() {
        var edited = loaded
        edited.displayName = "  ゆき "
        edited.bio = "こんにちは\n"
        edited.homeLocation = " 東京"
        XCTAssertNil(ProfileDraft.patch(from: loaded, to: edited))
    }

    /// ユーザー名はサーバーと同じ正規化で比べる（@・大文字・空白は「変えた」にしない）
    func testUsernameIsComparedNormalized() {
        var edited = loaded
        edited.username = " @Yuki "
        XCTAssertNil(ProfileDraft.patch(from: loaded, to: edited))
    }

    /// ユーザー名を変えたときは送る。形はサーバーと同じに整えて送る（Web と同じ）
    func testChangedUsernameIsSentNormalized() throws {
        var edited = loaded
        edited.username = "@Haru"
        let patch = ProfileDraft.patch(from: loaded, to: edited)
        XCTAssertEqual(try keys(patch), ["username"])
        XCTAssertEqual(patch?.username, "haru")
    }

    /// 保存済みの欄を空にした回は、その欄を空文字で送る（＝消せる）
    func testClearedFieldIsSentAsEmpty() throws {
        var edited = loaded
        edited.website = ""
        let patch = ProfileDraft.patch(from: loaded, to: edited)
        XCTAssertEqual(try keys(patch), ["website"])
        XCTAssertEqual(patch?.website, "")
    }

    /// 曲を変えたら一覧ごと送る（2曲目以降を残したまま）
    func testChangedSongsAreSentWhole() throws {
        var edited = loaded
        edited.songs = [songB, songA]
        let patch = ProfileDraft.patch(from: loaded, to: edited)
        XCTAssertEqual(try keys(patch), ["songs"])
        XCTAssertEqual(patch?.songs, [songB, songA])
    }

    /// 曲を持たない人が触らなければ、曲を送らない（空の一覧も「触った」にしない）
    func testUntouchedEmptySongsAreNotSent() throws {
        let profile = try JSONDecoder.api.decode(UserProfile.self, from: Data(#"{"userId":"u1","bio":"a"}"#.utf8))
        let original = ProfileDraft(profile: profile)
        var edited = original
        edited.bio = "b"
        XCTAssertEqual(try keys(ProfileDraft.patch(from: original, to: edited)), ["bio"])
    }

    /// 複数の欄を変えたら、変えた欄だけがそろって載る
    func testSeveralEditsAreAllSent() throws {
        var edited = loaded
        edited.statusText = "帰国しました"
        edited.themeColor = "#112233"
        edited.instagram = ""
        XCTAssertEqual(try keys(ProfileDraft.patch(from: loaded, to: edited)),
                       ["statusText", "themeColor", "instagram"])
    }
}
