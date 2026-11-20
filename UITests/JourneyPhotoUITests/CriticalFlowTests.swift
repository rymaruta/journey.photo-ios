import XCTest
import CoreLocation

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
        let app = XCUIApplication.jp()
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
        // 札 #435（2026-11-14）: 起動直後にマイページを押した回の selection の履歴を、通った回も残す（冷えた起動の比べる元）
        notePerfProbe(app, label: "mypageShown")
        tab(app, 2)
        // 2026-11-18（案 B1）: 下の「投稿」で写真の一覧が開き、見本の1枚（`-JPPreviewUploadSample`）はそのまま欄の段に入る
        // （前の選ぶシートの「写真を投稿」を押す手は無くなった）
        let thumb = app.buttons["upload.thumb.0"].firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 20), "見本の1枚が投稿画面に入らない")
        // 2026-11-14（#188）: 「投稿する」は下の帯の主ボタン（板の投稿画面）。キーボードが出る前に、画面の下の方に
        // 幅いっぱい・高さ 44 以上で在るかを見る（右上の字に戻ると落ちる）
        let bottomSubmit = app.buttons["upload.submit"].firstMatch
        XCTAssertTrue(bottomSubmit.waitForExistence(timeout: 5), "下の「投稿する」が無い")
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(bottomSubmit.frame.minY, screen.height * 0.8,
                             "「投稿する」が下に無い（frame \(bottomSubmit.frame)・画面 \(screen)）")
        // 2026-11-15（札 #409・案A）: 主ボタンの左に線の副ボタン「プレビュー」。帯の2つで幅いっぱい、主ボタンが広い方
        let preview = app.buttons["upload.preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "下の帯に「プレビュー」が無い")
        let barWidth = max(preview.frame.maxX, bottomSubmit.frame.maxX) - min(preview.frame.minX, bottomSubmit.frame.minX)
        XCTAssertGreaterThan(barWidth, screen.width * 0.8,
                             "下の帯が幅いっぱいでない（投稿 \(bottomSubmit.frame)・プレビュー \(preview.frame)）")
        XCTAssertGreaterThan(bottomSubmit.frame.width, preview.frame.width,
                             "「投稿する」が「プレビュー」より狭い（\(bottomSubmit.frame)・\(preview.frame)）")
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
        // 2026-11-18（案 B2・owner 採用）: 「投稿する」で画面がすぐ閉じ、裏の係（`PostUploadCenter`）が送る。
        // 上がったら知らせ「投稿しました　カードにする」（共有カードは画面いっぱいに出さない・1.1.83 の決めを置き換えた）
        // run 1465: 知らせの入れ物（`toast`）の label は空で、字は子の StaticText「投稿しました」（要素の木で確かめた）。
        // 字そのものを、押した直後から見る（知らせは6秒で消える）
        let postedText = app.staticTexts["投稿しました"].firstMatch
        let toastShown = postedText.waitForExistence(timeout: 60)
        print("[postedToast] shown=\(toastShown) uploadOpen=\(thumb.exists) card=\(app.buttons["toast.action"].exists)")
        XCTAssertTrue(toastShown, "裏で送っても「投稿しました」が出ない（上がっていない）")
        XCTAssertTrue(thumb.waitForNonExistence(timeout: 15), "「投稿する」で投稿の画面が閉じない（送り終えるのを待っている）")
        XCTAssertFalse(app.buttons["postedCard.close"].exists, "共有カードを画面いっぱいに出した")

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
        // 2026-11-18（案 B1）: 下の「投稿」は画面いっぱいの覆い（払って閉じない）になったので、払って閉じるシートの投稿画面は
        // 今週のお題の「参加する」から開く（`RootView.uploadSheet`・シートのまま）。見本の1枚がそのまま入る
        tab(app, 0)
        let join = app.buttons["参加する"].firstMatch
        XCTAssertTrue(join.waitForExistence(timeout: 20), "ホームに今週のお題の「参加する」が無い")
        join.tap()
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

    /// 投稿画面: 見本の1枚を外して書きかけを無くすと写真の一覧に戻り、閉じる。もう一度「投稿」から開ける
    func testClosingEmptyUploadReturnsAndReopens() {
        let app = launch(["-JPPreviewUploadSample", "YES"])
        var log: [String] = []
        defer { attachSwipeLog(log, "upload") }
        tab(app, 2)
        // 2026-11-18（案 B1）: 下の「投稿」で写真の一覧が開き、見本の1枚（`-JPPreviewUploadSample`）はそのまま欄の段に入る
        // （前の選ぶシートの「写真を投稿」を押す手は無くなった）
        let thumb = app.buttons["upload.thumb.0"].firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 20), "見本の1枚が投稿画面に入らない")
        let remove = app.buttons["1枚目を外す"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "1枚目を外す丸が無い")
        remove.tap()
        XCTAssertTrue(thumb.waitForNonExistence(timeout: 10), "外しても1枚目が残る")
        let submit = app.buttons["upload.submit"].firstMatch
        log.append("外した後: thumb=\(thumb.exists) submit=\(submit.exists ? "\(submit.isEnabled)" : "none")"
                   + " reason=\(app.staticTexts["upload.submitReason"].firstMatch.exists)")

        // 2026-11-18（案 B1）: 投稿の入口は画面いっぱいの覆い（払って閉じるシートではない）。写真を全部外すと
        // **写真の一覧の段に戻り**、左上のガラスの丸の「閉じる」で確認なしに閉じる（書きかけが無い）
        let close = app.buttons["post.library.close"].firstMatch
        let backToLibrary = close.waitForExistence(timeout: 10)
        log.append("外した後: library=\(backToLibrary) switcher=\(app.buttons["post.choice.story"].firstMatch.exists)")
        XCTAssertTrue(backToLibrary, "写真を全部外しても一覧の段に戻らない")
        close.tap()
        let stop = app.buttons["投稿をやめる"].firstMatch
        log.append("閉じた後: dialog=\(stop.exists) close=\(close.exists)")
        XCTAssertFalse(stop.exists, "書きかけが無いのに閉じる確認が出た")
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), "書きかけの無い投稿の入口を閉じられない")

        // 開き直す（`isPresented` が戻っていないと、押しても開かない）。見本の1枚がまた入る
        tab(app, 2)
        let reopened = app.buttons["upload.thumb.0"].firstMatch.waitForExistence(timeout: 20)
            || submit.waitForExistence(timeout: 5)
        log.append("開き直し: upload=\(reopened)")
        XCTAssertTrue(reopened, "閉じた投稿の入口を、同じ所から開き直せない")
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
        // 2026-11-18（案 B1）: 払って閉じるシートの投稿画面は、今週のお題の「参加する」から開く（下の「投稿」は覆い）
        tab(app, 0)
        let join = app.buttons["参加する"].firstMatch
        guard join.waitForExistence(timeout: 20) else { log.append("参加するが無い"); return }
        join.tap()
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

    // MARK: - 1b. 投稿 → ストーリーに載せる → 見る（札 #596・2026-11-13）

    /// **owner の報告（1.1.85〜1.1.87）: 写真を投稿してストーリーに載せ、そのストーリーを開いた瞬間に落ちる。
    /// ホームの輪からでもマイページの顔からでも落ちる。** その道を見本の通信（`-JPPreviewLocalBackend`・
    /// `-JPPreviewStories`）でそのまま通す。ストーリーの本体と行は端末の中の答え手が受けて覚える
    /// （`PreviewBackend` の `POST /stories`）——**サーバーには何も書かない**。
    ///
    /// 2026-11-14 owner の追加の事実: 「投稿 → ストーリーで共有、を**2回くらい**。その後どの画面からでもストーリーを押すと落ちる」
    /// 「載せた写真は iPhone のカメラで撮ったそのままの写真（HEIC）」。だから 2 本載せる形（同じ投稿から2回・別の投稿を1回ずつ）と、
    /// 実寸の HEIC（向きの情報つき・`-JPPreviewUploadSampleKind`）の種を足した。
    ///
    /// 落ちたかは `app.state` で見る（落ちると `.notRunning`）。各段で `[storyCrash]` の行を出し、画面の木は添付に残す。
    /// 閲覧画面の中身（id の並び・位置・メモリ）は見えない要素 `story.viewer.probe`、ホームの輪が読んだ並びは
    /// `stories.probe` に出る（`-JPPreviewFeedProbe`・Debug のみ）。
    /// 落ちたときの積みは、XCTest の失敗の文と `Tools/sim-crash-summary.py`（`[simCrash]` の行）に出る
    func testPostedPhotoStoryOpensFromHomeRing() {
        let app = launchForStory()
        postAndShare(app, shares: 1, tag: "a")
        openFromHomeRing(app)
    }

    /// 同じ道を**マイページの顔の輪**から開く（`MyPageView.avatar` → `StoryAvatar` → `StoryReelView`）
    func testPostedPhotoStoryOpensFromMyPage() {
        let app = launchForStory()
        postAndShare(app, shares: 1, tag: "a")
        openFromMyPage(app)
    }

    /// **同じ投稿から2回**ストーリーに載せる（共有カードの「ストーリーに載せる」を2回）→ ホームの輪 → マイページ。
    /// 写真は 48MP の HEIC（8064×6048・向き 6）。owner の「2回くらい」の形
    func testPostedPhotoSharedTwiceFromSameCardOpens() {
        let app = launchForStory(kind: "heic48")
        postAndShare(app, shares: 2, tag: "a")
        openFromHomeRing(app)
        openFromMyPage(app)
        assertNoStoryProblems()
    }

    /// **別の投稿を1回ずつ**ストーリーに載せる（2本）→ ホームの輪 → マイページ。写真は 12MP の HEIC（4032×3024・向き 6）
    func testTwoPostsSharedToStoryOpen() {
        let app = launchForStory(kind: "heic12")
        postAndShare(app, shares: 1, tag: "a")
        postAndShare(app, shares: 1, tag: "b")
        openFromHomeRing(app)
        openFromMyPage(app)
        assertNoStoryProblems()
    }

    /// 開く途中の不備（輪がもう一度押せない・「写真を見る」が出ない）は**その場で止めず**、最後にまとめて落とす。
    /// `continueAfterFailure = false` の組なので、途中で落とすとマイページから開く記録が残らなかった（run 1272）。
    /// アプリが落ちた（前に居ない）ときだけはその場で落とす
    private var storyProblems: [String] = []

    private func storyProblem(_ text: String) {
        print("[storyCrash] problem: \(text)")
        storyProblems.append(text)
    }

    private func assertNoStoryProblems() {
        XCTAssertTrue(storyProblems.isEmpty, storyProblems.joined(separator: " / "))
    }

    /// 大きい写真の種類ごとに1本ずつ載せて開く（メモリを `[storyCrash] … mem=` で残す）。
    /// パノラマ（16000×3000）・縦長の HEIC（3024×4032 向き 1）・大きい PNG（6000×4000）
    func testLargePhotoPanoramaSharedToStoryOpens() { largeKind("pano") }
    func testLargePhotoPortraitSharedToStoryOpens() { largeKind("portrait") }
    func testLargePhotoPNGSharedToStoryOpens() { largeKind("png") }

    private func largeKind(_ kind: String) {
        let app = launchForStory(kind: kind)
        postAndShare(app, shares: 1, tag: kind)
        openFromHomeRing(app)
    }

    private func launchForStory(kind: String? = nil) -> XCUIApplication {
        // 投稿 → 載せる → 見る、を2回まで通すので、1つの試験の持ち時間（既定 5 分・run 1272 で打ち切られた）を延ばす
        executionTimeAllowance = 900
        var extra = ["-JPPreviewUploadSample", "YES", "-JPPreviewStories", "YES", "-JPPreviewFeedProbe", "YES"]
        if let kind { extra += ["-JPPreviewUploadSampleKind", kind] }
        let app = launch(extra)
        storyCrashStep(app, "launched kind=\(kind ?? "asset")")
        return app
    }

    /// 見本の1枚を投稿 → 共有カードの「ストーリーに載せる」→ 作る画面の「シェアする」を `shares` 回 → カードを閉じる、まで。
    /// どの段も**出なければ落とす**（この組の決まり）
    private func postAndShare(_ app: XCUIApplication, shares: Int, tag: String) {
        tab(app, 2)
        // 2026-11-18（案 B1）: 下の「投稿」で写真の一覧が開き、見本の1枚（`-JPPreviewUploadSample`）はそのまま欄の段に入る
        // （前の選ぶシートの「写真を投稿」を押す手は無くなった）
        let thumb = app.buttons["upload.thumb.0"].firstMatch
        // 実寸の HEIC は作って整えるのに数秒かかる
        XCTAssertTrue(thumb.waitForExistence(timeout: 60), "見本の1枚が投稿画面に入らない")
        storyCrashStep(app, "\(tag).upload.thumb")
        let titleField = app.textFields["upload.title"].firstMatch
        reveal(titleField, in: app, "題の欄")
        enter("SC\(tag)\(Int(Date().timeIntervalSince1970) % 1_000_000)", into: titleField, "題の欄")
        let place = app.textFields["upload.place"].firstMatch
        reveal(place, in: app, "撮影地の欄")
        enter("Kagawa", into: place, "撮影地の欄")
        let submit = app.buttons["upload.submit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "「投稿する」が無い")
        XCTAssertTrue(wait(submit, "enabled == true", timeout: 30), "題と撮影地を入れても「投稿する」が押せない")
        submit.tap()
        // 2026-11-18（案 B2）: 画面はすぐ閉じ、上がったら知らせの「カードにする」から共有カードを開く。
        // 知らせは6秒で消えるので、押した直後から待つ。run 1472: 押した直後の記録（`storyCrashStep`・要素の木を全部書く）に
        // 7秒かかり（押した t=59.55s、記録の終わり t=66.56s）、その間に見本の送信が終わって（10:55:57 の記録で uploading=false）
        // 知らせが消えていた。run 1477: 見つけてから記録して押すと、記録の7秒（11:38:07 → 11:38:15）で消えていた。
        // **見つけたらすぐ押し、記録はそのあと**。run 1511: 在るのを見た（t=47.59s）あと、押す前に投稿の画面が開いているかを
        // 見ていて（t=51.19s）、押した t=52.72s には知らせが消えていた。投稿の画面を見るのも押したあとにする
        let makeCard = app.buttons["toast.action"].firstMatch
        let card = makeCard.waitForExistence(timeout: 90)
        if card { makeCard.tap() }
        let uploadOpen = thumb.exists
        storyCrashStep(app, "\(tag).upload.submitted toast card=\(card) uploadOpen=\(uploadOpen)")
        XCTAssertTrue(card, "裏で送っても「カードにする」の知らせが出ない")
        XCTAssertFalse(uploadOpen, "「投稿する」で投稿の画面が閉じない")

        let toStory = app.buttons["postedCard.story"].firstMatch
        XCTAssertTrue(toStory.waitForExistence(timeout: 90), "投稿しても共有カード（ストーリーに載せる）が出ない")
        storyCrashStep(app, "\(tag).postedCard.shown")
        for round in 1...shares {
            XCTAssertTrue(toStory.waitForExistence(timeout: 15) && wait(toStory, "hittable == true", timeout: 10),
                          "\(round)回目: カードの「ストーリーに載せる」が押せない")
            toStory.tap()
            // 作る画面（`StoryComposerView(sharing:)`）。札の絵が入ると「シェアする」が押せる
            let share = app.buttons.matching(NSPredicate(format: "label == %@", "シェアする")).firstMatch
            XCTAssertTrue(share.waitForExistence(timeout: 30), "\(round)回目: 「ストーリーに載せる」で作る画面が開かない")
            XCTAssertTrue(wait(share, "enabled == true", timeout: 30),
                          "\(round)回目: 作る画面の「シェアする」が押せるようにならない（札の絵が入らない）")
            storyCrashStep(app, "\(tag).composer\(round).ready")
            share.tap()
            // 押すと作る画面が閉じ、カードの画面に戻る（送るのは裏の係）
            XCTAssertTrue(share.waitForNonExistence(timeout: 30), "\(round)回目: 「シェアする」を押しても作る画面が閉じない")
            storyCrashStep(app, "\(tag).composer\(round).shared")
        }
        let close = app.buttons["postedCard.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 15), "作る画面を閉じたあとにカードの「閉じる」が無い")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 30), "カードの「閉じる」で閉じない")
        storyCrashStep(app, "\(tag).postedCard.closed")
        // 裏の送信（`StoryUploadCenter`）が済むまで待つ（輪が「送信中」から「あなたのストーリー」に替わる・`StoriesRow`）
        tab(app, 0)
        let uploading = app.descendants(matching: .any)["stories.uploading"].firstMatch
        if uploading.exists { _ = uploading.waitForNonExistence(timeout: 90) }
        _ = app.buttons.matching(NSPredicate(format: "label == %@", "あなたのストーリー")).firstMatch
            .waitForExistence(timeout: 30)
        storyCrashStep(app, "\(tag).afterUpload uploadingLeft=\(uploading.exists)")
    }

    private func openFromHomeRing(_ app: XCUIApplication, reopen: Bool = true) {
        tab(app, 0)
        let ring = app.buttons.matching(NSPredicate(format: "label == %@", "あなたのストーリー")).firstMatch
        let ringShown = ring.waitForExistence(timeout: 30)
        storyCrashStep(app, "home.ring ringShown=\(ringShown)")
        guard ringShown else { return storyProblem("ストーリーを出したのに、ホームに自分の輪（あなたのストーリー）が出ない") }
        ring.tap()
        watchStoryViewer(app, entry: "home", rounds: reopen ? 2 : 1) {
            app.buttons.matching(NSPredicate(format: "label == %@", "あなたのストーリー")).firstMatch
        }
    }

    private func openFromMyPage(_ app: XCUIApplication) {
        tab(app, 4)
        XCTAssertTrue(app.descendants(matching: .any)["mypage.nameLine"].firstMatch.waitForExistence(timeout: 20),
                      "ログイン中のマイページが出ない")
        let ring = app.buttons["story.avatar.ring"].firstMatch
        let ringShown = ring.waitForExistence(timeout: 30)
        storyCrashStep(app, "mypage.ring ringShown=\(ringShown)")
        guard ringShown else { return storyProblem("ストーリーを出したのに、マイページの顔に輪が出ない") }
        ring.tap()
        watchStoryViewer(app, entry: "mypage", rounds: 2) { app.buttons["story.avatar.ring"].firstMatch }
    }

    /// 開いたストーリーを、開いた瞬間・見終わるまで・**もう一度開いた瞬間**（2回目は「見た」の輪）と区切って見張る。
    /// 落ちていたら（`app.state != .runningForeground`）その段の名前で落とす。
    ///
    /// 2026-11-14（Mac run 1236）: 前の版は開いて5秒たってから「写真を見る」を探していた。出した1本は5秒で終わり、
    /// 束が1本だけなので閲覧画面が閉じていた。**開いている間に**探す。
    /// 閲覧画面の中身は 0.5 秒ごとに `story.viewer.probe`（id の並び・位置・メモリ）を読み、変わったら `[storyCrash]` の行に出す
    private func watchStoryViewer(_ app: XCUIApplication, entry: String, rounds: Int, ring: () -> XCUIElement) {
        let viewPhoto = app.buttons["story.viewer.sharedPhoto"].firstMatch
        let probe = app.descendants(matching: .any)["story.viewer.probe"].firstMatch
        // 閲覧画面が閉じる瞬間に `value` を読むと試験が落ちる（run 1272 のマイページ「No matches found」）。
        // `snapshot()` は見つからなければ投げるだけなので、無ければ "-" にする
        func probeValue() -> String { ((try? probe.snapshot())?.value as? String) ?? "-" }
        for round in 1...rounds {
            let label = "\(entry).open\(round)"
            print("[storyCrash] \(label).tapped state=\(app.state.rawValue)")
            // 紹介の札のストーリーには「写真を見る」が付く（`StoryViewerView.sharedPhotoButton`）。開いた瞬間に描く所
            let seen = viewPhoto.waitForExistence(timeout: 3)
            print("[storyCrash] \(label).first sharedPhotoButton=\(seen) state=\(app.state.rawValue) probe=\(probeValue())")
            if app.state != .runningForeground {
                storyCrashStep(app, "\(label).crashed")
                return XCTFail("[storyCrash] \(entry) から\(round)回目に開いた直後にアプリが前に居ない（state=\(app.state.rawValue)・落ちた可能性）")
            }
            if !seen { storyProblem("\(entry) から\(round)回目に開いても、出したばかりの紹介のストーリー（「写真を見る」）が出ない") }
            // 見終わるまで（出した1本は5秒ずつ・束の終わりで次の人へ送るか閉じる）0.5 秒刻みで見る
            var lastProbe = ""
            for tick in 1...28 {
                Thread.sleep(forTimeInterval: 0.5)
                if app.state != .runningForeground {
                    storyCrashStep(app, "\(label).crashed+\(Double(tick) * 0.5)s lastProbe=\(lastProbe)")
                    return XCTFail("[storyCrash] \(entry) から\(round)回目に開いて \(Double(tick) * 0.5) 秒でアプリが前に居ない（state=\(app.state.rawValue)・最後の中身 \(lastProbe)）")
                }
                let value = probeValue()
                if value != lastProbe {
                    print("[storyCrash] \(label).t=\(Double(tick) * 0.5)s probe=\(value)")
                    lastProbe = value
                }
                // 閉じた、または自分の束を見終わって人の束へ進んだら、それ以上は見ない
                if value == "-" && tick > 2 { break }
                if value != "-", !value.contains("user=\(Self.previewUserId)") { break }
            }
            storyCrashStep(app, "\(label).played")
            // 閲覧画面が閉じるまで（人の束へ続いたら下へ払って閉じる）。run 1272: 人の束には「…」（`story.viewer.more`）が
            // 無く、閉じずに輪が押せなかった。閲覧画面の印（`story.viewer.probe`）で見る
            for _ in 1...3 where probeValue() != "-" {
                app.swipeDown(velocity: .fast)
                Thread.sleep(forTimeInterval: 1.5)
            }
            print("[storyCrash] \(label).closed probe=\(probeValue()) state=\(app.state.rawValue)")
            if app.state != .runningForeground {
                storyCrashStep(app, "\(label).crashedAfterClose")
                return XCTFail("[storyCrash] \(entry) で見終わるまでにアプリが前に居ない（state=\(app.state.rawValue)）")
            }
            guard round < rounds else { break }
            // もう一度（今度は「見た」の輪から）。前の要素を使い回さず、探し直す
            let again = ring()
            let ready = again.waitForExistence(timeout: 15) && wait(again, "hittable == true", timeout: 10)
            storyCrashStep(app, "\(entry).beforeReopen ready=\(ready)")
            guard ready else {
                // 押せない理由を値で残す（何が上に居るか）
                print("[storyCrash] \(entry).reopenBlocked tree:\n\(app.debugDescription.prefix(6000))")
                return storyProblem("\(entry) の輪にもう一度押せない")
            }
            again.tap()
        }
    }

    /// `[storyCrash] <段> state=<数>` の行をログ（xcodebuild のログ）に、その時の画面の木を添付に残す。
    /// state: 1 = 動いていない（落ちた）・4 = 前に居る（`XCUIApplication.State`）。
    /// ホームの輪が読んだ並び（`stories.probe`）が見えていれば行に添える
    private func storyCrashStep(_ app: XCUIApplication, _ step: String) {
        let state = app.state
        var line = "[storyCrash] \(step) state=\(state.rawValue) t=\(ISO8601DateFormatter().string(from: Date()))"
        if state == .runningForeground {
            let rows = app.descendants(matching: .any)["stories.probe"].firstMatch
            if rows.exists { line += " rows=\(rows.value as? String ?? "?")" }
        }
        print(line)
        guard state == .runningForeground else { return }
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "storyCrash-\(step)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 4. ログアウト → ログイン

    /// メニューからログアウトし、マイページがログイン画面になるまで。マイページの名前の行とログインの欄の入れ物を返す
    private func signOutToForm(_ app: XCUIApplication) -> (nameLine: XCUIElement, form: XCUIElement) {
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
        return (nameLine, form)
    }

    /// メニューからログアウトするとマイページがログイン画面になり、見本の認証でログインすると元のマイページに戻る
    func testSignOutThenSignInReturnsToMyPage() {
        let app = launch()
        let (nameLine, form) = signOutToForm(app)

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

    /// **キーボードの右下のキーだけでログインできる**（2026-11-14 判断・`AuthFieldFlow`）:
    /// メールを打って右下のキー → パスワードの欄に焦点が移る → 打って右下のキー → ログインしてマイページに戻る。
    /// 前は右下のキーを押してもキーボードが閉じるだけで、パスワードの欄へ指で移り「ログイン」を押していた
    func testSignInMovesWithReturnKey() {
        let app = launch()
        let (nameLine, form) = signOutToForm(app)

        let email = app.textFields["signin.email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 5), "メールアドレスの欄が無い")
        enter(Self.previewEmail + "\n", into: email, "メールアドレスの欄")
        let password = app.secureTextFields["signin.password"].firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 5), "パスワードの欄が無い")
        // 右下のキーで焦点がパスワードの欄へ移ったか（読めない環境では、続けて打てるかで見る）
        if password.responds(to: NSSelectorFromString("hasKeyboardFocus")) {
            XCTAssertTrue(wait(password, "hasKeyboardFocus == true", timeout: 5),
                          "メールの欄で右下のキーを押しても、パスワードの欄に焦点が移らない")
        }
        XCTAssertTrue(app.keyboards.firstMatch.exists, "メールの欄で右下のキーを押したらキーボードが閉じた（次の欄へ進まない）")
        // 押さずに続けて打つ（焦点が移っていなければ typeText が落ちる）
        app.typeText(Self.previewPassword + "\n")

        XCTAssertTrue(nameLine.waitForExistence(timeout: 30), "パスワードの欄で右下のキーを押してもログインしない")
        XCTAssertTrue(form.waitForNonExistence(timeout: 10), "ログインしたのにログイン画面が残っている")
    }

    // MARK: - 4b. 探す: 最近の検索

    /// **前に探した言葉が欄の下に残り、押すとその言葉で探せる。1つずつ消せる**（2026-11-14 判断・`RecentSearchesStore`）
    func testSearchRemembersRecentWords() {
        let app = launch()
        tab(app, 1)
        let field = app.textFields["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "探すの欄が無い")
        // 前の回の言葉と重ならない言葉（同じ模擬機で流し直しても先頭に上がるだけ）
        let word = "Recent\(Int(Date().timeIntervalSince1970) % 100000)"
        enter(word + "\n", into: field, "探すの欄")
        let clear = app.buttons["search.clear"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "打っても欄の「消す」が出ない")
        clear.tap()

        let recent = app.buttons["\(word)で探す"].firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "探した言葉が、欄を空にしても最近の検索に出ない")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "最近の検索"
        shot.lifetime = .keepAlways
        add(shot)
        recent.tap()
        XCTAssertTrue(wait(field, "value == %@", [word], timeout: 5), "最近の言葉を押しても、その言葉で探さない")

        clear.tap()
        let remove = app.buttons["「\(word)」を最近の検索から消す"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "最近の言葉に消す印が無い")
        remove.tap()
        XCTAssertTrue(recent.waitForNonExistence(timeout: 5), "消す印を押しても最近の言葉が残る")
    }

    // MARK: - 4b2. 探す: AI に頼む（札 #652）

    /// **頼みの形で送ると、結果の代わりに AI の答えが出る。** 答えの下に「AI の答えは間違うことがあります」と残りの回数、
    /// 下の欄で続けて聞ける。作りの質問は断りの1行だけ（回数を使わない）。
    /// 見本の口（`-JPAskFixture`・サーバーへは送らず、端末の AI も呼ばない）で流す
    func testSearchAskAnswersFollowsUpAndRefuses() {
        let app = launch(["-JPAskFixture", "YES"])
        tab(app, 1)
        let field = app.textFields["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "探すの欄が無い")
        // 欄の名前は「AI に聞く、または探す」（見本の字は入れ替わる）
        XCTAssertEqual(field.label, "AI に聞く、または探す", "欄の読み上げの名前が違う")
        // 2026-11-20 判断（札 #662）: 途中の字（「おすすめの」）では送れない。欄の下に「続けて打つと AI に聞けます」
        enter("おすすめの", into: field, "探すの欄")
        let send = app.buttons["search.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "頼みの形の字なのに、欄の右に送信のボタンが無い")
        XCTAssertFalse(send.isEnabled, "途中の字（おすすめの）で送信のボタンが押せる")
        XCTAssertTrue(app.staticTexts["search.keepTyping"].firstMatch.exists, "途中の字で「続けて打つと AI に聞けます」が無い")
        field.typeText("観光スポット教えて")
        let answer = app.descendants(matching: .any)["search.ask.answer"].firstMatch
        // 打っただけでは答えを出さない（送信のボタンを押すまで）
        XCTAssertFalse(answer.waitForExistence(timeout: 3), "送信のボタンを押す前に AI の答えが出た")
        XCTAssertEqual(send.label, "AI に送る", "送信のボタンの読み上げが違う")
        XCTAssertTrue(send.isEnabled, "頼みの形の字で送信のボタンが押せない")
        XCTAssertFalse(app.staticTexts["search.keepTyping"].firstMatch.exists, "送れる字でも「続けて打つと」が残る")
        send.tap()
        XCTAssertTrue(answer.waitForExistence(timeout: 30), "送信のボタンを押しても AI の答えが出ない")
        XCTAssertTrue(app.staticTexts["search.ask.disclaimer"].firstMatch.waitForExistence(timeout: 5),
                      "答えの下に「AI の答えは間違うことがあります」が無い")
        let usage = app.descendants(matching: .any)["search.ask.usage"].firstMatch
        XCTAssertTrue(usage.waitForExistence(timeout: 5), "残りの回数の1行が無い")
        XCTAssertTrue(usage.label.contains("今日はあと2回"), "残りの回数の文が違う: \(usage.label)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "AI に頼む（答え）"
        shot.lifetime = .keepAlways
        add(shot)

        // 続けて聞く: 作りの質問は断りの1行（AI を呼ばない）
        let follow = app.textFields["search.ask.followUp"].firstMatch
        XCTAssertTrue(follow.waitForExistence(timeout: 10), "続けて聞く欄が無い")
        reveal(follow, in: app, "続けて聞く欄")
        enter("このアプリの作りを教えて", into: follow, "続けて聞く欄")
        let followSend = app.buttons["search.ask.send"].firstMatch
        XCTAssertTrue(followSend.waitForExistence(timeout: 5), "続けて聞く欄に送信のボタンが無い")
        followSend.tap()
        let refusal = app.descendants(matching: .any)["search.ask.refusal"].firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 10), "作りの質問を断っていない")
        XCTAssertTrue(app.staticTexts["この質問にはお答えできません。旅や写真、アプリの使い方のことなら聞いてください。"].firstMatch.exists,
                      "断りの1行が違う")
        // 欄を消すと今の字の検索に戻る
        app.buttons["search.clear"].firstMatch.tap()
        XCTAssertTrue(answer.waitForNonExistence(timeout: 5), "欄を消しても答えが残る")
    }

    /// 今日の分を使い切ったら、答えの上に帯1本（確かめのダイアログは出さない）。答えは言葉の表で出し続ける
    func testSearchAskUsedUpShowsOneBand() {
        let app = launch(["-JPAskFixture", "YES", "-JPAskFixtureMode", "usedUpDay"])
        tab(app, 1)
        let field = app.textFields["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "探すの欄が無い")
        // 前の試験と同じ頼みだと、同じ日の控え（回数を使わない）から答えて帯が出ない（run 1608）。毎回ちがう頼みにする
        enter("金沢でおすすめの観光スポットを教えて \(Int(Date().timeIntervalSince1970) % 100000)", into: field, "探すの欄")
        // AI に頼むのは欄の右の送信のボタンだけ（キーボードの「検索」は言葉の検索・札 #662）
        let send = app.buttons["search.send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "欄の右に送信のボタンが無い")
        send.tap()
        // 答えの欄が出るのを待ってから帯を見る（帯は答えの上に一緒に出る）。落ちたら段と経過（`search.ask.stage`）を出す
        let answer = app.descendants(matching: .any)["search.ask.answer"].firstMatch
        let stage = app.descendants(matching: .any)["search.ask.stage"].firstMatch
        func stageText() -> String { stage.exists ? (stage.value as? String ?? "-") : "missing" }
        XCTAssertTrue(answer.waitForExistence(timeout: 30), "使い切ったときに答えが出ない（段: \(stageText())）")
        let band = app.buttons["search.ask.band"].firstMatch
        XCTAssertTrue(band.waitForExistence(timeout: 5), "使い切っても帯が出ない（段: \(stageText())）")
        print("measured [ask-stage] \(stageText())")
        XCTAssertTrue(band.label.contains("今日の AI は3回使いました"), "帯の文が違う: \(band.label)")
        XCTAssertEqual(app.alerts.count, 0, "確かめのダイアログを出した")
        XCTAssertTrue(app.descendants(matching: .any)["search.ask.answer"].firstMatch.exists, "使い切ったら答えが出ない")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "AI に頼む（今日の分を使い切った）"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - 4c. 見つける（使い勝手の見直し 2026-11-16 A1・A4・A7・A9・A10。A1 は 2026-11-18 に2回たたくいいねだけ）

    /// A1: 写真を2回たたくといいね（大きく見る画面は開かない）、1回押すと今までどおり大きく見る。
    /// （2026-11-18 owner の判断で、操作の段を写真のすぐ下へ移す案は取りやめ。並びは板どおり）
    func testDetailDoubleTapLikes() {
        let app = launch()
        openFirstFeedPhoto(app)
        let like = app.buttons["photo.like"].firstMatch
        let hero = app.buttons["detail.hero"].firstMatch
        // 調べ（2026-11-16 run 1419 で `buttons["detail.hero"]` が見つからなかった）: 同じ名前の要素の種類と枠を失敗の文に出す
        let anyHero = app.descendants(matching: .any).matching(identifier: "detail.hero")
        _ = anyHero.firstMatch.waitForExistence(timeout: 10)
        let heroProbe = anyHero.allElementsBoundByIndex.map { "type=\($0.elementType.rawValue) frame=\($0.frame) label=\($0.label)" }
        print("measured detailHero \(heroProbe)")
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "写真の詳細の写真が Button として無い（同じ名前の要素: \(heroProbe)）")
        // いいね済みなら一度外してから（2回たたくのは付けるだけ・外さない）。段は題・作者の下なので送って押し、写真まで戻す
        _ = wait(like, "value != ''", timeout: 10)
        if like.isSelected {
            reveal(like, in: app, "いいね")
            like.tap()
            XCTAssertTrue(wait(like, "selected == false"), "いいねを外せない")
            var backs = 0
            while !hero.isHittable, backs < 6 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
                Thread.sleep(forTimeInterval: 1)
                backs += 1
            }
            XCTAssertTrue(hero.isHittable, "写真まで戻せない")
        }
        hero.doubleTap()
        XCTAssertTrue(wait(like, "selected == true", timeout: 10), "写真を2回たたいても、いいねが付かない")
        XCTAssertFalse(app.buttons["viewer.close"].firstMatch.waitForExistence(timeout: 2),
                       "2回たたいたら大きく見る画面が開いた")
        // もう一度2回たたいても外れない
        hero.doubleTap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(like.isSelected, "2回たたき直したら、いいねが外れた")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "A1-写真の詳細（2回たたいていいね）"
        shot.lifetime = .keepAlways
        add(shot)
        // 1回押すと大きく見る
        hero.tap()
        XCTAssertTrue(app.buttons["viewer.close"].firstMatch.waitForExistence(timeout: 10), "1回押しても大きく見る画面が開かない")
    }

    /// A4: **ログインしていなくてもフォローが出る。** いいねを押すと登録の側でログインの画面が開き、
    /// ログインできたら押したいいねまで済む（押し直さない）
    func testSignedOutLikeFinishesAfterSignIn() {
        let app = launch()
        _ = signOutToForm(app)
        openFirstFeedPhoto(app)
        XCTAssertTrue(app.buttons["photo.follow"].firstMatch.waitForExistence(timeout: 10),
                      "ログインしていない人の写真の詳細にフォローが無い")
        let like = app.buttons["photo.like"].firstMatch
        XCTAssertFalse(like.isSelected, "ログインしていないのにいいね済み")
        like.tap()
        XCTAssertTrue(app.staticTexts["登録すると、いいねできます"].firstMatch.waitForExistence(timeout: 10),
                      "いいねを押しても登録の側のログインの画面が開かない")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "A4-いいねから登録の画面"
        shot.lifetime = .keepAlways
        add(shot)
        let back = app.buttons["ログインに戻る"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "登録の画面に「ログインに戻る」が無い")
        back.tap()
        let email = app.textFields["signin.email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 5), "メールアドレスの欄が無い")
        enter(Self.previewEmail, into: email, "メールアドレスの欄")
        let password = app.secureTextFields["signin.password"].firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 5), "パスワードの欄が無い")
        enter(Self.previewPassword, into: password, "パスワードの欄")
        let submit = app.buttons["signin.submit"].firstMatch
        XCTAssertTrue(wait(submit, "enabled == true", timeout: 5), "入れてもログインが押せない")
        submit.tap()
        XCTAssertTrue(app.staticTexts["登録すると、いいねできます"].firstMatch.waitForNonExistence(timeout: 30),
                      "ログインしてもログインの画面が閉じない")
        XCTAssertTrue(wait(like, "selected == true", timeout: 20), "ログインしても、押したいいねが済んでいない（押し直しが要る）")
    }

    /// A7・A9: マップの3つ目の札は「リスト」のまま（2026-11-18 owner）。「このエリアを検索」は地図を動かした後だけ。
    /// 観光スポットの札に「行きたい」があり、押すと入る。札の × は無く、地図を押すと閉じる
    func testMapSpotCardWishAndTapMapToClose() {
        if #available(iOS 16.4, *) {
            XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 33.17, longitude: 131.18))
        }
        let app = launch()
        // ログインしていない人で見る（行きたい場所は端末に残るだけ・見本の通信は保存の口を持たない）
        _ = signOutToForm(app)
        tab(app, 3)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 5) {
            let alert = springboard.alerts.firstMatch
            let allow = ["アプリの使用中は許可", "Allow While Using App", "1度だけ許可", "Allow Once"]
                .map { alert.buttons[$0] }.first { $0.exists }
            (allow ?? alert.buttons.element(boundBy: 0)).tap()
        }
        let listTab = app.buttons["map.mode.list"].firstMatch
        XCTAssertTrue(listTab.waitForExistence(timeout: 20), "マップの切り替えが無い")
        XCTAssertEqual(listTab.label, "リスト", "3つ目の札が「リスト」でない")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.buttons["map.searchArea"].firstMatch.exists, "地図を動かす前から「このエリアを検索」が出ている")

        let field = app.textFields["map.search"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "マップの探す欄が無い")
        enter("鍋ヶ滝\n", into: field, "マップの探す欄")
        let pin = app.buttons["鍋ヶ滝"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 20), "「鍋ヶ滝」と打っても観光スポットのピンが出ない")
        Thread.sleep(forTimeInterval: 2)
        pin.tap()
        let card = app.descendants(matching: .any).matching(identifier: "map.officialCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "ピンを押しても観光スポットの札が出ない")
        XCTAssertFalse(card.buttons["閉じる"].exists, "札に × が残っている")
        let wish = app.buttons["map.officialCard.wish"].firstMatch
        // 調べ（2026-11-16 run 1419 で見つからないか押せなかった）: 有無・押せるか・枠と札の枠・同じ名前の要素を失敗の文に出す
        let wishExists = wish.waitForExistence(timeout: 5)
        let anyWish = app.descendants(matching: .any).matching(identifier: "map.officialCard.wish").allElementsBoundByIndex
            .map { "type=\($0.elementType.rawValue) frame=\($0.frame)" }
        let wishProbe = "exists=\(wishExists) hittable=\(wishExists && wish.isHittable) frame=\(wish.frame) card=\(card.frame) "
            + "window=\(app.windows.firstMatch.frame) any=\(anyWish) cardButtons=\(card.buttons.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)|\($0.frame)" })"
        print("measured mapCardWish \(wishProbe)")
        XCTAssertTrue(wishExists && wish.isHittable, "札に「行きたい」が無いか押せない（\(wishProbe)）")
        XCTAssertTrue(app.buttons["map.officialCard.directions"].firstMatch.exists, "札に「経路」が無い")
        XCTAssertTrue(app.buttons["map.officialCard.open"].firstMatch.exists, "札に「スポットを見る」が無い")
        print("measured mapCard wish=\(wish.frame) directions=\(app.buttons["map.officialCard.directions"].firstMatch.frame) open=\(app.buttons["map.officialCard.open"].firstMatch.frame)")
        XCTAssertGreaterThanOrEqual(wish.frame.height, 44, "「行きたい」の当たりが 44pt 未満")
        let wantedBefore = wish.isSelected
        wish.tap()
        XCTAssertTrue(wait(wish, "selected == %@", [!wantedBefore], timeout: 10), "「行きたい」を押しても入らない")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "A7-地図の観光スポットの札（行きたい）"
        shot.lifetime = .keepAlways
        add(shot)
        wish.tap()
        XCTAssertTrue(wait(wish, "selected == %@", [wantedBefore], timeout: 10), "もう一度押しても「行きたい」が戻らない")

        // 地図の空いている所（ピンの上 150pt）を押すと札が閉じる
        let empty = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: pin.frame.midX, dy: max(pin.frame.midY - 150, 260)))
        empty.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "地図を押しても札が閉じない")
        // ピンを押し直すと、また開く（押したそばから閉じない）
        pin.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10), "ピンを押し直しても札が開かない")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(card.exists, "ピンを押して開いた札が、すぐ閉じた")
        // 札の名前がボタンに付いていない（入れ物にして読み上げの「閉じる」を足した後も、行きたいが名前で見つかる）
        XCTAssertTrue(wish.waitForExistence(timeout: 5), "読み上げの閉じるを足したら、札の「行きたい」の名前が消えた")

        // 地図を2回たたいて寄せても札は閉じない（1回目で閉じる予約、2回目で取り消す）
        let probe = app.descendants(matching: .any).matching(identifier: "map.cardCloseProbe").firstMatch
        // 🔴 **iOS が2回押しと認めた回だけで確かめる**（2026-11-18 run 1454: シミュレーターの2回たたきが、iOS の2回押しに
        // ならなかった——2回押しの合図 double が増えず、1回押しが2回届いた。iOS から見て2回の別々の押しなので、札が閉じるのは
        // 決まりどおり）。認められなかった回は札を開き直して、3回までたたき直す。gapMs は2回の押しの合図の間（ms）
        func doubles(_ value: String) -> Int {
            guard let range = value.range(of: #"double=(\d+)"#, options: .regularExpression) else { return -1 }
            return Int(value[range].dropFirst("double=".count)) ?? -1
        }
        var recognized = false
        var attempts: [String] = []
        for attempt in 1...3 {
            if !card.exists {
                pin.tap()
                XCTAssertTrue(card.waitForExistence(timeout: 10), "ピンを押し直しても札が開かない（たたき直し \(attempt) 回目）")
                Thread.sleep(forTimeInterval: 1.5)
            }
            let probeBefore = (probe.value as? String) ?? "(なし)"
            empty.doubleTap()
            Thread.sleep(forTimeInterval: 1.5)
            let probeAfter = (probe.value as? String) ?? "(なし)"
            let line = "attempt=\(attempt) before=\(probeBefore) after=\(probeAfter) cardExists=\(card.exists)"
            attempts.append(line)
            print("measured mapDoubleTap \(line)")
            if doubles(probeAfter) > doubles(probeBefore) {
                recognized = true
                XCTAssertTrue(card.exists, "地図を2回たたいて寄せたら札が閉じた（\(line)）")
                break
            }
        }
        XCTAssertTrue(recognized, "シミュレーターの2回たたきが、3回とも iOS の2回押しにならなかった（\(attempts)）")

        // 指で地図を動かすと「このエリアを検索」が出る
        empty.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "寄せた後に地図を押しても札が閉じない")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)))
        XCTAssertTrue(app.buttons["map.searchArea"].firstMatch.waitForExistence(timeout: 5),
                      "地図を動かしても「このエリアを検索」が出ない")

        // Apple の地点の札も × が無く、地図を押せば閉じる。地点が画面に無い回は数だけ残す（地図の中身は Apple 次第）
        Thread.sleep(forTimeInterval: 2)
        let window = app.windows.firstMatch.frame
        let features = app.otherElements.matching(identifier: "VKPointFeature").allElementsBoundByIndex
            .filter { $0.isHittable && $0.frame.minY > window.minY + 220 && $0.frame.maxY < window.maxY - 260 }
        print("measured mapPlaceFeatures count=\(features.count) frames=\(features.prefix(5).map(\.frame))")
        if let feature = features.first {
            feature.tap()
            let placeCard = app.descendants(matching: .any).matching(identifier: "map.placeCard").firstMatch
            if placeCard.waitForExistence(timeout: 8) {
                XCTAssertFalse(placeCard.buttons["閉じる"].exists, "地点の札に × が残っている")
                let away = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: window.midX,
                                         dy: feature.frame.midY > window.midY ? feature.frame.midY - 140 : feature.frame.midY + 140))
                away.tap()
                XCTAssertTrue(placeCard.waitForNonExistence(timeout: 5), "地図を押しても地点の札が閉じない")
            } else {
                print("measured mapPlaceCard notShown afterTap=\(feature.frame)")
            }
        }
    }

    /// A10: 探すの範囲のチップは字を打ってから出る。明朝の「探す」は字を打つと畳む。
    /// 0件はキーボードの上に「見つかりませんでした」と「地図で撮影地を探す」
    func testSearchHeaderAndZeroHit() {
        let app = launch()
        tab(app, 1)
        let field = app.textFields["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "探すの欄が無い")
        let title = app.staticTexts["search.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "頭にいる間は明朝の「探す」を出す")
        XCTAssertFalse(app.buttons["search.scope.people"].firstMatch.exists, "字を打つ前から範囲のチップが出ている")
        // 2026-11-20 判断（札 #662）: 打っている間は結果を変えない。キーボードの「検索」で探す（キーボードは閉じる）
        enter("zzzz-no-photo-result", into: field, "探すの欄")
        XCTAssertFalse(app.buttons["search.emptyMap"].firstMatch.waitForExistence(timeout: 2), "打っただけで結果が入れ替わった")
        field.typeText("\n")
        let toMap = app.buttons["search.emptyMap"].firstMatch
        XCTAssertTrue(toMap.waitForExistence(timeout: 20), "0件でも「地図で撮影地を探す」が出ない")
        XCTAssertTrue(app.buttons["search.scope.people"].firstMatch.waitForExistence(timeout: 5), "字を打っても範囲のチップが出ない")
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "字を打っても明朝の「探す」が残る")
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            print("measured searchZeroHit mapMaxY=\(toMap.frame.maxY) keyboardMinY=\(keyboard.frame.minY)")
            XCTAssertLessThan(toMap.frame.maxY, keyboard.frame.minY, "「地図で撮影地を探す」がキーボードの裏にある")
        }
        XCTAssertGreaterThanOrEqual(toMap.frame.height, 44, "「地図で撮影地を探す」の当たりが 44pt 未満")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "A10-探す（0件）"
        shot.lifetime = .keepAlways
        add(shot)
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
        // 札 #435（2026-11-14）: 「中に入る」の段（`step=` の camper.enter.*）を、通った回も残す（冷えた起動の比べる元）
        notePerfProbe(app, label: "camperEntered")
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
