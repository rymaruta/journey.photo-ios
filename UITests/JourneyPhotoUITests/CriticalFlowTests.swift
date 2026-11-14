import XCTest

/// **利用者の大事な流れを、画面を押して確かめる**（2026-10-22）。
///
/// `ScreenshotTests` は「出なければ撮らずに抜ける」決まりで、押した結果が画面に出たかは見ていない。
/// ここは逆に、**押せない・結果が出ないなら必ず落とす**:
///
///   1. 投稿: 写真を選ぶ → 題・撮影地 → 投稿 → マイページに並ぶ
///   2. いいね・保存: 押して数と印が変わる → もう一度で戻る
///   3. コメント: 書いて送る → 一覧に出る（送れなかった知らせは `PhotoDetailViewModel` の単体テストが見る）
///   4. ログアウト → ログイン（見本の認証）→ マイページに戻れる
///   5. キャンピングカー: 部屋に入る → 写真を飾る → 額に写る
///
/// 2026-10-22 判断: **書き込みは端末の中だけ**（`-JPPreviewLocalBackend`・`PreviewBackend`）。CI は資格情報を
/// 持たないので staging の試験用の利用者でも入れず、持たせるには Actions の秘密に触る。鍵の要る口だけを端末の中で答え、
/// 画面・ViewModel・Service・`APIClient` は本物の道を通る。**サーバー（staging・本番）には何も書かない**——読むのは
/// 公開の一覧・いいね数だけ（`ScreenshotTests` と同じ本番の公開の口）。後片付けも要らない（アプリを終えると消える）。
///
/// 手順は `ScreenshotTests` の private の道具と似ているが、あちらは「出なければ抜ける」、こちらは「出なければ落とす」で
/// 決まりが逆なので使い回さない
final class CriticalFlowTests: XCTestCase {

    /// 見本の利用者（`ScreenshotTests.previewUserId` と同じ・公開 API が誰にでも返している値で資格情報ではない）
    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"
    /// 見本の認証で通るメールアドレスとパスワード（`PreviewBackend.email`・`password`。端末の中だけ）
    private static let previewEmail = "preview@journey-photo.test"
    private static let previewPassword = "Preview-1234"
    /// 投稿のあとのカードを閉じた回数の鍵（`PostedCardHabit.defaultsKey` と同じ・UI テストはアプリの型を読めない）
    static let postedCardHabitKey = "postedCard.closedWithoutSharing"

    override func setUp() {
        continueAfterFailure = false
    }

    /// 見本の利用者・見本の通信で起動し、同意を済ませてタブまで出す
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        // 公開のいいね数を読む口（読むだけ。書く口は `PreviewBackend` が端末の中で答える）
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES"]
        // 投稿のあとの共有カードを、閉じた回数に関係なく毎回出す（`PostedCardHabit`）。引数の値は起動の間ずっと
        // 端末に覚えた回数より先に読まれる——同じ模擬機で投稿を3回するとカードが出ず知らせだけになる道をふさぐ
        app.launchArguments += ["-\(Self.postedCardHabitKey)", "0"]
        app.launchArguments += extra
        // 起動直後の動きの記録（失敗したら終わりにログと添付へ残す・札 #435・`PerfProbeSupport`）
        enablePerfProbe(app)
        let launched = Date()
        app.launch()
        attachPerfProbeOnFailure(app)
        // 規約の同意は 60 秒まで待ち、同意の画面が消えるまで 3 回まで押し直す（`ScreenshotTests.agreeToTerms` と同じ考え方・
        // 2026-10-22: Mac で起動から同意の画面まで 20 秒を超える回があり、30 秒で切ると別の所で落ちた・run 686・689）
        let agree = app.buttons["legal.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 60),
                      "起動から \(Int(Date().timeIntervalSince(launched))) 秒たっても同意の画面が出ない（落ちている可能性）")
        var taps = 0
        while agree.exists, taps < 3 {
            if agree.isHittable { agree.tap() } else { agree.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            taps += 1
            let gone = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: agree)], timeout: 5)
            if gone == .completed { break }
        }
        XCTAssertFalse(agree.exists, "規約の同意を押しても同意の画面が消えない（押した回数 \(taps)）")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "タブが出ない")
        return app
    }

    private func tab(_ app: XCUIApplication, _ index: Int) {
        let button = app.tabBars.firstMatch.buttons.element(boundBy: index)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "タブ \(index) が無い")
        button.tap()
    }

    /// `element` が押せるまで、勢いの付かない短い引きで送る（上限あり）。押せなければ落とす
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, _ what: String, pushes: Int = 8) {
        var n = 0
        while !(element.exists && element.isHittable), n < pushes {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            n += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(what) まで送っても押せない")
    }

    /// 欄を押し、**その欄に**キーボードの焦点が来てから打つ。来なければ押し直す（最長 `timeout` 秒）。
    ///
    /// 2026-10-22 判断: PR の検証で、題を打った直後に撮影地の欄を押しても焦点が移らず、
    /// `typeText` が「Neither element nor any descendant has keyboard focus」で落ちた
    /// （鍵盤が出てくる途中で画面がずれ、押した所が欄から外れる）。2つ目の欄では
    /// 「鍵盤が出ている」は焦点の手がかりにならないので、欄そのものの `hasKeyboardFocus` を見る。
    /// 非公開の属性なので**在るときだけ**読む（無い名前を KVC で読むと ObjC の例外で落ちる・
    /// `ScreenshotTests.waitForKeyboardFocus` と同じ扱い）。読めない環境では今までどおり押してすぐ打つ
    private func enter(_ text: String, into field: XCUIElement, _ what: String, timeout: TimeInterval = 8) {
        let readable = field.responds(to: NSSelectorFromString("hasKeyboardFocus"))
        func focused() -> Bool { (field.value(forKey: "hasKeyboardFocus") as? Bool) == true }
        field.tap()
        if readable {
            let deadline = Date().addingTimeInterval(timeout)
            while !focused(), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.5)
                if !focused(), field.isHittable { field.tap() }
            }
            XCTAssertTrue(focused(), "\(what) を押しても焦点が来ない")
        }
        field.typeText(text)
    }

    /// `element` が `predicate` を満たすまで待つ
    private func wait(_ element: XCUIElement, _ predicate: String, _ args: [Any] = [], timeout: TimeInterval = 15) -> Bool {
        let p = NSPredicate(format: predicate, argumentArray: args)
        return XCTWaiter().wait(for: [expectation(for: p, evaluatedWith: element)], timeout: timeout) == .completed
    }

    /// ホームの1枚目の写真を開く
    private func openFirstFeedPhoto(_ app: XCUIApplication) {
        tab(app, 0)
        let photo = app.buttons["feed.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), "ホームに写真が出ない")
        reveal(photo, in: app, "ホームの1枚目")
        photo.tap()
        XCTAssertTrue(app.buttons["photo.like"].firstMatch.waitForExistence(timeout: 15), "写真の詳細が開かない")
    }

    // MARK: - 2. いいね・保存

    /// いいねを押すと♥が灯って数が1増え、もう一度で元に戻る。保存も押すと印が付き、もう一度で外れる
    func testLikeAndSaveToggleAndRevert() {
        let app = launch()
        openFirstFeedPhoto(app)

        let like = app.buttons["photo.like"].firstMatch
        reveal(like, in: app, "いいね")
        // 数の読み込みを待つ（公開の数・読めない写真もある——そのときは印だけ見る）
        _ = wait(like, "value != ''", timeout: 10)
        let likedBefore = like.isSelected
        let countBefore = Int(like.value as? String ?? "")
        like.tap()
        XCTAssertTrue(wait(like, "selected == %@", [!likedBefore]), "いいねを押しても♥が変わらない")
        if let countBefore {
            let expected = countBefore + (likedBefore ? -1 : 1)
            XCTAssertTrue(wait(like, "value == %@", ["\(expected)"]),
                          "いいねの数が \(countBefore) → \(expected) にならない（今は \(String(describing: like.value))）")
        }
        like.tap()
        XCTAssertTrue(wait(like, "selected == %@", [likedBefore]), "もう一度押しても♥が戻らない")
        if let countBefore {
            XCTAssertTrue(wait(like, "value == %@", ["\(countBefore)"]),
                          "もう一度押しても数が \(countBefore) に戻らない（今は \(String(describing: like.value))）")
        }

        let save = app.buttons["photo.save"].firstMatch
        reveal(save, in: app, "保存")
        let savedBefore = save.isSelected
        save.tap()
        XCTAssertTrue(wait(save, "selected == %@", [!savedBefore]), "保存を押しても印が変わらない")
        // 送れなかった回は印が戻る（`toggleSave`）。答えが届いた後も変わったままか
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(save.isSelected, !savedBefore, "保存の印が送ったあとに戻った（送れていない）")
        save.tap()
        XCTAssertTrue(wait(save, "selected == %@", [savedBefore]), "もう一度押しても保存の印が戻らない")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(save.isSelected, savedBefore, "保存を外したあとに印が戻った（送れていない）")
    }

    // MARK: - 3. コメント

    /// コメントを書いて送ると、欄が空になり一覧に出る
    func testCommentPostsAndAppearsInList() {
        let app = launch()
        openFirstFeedPhoto(app)

        // 打つ文は1語（自動の直しが効かない形・英字の鍵盤でも日本語の鍵盤でも同じ字になる）
        let text = "CF\(Int(Date().timeIntervalSince1970) % 1_000_000)"
        let field = app.descendants(matching: .any).matching(identifier: "photo.commentField").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "コメントの欄が無い（ログイン中なのに）")
        enter(text, into: field, "コメントの欄")
        let send = app.buttons["photo.commentSend"].firstMatch
        XCTAssertTrue(wait(send, "enabled == true", timeout: 5), "書いたのに送信が押せない")
        send.tap()

        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        var pushes = 0
        while !row.waitForExistence(timeout: 3), pushes < 6 {
            app.swipeUp()
            pushes += 1
        }
        XCTAssertTrue(row.exists, "送ったコメント「\(text)」が一覧に出ない")
        XCTAssertFalse((field.value as? String ?? "").contains(text), "送ったのに欄に文が残っている")
    }

    // MARK: - 1. 投稿

    /// 見本の1枚を選んだ投稿画面で、題と撮影地を打って投稿 → 画面が閉じ、マイページの格子にその題の1枚が並ぶ
    func testPostPhotoAppearsOnMyPage() {
        let app = launch(["-JPPreviewUploadSample", "YES"])
        // 🔴 マイページを**出したまま**「投稿」を押す（2026-10-22 確かめ役の指摘）。投稿はシートで、閉じたとき出ている
        // マイページが上がった写真を先に並べる（`MyPageView` の `postSheetsClosed` → `showPosted`・`justPosted`）。
        // 後から開くと公開の一覧の読み直しの順番次第になり、並ぶ所が決まらない
        tab(app, 4)
        XCTAssertTrue(app.descendants(matching: .any)["mypage.nameLine"].firstMatch.waitForExistence(timeout: 20),
                      "ログイン中のマイページが出ない")
        tab(app, 2)
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        XCTAssertTrue(toPhoto.waitForExistence(timeout: 10), "投稿の2択が出ない")
        toPhoto.tap()
        let thumb = app.buttons["upload.thumb.0"].firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 20), "見本の1枚が投稿画面に入らない")
        // 2026-11-14（#188）: 「投稿する」は下の帯の主ボタン（板の投稿画面）。キーボードが出る前に、画面の下の方に
        // 幅いっぱい・高さ 44 以上で在るかを見る（右上の字に戻ると落ちる）
        let bottomSubmit = app.buttons["upload.submit"].firstMatch
        XCTAssertTrue(bottomSubmit.waitForExistence(timeout: 5), "下の「投稿する」が無い")
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(bottomSubmit.frame.minY, screen.height * 0.8,
                             "「投稿する」が下に無い（frame \(bottomSubmit.frame)・画面 \(screen)）")
        XCTAssertGreaterThan(bottomSubmit.frame.width, screen.width * 0.8, "「投稿する」が幅いっぱいでない（\(bottomSubmit.frame)）")
        XCTAssertGreaterThanOrEqual(bottomSubmit.frame.height, 44, "「投稿する」の的が 44pt 未満")
        XCTAssertTrue(bottomSubmit.label.contains("投稿する"), "「投稿する」の字が違う（\(bottomSubmit.label)）")

        let title = "JP\(Int(Date().timeIntervalSince1970) % 1_000_000)"
        let titleField = app.textFields["upload.title"].firstMatch
        reveal(titleField, in: app, "題の欄")
        enter(title, into: titleField, "題の欄")
        let place = app.textFields["upload.place"].firstMatch
        reveal(place, in: app, "撮影地の欄")
        enter("Kagawa", into: place, "撮影地の欄")

        let submit = app.buttons["upload.submit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "「投稿する」が無い")
        XCTAssertTrue(wait(submit, "enabled == true", timeout: 15), "題と撮影地を入れても「投稿する」が押せない")
        submit.tap()
        // 1.1.83（資料「SNS をもっと SNS に」①）: 全体に公開の投稿は、上がると共有カードの画面が出る（`PostedShareCard`）。
        // 「閉じる」で投稿画面ごと閉じる
        let close = app.buttons["postedCard.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 60), "投稿しても共有カードが出ない（上がっていない）")
        close.tap()
        // カードを閉じると投稿画面も閉じる（`didPostAll`）
        XCTAssertTrue(thumb.waitForNonExistence(timeout: 30), "カードを閉じても投稿画面が閉じない")

        // 本体が空なら見本の答え手が 400 で断り、投稿画面は閉じない（`PreviewBackend.PreviewTransfer`）——上で落ちる
        let posted = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'mypage.photo' AND label CONTAINS %@", title)).firstMatch
        if !posted.waitForExistence(timeout: 20) {
            // 2026-11-13（PR #589 で4番目に流れて落ちた・最初に流れた回はいつも通る）: 推定で直さず、並ばなかったときの
            // マイページの姿を値で残す——格子の数と先頭の題・位置、下の札、区分の札、名前の行、投稿の画面が残っていないか
            let cells = app.descendants(matching: .any).matching(identifier: "mypage.photo")
            let first = cells.allElementsBoundByIndex.prefix(10).map { "\($0.label)@\(Int($0.frame.minY))" }
            let tabs = app.tabBars.firstMatch.buttons.allElementsBoundByIndex.map { "\($0.label)=\($0.isSelected)" }
            let posts = app.buttons["profile.tab.posts"].firstMatch
            let name = app.descendants(matching: .any)["mypage.nameLine"].firstMatch
            let line = "[postProbe] title=\(title) cells=\(cells.count) first=\(first) tabs=\(tabs)"
                + " postsTab=\(posts.exists ? "\(posts.isSelected)@\(Int(posts.frame.minY))" : "none")"
                + " nameLine=\(name.exists ? "\(name.frame)" : "none")"
                + " postedCard=\(app.buttons["postedCard.close"].exists) uploadOpen=\(app.buttons["upload.submit"].exists)"
            print(line)
            let note = XCTAttachment(string: line)
            note.name = "postProbe"
            note.lifetime = .keepAlways
            add(note)
        }
        XCTAssertTrue(posted.exists, "投稿した「\(title)」がマイページに並ばない")
    }

    /// 2026-11-14（#188・点検「直すべき 1」）: 書きかけ（見本の1枚を選んだ）の投稿画面を下へ払うと、跳ね返るだけでなく
    /// 左上の「キャンセル」と同じ閉じる確認が出る。画面は閉じない（書きかけが消えない）
    func testSwipeDownOnUploadDraftAsksBeforeClosing() {
        let app = launch(["-JPPreviewUploadSample", "YES"])
        tab(app, 2)
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        XCTAssertTrue(toPhoto.waitForExistence(timeout: 10), "投稿の2択が出ない")
        toPhoto.tap()
        let thumb = app.buttons["upload.thumb.0"].firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 20), "見本の1枚が投稿画面に入らない")
        Thread.sleep(forTimeInterval: 1)

        // 上のバー（題「新規投稿」の辺り）から下へ大きく払う
        var log: [String] = []
        defer { attachSwipeLog(log, "uploadDraft") }
        swipeSheetDown(app, log: &log, "書きかけの投稿")
        let bar = app.navigationBars.firstMatch

        let stop = app.buttons["投稿をやめる"].firstMatch
        let asked = stop.waitForExistence(timeout: 5)
        if !asked {
            // 推定で直さないための記録: 払ったあとの姿（画面が残ったか・どの確かめが出たか・バーの位置）
            let line = "[swipeProbe] uploadOpen=\(thumb.exists) sheets=\(app.sheets.count) alerts=\(app.alerts.count)"
                + " buttons=\(app.sheets.firstMatch.buttons.allElementsBoundByIndex.map(\.label))"
                + " bar=\(bar.exists ? "\(bar.frame)" : "none")"
            print(line)
            let note = XCTAttachment(string: line)
            note.name = "swipeProbe"
            note.lifetime = .keepAlways
            add(note)
        }
        XCTAssertTrue(asked, "書きかけの投稿画面を下へ払っても閉じる確認が出ない")
        XCTAssertTrue(app.buttons["下書きに保存"].firstMatch.exists, "閉じる確認が「キャンセル」と違う（下書きに保存が無い）")
        XCTAssertTrue(thumb.exists, "払っただけで書きかけの投稿画面が閉じた")
        // 「書き続ける」で確かめを閉じると、書きかけのまま画面に戻る
        let keep = app.buttons["書き続ける"].firstMatch
        if keep.exists {
            keep.tap()
            XCTAssertTrue(stop.waitForNonExistence(timeout: 5), "「書き続ける」で確かめが閉じない")
            XCTAssertTrue(thumb.exists, "「書き続ける」なのに書きかけが消えた")
        }
    }

    // MARK: - 1c. 書きかけの無いシートは、払えば閉じて開き直せる（#599 の見直し）
    //
    // 払うのを受ける中継ぎ（`SheetSwipeRelay`）は、SwiftUI がもともと持つ受け手へ知らせを回す（`forwardingTarget`）。
    // 回らないと、払って閉じても `isPresented` が戻らず onDismiss も走らず、**同じ所から開き直せない**。
    // 3種のシート（投稿・意見・名前の横）で「払って閉じる → 開き直せる」を見る。各段の値は `swipeLog` に残す

    /// 投稿画面: 見本の1枚を外して書きかけを無くし、払うと閉じる。もう一度「投稿」から開ける
    func testSwipeClosesEmptyUploadAndReopens() {
        let app = launch(["-JPPreviewUploadSample", "YES"])
        var log: [String] = []
        defer { attachSwipeLog(log, "upload") }
        tab(app, 2)
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        XCTAssertTrue(toPhoto.waitForExistence(timeout: 10), "投稿の2択が出ない")
        toPhoto.tap()
        let thumb = app.buttons["upload.thumb.0"].firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 20), "見本の1枚が投稿画面に入らない")
        let remove = app.buttons["1枚目を外す"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "1枚目を外す丸が無い")
        remove.tap()
        XCTAssertTrue(thumb.waitForNonExistence(timeout: 10), "外しても1枚目が残る")
        let submit = app.buttons["upload.submit"].firstMatch
        log.append("外した後: thumb=\(thumb.exists) submit=\(submit.exists ? "\(submit.isEnabled)" : "none")"
                   + " reason=\(app.staticTexts["upload.submitReason"].firstMatch.exists)")

        swipeSheetDown(app, log: &log, "投稿")
        let stop = app.buttons["投稿をやめる"].firstMatch
        log.append("払った後: dialog=\(stop.exists) submit=\(submit.exists) bar=\(app.navigationBars.firstMatch.exists)")
        XCTAssertFalse(stop.exists, "書きかけが無いのに閉じる確認が出た")
        XCTAssertTrue(submit.waitForNonExistence(timeout: 10), "書きかけの無い投稿画面を払っても閉じない")

        // 開き直す（`isPresented` が戻っていないと、押しても開かない）
        tab(app, 2)
        let again = app.buttons["post.choice.photo"].firstMatch
        let choiceShown = again.waitForExistence(timeout: 10)
        log.append("開き直し: choice=\(choiceShown)")
        XCTAssertTrue(choiceShown, "払って閉じたあと、投稿の2択が出ない")
        again.tap()
        let reopened = app.buttons["upload.thumb.0"].firstMatch.waitForExistence(timeout: 20)
            || submit.waitForExistence(timeout: 5)
        log.append("開き直し: upload=\(reopened)")
        XCTAssertTrue(reopened, "払って閉じた投稿画面を、同じ所から開き直せない")
    }

    /// 意見を送るシート（送っている最中だけ止めるシート）: 払うと閉じ、設定の行から開き直せる
    func testSwipeClosesFeedbackAndReopens() {
        let app = launch()
        var log: [String] = []
        defer { attachSwipeLog(log, "feedback") }
        tab(app, 4)
        XCTAssertTrue(app.buttons["mypage.edit"].firstMatch.waitForExistence(timeout: 20), "マイページが出ない")
        let gear = app.buttons["設定"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "設定の印が無い")
        gear.tap()
        let row = app.buttons["settings.feedback"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "設定に「意見を送る」が無い")
        reveal(row, in: app, "意見を送るの行")
        row.tap()
        let send = app.buttons["feedback.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "意見のシートが開かない")
        Thread.sleep(forTimeInterval: 1)
        swipeSheetDown(app, log: &log, "意見")
        let closed = send.waitForNonExistence(timeout: 10)
        log.append("払った後: closed=\(closed) row=\(row.exists)")
        XCTAssertTrue(closed, "意見のシートを払っても閉じない")
        reveal(row, in: app, "意見を送るの行（開き直し）")
        row.tap()
        let reopened = send.waitForExistence(timeout: 10)
        log.append("開き直し: sheet=\(reopened)")
        XCTAssertTrue(reopened, "払って閉じた意見のシートを開き直せない")
    }

    /// 名前の横のシート（つまみのあるシート・保存中だけ止める）: 払うと閉じ、名前の行から開き直せる
    func testSwipeClosesNameSideAndReopens() {
        let app = launch()
        var log: [String] = []
        defer { attachSwipeLog(log, "nameSide") }
        tab(app, 4)
        let nameLine = app.descendants(matching: .any)["mypage.nameLine"].firstMatch
        XCTAssertTrue(nameLine.waitForExistence(timeout: 20), "マイページの名前の行が無い")
        nameLine.tap()
        let save = app.descendants(matching: .any)["nameSide.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "名前の横のシートが開かない")
        Thread.sleep(forTimeInterval: 1)
        swipeSheetDown(app, log: &log, "名前の横")
        let closed = save.waitForNonExistence(timeout: 10)
        log.append("払った後: closed=\(closed) nameLine=\(nameLine.exists)")
        XCTAssertTrue(closed, "名前の横のシートを払っても閉じない")
        nameLine.tap()
        let reopened = save.waitForExistence(timeout: 10)
        log.append("開き直し: sheet=\(reopened)")
        XCTAssertTrue(reopened, "払って閉じた名前の横のシートを開き直せない")
    }

    /// **値を取るだけ（合否なし・名指しした回だけ・`pick-ui-tests.py` の `ONLY_WHEN_NAMED`）**。
    /// 書きかけの投稿画面から親しい友達（同じシートに積む画面）を開き、何も変えずに払ったときに何が起きるか
    /// （跳ね返る・閉じる・どの確かめが出る）を記録する。`SheetSwipeRelay` の注記の「奥の書きかけ」を決める材料
    func testMeasuresUploadStackedSwipe() {
        let app = launch(["-JPPreviewUploadSample", "YES"])
        var log: [String] = []
        defer { attachSwipeLog(log, "stacked") }
        tab(app, 2)
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        guard toPhoto.waitForExistence(timeout: 10) else { log.append("投稿の2択が出ない"); return }
        toPhoto.tap()
        let thumb = app.buttons["upload.thumb.0"].firstMatch
        guard thumb.waitForExistence(timeout: 20) else { log.append("見本の1枚が入らない"); return }
        let details = app.buttons["upload.details"].firstMatch
        for _ in 0..<4 where !(details.exists && details.isHittable) { app.swipeUp(); Thread.sleep(forTimeInterval: 1) }
        guard details.exists, details.isHittable else { log.append("詳しい設定が無い"); return }
        details.tap()
        let audience = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "公開範囲")).firstMatch
        for _ in 0..<4 where !(audience.exists && audience.isHittable) { app.swipeUp(); Thread.sleep(forTimeInterval: 1) }
        guard audience.exists, audience.isHittable else { log.append("公開範囲の行が無い"); return }
        audience.tap()
        let close = app.buttons["親しい友達"].firstMatch
        guard close.waitForExistence(timeout: 5) else { log.append("公開範囲のメニューに親しい友達が無い"); return }
        close.tap()
        let pick = app.buttons["親しい友達を選ぶ"].firstMatch
        for _ in 0..<4 where !(pick.exists && pick.isHittable) { app.swipeUp(); Thread.sleep(forTimeInterval: 1) }
        guard pick.exists, pick.isHittable else { log.append("親しい友達を選ぶの行が無い"); return }
        pick.tap()
        Thread.sleep(forTimeInterval: 2)
        log.append("積んだ後: bar=\(app.navigationBars.firstMatch.identifier) thumb=\(thumb.exists)")
        swipeSheetDown(app, log: &log, "積んだ親しい友達")
        Thread.sleep(forTimeInterval: 2)
        log.append("払った後: stop=\(app.buttons["投稿をやめる"].firstMatch.exists)"
                   + " back=\(app.buttons["保存せずに戻る"].firstMatch.exists)"
                   + " sheets=\(app.sheets.firstMatch.buttons.allElementsBoundByIndex.map(\.label))"
                   + " uploadOpen=\(app.buttons["upload.submit"].firstMatch.exists)"
                   + " bar=\(app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.identifier : "none")")
    }

    /// シートの上の端（シートの上のバー＝いちばん下にある上のバーの真ん中、無ければ画面の上 12%）から下へ大きく払う。
    /// シートの後ろの画面のバー（上に少し覗く）を掴まないよう、いちばん下のバーを選ぶ。払う前の姿を記録に足す
    private func swipeSheetDown(_ app: XCUIApplication, log: inout [String], _ what: String) {
        let bars = app.navigationBars.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        let bar = bars.max { $0.frame.minY < $1.frame.minY }
        let from = bar.map { $0.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)) }
            ?? app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        log.append("\(what) 払う前: bars=\(bars.map { "\($0.frame)" }) chose=\(bar.map { "\($0.frame)" } ?? "none")"
                   + " window=\(app.windows.firstMatch.frame)")
        from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// 払う試験の各段の値を、ログと添付に残す（推定で直さないため）
    private func attachSwipeLog(_ log: [String], _ name: String) {
        let text = log.map { "[swipeLog \(name)] \($0)" }.joined(separator: "\n")
        print(text)
        let note = XCTAttachment(string: text)
        note.name = "swipeLog-\(name)"
        note.lifetime = .keepAlways
        add(note)
    }

    // MARK: - 4. ログアウト → ログイン

    /// メニューからログアウトするとマイページがログイン画面になり、見本の認証でログインすると元のマイページに戻る
    func testSignOutThenSignInReturnsToMyPage() {
        let app = launch()
        tab(app, 4)
        let nameLine = app.descendants(matching: .any)["mypage.nameLine"].firstMatch
        XCTAssertTrue(nameLine.waitForExistence(timeout: 20), "ログイン中のマイページが出ない")

        tab(app, 0)
        let menu = app.buttons["header.menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "見出しにメニューが無い")
        menu.tap()
        let logout = app.buttons["menu.logout"].firstMatch
        XCTAssertTrue(logout.waitForExistence(timeout: 10), "メニューにログアウトが無い（ログイン中なのに）")
        var pushes = 0
        while !logout.isHittable, pushes < 5 {
            app.swipeUp()
            pushes += 1
        }
        logout.tap()
        XCTAssertTrue(logout.waitForNonExistence(timeout: 10), "ログアウトを押してもメニューが閉じない")

        tab(app, 4)
        let form = app.descendants(matching: .any)["signin.form"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 30), "ログアウトしてもマイページがログイン画面にならない")
        XCTAssertFalse(nameLine.exists, "ログアウトしたのにマイページの中身が残っている")

        let email = app.textFields["signin.email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 5), "メールアドレスの欄が無い")
        enter(Self.previewEmail, into: email, "メールアドレスの欄")
        let password = app.secureTextFields["signin.password"].firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 5), "パスワードの欄が無い")
        enter(Self.previewPassword, into: password, "パスワードの欄")
        let submit = app.buttons["signin.submit"].firstMatch
        XCTAssertTrue(wait(submit, "enabled == true", timeout: 5), "入れてもログインが押せない")
        submit.tap()

        XCTAssertTrue(nameLine.waitForExistence(timeout: 30), "ログインしてもマイページに戻らない")
        XCTAssertTrue(form.waitForNonExistence(timeout: 10), "ログインしたのにログイン画面が残っている")
    }

    // MARK: - 5. キャンピングカー

    /// 部屋に入る → 写真 → 額に入っていない1枚を選んで「この額に飾る」→ 部屋に戻ると、その写真が額に写っている
    func testCamperRoomHangPhotoShowsInFrame() {
        // 毎回最初の並び（保存しない）。見本の通信は要らないが、同じ起動で揃える
        let app = launch(["-JPPreviewCamperRoomReset", "YES"])
        tab(app, 4)
        let tripsTab = app.buttons["profile.tab.trips"].firstMatch
        XCTAssertTrue(tripsTab.waitForExistence(timeout: 20), "マイページに「旅の記録」のタブが無い")
        // 見出しの読み込みでタブの列が動く間は押さない（`ScreenshotTests.selectTripsTab` の注記）
        Thread.sleep(forTimeInterval: 3)
        reveal(tripsTab, in: app, "旅の記録のタブ", pushes: 4)
        tripsTab.tap()
        let camper = app.buttons["trips.camper"].firstMatch
        // 旅の記録のタブが「読み込み中」のまま 15 秒を越えることがある（run 728・2026-10-28 の Mac でここが落ちた）。
        // 長めに待ち、出なければタブを押し直してもう一度待つ（`TripsTabWait`・`ScreenshotTests.openTripsRow` と共通）
        XCTAssertTrue(TripsTabWait.waitForRow(camper, tripsTab: tripsTab), "「写真で作るキャンピングカー」の行が無い")
        reveal(camper, in: app, "キャンピングカーの行")
        camper.tap()
        let enter = app.buttons["camper.room.enter"].firstMatch
        XCTAssertTrue(enter.waitForExistence(timeout: 20), "キャンピングカーに「中に入る」が無い")
        reveal(enter, in: app, "中に入る")
        enter.tap()

        let scene = app.descendants(matching: .any)["camper.room.scene"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "部屋に入れない")
        XCTAssertTrue(wait(scene, "value CONTAINS 'camper-room-ready'", timeout: 60), "部屋を組み終えない")

        app.buttons["camper.room.tool.photos"].firstMatch.tap()
        XCTAssertFalse(app.buttons["camper.room.addFrame"].firstMatch.waitForExistence(timeout: 3),
                       "最初の並びの部屋に額が無い")
        let photos = app.buttons.matching(identifier: "camper.room.photo")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 30), "飾れる写真が出ない")
        // 額に保存した中身の印画が載るまで待つ（写真は本物の公開写真を読む）
        XCTAssertTrue(waitUntil(20) { !self.marker(scene, "framed").isEmpty }, "額に写真が載らない（今は \(scene.value ?? "")）")
        Thread.sleep(forTimeInterval: 3)
        let framedBefore = marker(scene, "framed")

        // 額に入っていない1枚
        let candidates = photos.allElementsBoundByIndex.prefix(12)
        guard let pick = candidates.first(where: {
            let id = $0.value as? String ?? ""
            return !id.isEmpty && !framedBefore.contains(id) && $0.isHittable
        }) else {
            return XCTFail("額に入っていない写真が無い（額 \(framedBefore.count)・写真 \(photos.count)）")
        }
        let photoId = pick.value as? String ?? ""
        pick.tap()
        XCTAssertTrue(wait(pick, "selected == true", timeout: 5), "写真を押しても選ばれない")
        // 選んだだけでは見本（preview）として載り、保存した中身（framed）にはまだ無い
        XCTAssertTrue(waitUntil(15) { self.marker(scene, "preview").contains(photoId) },
                      "選んだ写真 \(photoId) が見本として額に載らない（今は \(scene.value ?? "")）")
        XCTAssertFalse(marker(scene, "framed").contains(photoId), "「この額に飾る」を押す前に保存した中身に入っている")
        let hang = app.buttons["camper.room.hang"].firstMatch
        XCTAssertTrue(wait(hang, "enabled == true", timeout: 5), "「この額に飾る」が押せない")
        hang.tap()
        XCTAssertTrue(waitUntil(15) { self.marker(scene, "framed").contains(photoId) },
                      "飾った写真 \(photoId) が額の中身に入らない（今は \(scene.value ?? "")）")

        // 部屋に戻っても（見本ではなく保存した中身で描き直す）額に写っている
        app.buttons["camper.room.back"].firstMatch.tap()
        XCTAssertTrue(waitUntil(20) {
            self.marker(scene, "framed").contains(photoId) && self.marker(scene, "preview").isEmpty
        }, "部屋に戻ると飾った写真 \(photoId) が額に無い（今は \(scene.value ?? "")）")
    }

    /// 部屋の読み上げの値から、額の中身の id を読む（` framed=a,b preview=c`・`CamperRoomView.framedMarker`）。
    /// `framed` は保存した中身、`preview` は選んだだけの見本
    private func marker(_ scene: XCUIElement, _ name: String) -> [String] {
        let value = scene.value as? String ?? ""
        guard let start = value.range(of: " \(name)=") else { return [] }
        let rest = value[start.upperBound...]
        let end = rest.firstIndex(of: " ") ?? rest.endIndex
        return rest[..<end].split(separator: ",").map(String.init)
    }

    /// 条件が満たされるまで待つ（最長 `timeout` 秒）
    private func waitUntil(_ timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return condition()
    }
}
