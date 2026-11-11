import XCTest
@testable import JourneyPhoto

/// 設定の「検索エンジンにプロフィールを表示しない」（2026-11-11 owner 承認・#526）。
/// 既定はオフ（＝表示する）。入切はプロフィールの `searchHidden` を真偽だけで送る。
final class SearchHiddenSettingTests: XCTestCase {

    func testProfileReadsSearchHiddenWithDefaultOff() throws {
        let on = try JSONDecoder.api.decode(UserProfile.self, from: Data(#"{"userId":"u","searchHidden":true}"#.utf8))
        XCTAssertTrue(on.hidesFromSearch)
        let off = try JSONDecoder.api.decode(UserProfile.self, from: Data(#"{"userId":"u","searchHidden":false}"#.utf8))
        XCTAssertFalse(off.hidesFromSearch)
        // 古いサーバー（無い）は表示する（サーバーの既定）
        let none = try JSONDecoder.api.decode(UserProfile.self, from: Data(#"{"userId":"u"}"#.utf8))
        XCTAssertFalse(none.hidesFromSearch)
        // 形の崩れた値でプロフィール全体を落とさない
        let odd = try JSONDecoder.api.decode(UserProfile.self, from: Data(#"{"userId":"u","searchHidden":"yes"}"#.utf8))
        XCTAssertFalse(odd.hidesFromSearch)
    }

    /// 部分更新は `searchHidden` だけを真偽で送る（文字の "true" はサーバーが 400 で断る）
    func testPatchSendsOnlyTheFlag() throws {
        let data = try JSONEncoder().encode(ProfilePatch(searchHidden: true))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"searchHidden":true}"#)
        let off = try JSONEncoder().encode(ProfilePatch(searchHidden: false))
        XCTAssertEqual(String(data: off, encoding: .utf8), #"{"searchHidden":false}"#)
    }

    /// 押す前に何が起きるか分かる言葉（owner 2026-11-11）。「撮りどき」「捨てる」は使わない
    func testWording() {
        XCTAssertEqual(SearchHiddenSettingText.title, "検索エンジンにプロフィールを表示しない")
        XCTAssertTrue(SearchHiddenSettingText.detail.contains("写真ごとの公開の設定は変わりません"))
    }

    /// 行は設定の「公開範囲とプライバシー」に並ぶ（並びの表）
    func testRowIsInPrivacyPart() {
        XCTAssertEqual(SettingsOutline.Part.privacy.items.last, "settings.searchHidden")
    }
}
