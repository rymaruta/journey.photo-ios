import XCTest
@testable import JourneyPhoto

/// 🔴 **画面が判定の関数につながっていること**（2026-10-02 のレビュー）。
///
/// 判定（`StoryPlayback.timeUp`・`StoryReel.faceLook`・`PhotoMapView.listEmpty` …）は
/// それぞれの試験で縛っているが、**画面側のつなぎを外しても**それらは通ったままになる。
/// 画面は Linux で描けないので、ソースに**つなぎの呼び出しが残っていること**を見る。
/// 書き方を変えたら、ここも合わせて直す（消したら落ちるのが目的）
final class ScreenWiringTests: XCTestCase {

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

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// 読み上げ: 自動で送らない判定に読み上げの状態を渡す・操作を出す
    func testStoryViewerWiresVoiceOver() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("@Environment(\\.accessibilityVoiceOverEnabled)"))
        XCTAssertEqual(count("voiceOver: voiceOverOn", in: viewer), 2,
                       "時計（timeUp）と動画の終わり（mediaEnded）の両方に読み上げの状態を渡していない")
        XCTAssertTrue(viewer.contains(".onChange(of: voiceOverOn) { _, _ in settlePendingEnd() }"),
                      "読み上げを切っても控えた動画の終わりで進まない")
        XCTAssertTrue(viewer.contains(#".accessibilityAction(named: L("次へ", "Next")) { forward() }"#))
        XCTAssertTrue(viewer.contains(#".accessibilityAction(named: L("前へ", "Previous")) { voiceOverBack() }"#))
        XCTAssertTrue(viewer.contains("StoryPlayback.voiceOverPrevious("))
        XCTAssertTrue(viewer.contains(".accessibilityAction(.escape)"))
        XCTAssertEqual(count("StoryPlayback.forward(", in: viewer), 1)
        XCTAssertTrue(viewer.contains(".onTapGesture { forward() }"),
                      "右を押したときと読み上げの「次へ」が別の判定になっている")
    }

    /// 動きを減らす: 面の見せ方は `faceLook` の答えだけで描く
    func testStoryReelWiresReduceMotion() throws {
        let reel = try source("Features/Stories/StoryReelView.swift")
        XCTAssertTrue(reel.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(reel.contains("StoryReel.faceLook(minX: minX, width: width, reduceMotion: reduceMotion)"))
        XCTAssertTrue(reel.contains(".rotation3DEffect(.degrees(look.angle)"))
        XCTAssertTrue(reel.contains(".offset(x: look.offsetX)"))
        XCTAssertTrue(reel.contains(".opacity(look.opacity)"))
        XCTAssertFalse(reel.contains("StoryReel.cubeAngle("), "faceLook を通らずに回している")
        // ばねは「動きを減らす」を見る1か所（settleAnimation）だけ
        XCTAssertEqual(count(".spring(", in: reel), 1, "ばねを settleAnimation の外で使っている")
        XCTAssertTrue(reel.contains("reduceMotion ? .easeOut(duration: 0.2) : .spring("))
    }

    /// 地図のリスト: 空と失敗を `listEmpty` で分けている
    func testMapListWiresListEmpty() throws {
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertTrue(map.contains("switch Self.listEmpty(loadFailed: model.loadFailed, photosEmpty: model.photos.isEmpty,"))
    }

    /// ログアウト: メニューと設定の両方が共有の印（`AuthStore.startSigningOut`）を通る
    func testSignOutButtonsShareTheGate() throws {
        for path in ["Features/Common/SiteMenuView.swift", "Features/Settings/SettingsView.swift"] {
            let screen = try source(path)
            XCTAssertTrue(screen.contains("auth.startSigningOut {"), "\(path) が共有の印を通らずにログアウトしている")
            XCTAssertFalse(screen.contains("await auth.signOut()"), "\(path) が直にログアウトしている")
        }
    }

    /// ストーリー: 選んだ写真は上限時間つきで読む（`StorySimpleRules.readPicks`）
    func testStoryComposerReadsPicksWithTimeout() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("StorySimpleRules.readPicks("), "上限時間を通らずに写真を読んでいる")
        XCTAssertEqual(count("loadTransferable(", in: composer), 1, "readPicks の外で写真を読んでいる")
    }

    /// ストーリー: 閉じる確認の「下書きに保存」は読み込み中を見る（`leaveDialog`）
    func testStoryComposerLeaveDialogSeesLoading() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("canSave: leaveDialog.canSave"))
        XCTAssertTrue(composer.contains("loading: loadingPicks > 0"))
        XCTAssertTrue(composer.contains("if let blocked = Self.draftSaveBlockedNote(loading: loadingPicks > 0) {"),
                      "読み込み中の下書き保存が黙って戻る")
    }

    /// 写真詳細: 吹き出しの数と読み上げは見出しと同じ `visibleCommentCount`（ブロックした人の分を引く・2026-10-07）
    func testPhotoDetailBubbleCountMatchesHeading() throws {
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains(#"actionLabel(systemImage: "bubble.right", count: visibleCommentCount)"#),
                      "吹き出しの数がサーバーの総数のまま（見出しと食い違う）")
        XCTAssertEqual(count("CommentsHeading.label(commentCount: visibleCommentCount)", in: detail), 2,
                       "吹き出しの読み上げと見出しが同じ数を読まない")
        XCTAssertFalse(detail.contains("commentCount: model.commentCount"), "ブロックした人の分を含む数を出している")
        XCTAssertFalse(detail.contains("count: model.commentCount"), "ブロックした人の分を含む数を出している")
    }

    /// ストーリーの反応: 数はブロックした人を落としてから数える（一覧と合わせる・2026-10-07）
    func testStoryInsightsCountsDropBlockedPeople() throws {
        let insights = try source("Features/Stories/StoryInsightsView.swift")
        XCTAssertTrue(insights.contains("viewersLoaded ? dropped.viewers(viewers).count : nil"))
        XCTAssertTrue(insights.contains("repliesLoaded ? dropped.replies(replies).reactionCount : nil"))
        XCTAssertTrue(insights.contains("repliesLoaded ? dropped.replies(replies).textReplies.count : nil"))
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertEqual(count("viewers = BlockFilter.viewers(loaded, blocked: hidden.blockedUserIds)", in: viewer), 1,
                       "見た人の数・顔がブロックした人を含む")
        XCTAssertEqual(count("replies = BlockFilter.replies(loaded, blocked: hidden.blockedUserIds)", in: viewer), 2,
                       "初めの読み込みと読み直しの両方で返信を落としていない")
        XCTAssertFalse(viewer.contains("viewers = loaded"))
        XCTAssertFalse(viewer.contains("replies = loaded"))
    }

    /// 写真詳細の撮影地の行: 開いた写真を一覧に渡す。共有は並ぶ写真で URL を決める（2026-10-07）
    func testPlaceRowPassesOpenedPhotoAndShareSeesPhotos() throws {
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("TagPhotosView(kind: .location(location), opened: shown)"),
                      "下書き・限定写真から開くと空の一覧になる")
        let tag = try source("Features/Gallery/TagPhotosView.swift")
        XCTAssertTrue(tag.contains("CollectionScreen.withOpened(PhotoQuery.photos(all, in: kind), opened: opened, kind: kind)"))
        let screen = try source("Features/Gallery/CollectionPhotosScreen.swift")
        XCTAssertTrue(screen.contains("photos: shown)"), "共有の URL を並ぶ写真で決めていない")
    }

    /// 英語の枚数は単数形を持つ `photoCountLabel` を通す（「1 photos」と出ていた・2026-10-07）
    func testPhotoCountsUseSingularAwareLabel() throws {
        for path in ["Core/Text/CollectionScreen.swift", "Features/Gallery/HomeTopCardView.swift",
                     "Core/Text/TripBookFacts.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains(".photoCountLabel("), path)
            XCTAssertFalse(text.contains("count) photos\")"), "\(path) が「1 photos」と出す")
            XCTAssertFalse(text.contains("count)枚\", \"\\("), "\(path) が単数形を持たない枚数を組んでいる")
        }
    }
}
