import XCTest
@testable import JourneyPhoto

/// ストーリーとそこから作った写真の関係（2026-11-11 判断・`StoryPhotoLink`）。
/// 消すときの約束（画像の置き去り・退会）はサーバーの `storyKeptMedia.test.ts` が縛る。ここは画面の側
final class StoryPhotoLinkTests: XCTestCase {

    private func story(_ extra: String) throws -> Story {
        try JSONDecoder.api.decode(Story.self, from: Data("""
        {"id":"s1","src":"https://example.com/a.jpg"\(extra)}
        """.utf8))
    }

    private func photo(_ extra: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data("""
        {"id":"p1","src":"https://example.com/p.jpg"\(extra)}
        """.utf8))
    }

    /// 写真にしたときの写真の id（`keptAs`）を読む。空は無いのと同じ
    func testStoryReadsKeptAs() throws {
        XCTAssertEqual(try story(#","keptAs":"p9""#).keptAs, "p9")
        XCTAssertNil(try story("").keptAs)
        XCTAssertNil(try story(#","keptAs":"""#).keptAs)
        // 形が崩れていても一覧ごと落とさない
        XCTAssertNil(try story(#","keptAs":3"#).keptAs)
    }

    /// 写真の元のストーリー（共有の `keptFrom`・写しの `fromStory`）
    func testPhotoReadsSourceStory() throws {
        XCTAssertEqual(try photo(#","keptFrom":"s1""#).sourceStoryId, "s1")
        XCTAssertEqual(try photo(#","fromStory":"s2""#).sourceStoryId, "s2")
        XCTAssertNil(try photo("").sourceStoryId)
    }

    /// 自分用に残すストーリーも写真にできる。動画・写真にしたあとは出さない
    func testCanKeep() {
        XCTAssertTrue(StoryPhotoLink.canKeep(isVideo: false, keptPhotoId: nil))
        XCTAssertFalse(StoryPhotoLink.canKeep(isVideo: true, keptPhotoId: nil))
        XCTAssertFalse(StoryPhotoLink.canKeep(isVideo: false, keptPhotoId: "p1"))
    }

    /// 消す確認: 写真のいいね・コメントがあれば数を添える。無ければ添えない
    func testStoryDeleteMessageCounts() {
        let none = StoryPhotoLink.storyDeleteMessage(likes: nil, comments: nil)
        XCTAssertFalse(none.contains("消えます"), none)
        XCTAssertTrue(StoryPhotoLink.storyDeleteMessage(likes: 3, comments: 2).contains("いいね 3・コメント 2 も消えます"))
        XCTAssertTrue(StoryPhotoLink.storyDeleteMessage(likes: 0, comments: 1).contains("コメント 1 も消えます"))
    }

    /// 「捨てる」を使わない（owner の好み・`NoDiscardWordingTests`）
    func testNoDiscardWording() {
        let all = [StoryPhotoLink.madeIntoPhoto, StoryPhotoLink.madeFromStory,
                   StoryPhotoLink.deleteWithPhoto, StoryPhotoLink.deleteStoryOnly,
                   StoryPhotoLink.deleteWithStory, StoryPhotoLink.deletePhotoOnly,
                   StoryPhotoLink.photoDeleteMessage,
                   StoryPhotoLink.storyDeleteMessage(likes: 4, comments: 5)]
        for text in all { XCTAssertFalse(text.contains("捨"), text) }
    }

    /// 元のストーリーを探す: 写真が元の id を持っていればそれ、無ければストーリーの `keptAs` で
    func testSourceLookup() throws {
        let a = try story(#","keptAs":"p1""#)
        let other = try JSONDecoder.api.decode(Story.self, from: Data(#"{"id":"s2","src":"x"}"#.utf8))
        XCTAssertEqual(StoryPhotoLink.source(of: "p1", sourceStoryId: nil, in: [other, a])?.id, "s1")
        XCTAssertEqual(StoryPhotoLink.source(of: "p9", sourceStoryId: "s2", in: [other, a])?.id, "s2")
        XCTAssertNil(StoryPhotoLink.source(of: "p9", sourceStoryId: "gone", in: [other, a]))
    }

    /// 画面のつなぎ（Linux では描けないのでソースを見る）: 写真にした1本は2つの選び方、
    /// 「写真も一緒に消す」は写真の口に withStory（true）で頼む
    func testViewerWiring() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let viewer = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Stories/StoryViewerView.swift"), encoding: .utf8)
        XCTAssertTrue(viewer.contains("confirmButton(StoryPhotoLink.deleteWithPhoto, color: Self.storyDanger"))
        XCTAssertTrue(viewer.contains("confirmButton(StoryPhotoLink.deleteStoryOnly, color: .white"))
        XCTAssertTrue(viewer.contains("try await environment.photos.delete(photoId: withPhoto, withStory: true)"))
        XCTAssertTrue(viewer.contains("Text(StoryPhotoLink.madeIntoPhoto)"))
        let detail = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift"), encoding: .utf8)
        XCTAssertTrue(detail.contains("Button(StoryPhotoLink.deleteWithStory, role: .destructive) { Task { await deletePhoto(withStory: true) } }"))
        XCTAssertTrue(detail.contains("Button(StoryPhotoLink.deletePhotoOnly) { Task { await deletePhoto(withStory: false) } }"))
        // 「写真も一緒に消す」: 写真が 404 でもストーリーの口でも消す・消した写真を一覧から落とす・詳細も閉じる
        XCTAssertTrue(viewer.contains("try await environment.stories.delete(id: story.id)\n                } catch where SocialService.isNotFound(error) {}"),
                      "写真がもう無い（404）ときにストーリーを残す")
        XCTAssertTrue(viewer.contains("await hidden.hideGone(withPhoto, for: owner, environment: environment, deleted: true)"),
                      "消した写真が公開一覧・控えに残る")
        XCTAssertTrue(viewer.contains("onPhotoDeleted?(withPhoto)"))
        XCTAssertTrue(detail.contains("onPhotoDeleted: { photoId in"))
        // 元のストーリーは、元の id を持つ写真のときだけ読む（開くたびに一覧2つを読まない）
        XCTAssertTrue(detail.contains("guard isMine, auth.userId != nil, photo.sourceStoryId != nil else { sourceStory = nil; return }"),
                      "自分の写真を開くたびにストーリーの一覧を読んでいる")
        let service = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Services/PhotoService.swift"), encoding: .utf8)
        XCTAssertTrue(service.contains(#"query: withStory.map { ["withStory": $0 ? "1" : "0"] } ?? [:]"#))
    }
}
