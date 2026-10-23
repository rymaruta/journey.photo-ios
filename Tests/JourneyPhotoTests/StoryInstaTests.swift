import XCTest
@testable import JourneyPhoto

/// ストーリーを「インスタみたいに使いやすく」した第1弾（2026-10-22）の見張り。
///
/// 決まり（左タップの行き先・♡ の先塗りと戻し・上への払い・どの顔に輪が出るか・先読み）は
/// 関数をそのまま試す。画面の配線は Linux で描けないので、元のファイルを読んで見る
/// （`StoryViewerV2FixTests` と同じ）。
final class StoryInstaTests: XCTestCase {

    private func story(_ id: String, user: String? = "u1", createdAt: String? = nil,
                       video: Bool = false) -> Story {
        var fields = [#""id":"\#(id)""#, #""src":"https://x.test/\#(id).jpg""#]
        if let user { fields.append(#""userId":"\#(user)""#) }
        if let createdAt { fields.append(#""createdAt":"\#(createdAt)""#) }
        if video { fields.append(#""mediaType":"video""#) }
        let json = "{" + fields.joined(separator: ",") + "}"
        return try! JSONDecoder.api.decode(Story.self, from: Data(json.utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `name` から次の宣言までを切り出す
    private func member(_ name: String, in text: String,
                        file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = text.range(of: name) else {
            XCTFail("\(name) が無い", file: file, line: line)
            return ""
        }
        let rest = text[start.upperBound...]
        let ends = ["\n    private func ", "\n    private var ", "\n    func ", "\n    var ",
                    "\n    static ", "\n    @MainActor static ", "\n    private static ", "\n}"]
            .compactMap { rest.range(of: $0)?.lowerBound }
        return String(rest[..<(ends.min() ?? rest.endIndex)])
    }

    // MARK: - 2. 左タップは必ず前の1本へ

    /// 🔴 **経過に関係なく1つ前へ**（以前は 0.8 秒を過ぎると今の1本の頭へ戻り、前へ戻れなかった）。
    /// 束の先頭なら前の人、前の人もいなければ頭から
    func testLeftTapGoesToPreviousStory() {
        XCTAssertEqual(StoryPlayback.leftTap(index: 3, hasPreviousGroup: false), .previous(2))
        XCTAssertEqual(StoryPlayback.leftTap(index: 1, hasPreviousGroup: true), .previous(0))
        XCTAssertEqual(StoryPlayback.leftTap(index: 0, hasPreviousGroup: true), .previousGroup,
                       "1本目なら前の人へ")
        XCTAssertEqual(StoryPlayback.leftTap(index: 0, hasPreviousGroup: false), .restart,
                       "前が何も無いときだけ頭から")
    }

    /// 閲覧画面は経過を渡さない（時計や見せ始めた時刻で行き先を変えない）
    func testViewerLeftTapDoesNotLookAtElapsed() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        let body = member("private func leftTap() {", in: viewer)
        XCTAssertTrue(body.contains("StoryPlayback.leftTap(index: index, hasPreviousGroup: onGroupBack != nil)"))
        XCTAssertFalse(body.contains("elapsed"), "左タップがまだ経過を見ている")
        XCTAssertFalse(viewer.contains("shownAt"), "左タップのためだけの時刻が残っている")
    }

    /// 当たりは**左 1/3・右 2/3**（真ん中を押したら次へ）
    func testLeftTapZoneIsNarrow() throws {
        XCTAssertEqual(StoryPlayback.leftTapFraction, 1.0 / 3.0, accuracy: 0.0001)
        // 画面は左の当たりの幅をこの割合で決める
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains(".frame(width: geo.size.width * StoryPlayback.leftTapFraction)"))
    }

    // MARK: - 3. ♡ をすぐ塗る

    /// 🔴 **返事を待たずに塗り、送れなかったら戻す**。二重には送らない（印があるので）
    func testHeartFillsBeforeTheServerAnswers() {
        var sent = StoryPlayback.SentReactions()
        XCTAssertTrue(sent.begin("❤️", on: "s1"))
        XCTAssertEqual(sent.emoji(on: "s1"), "❤️", "送る前に塗っていない")
        XCTAssertFalse(sent.begin("❤️", on: "s1"), "返事を待つ間の2回目を送った")
        XCTAssertFalse(sent.begin("👏", on: "s1"), "別の絵文字でも2回目は送らない")
        // 送れなかった → 塗りを戻し、もう一度押せる
        sent.rollback("❤️", on: "s1")
        XCTAssertNil(sent.emoji(on: "s1"), "失敗したのに塗ったまま")
        XCTAssertTrue(sent.shouldSend(on: "s1"))
        // 別の絵文字の印は、違う絵文字の失敗で外さない
        XCTAssertTrue(sent.begin("😍", on: "s2"))
        sent.rollback("❤️", on: "s2")
        XCTAssertEqual(sent.emoji(on: "s2"), "😍")
    }

    /// 送れたときの文字の知らせは ♡ には出さない（塗りと弾みで分かる）。失敗は何が送れなかったかを言う
    func testReactionMessages() {
        XCTAssertFalse(StoryPlayback.announcesReactionSent("❤️"))
        XCTAssertTrue(StoryPlayback.announcesReactionSent("👏"))
        XCTAssertEqual(StoryPlayback.reactionFailedMessage("❤️"),
                       L("いいねを送れませんでした", "Couldn't send your like"))
        XCTAssertEqual(StoryPlayback.reactionFailedMessage("😮"),
                       L("😮 を送れませんでした", "Couldn't send 😮"))
    }

    /// 🔴 **送っている間も再生を止めない**——反応は `isSending` を立てない（立てると時計が止まり、
    /// 前後へも送れない）。先に塗って弾ませ、失敗したら戻して並びにも知らせる
    func testViewerReactsOptimisticallyWithoutPausing() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        let body = member("private func sendReaction(_ emoji: String, to story: Story) async {", in: viewer)
        XCTAssertFalse(body.contains("isSending = true"), "♡ を送る間に再生を止めている")
        XCTAssertFalse(body.contains("guard !isSending"), "返信を送っている間の ♡ を黙って捨てている")
        let begin = try XCTUnwrap(body.range(of: "sentReactions.begin(emoji, on: story.id)"))
        let pop = try XCTUnwrap(body.range(of: "heartPops += 1"))
        let send = try XCTUnwrap(body.range(of: "environment.stories.react("))
        XCTAssertLessThan(begin.lowerBound, send.lowerBound, "返事を待ってから塗っている")
        XCTAssertLessThan(pop.lowerBound, send.lowerBound, "返事を待ってから弾ませている")
        XCTAssertTrue(body.contains("sentReactions.rollback(emoji, on: story.id)"), "失敗しても塗ったまま")
        XCTAssertTrue(body.contains("onReactionFailed(story.id, emoji)"), "並びの印を戻していない")
        // 弾みと振動（iOS 17 の `sensoryFeedback`）
        XCTAssertTrue(viewer.contains(".sensoryFeedback(.impact(weight: .light), trigger: heartPops)"))
        XCTAssertTrue(viewer.contains(".scaleEffect(heartPopped ? StoryViewerMetrics.heartPopScale : 1)"))
        // 並び（人を回して戻っても塗りを忘れない・失敗したら外す）
        let reel = try source("Features/Stories/StoryReelView.swift")
        XCTAssertTrue(reel.contains("sentReactions.rollback(emoji, on: storyId)"))
    }

    // MARK: - 4. 反応の絵文字・上へ払う

    /// 上へ払ったら: 人の投稿は返信欄、自分の投稿は見た人の一覧。足元に無い物は開かない
    func testSwipeUpAction() {
        XCTAssertEqual(StoryPlayback.swipe(dx: 5, dy: -120), .up)
        XCTAssertEqual(StoryPlayback.swipeUpAction(isMine: false, acceptsReplies: true, expired: false,
                                                   inHighlight: false), .reply)
        XCTAssertEqual(StoryPlayback.swipeUpAction(isMine: false, acceptsReplies: false, expired: false,
                                                   inHighlight: false), .none, "返信を受けない投稿で返信欄を開いた")
        XCTAssertEqual(StoryPlayback.swipeUpAction(isMine: true, acceptsReplies: true, expired: false,
                                                   inHighlight: false), .insights)
        XCTAssertEqual(StoryPlayback.swipeUpAction(isMine: true, acceptsReplies: true, expired: true,
                                                   inHighlight: false), .none, "期限切れは見た人の記録が無い")
        XCTAssertEqual(StoryPlayback.swipeUpAction(isMine: false, acceptsReplies: true, expired: false,
                                                   inHighlight: true), .none, "ハイライトには返信欄が無い")
        // ♡ の長押しの並びが開いていたら、閉じるだけ（返信欄も見た人の一覧も開かない）
        XCTAssertEqual(StoryPlayback.swipeUpAction(isMine: false, acceptsReplies: true, expired: false,
                                                   inHighlight: false, reactionsOpen: true), .closeReactions)
        XCTAssertEqual(StoryPlayback.swipeUpAction(isMine: true, acceptsReplies: true, expired: false,
                                                   inHighlight: false, reactionsOpen: true), .closeReactions)
        // 上へ払って離したときは、並びの縮みを戻す動き（時計を止める）を走らせない
        XCTAssertFalse(StoryReel.needsSettle(dy: -120))
        XCTAssertFalse(StoryReel.needsSettle(dy: 0))
        XCTAssertTrue(StoryReel.needsSettle(dy: 40))
    }

    /// 🔴 上への払いは**並びの中でも閲覧画面が受ける**（外の並びは上を受けないので、
    /// `swipesHandledOutside` の手前で拾わないと並びの中では効かない）
    func testSwipeUpIsHandledInsideTheReel() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        let up = try XCTUnwrap(viewer.range(of: "if swipe == .up { swipeUp(); return }"))
        let outside = try XCTUnwrap(viewer.range(of: "guard !swipesHandledOutside else { return }\n                    switch swipe {"))
        XCTAssertLessThan(up.lowerBound, outside.lowerBound)
        let body = member("private func swipeUp() {", in: viewer)
        XCTAssertTrue(body.contains("reactionsOpen: showReactions"), "反応の並びが開いているかを渡していない")
        XCTAssertTrue(body.contains("case .closeReactions: showReactions = false"))
        XCTAssertTrue(body.contains("case .reply: replyFocused = true"))
        XCTAssertTrue(body.contains("case .insights: showInsights = true"))
        // 外の並びは上を受けない（閲覧画面と取り合わない）
        XCTAssertNil(StoryReel.axis(dx: 5, dy: -120))
    }

    /// 返信欄に入ったら、入力欄の上に反応の6つ（長押しの並びも残す）
    func testReplyFieldShowsReactionRow() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        let footer = member("private func footer(for story: Story) -> some View {", in: viewer)
        let row = try XCTUnwrap(footer.range(of: "if replyFocused {\n                    replyReactionRow(for: story)"),
                                "返信欄に入っても絵文字の列が出ない")
        let field = try XCTUnwrap(footer.range(of: "TextField(L(\"返信する\", \"Reply\")"))
        XCTAssertLessThan(row.lowerBound, field.lowerBound, "絵文字の列は入力欄の上")
        XCTAssertTrue(footer.contains("showReactions = true"), "♡ の長押しの並びを消した")
        let rowBody = member("private func replyReactionRow(for story: Story) -> some View {", in: viewer)
        XCTAssertTrue(rowBody.contains("ForEach(StoryService.reactions"))
        XCTAssertTrue(rowBody.contains("minHeight: WebTheme.minTapTarget"), "押せる高さが 44 に満たない")
        XCTAssertTrue(rowBody.contains("await sendReaction(emoji, to: story)"))
        XCTAssertEqual(StoryService.reactions.count, 6)
    }

    // MARK: - 1. 顔の輪

    /// どの顔に輪が出るか: **ストーリーがある人だけ**。未見があれば真鍮、全部見ていれば白。
    /// 押すと**まだ見ていない中で一番古い1本**から（ホームの輪と同じ）
    func testPersonRing() {
        let all = [
            story("a2", user: "u1", createdAt: "2026-10-22T02:00:00.000Z"),
            story("b1", user: "u2", createdAt: "2026-10-22T01:30:00.000Z"),
            story("a1", user: "u1", createdAt: "2026-10-22T01:00:00.000Z"),
            story("a3", user: "u1", createdAt: "2026-10-22T03:00:00.000Z"),
        ]
        let seen: Set<String> = ["a1"]
        let ring = StoryPlayback.personRing(userId: "u1", in: all, isSeen: { seen.contains($0) })
        XCTAssertEqual(ring?.group.stories.map(\.id), ["a1", "a2", "a3"], "その人の分だけ・古い順")
        XCTAssertEqual(ring?.group.start, 1, "見た1本を飛ばして、まだ見ていない1本から")
        XCTAssertEqual(ring?.unseen, true)
        XCTAssertEqual(ring?.count, 3)
        // 全部見た → 白の輪・一番古い1本から
        let allSeen = StoryPlayback.personRing(userId: "u1", in: all, isSeen: { _ in true })
        XCTAssertEqual(allSeen?.unseen, false)
        XCTAssertEqual(allSeen?.group.start, 0)
        // ストーリーの無い人・分からない人は輪を出さない（顔は今までどおり）
        XCTAssertNil(StoryPlayback.personRing(userId: "u9", in: all, isSeen: { _ in false }))
        XCTAssertNil(StoryPlayback.personRing(userId: nil, in: all, isSeen: { _ in false }))
        XCTAssertNil(StoryPlayback.personRing(userId: "", in: all, isSeen: { _ in false }))
        XCTAssertNil(StoryPlayback.personRing(userId: "u1", in: [], isSeen: { _ in false }))
    }

    /// 一覧は使い回す（1分以内に読んだ控えは読み直さない）。人が替わったら必ず読む
    func testRingDirectoryRefresh() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(StoryPlayback.needsRingRefresh(fetchedAt: nil, sameViewer: true, now: now))
        XCTAssertFalse(StoryPlayback.needsRingRefresh(fetchedAt: now.addingTimeInterval(-30), sameViewer: true, now: now))
        XCTAssertTrue(StoryPlayback.needsRingRefresh(fetchedAt: now.addingTimeInterval(-61), sameViewer: true, now: now))
        XCTAssertTrue(StoryPlayback.needsRingRefresh(fetchedAt: now, sameViewer: false, now: now),
                      "前の人の一覧を使った")
        XCTAssertTrue(StoryPlayback.needsRingRefresh(fetchedAt: now.addingTimeInterval(120), sameViewer: true, now: now),
                      "時計が戻ったら読み直す")
        // 読めなかったばかりなら読まない（圏外で顔を開くたびに読みに行かない）。少し経てば読む
        XCTAssertFalse(StoryPlayback.needsRingRefresh(fetchedAt: nil, sameViewer: false,
                                                      failedAt: now.addingTimeInterval(-5), now: now))
        XCTAssertTrue(StoryPlayback.needsRingRefresh(fetchedAt: nil, sameViewer: false,
                                                     failedAt: now.addingTimeInterval(-20), now: now))
    }

    // MARK: - 顔の輪の控え（`StoryRingDirectory`）の振る舞い

    /// 🔴 **読んでいる間にアカウントを切り替えたら、前の人の一覧を新しい人の控えに入れない**。
    /// 控えの持ち主と違う人には空を返す
    @MainActor
    func testDirectoryDoesNotHandOverAnotherViewersList() async {
        let directory = StoryRingDirectory()
        let a = [story("a1", user: "x")]
        XCTAssertTrue(directory.publish(a, loadedFor: "me-A", current: "me-A"))
        XCTAssertEqual(directory.stories(for: "me-A").map(\.id), ["a1"])
        XCTAssertTrue(directory.stories(for: "me-B").isEmpty, "別の人に前の人の控えを見せた")
        XCTAssertTrue(directory.stories(for: nil).isEmpty)
        // A で読み始め、返る前に B へ切り替わった → 入れない（B の控えにならない）
        XCTAssertFalse(directory.publish([story("late", user: "y")], loadedFor: "me-A", current: "me-B"))
        XCTAssertTrue(directory.stories(for: "me-B").isEmpty, "前の人の一覧が新しい人の控えに入った")
        XCTAssertEqual(directory.stories(for: "me-A").map(\.id), ["a1"], "前の控えを書き換えた")
        XCTAssertFalse(directory.publish(a, loadedFor: nil, current: nil), "ログインしていない人の控えを作った")
    }

    /// 同じ人の読み込みは**1つにまとめる**（顔が並ぶ画面で同時に何度も読まない）。答えは今の人のときだけ入る
    @MainActor
    func testDirectoryCoalescesConcurrentLoads() async {
        let directory = StoryRingDirectory()
        let counter = Counter()
        let made = [story("s1", user: "x")]
        let fetch: () async throws -> [Story] = {
            await counter.bump()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return made
        }
        async let first: Void = directory.refresh(viewerId: "me", current: { "me" }, fetch: fetch)
        async let second: Void = directory.refresh(viewerId: "me", current: { "me" }, fetch: fetch)
        _ = await (first, second)
        let afterTwo = await counter.value
        XCTAssertEqual(afterTwo, 1, "同時の読み込みを2回送った")
        XCTAssertEqual(directory.stories(for: "me").map(\.id), ["s1"])
        // 古くなければ読み直さない
        await directory.refreshIfStale(viewerId: "me", current: { "me" }, fetch: fetch)
        let afterStale = await counter.value
        XCTAssertEqual(afterStale, 1, "読んだばかりの控えを読み直した")
        // 読んでいる間に人が替わった → 入れない
        let other = StoryRingDirectory()
        await other.refresh(viewerId: "me-A", current: { "me-B" }, fetch: fetch)
        XCTAssertTrue(other.stories(for: "me-A").isEmpty)
        XCTAssertTrue(other.stories(for: "me-B").isEmpty)
    }

    /// 読めなかったら前の控えを残し、**しばらくは読み直さない**。消した1本は控えから外す
    @MainActor
    func testDirectoryFailureAndRemove() async {
        let directory = StoryRingDirectory()
        directory.publish([story("s1", user: "x"), story("s2", user: "x")], loadedFor: "me", current: "me",
                          now: Date().addingTimeInterval(-120))
        let counter = Counter()
        let failing: () async throws -> [Story] = {
            await counter.bump()
            throw URLError(.notConnectedToInternet)
        }
        await directory.refreshIfStale(viewerId: "me", current: { "me" }, fetch: failing)
        let once = await counter.value
        XCTAssertEqual(once, 1)
        XCTAssertEqual(directory.stories(for: "me").count, 2, "読めなかった回に控えを消した")
        await directory.refreshIfStale(viewerId: "me", current: { "me" }, fetch: failing)
        let twice = await counter.value
        XCTAssertEqual(twice, 1, "読めなかった直後にまた読みに行った（圏外のたびに読む）")
        directory.remove(id: "s1")
        XCTAssertEqual(directory.stories(for: "me").map(\.id), ["s2"])
        // 消した1本は、あとから届いた一覧にあっても戻さない
        directory.publish([story("s1", user: "x")], loadedFor: "me", current: "me")
        XCTAssertTrue(directory.stories(for: "me").isEmpty)
    }

    /// ホームの読み込みは、**読み始めた人**で控えに渡す（待つ前に人を決める）
    func testHomePublishesWithTheViewerItStartedWith() throws {
        let row = try source("Features/Stories/StoriesRow.swift")
        let reload = member("private func reload() async {", in: row)
        let viewer = try XCTUnwrap(reload.range(of: "let viewer = auth.userId"))
        let load = try XCTUnwrap(reload.range(of: "await model.load("))
        XCTAssertLessThan(viewer.lowerBound, load.lowerBound, "待ってから人を決めている")
        XCTAssertTrue(reload.contains("publish(applied, loadedFor: viewer, current: auth.userId)"))
        XCTAssertFalse(row.contains("lastFetched"), "最後に取れた一覧（誰のものか分からない）をまだ渡している")
    }

    /// 人のページ・自分のページ・写真の作者の顔が輪を出す部品を使う
    func testAvatarsUseStoryRing() throws {
        XCTAssertTrue(try source("Features/Profile/UserProfileView.swift")
            .contains("StoryAvatar(userId: userId, name: model.shownName ?? \"\", diameter: ProfileCover.avatarSize)"))
        XCTAssertTrue(try source("Features/Profile/MyPageView.swift")
            .contains("StoryAvatar(userId: profile.userId, name: L(\"あなた\", \"You\"), diameter: side)"))
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("StoryAvatar(userId: ownerId,"))
        // 新しい口は作らない（`GET /stories` を読むだけ）
        let avatar = try source("Features/Stories/StoryAvatar.swift")
        XCTAssertTrue(avatar.contains("environment.stories.list()"))
        XCTAssertTrue(avatar.contains("StoryReelView(groups: [group], startGroup: 0"))
    }

    /// 🔴 **輪の下に黒の丸を敷く**（カバー写真の上ですき間から写真が透け、真鍮が写真に接していた）
    func testRingSitsOnBlack() throws {
        let ring = try source("Features/Stories/StoryRing.swift")
        let body = member("var body: some View {", in: ring)
        let black = try XCTUnwrap(body.range(of: ".fill(Self.gapFill)"), "輪の下に黒を敷いていない")
        let stroke = try XCTUnwrap(body.range(of: ".stroke(Self.style(unseen: unseen)"))
        XCTAssertLessThan(black.lowerBound, stroke.lowerBound, "黒の丸が輪の線より上に重なる")
        XCTAssertTrue(ring.contains("static var gapFill: Color { WebTheme.background }"))
    }

    /// 閲覧画面の中から開いた人のページでは顔の輪を出さない（閲覧画面を二重に重ねない）
    func testNoRingInsideTheViewer() throws {
        let avatar = try source("Features/Stories/StoryAvatar.swift")
        XCTAssertTrue(avatar.contains("guard auth.userId != nil, !insideStoryViewer else { return nil }"))
        XCTAssertFalse(InsideStoryViewerKey.defaultValue, "ふだんの画面で輪が出なくなる")
        for path in ["Features/Stories/StoryViewerView.swift", "Features/Stories/StoryInsightsView.swift",
                     "Features/Stories/StoryRepliesSheet.swift"] {
            XCTAssertTrue(try source(path).contains(".environment(\\.insideStoryViewer, true)"), path)
        }
    }

    /// 並びが覚えた反応が変わったら（あとから届いた失敗の取り消し）、作り直した閲覧画面も写し直す。
    /// 失敗の知らせは並びが出す
    func testReactionFailureReachesARebuiltViewer() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains(".onChange(of: providedReactions) { _, now in sentReactions = now }"))
        let reel = try source("Features/Stories/StoryReelView.swift")
        XCTAssertTrue(reel.contains("toasts.show(StoryPlayback.reactionFailedMessage(emoji), kind: .failure)"))
        // 並びの覚え（値）: 先に塗った印を失敗で並びが外すと値が変わる（＝閲覧画面が写し直す合図になる）
        var reelState = StoryPlayback.SentReactions()
        XCTAssertTrue(reelState.begin("❤️", on: "s1"))
        let rebuiltBeforeFailure = reelState
        reelState.rollback("❤️", on: "s1")
        XCTAssertNotEqual(rebuiltBeforeFailure, reelState)
        XCTAssertNil(reelState.emoji(on: "s1"))
    }

    /// 写真の作者の顔は輪の有無で幅を変えない（44 にそろえる）
    func testAuthorFaceWidthIsStable() throws {
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains(".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)"))
        let avatar = try source("Features/Stories/StoryAvatar.swift")
        XCTAssertTrue(avatar.contains(".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)"))
    }

    /// 顔の大きさのまま輪を描き、写真を内側へ縮める。64 ならホームの輪と同じ寸法
    func testRingFitsAnyFace() {
        XCTAssertEqual(StoryRingMetrics.photo(diameter: 64), StoryRingMetrics.photo)
        XCTAssertEqual(StoryRingMetrics.photo(diameter: 88), 78)
        XCTAssertEqual(StoryRingMetrics.photo(diameter: 40), 30)
        XCTAssertEqual(StoryRingMetrics.segmentGapFraction(diameter: 64), 4.0 / 194.8, accuracy: 0.0001)
        XCTAssertGreaterThan(StoryRingMetrics.segmentGapFraction(diameter: 40),
                             StoryRingMetrics.segmentGapFraction(diameter: 88), "小さい輪ほど割合は大きい（4pt のまま）")
    }

    // MARK: - 5. 1本目の先読み

    /// 見えている輪の数（390 の幅なら 5 つ）。先読みは見えている輪の中の動画1本だけ
    func testRingPrefetch() {
        XCTAssertEqual(StoryPlayback.visibleRingCount(width: 390), 5)
        XCTAssertEqual(StoryPlayback.visibleRingCount(width: 320), 4)
        XCTAssertEqual(StoryPlayback.visibleRingCount(width: 0), 0)
        let openers = [story("p1"), story("p2"), story("v1", video: true), story("p3"),
                       story("p4"), story("v2", video: true)]
        XCTAssertEqual(StoryPlayback.ringPrefetchVideo(openers: openers, visibleCount: 5)?.absoluteString,
                       "https://x.test/v1.jpg")
        XCTAssertNil(StoryPlayback.ringPrefetchVideo(openers: openers, visibleCount: 2),
                     "見えていない輪まで読んだ")
        XCTAssertNil(StoryPlayback.ringPrefetchVideo(openers: [story("p1")], visibleCount: 5),
                     "写真は輪のサムネが同じ URL を読むので重ねない")
    }

    // MARK: - 7. 自分の輪の「＋」

    /// 自分にストーリーがあっても右下の「＋」で足せる。**「＋」は別のボタン**（輪の残りは開く）
    func testOwnRingHasPlusWhenStoryExists() throws {
        let row = try source("Features/Stories/StoriesRow.swift")
        let mine = member("private func mineRing(_ mine: Story?) -> some View {", in: row)
        let open = try XCTUnwrap(mine.range(of: "open(mine)"))
        let add = try XCTUnwrap(mine.range(of: "stories.mine.add"), "ストーリーがあるときの「＋」が無い")
        let noStory = try XCTUnwrap(mine.range(of: "} else {"))
        XCTAssertLessThan(open.lowerBound, add.lowerBound)
        XCTAssertLessThan(add.lowerBound, noStory.lowerBound, "「＋」がストーリーのある枝に無い")
        XCTAssertTrue(mine.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"),
                      "「＋」の当たりが 44 に満たない")
        XCTAssertTrue(mine.contains(".accessibilityAction(named: L(\"ストーリーを追加\", \"Add to your story\"))"))
        // 丸の中心は輪が無いときの「＋」と同じ所（輪の右下・外へ 2pt）
        XCTAssertEqual(StoriesRow.plusCenter, 52)
    }

    // MARK: - UI テストの見本（`-JPPreviewStories`）

    /// 見本の通信は、鍵（`-JPPreviewStories`）があるときだけストーリーの一覧を答える。答えは**本物の読み手**
    /// （`Story`）で読め、公開の新着の作者ごとに1本（先頭の人は2本）と自分の1本。知らない口は今までどおり断る
    func testPreviewBackendAnswersStoriesOnlyWhenAsked() async throws {
        let feed: [[String: Any]] = [
            ["id": "p1", "src": "https://img.test/p1.jpg", "userId": "a"],
            ["id": "p2", "src": "https://img.test/p2.jpg", "userId": "me"],
            ["id": "p3", "src": "https://img.test/p3.jpg", "userId": "a"],
            ["id": "p4", "src": "https://img.test/p4.jpg", "uploadedBy": "b"],
        ]
        let off = await PreviewBackend.reply(method: "GET", route: ["stories"], body: nil, userId: "me",
                                             store: PreviewBackend.Store(), publicFeed: { feed },
                                             publicLikes: { _ in nil })
        XCTAssertNotEqual(off.status, 200, "鍵が無いのにストーリーを答えた（ほかの UI テストの輪が変わる）")
        let on = await PreviewBackend.reply(method: "GET", route: ["stories"], body: nil, userId: "me",
                                            store: PreviewBackend.Store(), stories: true, publicFeed: { feed },
                                            publicLikes: { _ in nil })
        XCTAssertEqual(on.status, 200)
        let stories = try JSONDecoder.api.decode([Story].self, from: on.body)
        XCTAssertEqual(stories.map(\.userId), ["me", "a", "a", "b"])
        XCTAssertEqual(stories.map(\.src).last, "https://img.test/p4.jpg")
        XCTAssertNotNil(StoryPlayback.personRing(userId: "a", in: stories, isSeen: { _ in false }))
        for story in stories { XCTAssertNoThrow(try PathID.segment(story.id)) }
        // 反応・見た・返信の一覧は受けたことにする
        let react = await PreviewBackend.reply(method: "POST", route: ["stories", stories[1].id, "replies"],
                                               body: Data(#"{"emoji":"❤️"}"#.utf8), userId: "me",
                                               store: PreviewBackend.Store(), stories: true,
                                               publicLikes: { _ in nil })
        XCTAssertEqual(react.status, 200)
    }
}

/// 呼ばれた回数（読み込みをまとめたかを数える）
private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}
