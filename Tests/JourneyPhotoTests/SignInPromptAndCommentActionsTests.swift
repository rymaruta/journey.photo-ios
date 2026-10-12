import XCTest
@testable import JourneyPhoto

/// 2026-10-11 の使い勝手の直し:
/// 1. 未ログインのいいね・保存・2回叩くから「ログインする」へ進める（`SignInPrompt`）
/// 2. 人のコメントの「…」から通報・ブロック（`PhotoDetailRules.commentActions`・
///    `ModerationService.commentReportNote`）
final class SignInPromptTests: XCTestCase {

    /// 未ログインと分かっているときだけ「ログインする」を出す。確認中・ログイン済みには出さない
    func testRequestOnlyWhenSignedOut() {
        let request = SignInPrompt.request(SignInPrompt.like, userId: nil, isResolving: false)
        XCTAssertEqual(request?.reason, SignInPrompt.like)
        XCTAssertNil(SignInPrompt.request(SignInPrompt.like, userId: nil, isResolving: true),
                     "確認中に促すと、ログイン済みの人にも出る")
        XCTAssertNil(SignInPrompt.request(SignInPrompt.save, userId: "me", isResolving: false))
    }

    /// コメントの欄の代わりの1行は、未ログインでコメントを受け付ける写真のときだけ
    func testCommentLine() {
        XCTAssertTrue(SignInPrompt.showsCommentLine(userId: nil, isResolving: false, acceptsReactions: true))
        XCTAssertFalse(SignInPrompt.showsCommentLine(userId: "me", isResolving: false, acceptsReactions: true))
        XCTAssertFalse(SignInPrompt.showsCommentLine(userId: nil, isResolving: true, acceptsReactions: true))
        XCTAssertFalse(SignInPrompt.showsCommentLine(userId: nil, isResolving: false, acceptsReactions: false))
        XCTAssertEqual(SignInPrompt.commentLine, "ログインするとコメントできます")
        XCTAssertEqual(SignInPrompt.actionLabel, "ログインする")
    }
}

final class CommentActionsTests: XCTestCase {

    /// 人の写真の、人のコメント: 通報とブロック
    func testOthersCommentOnOthersPhoto() {
        let a = PhotoDetailRules.commentActions(commentUid: "u2", viewerId: "me", isMine: false, deletedUser: false)
        XCTAssertTrue(a.report)
        XCTAssertTrue(a.block)
    }

    /// 自分の写真の、人のコメント: ブロックだけ（写真の通報の口は自分の写真に送れない・削除は出ている）
    func testOthersCommentOnMyPhoto() {
        let a = PhotoDetailRules.commentActions(commentUid: "u2", viewerId: "me", isMine: true, deletedUser: false)
        XCTAssertFalse(a.report)
        XCTAssertTrue(a.block)
    }

    /// 自分のコメント・退会した人・未ログインには出さない
    func testNoMenu() {
        for a in [
            PhotoDetailRules.commentActions(commentUid: "me", viewerId: "me", isMine: false, deletedUser: false),
            PhotoDetailRules.commentActions(commentUid: "u2", viewerId: "me", isMine: false, deletedUser: true),
            PhotoDetailRules.commentActions(commentUid: "u2", viewerId: nil, isMine: false, deletedUser: false),
        ] {
            XCTAssertFalse(a.report)
            XCTAssertFalse(a.block)
        }
    }
}

final class CommentReportNoteTests: XCTestCase {

    private let comment = ModerationService.ReportedComment(
        id: "c-123", authorId: "user-abc", authorName: "旅人", text: "ひどい\nコメント")

    /// 誰の・どのコメント・本文・本人の補足が1行で入る（改行はサーバーで消えるので空白に）
    func testNoteCarriesAuthorAndText() {
        let note = ModerationService.commentReportNote(comment, note: "何度も\n書かれる")
        XCTAssertEqual(note,
                       "[コメントの通報] 投稿者: 旅人 (user-abc) / コメントID: c-123 / 補足: 何度も 書かれる / 本文: ひどい コメント")
        XCTAssertEqual(ModerationService.commentReportNote(comment, note: "  "),
                       "[コメントの通報] 投稿者: 旅人 (user-abc) / コメントID: c-123 / 本文: ひどい コメント")
    }

    /// 長いコメント・長い補足でもサーバーの上限（500・UTF-16）に収め、頭は切らない
    func testNoteFitsServerLimit() {
        let long = ModerationService.ReportedComment(
            id: "c-1", authorId: "user-abc", authorName: "旅人", text: String(repeating: "😀", count: 400))
        let note = ModerationService.commentReportNote(long, note: String(repeating: "あ", count: 600))
        XCTAssertLessThanOrEqual(PostLimits.length(note), ModerationService.reportNoteMax)
        XCTAssertTrue(note.hasPrefix("[コメントの通報] 投稿者: 旅人 (user-abc) / コメントID: c-1 / 補足: "))
        XCTAssertTrue(note.contains(" / 本文: 😀"), "本文が補足に押し出されている")
        // 送る形（`reportNote`）を通しても切られない
        XCTAssertEqual(ModerationService.reportNote(note), note)
    }

    func testFromComment() throws {
        let decoded = try JSONDecoder().decode(
            PhotoComment.self,
            from: Data(#"{"id":"c9","uid":"u9","name":"山の人","text":"こんにちは","t":null,"deleted":null}"#.utf8))
        XCTAssertEqual(ModerationService.ReportedComment(decoded),
                       ModerationService.ReportedComment(id: "c9", authorId: "u9", authorName: "山の人", text: "こんにちは"))
    }
}

/// 画面が上の判定につながっていること（画面は Linux で描けないので、ソースのつなぎを見る。
/// `ScreenWiringTests` と同じ考え——消したら落ちるのが目的）
final class UsabilityWiringTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 写真の詳細: いいね・保存から「ログインする」、コメントの欄の代わりの1行、コメントの「…」
    func testPhotoDetailWiring() throws {
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("SignInPrompt.request(SignInPrompt.like, userId: auth.userId, isResolving: auth.isResolving)"))
        XCTAssertTrue(detail.contains("SignInPrompt.request(SignInPrompt.save, userId: auth.userId, isResolving: auth.isResolving)"))
        XCTAssertFalse(detail.contains(#"actionError = L("保存するにはログインしてください""#),
                       "保存の断りが赤字だけに戻っている")
        XCTAssertTrue(detail.contains(".signInPrompt(ask: $signInAsk, open: $signInOpen)"))
        XCTAssertTrue(detail.contains("SignInPrompt.showsCommentLine("))
        XCTAssertTrue(detail.contains("signInOpen = SignInRequest(reason: SignInPrompt.comment)"))
        XCTAssertTrue(detail.contains("signInResolving: auth.isResolving"))
        XCTAssertTrue(detail.contains("PhotoDetailRules.commentActions("))
        XCTAssertTrue(detail.contains("ReportSheet(photoId: current.id, ownerId: ownerId, comment: .init(comment))"))
        XCTAssertTrue(detail.contains("commentAuthorBlockedWhenReporting"),
                      "コメント通報のブロック後始末が無い")
        XCTAssertTrue(detail.contains("Task { await block(comment.uid) }"))
        XCTAssertTrue(detail.contains("Text(LocationMatch.display(location))"), "撮影地の行が住所のまま")
    }

    /// ホームの♥: 知らせだけでなく「ログインする」
    func testHomeLikeWiring() throws {
        let home = try source("Features/Gallery/HomeMosaic.swift")
        XCTAssertTrue(home.contains("signInAsk = SignInPrompt.request(SignInPrompt.like"))
        XCTAssertTrue(home.contains(".signInPrompt(ask: $signInAsk, open: $signInOpen)"))
        XCTAssertFalse(home.contains(#"toasts.show(L("いいねするにはログインしてください""#),
                       "ホームの♥が3秒の知らせだけに戻っている")
    }

    /// 大きく見る画面: 未ログインの2回叩くはハートを出さずに「ログインする」
    func testViewerWiring() throws {
        let viewer = try source("Features/PhotoDetail/PhotoViewerView.swift")
        // 注記の行は数えないので、促す1行がすぐ続く（`showBurst()` を挟まない）
        XCTAssertTrue(viewer.contains("case .askToSignIn:\n            signInAsk = SignInRequest(reason: SignInPrompt.like)\n        case .ignore:"),
                      "未ログインの2回叩くでハートを出している")
        XCTAssertTrue(viewer.contains(".signInPrompt(ask: $signInAsk, open: $signInOpen)"))
        XCTAssertTrue(viewer.contains("signInResolving: signInResolving)"))
        XCTAssertTrue(viewer.contains("let place = LocationMatch.display(current?.location)"))
    }

    /// 通報のシート: コメントの通報は補足に誰のどのコメントかを書き、写真は消さない
    func testReportSheetCommentMode() throws {
        let sheet = try source("Features/Social/ReportSheet.swift")
        XCTAssertTrue(sheet.contains("comment.map { ModerationService.commentReportNote($0, note: note) } ?? note"))
        XCTAssertTrue(sheet.contains("if comment == nil {\n                hidden.markReported(photoId, for: blocker)"),
                      "コメントの通報で写真ごと消している")
        XCTAssertTrue(sheet.contains("try await environment.moderation.block(userId: blockTarget)"))
    }

    /// 撮影スポットの見出し（写真 → 撮影地）も縮めた名前
    func testSpotHeadingWiring() throws {
        let spot = try source("Features/Spots/SpotDetailView.swift")
        XCTAssertTrue(spot.contains("Text(LocationMatch.display(spot.label))"))
        XCTAssertTrue(spot.contains(".navigationTitle(LocationMatch.display(spot.label))"))
        // 地図の検索は元の文字で（縮めた名前で引くと別の場所に当たる）
        XCTAssertTrue(spot.contains("SpotScreen.mapURL(name: spot.label, coords: place.coords)"))
    }
}
