import XCTest
@testable import JourneyPhoto

/// 写真の上に置く文字の決まりごと。
final class TextOverlayTests: XCTestCase {

    /// **画面の外に出さない。** 出ると掴み直せず、消すこともできなくなる
    func testPositionStaysOnScreen() {
        XCTAssertEqual(TextOverlay.clampPosition(-5), 0.02, accuracy: 0.0001)
        XCTAssertEqual(TextOverlay.clampPosition(9), 0.98, accuracy: 0.0001)
        XCTAssertEqual(TextOverlay.clampPosition(0.4), 0.4, accuracy: 0.0001)
    }

    /// 大きさの幅。小さすぎて読めない／画面を覆う、のどちらも止める
    func testSizeIsClamped() {
        XCTAssertEqual(TextOverlay.clampSize(0), TextOverlay.minSize, accuracy: 0.0001)
        XCTAssertEqual(TextOverlay.clampSize(1), TextOverlay.maxSize, accuracy: 0.0001)
    }

    /// 動かした量は**画面の大きさに対する割合**で効く
    /// （編集中の画面と実際の画像は大きさが違う）
    func testMoveIsRelativeToCanvas() {
        let overlay = TextOverlay(text: "ここ", x: 0.5, y: 0.5)
        let moved = overlay.moved(by: CGSize(width: 100, height: -50),
                                  in: CGSize(width: 400, height: 500))
        XCTAssertEqual(moved.x, 0.75, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0.4, accuracy: 0.0001)
    }

    /// 大きさが 0 の画面で割らない（起動直後に来ることがある）
    func testMoveIgnoresEmptyCanvas() {
        let overlay = TextOverlay(text: "ここ", x: 0.3, y: 0.3)
        let moved = overlay.moved(by: CGSize(width: 10, height: 10),
                                  in: CGSize(width: 0, height: 0))
        XCTAssertEqual(moved.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0.3, accuracy: 0.0001)
    }

    /// 端まで動かしても外へは出ない
    func testMoveCannotLeaveTheCanvas() {
        let overlay = TextOverlay(text: "ここ", x: 0.9, y: 0.9)
        let moved = overlay.moved(by: CGSize(width: 9999, height: 9999),
                                  in: CGSize(width: 400, height: 500))
        XCTAssertEqual(moved.x, 0.98, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0.98, accuracy: 0.0001)
    }

    /// 写真は枠の中に縦横比のまま収まる。横長の写真を 3:4 の枠に入れると
    /// 上下に余白が出る
    func testFittedRectLeavesBandsAroundAWidePhoto() {
        let rect = TextOverlay.fittedRect(image: CGSize(width: 4000, height: 3000),
                                          in: CGSize(width: 300, height: 400))
        XCTAssertEqual(rect.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 300, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 225, accuracy: 0.0001)
        XCTAssertEqual(rect.minY, 87.5, accuracy: 0.0001)
    }

    /// 縦長の写真（9:16）は**左右に**余白が出る。中心は余白のぶん右へずれる
    func testCenterIncludesTheSideBands() {
        let photo = TextOverlay.fittedRect(image: CGSize(width: 900, height: 1600),
                                           in: CGSize(width: 300, height: 400))
        XCTAssertEqual(photo.width, 225, accuracy: 0.0001)
        XCTAssertEqual(photo.minX, 37.5, accuracy: 0.0001)
        let center = TextOverlay(text: "ここ", x: 0.2, y: 0.5).center(in: photo)
        XCTAssertEqual(center.x, 37.5 + 45, accuracy: 0.0001)
        XCTAssertEqual(center.y, 200, accuracy: 0.0001)
    }

    /// 埋めて敷く（作る画面）。縦長の枠に横長の写真を敷くと左右がはみ出す
    func testFilledRectOverflowsSideways() {
        let rect = TextOverlay.filledRect(image: CGSize(width: 4000, height: 3000),
                                          in: CGSize(width: 390, height: 700))
        XCTAssertEqual(rect.height, 700, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 700 * 4.0 / 3.0, accuracy: 0.0001)
        XCTAssertLessThan(rect.minX, 0)
    }

    /// 🔴 **見えている範囲の外へ出さない。** はみ出した端へ動かすと掴み直せない
    func testClampedToVisibleKeepsTextOnScreen() {
        let canvas = CGSize(width: 390, height: 700)
        let photo = TextOverlay.filledRect(image: CGSize(width: 4000, height: 3000), in: canvas)
        let overlay = TextOverlay(text: "端", x: 0.02, y: 0.5)
        let clamped = overlay.clamped(toVisible: photo, canvas: canvas)
        let center = clamped.center(in: photo)
        XCTAssertGreaterThanOrEqual(center.x, 0)
        XCTAssertLessThanOrEqual(center.x, canvas.width)
        // 真ん中は動かさない
        let middle = TextOverlay(text: "中", x: 0.5, y: 0.5).clamped(toVisible: photo, canvas: canvas)
        XCTAssertEqual(middle.x, 0.5, accuracy: 0.0001)
    }

    /// 大きさが分からないときは枠いっぱい（0 で割らない）
    func testFittedRectWithUnknownImageFillsTheCanvas() {
        let rect = TextOverlay.fittedRect(image: CGSize(width: 0, height: 0),
                                          in: CGSize(width: 300, height: 400))
        XCTAssertEqual(rect.width, 300, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 400, accuracy: 0.0001)
    }

    /// 🔴 **編集画面の文字は、焼き込んだ画像を縮めたものと重なる。**
    /// 以前は編集画面が「枠の高さ」「枠に対する位置」で描いていて、
    /// 横長の写真だと大きさも位置も投稿後と違っていた
    func testEditorMatchesTheBurnedImage() {
        let image = CGSize(width: 4000, height: 3000)
        let overlay = TextOverlay(text: "ここ", x: 0.2, y: 0.1, size: 0.1)
        let photo = TextOverlay.fittedRect(image: image, in: CGSize(width: 300, height: 400))
        let shrink = photo.width / image.width

        // 大きさ: 焼き込み（画像の短い辺 3000 × 0.1 = 300）を縮めたもの
        XCTAssertEqual(TextOverlay.fontSize(overlay.size, in: photo.size),
                       TextOverlay.fontSize(overlay.size, in: image) * shrink, accuracy: 0.0001)
        XCTAssertEqual(TextOverlay.fontSize(overlay.size, in: image), 300, accuracy: 0.0001)

        // 位置: 編集画面（枠の中の写真）と焼き込み（画像全体）が同じ関数を通り、
        // 縮めると重なる。**枠に対して置くと y は 400 × 0.1 = 40 になっていた**
        let editor = overlay.center(in: photo)
        let burned = overlay.center(in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        XCTAssertEqual(editor.x, photo.minX + burned.x * shrink, accuracy: 0.0001)
        XCTAssertEqual(editor.y, photo.minY + burned.y * shrink, accuracy: 0.0001)
        XCTAssertEqual(editor.y, 87.5 + 22.5, accuracy: 0.0001)
    }

    /// 空白だけの文字は「無い」扱い（見えない物を焼き込まない）
    func testBlankTextIsEmpty() {
        XCTAssertTrue(TextOverlay(text: "   \n ").isEmpty)
        XCTAssertFalse(TextOverlay(text: "秋").isEmpty)
    }

    /// 長すぎる文字はサーバーのキャプションと同じ 200 字で切る
    func testTextIsTruncated() {
        let overlay = TextOverlay(text: String(repeating: "あ", count: 300))
        XCTAssertEqual(overlay.text.count, TextOverlay.maxLength)
    }

    /// 作ったときも位置と大きさは幅の中に収める
    func testInitClamps() {
        let overlay = TextOverlay(text: "x", x: 2, y: -1, size: 99)
        XCTAssertEqual(overlay.x, 0.98, accuracy: 0.0001)
        XCTAssertEqual(overlay.y, 0.02, accuracy: 0.0001)
        XCTAssertEqual(overlay.size, TextOverlay.maxSize, accuracy: 0.0001)
    }
}

/// 焼き込みの入口。**実際に描けるかは iOS でしか確かめられない**
/// （`UIGraphicsImageRenderer` は模型では何も描かない）ので、
/// ここで見張るのは「描かない回に元のデータを壊さないこと」。
final class TextOverlayRendererTests: XCTestCase {

    private let original = Data("これは画像のつもり".utf8)

    /// 文字が無ければ**元のデータをそのまま返す**
    /// （読み書きの往復で画質を落とさない）
    func testNoOverlaysReturnsTheOriginal() {
        XCTAssertEqual(TextOverlayRenderer.burn([], into: original), original)
    }

    /// 空白だけの文字も「無い」扱い
    func testBlankOverlaysReturnTheOriginal() {
        let blank = [TextOverlay(text: "   "), TextOverlay(text: "\n")]
        XCTAssertEqual(TextOverlayRenderer.burn(blank, into: original), original)
    }

    /// 画像として読めないデータは**素通しする**。
    /// ここで投げると、投稿そのものが落ちる（文字が乗らないだけで済ませる）
    func testUnreadableImageIsPassedThrough() {
        XCTAssertEqual(TextOverlayRenderer.burn([TextOverlay(text: "秋")], into: original),
                       original)
    }
}

/// 札の種類（文字・場所・曲）。モック4 のステッカー。
final class TextOverlayKindTests: XCTestCase {

    /// **場所と曲は帯で固定。** 見た目を選ばせると、白い文字を明るい空に
    /// 置いて読めない札ができる
    func testPlaceAndSongAreAlwaysBanners() {
        XCTAssertEqual(TextOverlay(text: "フィンランド", style: .light, kind: .place).style, .banner)
        XCTAssertEqual(TextOverlay(text: "Sayonara", style: .dark, kind: .song).style, .banner)
    }

    /// 自由な文字は選んだ見た目のまま
    func testPlainTextKeepsItsStyle() {
        XCTAssertEqual(TextOverlay(text: "また来たい", style: .dark, kind: .text).style, .dark)
    }

    /// 印は場所と曲にだけ付く
    func testSymbols() {
        XCTAssertEqual(TextOverlay.display(text: "京都", kind: .place), "📍 京都")
        XCTAssertEqual(TextOverlay.display(text: "海の音", kind: .song), "♪ 海の音")
        XCTAssertEqual(TextOverlay.display(text: "また来たい", kind: .text), "また来たい")
    }
}

// MARK: - スタンプ（モック4-3）

extension TextOverlayTests {

    private var noon: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// **時刻と日付は端末から採る。** 打たせるものではないし、
    /// 打たせると嘘を書ける
    func testTimeAndDateComeFromTheClock() {
        let time = TextOverlay.Kind.time.initialText(now: noon, calendar: utc)
        XCTAssertTrue(time.contains(":"), time)
        let date = TextOverlay.Kind.date.initialText(now: noon, calendar: utc)
        XCTAssertFalse(date.isEmpty)
    }

    /// 打って置く札は空から始まる（打つ前に何かが入っていない）
    func testTypedKindsStartEmpty() {
        for kind in [TextOverlay.Kind.text, .place, .song, .hashtag] {
            XCTAssertEqual(kind.initialText(now: noon, calendar: utc), "", "\(kind)")
        }
    }

    /// **端末から採った札は直させない**（直せると「いつの話か」が嘘になる）
    func testClockKindsAreNotEditable() {
        XCTAssertFalse(TextOverlay.Kind.time.isEditable)
        XCTAssertFalse(TextOverlay.Kind.date.isEditable)
        XCTAssertTrue(TextOverlay.Kind.text.isEditable)
        XCTAssertTrue(TextOverlay.Kind.hashtag.isEditable)
    }

    /// 自由な文字以外は**必ず帯**（写真の上で読めなくならないように）
    func testOnlyFreeTextKeepsItsStyle() {
        for kind in TextOverlay.Kind.allCases where kind != .text {
            XCTAssertEqual(kind.forcedStyle, .banner, "\(kind)")
        }
        XCTAssertNil(TextOverlay.Kind.text.forcedStyle)
    }

    /// どの札にも道具の名前と絵がある（板に並べるため）
    func testEveryKindHasATool() {
        for kind in TextOverlay.Kind.allCases {
            XCTAssertFalse(kind.toolLabel.isEmpty, "\(kind)")
            XCTAssertFalse(kind.toolSymbol.isEmpty, "\(kind)")
        }
    }

    /// 🔴 **前の版の下書きも読める。** 書体・色・回しは後から足した項目で、
    /// 無いと下書きごと捨てられていた（`StoryDraftStore` が読めない記録を捨てる）
    func testOldDraftOverlayStillDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"港","x":0.4,"y":0.3,"size":0.07,"style":"dark","kind":"text"}"#
        let overlay = try JSONDecoder().decode(TextOverlay.self, from: Data(json.utf8))
        XCTAssertEqual(overlay.face, .gothic)
        XCTAssertEqual(overlay.ink, .ink)
        XCTAssertEqual(overlay.rotation, 0)
    }

    /// 書体・色・回しは下書きを行き来しても残る
    func testFaceInkRotationRoundTrip() throws {
        let overlay = TextOverlay(text: "港", face: .hand, ink: .brass, rotation: 0.4)
        let back = try JSONDecoder().decode(TextOverlay.self, from: JSONEncoder().encode(overlay))
        XCTAssertEqual(back.face, .hand)
        XCTAssertEqual(back.ink, .brass)
        XCTAssertEqual(back.rotation, 0.4, accuracy: 0.0001)
    }

    /// 色を言わなければ見た目に合わせる（黒の見た目は墨の文字）
    func testDefaultInkFollowsStyle() {
        XCTAssertEqual(TextOverlay(text: "a", style: .dark).ink, .ink)
        XCTAssertEqual(TextOverlay(text: "a", style: .light).ink, .white)
    }

    /// 🔴 **帯に墨・黒の見た目に白は描かない**（地や縁と同じ色で文字が消える）。
    /// 札（撮影地など）は帯に固定なので、墨を選んでいても白で描く
    func testUnreadableInkIsNotDrawn() {
        XCTAssertEqual(TextOverlay(text: "a", style: .banner, ink: .ink).drawnInk, .white)
        XCTAssertEqual(TextOverlay(text: "a", style: .dark, ink: .white).drawnInk, .ink)
        XCTAssertEqual(TextOverlay(text: "港", style: .light, kind: .place, ink: .ink).drawnInk, .white)
        XCTAssertEqual(TextOverlay(text: "a", style: .banner, ink: .brass).drawnInk, .brass)
        XCTAssertFalse(TextOverlay.inks(for: .banner).contains(.ink))
        XCTAssertFalse(TextOverlay.inks(for: .dark).contains(.white))
        XCTAssertEqual(TextOverlay.inks(for: .light), TextOverlay.Ink.allCases)
    }
}
