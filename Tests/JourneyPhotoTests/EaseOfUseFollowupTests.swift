import XCTest
@testable import JourneyPhoto

/// 人間工学の点検の続き（2026-11-14 判断・owner「今ある機能を更に使いやすく」）の3件を見張る。
///
/// 1. ストーリーの「場所」は候補つきの欄（`StoryPlaceSheet` が `PlaceSearchField` を使い回す）
/// 2. 探すの「最近の検索」（`RecentSearchesStore`・端末の中だけ）
/// 3. ログイン・登録・再設定・パスワードの変更は、キーボードの右下のキーで次の欄へ進み、最後の欄で送る（`AuthFieldFlow`）
final class EaseOfUseFollowupTests: XCTestCase {

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    // MARK: - 1. ストーリーの「場所」

    /// 🔴 「場所」は字を打つだけの窓（`alert`）ではなく、候補つきの欄のシートを開く
    func testStoryPlaceToolOpensSuggestingSheet() throws {
        let composer = try source("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertFalse(composer.contains(".alert(L(\"撮影地\", \"Place\"), isPresented: $showPlaceEditor)"),
                       "「場所」がまだ字を打つだけの窓")
        XCTAssertTrue(composer.contains(".sheet(isPresented: $showPlaceEditor)"), "「場所」でシートを開かない")
        XCTAssertTrue(composer.contains("StoryPlaceSheet(initial: place.location"), "「場所」のシートが候補つきの欄でない")
        XCTAssertTrue(composer.contains("setPlace(picked)"), "選んだ撮影地を写真の上の札に合わせていない")
    }

    /// 🔴 シートは投稿の撮影地の欄と**同じ部品**を使い、候補を押したら決めて閉じる。開いたらすぐ打てる
    func testStoryPlaceSheetReusesPlaceSearchField() throws {
        let sheet = try source("Sources/JourneyPhoto/Features/Stories/StoryPlaceSheet.swift")
        XCTAssertTrue(sheet.contains("PlaceSearchField("), "撮影地の欄を写しで作っている")
        XCTAssertTrue(sheet.contains("offersSpots: true"), "撮影スポットの候補を出さない")
        XCTAssertTrue(sheet.contains("autoFocus: true"), "開いてもすぐ打てない")
        XCTAssertTrue(sheet.contains("onPick: { name in finish(name) }"), "候補を押しても決まらない")
        XCTAssertTrue(sheet.contains("SheetCloseButton(onContent: true)"), "閉じるが左上に無い（板の決まり）")
        XCTAssertFalse(sheet.contains("TextField("), "シートが自前の欄を持っている（写しを作らない）")

        let field = try source("Sources/JourneyPhoto/Features/Upload/PlaceSearchField.swift")
        XCTAssertTrue(field.contains("onPick?(spot.name)"), "撮影スポットの候補を押しても知らせない")
        XCTAssertTrue(field.contains("onPick?(place.label)"), "地名の候補を押しても知らせない")
        XCTAssertTrue(field.contains("if autoFocus { focused = true }"), "開いたときに欄へ焦点を当てない")
        // 投稿画面の UI テストの名前は変えない
        XCTAssertTrue(field.contains("var fieldIdentifier = \"upload.place\""))
    }

    // MARK: - 2. 最近の検索

    /// 新しい順・同じ言葉は1つにまとめて上へ・5つまで・空と長すぎる言葉は覚えない
    func testRememberingOrdersNewestFirstAndDedupes() {
        var words: [String] = []
        for w in ["京都", "奈良", " 京都 ", "Kyoto", "kyoto"] {
            words = RecentSearchesStore.remembering(w, in: words)
        }
        XCTAssertEqual(words, ["kyoto", "京都", "奈良"], "同じ言葉をまとめていない・新しい順でない")
        for w in ["a", "b", "c", "d", "e", "f"] {
            words = RecentSearchesStore.remembering(w, in: words)
        }
        XCTAssertEqual(words, ["f", "e", "d", "c", "b"], "5つまでで切れていない")
        XCTAssertEqual(RecentSearchesStore.remembering("   ", in: ["a"]), ["a"], "空の言葉を覚えた")
        let long = String(repeating: "あ", count: RecentSearchesStore.maxLength + 1)
        XCTAssertEqual(RecentSearchesStore.remembering(long, in: ["a"]), ["a"], "長すぎる言葉を覚えた")
        XCTAssertEqual(RecentSearchesStore.remembering("ＡＢＣ", in: ["abc"]), ["ＡＢＣ"], "全角半角の違いで2つになった")
    }

    /// 端末に覚え、読み直しても残る。人ごとに分ける。1つずつ・全部消せる
    func testStoreKeepsPerUserAndRemoves() {
        let d = defaults()
        let store = RecentSearchesStore(defaults: d)
        store.remember("京都", userId: "u1")
        store.remember("奈良", userId: "u1")
        store.remember("札幌", userId: "u2")
        store.remember("那覇", userId: nil)
        XCTAssertEqual(RecentSearchesStore(defaults: d).words(userId: "u1"), ["奈良", "京都"])
        XCTAssertEqual(RecentSearchesStore(defaults: d).words(userId: "u2"), ["札幌"], "別の人の言葉が混ざった")
        XCTAssertEqual(RecentSearchesStore(defaults: d).words(userId: nil), ["那覇"])
        XCTAssertEqual(store.remove("京都", userId: "u1"), ["奈良"], "1つ消せない")
        store.removeAll(userId: "u1")
        XCTAssertEqual(store.words(userId: "u1"), [], "全部消せない")
        XCTAssertEqual(store.words(userId: "u2"), ["札幌"], "全部消すで別の人の言葉まで消した")
    }

    /// 欄が空の間だけ出す。カテゴリだけで絞っている間は、欄を押したときだけ
    func testShowsOnlyWhileFieldIsEmpty() {
        XCTAssertTrue(RecentSearchesStore.shows(query: "", words: ["京都"], discovering: true, focused: false))
        XCTAssertTrue(RecentSearchesStore.shows(query: "", words: ["京都"], discovering: false, focused: true))
        XCTAssertFalse(RecentSearchesStore.shows(query: "京", words: ["京都"], discovering: false, focused: true),
                       "打っている間も出した")
        XCTAssertFalse(RecentSearchesStore.shows(query: "", words: [], discovering: true, focused: true), "空の段を出した")
        XCTAssertFalse(RecentSearchesStore.shows(query: "", words: ["京都"], discovering: false, focused: false),
                       "カテゴリの結果の上に割り込んだ")
    }

    /// 🔴 探す画面が言葉を覚え（右下の「検索」・欄を離れたとき）、欄が空なら段を出す
    func testSearchViewWiresRecentSearches() throws {
        let view = try source("Sources/JourneyPhoto/Features/Search/SearchView.swift")
        XCTAssertTrue(view.contains(".onSubmit { rememberQuery() }"), "右下の「検索」で言葉を覚えない")
        XCTAssertTrue(view.contains(".onChange(of: fieldFocused) { _, focused in if !focused { rememberQuery() } }"),
                      "欄を離れたときに言葉を覚えない")
        XCTAssertTrue(view.contains("if showsRecentSearches {"), "最近の検索の段を出さない")
        XCTAssertTrue(view.contains("RecentSearchesSection(words: recentWords"))
        // サーバーには送らない（端末の中だけ）
        let store = try source("Sources/JourneyPhoto/Core/Storage/RecentSearchesStore.swift")
        XCTAssertFalse(store.contains("environment") || store.contains("APIClient") || store.contains("URLSession"),
                       "最近の検索をサーバーへ送っている")
    }

    // MARK: - 3. 右下のキーで進む

    /// ログイン: メール →（次へ）→ パスワード →（完了）→ ログイン
    func testSignInMovesEmailToPasswordThenSubmits() {
        let both: Set<AuthFieldFlow.Field> = [.email, .password]
        XCTAssertEqual(AuthFieldFlow.step(after: .email, in: .signIn, filled: [.email]), .focus(.password))
        XCTAssertEqual(AuthFieldFlow.step(after: .password, in: .signIn, filled: both), .submit)
        XCTAssertEqual(AuthFieldFlow.key(for: .email, in: .signIn), .next)
        XCTAssertEqual(AuthFieldFlow.key(for: .password, in: .signIn), .done)
        // 🔴 メールが空のまま最後の欄で押したら、送らずにメールの欄へ戻す
        XCTAssertEqual(AuthFieldFlow.step(after: .password, in: .signIn, filled: [.password]), .focus(.email))
    }

    /// 登録: メール → パスワード → 表示名（任意。空でも送る）
    func testSignUpEndsAtOptionalDisplayName() {
        XCTAssertEqual(AuthFieldFlow.step(after: .email, in: .signUp, filled: []), .focus(.password))
        XCTAssertEqual(AuthFieldFlow.step(after: .password, in: .signUp, filled: [.email, .password]),
                       .focus(.displayName))
        XCTAssertEqual(AuthFieldFlow.step(after: .displayName, in: .signUp, filled: [.email, .password]), .submit,
                       "表示名が空だと送れない（任意の欄）")
        XCTAssertEqual(AuthFieldFlow.key(for: .password, in: .signUp), .next)
        XCTAssertEqual(AuthFieldFlow.key(for: .displayName, in: .signUp), .done)
    }

    /// 再設定: メールで「送信」→ コードを送る。コードと新しいパスワード →（完了）→ 変える
    func testResetAndChangePasswordFlows() {
        XCTAssertEqual(AuthFieldFlow.key(for: .email, in: .resetRequest), .send)
        XCTAssertEqual(AuthFieldFlow.step(after: .email, in: .resetRequest, filled: [.email]), .submit)
        XCTAssertEqual(AuthFieldFlow.step(after: .newPassword, in: .resetConfirm, filled: [.newPassword]), .focus(.code),
                       "コードが空のまま送った")
        XCTAssertEqual(AuthFieldFlow.step(after: .newPassword, in: .resetConfirm, filled: [.code, .newPassword]), .submit)
        XCTAssertEqual(AuthFieldFlow.step(after: .currentPassword, in: .changePassword, filled: [.currentPassword]),
                       .focus(.newPassword))
        XCTAssertEqual(AuthFieldFlow.step(after: .newPassword, in: .changePassword,
                                          filled: [.currentPassword, .newPassword]), .submit)
        XCTAssertEqual(AuthFieldFlow.key(for: .currentPassword, in: .changePassword), .next)
        XCTAssertEqual(AuthFieldFlow.key(for: .newPassword, in: .changePassword), .done)
    }

    /// 🔴 欄が右下のキーを受ける（無いとキーボードが閉じるだけ）
    func testAuthFieldsHandleReturnKey() throws {
        let signIn = try source("Sources/JourneyPhoto/Features/Auth/SignInView.swift")
        XCTAssertTrue(signIn.contains("@FocusState private var focusedField: AuthFieldFlow.Field?"))
        for field in ["email", "password", "displayName", "newPassword"] {
            XCTAssertTrue(signIn.contains(".onSubmit { advance(from: .\(field)) }"), "ログインの \(field) が右下のキーを受けない")
            XCTAssertTrue(signIn.contains(".focused($focusedField, equals: .\(field))"), "ログインの \(field) に焦点を移せない")
        }
        XCTAssertTrue(signIn.contains("Task { await submitCredentials() }"))
        let change = try source("Sources/JourneyPhoto/Features/Settings/ChangePasswordView.swift")
        for field in ["currentPassword", "newPassword"] {
            XCTAssertTrue(change.contains(".onSubmit { advance(from: .\(field)) }"), "パスワードの変更の \(field) が右下のキーを受けない")
        }
    }
}

/// 退会の後始末（`AccountLocalData` は `@MainActor`。テストの組を分けて async で呼ぶ・ほかの退会の試験と同じ形）
@MainActor
final class EaseOfUseFollowupAccountTests: XCTestCase {

    /// 🔴 退会したら端末の言葉も消す（`AccountLocalData`）
    func testAccountRemovalDeletesRecentSearches() async {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        RecentSearchesStore(defaults: d).remember("京都", userId: "a")
        RecentSearchesStore(defaults: d).remember("奈良", userId: "b")
        AccountLocalData.remove(userId: "a", username: nil, defaults: d, draftDirectory: temp,
                                offlineTripsRoot: temp, passRoot: temp)
        XCTAssertEqual(RecentSearchesStore(defaults: d).words(userId: "a"), [], "退会した人の言葉が残った")
        XCTAssertEqual(RecentSearchesStore(defaults: d).words(userId: "b"), ["奈良"], "別の人の言葉まで消した")
    }
}
