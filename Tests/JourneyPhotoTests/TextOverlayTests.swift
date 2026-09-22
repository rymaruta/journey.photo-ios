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
}
