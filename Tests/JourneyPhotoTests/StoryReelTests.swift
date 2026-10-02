import XCTest
@testable import JourneyPhoto

/// ストーリーを人から人へ続けて見る並び（`StoryReel`・2026-09-29）
final class StoryReelTests: XCTestCase {

    private func story(_ id: String, _ user: String?, _ createdAt: String) -> Story {
        var fields = [#""id":"\#(id)""#, #""src":"https://x.test/\#(id).jpg""#, #""createdAt":"\#(createdAt)""#]
        if let user { fields.append(#""userId":"\#(user)""#) }
        return try! JSONDecoder.api.decode(Story.self, from: Data(("{" + fields.joined(separator: ",") + "}").utf8))
    }

    // MARK: - 束

    /// 輪の順に人ごとの束を作り、各束は**輪に出していた1本から**開く
    func testGroupsFollowRingOrderAndStartAtTheRing() {
        let a1 = story("a1", "a", "2026-09-29T01:00:00Z")
        let a2 = story("a2", "a", "2026-09-29T02:00:00Z")
        let b1 = story("b1", "b", "2026-09-29T03:00:00Z")
        let all = [a1, a2, b1]
        let groups = StoryReel.groups(rings: [b1, a2], in: all)
        XCTAssertEqual(groups.map { $0.stories.map(\.id) }, [["b1"], ["a1", "a2"]])
        XCTAssertEqual(groups.map(\.start), [0, 1], "輪の1本（a2）から開いていない")
        // 同じ人の輪が2つ来ても束は1つ
        XCTAssertEqual(StoryReel.groups(rings: [a1, a2], in: all).count, 1)
        XCTAssertEqual(StoryReel.groups(rings: [], in: all), [])
    }

    /// 落とした1本・ブロックした人を外す。開く位置は元の1本が残っていればそこ
    func testLiveGroupDropsRemovedAndBlocked() {
        let a1 = story("a1", "a", "2026-09-29T01:00:00Z")
        let a2 = story("a2", "a", "2026-09-29T02:00:00Z")
        let a3 = story("a3", "a", "2026-09-29T03:00:00Z")
        let g = StoryReel.Group(stories: [a1, a2, a3], start: 2)
        let kept = StoryReel.live(g, removed: ["a1"], blocked: [])
        XCTAssertEqual(kept?.stories.map(\.id), ["a2", "a3"])
        XCTAssertEqual(kept?.start, 1, "開く1本（a3）の位置を詰め直していない")
        XCTAssertEqual(StoryReel.live(g, removed: ["a3"], blocked: [])?.start, 0, "開く1本が消えたら先頭から")
        XCTAssertNil(StoryReel.live(g, removed: ["a1", "a2", "a3"], blocked: []), "全部落としたら飛ばす")
        XCTAssertNil(StoryReel.live(g, removed: [], blocked: ["a"]), "ブロックした人は飛ばす")
    }

    /// 隣は**まだ見せるものがある**いちばん近い人（飛ばした人を越える）
    func testNeighborSkipsEmptyGroups() {
        let live: Set<Int> = [0, 3]
        XCTAssertEqual(StoryReel.neighbor(from: 0, step: 1, count: 4) { live.contains($0) }, 3)
        XCTAssertEqual(StoryReel.neighbor(from: 3, step: -1, count: 4) { live.contains($0) }, 0)
        XCTAssertNil(StoryReel.neighbor(from: 3, step: 1, count: 4) { live.contains($0) })
        XCTAssertNil(StoryReel.neighbor(from: 0, step: -1, count: 4) { _ in true })
    }

    /// 前の人へ戻るときは**その人の最後の1本から**（Web の `goPrev`）。進むときは開く1本から
    func testEnteringBackStartsAtLastStory() {
        let a1 = story("a1", "a", "2026-09-29T01:00:00Z")
        let a2 = story("a2", "a", "2026-09-29T02:00:00Z")
        let a3 = story("a3", "a", "2026-09-29T03:00:00Z")
        let g = StoryReel.Group(stories: [a1, a2, a3], start: 1)
        XCTAssertEqual(StoryReel.entering(g, back: true).start, 2, "前の人の最後の1本へ戻っていない")
        XCTAssertEqual(StoryReel.entering(g, back: false), g, "進む向きは今までどおり")
        let single = StoryReel.Group(stories: [a1], start: 0)
        XCTAssertEqual(StoryReel.entering(single, back: true).start, 0)
    }

    // MARK: - 立方体

    /// 真ん中の面は 0 度・隣の面は ±90 度・その間は指の移動に比例
    func testCubeAngle() {
        XCTAssertEqual(StoryReel.cubeAngle(minX: 0, width: 400), 0)
        XCTAssertEqual(StoryReel.cubeAngle(minX: 400, width: 400), 90)
        XCTAssertEqual(StoryReel.cubeAngle(minX: -400, width: 400), -90)
        XCTAssertEqual(StoryReel.cubeAngle(minX: -100, width: 400), -22.5, accuracy: 0.0001)
        XCTAssertEqual(StoryReel.cubeAngle(minX: 900, width: 400), 90, "90度より回さない")
        XCTAssertEqual(StoryReel.cubeAngle(minX: 50, width: 0), 0, "幅が0でも割らない")
        // 右へずれた面は左端、左へずれた面は右端を軸に（2つの面が境目で接して回る）
        XCTAssertEqual(StoryReel.hinge(minX: 120), .leading)
        XCTAssertEqual(StoryReel.hinge(minX: -120), .trailing)
    }

    // MARK: - 離したとき

    func testReleaseTurnsPastAQuarterOrWithMomentum() {
        let w = 400.0
        XCTAssertEqual(StoryReel.release(dx: -120, predictedDX: -120, width: w, hasNext: true, hasPrevious: true), .forward)
        XCTAssertEqual(StoryReel.release(dx: 120, predictedDX: 120, width: w, hasNext: true, hasPrevious: true), .back)
        XCTAssertEqual(StoryReel.release(dx: -60, predictedDX: -60, width: w, hasNext: true, hasPrevious: true), .stay)
        // 短く速く払えば回る（勢い）
        XCTAssertEqual(StoryReel.release(dx: -40, predictedDX: -300, width: w, hasNext: true, hasPrevious: true), .forward)
        // 引いた向きと逆へ弾いても、見えていない側へは回らない（勢いは同じ向きだけ）
        XCTAssertEqual(StoryReel.release(dx: -60, predictedDX: 200, width: w, hasNext: true, hasPrevious: true), .stay)
        XCTAssertNotEqual(StoryReel.release(dx: -150, predictedDX: 200, width: w, hasNext: true, hasPrevious: true), .back)
        // 隣の人がいない向きは戻す
        XCTAssertEqual(StoryReel.release(dx: -300, predictedDX: -300, width: w, hasNext: false, hasPrevious: true), .stay)
        XCTAssertEqual(StoryReel.release(dx: 300, predictedDX: 300, width: w, hasNext: true, hasPrevious: false), .stay)
    }

    /// 隣がいない向きは重くしか動かない
    func testResistedAtTheEnds() {
        XCTAssertEqual(StoryReel.resisted(dx: -90, hasNext: false, hasPrevious: true), -30)
        XCTAssertEqual(StoryReel.resisted(dx: 90, hasNext: true, hasPrevious: false), 30)
        XCTAssertEqual(StoryReel.resisted(dx: -90, hasNext: true, hasPrevious: false), -90)
    }

    // MARK: - 縦横

    /// 向きは払い始めに決める。揺れ（10未満）は決めない・上へは何もしない
    func testAxis() {
        XCTAssertNil(StoryReel.axis(dx: 4, dy: 5))
        XCTAssertEqual(StoryReel.axis(dx: -30, dy: 10), .horizontal)
        XCTAssertEqual(StoryReel.axis(dx: 5, dy: 40), .vertical)
        XCTAssertNil(StoryReel.axis(dx: 5, dy: -40), "上へ払って閉じたり回ったりしない")
    }

    /// 🔴 **返信を打っている間の払いは、下も横も動かさない**（閲覧画面がキーボードを閉じるだけ）
    /// ——下へ払うと閉じて書きかけが消えていた。払えない間（メニュー・送信中）は横だけ止め、
    /// 下へ閉じるのは今どおり通す
    func testAxisWhileTypingOrLocked() {
        XCTAssertNil(StoryReel.axis(dx: 5, dy: 200, swipeLocked: true, typing: true), "入力中に下へ払って閉じた")
        XCTAssertNil(StoryReel.axis(dx: -200, dy: 5, swipeLocked: true, typing: true), "入力中に横へ払って回った")
        XCTAssertEqual(StoryReel.axis(dx: 5, dy: 200, swipeLocked: true, typing: false), .vertical,
                       "送信中に下へ払って閉じられない")
        XCTAssertNil(StoryReel.axis(dx: -200, dy: 5, swipeLocked: true, typing: false))
        XCTAssertEqual(StoryReel.axis(dx: -200, dy: 5, swipeLocked: false, typing: false), .horizontal)
    }

    // MARK: - 下へ払って閉じる

    func testCloseAndScale() {
        XCTAssertTrue(StoryReel.closes(dy: 130, predictedDY: 130))
        XCTAssertTrue(StoryReel.closes(dy: 40, predictedDY: 300), "勢いでも閉じる")
        XCTAssertFalse(StoryReel.closes(dy: 60, predictedDY: 80))
        XCTAssertEqual(StoryReel.dragScale(dy: 0), 1)
        XCTAssertEqual(StoryReel.dragScale(dy: 200), 0.9, accuracy: 0.0001)
        XCTAssertEqual(StoryReel.dragScale(dy: 5_000), 0.8, accuracy: 0.0001, "縮みすぎない")
        XCTAssertEqual(StoryReel.dragScale(dy: -50), 1, "上へ引いても大きくならない")
    }

    // MARK: - 左タップ

    /// 束の先頭で始まってすぐ左を押したら、前の人がいれば前の人へ
    func testLeftTapAtGroupStartGoesToPreviousPerson() {
        XCTAssertEqual(StoryPlayback.leftTap(index: 0, elapsed: 0.3, hasPreviousGroup: true), .previousGroup)
        XCTAssertEqual(StoryPlayback.leftTap(index: 0, elapsed: 0.3, hasPreviousGroup: false), .restart)
        XCTAssertEqual(StoryPlayback.leftTap(index: 0, elapsed: 1.2, hasPreviousGroup: true), .restart,
                       "見始めて時間が経っていれば、今のを最初から")
        XCTAssertEqual(StoryPlayback.leftTap(index: 2, elapsed: 0.3, hasPreviousGroup: true), .previous(1))
    }

    /// **「動きを減らす」なら立方体に回さない**——同じ場所に重ね、払った分だけ濃さを
    /// 入れ替える（フェード）。入っていなければ今までどおり回して横へずらす
    func testReduceMotionFadesInsteadOfRotating() {
        let normal = StoryReel.faceLook(minX: 200, width: 400, reduceMotion: false)
        XCTAssertEqual(normal, .init(angle: 45, offsetX: 200, opacity: 1))
        let still = StoryReel.faceLook(minX: 200, width: 400, reduceMotion: true)
        XCTAssertEqual(still.angle, 0, "「動きを減らす」なのに3Dで回している")
        XCTAssertEqual(still.offsetX, 0, "「動きを減らす」なのに横へ流している")
        XCTAssertEqual(still.opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(StoryReel.faceLook(minX: 0, width: 400, reduceMotion: true).opacity, 1)
        XCTAssertEqual(StoryReel.faceLook(minX: -400, width: 400, reduceMotion: true).opacity, 0,
                       "画面の外に置いた隣の面が見えている")
        XCTAssertEqual(StoryReel.faceLook(minX: 900, width: 400, reduceMotion: true).opacity, 0)
        XCTAssertEqual(StoryReel.faceLook(minX: 10, width: 0, reduceMotion: true).opacity, 1)
    }
}
