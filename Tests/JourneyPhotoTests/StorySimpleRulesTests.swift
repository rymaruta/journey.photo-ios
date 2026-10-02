import XCTest
@testable import JourneyPhoto

/// ストーリー作成のかんたん版（owner・2026-10-02）の決まり。
/// 「次へ」の文言と押せるか・書体の回り順・背景の回り順・色の丸・道具の「使った」の判断
final class StorySimpleRulesTests: XCTestCase {

    // MARK: - 「次へ（N枚）」

    func testNextIsDisabledWithNoPhotos() {
        let next = StorySimpleRules.nextButton(selected: 0, loading: false)
        XCTAssertFalse(next.enabled)
        XCTAssertEqual(next.title, L("写真を選んでください", "Choose photos"))
    }

    func testNextShowsTheCount() {
        let next = StorySimpleRules.nextButton(selected: 3, loading: false)
        XCTAssertTrue(next.enabled)
        XCTAssertEqual(next.title, L("次へ（3枚）", "Next (3)"))
    }

    /// 読み込みの最中は押せない（2本の読み込みが混ざって並んだ）
    func testNextIsDisabledWhileLoading() {
        XCTAssertFalse(StorySimpleRules.nextButton(selected: 2, loading: true).enabled)
    }

    // MARK: - カメラ・並びの帯

    /// 写真を選ぶ段で印を付けてからカメラで撮ったら、印の写真も読み込む（撮った1枚は後）
    func testCameraKeepsMarkedPicksOnPickStage() {
        XCTAssertEqual(StorySimpleRules.picksToLoadBeforeCamera(["a", "b"], hasShots: false), ["a", "b"])
    }

    /// 仕上げる段で撮ったときは足すだけ
    func testCameraOnEditStageLoadsNothingElse() {
        XCTAssertEqual(StorySimpleRules.picksToLoadBeforeCamera(["a"], hasShots: true), [])
    }

    /// 読み込み中は「この写真を外す」を止める
    func testCannotRemoveShotWhileLoading() {
        XCTAssertFalse(StorySimpleRules.canRemoveShot(loading: true))
        XCTAssertTrue(StorySimpleRules.canRemoveShot(loading: false))
    }

    // MARK: - 書体

    /// 明朝 → ゴシック → 手書き風 の順で回り、後ろの5つを通って明朝へ戻る
    func testFaceCyclesMinchoGothicHand() {
        var overlay = TextOverlay(text: "旅", face: .mincho)
        overlay = StorySimpleRules.nextFace(overlay)
        XCTAssertEqual(overlay.face, .gothic)
        overlay = StorySimpleRules.nextFace(overlay)
        XCTAssertEqual(overlay.face, .hand)
        var seen: [TextOverlay.Face] = [.mincho, .gothic, .hand]
        for _ in 0..<(TextOverlay.Face.allCases.count - 3) {
            overlay = StorySimpleRules.nextFace(overlay)
            seen.append(overlay.face)
        }
        XCTAssertEqual(Set(seen), Set(TextOverlay.Face.allCases), "どの書体も選べる（前に足した5つを落とさない）")
        XCTAssertEqual(StorySimpleRules.nextFace(overlay).face, .mincho)
    }

    /// スタンプは書体を持たない
    func testStampFaceDoesNotChange() {
        let stamp = TextOverlay(text: "🌸", kind: .stamp)
        XCTAssertEqual(StorySimpleRules.nextFace(stamp), stamp)
    }

    // MARK: - 背景

    func testBackdropCyclesNoneBannerOutline() {
        var overlay = TextOverlay(text: "旅", style: .light)
        XCTAssertEqual(StorySimpleRules.backdrop(of: overlay.style), .none)
        overlay = StorySimpleRules.nextBackdrop(overlay)
        XCTAssertEqual(overlay.style, .banner)
        overlay = StorySimpleRules.nextBackdrop(overlay)
        XCTAssertEqual(overlay.style, .outline)
        overlay = StorySimpleRules.nextBackdrop(overlay)
        XCTAssertEqual(overlay.style, .light)
    }

    /// 黒の見た目（墨の字）も「背景無し」。帯へ進むと墨は読めないので白に寄る（`withStyle`）
    func testDarkCountsAsNoBackdrop() {
        let dark = TextOverlay(text: "旅", style: .dark, ink: .ink)
        XCTAssertEqual(StorySimpleRules.backdrop(of: dark.style), .none)
        let banner = StorySimpleRules.nextBackdrop(dark)
        XCTAssertEqual(banner.style, .banner)
        XCTAssertEqual(banner.ink, .white)
    }

    /// 帯で固定の札（撮影地）は背景を変えない
    func testForcedBannerDoesNotChange() {
        let place = TextOverlay(text: "京都", kind: .place)
        XCTAssertEqual(StorySimpleRules.nextBackdrop(place), place)
    }

    // MARK: - 色の丸

    func testFourInksWithoutBackdrop() {
        let overlay = TextOverlay(text: "旅", style: .light)
        XCTAssertEqual(StorySimpleRules.inks(for: overlay), [.white, .ink, .brass, .sky])
    }

    /// 帯・縁取りでは墨を出さない（読めない）
    func testNoInkOnBanner() {
        let overlay = TextOverlay(text: "旅", style: .banner)
        XCTAssertEqual(StorySimpleRules.inks(for: overlay), [.white, .brass, .sky])
    }

    /// 背景無しで墨を選ぶと黒の見た目（白い縁）、白に戻すと白の見た目。好きな色は外す
    func testChoosingInkSwitchesLightAndDark() {
        var overlay = TextOverlay(text: "旅", style: .light)
        overlay.customHex = 0x123456
        overlay = StorySimpleRules.choose(.ink, for: overlay)
        XCTAssertEqual(overlay.style, .dark)
        XCTAssertEqual(overlay.ink, .ink)
        XCTAssertNil(overlay.customHex)
        overlay = StorySimpleRules.choose(.white, for: overlay)
        XCTAssertEqual(overlay.style, .light)
        XCTAssertEqual(overlay.ink, .white)
    }

    /// 帯の上で色を選んでも、背景は帯のまま
    func testChoosingInkKeepsBanner() {
        let overlay = StorySimpleRules.choose(.brass, for: TextOverlay(text: "旅", style: .banner))
        XCTAssertEqual(overlay.style, .banner)
        XCTAssertEqual(overlay.ink, .brass)
        XCTAssertTrue(StorySimpleRules.isSelected(.brass, in: overlay))
    }

    // MARK: - 道具の「使った」

    private func used(_ tool: StoryTool, overlays: [TextOverlay] = [], vote: Bool = false,
                      song: Bool = false, location: String = "") -> Bool {
        StoryTool.isUsed(tool, overlays: overlays, hasVote: vote, hasSong: song, location: location)
    }

    func testNothingUsedAtFirst() {
        for tool in StoryTool.allCases {
            XCTAssertFalse(used(tool), "\(tool)")
        }
    }

    func testTextUsedOnlyByTextOverlays() {
        XCTAssertTrue(used(.text, overlays: [TextOverlay(text: "旅")]))
        XCTAssertFalse(used(.text, overlays: [TextOverlay(text: "🌸", kind: .stamp)]))
    }

    /// スタンプ: スタンプ・タグ・時刻などの札か投票
    func testStickerUsedByStampsOrVote() {
        XCTAssertTrue(used(.sticker, overlays: [TextOverlay(text: "🌸", kind: .stamp)]))
        XCTAssertTrue(used(.sticker, overlays: [TextOverlay(text: "旅行", kind: .hashtag)]))
        XCTAssertTrue(used(.sticker, vote: true))
        XCTAssertFalse(used(.sticker, overlays: [TextOverlay(text: "旅")]))
    }

    /// 曲の札（曲を付けると自動で置かれる）はスタンプに数えず、曲を光らせる
    func testSongStickerLightsSongNotSticker() {
        let sticker = [TextOverlay(text: "曲名", kind: .song)]
        XCTAssertFalse(used(.sticker, overlays: sticker, song: true))
        XCTAssertTrue(used(.song, overlays: sticker, song: true))
    }

    /// 撮影地の札は場所を光らせ、スタンプには数えない
    func testPlaceStickerLightsPlaceNotSticker() {
        let sticker = [TextOverlay(text: "京都", kind: .place)]
        XCTAssertFalse(used(.sticker, overlays: sticker))
        XCTAssertTrue(used(.place, overlays: sticker))
    }

    func testSongAndPlace() {
        XCTAssertTrue(used(.song, song: true))
        XCTAssertTrue(used(.place, location: "京都"))
        XCTAssertFalse(used(.place, location: "  "), "空白だけは入っていない扱い")
    }

    func testAccessibilityLabelReadsState() {
        XCTAssertEqual(StoryTool.text.accessibilityLabel(used: true), L("文字・入れてあります", "Text, added"))
        XCTAssertEqual(StoryTool.text.accessibilityLabel(used: false), L("文字", "Text"))
    }
}
