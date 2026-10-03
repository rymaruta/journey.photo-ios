import XCTest
@testable import JourneyPhoto

/// 直した欄があるまま閉じる・戻るのを確かめる（バグ探し 2026-10-03）。
/// 写真の編集（`EditPhotoChanges`）・プロフィールの編集（`ProfileDraft.leave`）・
/// ハイライトの編集（`HighlightService.leave`）が、ストーリー作成と同じ `UnsavedLeave` を使う。
final class UnsavedEditCloseTests: XCTestCase {

    private func photo(_ json: String) -> Photo {
        try! JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    private var sample: Photo {
        photo(#"""
        {"id":"p1","src":"https://x/p1.jpg","title":"朝の海","description":"静かな朝",
         "location":"金沢","tags":["海","朝"],"category":"風景","date":"2026-05-01",
         "published":true,"audience":"followers"}
        """#)
    }

    // MARK: - 写真の編集

    /// 開いたままの欄は「変更なし」——払っても閉じる・「閉じる」で確かめない
    func testEditPhotoUntouchedClosesAtOnce() {
        let p = sample
        let fields = EditPhotoChanges.Fields(opening: p)
        let opened = EditPhotoChanges.openedAudience(p)
        XCTAssertFalse(EditPhotoChanges.hasChanges(photo: p, openedAudience: opened, fields: fields))
        XCTAssertEqual(EditPhotoChanges.leave(photo: p, openedAudience: opened, fields: fields, isSaving: false), .now)
    }

    /// 🔴 **題・撮影地・タグ・公開を直したら確かめる。** 以前は保存の最中しか止めず、
    /// 直したあと下へ払う・「閉じる」で黙って消えた
    func testEditPhotoChangesAskBeforeClosing() {
        let p = sample
        let opened = EditPhotoChanges.openedAudience(p)
        func leave(_ edit: (inout EditPhotoChanges.Fields) -> Void) -> UnsavedLeave {
            var f = EditPhotoChanges.Fields(opening: p)
            edit(&f)
            return EditPhotoChanges.leave(photo: p, openedAudience: opened, fields: f, isSaving: false)
        }
        XCTAssertEqual(leave { $0.title = "夕方の海" }, .confirm, "題を直しても確かめない")
        XCTAssertEqual(leave { $0.caption = "" }, .confirm)
        XCTAssertEqual(leave { $0.location = "" }, .confirm, "撮影地を消しても確かめない")
        XCTAssertEqual(leave { $0.pickedCoords = Photo.Coords(lat: 36.5, lng: 136.6) }, .confirm)
        XCTAssertEqual(leave { $0.tagsText = "海" }, .confirm)
        XCTAssertEqual(leave { $0.category = "食" }, .confirm)
        XCTAssertEqual(leave { $0.date = "2026-05-02" }, .confirm)
        XCTAssertEqual(leave { $0.published = false }, .confirm)
        XCTAssertEqual(leave { $0.audience = .everyone }, .confirm)
    }

    /// 送る差分が出ない打ち直し（タグの区切りの空白・分類の前後の空白）は変更にしない
    /// ——保存しても何も送らないのに確かめると、閉じるたびに聞かれる
    func testEditPhotoNoOpRetypesDoNotAsk() {
        let p = sample
        var f = EditPhotoChanges.Fields(opening: p)
        f.tagsText = "海,朝"
        f.category = " 風景 "
        XCTAssertEqual(EditPhotoChanges.leave(photo: p, openedAudience: EditPhotoChanges.openedAudience(p),
                                              fields: f, isSaving: false), .now)
    }

    /// 保存・差し替えの最中は閉じさせない（直していなくても）
    func testEditPhotoWaitsWhileSaving() {
        let p = sample
        XCTAssertEqual(EditPhotoChanges.leave(photo: p, openedAudience: EditPhotoChanges.openedAudience(p),
                                              fields: EditPhotoChanges.Fields(opening: p), isSaving: true), .wait)
    }

    /// 知らない公開範囲の写真は、範囲を触れない（送らない）ので変更にもならない
    func testEditPhotoUnknownAudienceIsNotAChange() {
        let p = photo(#"{"id":"p2","src":"https://x/p2.jpg","audience":"mystery"}"#)
        XCTAssertNil(EditPhotoChanges.openedAudience(p))
        let f = EditPhotoChanges.Fields(opening: p)
        XCTAssertFalse(EditPhotoChanges.hasChanges(photo: p, openedAudience: nil, fields: f))
    }

    // MARK: - プロフィールの編集

    /// 🔴 **自己紹介などを直したら、戻るで確かめる。** 以前は戻るで黙って消えた
    func testProfileEditAsksBeforeGoingBack() {
        let original = ProfileDraft(username: "taro", displayName: "太郎", bio: "旅の写真")
        var edited = original
        XCTAssertEqual(ProfileDraft.leave(original: original, edited: edited, isBusy: false), .now)
        edited.bio = "旅と海の写真"
        XCTAssertEqual(ProfileDraft.leave(original: original, edited: edited, isBusy: false), .confirm)
        // 保存・画像の送信の最中は戻らせない（以前の戻るを隠す門と同じ）
        XCTAssertEqual(ProfileDraft.leave(original: original, edited: original, isBusy: true), .wait)
        // 末尾に空白を打っただけは変更にしない（保存でも送らない）
        var spaced = original
        spaced.bio = "旅の写真 "
        XCTAssertEqual(ProfileDraft.leave(original: original, edited: spaced, isBusy: false), .now)
    }

    /// 読めていない間（`original` が nil）は、欄が空でも確かめずに戻す（保存もできない）
    func testProfileNotLoadedLeavesAtOnce() {
        XCTAssertEqual(ProfileDraft.leave(original: nil, edited: ProfileDraft(bio: "打ちかけ"), isBusy: false), .now)
    }

    // MARK: - ハイライトの編集

    /// 🔴 **選んだストーリー・打った名前があれば「キャンセル」で確かめる。**
    func testHighlightEditorAsksBeforeCancel() {
        let empty = HighlightService.Draft(title: "", picked: [], coverId: nil)
        XCTAssertEqual(HighlightService.leave(opened: empty, now: empty, saving: false), .now)
        XCTAssertEqual(HighlightService.leave(opened: empty,
                                              now: .init(title: "", picked: ["s1"], coverId: "s1"),
                                              saving: false), .confirm, "選んだストーリーを黙って捨てる")
        XCTAssertEqual(HighlightService.leave(opened: empty, now: .init(title: "ギリシャ", picked: [], coverId: nil),
                                              saving: false), .confirm)
        // 直すとき: 並びを入れ替えた・表紙を替えたのも変更
        let opened = HighlightService.Draft(title: "旅", picked: ["a", "b"], coverId: "a")
        XCTAssertEqual(HighlightService.leave(opened: opened, now: .init(title: "旅", picked: ["b", "a"], coverId: "a"),
                                              saving: false), .confirm)
        XCTAssertEqual(HighlightService.leave(opened: opened, now: .init(title: "旅", picked: ["a", "b"], coverId: "b"),
                                              saving: false), .confirm)
        // 名前の前後の空白だけは変更にしない（送るときに trim する）
        XCTAssertEqual(HighlightService.leave(opened: opened, now: .init(title: " 旅 ", picked: ["a", "b"], coverId: "a"),
                                              saving: false), .now)
        // 保存・削除の最中は閉じさせない
        XCTAssertEqual(HighlightService.leave(opened: opened, now: opened, saving: true), .wait)
    }
}
