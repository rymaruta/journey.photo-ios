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

    /// 🔴 2026-10-28 owner の決定（モック A）: 白 12% の細い縁・角 14・内側の余白 12・地は塗らない・ラベル無し
    func testFrameIsAThinBorderWithoutFill() throws {
        XCTAssertEqual(ProfileBgmCard.frameRadius, 14)
        XCTAssertEqual(ProfileBgmCard.frameRadius, JPRadius.m)
        XCTAssertEqual(ProfileBgmCard.framePadding, 12)
        XCTAssertEqual(ProfileBgmCard.frameLineWidth, JPStroke.hairline)
        let view = try source("Sources/JourneyPhoto/Features/Profile/ProfileBgmCard.swift")
        XCTAssertTrue(view.contains("static let frameColor = WebTheme.border"), "縁が白 12% の色トークンになっていない")
        XCTAssertTrue(view.contains(".strokeBorder(Self.frameColor, lineWidth: Self.frameLineWidth)"), "枠の縁が引かれていない")
        XCTAssertTrue(view.contains(".padding(Self.framePadding)"), "枠の内側の余白が無い")
        XCTAssertFalse(view.contains(".background("), "枠に地を塗っている")
        XCTAssertFalse(view.contains("Text(\"BGM\")"), "枠にラベルを付けている")
    }

    /// 🔴 再生ボタンは見た目 34pt の真鍮の輪（1px）＋13pt の印。押せる範囲は 44 のまま。色は真鍮だけ
    func testPlayRingSizesAndColor() throws {
        XCTAssertEqual(ProfileBgmCard.ringSide, 34)
        XCTAssertEqual(ProfileBgmCard.playIconSize, 13)
        XCTAssertEqual(ProfileBgmCard.ringLineWidth, 1)
        XCTAssertEqual(ProfileBgmCard.progressLineWidth, 2)
        XCTAssertEqual(ProfileBgmCard.ringTrackOpacity, 0.28, accuracy: 0.0001)
        XCTAssertEqual(ProfileBgmCard.playSide, WebTheme.minTapTarget)
        XCTAssertLessThan(ProfileBgmCard.ringSide, ProfileBgmCard.playSide)
        let view = try source("Sources/JourneyPhoto/Features/Profile/ProfileBgmCard.swift")
        XCTAssertTrue(view.contains(".frame(width: Self.playSide, height: Self.playSide)"), "再生の押せる範囲が 44 でない")
        XCTAssertTrue(view.contains(".frame(width: Self.ringSide, height: Self.ringSide)"), "輪が 34 でない")
        XCTAssertTrue(view.contains("lineCap: .round"), "進みの端が丸くない")
        XCTAssertTrue(view.contains(".rotationEffect(.degrees(-90))"), "進みが12時から始まらない")
        // 新しい色を作らない（真鍮と既存の縁の色だけ）
        XCTAssertFalse(view.contains("Color("), "新しい色を作っている")
        XCTAssertFalse(view.contains("Color.white"), "白を使っている")
    }

    /// 🔴 進みは 0〜1 に収まり、止まっていると 0。長さが読めないときは 30 秒で割る
    func testPreviewProgressIsClamped() {
        XCTAssertEqual(MusicPreviewPlayer.previewProgress(current: 0, duration: 30), 0)
        XCTAssertEqual(MusicPreviewPlayer.previewProgress(current: 15, duration: 30), 0.5, accuracy: 0.0001)
        XCTAssertEqual(MusicPreviewPlayer.previewProgress(current: 18, duration: nil), 0.6, accuracy: 0.0001)
        XCTAssertEqual(MusicPreviewPlayer.previewProgress(current: 18, duration: .nan), 0.6, accuracy: 0.0001)
        XCTAssertEqual(MusicPreviewPlayer.previewProgress(current: 18, duration: .infinity), 0.6, accuracy: 0.0001)
        XCTAssertEqual(MusicPreviewPlayer.previewProgress(current: 18, duration: 0), 0.6, accuracy: 0.0001)
        XCTAssertEqual(MusicPreviewPlayer.previewProgress(current: 45, duration: 30), 1)
        XCTAssertEqual(MusicPreviewPlayer.previewProgress(current: -3, duration: 30), 0)
        XCTAssertEqual(MusicPreviewPlayer.previewProgress(current: .nan, duration: 30), 0)
        for current in stride(from: -10.0, through: 60, by: 0.7) {
            let value = MusicPreviewPlayer.previewProgress(current: current, duration: 29.98)
            XCTAssertTrue((0...1).contains(value), "\(current) 秒で \(value)")
        }
        // 鳴っていない曲の進みは 0（止めると 0）
        let player = MusicPreviewPlayer.shared
        player.stop()
        XCTAssertEqual(player.previewProgress(for: URL(string: "https://audio-ssl.itunes.apple.com/a.m4a")), 0)
        XCTAssertEqual(player.previewProgress(for: nil), 0)
    }

    /// 🔴 進みの見張りはこの行の中だけ。再生器は進みを publish しない（マイページ全体を描き直さない）。
    /// 「動きを減らす」がオンなら 1 秒ごとに飛び飛び
    func testProgressIsReadOnlyInsideTheRow() throws {
        let view = try source("Sources/JourneyPhoto/Features/Profile/ProfileBgmCard.swift")
        XCTAssertTrue(view.contains("TimelineView(.animation(minimumInterval: reduceMotion ? Self.reducedProgressInterval"),
                      "進みを行の中の TimelineView で読んでいない・動きを減らすを見ていない")
        XCTAssertTrue(view.contains("player.previewProgress(for: song.previewURL)"))
        XCTAssertGreaterThan(ProfileBgmCard.reducedProgressInterval, ProfileBgmCard.progressInterval)
        let player = try source("Sources/JourneyPhoto/Features/Common/MusicPreviewPlayer.swift")
        let published = player.components(separatedBy: "\n").filter { $0.contains("@Published") }
        XCTAssertFalse(published.contains { $0.lowercased().contains("progress") || $0.contains("currentTime") },
                       "進みを publish している（見ている画面が毎回描き直される）")
        let page = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        XCTAssertFalse(page.contains("previewProgress"), "マイページ全体が進みを見ている")
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
