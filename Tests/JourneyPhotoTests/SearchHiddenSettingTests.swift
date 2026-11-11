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

    /// 🔴 プロフィールが後から届いても、オンの人はオンに出る（nil → true。確かめ役 2026-11-11）
    func testLateProfileTurnsToggleOn() {
        // init の時はプロフィールが無い＝ false で始まる（`profile?.hidesFromSearch ?? false`）
        var shown = false
        // 届いたら値に合わせる
        shown = SearchHiddenSettingRow.synced(current: shown, profileValue: true, isSaving: false)
        XCTAssertTrue(shown)
        // Web で切り替えた分（true → false）も
        XCTAssertFalse(SearchHiddenSettingRow.synced(current: true, profileValue: false, isSaving: false))
        // 読めなくなった（nil）・送っている最中は今の値のまま
        XCTAssertTrue(SearchHiddenSettingRow.synced(current: true, profileValue: nil, isSaving: false))
        XCTAssertTrue(SearchHiddenSettingRow.synced(current: true, profileValue: false, isSaving: true))
    }

    /// 合わせる onChange は、いつも在る外側に付き、現れた時点でも走る（行の側に付けると nil → 値を受けられない）
    func testSyncIsAttachedOutsideTheConditionalRow() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repo.appendingPathComponent("Sources/JourneyPhoto/Features/Settings/SearchHiddenSettingRow.swift"),
                                encoding: .utf8)
        let body = try XCTUnwrap(source.range(of: "var body: some View {"))
        let rest = String(source[body.upperBound...])
        let group = try XCTUnwrap(rest.range(of: "Group {"))
        let conditional = try XCTUnwrap(rest.range(of: "if profile != nil {"))
        let sync = try XCTUnwrap(rest.range(of: ".onChange(of: profile?.hidesFromSearch, initial: true)"))
        XCTAssertLessThan(group.lowerBound, conditional.lowerBound)
        // Group を閉じた後（インデント8の `}`）に付いている
        let groupClose = try XCTUnwrap(rest.range(of: "\n        }\n        // 読み直した"))
        XCTAssertLessThan(groupClose.lowerBound, sync.lowerBound)
    }
}
