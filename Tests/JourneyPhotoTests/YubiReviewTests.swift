import XCTest
@testable import JourneyPhoto

/// 第6章（札 #543）の確かめ役の指摘（2026-11-12）の直し。直しを戻すと落ちることを確かめてある
final class YubiReviewTests: XCTestCase {

    private func photo(_ id: String, owner: String?) throws -> Photo {
        let u = owner.map { ",\"userId\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(u)}".utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 1. 送る人の列（読み上げの「送る」）を開いたまま残さない

    /// 読み上げの操作の行き先は、選んだ1回として重ねた画面へ渡す（指の位置は持たない）
    @MainActor
    func testChooseDeliversTheDrop() async throws {
        let center = PhotoLiftCenter()
        let p = try photo("a", owner: "me")
        center.choose(p, target: .save)
        let drop = try XCTUnwrap(center.drop)
        XCTAssertEqual(drop.photo.id, "a")
        XCTAssertEqual(drop.chosen, .save)
        XCTAssertFalse(center.isHolding, "選んだだけで幕がかかった")
    }

    /// 裏に回る・通知センターで送る人の列を戻す。幕を押しても戻す
    @MainActor
    func testSceneAndBackdropCancel() async throws {
        let center = PhotoLiftCenter()
        let p = try photo("a", owner: "me")
        center.openFaces(for: p)
        XCTAssertTrue(center.isHolding)
        XCTAssertTrue(PhotoLiftCenter.holding)
        center.sceneChanged(active: true)
        XCTAssertNotNil(center.facesOpenFor)
        center.sceneChanged(active: false)
        XCTAssertFalse(center.isHolding, "裏に回っても送る人の列が開いたまま")
        XCTAssertFalse(PhotoLiftCenter.holding, "縦の送りが止まったまま")
        center.openFaces(for: p)
        center.backdropTapped()
        XCTAssertFalse(center.isHolding, "幕を押しても戻らない")
        XCTAssertNil(center.facesOpenFor)
        XCTAssertFalse(PhotoLiftCenter.holding)
    }

    // MARK: - 3. ストーリーで紹介は自分の写真だけ

    func testStoryOnlyForOwnPhotos() {
        XCTAssertTrue(PhotoLift.allowsStory(ownerId: "me", me: "me"))
        XCTAssertFalse(PhotoLift.allowsStory(ownerId: "other", me: "me"), "他人の写真をストーリーへ運べる")
        XCTAssertFalse(PhotoLift.allowsStory(ownerId: nil, me: "me"))
        XCTAssertFalse(PhotoLift.allowsStory(ownerId: "me", me: nil))
    }

    // MARK: - 2・4. ①現像の投稿（開き直す・非公開で始める・閉じたら取り消す）

    /// 🔴 行き先を決める口に「ストーリーに出せるか」の既定値を置かない（1.1.84 のまとめ・秘書室の指示）。
    /// 既定が「出せる」だと、呼ぶ所で持ち主かを渡し忘れたときに他人の写真がストーリーへ通る。
    /// 画面の側は毎回 `PhotoLift.allowsStory(ownerId:me:)`（自分の写真だけ）の答えを渡す
    func testAllowsStoryHasNoDefaultAndCallersPassTheOwnerCheck() throws {
        let rules = try source("Sources/JourneyPhoto/Core/Text/PhotoLift.swift")
        let overlay = try source("Sources/JourneyPhoto/Features/Gallery/PhotoLiftOverlay.swift")
        for text in [rules, overlay] {
            XCTAssertFalse(text.contains("allowsStory: Bool ="), "ストーリーに出せるかに既定値がある")
        }
        XCTAssertTrue(overlay.contains("return PhotoLift.allowsStory(ownerId: PhotoOwnership.ownerId(of: photo), me: auth.userId)"))
        // ストーリーで紹介を実行する所は、写真ごとの答え（`allowsStory(…)`）を見てから開く
        XCTAssertTrue(overlay.contains("case .story: if allowsStory(drop.photo) { openStory(drop.photo) }"))
        // 持ち主の答え: 自分の写真だけ・ログインしていなければ出さない
        XCTAssertTrue(PhotoLift.allowsStory(ownerId: "me", me: "me"))
        XCTAssertFalse(PhotoLift.allowsStory(ownerId: "other", me: "me"))
        XCTAssertFalse(PhotoLift.allowsStory(ownerId: "me", me: nil))
        XCTAssertFalse(PhotoLift.allowsStory(ownerId: nil, me: "me"))
    }

    func testDevelopPostDefaultsAndReopen() {
        XCTAssertFalse(DevelopTrips.startsPublic, "旅の写真から来た投稿を公開で始めた")
        XCTAssertTrue(DevelopTrips.uploadStartsPrivate(hasTripPhotos: true, chosePublic: false))
        XCTAssertFalse(DevelopTrips.uploadStartsPrivate(hasTripPhotos: true, chosePublic: true), "選んだ公開が届かない")
        XCTAssertFalse(DevelopTrips.uploadStartsPrivate(hasTripPhotos: false, chosePublic: false))
        XCTAssertEqual(DevelopTrips.audienceLabel(published: false), "自分だけ（非公開）")
        XCTAssertTrue(DevelopTrips.reopensAfterPost(posted: 0), "1枚も上がらないのに札を閉じたまま")
        XCTAssertFalse(DevelopTrips.reopensAfterPost(posted: 2))
        XCTAssertTrue(DevelopTrips.closingCancelsPendingPost, "取り消しの間に閉じると送り出した")
    }

    /// 画面が送っている最中を見張る・閉じたら取り消す・開き直す・非公開で始める（コードの形で縛る）
    func testDevelopWiring() throws {
        let view = try source("Sources/JourneyPhoto/Features/Trips/DevelopView.swift")
        XCTAssertTrue(view.contains("@ObservedObject private var postCenter = DevelopPostCenter.shared"))
        XCTAssertTrue(view.contains("posting: postCenter.isPosting"))
        XCTAssertFalse(view.contains("published: true"), "①の投稿を公開に決め打ちしている")
        let center = try source("Sources/JourneyPhoto/Features/Trips/DevelopPostCenter.swift")
        XCTAssertTrue(center.contains("DevelopTrips.reopensAfterPost(posted: posted)"))
        XCTAssertFalse(center.contains("published: true"))
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains("DevelopTrips.uploadStartsPrivate(hasTripPhotos:"))
    }

    // MARK: - ②1年前（投稿済みの旅を出さない・閉じたら読みを取り消す）

    func testYearAgoUsesPostedShots() throws {
        let row = try source("Sources/JourneyPhoto/Features/Stories/StoriesRow.swift")
        XCTAssertTrue(row.contains("deviceTrips.books(posted: LibraryTrips.postedShots(of: myPhotos)"),
                      "投稿済みの旅を「1年前」にもう一度出す")
    }

    @MainActor
    func testCancelledLoadDoesNotDeliver() async {
        let load = CancellableLoad<Int>()
        var delivered: [Int] = []
        load.start({
            try? await Task.sleep(nanoseconds: 50_000_000)
            return 1
        }) { delivered.append($0) }
        load.cancel()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(delivered.isEmpty, "閉じたあとに読み終えた写真を渡した")
        load.start({ 2 }) { delivered.append($0) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(delivered, [2])
    }

    // MARK: - つまむと地図（振動・地図で見る）

    func testPinchBuzzAndMapLink() throws {
        XCTAssertTrue(PinchToMap.buzzes(wasPast: false, isPast: true))
        XCTAssertFalse(PinchToMap.buzzes(wasPast: true, isPast: false), "広げて戻すときにも鳴った")
        XCTAssertTrue(PinchToMap.showsMapLink(hasPlace: true, nearbyCount: 0), "近くの写真が無いと「地図で見る」が出ない")
        XCTAssertFalse(PinchToMap.showsMapLink(hasPlace: false, nearbyCount: 0))
        // つまむ値は小さな部品の中だけ（写真の詳細の画面全体を描き直さない）
        let detail = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertFalse(detail.contains("@GestureState private var heroPinch"))
        XCTAssertTrue(detail.contains("PinchToMapHero(item:"))
    }

    // MARK: - 中黒で区切らない

    func testNoMiddleDots() {
        let trip = LibraryTrip(id: "t", shots: [], start: Date(), end: Date(), days: [], center: nil,
                               timeZone: .current)
        XCTAssertFalse(DevelopTrips.cardLine(trip, name: "金沢").contains("·"))
        XCTAssertFalse(YearAgoTrips.storyText(years: 1, name: "竹富町").contains("·"))
    }
}
