import XCTest
@testable import JourneyPhoto

/// 「曲を選ぶ」（板 23）の並び・文言と、最近選んだ曲の控え
final class SongPickerTextTests: XCTestCase {

    private func song(_ n: Int, title: String? = nil) -> Photo.Song {
        Photo.Song(title: title ?? "曲\(n)", artist: "誰か", artwork: nil,
                   previewUrl: "https://audio-ssl.itunes.apple.com/\(n).m4a", trackUrl: nil)
    }

    /// 欄が空（空白だけも）なら最近選んだ曲、打っていれば検索結果
    func testRowsSwitchOnQuery() {
        let recent = [song(1), song(2)]
        let results = [song(3)]
        XCTAssertEqual(SongPickerText.rows(query: "", results: results, recent: recent), recent)
        XCTAssertEqual(SongPickerText.rows(query: "  ", results: results, recent: recent), recent)
        XCTAssertEqual(SongPickerText.rows(query: "海", results: results, recent: recent), results)
        // 打ったがまだ探していない（結果が空）なら何も出さない——最近の曲を検索結果に見せない
        XCTAssertEqual(SongPickerText.rows(query: "海", results: [], recent: recent), [])
    }

    /// 同じ試聴の URL は1行にする（`ForEach` の目印が重なると行を取り違える）
    func testRowsAreUniqueByPreview() {
        let rows = SongPickerText.rows(query: "海", results: [song(1), song(1, title: "別名"), song(2)], recent: [])
        XCTAssertEqual(rows.map(\.title), ["曲1", "曲2"])
    }

    /// 選んだ曲は先頭へ。前の同じ曲は取り除き、5曲を超えたら古い方から落とす
    func testRememberingMovesToFrontAndCaps() {
        let recent = (1...5).map { song($0) }
        let next = SongPickerText.remembering(song(3), in: recent)
        XCTAssertEqual(next.map(\.title), ["曲3", "曲1", "曲2", "曲4", "曲5"])
        let added = SongPickerText.remembering(song(6), in: recent)
        XCTAssertEqual(added.map(\.title), ["曲6", "曲1", "曲2", "曲3", "曲4"])
        XCTAssertEqual(SongPickerText.recentLimit, 5)
    }

    /// 板の文言: 注記・再生バーの1行目・鳴っている間の読み上げ「止める」
    func testWords() {
        XCTAssertEqual(SongPickerText.previewNote, "30秒の試聴だけを使います。")
        XCTAssertEqual(SongPickerText.nowPreviewing("海へ"), "海へ · 試し聴き中")
        XCTAssertEqual(SongPickerText.previewButtonLabel(isPlaying: true), "止める")
        XCTAssertEqual(SongPickerText.previewButtonLabel(isPlaying: false), "試し聴き")
    }

    /// 🔴 遅れて届いた返事は、欄が変わっていたら入れない
    /// （欄を空にしたあとに古い「見つかりませんでした」が出ていた）
    func testLateResponseIsDropped() {
        XCTAssertTrue(SongPickerText.isCurrent(sent: "海", now: "海"))
        XCTAssertTrue(SongPickerText.isCurrent(sent: "海", now: " 海 "))
        XCTAssertFalse(SongPickerText.isCurrent(sent: "海", now: ""), "欄を空にした")
        XCTAssertFalse(SongPickerText.isCurrent(sent: "海", now: "山"), "打ち直した")
    }

    /// 🔴 シートの中のバーは、鳴っている曲なら**どこで鳴らしたかに関わらず**出す。
    /// 全体のバーはシートに覆われて見えないので、前から鳴っていた曲（マイページの
    /// BGM など）を出さないと、鳴っているのに止める口が画面に無くなる
    func testPickerBarShowsAnyPlayingSong() {
        XCTAssertTrue(SongPickerText.showsBar(playingFrom: .songPicker, inSongPicker: true))
        XCTAssertTrue(SongPickerText.showsBar(playingFrom: .app, inSongPicker: true), "前から鳴っていた曲")
        XCTAssertFalse(SongPickerText.showsBar(playingFrom: nil, inSongPicker: true))
        // 全体のバー: 曲選びで鳴らした曲は出さない（閉じる途中に2本並ばない）
        XCTAssertTrue(SongPickerText.showsBar(playingFrom: .app, inSongPicker: false))
        XCTAssertFalse(SongPickerText.showsBar(playingFrom: .songPicker, inSongPicker: false))
        XCTAssertFalse(SongPickerText.showsBar(playingFrom: nil, inSongPicker: false))
    }

    /// 「· 試し聴き中」は曲選びで鳴らした曲を、シートの中で出すときだけ。
    /// 前から鳴っていた曲は試し聴きではないので題だけ
    func testPreviewingSuffixOnlyForPickerSongs() {
        XCTAssertEqual(SongPickerText.barTitle("海へ", playingFrom: .songPicker, inSongPicker: true), "海へ · 試し聴き中")
        XCTAssertEqual(SongPickerText.barTitle("海へ", playingFrom: .app, inSongPicker: true), "海へ")
        XCTAssertEqual(SongPickerText.barTitle("海へ", playingFrom: .app, inSongPicker: false), "海へ")
    }

    /// 🔴 くるくるを戻すのは最新の検索の回だけ。古い検索が遅れて終わっても、
    /// 新しい検索の途中の表示を消さない
    func testOnlyLatestSearchEndsSpinner() {
        var runs = SongPickerText.SearchRuns()
        let first = runs.begin()
        let second = runs.begin()
        XCTAssertFalse(runs.isLatest(first), "古い検索")
        XCTAssertTrue(runs.isLatest(second))
    }

    // MARK: - 控え

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    /// 覚えた曲は読み直しても残る（新しい順）
    func testStoreRemembersAcrossReads() {
        let d = defaults()
        RecentSongsStore(defaults: d).remember(song(1), userId: "u1")
        RecentSongsStore(defaults: d).remember(song(2), userId: "u1")
        XCTAssertEqual(RecentSongsStore(defaults: d).songs(userId: "u1").map(\.title), ["曲2", "曲1"])
    }

    /// 同じ端末で人が変わったら持ち越さない
    func testStoreDoesNotLeakBetweenAccounts() {
        let d = defaults()
        RecentSongsStore(defaults: d).remember(song(1), userId: "u1")
        XCTAssertEqual(RecentSongsStore(defaults: d).songs(userId: "u2"), [])
        XCTAssertEqual(RecentSongsStore(defaults: d).songs(userId: nil), [])
    }

    /// 何も選んでいない・壊れた控えは空（曲をでっち上げない）
    func testStoreEmptyOrBrokenIsEmpty() {
        let d = defaults()
        XCTAssertEqual(RecentSongsStore(defaults: d).songs(userId: "u1"), [])
        // 一度覚えてから壊す（鍵を綴り違えていれば曲が残って落ちる）
        RecentSongsStore(defaults: d).remember(song(1), userId: "u1")
        d.set(Data("壊れ".utf8), forKey: "journey-photo-recent-songs:u1")
        XCTAssertEqual(RecentSongsStore(defaults: d).songs(userId: "u1"), [])
    }
}
