import XCTest
@testable import JourneyPhoto

/// ストーリー閲覧の決まりごと（`StoryPlayback`）。**Web の `StoryViewer.tsx` と
/// 同じ約束**を Linux の `swift test` で縛る。
final class StoryPlaybackTests: XCTestCase {

    private func story(_ id: String, user: String? = "u1", createdAt: String? = nil,
                       video: Bool = false, song: String? = nil) -> Story {
        var fields = [#""id":"\#(id)""#, #""src":"https://x.test/\#(id).jpg""#]
        if let user { fields.append(#""userId":"\#(user)""#) }
        if let createdAt { fields.append(#""createdAt":"\#(createdAt)""#) }
        if video { fields.append(#""mediaType":"video""#) }
        if let song { fields.append(song) }
        let json = "{" + fields.joined(separator: ",") + "}"
        return try! JSONDecoder.api.decode(Story.self, from: Data(json.utf8))
    }

    // MARK: - 表示秒数

    /// Web の `storyDurationMs` と同じ丸め（無ければ 5・3〜15）。
    func testDurationDefaultsAndClamps() {
        XCTAssertEqual(StoryPlayback.duration(seconds: nil), 5)
        XCTAssertEqual(StoryPlayback.duration(seconds: 1), 3)
        XCTAssertEqual(StoryPlayback.duration(seconds: 60), 15)
        XCTAssertEqual(StoryPlayback.duration(seconds: 10), 10)
    }

    // MARK: - 進行バー

    /// 前は満・今は経過・後は空。
    func testSegmentFill() {
        let fills = StoryPlayback.segmentFills(count: 3, current: 1, elapsed: 2, duration: 5, isVideo: false)
        XCTAssertEqual(fills, [1.0, 0.4, 0.0])
    }

    /// 経過が秒数を超えても 1 を超えない（`sleep` の遅れで少し超える）。
    func testSegmentFillIsClamped() {
        let fills = StoryPlayback.segmentFills(count: 1, current: 0, elapsed: 9, duration: 5, isVideo: false)
        XCTAssertEqual(fills, [1.0])
    }

    /// **動画の区切りは塗らない。** 経過の出どころが無いものを動かさない
    func testVideoSegmentHasNoFakeProgress() {
        let fills = StoryPlayback.segmentFills(count: 3, current: 1, elapsed: 2, duration: 5, isVideo: true)
        XCTAssertEqual(fills, [1.0, nil, 0.0])
    }

    // MARK: - 止まる条件

    func testFrozenConditions() {
        func frozen(pressing: Bool = false, paused: Bool = false, menuOpen: Bool = false,
                    sheetOpen: Bool = false, replyFocused: Bool = false, isSending: Bool = false,
                    mediaReady: Bool = true) -> Bool {
            StoryPlayback.isFrozen(pressing: pressing, paused: paused, menuOpen: menuOpen,
                                   sheetOpen: sheetOpen, replyFocused: replyFocused,
                                   isSending: isSending, mediaReady: mediaReady)
        }
        XCTAssertFalse(frozen())
        XCTAssertTrue(frozen(pressing: true))
        XCTAssertTrue(frozen(paused: true))
        XCTAssertTrue(frozen(menuOpen: true))
        XCTAssertTrue(frozen(sheetOpen: true))
        XCTAssertTrue(frozen(replyFocused: true))
        // Web が踏んだ穴: 送信中に次へ送られ「送りました」が別の1本に出た
        XCTAssertTrue(frozen(isSending: true))
        // 絵が出る前から秒数を減らさない
        XCTAssertTrue(frozen(mediaReady: false))
        // 前面に居ない間（ホームへ戻った）は止める
        XCTAssertTrue(StoryPlayback.isFrozen(pressing: false, paused: false, menuOpen: false,
                                             sheetOpen: false, replyFocused: false, isSending: false,
                                             mediaReady: true, inBackground: true))
    }

    /// **アプリが止まっていた時間を数えない。** 数えると、戻った瞬間に表示時間を
    /// 使い切って次の1本へ飛ぶ（見回りの間が `maxTickSeconds` を超えた分は捨てる）
    func testStalledSecondsAreDiscarded() {
        XCTAssertEqual(StoryPlayback.stalledSeconds(gap: 0.05), 0)
        XCTAssertEqual(StoryPlayback.stalledSeconds(gap: 30), 30 - StoryPlayback.maxTickSeconds, accuracy: 0.0001)
        XCTAssertEqual(StoryPlayback.stalledSeconds(gap: -2), 0)
        // 1秒見て、30秒止まって戻っても、5秒の写真を使い切らない
        let t0 = Date(timeIntervalSince1970: 1_000)
        var clock = StoryPlayback.Clock()
        clock.set(running: true, at: t0)
        let back = t0.addingTimeInterval(31)
        clock.discard(StoryPlayback.stalledSeconds(gap: 30), at: back)
        XCTAssertEqual(clock.elapsed(at: back), 1 + StoryPlayback.maxTickSeconds, accuracy: 0.0001)
        XCTAssertLessThan(clock.elapsed(at: back), 5)
        // 止まっている時計には効かない
        var stopped = StoryPlayback.Clock()
        stopped.discard(10, at: back)
        XCTAssertEqual(stopped.elapsed(at: back), 0)
    }

    /// 時計は**時刻から経過を計算する**。止めている間は1ミリも進まず、動かすと続きから
    func testClockPausesAndResumes() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var clock = StoryPlayback.Clock()
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(5)), 0, "動かす前は進まない")
        XCTAssertTrue(clock.set(running: true, at: t0))
        XCTAssertFalse(clock.set(running: true, at: t0.addingTimeInterval(0.2)), "同じ向きの2回目は何もしない")
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(0.4)), 0.4, accuracy: 0.0001,
                       "2回目で動き出しの時刻を書き直していない")
        XCTAssertTrue(clock.set(running: false, at: t0.addingTimeInterval(0.4)))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(10)), 0.4, accuracy: 0.0001, "止めている間は進まない")
        clock.set(running: true, at: t0.addingTimeInterval(10))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(10.6)), 1.0, accuracy: 0.0001, "続きから")
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(9)), 0.4, accuracy: 0.0001, "時刻が戻っても減らない")
    }

    /// 🔴 **捨てるのは動いていた長さまで。** 背面から戻る合図で先に動き出し、そのあと
    /// 背面の前から眠っていた見回りが1時間の間で起きても、戻った後のバーは止まらない
    func testDiscardNeverPushesStartIntoTheFuture() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var clock = StoryPlayback.Clock()
        clock.set(running: true, at: t0)
        clock.set(running: false, at: t0.addingTimeInterval(1))       // 1秒見て背面へ
        let resumed = t0.addingTimeInterval(3_601)
        clock.set(running: true, at: resumed)                         // 戻る合図が先
        clock.discard(StoryPlayback.stalledSeconds(gap: 3_600), at: resumed.addingTimeInterval(0.01))
        XCTAssertEqual(clock.elapsed(at: resumed.addingTimeInterval(10)), 11, accuracy: 0.05,
                       "戻った後も進んでいない（動き出しが先へずれた）")
    }

    /// 頭から（左タップ・別の1本）は 0 から。動かすかは呼ぶ側が決める
    func testClockRestart() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var clock = StoryPlayback.Clock()
        clock.set(running: true, at: t0)
        // 一度止めて経過を貯めてから頭へ（貯めた分も 0 に戻ること）
        clock.set(running: false, at: t0.addingTimeInterval(2))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(3)), 2, accuracy: 0.0001)
        clock.restart(running: false, at: t0.addingTimeInterval(3))
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(9)), 0)
        clock.restart(running: true, at: t0.addingTimeInterval(9))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(9.5)), 0.5, accuracy: 0.0001)
    }

    // MARK: - 動画の位置

    /// 動画は再生器が知らせた位置で塗る。知らせが無ければ塗らない（今までどおり）
    func testVideoSegmentFillsFromReportedPosition() {
        XCTAssertEqual(StoryPlayback.segmentFills(count: 3, current: 1, elapsed: 0, duration: 5, isVideo: true,
                                                  videoFraction: 0.25)[1], 0.25)
        XCTAssertNil(StoryPlayback.segmentFills(count: 3, current: 1, elapsed: 0, duration: 5, isVideo: true,
                                                videoFraction: nil)[1])
        XCTAssertEqual(StoryPlayback.segmentFills(count: 1, current: 0, elapsed: 0, duration: 5, isVideo: true,
                                                  videoFraction: 1.7)[0], 1.0, "1 を超えない")
    }

    /// 知らせの間は時刻から伸ばす。止めている間は伸ばさない・長さを超えない・長さが分からなければ塗らない
    func testVideoProgressExtrapolates() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let playing = StoryPlayback.VideoProgress(seconds: 2, duration: 10, at: t0, playing: true)
        XCTAssertEqual(playing.seconds(at: t0.addingTimeInterval(1.5)), 3.5, accuracy: 0.0001)
        XCTAssertEqual(playing.fraction(at: t0.addingTimeInterval(3))!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(playing.seconds(at: t0.addingTimeInterval(60)), 10, "長さを超えない")
        let paused = StoryPlayback.VideoProgress(seconds: 2, duration: 10, at: t0, playing: false)
        XCTAssertEqual(paused.seconds(at: t0.addingTimeInterval(5)), 2, "止めている間は伸ばさない")
        let unknown = StoryPlayback.VideoProgress(seconds: 2, duration: .nan, at: t0, playing: true)
        XCTAssertNil(unknown.fraction(at: t0), "長さが分からなければ塗らない")
        XCTAssertNil(StoryPlayback.VideoProgress(seconds: 0, duration: 0, at: t0, playing: true).fraction(at: t0))
    }

    /// 画面を書き直すのは、ずれた・止まった・動き出した・長さが分かったときだけ
    func testVideoProgressUpdatesOnlyWhenNeeded() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let old = StoryPlayback.VideoProgress(seconds: 2, duration: 10, at: t0, playing: true)
        XCTAssertTrue(StoryPlayback.VideoProgress.needsUpdate(from: nil, to: old))
        let onTrack = StoryPlayback.VideoProgress(seconds: 2.5, duration: 10, at: t0.addingTimeInterval(0.5), playing: true)
        XCTAssertFalse(StoryPlayback.VideoProgress.needsUpdate(from: old, to: onTrack), "予想どおりなら書かない")
        let stalled = StoryPlayback.VideoProgress(seconds: 2.0, duration: 10, at: t0.addingTimeInterval(0.5), playing: true)
        XCTAssertTrue(StoryPlayback.VideoProgress.needsUpdate(from: old, to: stalled), "詰まってずれたら書く")
        let paused = StoryPlayback.VideoProgress(seconds: 2.5, duration: 10, at: t0.addingTimeInterval(0.5), playing: false)
        XCTAssertTrue(StoryPlayback.VideoProgress.needsUpdate(from: old, to: paused), "止まったら書く")
        let known = StoryPlayback.VideoProgress(seconds: 2.5, duration: 12, at: t0.addingTimeInterval(0.5), playing: true)
        XCTAssertTrue(StoryPlayback.VideoProgress.needsUpdate(from: old, to: known), "長さが替わったら書く")
    }

    /// 🔴 読み込み前の長さは NaN。`NaN != NaN` で**毎回書き直していた**（ae5d821 のレビュー）
    func testVideoProgressUnknownDurationIsStable() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let loading = StoryPlayback.VideoProgress(seconds: 0, duration: .nan, at: t0, playing: false)
        let stillLoading = StoryPlayback.VideoProgress(seconds: 0, duration: .nan, at: t0.addingTimeInterval(0.5), playing: false)
        XCTAssertFalse(StoryPlayback.VideoProgress.needsUpdate(from: loading, to: stillLoading), "分からない同士は書かない")
        let loaded = StoryPlayback.VideoProgress(seconds: 0, duration: 10, at: t0.addingTimeInterval(0.5), playing: false)
        XCTAssertTrue(StoryPlayback.VideoProgress.needsUpdate(from: loading, to: loaded), "長さが分かったら書く")
        XCTAssertTrue(StoryPlayback.VideoProgress.needsUpdate(from: loaded, to: stillLoading), "分からなくなったら書く")
    }

    // MARK: - 前後

    /// 最後は閉じる（最初に戻して回し続けない）。
    func testNextAndClose() {
        XCTAssertEqual(StoryPlayback.next(after: 1, count: 3), 2)
        XCTAssertNil(StoryPlayback.next(after: 2, count: 3))
        XCTAssertNil(StoryPlayback.next(after: 0, count: 1))
    }

    /// 始まってすぐ（0.8秒以内）の左タップだけ前へ。それ以降は最初から。
    /// 🔴 頭から見直したら、控えていた終わりを捨て、いまの1本の印も外す（見直している途中で
    /// 次へ飛ばさない・見直した回の終わりをもう一度受ける）。ほかの1本の印は残す
    func testRestartDropsThePendingEnd() {
        let after = StoryPlayback.afterRestart(pendingEnd: "v1", endedIds: ["v1", "v0"], currentId: "v1")
        XCTAssertNil(after.pendingEnd)
        XCTAssertEqual(after.endedIds, ["v0"])
    }

    /// 🔴 読めなかった動画は終わりを二度と知らせない。見直しで控えを捨てたら、合図を受けた側が
    /// **知らせ直す**——そうしないと黒い画面のまま進まない（fe1bcf4 のレビュー）
    func testFailedVideoReportsItsEndAgainOnRestart() {
        XCTAssertEqual(StoryPlayback.restartAction(mediaFailed: true), .reportEnd)
        XCTAssertEqual(StoryPlayback.restartAction(mediaFailed: false), .seekToStart)
        // 知らせ直した終わりは、見直しで印を外したので進める（止めていなければ）
        let after = StoryPlayback.afterRestart(pendingEnd: "v1", endedIds: ["v1"], currentId: "v1")
        XCTAssertFalse(after.endedIds.contains("v1"))
        XCTAssertEqual(StoryPlayback.mediaEnded(storyId: "v1", currentId: "v1", frozen: false), .advance)
    }

    func testLeftTapRestartsUnlessJustStarted() {
        XCTAssertEqual(StoryPlayback.leftTap(index: 1, elapsed: 1.2), .restart)
        XCTAssertEqual(StoryPlayback.leftTap(index: 1, elapsed: 0.3), .previous(0))
        XCTAssertEqual(StoryPlayback.leftTap(index: 0, elapsed: 0.3), .restart, "先頭より前は無い")
    }

    /// 🔴 動画と読み込み中の写真は時計が回らない。**見せ始めてからの実時間で決める**
    /// ——時計（いつも0）を渡すと、動画を3秒見てから左を押しても前の1本へ飛んでいた
    func testLeftTapElapsedUsesWallTimeForVideoAndLoadingPhoto() {
        let video = StoryPlayback.leftTapElapsed(clock: 0, sinceShown: 3, isVideo: true, mediaReady: true)
        XCTAssertEqual(video, 3)
        XCTAssertEqual(StoryPlayback.leftTap(index: 1, elapsed: video), .restart, "動画を見てしばらく経ったら頭から")
        XCTAssertEqual(StoryPlayback.leftTap(index: 0, elapsed: video, hasPreviousGroup: true), .restart,
                       "動画を見てしばらく経ったら前の人へ飛ばない")
        XCTAssertEqual(StoryPlayback.leftTapElapsed(clock: 0, sinceShown: 2, isVideo: false, mediaReady: false), 2,
                       "読み込み中の写真も実時間")
        XCTAssertEqual(StoryPlayback.leftTapElapsed(clock: 0.3, sinceShown: 5, isVideo: false, mediaReady: true), 0.3,
                       "出ている写真は今までどおり時計（止めていた間は数えない）")
    }

    // MARK: - 兄弟

    /// 他人の混じった一覧から同じ投稿者だけを古い順に。押した1本の位置も返す。
    func testSiblingsAreSameAuthorInCreatedOrder() {
        let all = [
            story("b", user: "u1", createdAt: "2026-09-20T02:00:00.000Z"),
            story("x", user: "u2", createdAt: "2026-09-20T01:30:00.000Z"),
            story("a", user: "u1", createdAt: "2026-09-20T01:00:00.000Z"),
            story("c", user: "u1", createdAt: "2026-09-20T03:00:00.000Z"),
        ]
        let group = StoryPlayback.siblings(of: all[0], in: all)
        XCTAssertEqual(group.stories.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(group.index, 1)
    }

    /// `userId` が無い行は兄弟を探しようがない——その1本だけ。
    func testSiblingsWithoutUserIdIsJustTheOne() {
        let lone = story("z", user: nil)
        let group = StoryPlayback.siblings(of: lone, in: [lone, story("a")])
        XCTAssertEqual(group.stories.map(\.id), ["z"])
        XCTAssertEqual(group.index, 0)
    }

    /// 輪は1人＝1つ。2本出した人が2人に見えない（owner 2026-09-25「わたしが2人いる」）
    func testRingsAreOnePerPerson() {
        let all = [
            story("b", user: "me", createdAt: "2026-09-25T02:00:00.000Z"),
            story("x", user: "them", createdAt: "2026-09-25T01:30:00.000Z"),
            story("a", user: "me", createdAt: "2026-09-25T01:00:00.000Z"),
            story("z", user: nil),
            story("y", user: nil),
        ]
        let rings = StoryPlayback.rings(all, isSeen: { _ in false })
        // 並びは最初に出てきた順。束の代表は一番古い1本。userId の無い行は1本ずつ
        XCTAssertEqual(rings.map(\.id), ["a", "x", "z", "y"])
    }

    /// 輪の代表は「まだ見ていない中で一番古いもの」。全部見ていれば一番古いもの
    func testRingStartsAtTheFirstUnseen() {
        let all = [
            story("a", user: "me", createdAt: "2026-09-25T01:00:00.000Z"),
            story("b", user: "me", createdAt: "2026-09-25T02:00:00.000Z"),
            story("c", user: "me", createdAt: "2026-09-25T03:00:00.000Z"),
        ]
        XCTAssertEqual(StoryPlayback.rings(all, isSeen: { $0 == "a" }).map(\.id), ["b"])
        XCTAssertEqual(StoryPlayback.rings(all, isSeen: { _ in true }).map(\.id), ["a"])
    }

    /// 通報した1本とブロックした人のぶんは端末で落とす。
    func testVisibleDropsReportedAndBlocked() {
        let all = [story("a", user: "u1"), story("b", user: "u2"), story("c", user: "u3")]
        let left = StoryPlayback.visible(all, blockedUserIds: ["u2"], reportedPhotoIds: ["c"])
        XCTAssertEqual(left.map(\.id), ["a"])
    }

    // MARK: - メニュー

    /// 押しても何も起きない項目は出さない。
    func testMenuItemsHideDeadControls() {
        let plain = StoryPlayback.menuItems(isMine: false, isVideo: false, hasCaption: false, hasOwner: true)
        XCTAssertEqual(plain, [.pause, .block, .report])
        XCTAssertFalse(plain.contains(.mute), "写真のストーリーに消す音は無い")
        XCTAssertFalse(plain.contains(.hideCaption), "消せる文字が無い（焼き込みは消せない）")

        XCTAssertTrue(StoryPlayback.menuItems(isMine: false, isVideo: true, hasCaption: false, hasOwner: true).contains(.mute))
        XCTAssertTrue(StoryPlayback.menuItems(isMine: false, isVideo: false, hasCaption: true, hasOwner: true).contains(.hideCaption))

        let mine = StoryPlayback.menuItems(isMine: true, isVideo: false, hasCaption: true, hasOwner: true)
        XCTAssertEqual(mine, [.pause, .hideCaption, .delete], "自分は通報もブロックもできず、削除ができる")
        // 残せる投稿だけ「写真として残す」。人の投稿には残す・削除を出さない
        XCTAssertEqual(StoryPlayback.menuItems(isMine: true, isVideo: false, hasCaption: false, hasOwner: true,
                                               canKeep: true), [.pause, .keep, .delete])
        let theirs = StoryPlayback.menuItems(isMine: false, isVideo: false, hasCaption: false, hasOwner: true,
                                             canKeep: true)
        XCTAssertFalse(theirs.contains(.keep) || theirs.contains(.delete))
        // ハイライトの中では残す・削除を出さない（以前も無かった操作）
        XCTAssertEqual(StoryPlayback.menuItems(isMine: true, isVideo: true, hasCaption: false, hasOwner: true,
                                               canKeep: true, inHighlight: true), [.pause, .mute])
    }

    /// 上の「…」。自分の投稿は足元に「…」があるので、ハイライトで音があるときだけ
    func testTopMenuIsNotDoubledForOwnStories() {
        XCTAssertTrue(StoryPlayback.showsTopMenu(isMine: false, inHighlight: false, hasAudio: false))
        XCTAssertTrue(StoryPlayback.showsTopMenu(isMine: false, inHighlight: true, hasAudio: false))
        XCTAssertFalse(StoryPlayback.showsTopMenu(isMine: true, inHighlight: false, hasAudio: true),
                       "足元の「…」と上下に2つ並ぶ")
        XCTAssertFalse(StoryPlayback.showsTopMenu(isMine: true, inHighlight: true, hasAudio: false))
        XCTAssertTrue(StoryPlayback.showsTopMenu(isMine: true, inHighlight: true, hasAudio: true),
                      "ハイライトでは音を消す口がここにしか無い")

        let unknownOwner = StoryPlayback.menuItems(isMine: false, isVideo: false, hasCaption: false, hasOwner: false)
        XCTAssertEqual(unknownOwner, [.pause, .report], "相手が分からなければブロックは出せない")
    }

    // MARK: - 曲

    private let songJSON = #""song":{"title":"海へ","artist":"誰か","previewUrl":"https://audio-ssl.itunes.apple.com/p.m4a"}"#

    /// 曲が付いていれば鳴らす。題の無い曲は鳴らさない（曲名の行も出ない）
    func testSongURL() {
        XCTAssertEqual(StoryPlayback.songURL(for: story("a", song: songJSON))?.absoluteString,
                       "https://audio-ssl.itunes.apple.com/p.m4a")
        XCTAssertNil(StoryPlayback.songURL(for: story("b")))
        let untitled = #""song":{"title":"  ","previewUrl":"https://audio-ssl.itunes.apple.com/p.m4a"}"#
        XCTAssertNil(StoryPlayback.songURL(for: story("c", song: untitled)))
    }

    /// 音源は iTunes の配信元だけ。**開いた瞬間に取りに行く**ので、任意の URL を
    /// 通すと開いた人の IP が外へ渡る（Web の `safeSongPreviewUrl` と同じ規則）
    func testSongURLRejectsForeignHosts() {
        func url(_ s: String) -> String { #""song":{"title":"海へ","previewUrl":"\#(s)"}"# }
        XCTAssertNotNil(StoryPlayback.songURL(for: story("a", song: url("https://audio-ssl.itunes.apple.com/x.m4a"))))
        XCTAssertNotNil(StoryPlayback.songURL(for: story("b", song: url("https://a1.mzstatic.com/x.m4a"))))
        XCTAssertNil(StoryPlayback.songURL(for: story("c", song: url("https://evil-mzstatic.com/x.m4a"))),
                     "末尾一致では通さない")
        XCTAssertNil(StoryPlayback.songURL(for: story("d", song: url("https://tracker.example/x.m4a"))))
        XCTAssertNil(StoryPlayback.songURL(for: story("e", song: url("http://audio-ssl.itunes.apple.com/x.m4a"))),
                     "https だけ")
    }

    /// **期限（24時間）を過ぎた1本は、取れなかった回に前の一覧を残すときも落とす**
    /// （日をまたいで戻ると昨日の輪が並んだままだった）
    func testAfterLoadDropsExpiredStories() {
        func withExpiry(_ id: String, _ iso: String) -> Story {
            let json = #"{"id":"\#(id)","src":"https://x.test/\#(id).jpg","userId":"u1","expiresAt":"\#(iso)"}"#
            return try! JSONDecoder.api.decode(Story.self, from: Data(json.utf8))
        }
        let previous = [withExpiry("old", "2000-01-01T00:00:00.000Z"),
                        withExpiry("live", "2999-01-01T00:00:00.000Z")]
        XCTAssertEqual(StoryPlayback.afterLoad(fetched: nil, previous: previous, sameViewer: true,
                                               blockedUserIds: [], reportedPhotoIds: []).map(\.id), ["live"],
                       "期限の切れた輪が残っている")
        // 取れた一覧は端末の時計で絞らない（サーバーが絞っている。時計が進んだ端末で消えた）
        XCTAssertEqual(StoryPlayback.afterLoad(fetched: previous, previous: [], sameViewer: true,
                                               blockedUserIds: [], reportedPhotoIds: [],
                                               now: Date(timeIntervalSince1970: 4_102_444_800 * 10)).map(\.id),
                       ["old", "live"], "取れた一覧を端末の時計で消している")
    }

    /// **動画の終わりは、見ている1本の・止めていない間だけ進める**
    /// （読めない動画の失敗はブロックの確認中にも届き、確認が次の投稿者に効いた）
    func testMediaEndedOnlyAdvancesTheCurrentUnfrozenStory() {
        XCTAssertEqual(StoryPlayback.mediaEnded(storyId: "a", currentId: "a", frozen: false), .advance)
        XCTAssertEqual(StoryPlayback.mediaEnded(storyId: "a", currentId: "a", frozen: true), .hold,
                       "止めている間に次へ進めている")
        XCTAssertEqual(StoryPlayback.mediaEnded(storyId: "a", currentId: "b", frozen: false), .ignore,
                       "前の1本の知らせ（2回目）で1本飛ばしている")
        XCTAssertEqual(StoryPlayback.mediaEnded(storyId: "a", currentId: nil, frozen: false), .ignore)
    }

    /// **読み上げ（VoiceOver）が動いている間は、ひとりでに次へ送らない**
    /// （写真の秒数を使い切っても・動画が終わっても。送るのは読み上げの「次へ」）
    func testVoiceOverNeverAutoAdvances() {
        XCTAssertTrue(StoryPlayback.autoAdvances(voiceOver: false))
        XCTAssertFalse(StoryPlayback.autoAdvances(voiceOver: true))
        XCTAssertTrue(StoryPlayback.timeUp(elapsed: 5, duration: 5, frozen: false,
                                           messageShown: false, voiceOver: false))
        XCTAssertFalse(StoryPlayback.timeUp(elapsed: 60, duration: 5, frozen: false,
                                            messageShown: false, voiceOver: true),
                       "読み上げ中に写真の秒数で次へ送っている")
        XCTAssertFalse(StoryPlayback.timeUp(elapsed: 4.9, duration: 5, frozen: false,
                                            messageShown: false, voiceOver: false))
        XCTAssertFalse(StoryPlayback.timeUp(elapsed: 9, duration: 5, frozen: true,
                                            messageShown: false, voiceOver: false))
        XCTAssertFalse(StoryPlayback.timeUp(elapsed: 9, duration: 5, frozen: false,
                                            messageShown: true, voiceOver: false))
        XCTAssertEqual(StoryPlayback.mediaEnded(storyId: "a", currentId: "a", frozen: false,
                                                voiceOver: true), .ignore,
                       "読み上げ中に動画の終わりで次へ送っている")
        XCTAssertEqual(StoryPlayback.mediaEnded(storyId: "a", currentId: "a", frozen: false,
                                                voiceOver: false), .advance)
    }

    /// 読み直しに失敗したら前の輪を残す。ただし絞り込みはかけ直し、
    /// 見ている人が変わっていたら空にする
    func testAfterLoadKeepsPreviousOnFailure() {
        let previous = [story("a", user: "u1"), story("b", user: "u2")]
        let fresh = [story("c", user: "u3")]
        XCTAssertEqual(StoryPlayback.afterLoad(fetched: fresh, previous: previous, sameViewer: true,
                                               blockedUserIds: [], reportedPhotoIds: []).map(\.id), ["c"])
        XCTAssertEqual(StoryPlayback.afterLoad(fetched: nil, previous: previous, sameViewer: true,
                                               blockedUserIds: [], reportedPhotoIds: []).map(\.id), ["a", "b"],
                       "圏外で閉じても輪を消さない")
        XCTAssertEqual(StoryPlayback.afterLoad(fetched: nil, previous: previous, sameViewer: true,
                                               blockedUserIds: ["u2"], reportedPhotoIds: []).map(\.id), ["a"],
                       "圏外でブロックした人の輪は消す")
        XCTAssertEqual(StoryPlayback.afterLoad(fetched: nil, previous: previous, sameViewer: false,
                                               blockedUserIds: [], reportedPhotoIds: []), [],
                       "別の人に切り替わったら前の人の輪を見せない")
    }

    /// 曲のある写真にも「音を消す」を出す（Web の `hasAudio = isVideo || !!item.song`）
    func testMenuOffersMuteWhenSongAttached() {
        XCTAssertTrue(StoryPlayback.menuItems(isMine: false, isVideo: false, hasSong: true,
                                              hasCaption: false, hasOwner: true).contains(.mute))
    }

    /// 曲のある動画は動画の音を常に消す（2つ重ねて鳴らさない）
    func testVideoMutedWhenSongAttached() {
        XCTAssertTrue(StoryPlayback.videoMuted(muted: false, hasSong: true))
        XCTAssertTrue(StoryPlayback.videoMuted(muted: true, hasSong: false))
        XCTAssertFalse(StoryPlayback.videoMuted(muted: false, hasSong: false))
    }

    // MARK: - 時刻

    /// 「2時間前」。読めない・未来は出さない（「0分前」を書かない）。
    func testAgoFormatting() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let twoHoursAgo = "2027-01-15T06:00:00.000Z" // 1_800_000_000 は 08:00:00Z
        XCTAssertEqual(StoryPlayback.ago(from: twoHoursAgo, now: now), L("2時間前", "2h ago"))
        XCTAssertNil(StoryPlayback.ago(from: "not a date", now: now))
        XCTAssertNil(StoryPlayback.ago(from: nil, now: now))
        XCTAssertNil(StoryPlayback.ago(from: "2027-01-15T09:00:00.000Z", now: now), "未来は出さない")
    }

    /// 小数秒の無い ISO8601 も読める（片方だけだと時刻が丸ごと消える）。
    func testAgoReadsIsoWithoutFractionalSeconds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(StoryPlayback.ago(from: "2027-01-15T07:55:00Z", now: now), L("5分前", "5m ago"))
    }

    // MARK: - スワイプ（モック7・最後に残っていた ⛔）

    /// **払った向きと進む向きを合わせる**（左へ払う＝次。紙をめくる向き）
    func testSwipeDirection() {
        XCTAssertEqual(StoryPlayback.swipe(dx: -120, dy: 0), .next)
        XCTAssertEqual(StoryPlayback.swipe(dx: 120, dy: 0), .back)
    }

    /// 下へ払うと閉じる
    func testSwipeDownCloses() {
        XCTAssertEqual(StoryPlayback.swipe(dx: 0, dy: 120), .close)
    }

    /// 🔴 **上への払いは何もしない。** モックに無いし、他のアプリでは
    /// 「詳細を開く」に割り当てられている——同じ動きで違うことが起きる方が悪い
    func testSwipeUpDoesNothing() {
        XCTAssertEqual(StoryPlayback.swipe(dx: 0, dy: -120), .ignore)
    }

    /// **短い払いは指の揺れ。** 押しただけで送られない
    func testShortSwipeIsIgnored() {
        XCTAssertEqual(StoryPlayback.swipe(dx: -20, dy: 0), .ignore)
        XCTAssertEqual(StoryPlayback.swipe(dx: 0, dy: 20), .ignore)
        XCTAssertEqual(StoryPlayback.swipe(dx: 0, dy: 0), .ignore)
    }

    /// 🔴 **斜めは何もしない。** 「次へ」と読むと、閉じようとして進む
    /// ——戻る手が無い操作ほど慎重に倒す
    func testDiagonalIsIgnored() {
        XCTAssertEqual(StoryPlayback.swipe(dx: -100, dy: 100), .ignore)
        XCTAssertEqual(StoryPlayback.swipe(dx: 100, dy: 90), .ignore)
    }

    /// 境目ちょうどは通す（44pt＝押せるものの最小）
    func testThresholdIsInclusive() {
        XCTAssertEqual(StoryPlayback.swipe(dx: -StoryPlayback.swipeThreshold, dy: 0), .next)
        XCTAssertEqual(StoryPlayback.swipe(dx: 0, dy: StoryPlayback.swipeThreshold), .close)
    }

    /// 返信の候補は板の3つ。空の一言は送らない
    func testQuickRepliesMatchTheBoard() {
        XCTAssertEqual(StoryPlayback.quickReplies, ["きれい", "行ってみたい", "どこですか？"])
        XCTAssertFalse(StoryPlayback.quickReplies.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        XCTAssertEqual(StoryPlayback.quickReplies.count, StoryPlayback.quickRepliesEnglish.count)
    }

    /// 止め方で札の言い方を変える（メニューで止めた人に「指を離すと」と言わない）
    func testPausedNoteDependsOnHowItWasPaused() {
        XCTAssertNotEqual(StoryPlayback.pausedNote(pressing: true),
                          StoryPlayback.pausedNote(pressing: false))
    }

    /// 🔴 **触れただけでは隠さない。** 長押しが決まるまで何も変えない
    /// （以前はタップのたびに見出しと足元が点滅した）
    func testTapDoesNotHideTheChrome() {
        let c = StoryPlayback.chrome(longHeld: false, paused: false, overlayOpen: false)
        XCTAssertFalse(c.hidesChrome)
        XCTAssertFalse(c.showsPill)
    }

    /// 長押しの間は見出しと足元を隠し、「指を離すと」の札
    func testLongHoldHidesChrome() {
        let c = StoryPlayback.chrome(longHeld: true, paused: false, overlayOpen: false)
        XCTAssertTrue(c.hidesChrome)
        XCTAssertTrue(c.showsPill)
        XCTAssertTrue(c.pillSaysRelease)
    }

    /// 🔴 **メニューで止めたときは見出しを残す**（隠すと ✕ と「再開」に届かない）
    func testMenuPauseKeepsTheHeader() {
        let c = StoryPlayback.chrome(longHeld: false, paused: true, overlayOpen: false)
        XCTAssertFalse(c.hidesChrome)
        XCTAssertTrue(c.showsPill)
        XCTAssertFalse(c.pillSaysRelease)
    }

    /// 止めている間に長押ししても、離して続くとは言わない
    func testHoldWhilePausedDoesNotPromiseRelease() {
        let c = StoryPlayback.chrome(longHeld: true, paused: true, overlayOpen: false)
        XCTAssertFalse(c.pillSaysRelease)
    }

    /// メニューや確認を開いている間は札を出さない
    func testOverlayWins() {
        let c = StoryPlayback.chrome(longHeld: true, paused: true, overlayOpen: true)
        XCTAssertFalse(c.hidesChrome)
        XCTAssertFalse(c.showsPill)
    }

    /// 「あと N 時間で消えます」。1時間を切ったら分、過ぎたら出さない
    func testRemaining() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func iso(_ seconds: TimeInterval) -> String {
            let f = ISO8601DateFormatter()
            return f.string(from: now.addingTimeInterval(seconds))
        }
        XCTAssertEqual(StoryPlayback.remaining(until: iso(22 * 3600 + 120), now: now),
                       L("あと 22 時間で消えます", "Disappears in 22h"))
        XCTAssertEqual(StoryPlayback.remaining(until: iso(30 * 60 + 5), now: now),
                       L("あと 30 分で消えます", "Disappears in 30m"))
        XCTAssertNil(StoryPlayback.remaining(until: iso(-60), now: now))
        XCTAssertNil(StoryPlayback.remaining(until: "not a date", now: now))
    }

    /// 🔴 **返信の数に反応を混ぜない。** 反応の画面と数が割れていた
    func testRepliesExcludeReactions() throws {
        let json = #"[{"uid":"a","text":"きれい","t":"1"},{"uid":"b","emoji":"❤️","t":"2"},{"uid":"c","text":"どこ？","t":"3"}]"#
        let replies = try JSONDecoder.api.decode([StoryReply].self, from: Data(json.utf8))
        XCTAssertEqual(replies.textReplies.map(\.body), ["きれい", "どこ？"])
        XCTAssertEqual(replies.reactionCount, 1)
    }

    /// 🔴 **♡ を何度押しても1人1つ。** サーバーは1件ずつ足す（1人10件まで）
    func testReactionsCountOncePerPerson() throws {
        let json = #"[{"uid":"a","emoji":"❤️","t":"1"},{"uid":"a","emoji":"❤️","t":"2"},{"uid":"a","emoji":"😂","t":"3"},{"uid":"b","emoji":"❤️","t":"4"},{"emoji":"❤️","t":"5"}]"#
        let replies = try JSONDecoder.api.decode([StoryReply].self, from: Data(json.utf8))
        XCTAssertEqual(replies.reactionCount, 3, "a を3人に数えた")
    }

    /// 反応の画面の副題と、ハイライトの日付（端末の時刻帯で読む）
    func testPostedAtAndDotDate() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(StoryPlayback.postedAt("2026-09-24T09:20:00.000Z", timeZone: tokyo),
                       L("9月24日 18:20に投稿", "Posted Sep 24, 18:20"))
        XCTAssertEqual(StoryPlayback.dotDate("2026-09-11T20:00:00Z", timeZone: tokyo), "2026.09.12")
        XCTAssertNil(StoryPlayback.postedAt(nil))
        XCTAssertNil(StoryPlayback.dotDate("?"))
    }

    /// 🔴 **自分は先頭、残りは未読 → 既読**（板 27）。同じ組の中はサーバーの並びのまま
    func testRingsOrderMeFirstThenUnseen() throws {
        func story(_ id: String, _ user: String) throws -> Story {
            try JSONDecoder.api.decode(Story.self, from: Data(
                #"{"id":"\#(id)","src":"https://x.test/\#(id).jpg","userId":"\#(user)"}"#.utf8))
        }
        let rings = try [story("s1", "a"), story("s2", "me"), story("s3", "b"), story("s4", "c")]
        let seen: Set<String> = ["s1"]
        let ordered = StoryPlayback.orderedRings(rings, me: "me", isUnseen: { !seen.contains($0.id) })
        XCTAssertEqual(ordered.mine?.id, "s2")
        XCTAssertEqual(ordered.others.map(\.id), ["s3", "s4", "s1"])
        // ログインしていなければ自分の輪は無い
        XCTAssertNil(StoryPlayback.orderedRings(rings, me: nil, isUnseen: { _ in true }).mine)
    }

    /// 輪を本数で区切る。1本は切れ目なし、2本は半分ずつで間に切れ目
    func testRingSegments() {
        XCTAssertEqual(StoryPlayback.ringSegments(count: 1).count, 1)
        XCTAssertEqual(StoryPlayback.ringSegments(count: 1)[0].start, 0)
        XCTAssertEqual(StoryPlayback.ringSegments(count: 1)[0].end, 1)
        let two = StoryPlayback.ringSegments(count: 2, gap: 0.02)
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two[0].end, 0.49, accuracy: 0.0001)
        XCTAssertEqual(two[1].start, 0.51, accuracy: 0.0001)
    }
}
