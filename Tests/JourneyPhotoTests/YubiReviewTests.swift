import XCTest
@testable import JourneyPhoto

/// 第6章（札 #543）の確かめ役の指摘（2026-11-12）の直し。直しを戻すと落ちることを確かめてある
final class YubiReviewTests: XCTestCase {

    private let w = 390.0, h = 844.0

    private func photo(_ id: String, owner: String?) throws -> Photo {
        let u = owner.map { ",\"userId\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(u)}".utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 1. 手に取ったまま身振りが取り消されても、幕を残さない

    /// 離した（`end`）が来ないまま身振りが終わったら戻す。幕（`isHolding`）が残らない
    @MainActor
    func testCancelledGestureReleasesTheLift() async throws {
        let center = PhotoLiftCenter()
        let p = try photo("a", owner: "me")
        center.lift(p, at: CGPoint(x: 100, y: 300))
        XCTAssertTrue(center.isHolding)
        center.gestureReset(photoId: "a")
        XCTAssertNil(center.photo, "身振りが取り消されたのに手に取ったまま")
        XCTAssertFalse(center.isHolding, "幕が残った")
        XCTAssertFalse(PhotoLiftCenter.holding, "縦の送りが止まったまま")
        XCTAssertNil(center.drop, "取り消された身振りで行き先を実行した")
    }

    /// 離したあとに身振りが戻っても、離した1回は消さない。別の写真の身振りでは戻さない
    @MainActor
    func testNormalReleaseKeepsTheDrop() async throws {
        let center = PhotoLiftCenter()
        let p = try photo("a", owner: "me")
        center.lift(p, at: CGPoint(x: 100, y: 300))
        center.move(to: CGPoint(x: 380, y: 430))
        center.end()
        center.gestureReset(photoId: "a")
        XCTAssertNotNil(center.drop)
        center.lift(p, at: CGPoint(x: 100, y: 300))
        center.gestureReset(photoId: "b")
        XCTAssertNotNil(center.photo, "別の写真の身振りで戻した")
    }

    /// 裏に回る・通知センターで戻す。幕を押しても戻す（送る人の列も）
    @MainActor
    func testSceneAndBackdropCancel() async throws {
        let center = PhotoLiftCenter()
        let p = try photo("a", owner: "me")
        center.lift(p, at: .zero)
        center.sceneChanged(active: true)
        XCTAssertNotNil(center.photo)
        center.sceneChanged(active: false)
        XCTAssertFalse(center.isHolding, "裏に回っても手に取ったまま")
        center.lift(p, at: .zero)
        center.openFaces(for: p)
        center.backdropTapped()
        XCTAssertFalse(center.isHolding, "幕を押しても戻らない")
        XCTAssertNil(center.facesOpenFor)
    }

    // MARK: - 動かさずに離したら元へ戻る

    func testReleaseWithoutMovingPutsBack() {
        let size = CGSize(width: w, height: h)
        // 手に取った所が右の半円の上でも、動かさずに離したら保存しない
        let still = [PhotoLiftCenter.Sample(t: 0, x: 330, y: 430), PhotoLiftCenter.Sample(t: 0.5, x: 332, y: 431)]
        XCTAssertNil(PhotoLift.resolve(point: CGPoint(x: 332, y: 431), samples: still, size: size, faces: 4, allowsStory: true).target,
                     "動かさずに離しただけで保存した")
        // 指の跡が無い（指の位置が届かないまま）も戻る
        XCTAssertNil(PhotoLift.resolve(point: CGPoint(x: 330, y: 430), samples: [], size: size, faces: 4, allowsStory: true).target)
        // 運べば保存
        let carried = [PhotoLiftCenter.Sample(t: 0, x: 150, y: 430), PhotoLiftCenter.Sample(t: 1, x: 330, y: 430)]
        XCTAssertEqual(PhotoLift.resolve(point: CGPoint(x: 330, y: 430), samples: carried, size: size, faces: 4, allowsStory: true).target, .save)
    }

    /// 札の真ん中で代えた位置は指の跡にしない（動かした距離を見誤らない）
    @MainActor
    func testLiftWithoutFingerStartsTraceAtFirstMove() async throws {
        let center = PhotoLiftCenter()
        center.lift(try photo("a", owner: "me"), at: CGPoint(x: 330, y: 430), fingerKnown: false)
        center.move(to: CGPoint(x: 335, y: 432))
        center.end()
        let drop = try XCTUnwrap(center.drop)
        XCTAssertEqual(drop.samples.count, 1)
        XCTAssertNil(PhotoLift.resolve(point: drop.point, samples: drop.samples, size: CGSize(width: w, height: h),
                                       faces: 4, allowsStory: true).target)
    }

    // MARK: - 3. ストーリーの行き先は自分の写真だけ

    func testStoryOnlyForOwnPhotos() {
        XCTAssertTrue(PhotoLift.allowsStory(ownerId: "me", me: "me"))
        XCTAssertFalse(PhotoLift.allowsStory(ownerId: "other", me: "me"), "他人の写真をストーリーへ運べる")
        XCTAssertFalse(PhotoLift.allowsStory(ownerId: nil, me: "me"))
        XCTAssertFalse(PhotoLift.allowsStory(ownerId: "me", me: nil))
        XCTAssertNil(PhotoLift.target(x: 200, y: 60, width: w, height: h, faces: 4, allowsStory: false),
                     "他人の写真で上の帯が行き先になった")
        XCTAssertNil(PhotoLift.near(x: 200, y: 140, width: w, height: h, faces: 4, allowsStory: false))
        // 上へ弾いても何もしない
        let up = [PhotoLiftCenter.Sample(t: 0, x: 200, y: 500), PhotoLiftCenter.Sample(t: 0.05, x: 200, y: 400)]
        let size = CGSize(width: w, height: h)
        XCTAssertEqual(PhotoLift.resolve(point: CGPoint(x: 200, y: 400), samples: up, size: size, faces: 4, allowsStory: true).target, .story)
        XCTAssertNil(PhotoLift.resolve(point: CGPoint(x: 200, y: 400), samples: up, size: size, faces: 4,
                                       allowsStory: false).target, "他人の写真を上へ弾いてストーリーにした")
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
        XCTAssertTrue(overlay.contains("return PhotoLift.allowsStory(ownerId: photo.userId ?? photo.uploadedBy, me: auth.userId)"))
        // 画面から行き先を決める呼び出しは、どれも写真ごとの答え（`allowsStory(…)`）を渡す
        let calls = overlay.components(separatedBy: "allowsStory: ").dropFirst()
        XCTAssertGreaterThanOrEqual(calls.count, 4)
        for call in calls where !call.hasPrefix("Bool") {
            XCTAssertTrue(call.hasPrefix("allowsStory(") || call.hasPrefix("allowsStory)"), String(call.prefix(60)))
        }
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

    // MARK: - 長押しの案内・身振りの形

    func testIntroAndGestureState() throws {
        XCTAssertTrue(PhotoLift.showsIntro(signedIn: true, alreadyShown: false))
        XCTAssertFalse(PhotoLift.showsIntro(signedIn: true, alreadyShown: true), "案内を2回出した")
        XCTAssertFalse(PhotoLift.showsIntro(signedIn: false, alreadyShown: false))
        XCTAssertFalse(PhotoLift.introText.contains("・"))
        let tile = try source("Sources/JourneyPhoto/Features/Gallery/HomeMosaic.swift")
        XCTAssertTrue(tile.contains("@GestureState private var lifted"), "手に取った印が身振りの終わりで戻らない")
        XCTAssertTrue(tile.contains("gestureReset(photoId:"))
        XCTAssertFalse(tile.contains(".onGeometryChange(for: CGRect.self)"), "全部の札で送るたびに座標を読む")
    }

    // MARK: - 中黒で区切らない

    func testNoMiddleDots() {
        let trip = LibraryTrip(id: "t", shots: [], start: Date(), end: Date(), days: [], center: nil,
                               timeZone: .current)
        XCTAssertFalse(DevelopTrips.cardLine(trip, name: "金沢").contains("·"))
        XCTAssertFalse(YearAgoTrips.storyText(years: 1, name: "竹富町").contains("·"))
    }
}
