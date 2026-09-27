import XCTest
@testable import JourneyPhoto
import ImageIO

/// 投稿・編集で送る値（D6・B11・D5・D8）。
final class UploadMetaFixTests: XCTestCase {

    // MARK: - D6 撮影日時は Web が読む形で送る

    func testExifDateTimeIsSentInStoredForm() {
        XCTAssertEqual(ImagePreparer.storedDateTime("2026:09:13 08:21:05"), "2026-09-13T08:21:05")
        // 既に保存の形ならそのまま
        XCTAssertEqual(ImagePreparer.storedDateTime("2026-09-13T08:21:05"), "2026-09-13T08:21:05")
        XCTAssertNil(ImagePreparer.storedDateTime("0000:00:00 00:00:00"))
        XCTAssertNil(ImagePreparer.storedDateTime("   "))
        XCTAssertNil(ImagePreparer.storedDateTime(nil))
    }

    func testReadExifConvertsDateTimeOriginal() {
        let props: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:13 08:21:05"] as [CFString: Any],
        ]
        XCTAssertEqual(ImagePreparer.readExif(from: props).dateTimeOriginal, "2026-09-13T08:21:05")
    }

    /// 読む側（一覧の並び・メタ行）は送った形を読める
    func testReadersUnderstandTheSentForm() {
        XCTAssertEqual(PhotoMetaLine.stamp(date: nil, exifDateTime: "2026-09-13T08:21:05"),
                       PhotoMetaLine.stamp(date: nil, exifDateTime: "2026:09:13 08:21:05"))
    }

    // MARK: - B11 GPS 0,0 は座標なし

    private func gps(_ lat: Double, _ lng: Double) -> [CFString: Any] {
        [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: lat, kCGImagePropertyGPSLongitude: lng,
            kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitudeRef: "E",
        ] as [CFString: Any]]
    }

    func testNullIslandIsNoCoords() {
        XCTAssertNil(ImagePreparer.readCoords(from: gps(0, 0)))
        XCTAssertEqual(ImagePreparer.readCoords(from: gps(35.6812, 139.7671)),
                       Photo.Coords(lat: 35.68, lng: 139.77))
        // 片方だけ 0 は実在する（赤道・本初子午線）
        XCTAssertNotNil(ImagePreparer.readCoords(from: gps(0, 139.77)))
    }

    // MARK: - D5 公開・公開範囲は変えたときだけ
    //
    // 判定は `EditVisibilityRules` の1本（main 側の `EditVisibility.toSend` と同じ役目
    // だったので、併合で寄せた）。`openedAudience` は「知らない値なら nil」＝旧 `audienceKnown: false`

    func testUntouchedVisibilityIsNotSent() {
        let r = EditVisibilityRules.patch(openedPublished: true, openedAudience: .everyone,
                                          published: true, audience: .everyone)
        XCTAssertNil(r.published)
        XCTAssertNil(r.audience)
        let r2 = EditVisibilityRules.patch(openedPublished: false, openedAudience: .followers,
                                           published: false, audience: .followers)
        XCTAssertNil(r2.published)
        XCTAssertNil(r2.audience)
    }

    func testChangedVisibilityIsSent() {
        // 🔴 **非公開にするときは範囲を送らない**（main 側はここで "" を期待していた）。
        // "" を送るとサーバーは範囲を消す（`photoUpdate.ts` の `hasAudience`）ので、
        // 「フォロワーのみ」を非公開→公開に戻すと**全体に公開**されていた。
        // 送らなければサーバーは範囲を残す
        let off = EditVisibilityRules.patch(openedPublished: true, openedAudience: .followers,
                                            published: false, audience: .followers)
        XCTAssertEqual(off.published, false)
        XCTAssertNil(off.audience)
        let narrowed = EditVisibilityRules.patch(openedPublished: true, openedAudience: .everyone,
                                                 published: true, audience: .closeFriends)
        XCTAssertNil(narrowed.published)
        XCTAssertEqual(narrowed.audience, "closeFriends")
        let unknown = EditVisibilityRules.patch(openedPublished: false, openedAudience: nil,
                                                published: true, audience: .everyone)
        XCTAssertEqual(unknown.published, true)
        XCTAssertNil(unknown.audience)
    }

    // MARK: - D8 タグの区切りは Web と同じ

    func testSpaceDoesNotSplitTags() {
        XCTAssertEqual(TagInput.parse("New York, 夕焼け"), ["New York", "夕焼け"])
        XCTAssertTrue(TagInput.has("New York, 夕焼け", tag: "New York"))
        XCTAssertFalse(TagInput.has("New York", tag: "York"))
        XCTAssertEqual(TagInput.parse(TagInput.append("New York, ", tag: "Paris")), ["New York", "Paris"])
        XCTAssertEqual(TagInput.parse(TagInput.toggle("New York, 夕焼け, ", tag: "夕焼け")), ["New York"])
    }

    func testFullWidthAndHalfWidthCommasSplit() {
        XCTAssertEqual(TagInput.parse("夕焼け，海､山、川"), ["夕焼け", "海", "山", "川"])
        // `夕焼け，` で打ち終わり＝打ちかけの欠片は無い
        XCTAssertEqual(TagInput.typingFragment(TagChoices.all, current: "夕焼け，"), "")
        XCTAssertEqual(TagInput.typingFragment(["sauna"], current: "京都，sau"), "sau")
        XCTAssertEqual(TagInput.typingFragment(["sauna"], current: "New Yo"), "New Yo")
        XCTAssertEqual(TagInput.dropFragment(["sauna"], current: "京都，sau"), "京都，")
    }
}
