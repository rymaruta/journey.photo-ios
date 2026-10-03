import XCTest
@testable import JourneyPhoto

/// ストーリーの反応を選ぶ・音の設定を覚える（2026-09-30）
final class StoryReactionAudioTests: XCTestCase {

    /// 音を消したら覚える。覚えが無ければ音あり（今までと同じ）
    func testMutePreferenceIsRemembered() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = StoryAudioPreference(defaults: defaults)
        XCTAssertFalse(first.muted, "覚えが無ければ音あり")
        first.muted = true
        XCTAssertTrue(StoryAudioPreference(defaults: defaults).muted, "次に開いたときも消したまま")
        first.muted = false
        XCTAssertFalse(StoryAudioPreference(defaults: defaults).muted)
    }

    /// ❤️ は今までどおり「いいね」、ほかは絵文字で知らせる
    func testReactionSentMessage() {
        XCTAssertEqual(StoryPlayback.reactionSentMessage("❤️"), L("いいねを送りました", "Like sent"))
        XCTAssertEqual(StoryPlayback.reactionSentMessage("👏"), L("👏 を送りました", "Sent 👏"))
    }

    /// 6つとも読み上げの名前を持つ（絵文字のまま読ませない）。名前は重ならない
    func testEveryReactionHasAName() {
        let names = StoryService.reactions.map(StoryPlayback.reactionName)
        XCTAssertEqual(StoryService.reactions.count, 6)
        for (emoji, name) in zip(StoryService.reactions, names) {
            XCTAssertNotEqual(name, emoji, "\(emoji) に名前が無い")
        }
        XCTAssertEqual(Set(names).count, names.count)
    }

    /// 返信欄・メニュー・シートのどれかが開いたら並びを閉じる。何も開いていなければ残す
    func testReactionPickerClosesWhenSomethingElseOpens() {
        XCTAssertFalse(StoryPlayback.closesReactionPicker(replyFocused: false, menuOpen: false, sheetOpen: false))
        XCTAssertTrue(StoryPlayback.closesReactionPicker(replyFocused: true, menuOpen: false, sheetOpen: false))
        XCTAssertTrue(StoryPlayback.closesReactionPicker(replyFocused: false, menuOpen: true, sheetOpen: false))
        XCTAssertTrue(StoryPlayback.closesReactionPicker(replyFocused: false, menuOpen: false, sheetOpen: true))
    }

    // MARK: - 同じ1本に二度送らない（バグ探し 2026-10-03）

    /// 🔴 **送れた1本には、2回目を送らない**（別の絵文字でも）。サーバーは反応を重ねて消さず、
    /// 毎回新しい返信として足して投稿者へ通知を飛ばす（`storyReplies.ts` の `postStoryReply`）
    func testReactionIsSentOncePerStory() {
        var sent = StoryPlayback.SentReactions()
        XCTAssertTrue(sent.shouldSend(on: "s1"))
        XCTAssertNil(sent.emoji(on: "s1"), "送る前から塗りつぶしている")
        sent.record("❤️", on: "s1")
        XCTAssertFalse(sent.shouldSend(on: "s1"), "同じ1本に2回目を送る")
        XCTAssertEqual(sent.emoji(on: "s1"), "❤️", "送った印（塗りつぶし）が付かない")
        // 別の1本は今までどおり送れる
        XCTAssertTrue(sent.shouldSend(on: "s2"))
        XCTAssertNil(sent.emoji(on: "s2"))
    }

    /// 人から人への並びは、閲覧画面が知らせた反応（`onReacted`）を覚え、作り直した閲覧画面へ
    /// 渡し直す（`sentReactions`）。値で渡すので、渡した後に閲覧画面の中で足しても並びの覚えは
    /// 知らせ（`record`）でしか増えない——知らせを落とすと、人を回して戻ったら忘れる
    func testReelKeepsReactionsAcrossViewerRebuilds() {
        var reel = StoryPlayback.SentReactions()
        // 1人目の閲覧画面（並びの覚えから始まる）で ❤️ を送り、並びへ知らせた
        var firstViewer = reel
        firstViewer.record("❤️", on: "s1")
        reel.record("❤️", on: "s1")        // `onReacted`
        // 次の人へ回って戻った: 閲覧画面は並びの覚えから作り直される
        let rebuilt = reel
        XCTAssertFalse(rebuilt.shouldSend(on: "s1"), "人を回して戻ったら、送った反応を忘れた")
        XCTAssertEqual(rebuilt.emoji(on: "s1"), "❤️")
        XCTAssertEqual(firstViewer, rebuilt)
    }

    /// 2回目の知らせは、**送ってある方の絵文字**で言う
    func testAlreadySentMessage() {
        XCTAssertEqual(StoryPlayback.reactionAlreadySentMessage("❤️"),
                       L("いいねは送ってあります", "You already liked this"))
        XCTAssertEqual(StoryPlayback.reactionAlreadySentMessage("👏"),
                       L("👏 は送ってあります", "You already sent 👏"))
    }
}
