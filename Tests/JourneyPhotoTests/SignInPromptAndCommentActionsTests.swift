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

/// ログインのお願いに新規登録も出す（札 #630・2026-11-15 owner「会員登録もそこに出したい」）。
/// お願いの「新規登録」は今のログイン画面（`SignInView`）を**登録の側**で開く。画面そのものは変えない。
/// 画面の部品は Linux で動かせないので、決まりは値で、配線は元のコードを読んで確かめる
/// （押した先は `ScreenshotTests.testSignInAskOffersSignUp`・`testCapturesHomeSignUpBenefits`）
final class SignInAskSignUpTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 字は Web の「登録するとできること」の2つ（`SIGNUP_BENEFITS_SIGNUP`・`SIGNUP_BENEFITS_LOGIN`）と同じ
    func testLabelsMatchWeb() {
        XCTAssertEqual(SignInPrompt.signUpLabel, "新規登録")
        XCTAssertEqual(SignInPrompt.loginLabel, "ログイン")
    }

    /// 何も言わなければログインの側（今までどおり）。登録の側は名指ししたときだけ
    func testRequestDefaultsToSignInSide() {
        XCTAssertEqual(SignInRequest(reason: "x").entry, .signIn)
        XCTAssertEqual(SignInRequest(reason: "x", entry: .signUp).entry, .signUp)
        XCTAssertEqual(SignInPrompt.request(SignInPrompt.like, userId: nil, isResolving: false)?.entry, .signIn)
    }

    /// 確認（いいね・保存・2回叩く）: 「新規登録」を先（主）に、押したら登録の側でシートを開く
    func testAlertOffersSignUpFirst() throws {
        let prompt = try source("Features/Auth/SignInPrompt.swift")
        let alert = prompt.components(separatedBy: "presenting: ask) { request in").last?
            .components(separatedBy: "} message:").first ?? ""
        let signUp = alert.range(of: "Button(SignInPrompt.signUpLabel) { open = SignInRequest(reason: request.reason, entry: .signUp) }")
        let signIn = alert.range(of: "Button(SignInPrompt.actionLabel) { open = request }")
        XCTAssertNotNil(signUp, "確認に新規登録が無い（または登録の側で開かない）")
        XCTAssertNotNil(signIn, "確認にログインが無い")
        if let signUp, let signIn { XCTAssertLessThan(signUp.lowerBound, signIn.lowerBound, "新規登録が先（主）でない") }
        XCTAssertTrue(prompt.contains("SignInSheet(reason: request.reason, entry: request.entry)"), "開く側をシートに渡していない")
        XCTAssertTrue(prompt.contains("SignInView(reason: reason, entry: entry)"), "開く側をログイン画面に渡していない")
    }

    /// ログイン画面は**開いたときの側を選ぶだけ**。登録の側は今の「アカウントを作る」を押した後と同じ `.signUp`
    func testSignInViewStartsOnRequestedSide() throws {
        let view = try source("Features/Auth/SignInView.swift")
        XCTAssertTrue(view.contains("init(reason: String?, entry: SignInEntry = .signIn) {\n        self.reason = reason\n        _mode = State(initialValue: entry == .signUp ? .signUp : .signIn)\n    }"))
        XCTAssertTrue(view.contains("mode = mode == .signIn ? .signUp : .signIn"), "「アカウントを作る」の切り替えが変わった")
        XCTAssertTrue(view.contains(#"L("アカウントを作る", "Create an account")"#), "ログイン画面の字を変えている")
    }

    /// 並べる部品: 新規登録が主ボタン（写真の有無で白か真鍮・`JPPillStyle.main`）、ログインは線のボタン。新規登録が先
    func testAskButtonsPutSignUpFirst() throws {
        let prompt = try source("Features/Auth/SignInPrompt.swift")
        let buttons = prompt.components(separatedBy: "struct SignInAskButtons: View {").last ?? ""
        let signUp = buttons.range(of: "Text(SignInPrompt.signUpLabel).jpPillButton(.main(onPhoto: onPhoto))")
        let signIn = buttons.range(of: "Text(SignInPrompt.loginLabel).jpPillButton(.outline)")
        XCTAssertNotNil(signUp)
        XCTAssertNotNil(signIn)
        if let signUp, let signIn { XCTAssertLessThan(signUp.lowerBound, signIn.lowerBound) }
        XCTAssertTrue(buttons.contains("open(SignInRequest(reason: reason, entry: .signUp))"))
    }

    /// 行の中のお願い（コメントの欄の代わりの1行・招待の参加の帯）にも新規登録がある
    func testInlineAsksOfferSignUp() throws {
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains(#"commentSignInLink(SignInPrompt.signUpLabel, entry: .signUp, identifier: "photoDetail.comment.signUp")"#),
                      "コメントの1行に新規登録が無い")
        XCTAssertTrue(detail.contains("signInOpen = SignInRequest(reason: SignInPrompt.comment, entry: entry)"))
        let invite = try source("Features/Albums/InviteView.swift")
        XCTAssertTrue(invite.contains(#"SignInAskButtons(reason: Self.signInReason, onPhoto: true, identifier: "invite") { signInOpen = $0 }"#),
                      "招待の帯に新規登録が無い（一行だけの行き止まり）")
        XCTAssertTrue(invite.contains(".signInPrompt(ask: $signInAsk, open: $signInOpen)"))
        XCTAssertEqual(InviteView.signInReason, "参加するにはログインしてください")
    }

    /// 撮影スポットを払う画面の挟む札: 主ボタンは登録の側、下の文字のボタンと足元の「地図で見る」はログインの側
    func testSpotSwipePauseOpensSignUp() throws {
        let view = try source("Features/Trips/SpotSwipeView.swift")
        let main = view.components(separatedBy: "private func mainAction() {").last?
            .components(separatedBy: "\n    }\n").first ?? ""
        XCTAssertTrue(main.contains("signIn = SignInRequest(reason: SpotSwipe.signInReason, entry: .signUp)"))
        XCTAssertTrue(view.contains("secondaryTitle: signedIn ? nil : SpotSwipe.loginTitle"))
        XCTAssertTrue(view.contains("let login: (() -> Void)? = signedIn ? nil : { signInFromFooter() }"))
        XCTAssertTrue(view.contains("signedIn ? mainAction() : signInFromFooter()"))
        XCTAssertTrue(view.contains("SignInSheet(reason: request.reason, entry: request.entry)"))
    }

    /// 中黒で区切らない・「捨てる」を使わない（owner の好み）
    func testWording() {
        for text in [SignInPrompt.signUpLabel, SignInPrompt.loginLabel, SpotSwipe.actionTitle(signedIn: false),
                     SpotSwipe.loginTitle, InviteView.signInReason] {
            XCTAssertFalse(text.contains("・") || text.contains("·") || text.contains("捨て"), text)
        }
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
        // 2026-11-15（札 #630）: コメントの1行は「新規登録」と「ログイン」の2つ（開く側を渡す）
        XCTAssertTrue(detail.contains("signInOpen = SignInRequest(reason: SignInPrompt.comment, entry: entry)"))
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
        // 2026-10-16: すれちがいのひとことの通報でも写真は消さない（`passNote`）
        XCTAssertTrue(sheet.contains("if comment == nil && passNote == nil {\n                hidden.markReported(photoId, for: blocker)"),
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
