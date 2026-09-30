import XCTest
@testable import JourneyPhoto

/// 写真から行き先を選ぶ画面の状態（`TripPickerModel`）。
///
/// 固定したいのは:
///  1. 札の山は**一度だけ**作る（戻ってくるたびに混ぜ直して、見た札をまた出さない）
///  2. 行きたい／見送る／ひとつ戻す／下書きから外す の積み方
///  3. 選べる上限（`TripPicker.pickMax`）を越えて「行きたい」を足さない
///  4. 「行きたい」への出し入れは**押した順に1本ずつ**（戻したのに残る、を防ぐ）
@MainActor
final class TripPickerModelTests: XCTestCase {

    private struct Offline: Error {}

    private func spot(_ slug: String) throws -> OfficialSpot {
        try JSONDecoder.api.decode(OfficialSpot.self, from: Data("""
        {"spotId":"sp_\(slug)","slug":"\(slug)","name":"[\(slug)]","stage":"published",
         "image":{"url":"https://journey-photo.com/images/spots/\(slug).jpg","author":"A","license":"CC BY 4.0"}}
        """.utf8))
    }

    private func loaded(_ spots: [OfficialSpot], excluding: Set<String> = [], seed: UInt64 = 7) async -> TripPickerModel {
        let model = TripPickerModel()
        await model.load(fetch: { spots }, excluding: excluding, seed: seed)
        return model
    }

    // MARK: - 1. 札の山

    func testLoadBuildsDeckOnceAndDoesNotReshuffle() async throws {
        let spots = try (0..<12).map { try spot("s\($0)") }
        let model = await loaded(spots, excluding: [SavedSpotKey.official("s0")])
        XCTAssertEqual(model.status, .loaded)
        XCTAssertEqual(model.deck.count, 11)
        XCTAssertFalse(model.deck.contains { $0.slug == "s0" })
        let first = model.deck.map(\.slug)
        // 戻ってきた（`.task` がもう一度走った）: 違う種でも作り直さない
        await model.load(fetch: { spots }, excluding: [], seed: 99)
        XCTAssertEqual(model.deck.map(\.slug), first)
    }

    func testFailedLoadCanBeRetried() async throws {
        let model = TripPickerModel()
        await model.load(fetch: { throw Offline() }, excluding: [], seed: 1)
        XCTAssertEqual(model.status, .failed)
        XCTAssertNil(model.current)
        let spots = [try spot("a")]
        await model.load(fetch: { spots }, excluding: [], seed: 1)
        XCTAssertEqual(model.status, .loaded)
        XCTAssertEqual(model.current?.slug, "a")
    }

    // MARK: - 2. 積み方

    func testDecideUndoAndRemove() async throws {
        let model = await loaded(try (0..<4).map { try spot("s\($0)") })
        let deck = model.deck
        XCTAssertEqual(model.decide(.want)?.slug, deck[0].slug)
        XCTAssertEqual(model.decide(.skip)?.slug, deck[1].slug)
        XCTAssertEqual(model.decide(.want)?.slug, deck[2].slug)
        XCTAssertEqual(model.picked.map(\.slug), [deck[0].slug, deck[2].slug])
        XCTAssertEqual(model.current?.slug, deck[3].slug)
        XCTAssertNil(model.upcoming)

        // 下書きから外す: 選んだ場所から消えるが、札は戻らない
        model.remove(deck[0].spotId)
        XCTAssertEqual(model.picked.map(\.slug), [deck[2].slug])
        XCTAssertEqual(model.current?.slug, deck[3].slug)

        // ひとつ戻す: 最後の決めごとから
        XCTAssertEqual(model.undo(), .init(spot: deck[2], choice: .want))
        XCTAssertEqual(model.current?.slug, deck[2].slug)
        XCTAssertEqual(model.undo()?.choice, .skip)
        // 外していた場所まで戻したら、下書きにも戻る
        XCTAssertEqual(model.undo()?.spot.slug, deck[0].slug)
        XCTAssertEqual(model.decide(.want)?.slug, deck[0].slug)
        XCTAssertEqual(model.picked.map(\.slug), [deck[0].slug])
    }

    func testNothingToDecideAtTheEnd() async throws {
        let model = await loaded([try spot("a")])
        model.decide(.skip)
        XCTAssertNil(model.current)
        XCTAssertNil(model.decide(.want))
        XCTAssertEqual(model.decisions.count, 1)
        XCTAssertNil(TripPickerModel().undo())
    }

    /// 前から「行きたい」に入っていた場所は、戻したときに外さない（決めた時点の記録を返す）
    func testUndoRemembersPlacesThatWereAlreadyWanted() async throws {
        let model = await loaded(try (0..<3).map { try spot("s\($0)") })
        model.decide(.want, alreadyWanted: true)
        model.decide(.want)
        model.decide(.skip, alreadyWanted: true)
        XCTAssertEqual(model.undo()?.wasWanted, false)   // 見送りは足していない
        XCTAssertEqual(model.undo()?.wasWanted, false)
        XCTAssertEqual(model.undo()?.wasWanted, true)
        // 前から入っていた場所も、選んだ場所には入る
        model.decide(.want, alreadyWanted: true)
        XCTAssertEqual(model.picked.count, 1)
    }

    /// 足す→戻す（外す要求が待っている）→また行きたい: 控えにまだ残っていても「前から」と読まない
    func testPlacesAddedHereAreNeverTreatedAsAlreadyWanted() async {
        let model = TripPickerModel()
        XCTAssertFalse(model.wasWantedBefore("sp_a", inWishlist: false))
        XCTAssertTrue(model.wasWantedBefore("sp_b", inWishlist: true))
        model.markAdded("sp_a")
        XCTAssertFalse(model.wasWantedBefore("sp_a", inWishlist: true))
        // 外し終えたあとに控えに入っていたら、それは他（Web など）で入れたもの
        model.unmarkAdded("sp_a", generation: model.addedGeneration("sp_a"))
        XCTAssertTrue(model.wasWantedBefore("sp_a", inWishlist: true))
    }

    /// 行きたい→戻す→すぐ行きたい: 前の「外す」の結果が後から返っても、後の「行きたい」の印は消さない
    func testLateRemovalDoesNotClearANewerAdd() async {
        let model = TripPickerModel()
        model.markAdded("sp_a")
        let atUndo = model.addedGeneration("sp_a")   // 戻したとき
        model.markAdded("sp_a")                        // すぐまた行きたい
        model.unmarkAdded("sp_a", generation: atUndo)  // 前の外すが返る
        XCTAssertFalse(model.wasWantedBefore("sp_a", inWishlist: true))
    }

    // MARK: - 3. 上限

    func testWantStopsAtPickMaxButPassStillWorks() async throws {
        let spots = try (0..<(TripPicker.pickMax + 2)).map { try spot("s\($0)") }
        let model = await loaded(spots)
        for _ in 0..<TripPicker.pickMax { XCTAssertNotNil(model.decide(.want)) }
        XCTAssertTrue(model.isFull)
        let before = model.position
        XCTAssertNil(model.decide(.want))
        XCTAssertEqual(model.position, before)
        XCTAssertEqual(model.picked.count, TripPicker.pickMax)
        // 見送るはできる
        XCTAssertNotNil(model.decide(.skip))
        // 下書きから外せば、また足せる
        model.remove(model.picked[0].spotId)
        XCTAssertFalse(model.isFull)
        XCTAssertNotNil(model.decide(.want))
    }

    // MARK: - 4. 出し入れの順

    func testWishOperationsRunOneAtATimeInOrder() async {
        let model = TripPickerModel()
        var log: [String] = []
        model.enqueueWish {
            log.append("add:start")
            try? await Task.sleep(nanoseconds: 50_000_000)
            log.append("add:end")
        }
        model.enqueueWish {
            log.append("remove")
        }
        await model.waitForWishes()
        XCTAssertEqual(log, ["add:start", "add:end", "remove"])
    }
}
