import XCTest
@testable import JourneyPhoto

/// 曲を選んだら写真に置く、動かせる曲の札（`SongSticker`）
final class SongStickerTests: XCTestCase {

    private func song(_ title: String, _ artist: String? = nil) -> Photo.Song {
        Photo.Song(title: title, artist: artist, artwork: nil,
                   previewUrl: "https://audio-ssl.itunes.apple.com/p.m4a", trackUrl: nil)
    }

    /// 札は「曲名 · アーティスト」の曲の札（動かせる `.song`）。題が空なら置かない
    func testMakeSticker() {
        let sticker = SongSticker.make(for: song("海へ", "誰か"))
        XCTAssertEqual(sticker?.text, "海へ · 誰か")
        XCTAssertEqual(sticker?.kind, .song)
        XCTAssertEqual(SongSticker.make(for: song("海へ"))?.text, "海へ")
        XCTAssertNil(SongSticker.make(for: song("  ")))
    }

    /// 曲を変えたら前の曲の札の文字を差し替える（位置は残す。大きさは文字の長さの比で変わる）
    func testChangeRetextsOldSticker() {
        var sticker = SongSticker.make(for: song("海へ"))!
        sticker.x = 0.2
        let other = TextOverlay(text: "こんにちは")
        let result = SongSticker.retext([other, sticker], from: song("海へ"), to: song("山へ", "誰か"))
        XCTAssertTrue(result.found)
        XCTAssertEqual(result.overlays.map(\.text), ["こんにちは", "山へ · 誰か"])
        XCTAssertEqual(result.overlays[1].x, 0.2, "動かした位置は残す")
    }

    /// 曲を外したら前の曲の札だけ消す。打ち直した札・ほかの文字には触らない
    func testRemoveDeletesOnlyOldSticker() {
        let sticker = SongSticker.make(for: song("海へ"))!
        let edited = TextOverlay(text: "好きな曲", kind: .song)
        let result = SongSticker.retext([sticker, edited], from: song("海へ"), to: nil)
        XCTAssertTrue(result.found)
        XCTAssertEqual(result.overlays.map(\.text), ["好きな曲"])
    }

    /// 前の曲の札が無ければ見つからない（呼ぶ側がいまの1枚に置く）
    func testNotFoundWhenNoOldSticker() {
        XCTAssertFalse(SongSticker.retext([], from: nil, to: song("海へ")).found)
        XCTAssertFalse(SongSticker.retext([TextOverlay(text: "x")], from: song("海へ"), to: song("山へ")).found)
    }

    /// 長い曲名は小さくして置く（焼き込みは1行。既定の大きさだと写真の幅を超える）
    func testLongTitleIsShrunkToFit() {
        let short = SongSticker.make(for: song("海へ"))!
        XCTAssertEqual(short.size, TextOverlay.defaultSize, "短い曲名は既定の大きさ")

        let long = SongSticker.make(for: song("Bohemian Rhapsody", "Queen"))!
        XCTAssertLessThan(long.size, TextOverlay.defaultSize)
        XCTAssertGreaterThanOrEqual(long.size, TextOverlay.minSize)
        // 字の幅の目安（半角0.6・全角1）で、見えている幅に収まる
        let ems = long.displayText.reduce(1.0) { $0 + ($1.isASCII ? 0.6 : 1.0) }
        XCTAssertLessThanOrEqual(ems * long.size, SongSticker.fitWidth + 1e-9)
    }

    /// 閲覧画面の ♪ 行と札は同じ文字（片方だけ変わらないように）
    func testViewerSongLineMatchesSticker() throws {
        let json = #"{"id":"s","src":"https://x.test/s.jpg","song":{"title":"海へ","artist":"誰か","previewUrl":"https://audio-ssl.itunes.apple.com/p.m4a"}}"#
        let story = try JSONDecoder.api.decode(Story.self, from: Data(json.utf8))
        XCTAssertEqual(story.songLine, SongSticker.make(for: song("海へ", "誰か"))?.text)
    }

    /// 曲を変えたら、置いたときの大きさの比で大きさを変える
    func testChangingSongScalesStickerByFittedSize() {
        func change(_ size: Double, _ from: String, _ to: String) -> Double {
            var sticker = SongSticker.make(for: song(from))!
            sticker.size = size
            return SongSticker.retext([sticker], from: song(from), to: song(to)).overlays[0].size
        }
        let fittedLemon = SongSticker.make(for: song("Lemon · 米津玄師"))!.size
        let fittedLong = SongSticker.make(for: song("Bohemian Rhapsody · Queen"))!.size

        // 手を付けていない札は、新しい曲名で置いたときと同じ大きさ
        XCTAssertEqual(change(TextOverlay.defaultSize, "海へ", "Lemon · 米津玄師"), fittedLemon, accuracy: 1e-9)
        XCTAssertEqual(change(TextOverlay.defaultSize, "山", "海へ"), TextOverlay.defaultSize, accuracy: 1e-9,
                       "短い曲どうしは変わらない")
        XCTAssertEqual(change(TextOverlay.defaultSize, "海へ", "Bohemian Rhapsody · Queen"), fittedLong, accuracy: 1e-9)

        // 自分で大きくした分は倍率として残り、行き来しても元に戻る
        let big = change(0.10, "海へ", "Lemon · 米津玄師")
        XCTAssertEqual(big, 0.10 * fittedLemon / TextOverlay.defaultSize, accuracy: 1e-9)
        var sticker = SongSticker.make(for: song("Lemon · 米津玄師"))!
        sticker.size = big
        let back = SongSticker.retext([sticker], from: song("Lemon · 米津玄師"), to: song("海へ")).overlays[0].size
        XCTAssertEqual(back, 0.10, accuracy: 1e-9, "戻したら元の大きさ")

        // 短い曲どうしなら、自分で小さく・大きくした分はそのまま
        XCTAssertEqual(change(TextOverlay.minSize, "海へ", "山"), TextOverlay.minSize, accuracy: 1e-9)
        XCTAssertEqual(change(0.15, "海へ", "山へ"), 0.15, accuracy: 1e-9)
    }
}
