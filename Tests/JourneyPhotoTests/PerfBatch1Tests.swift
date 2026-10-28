import XCTest
@testable import JourneyPhoto

/// 表示が重い所の低リスクな直し（2026-10-28・見た目は変えない）。
///
/// 画面の作り（Lazy かどうか・1回だけ作るか）は Linux では描いて確かめられないので、
/// 型の中身と、ソースの形（直しを戻すと落ちる）の両方で押さえる
final class PerfBatch1Tests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: 1. 写真の格子

    /// 格子は `LazyVStack`。複数枚の印は描くたびに1回だけ数える（札ごとに並び全部を数え直さない）
    func testPhotoGridIsLazyAndCountsMultipleOnce() throws {
        let text = try source("Sources/JourneyPhoto/Features/Common/PhotoGrid.swift")
        XCTAssertTrue(text.contains("LazyVStack(spacing: gap)"), "格子が Lazy でない")
        XCTAssertFalse(text.contains("private var multiple:"), "複数枚の印を計算型のプロパティで札ごとに数えている")
        XCTAssertEqual(count("PhotoGroups.multiPhotoIds(", in: text), 1, "複数枚の数え方が1か所でない")
        XCTAssertTrue(text.contains("let multiple = PhotoGroups.multiPhotoIds(photos)"))
    }

    // MARK: 2. 大きく見る画面の下のサムネイル

    func testViewerThumbnailStripIsLazy() throws {
        let text = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoViewerView.swift")
        let strip = try XCTUnwrap(text.range(of: "private var thumbnailStrip"))
        let body = String(text[strip.upperBound...].prefix(800))
        XCTAssertTrue(body.contains("LazyHStack(spacing: 6)"), "サムネイルの列が Lazy でない")
    }

    // MARK: 4. 写真詳細の上の束

    /// 束は描くたびに1回だけ作り、写真・点・題の下の1行に渡す
    func testPhotoDetailBuildsHeroGroupOncePerRender() throws {
        let text = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertEqual(count("PhotoDetailRules.heroGroup(", in: text), 1, "束を作る所が1か所でない")
        XCTAssertTrue(text.contains("let hero = heroLineup"), "body で束を1回作っていない")
        XCTAssertTrue(text.contains("imageButton(hero)"))
        XCTAssertTrue(text.contains("pageDots(hero)"))
        XCTAssertTrue(text.contains("heading(hero)"))
        XCTAssertFalse(text.contains("heroPage.wrappedValue"), "束の位置を読むたびに束を作り直している")
    }

    // MARK: 5. コメントの時刻

    /// 時刻の読み手を毎回作らない。小数秒の有無の両方を読む（振る舞いは前と同じ）
    func testCommentAgeReusesStaticFormatters() throws {
        let text = try source("Sources/JourneyPhoto/Features/PhotoDetail/CommentsHeading.swift")
        XCTAssertFalse(text.contains("ISO8601DateFormatter()"), "時刻の読み手を呼ぶたびに作っている")
        let now = try XCTUnwrap(NotificationGroups.parse("2026-10-28T12:00:00Z"))
        XCTAssertEqual(CommentsHeading.age("2026-10-28T11:54:30.500Z", now: now), L("5分前", "5m ago"))
        XCTAssertEqual(CommentsHeading.age("2026-10-28T10:00:00Z", now: now), L("2時間前", "2h ago"))
        XCTAssertNil(CommentsHeading.age("きのう", now: now))
    }

    // MARK: 6. ホームの「いまの季節のスポット」

    /// 札の写真は表示の大きさまで縮めて読む（`.fit` のまま）。縮めた大きさは札（240×150pt）を
    /// 3倍の画面で敷いても足りる
    func testHomeSpotShelfDownsamplesPictures() throws {
        let text = try source("Sources/JourneyPhoto/Features/Gallery/HomeSpotShelfView.swift")
        XCTAssertTrue(text.contains("DownsampledRemoteImage(url: picture.url, contentMode: .fit"), "縮めて読んでいない")
        XCTAssertFalse(text.contains(" RemoteImage(url: picture.url"), "元の大きさのまま展開する部品が残っている")
        let pixels = try XCTUnwrap(DownsampledImageSize.pixels(width: 240, scale: 3))
        XCTAssertGreaterThanOrEqual(pixels, 240 * 3, "横長の写真がぼやける")
        XCTAssertGreaterThanOrEqual(pixels, 150 * 3, "縦長の写真がぼやける")
    }

    // MARK: 7. 模様替えの見本

    /// 見本の貼り絵は画面の処理の外で描き、同じ絵は一度だけ描く。描く中身は前と同じ
    @MainActor
    func testRoomSwatchRendersOffMainOnce() async throws {
        let kind = CamperTextureKind.woodGrain
        let color: UInt32 = 0x123457
        XCTAssertEqual(CamperRoomSwatch.draw(kind, color), CamperTextures.make(kind).tinted(color))

        let before = CamperRoomSwatch.renderCount
        async let first = CamperRoomSwatch.image(kind, color)
        async let second = CamperRoomSwatch.image(kind, color)
        let (a, b) = await (first, second)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        _ = await CamperRoomSwatch.image(kind, color)
        XCTAssertEqual(CamperRoomSwatch.renderCount - before, 1, "同じ見本を二度描いている")

        let text = try source("Sources/JourneyPhoto/Features/Camper/Room/CamperRoomView.swift")
        XCTAssertTrue(text.contains("Task.detached(priority: .userInitiated) { draw(kind, color) }"),
                      "見本を画面の処理の外で描いていない")
        XCTAssertEqual(count("CamperTextures.make(", in: text), 1, "見本を描く所が draw の外にもある")
    }

    // MARK: 8. 置く棚

    /// 材料が同じ間は棚を作り直さない。家具を動かしても作り直さず、しまう・持ち物・置き場所が変われば作り直す。
    /// 中身は毎回作ったときと同じ
    func testPlaceShelfMemoRebuildsOnlyWhenInputsChange() throws {
        let camper = CamperRoomLayout.make(.car, stage: .camper)
        let owned = CamperRoomCatalog.owned(CamperStats(), CamperRoomStats())
        var e = CamperRoomEditor(doc: CamperRoomRules.starterDocument(camper), layout: camper)
        let memo = CamperRoomShelfMemo()

        let first = memo.shelf(e, placement: .floor, owned: owned, news: [])
        _ = memo.shelf(e, placement: .floor, owned: owned, news: [])
        XCTAssertEqual(memo.builds, 1, "同じ材料で棚を作り直している")
        XCTAssertEqual(first.categories, e.trayCategories(.floor, owned: owned))

        // 回す（置いた種類は変わらない）→ 作り直さない
        let before = e.doc
        var rotated = false
        for u in before.items.map(\.u) where !rotated { rotated = e.rotate(u) }
        XCTAssertTrue(rotated, "回せる家具が無い（前提）")
        XCTAssertNotEqual(e.doc, before, "前提: 回して文書が変わる")
        _ = memo.shelf(e, placement: .floor, owned: owned, news: [])
        XCTAssertEqual(memo.builds, 1, "家具を回しただけで棚を作り直している")

        // しまう → 棚に戻る
        let trunk = try XCTUnwrap(e.doc.items.first { $0.k == "storage.trunk" })
        e.stow(trunk.u)
        let stowed = memo.shelf(e, placement: .floor, owned: owned, news: [])
        XCTAssertEqual(memo.builds, 2)
        XCTAssertEqual(stowed.items(.storage), e.tray(.storage, owned: owned), "しまった家具が棚に出ない")

        // 新しい家具・置き場所・持ち物・編集の有無が変われば作り直す
        let fresh = memo.shelf(e, placement: .floor, owned: owned, news: ["storage.trunk"])
        XCTAssertEqual(fresh.fresh, [.storage])
        _ = memo.shelf(e, placement: .wall, owned: owned, news: ["storage.trunk"])
        _ = memo.shelf(e, placement: .wall, owned: owned.subtracting(["photo_frame.landscape"]), news: ["storage.trunk"])
        let none = memo.shelf(nil, placement: .wall, owned: owned, news: ["storage.trunk"])
        XCTAssertEqual(memo.builds, 6)
        XCTAssertTrue(none.categories.isEmpty)

        let text = try source("Sources/JourneyPhoto/Features/Camper/Room/CamperRoomView.swift")
        XCTAssertTrue(text.contains("shelfMemo.shelf(editor, placement: trayTab, owned: owned, news: news)"),
                      "置く板が棚の控えを使っていない")
    }
}
