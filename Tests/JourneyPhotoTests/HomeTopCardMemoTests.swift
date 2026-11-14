import XCTest
@testable import JourneyPhoto

/// ホームの上の札の重い計算を、材料が変わったときだけにする直し（2026-11-14・札 #594・Mac run 1238 の数）の試験。
///
/// 1. 写真の候補の並び（`SpotSwipe.CoverPool`）から選ぶ 1 件が、前の計算（絞って `spotId` で並べ替える）と同じ
/// 2. 控え（`HomeTopCardMemo`）は、材料が同じなら計算し直さない・変われば計算し直す
/// 3. 札の画面が控えを使っている・ホームが親の描き直しだけでは描き直さない（`GalleryView` の `==`）
final class HomeTopCardMemoTests: XCTestCase {

    private func spot(_ id: String, slug: String? = nil, image: Bool = true, draft: Bool = false) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"\(id)\"", "\"slug\":\"\(slug ?? id)\"", "\"name\":\"[\(id)]\"",
                      "\"stage\":\"\(draft ? "draft" : "published")\""]
        if image {
            fields.append("\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(id).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}")
        }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 前の計算そのもの（直す前の `SpotSwipe.cover`）
    private func oldCover(_ spots: [OfficialSpot], _ ids: Set<String>, _ day: Int) -> OfficialSpot? {
        let pool = spots.filter { TripPicker.isEligible($0) && !ids.contains($0.spotId) }
            .sorted { $0.spotId < $1.spotId }
        guard !pool.isEmpty else { return nil }
        return pool[((day % pool.count) + pool.count) % pool.count]
    }

    // MARK: - 1. 選ぶ 1 件は前と同じ

    func testCoverPoolPicksTheSameSpotAsBefore() throws {
        // 順不同・写真なし・下書き・同じ spotId（slug で見分ける）を混ぜる
        var spots: [OfficialSpot] = []
        for i in 0..<40 {
            let id = String(format: "s%02d", (i * 17) % 40)
            spots.append(try spot(id, image: i % 7 != 3, draft: i % 11 == 5))
        }
        spots.append(try spot("s05"))
        let pool = SpotSwipe.CoverPool(spots: spots)
        let exclusions: [Set<String>] = [[], ["s05"], ["s00", "s01", "s39", "nothing"], Set(spots.map(\.spotId))]
        for excluded in exclusions {
            for day in [-41, -1, 0, 1, 2, 19, 20_406, 999_999] {
                let expected = oldCover(spots, excluded, day)
                XCTAssertEqual(pool.cover(spots: spots, excluding: excluded, day: day)?.spotId, expected?.spotId,
                               "除く \(excluded.sorted()) 日 \(day)")
                XCTAssertEqual(SpotSwipe.cover(spots: spots, excluding: excluded, day: day)?.spotId, expected?.spotId)
            }
        }
        XCTAssertNil(SpotSwipe.CoverPool(spots: []).cover(spots: [], excluding: [], day: 3))
    }

    /// 🔴 同じ `spotId` が並ぶとき（どちらも公開済み・写真あり）、元の索引の順を保つ（前の安定な並べ替えと同じ）。
    /// `lhs < rhs` を `>` にすると、同じ `spotId` の後ろの方（slug が違う）を選んで落ちる
    func testCoverPoolKeepsIndexOrderForTheSameSpotId() throws {
        let spots = [try spot("b", slug: "b-first"), try spot("a"), try spot("b", slug: "b-second"),
                     try spot("c"), try spot("b", slug: "b-third")]
        let pool = SpotSwipe.CoverPool(spots: spots)
        XCTAssertEqual(pool.ids, ["a", "b", "b", "b", "c"])
        XCTAssertEqual(pool.indices, [1, 0, 2, 4, 3])
        for day in -10...10 {
            for excluded: Set<String> in [[], ["a"], ["c", "zz"]] {
                let expected = oldCover(spots, excluded, day)
                let got = pool.cover(spots: spots, excluding: excluded, day: day)
                XCTAssertEqual(got?.slug, expected?.slug, "除く \(excluded.sorted()) 日 \(day)")
                XCTAssertEqual(SpotSwipe.cover(spots: spots, excluding: excluded, day: day)?.slug, expected?.slug)
            }
        }
        XCTAssertEqual(pool.cover(spots: spots, excluding: [], day: 1)?.slug, "b-first")
        XCTAssertEqual(pool.cover(spots: spots, excluding: [], day: 3)?.slug, "b-third")
    }

    /// 🔴 索引を書き換えて番号を進め忘れても、古い並びで範囲外を引いて落ちない。その場で作り直して正しい 1 件を選ぶ
    func testCoverPoolRebuildsWhenGivenADifferentIndex() throws {
        let old = [try spot("a"), try spot("b"), try spot("c"), try spot("d"), try spot("e")]
        let pool = SpotSwipe.CoverPool(spots: old)
        // 件数が減った（古い位置 3・4 は範囲外）
        let shorter = [try spot("e"), try spot("d")]
        for day in 0..<6 {
            XCTAssertEqual(pool.cover(spots: shorter, excluding: [], day: day)?.slug, oldCover(shorter, [], day)?.slug, "日 \(day)")
        }
        // 件数が増えた
        let longer = old + [try spot("0"), try spot("f")]
        for day in 0..<8 {
            XCTAssertEqual(pool.cover(spots: longer, excluding: ["c"], day: day)?.slug, oldCover(longer, ["c"], day)?.slug, "日 \(day)")
        }
        // 件数は同じで中身が違う（並びが変わった）
        let reordered = [try spot("e"), try spot("d"), try spot("c"), try spot("b"), try spot("a")]
        for day in 0..<5 {
            XCTAssertEqual(pool.cover(spots: reordered, excluding: [], day: day)?.slug, oldCover(reordered, [], day)?.slug, "日 \(day)")
        }
        XCTAssertNil(pool.cover(spots: [], excluding: [], day: 0))
    }

    // MARK: - 2. 控え

    func testCoverPoolIsBuiltOncePerIndexRevision() throws {
        let memo = HomeTopCardMemo()
        let spots = [try spot("b"), try spot("a")]
        _ = memo.coverPool(spots: spots, revision: 1)
        _ = memo.coverPool(spots: spots, revision: 1)
        XCTAssertEqual(memo.poolBuilds, 1, "索引が同じなら並べ直さない")
        let next = [try spot("c")]
        let pool = memo.coverPool(spots: next, revision: 2)
        XCTAssertEqual(memo.poolBuilds, 2, "索引を書き換えたら作り直す")
        XCTAssertEqual(pool.ids, ["c"])
    }

    func testShelfAndNeedsAreComputedOnlyWhenTheKeyChanges() throws {
        let memo = HomeTopCardMemo()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let key = HomeTopCardMemo.ShelfKey(today: day, spotsRevision: 3, choices: [.theme], quiz: nil, quizSettled: true)
        var computed = 0
        for _ in 0..<5 {
            _ = memo.visibleShelf(key) { computed += 1; return nil }
            _ = memo.detailNeeds(key) { computed += 1; return [] }
        }
        XCTAssertEqual(computed, 2, "同じ材料なら 1 回ずつ")
        for changed in [
            HomeTopCardMemo.ShelfKey(today: day.addingTimeInterval(86_400), spotsRevision: 3, choices: [.theme], quiz: nil, quizSettled: true),
            HomeTopCardMemo.ShelfKey(today: day, spotsRevision: 4, choices: [.theme], quiz: nil, quizSettled: true),
            HomeTopCardMemo.ShelfKey(today: day, spotsRevision: 3, choices: [], quiz: nil, quizSettled: true),
            HomeTopCardMemo.ShelfKey(today: day, spotsRevision: 3, choices: [.theme], quiz: nil, quizSettled: false),
        ] {
            let before = memo.shelfComputes
            _ = memo.visibleShelf(changed) { nil }
            XCTAssertEqual(memo.shelfComputes, before + 1, "材料が変わったら計算し直す: \(changed)")
        }
    }

    // MARK: - 3. 配線

    /// 🔴 札の画面が控えを使う（外すと body のたびに索引を並べ替える）
    func testHomeTopCardViewUsesTheMemo() throws {
        let view = try source("Sources/JourneyPhoto/Features/Gallery/HomeTopCardView.swift")
        XCTAssertTrue(view.contains("pool: memo.coverPool(spots: spots, revision: spotsRevision)"), "写真の候補の並びを控えから渡していない")
        XCTAssertTrue(view.contains("memo.visibleShelf(shelfMemoKey(choices))"), "季節の段を控えていない")
        XCTAssertTrue(view.contains("memo.detailNeeds(shelfMemoKey(choices))"), "詳細を取りに行く場所を控えていない")
        // 索引を書き換える所は、必ず書き換えの番号も進める（控えの鍵）
        let assigns = view.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("spots = ") }
        let bumps = view.components(separatedBy: "spotsRevision &+= 1").count - 1
        XCTAssertEqual(assigns.count, bumps, "索引を書き換えて番号を進めていない所がある")
    }

    /// 🔴 ホームは、親から渡す閉じた処理が新しくなっただけでは描き直さない。未読の数が変わったら描き直す
    /// （`GalleryView` そのものは Linux で作れない——`GalleryViewModel` が設定を読んで止まる。比べる値と配線を見る）
    func testGalleryViewComparesOnlyWhatItDraws() throws {
        XCTAssertEqual(GalleryViewInputs(unread: 2, messagesUnread: false), GalleryViewInputs(unread: 2, messagesUnread: false))
        XCTAssertNotEqual(GalleryViewInputs(unread: 2, messagesUnread: false), GalleryViewInputs(unread: 3, messagesUnread: false))
        XCTAssertNotEqual(GalleryViewInputs(unread: 2, messagesUnread: false), GalleryViewInputs(unread: 2, messagesUnread: true))
        let equatable = try source("Sources/JourneyPhoto/Features/Gallery/GalleryView+Equatable.swift")
        XCTAssertTrue(equatable.contains("lhs.drawnInputs == rhs.drawnInputs"), "== が描く値で比べていない")
        XCTAssertTrue(equatable.contains("GalleryViewInputs(unread: unread, messagesUnread: messagesUnread)"))
        // 親から渡す値が増えたら、ここも見直す（比べ忘れると、その値が変わっても描き直さない）
        let file = try source("Sources/JourneyPhoto/Features/Gallery/GalleryView.swift")
        guard let head = file.range(of: "struct GalleryView: View {") else { return XCTFail("GalleryView が無い") }
        let gallery = file[head.upperBound...].components(separatedBy: "\n}\n").first ?? ""
        let passed = gallery.components(separatedBy: "\n").filter { line in
            (line.hasPrefix("    var ") || line.hasPrefix("    let ")) && !line.contains("{") || line.hasPrefix("    var ") && line.contains("= {")
        }.map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(passed, ["var unread: Int = 0", "var onOpenNotifications: () -> Void = {}", "var messagesUnread = false"],
                       "GalleryView が親から受け取る値が変わった。GalleryViewInputs も見直す")
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        guard let range = root.range(of: "GalleryView(unread: unread") else { return XCTFail("RootView に GalleryView が無い") }
        let after = root[range.upperBound...].prefix(400)
        XCTAssertTrue(after.contains(".equatable()"), "RootView が GalleryView を .equatable() で包んでいない")
    }
}
