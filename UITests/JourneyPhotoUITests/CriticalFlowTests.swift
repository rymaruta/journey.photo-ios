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
    }

    /// **別の投稿を1回ずつ**ストーリーに載せる（2本）→ ホームの輪 → マイページ。写真は 12MP の HEIC（4032×3024・向き 6）
    func testTwoPostsSharedToStoryOpen() {
        let app = launchForStory(kind: "heic12")
        postAndShare(app, shares: 1, tag: "a")
        postAndShare(app, shares: 1, tag: "b")
        openFromHomeRing(app)
        openFromMyPage(app)
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
        let toPhoto = app.buttons["post.choice.photo"].firstMatch
        XCTAssertTrue(toPhoto.waitForExistence(timeout: 10), "投稿の2択が出ない")
        toPhoto.tap()
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
        storyCrashStep(app, "\(tag).upload.submitted")

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
        XCTAssertTrue(thumb.waitForNonExistence(timeout: 30), "カードを閉じても投稿画面が閉じない")
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
        XCTAssertTrue(ringShown, "ストーリーを出したのに、ホームに自分の輪（あなたのストーリー）が出ない")
        guard ringShown else { return }
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
        XCTAssertTrue(ringShown, "ストーリーを出したのに、マイページの顔に輪が出ない")
        guard ringShown else { return }
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
            XCTAssertTrue(seen, "\(entry) から\(round)回目に開いても、出したばかりの紹介のストーリー（「写真を見る」）が出ない")
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
            XCTAssertEqual(app.state, .runningForeground, "[storyCrash] \(entry) で見終わるまでにアプリが前に居ない")
            guard round < rounds else { break }
            // もう一度（今度は「見た」の輪から）。前の要素を使い回さず、探し直す
            let again = ring()
            let ready = again.waitForExistence(timeout: 15) && wait(again, "hittable == true", timeout: 10)
            storyCrashStep(app, "\(entry).beforeReopen ready=\(ready)")
            XCTAssertTrue(ready, "\(entry) の輪にもう一度押せない")
            guard ready else { return }
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
