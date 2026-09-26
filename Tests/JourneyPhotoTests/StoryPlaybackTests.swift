import XCTest
@testable import JourneyPhoto

/// ストーリー閲覧の決まりごと（`StoryPlayback`）。**Web の `StoryViewer.tsx` と
/// 同じ約束**を Linux の `swift test` で縛る。
final class StoryPlaybackTests: XCTestCase {

    private func story(_ id: String, user: String? = "u1", createdAt: String? = nil,
                       video: Bool = false) -> Story {
        var fields = [#""id":"\#(id)""#, #""src":"https://x.test/\#(id).jpg""#]
        if let user { fields.append(#""userId":"\#(user)""#) }
        if let createdAt { fields.append(#""createdAt":"\#(createdAt)""#) }
        if video { fields.append(#""mediaType":"video""#) }
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

    /// **アプリが止まっていた時間を1回の刻みに入れない。** 入れると、
    /// 戻った瞬間に表示時間を使い切って次の1本へ飛ぶ
    func testTickDeltaIsCapped() {
        XCTAssertEqual(StoryPlayback.tickDelta(0.05), 0.05, accuracy: 0.0001)
        XCTAssertEqual(StoryPlayback.tickDelta(30), StoryPlayback.maxTickSeconds)
        XCTAssertEqual(StoryPlayback.tickDelta(-2), 0)
        // 5秒の写真が、30秒止まって戻っても使い切らない
        var progress = StoryPlayback.Progress(elapsed: 1, duration: 5)
        XCTAssertEqual(progress.tick(StoryPlayback.tickDelta(30), frozen: false), .running)
    }

    /// 凍っている間は進まず、解けたら進み、使い切ったら次へ。
    func testPauseStopsElapsed() {
        var progress = StoryPlayback.Progress(duration: 1)
        XCTAssertEqual(progress.tick(0.4, frozen: true), .running)
        XCTAssertEqual(progress.elapsed, 0, "凍っている間は1ミリも進まない")
        XCTAssertEqual(progress.tick(0.4, frozen: false), .running)
        XCTAssertEqual(progress.elapsed, 0.4, accuracy: 0.0001)
        XCTAssertEqual(progress.tick(0.7, frozen: false), .advance)
        XCTAssertEqual(progress.elapsed, 1, "秒数を超えて溜めない")
    }

    // MARK: - 前後

    /// 最後は閉じる（最初に戻して回し続けない）。
    func testNextAndClose() {
        XCTAssertEqual(StoryPlayback.next(after: 1, count: 3), 2)
        XCTAssertNil(StoryPlayback.next(after: 2, count: 3))
        XCTAssertNil(StoryPlayback.next(after: 0, count: 1))
    }

    /// 始まってすぐ（0.8秒以内）の左タップだけ前へ。それ以降は最初から。
    func testLeftTapRestartsUnlessJustStarted() {
        XCTAssertEqual(StoryPlayback.leftTap(index: 1, elapsed: 1.2), .restart)
        XCTAssertEqual(StoryPlayback.leftTap(index: 1, elapsed: 0.3), .previous(0))
        XCTAssertEqual(StoryPlayback.leftTap(index: 0, elapsed: 0.3), .restart, "先頭より前は無い")
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
        XCTAssertEqual(mine, [.pause, .hideCaption], "自分は通報もブロックもできない")

        let unknownOwner = StoryPlayback.menuItems(isMine: false, isVideo: false, hasCaption: false, hasOwner: false)
        XCTAssertEqual(unknownOwner, [.pause, .report], "相手が分からなければブロックは出せない")
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
