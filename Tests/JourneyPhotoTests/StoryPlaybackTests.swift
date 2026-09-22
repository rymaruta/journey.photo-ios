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
}

// MARK: - 公開範囲

final class StoryAudienceTests: XCTestCase {

    /// **「全体に公開」は送らない。** サーバーも属性を書かない形で持つので、
    /// 既にある行と同じ形に揃える
    func testEveryoneSendsNothing() {
        XCTAssertNil(StoryService.Audience.everyone.wireValue)
    }

    /// 送る値は**サーバーが受け取る綴りちょうど**（`stories.ts` の
    /// `sanitizeAudience` は "followers" しか受け取らない）
    func testFollowersSendsTheExactWord() {
        XCTAssertEqual(StoryService.Audience.followers.wireValue, "followers")
    }

    /// **3つともサーバーが守る**（`GET /stories` が実行時に落とす）
    func testThreeChoices() {
        XCTAssertEqual(StoryService.Audience.allCases.count, 3)
        XCTAssertEqual(StoryService.Audience.closeFriends.wireValue, "closeFriends")
        for choice in StoryService.Audience.allCases {
            XCTAssertFalse(choice.label.isEmpty)
            XCTAssertFalse(choice.note.isEmpty)
        }
    }
}
