import XCTest
@testable import JourneyPhoto

/// 曲の札の6つの形（2026-10-28・押して替える・`SongStickerStyle` / `SongStickerLayout`）
final class SongStickerStyleTests: XCTestCase {

    private func song(_ title: String, _ artist: String? = nil) -> Photo.Song {
        Photo.Song(title: title, artist: artist, artwork: "https://is1-ssl.mzstatic.com/a.jpg",
                   previewUrl: "https://audio-ssl.itunes.apple.com/p.m4a", trackUrl: nil)
    }

    /// 決まった測り方（全角1・半角0.6 × 字の大きさ、高さは字の 1.2 倍）。描く側の書体の代わり
    private let measure: SongStickerLayout.Measure = { text, _, size in
        CGSize(width: text.reduce(0.0) { $0 + ($1.isASCII ? 0.6 : 1.0) } * size, height: size * 1.2)
    }

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SongStickerStyleTests")
        defaults.removePersistentDomain(forName: "SongStickerStyleTests")
    }

    // MARK: - 順送り

    /// 押すたびに A→B→C→D→E→F→A（6回で一周）
    func testCycleOrderWrapsAfterSix() {
        XCTAssertEqual(SongStickerStyle.allCases.map(\.letter), ["A", "B", "C", "D", "E", "F"])
        var style = SongStickerStyle.glass
        var seen: [SongStickerStyle] = []
        for _ in 0..<6 {
            seen.append(style)
            style = style.next
        }
        XCTAssertEqual(seen, [.glass, .white, .pill, .sleeve, .disc, .title])
        XCTAssertEqual(style, .glass, "F の次が A に戻らない")
    }

    /// 札を押す（`cycled`）: 形が次へ。文字だけの札（前の版）は A から。文字・位置・回しは残す
    func testCycledAdvancesStyleAndKeepsPlacement() throws {
        let now = song("海へ", "誰か")
        var sticker = try XCTUnwrap(SongSticker.make(for: now, style: .glass))
        sticker.x = 0.3; sticker.y = 0.7; sticker.rotation = 0.4
        let next = SongSticker.cycled(sticker, song: now)
        XCTAssertEqual(next.songStyle, .white)
        XCTAssertEqual(next.text, sticker.text)
        XCTAssertEqual(next.x, 0.3); XCTAssertEqual(next.y, 0.7); XCTAssertEqual(next.rotation, 0.4)
        XCTAssertTrue(SongSticker.isSticker(next, of: now), "押したら付けた曲の札と見なされなくなった")

        let legacy = try XCTUnwrap(SongSticker.make(for: now, style: nil))
        XCTAssertEqual(SongSticker.cycled(legacy, song: now).songStyle, .glass)
    }

    /// 6回押すと元の形・元の大きさに戻る（大きさは形ごとの置いたときの大きさの比で替わる）
    func testCyclingSixTimesReturnsToSameSize() throws {
        let now = song("Bohemian Rhapsody", "Queen")
        var sticker = try XCTUnwrap(SongSticker.make(for: now, style: .glass))
        sticker.size = 0.05
        var cur = sticker
        for _ in 0..<6 { cur = SongSticker.cycled(cur, song: now) }
        XCTAssertEqual(cur.songStyle, .glass)
        XCTAssertEqual(cur.size, 0.05, accuracy: 1e-9)
    }

    // MARK: - 覚える

    /// 最後に選んだ形を覚え、次に置く札はその形で始まる。覚えていなければ A
    func testRememberedStyle() throws {
        XCTAssertEqual(SongStickerStyle.remembered(defaults: defaults), .glass)
        SongStickerStyle.remember(.disc, defaults: defaults)
        XCTAssertEqual(SongStickerStyle.remembered(defaults: defaults), .disc)
        let placed = try XCTUnwrap(SongSticker.make(for: song("海へ"), style: SongStickerStyle.remembered(defaults: defaults)))
        XCTAssertEqual(placed.songStyle, .disc)
        // 読めない値は A に戻す
        defaults.set("tape", forKey: SongStickerStyle.defaultsKey)
        XCTAssertEqual(SongStickerStyle.remembered(defaults: defaults), .glass)
    }

    /// 形は下書きに残る（`Codable`）。前の版の下書き（形の項目なし）は文字だけの札。曲の札以外は持たない
    func testStyleSurvivesDraftAndOldDraftsDecode() throws {
        let sticker = try XCTUnwrap(SongSticker.make(for: song("海へ"), style: .sleeve))
        let data = try JSONEncoder().encode(sticker)
        XCTAssertEqual(try JSONDecoder().decode(TextOverlay.self, from: data).songStyle, .sleeve)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "songStyle")
        let old = try JSONDecoder().decode(TextOverlay.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.songStyle)

        object["songStyle"] = "disc"
        object["kind"] = "text"
        let text = try JSONDecoder().decode(TextOverlay.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(text.songStyle, "文字の札に形が付いた")
    }

    // MARK: - 曲を変えた・外した（形を問わず今と同じ）

    func testRetextKeepsStyleAndDetachWorksForEveryStyle() throws {
        let old = song("海へ", "誰か"), new = song("山へ", "彼方")
        for style in SongStickerStyle.allCases {
            var sticker = try XCTUnwrap(SongSticker.make(for: old, style: style))
            sticker.x = 0.2
            let changed = SongSticker.retext([sticker], from: old, to: new)
            XCTAssertTrue(changed.found, "\(style)")
            XCTAssertEqual(changed.overlays[0].text, "山へ · 彼方", "\(style)")
            XCTAssertEqual(changed.overlays[0].songStyle, style, "曲を変えたら形が戻った \(style)")
            XCTAssertEqual(changed.overlays[0].x, 0.2)
            XCTAssertTrue(SongSticker.isOnPhoto(changed.overlays, song: new), "\(style)")

            let removed = SongSticker.retext([sticker], from: old, to: nil)
            XCTAssertTrue(removed.found)
            XCTAssertTrue(removed.overlays.isEmpty, "曲を外しても札が残った \(style)")

            XCTAssertTrue(SongSticker.shouldDetach(removedSticker: SongSticker.isSticker(sticker, of: old),
                                                   remaining: [[]], song: old), "\(style)")
            XCTAssertFalse(SongSticker.shouldDetach(removedSticker: true, remaining: [[sticker]], song: old))
        }
    }

    /// 形で描くのは付けた曲の札だけ。前の曲の札・自分で打った「曲」の札・文字だけの札は文字で描く
    func testShapeOnlyForCurrentSongSticker() throws {
        let now = song("海へ")
        let sticker = try XCTUnwrap(SongSticker.make(for: now, style: .disc))
        XCTAssertEqual(SongSticker.shape(of: sticker, song: now), .disc)
        XCTAssertNil(SongSticker.shape(of: sticker, song: song("山へ")))
        XCTAssertNil(SongSticker.shape(of: sticker, song: nil))
        var typed = TextOverlay(text: "旅のBGM", kind: .song)
        typed.songStyle = .glass
        XCTAssertNil(SongSticker.shape(of: typed, song: now))
        XCTAssertNil(SongSticker.shape(of: try XCTUnwrap(SongSticker.make(for: now, style: nil)), song: now))
    }

    /// 大きさの幅: 形のある札はつまんでも上限 0.08（文字の 0.2 まで広げると写真を覆う）。下限は 12pt 相当
    func testShapedStickerSizeRange() throws {
        let sticker = try XCTUnwrap(SongSticker.make(for: song("海へ"), style: .sleeve))
        XCTAssertEqual(sticker.scaled(by: 100).size, SongStickerStyle.maxSize)
        XCTAssertEqual(sticker.scaled(by: 0.01).size, SongStickerStyle.minSize)
        XCTAssertGreaterThanOrEqual(SongStickerStyle.minSize * 390, 11.5, "下限で歌手の字が 12pt 相当を割る")
        let text = TextOverlay(text: "x")
        XCTAssertEqual(text.scaled(by: 100).size, TextOverlay.maxSize, "文字の札の上限まで変わった")
    }

    /// 置いたときの大きさ: 長い曲名は縮めて見えている幅に収め、短い曲名は既定
    func testFittedSizeShrinksLongTitles() throws {
        let short = try XCTUnwrap(SongSticker.make(for: song("海"), style: .glass))
        XCTAssertEqual(short.size, SongStickerStyle.defaultSize)
        let long = try XCTUnwrap(SongSticker.make(for: song("Bohemian Rhapsody (Remastered 2011)", "Queen"),
                                                  style: .glass))
        XCTAssertLessThan(long.size, SongStickerStyle.defaultSize)
        XCTAssertGreaterThanOrEqual(long.size, SongStickerStyle.minSize)
    }

    // MARK: - 焼き込みの寸法（作る画面と同じ寸法の組み方）

    /// 寸法は字の大きさに比例する（写真の画素が倍なら札も倍＝作る画面と焼き込みで同じ割合）
    func testLayoutScalesWithUnit() {
        for style in SongStickerStyle.allCases {
            let small = SongStickerLayout.make(style: style, title: "LADY", artist: "米津玄師", unit: 10, measure: measure)
            let big = SongStickerLayout.make(style: style, title: "LADY", artist: "米津玄師", unit: 30, measure: measure)
            XCTAssertEqual(big.size.width, small.size.width * 3, accuracy: 1e-6, "\(style)")
            XCTAssertEqual(big.size.height, small.size.height * 3, accuracy: 1e-6, "\(style)")
            for (a, b) in zip(small.texts, big.texts) {
                XCTAssertEqual(b.frame.minX, a.frame.minX * 3, accuracy: 1e-6, "\(style)")
                XCTAssertEqual(b.frame.minY, a.frame.minY * 3, accuracy: 1e-6, "\(style)")
                XCTAssertEqual(b.pointSize, a.pointSize * 3, accuracy: 1e-6)
            }
        }
    }

    /// モックの寸法（歌手の字 11.5px で組むと px がそのまま出る）
    func testLayoutMatchesMockPixels() {
        let card = SongStickerLayout.make(style: .glass, title: "LADY", artist: "米津玄師", unit: 11.5, measure: measure)
        let art = card.artwork ?? .zero
        XCTAssertEqual(art.minX, 8, accuracy: 1e-6); XCTAssertEqual(art.minY, 8, accuracy: 1e-6)
        XCTAssertEqual(art.width, 40, accuracy: 1e-6)
        XCTAssertEqual(card.size.height, 56, accuracy: 1e-6, "札の高さ（上下 8 ＋ ジャケット 40）")
        XCTAssertEqual(card.plate?.radius ?? 0, 14, accuracy: 1e-6)
        XCTAssertEqual(card.texts.first?.pointSize ?? 0, 13, accuracy: 1e-6)
        XCTAssertEqual(card.texts.first?.frame.minX ?? 0, 58, accuracy: 1e-6, "曲名はジャケットの右 10px")
        for (bar, h) in zip(card.bars, [6.0, 12, 8]) { XCTAssertEqual(bar.height, h, accuracy: 1e-6) }
        XCTAssertEqual(card.bars.count, 3)
        XCTAssertEqual(card.plate?.kind, .glass)

        let white = SongStickerLayout.make(style: .white, title: "LADY", artist: "米津玄師", unit: 11.5, measure: measure)
        XCTAssertEqual(white.plate?.kind, .white)
        XCTAssertEqual(white.texts.first?.color, SongStickerLayout.ink, "白い札の字は墨")

        let sleeve = SongStickerLayout.make(style: .sleeve, title: "LADY", artist: "米津玄師", unit: 11.5, measure: measure)
        XCTAssertEqual(sleeve.artwork?.width ?? 0, 118, accuracy: 1e-6)
        XCTAssertNil(sleeve.plate)

        let disc = SongStickerLayout.make(style: .disc, title: "LADY", artist: "米津玄師", unit: 11.5, measure: measure)
        XCTAssertEqual(disc.disc?.width ?? 0, 118, accuracy: 1e-6)
        XCTAssertTrue(disc.artworkIsCircle)
        XCTAssertEqual(disc.artwork?.width ?? 0, 118 * 0.32, accuracy: 1e-6, "中央の紙は盤の 32%")
        XCTAssertFalse(disc.grooves.isEmpty)

        let type = SongStickerLayout.make(style: .title, title: "LADY", artist: "米津玄師", unit: 11.5, measure: measure)
        XCTAssertEqual(type.texts.first?.role, .mincho)
        XCTAssertEqual(type.texts.first?.pointSize ?? 0, 30, accuracy: 1e-6)
        XCTAssertNil(type.artwork, "題字にジャケットを出した")

        let pill = SongStickerLayout.make(style: .pill, title: "LADY", artist: "米津玄師", unit: 11.5, measure: measure)
        XCTAssertNil(pill.artwork)
        XCTAssertEqual(pill.plate?.radius ?? 0, pill.size.height / 2, accuracy: 1e-6, "帯の角は丸")
    }

    /// 写真の上なので真鍮を使わない（白・墨・黒のガラスだけ）。字は 12pt 相当以上（歌手の字＝1）
    func testNoBrassAndReadableSizes() {
        for style in SongStickerStyle.allCases {
            let layout = SongStickerLayout.make(style: style, title: "LADY", artist: "米津玄師", unit: 12, measure: measure)
            let colors = layout.texts.map(\.color) + [layout.barColor]
            XCTAssertFalse(colors.contains(0xC9A66B), "\(style) に真鍮")
            XCTAssertTrue(colors.allSatisfy { $0 == 0xFFFFFF || $0 == SongStickerLayout.ink }, "\(style)")
            XCTAssertTrue(layout.texts.allSatisfy { $0.pointSize >= 12 - 1e-9 }, "\(style) に 12pt 未満の字")
        }
    }

    /// 長い曲名は「…」で切って、札の幅を抑える（焼き込みは折り返さない）
    func testLongTitleIsTruncated() {
        let title = String(repeating: "とても長い曲の名前", count: 4)
        for style in SongStickerStyle.allCases {
            let layout = SongStickerLayout.make(style: style, title: title, artist: "誰か", unit: 10, measure: measure)
            let first = layout.texts[0]
            XCTAssertTrue(first.text.hasSuffix("…"), "\(style)")
            XCTAssertLessThanOrEqual(layout.size.width, 10 * 26, "\(style) の札が広がりすぎる")
        }
        let short = SongStickerLayout.make(style: .glass, title: "海", artist: nil, unit: 10, measure: measure)
        XCTAssertEqual(short.texts.map(\.text), ["海"], "歌手が無いのに行を出した")
    }

    /// 棒の動きは 0.4〜1 倍、レコードは 6 秒で1周（作る画面だけ・焼き込みは止まった `bars`）
    func testMotionRanges() {
        for i in 0..<3 {
            for step in 0..<50 {
                let s = SongStickerLayout.barScale(index: i, time: Double(step) * 0.05)
                XCTAssertGreaterThanOrEqual(s, 0.4 - 1e-9)
                XCTAssertLessThanOrEqual(s, 1 + 1e-9)
            }
        }
        XCTAssertEqual(SongStickerLayout.discAngle(time: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(SongStickerLayout.discAngle(time: 3), .pi, accuracy: 1e-9)
    }

    // MARK: - 見る画面の流れる行

    func testMarquee() {
        XCTAssertFalse(SongMarquee.scrolls(textWidth: 120, reduceMotion: false), "収まる曲名を流した")
        XCTAssertTrue(SongMarquee.scrolls(textWidth: 400, reduceMotion: false))
        XCTAssertFalse(SongMarquee.scrolls(textWidth: 400, reduceMotion: true), "動きを減らす設定で流した")
        XCTAssertEqual(SongMarquee.offset(time: 0.5, textWidth: 400), 0, "頭で止まらない")
        let later = SongMarquee.offset(time: SongMarquee.pause + 2, textWidth: 400)
        XCTAssertEqual(later, 2 * SongMarquee.speed, accuracy: 1e-6)
        let cycle = SongMarquee.cycle(textWidth: 400)
        XCTAssertEqual(SongMarquee.offset(time: cycle + 0.5, textWidth: 400), 0, accuracy: 1e-9, "一周して頭に戻らない")
    }
}
