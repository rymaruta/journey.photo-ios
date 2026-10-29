import XCTest
import Foundation
@testable import JourneyPhoto

/// #404（2026-10-29）: ストーリーを作る画面で、**何も書いていない「ひとことを書く」の欄が写真の真ん中に
/// 出続けて写真を隠した**（owner「ひとことを書くに何も入力しなかった場合も残っちゃうの嫌だな」）。
/// 空で打っていない欄は描かない。入口は写真を押す（Instagram の文字入れと同じ）・「…」・一度だけの案内。
/// 曲の札は欄が出ていなければ真ん中に置き、欄が出たら置いたままの札だけ欄の外へ置き直す
final class StoryEmptyCaptionTests: XCTestCase {

    private func song(_ title: String, _ artist: String? = nil) -> Photo.Song {
        Photo.Song(title: title, artist: artist, artwork: "https://is1-ssl.mzstatic.com/a.jpg",
                   previewUrl: "https://audio-ssl.itunes.apple.com/p.m4a", trackUrl: nil)
    }

    private func span(_ overlay: TextOverlay, song: Photo.Song, image: CGSize) throws -> ClosedRange<Double> {
        let half = try XCTUnwrap(SongSticker.halfHeight(of: overlay, song: song, image: image))
        return (overlay.y - half)...(overlay.y + half)
    }

    private func clear(_ r: ClosedRange<Double>, of band: ClosedRange<Double>) -> Bool {
        r.upperBound <= band.lowerBound + 1e-9 || r.lowerBound >= band.upperBound - 1e-9
    }

    // MARK: - 欄を描くか

    /// 🔴 空で打っていない欄は描かない。打っている・打ち始めた直後・書いてあるときは描く
    func testEmptyUnfocusedCaptionIsNotDrawn() {
        XCTAssertFalse(StoryTextEditing.showsCaptionField(caption: "", focused: false, opening: false),
                       "空で打っていない欄が写真の上に残る")
        XCTAssertTrue(StoryTextEditing.showsCaptionField(caption: "", focused: true, opening: false))
        XCTAssertTrue(StoryTextEditing.showsCaptionField(caption: "", focused: false, opening: true),
                      "打ち始めた直後に欄が無いと、ピントを渡せない")
        XCTAssertTrue(StoryTextEditing.showsCaptionField(caption: "夕方の港で", focused: false, opening: false),
                      "書いたひとことが消える")
    }

    // MARK: - 写真を押したとき

    func testTappingThePhotoStartsAndEndsTheCaption() {
        XCTAssertEqual(StoryTextEditing.photoTap(caption: "", captionFocused: false, voteOpen: false), .startCaption)
        XCTAssertEqual(StoryTextEditing.photoTap(caption: "", captionFocused: true, voteOpen: false), .endCaption)
        XCTAssertEqual(StoryTextEditing.photoTap(caption: "港", captionFocused: true, voteOpen: false), .endCaption)
        XCTAssertEqual(StoryTextEditing.photoTap(caption: "港", captionFocused: false, voteOpen: false), .none,
                       "書いてあるのに写真を触るたびにキーボードが出る")
        XCTAssertEqual(StoryTextEditing.photoTap(caption: "", captionFocused: false, voteOpen: true), .closeVote,
                       "投票の欄を閉じる指で、ひとことまで打ち始めた")
    }

    // MARK: - 入口の案内（端末に1回だけ）

    func testCaptionHintShowsOncePerDeviceAndOnlyWhenEmpty() throws {
        let name = "StoryEmptyCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(StoryTextEditing.shouldShowCaptionHint(caption: "港", defaults: defaults))
        XCTAssertTrue(StoryTextEditing.shouldShowCaptionHint(caption: "", defaults: defaults))
        StoryTextEditing.markCaptionHintShown(defaults: defaults)
        XCTAssertFalse(StoryTextEditing.shouldShowCaptionHint(caption: "", defaults: defaults), "毎回出る")
        XCTAssertGreaterThan(StoryTextEditing.captionHintSeconds, 0)
        XCTAssertLessThanOrEqual(StoryTextEditing.captionHintSeconds, 6, "案内が写真の上に長く残る")
        XCTAssertEqual(StoryTextEditing.captionHint, "写真を押してひとこと")
    }

    // MARK: - 曲の札の置き場

    /// 🔴 欄が出ていない（band が nil）ときは欄を避けず、写真の縦の真ん中に置く。上下の道具には掛けない
    func testStickerIsCenteredWhenNoCaptionIsShown() throws {
        let now = song("夜明けの港で聴くバラード", "Journey Photo Band")
        for image in [CGSize(width: 3000, height: 4000), CGSize(width: 1080, height: 1920),
                      CGSize(width: 4000, height: 3000)] {
            for style in SongStickerStyle.allCases {
                let placed = try XCTUnwrap(SongSticker.make(for: now, style: style, image: image, band: nil))
                let r = try span(placed, song: now, image: image)
                XCTAssertGreaterThanOrEqual(r.lowerBound, SongSticker.placeRange.lowerBound - 1e-9, "\(style) \(image)")
                XCTAssertLessThanOrEqual(r.upperBound, SongSticker.placeRange.upperBound + 1e-9, "\(style) \(image)")
                if r.upperBound - r.lowerBound <= 0.5 {
                    XCTAssertEqual(placed.y, SongSticker.centerY, accuracy: 1e-9, "\(style) \(image) が真ん中に来ない")
                }
            }
        }
        // 欄が出ていれば今までどおり欄を避ける（既定の帯）
        let withBand = try XCTUnwrap(SongSticker.make(for: now, style: .glass, image: CGSize(width: 3000, height: 4000)))
        XCTAssertTrue(clear(try span(withBand, song: now, image: CGSize(width: 3000, height: 4000)),
                            of: SongSticker.defaultCaptionBand))
        // 文字だけの札（前の版）は欄に関係なく 0.6
        XCTAssertEqual(try XCTUnwrap(SongSticker.make(for: now, style: nil, band: nil)).y, 0.6)
    }

    /// 🔴 欄が出たら、置いたままの札で欄に掛かるものだけ欄の外へ。動かした札・掛かっていない札・別の札はそのまま
    func testCaptionAppearingMovesOnlyUntouchedOverlappingStickers() throws {
        let now = song("夜明けの港で聴くバラード", "Journey Photo Band")
        let image = CGSize(width: 3000, height: 4000)
        let band = SongSticker.defaultCaptionBand
        let centered = try XCTUnwrap(SongSticker.make(for: now, style: .glass, image: image, band: nil))
        XCTAssertFalse(clear(try span(centered, song: now, image: image), of: band), "前提: 真ん中の札は欄に掛かる")
        var moved = try XCTUnwrap(SongSticker.make(for: now, style: .glass, image: image, band: nil))
        moved.songMoved = true
        var high = try XCTUnwrap(SongSticker.make(for: now, style: .glass, image: image, band: nil))
        high.y = 0.2
        let text = TextOverlay(text: "港", x: 0.5, y: 0.5, kind: .text, face: .mincho)

        let out = SongSticker.clearedOfCaption([centered, moved, high, text], song: now, image: image, band: band)
        XCTAssertTrue(clear(try span(out[0], song: now, image: image), of: band), "欄が出ても札が欄の字に重なる")
        XCTAssertEqual(out[1], moved, "指で動かした札を動かした")
        XCTAssertEqual(out[2], high, "欄に掛かっていない札を動かした")
        XCTAssertEqual(out[3], text, "曲の札でない札を動かした")
        // 曲が無ければ何もしない
        XCTAssertEqual(SongSticker.clearedOfCaption([centered], song: nil, image: image, band: band), [centered])
    }

    // MARK: - 画面（作る画面の組み方）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let head = text.range(of: start) else { return "" }
        let rest = text[head.lowerBound...]
        guard let tail = rest.range(of: end, range: rest.index(after: rest.startIndex)..<rest.endIndex) else {
            return String(rest)
        }
        return String(rest[..<tail.lowerBound])
    }

    func testComposerHidesTheEmptyCaptionAndOffersEntrances() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        let field = slice(composer, from: "private var captionBlock: some View", to: "if !place.location.isEmpty")
        XCTAssertTrue(field.contains(".frame(height: captionShown ? nil : 0)"), "空の欄が高さを取る")
        XCTAssertTrue(field.contains(".opacity(captionShown ? 1 : 0)"), "空の欄を隠していない")
        XCTAssertTrue(field.contains(".allowsHitTesting(captionShown)"), "見えない欄が写真を押す指を取る")
        XCTAssertTrue(field.contains(".accessibilityHidden(!captionShown)"))
        XCTAssertTrue(composer.contains("StoryTextEditing.showsCaptionField(caption: caption, focused: captionFocused, opening: captionOpening)"))
        // 写真を押すと打ち始める
        XCTAssertTrue(composer.contains("onTapPhoto: { tapPhoto() }"), "写真を押してもひとことを打ち始めない")
        // 「…」の逃げ道
        let menu = slice(composer, from: "private var moreMenu: some View", to: "// MARK: - 足元")
        XCTAssertTrue(menu.contains("startCaption(after:"), "「…」に「ひとことを書く」が無い")
        XCTAssertTrue(menu.contains("L(\"ひとことを書く\""))
        // 案内は写真の上なので白・真鍮は使わない
        let hint = slice(composer, from: "private var captionHint: some View", to: "private func offerCaptionHint()")
        XCTAssertTrue(hint.contains(".foregroundStyle(.white)"))
        XCTAssertFalse(hint.contains("WebTheme.accent"), "写真の上に真鍮を置いた")
        XCTAssertTrue(hint.contains(".frame(minHeight: WebTheme.minTapTarget)"))
        // 欄が出ていないときは曲の札が欄を避けない
        let band = slice(composer, from: "private var songStickerBand: ClosedRange<Double>?", to: "/// 付けた曲とジャケット")
        XCTAssertTrue(band.contains("guard captionAreaShown else { return nil }"))
        XCTAssertTrue(composer.contains("captionShown || !place.location.isEmpty || place.chip != nil"),
                      "撮影地の札が出ているのに、曲の札が真ん中に重なる")
    }

    // MARK: - 見直しの直し（2026-10-29）

    /// 🔴 ピントは「欄を出した」状態が反映された後に渡す（`Task.yield()` は描き直しの後を保証しない）。
    /// ピントが入らなかったときに下ろすのは、空のときだけ
    func testFocusIsHandedAfterTheFieldIsShown() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        let start = slice(composer, from: "private func startCaption(after", to: "private func captionOpened()")
        XCTAssertFalse(start.contains("captionFocused = true"), "欄を出す前の同じ回にピントを渡している")
        XCTAssertFalse(start.contains("Task.yield()"))
        XCTAssertTrue(composer.contains(".onChange(of: captionOpening) { _, opening in if opening { captionOpened() } }"))
        let opened = slice(composer, from: "private func captionOpened()", to: "private func tapPhoto()")
        XCTAssertTrue(opened.contains("captionFocused = true"))
        XCTAssertTrue(opened.contains("if !captionFocused && caption.isEmpty { captionOpening = false }"),
                      "書いてある欄まで下ろす／空の欄を出したままにする")
    }

    /// 🔴 下書きを開いた・欄を測っただけでは曲の札を動かさない（開いたときの中身とずれて、閉じるときに確認が出た）。
    /// 動かすのは打ち始めた・打っている間だけ
    func testStickersMoveOnlyWhileWriting() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        let clear = slice(composer, from: "private func clearSongStickersOfCaption()", to: "private var captionBlock")
        XCTAssertTrue(clear.contains("guard captionOpening || captionFocused, let song else { return }"),
                      "打っていないのに曲の札を置き直す")
        XCTAssertFalse(composer.contains(".onChange(of: captionAreaShown)"), "欄が出た（下書きを開いた）だけで札を動かす")
    }

    /// 🔴 2本指の操作中・離した直後の1回押しは写真を押したことにしない
    func testTapRightAfterTwoFingersIsIgnored() {
        let now = Date()
        XCTAssertTrue(StoryTextEditing.acceptsPhotoTap(twoFingerActive: false, twoFingerEndedAt: nil, now: now))
        XCTAssertFalse(StoryTextEditing.acceptsPhotoTap(twoFingerActive: true, twoFingerEndedAt: nil, now: now))
        XCTAssertFalse(StoryTextEditing.acceptsPhotoTap(twoFingerActive: false,
                                                        twoFingerEndedAt: now.addingTimeInterval(-0.1), now: now),
                       "つまんで離した直後にキーボードが出る")
        XCTAssertTrue(StoryTextEditing.acceptsPhotoTap(twoFingerActive: false,
                                                       twoFingerEndedAt: now.addingTimeInterval(-1), now: now))
    }

    /// 🔴 写真の1回押しを2回押しで待たせない（合わせ方を戻すのは「…」だけ）。VoiceOver の入口がある
    func testPhotoTapIsNotDelayedAndVoiceOverCanWrite() throws {
        let editor = try source("Features/Stories/TextOverlayEditor.swift")
        XCTAssertFalse(editor.contains("onTapGesture(count: 2)"), "1回押しが2回押しを待って遅れる")
        XCTAssertFalse(editor.contains("2回押すと元に戻します"), "読み上げの説明が古い")
        XCTAssertTrue(editor.contains("StoryTextEditing.acceptsPhotoTap(twoFingerActive: twoFingerActive,"))
        XCTAssertTrue(editor.contains(".accessibilityAction(named: L(\"ひとことを書く\", \"Write a caption\")) { onWriteCaption() }"))
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("onWriteCaption: { startCaption() },"))
        XCTAssertTrue(composer.contains(".accessibilityIdentifier(captionShown ? \"story.caption\" : \"story.caption.hidden\")"))
        let menu = slice(composer, from: "private var moreMenu: some View", to: "// MARK: - 足元")
        XCTAssertTrue(menu.contains("framing.wrappedValue = .identity"), "合わせ方を戻す口が無くなった")
    }

    /// 画面写真（曲の札 62・ストーリー作成）に入口の案内を写さない
    func testScreenshotsSkipTheCaptionHint() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shots = try String(contentsOf: root.appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"),
                               encoding: .utf8)
        let song = slice(shots, from: "func testCapturesStorySongStickerStyles()", to: "app.launch()")
        XCTAssertTrue(song.contains("\"-story.captionHintShown\", \"YES\""), "曲の札の絵に案内が写る")
        XCTAssertEqual(StoryTextEditing.captionHintShownKey, "story.captionHintShown")
    }
}
