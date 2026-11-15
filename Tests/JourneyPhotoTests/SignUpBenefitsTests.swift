import XCTest
@testable import JourneyPhoto

/// 「登録するとできること」の段（札 #618 の案1・2026-11-15 判断で案C・`SignUpBenefit`、`HomeSignUpBenefitsView`）。
/// 札の名前と並び、出す条件、ホームへの配線、**ログイン画面を変えていないこと**を確かめる。
/// 画面の部品は Linux で動かせないので、決まりは値で、配線は元のコードを読んで確かめる
/// （寸法と見た目は `ScreenshotTests.testCapturesHomeSignUpBenefits`）
final class SignUpBenefitsTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - 札の中身

    /// 4枚の名前は Web の案内（`lib/auth/signupBenefits.ts` の `SIGNUP_BENEFITS`）と同じ字、同じ順（輪の順）
    func testFourCardsInRingOrderWithWebWording() {
        XCTAssertEqual(SignUpBenefit.allCases.map(\.title),
                       ["写真を載せる", "行きたい場所を保存", "旅行プランを仲間と作る", "メッセージで話す"])
        XCTAssertEqual(SignUpBenefit.heading, "登録するとできること")
        XCTAssertEqual(Set(SignUpBenefit.allCases.map(\.symbol)).count, 4, "絵の印が重なっている")
    }

    /// 中黒で区切らない（owner の好み・2026-11-12）。「撮りどき」「捨てる」も画面の文に使わない
    func testWordingHasNoMiddleDots() {
        let texts = SignUpBenefit.allCases.flatMap { [$0.title, $0.signInReason] }
            + [SignUpBenefit.heading, SignUpBenefit.actionReason, SignUpBenefit.signUpActionReason, SignInPrompt.signUpLabel, SignInPrompt.loginLabel]
            + SignUpBenefit.allCases.map(\.signUpReason)
        for text in texts {
            XCTAssertFalse(text.contains("・") || text.contains("·"), "中黒で区切っている: \(text)")
            XCTAssertFalse(text.contains("撮りどき") || text.contains("捨て"), text)
        }
    }

    /// 投稿、DM、旅行プランから来たときと同じ一言をログイン画面に渡す（ログイン画面の文は増やさない）
    func testCardReasonsReuseExistingSignInLines() throws {
        XCTAssertTrue(try source("Features/Upload/UploadView.swift").contains("\"\(SignUpBenefit.post.signInReason)\""))
        XCTAssertTrue(try source("Features/Messages/DMInboxView.swift").contains("\"\(SignUpBenefit.message.signInReason)\""))
        XCTAssertTrue(try source("Features/Trips/TripPlansView.swift").contains("\"\(SignUpBenefit.tripPlan.signInReason)\""))
    }

    /// ログインしていないと分かってから、写真のある日だけ
    func testShowsOnlyToSignedOutPeopleWithPhotos() {
        XCTAssertTrue(SignUpBenefit.showsOnHome(userId: nil, isResolving: false, feedIsEmpty: false))
        XCTAssertFalse(SignUpBenefit.showsOnHome(userId: "me", isResolving: false, feedIsEmpty: false))
        XCTAssertFalse(SignUpBenefit.showsOnHome(userId: nil, isResolving: true, feedIsEmpty: false),
                       "起動直後の確かめ中に出すと、ログイン済みの人にも一瞬出る")
        XCTAssertFalse(SignUpBenefit.showsOnHome(userId: nil, isResolving: false, feedIsEmpty: true))
    }

    // MARK: - 寸法と色（案1の模型）

    func testLayoutFollowsMock() {
        XCTAssertEqual(HomeSignUpBenefitsLayout.columns, 2)
        XCTAssertEqual(HomeSignUpBenefitsLayout.gap, 8)
        XCTAssertEqual(HomeSignUpBenefitsLayout.padding, 8)
        XCTAssertEqual(HomeSignUpBenefitsLayout.picture, 58)
        XCTAssertEqual(HomeSignUpBenefitsLayout.symbolSize, 26)
        XCTAssertEqual(HomeSignUpBenefitsLayout.photoCount, 4)
    }

    func testColorsAndTapTargetsFollowBoard() throws {
        let view = try source("Features/Gallery/HomeSignUpBenefitsView.swift")
        XCTAssertTrue(view.contains(".jpEyebrow()\n                .foregroundStyle(WebTheme.accent)"), "眉ラベルが真鍮でない")
        XCTAssertTrue(view.contains("Image(systemName: benefit.symbol)\n                    .font(.system(size: HomeSignUpBenefitsLayout.symbolSize, weight: .semibold))\n                    .foregroundStyle(WebTheme.foreground)"),
                      "写真の上の印が白でない")
        XCTAssertTrue(view.contains(".background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))"))
        XCTAssertTrue(view.contains(".font(JPFont.footnote.weight(.semibold))"), "名前が本文系 12 を割る")
        XCTAssertTrue(view.contains("Text(SignInPrompt.signUpLabel).jpOutlineButton(.regular)"), "下の新規登録が線のボタン（44）でない")
        XCTAssertFalse(view.contains("WebTheme.accentFill"), "写真の並びの中に真鍮の主ボタンを置いている")
        XCTAssertTrue(view.contains("typeSize.isAccessibilitySize ? 1 : HomeSignUpBenefitsLayout.columns"))
    }

    // MARK: - 配線

    /// 札を押すと今のログイン画面（`SignInSheet`）。確かめは挟まない（押す回数 1回）。
    /// 札と「新規登録」は登録の側、「ログイン」はログインの側で開く（札 #630・Web の段と同じ2つ）
    func testCardsOpenTheExistingSignInSheet() throws {
        let view = try source("Features/Gallery/HomeSignUpBenefitsView.swift")
        XCTAssertTrue(view.contains("signInOpen = SignInRequest(reason: benefit.signUpReason, entry: .signUp)"),
                      "札が登録の側で開かない")
        XCTAssertTrue(view.contains("signInOpen = SignInRequest(reason: SignUpBenefit.signUpActionReason, entry: .signUp)"),
                      "「新規登録」が登録の側で開かない")
        XCTAssertTrue(view.contains("signInOpen = SignInRequest(reason: SignUpBenefit.actionReason)\n"),
                      "「ログイン」が無い")
        XCTAssertTrue(view.contains("Text(SignInPrompt.loginLabel)"))
        XCTAssertFalse(view.contains("ログイン、新規登録"), "1つのボタンに2つを詰めている（登録はもう1回押すことになる）")
        XCTAssertTrue(view.contains(".signInPrompt(ask: $signInAsk, open: $signInOpen)"))
        XCTAssertFalse(view.contains("signInAsk = "), "確かめの窓を挟むと押す回数が増える")
        XCTAssertFalse(view.contains("SignInView("), "ログイン画面を作り直している")
    }

    /// ホームの並びの、季節の段とおすすめの人の後ろ・残りの写真の前に1回だけ
    func testHomeShowsTheSectionOnceAfterFirstCycle() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertEqual(gallery.components(separatedBy: "HomeSignUpBenefitsView(").count - 1, 1)
        let body = gallery.components(separatedBy: "private func feedSection(").dropFirst().first ?? ""
        let shelf = body.range(of: "HomeSpotShelfView(")
        let benefits = body.range(of: "SignUpBenefit.showsOnHome(userId: auth.userId, isResolving: auth.isResolving, feedIsEmpty: isEmpty)")
        let rest = body.range(of: "if !rows.rest.isEmpty {")
        XCTAssertNotNil(benefits, "ホームに段が無い")
        if let shelf, let benefits, let rest {
            XCTAssertLessThan(shelf.lowerBound, benefits.lowerBound)
            XCTAssertLessThan(benefits.lowerBound, rest.lowerBound)
        }
    }

    /// owner「アカウント登録画面は何も変えたくない」（2026-11-15）: ログイン画面に札を置かない
    func testSignInScreenIsUntouched() throws {
        let signIn = try source("Features/Auth/SignInView.swift")
        XCTAssertFalse(signIn.contains("SignUpBenefit"))
        XCTAssertTrue(try source("Features/Profile/MyPageView.swift").contains("SignInView(reason: nil)"),
                      "マイページの手前に札の画面をはさまない（押す回数が増える）")
    }
}
