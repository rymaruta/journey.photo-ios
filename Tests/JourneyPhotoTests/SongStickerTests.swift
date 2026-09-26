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

    /// 曲を変えたら前の曲の札の文字を差し替える（位置・大きさは残す）
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
}
