import XCTest
@testable import JourneyPhoto

/// マイページの曲の行（2026-10-24 owner の要望「アルバムのジャケット・曲名・歌手名・再生ボタン」）。
/// ジャケットの出どころ・読めないときの代わり・再生の印・表示文言を見張る
final class ProfileSongLineTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func song(artist: String? = "米津玄師", artwork: String?) -> Photo.Song {
        Photo.Song(title: "LADY", artist: artist, artwork: artwork,
                   previewUrl: "https://audio-ssl.itunes.apple.com/a.m4a", trackUrl: nil)
    }

    /// ジャケットはサーバーが曲と一緒に返す `artwork`（iTunes の 300x300）をそのまま使う
    func testArtworkComesFromTheSong() {
        let url = "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/x/4547366614275.jpg/300x300bb.jpg"
        XCTAssertEqual(ProfileSongLine.artworkURL(song(artwork: url))?.absoluteString, url)
    }

    /// 🔴 ジャケットが無い・空・壊れた・http のときは nil ＝ ♪ の四角を出す
    func testMissingArtworkFallsBackToNote() {
        for value in [nil, "", "   ", "not a url", "http://is1-ssl.mzstatic.com/a.jpg", "https://"] as [String?] {
            XCTAssertNil(ProfileSongLine.artworkURL(song(artwork: value)), "\(value ?? "nil") でジャケットを読みに行く")
        }
        XCTAssertEqual(ProfileSongLine.fallbackSymbol, "music.note")
        // 画面は読めないときの記号に ♪ を渡している（写真の記号を出さない）
        let view = try? source("Sources/JourneyPhoto/Features/Profile/ProfileBgmCard.swift")
        XCTAssertTrue(view?.contains("placeholderSymbol: ProfileSongLine.fallbackSymbol") == true,
                      "ジャケットが読めないときの代わりが ♪ になっていない")
    }

    /// 🔴 再生中は一時停止の印、止まっている間は再生の印
    func testPlaySymbolFollowsPlaybackState() {
        XCTAssertEqual(ProfileSongLine.playSymbol(isPlaying: false), "play.fill")
        XCTAssertEqual(ProfileSongLine.playSymbol(isPlaying: true), "pause.fill")
        let view = try? source("Sources/JourneyPhoto/Features/Profile/ProfileBgmCard.swift")
        XCTAssertTrue(view?.contains("ProfileSongLine.playSymbol(isPlaying: playing)") == true,
                      "再生の丸が再生の状態を見ていない")
    }

    /// 2行目は歌手名だけ。試聴の文字は表示しない
    func testArtistLineAndPreviewMark() {
        XCTAssertEqual(ProfileSongLine.artist(song(artwork: nil)), "米津玄師")
        XCTAssertNil(ProfileSongLine.artist(song(artist: nil, artwork: nil)))
        XCTAssertNil(ProfileSongLine.artist(song(artist: "  ", artwork: nil)))
        let view = try? source("Sources/JourneyPhoto/Features/Profile/ProfileBgmCard.swift")
        XCTAssertFalse(view?.contains("ProfileSongLine.previewLabel") == true, "試聴ラベルを表示しない")
        XCTAssertTrue(view?.contains("ProfileSongLine.brass") == true, "再生ボタンに真鍮色を使う")
        XCTAssertTrue(view?.contains("static let brass = WebTheme.accent") == true, "既存デザインシステムの真鍮アクセントを使う")
    }

    /// 押せる所は 44pt 以上・本文 12pt 以上（ジャケット 48・再生の丸 44）
    func testSizes() {
        XCTAssertEqual(ProfileBgmCard.artworkSide, 48)
        XCTAssertEqual(ProfileBgmCard.artworkRadius, 8)
        XCTAssertGreaterThanOrEqual(ProfileBgmCard.playSide, WebTheme.minTapTarget)
    }

    /// 国の並びは長いとき今までどおり1行で末尾を省く（区切りを変えても崩さない）
    func testCountriesLineStillTruncatesOnOneLine() throws {
        let view = try source("Sources/JourneyPhoto/Features/Profile/TravelRecordView.swift")
        let start = try XCTUnwrap(view.range(of: "Text(TravelRoute.countriesLine(countries))"))
        let tail = String(view[start.upperBound...].prefix(400))
        XCTAssertTrue(tail.contains(".lineLimit(1)"))
        XCTAssertTrue(tail.contains(".truncationMode(.tail)"))
    }
}
