import XCTest
@testable import JourneyPhoto

/// 再生しながら送ると重い（2026-10-28 owner・TestFlight 1.1.43）。
/// 「1秒あたり・送る1フレームあたりに、画面を描き直させる回数」を数えて見張る。
/// 実機の描画は Linux では測れないので、描き直しの**きっかけ**（時計の刻み・見張る値の書き込み・
/// 再生器の知らせ）の回数を数える
final class PlaybackScrollLoadTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private let url = URL(fileURLWithPath: "/nonexistent/perf-a.m4a")

    override func tearDown() {
        MusicPreviewPlayer.shared.stop(releaseSession: false)
        super.tearDown()
    }

    // MARK: - マイページの BGM の輪

    /// 🔴 鳴っている間でも、見えていない BGM の輪は描き直さない（毎秒 10 回 → 0 回）。
    /// 直す前は、送って画面の外へ出しても・別の札や次の画面へ移っても 0.1 秒ごとに描き直していた
    func testBgmRingStopsTickingWhenNotOnScreen() {
        let rate = ProfileBgmCard.progressTicksPerSecond
        XCTAssertEqual(rate(true, true, true, false), 10, accuracy: 0.001, "見えている間は今までどおり 0.1 秒ごと")
        XCTAssertEqual(rate(true, true, true, true), 1, accuracy: 0.001, "動きを減らすなら 1 秒ごと")
        XCTAssertEqual(rate(true, true, false, false), 0, "送って画面の外へ出しても描き直している")
        XCTAssertEqual(rate(true, false, true, false), 0, "別の札・次の画面へ移っても描き直している")
        XCTAssertEqual(rate(false, true, true, false), 0, "鳴っていないのに描き直している")

        // 1 秒（120 フレーム）かけて、輪（高さ 72）が見えている枠（高さ 800）の上へ抜けるまで送る。
        // 見える／見えないが替わるのは境目をまたいだ1回だけ（毎フレーム書き換えない）
        let size = CGSize(width: 360, height: 72)
        var visible: Bool?
        var writes = 0
        var ticks = 0.0
        for frame in 0..<120 {
            // 輪の座標で見た、見えている枠の上端（送るほど下へ＝輪が上へ抜ける）
            let top = CGFloat(frame) * 2 - 100
            let now = ProfileBgmCard.isInViewport(size: size,
                                                  visibleBounds: CGRect(x: 0, y: top, width: 393, height: 800))
            if now != visible { writes += 1; visible = now }
            ticks += rate(true, true, now, false) / 120
        }
        XCTAssertEqual(writes, 2, "見えている→見えていないの境目以外でも状態を書いている")
        XCTAssertLessThan(ticks, 10, "画面の外へ出たあとも描き直している")
        XCTAssertTrue(ProfileBgmCard.isInViewport(size: size, visibleBounds: nil), "スクロールの外は出ている扱い")
        XCTAssertTrue(ProfileBgmCard.isInViewport(size: size, visibleBounds: CGRect(x: 0, y: 71, width: 393, height: 800)),
                      "1pt でも掛かれば動かす")
        XCTAssertFalse(ProfileBgmCard.isInViewport(size: size, visibleBounds: CGRect(x: 0, y: -800, width: 393, height: 800)),
                       "枠のちょうど外（上）")
    }

    /// 輪の `TimelineView` が上の計算で止まること（計算だけあって画面が使っていない、を防ぐ）
    func testBgmRingUsesTheVisibilityToPause() throws {
        let view = try source("Sources/JourneyPhoto/Features/Profile/ProfileBgmCard.swift")
        XCTAssertTrue(view.contains("paused: Self.progressTicksPerSecond(playing: true, appeared: appeared,"),
                      "輪の時計が見えているかで止まらない")
        XCTAssertTrue(view.contains(".onAppear { appeared = true }"))
        XCTAssertTrue(view.contains(".onDisappear { appeared = false }"))
        XCTAssertTrue(view.contains("Self.isInViewport(size: proxy.size, visibleBounds: proxy.bounds(of: .scrollView))"))
        XCTAssertTrue(view.contains(".onGeometryChange(for: Bool.self)"),
                      "送るたびに変わる値（枠そのもの）を見張っている。真偽だけにする")
    }

    // MARK: - 再生器の知らせ

    /// 🔴 再生器は**値が変わったときだけ**知らせる。ストーリーの曲の流れ（鳴らす→再開→長押しで止める
    /// →離す→同じ曲の次の1本→閉じる→もう一度止める）で 23 回 → 8 回
    func testPlayerPublishesOnlyRealChanges() {
        let player = MusicPreviewPlayer.shared
        player.stop(releaseSession: false)
        let start = player.publishCount

        player.play(url, loops: true)        // 回・URL・どこで（3）
        player.setMuted(true)                // 知らせない
        player.resume()                      // 鳴っているので 0（直す前は 1）
        player.pause()                       // 1
        player.pause()                       // 0（直す前は 1）
        player.resume()                      // 1
        player.play(url, loops: true)        // 同じ曲の次の1本: 回だけ（1）
        player.resume()                      // 0
        player.stop(releaseSession: false)   // URL・どこで（2）
        player.stop(releaseSession: false)   // 何も鳴っていない: 0（直す前は 4）

        XCTAssertEqual(player.publishCount - start, 8, "変わっていない値を入れ直して、見ている画面を描き直させている")
    }

    /// 同じ曲を鳴らし直したときは「回が進んだ」ことだけは知らせる
    /// （`SongStartSheet` の ▶ ⏸ は回で見分けるので、知らせが無いと古いまま残る）
    func testReplayingTheSameSongStillAnnouncesTheNewSession() {
        let player = MusicPreviewPlayer.shared
        player.play(url)
        let before = player.publishCount
        let session = player.play(url)
        XCTAssertEqual(player.publishCount - before, 1)
        XCTAssertEqual(player.session, session)
    }

    // MARK: - プロフィールの札の行

    /// 🔴 マイページ・人のページを送っても、画面全体を作り直す値を書かない（1秒 120 フレームで 120 回 → 0 回）。
    /// 直す前は札の行の上端を `@State` に毎フレーム書いていて、そのたびに見出しと保持した全部の札が作り直された
    func testScrollingTheProfileDoesNotRewriteViewState() throws {
        let spot = ProfileTabRowSpot()
        let height: CGFloat = 44
        var writes = 0
        for frame in 0..<120 {
            let minY = 400 - CGFloat(frame) * 8
            if spot.record(CGRect(x: 0, y: minY, width: 393, height: height), height: height) != nil { writes += 1 }
        }
        XCTAssertEqual(writes, 0, "送るたびに画面の値を書いている")
        XCTAssertEqual(spot.minY, 400 - 119 * 8, "上端は控えている（替えたとき・払い始めに読む）")
        XCTAssertEqual(ProfileTabScroll.rowOverflow(rowMinY: spot.minY, visibleTop: 0), 119 * 8 - 400)
        // 文字の大きさが変わって高さが替わったときだけ書く
        XCTAssertEqual(spot.record(CGRect(x: 0, y: 0, width: 393, height: 52), height: height), 52)

        for page in ["MyPageView", "UserProfileView"] {
            let text = try source("Sources/JourneyPhoto/Features/Profile/\(page).swift")
            XCTAssertFalse(text.contains("tabRowMinY"), "\(page) が札の行の上端を見張る値に置いている")
            XCTAssertTrue(text.contains("if let height = tabRow.record(frame, height: tabRowHeight) { tabRowHeight = height }"),
                          "\(page) が札の行の位置を箱に控えていない")
        }
        let pager = try source("Sources/JourneyPhoto/Features/Profile/ProfileTabPager.swift")
        XCTAssertTrue(pager.contains("final class ProfileTabRowSpot {"), "箱を見張る形（ObservableObject）にしている")
        XCTAssertTrue(pager.contains("var rowOverflow: () -> CGFloat"), "はみ出しを値で受けている（呼ぶ側が毎フレーム書くことになる）")
    }
}
