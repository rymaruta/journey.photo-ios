import XCTest
@testable import JourneyPhoto

/// 確認コードの6桁の箱（模型 NL2x「登録の確認コード」「確認コードの状態」「パスワードの再設定」・2026-11-23 owner「これでいいよ」）。
/// 決まりは値で、画面の配線は元のコードを読んで確かめる
final class VerificationCodeTests: XCTestCase {

    // MARK: - 入力の整え方

    /// キーボードの候補・貼り付けの6桁がそのまま入る。数字以外は捨てずに無視、7桁目から入れない
    func testNormalizeKeepsDigitsOnlyAndStopsAtSix() {
        XCTAssertEqual(VerificationCodeEntry.normalize("482913"), "482913")
        XCTAssertEqual(VerificationCodeEntry.normalize("482-913"), "482913", "区切りのある貼り付けが6桁にならない")
        XCTAssertEqual(VerificationCodeEntry.normalize(" 482 913\n"), "482913")
        XCTAssertEqual(VerificationCodeEntry.normalize("確認コード 482913 です"), "482913", "文ごと貼っても数字だけ拾わない")
        XCTAssertEqual(VerificationCodeEntry.normalize("4829137"), "482913", "7桁目が入った")
        XCTAssertEqual(VerificationCodeEntry.normalize("12345678901"), "123456")
        XCTAssertEqual(VerificationCodeEntry.normalize("12a"), "12", "数字以外で全体を捨てた")
        XCTAssertEqual(VerificationCodeEntry.normalize("４８２９１３"), "482913", "全角の数字を拾わない")
        XCTAssertEqual(VerificationCodeEntry.normalize("abc"), "")
        XCTAssertEqual(VerificationCodeEntry.normalize("٤٨٢"), "", "ほかの文字の数字を拾った")
    }

    /// 途中まで打ってから候補・貼り付けで6桁が続けて入ったら、後から入った6桁を取る。1字ずつの7桁目は入れない
    func testCandidateAfterPartialTypingTakesTheNewSix() {
        XCTAssertEqual(VerificationCodeEntry.normalize("48482913", previous: "48"), "482913", "「48」＋候補が先頭の6桁になった")
        XCTAssertEqual(VerificationCodeEntry.normalize("4829137", previous: "482913"), "482913", "1字ずつの7桁目が入った")
        XCTAssertEqual(VerificationCodeEntry.normalize("4831", previous: "48"), "4831")
        var entry = VerificationCodeEntry()
        entry.input("48")
        entry.input("48482913")
        XCTAssertEqual(entry.code, "482913")
        XCTAssertTrue(entry.shouldSubmit(isOffline: false))
    }

    func testInputUpdatesCodeAndBoxes() {
        var entry = VerificationCodeEntry()
        entry.input("48")
        XCTAssertEqual(entry.code, "48")
        XCTAssertEqual(entry.digit(at: 0), "4")
        XCTAssertNil(entry.digit(at: 2))
        XCTAssertEqual(entry.currentIndex, 2, "いま打つ箱が3つ目でない")
        entry.input("4829135")
        XCTAssertEqual(entry.code, "482913")
        XCTAssertTrue(entry.isComplete)
        XCTAssertNil(entry.currentIndex, "そろったのに打つ箱が残る")
    }

    // MARK: - 自動で確かめる

    func testAutoSubmitOnlyWhenSixDigitsAndOnline() {
        var entry = VerificationCodeEntry()
        entry.input("48291")
        XCTAssertFalse(entry.shouldSubmit(isOffline: false), "5桁で確かめた")
        entry.input("482913")
        XCTAssertFalse(entry.shouldSubmit(isOffline: true), "圏外で送った")
        XCTAssertTrue(entry.shouldSubmit(isOffline: false), "6桁そろっても確かめない")
    }

    /// 🔴 二重に送らない: 確かめ中は送らず、同じコードを二度送らない
    func testNoDoubleSubmit() {
        var entry = VerificationCodeEntry(code: "482913")
        XCTAssertEqual(entry.beginCheck(), "482913")
        XCTAssertEqual(entry.phase, .checking)
        XCTAssertFalse(entry.shouldSubmit(isOffline: false), "確かめ中にもう一度送った")
        XCTAssertNil(entry.beginCheck(), "確かめ中にもう一度出した")
        entry.input("111111")
        XCTAssertEqual(entry.code, "482913", "確かめ中に打った字を受けた")
        // そのほかの失敗（回数の上限）: 同じコードで送り続けない
        entry.finish(.failed)
        XCTAssertEqual(entry.phase, .typing)
        XCTAssertFalse(entry.shouldSubmit(isOffline: false), "失敗した同じコードをまた送る")
        entry.input("48291")
        entry.input("482914")
        XCTAssertTrue(entry.shouldSubmit(isOffline: false), "打ち直したコードを送らない")
    }

    /// 違うコード: 赤で見せてから空に戻す。文は打ち始めるまで残る。打ち直した6桁はまた自動で確かめる
    func testWrongCodeClearsAndRetries() {
        var entry = VerificationCodeEntry(code: "482931")
        _ = entry.beginCheck()
        entry.finish(.wrong)
        XCTAssertEqual(entry.phase, .wrong)
        XCTAssertEqual(entry.code, "482931", "揺らす前に消えた")
        XCTAssertEqual(entry.errorText, VerificationCodeEntry.wrongText)
        entry.clearWrong()
        XCTAssertEqual(entry.code, "")
        XCTAssertEqual(entry.errorText, VerificationCodeEntry.wrongText, "空に戻しただけで文が消えた")
        XCTAssertEqual(entry.currentIndex, 0, "1つ目の箱から打てない")
        entry.input("4")
        XCTAssertNil(entry.errorText, "打ち始めても文が残る")
        entry.input("482913")
        XCTAssertTrue(entry.shouldSubmit(isOffline: false))
    }

    func testExpiredEmptiesBoxesAndOffersNewCode() {
        var entry = VerificationCodeEntry(code: "482913")
        _ = entry.beginCheck()
        entry.finish(.expired)
        XCTAssertEqual(entry.phase, .expired)
        XCTAssertEqual(entry.code, "")
        XCTAssertEqual(entry.errorText, VerificationCodeEntry.expiredText)
        XCTAssertEqual(VerificationCodeLine.line(for: entry, isOffline: false, remaining: 0), .none,
                       "期限切れなのに箱の下の1行が出る（主ボタンを出す）")
        entry.restart()
        XCTAssertEqual(entry.phase, .typing)
        XCTAssertNil(entry.errorText)
    }

    /// 圏外: 打ったコードは残し、電波が戻ったら押さなくても確かめ直す
    func testOfflineKeepsCodeAndRetriesOnReconnect() {
        var entry = VerificationCodeEntry(code: "482913")
        _ = entry.beginCheck()
        entry.finish(.offline)
        XCTAssertEqual(entry.code, "482913", "圏外で打ったコードが消えた")
        XCTAssertFalse(entry.shouldSubmit(isOffline: true))
        XCTAssertEqual(VerificationCodeLine.line(for: entry, isOffline: true, remaining: 30), .offline)
        entry.reconnected()
        XCTAssertTrue(entry.shouldSubmit(isOffline: false), "電波が戻っても確かめ直さない")
    }

    func testOutcomeFromFailure() {
        typealias O = VerificationCodeEntry.Outcome
        XCTAssertEqual(O.from(.codeMismatch, isOffline: false), .wrong)
        XCTAssertEqual(O.from(.codeExpired, isOffline: false), .expired)
        XCTAssertEqual(O.from(.network, isOffline: true), .offline)
        XCTAssertEqual(O.from(.network, isOffline: false), .failed, "電波があるのに圏外の形にした（戻るのを待っても戻らない）")
        XCTAssertEqual(O.from(.limitExceeded, isOffline: false), .failed)
        XCTAssertEqual(O.from(.none, isOffline: false), .verified)
    }

    /// 🔴 再設定は、無いアカウントを「コードが違います」と同じにする（アカウントの有無を分からせない）
    func testResetHidesMissingAccountAsWrongCode() {
        typealias O = VerificationCodeEntry.Outcome
        XCTAssertEqual(O.from(.userNotFound, isOffline: false, hidesAccount: true), .wrong, "再設定で無いアカウントが分かる")
        XCTAssertEqual(O.from(.userNotFound, isOffline: false), .failed)
        let view = try? source("Features/Auth/SignInView.swift")
        XCTAssertTrue(view?.contains("applyCodeFailure(hidesAccount: true)") == true, "再設定の失敗でアカウントを隠していない")
        XCTAssertTrue(view?.contains("hidesAccount: hidesAccount)") == true, "隠す印を Outcome に渡していない")
    }

    // MARK: - 送り直しの待ち時間

    func testResendCooldownCountsSixtySeconds() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var cooldown = ResendCooldown()
        XCTAssertTrue(cooldown.canResend(now: start), "まだ送っていないのに待たせる")
        cooldown.start(now: start)
        XCTAssertEqual(ResendCooldown.seconds, 60)
        XCTAssertEqual(cooldown.remaining(now: start), 60)
        XCTAssertEqual(cooldown.remaining(now: start.addingTimeInterval(0.4)), 60, "切り上げていない")
        XCTAssertEqual(cooldown.remaining(now: start.addingTimeInterval(59.5)), 1)
        XCTAssertFalse(cooldown.canResend(now: start.addingTimeInterval(59.9)))
        XCTAssertTrue(cooldown.canResend(now: start.addingTimeInterval(60)))
        XCTAssertEqual(cooldown.remaining(now: start.addingTimeInterval(-5)), 60, "時計が戻ったとき 60 を超えた")
        cooldown.clear()
        XCTAssertTrue(cooldown.canResend(now: start))
    }

    // MARK: - 文（模型のとおり）

    func testLineAndTexts() {
        var entry = VerificationCodeEntry()
        XCTAssertEqual(VerificationCodeLine.line(for: entry, isOffline: false, remaining: 60), .wait(60))
        XCTAssertEqual(VerificationCodeLine.wait(60).text, L("60秒後に送り直せます", "You can resend in 60s"))
        XCTAssertEqual(VerificationCodeLine.line(for: entry, isOffline: false, remaining: 0), .resend)
        XCTAssertEqual(VerificationCodeLine.resend.text, L("コードを送り直す", "Send a new code"))
        entry.input("482913")
        XCTAssertEqual(VerificationCodeLine.line(for: entry, isOffline: true, remaining: 10), .offline,
                       "圏外で6桁そろったのに「電波が戻ったら」を出さない")
        _ = entry.beginCheck()
        XCTAssertEqual(VerificationCodeLine.line(for: entry, isOffline: false, remaining: 10), .checking)
        XCTAssertEqual(entry.announcement, L("確かめています", "Checking"))
        entry.finish(.verified)
        XCTAssertEqual(VerificationCodeLine.line(for: entry, isOffline: false, remaining: 10), .verified)
        XCTAssertEqual(entry.announcement, L("確認できました", "Verified"))
        XCTAssertEqual(VerificationCodeEntry.wrongText, L("コードが違います。もう一度入れてください", "That code isn't right. Please enter it again."))
        XCTAssertEqual(VerificationCodeEntry.expiredText, L("このコードは期限が切れました", "This code has expired"))
        XCTAssertEqual(VerificationCodeEntry.offlineText, L("電波が戻ったら、そのまま確かめます", "We'll check it as soon as you're back online"))
        // 「・」で区切らない、「捨てる」と言わない
        for text in [VerificationCodeEntry.wrongText, VerificationCodeEntry.expiredText, VerificationCodeEntry.checkingText,
                     VerificationCodeEntry.verifiedText, VerificationCodeEntry.offlineText, VerificationCodeEntry.resendText,
                     VerificationCodeEntry.newCodeText, VerificationCodeEntry.changeEmailText, VerificationCodeEntry.sentAfter,
                     AuthMessage.passwordRuleShort] {
            XCTAssertFalse(text.contains("・") || text.contains("·") || text.contains("捨て"), text)
        }
    }

    /// 箱の寸法（模型 NL2x の「詳しく」）
    func testBoxMetrics() {
        XCTAssertEqual(VerificationCodeEntry.length, 6)
        XCTAssertEqual(VerificationCodeEntry.groupSize, 3)
        XCTAssertEqual(VerificationCodeLayout.boxHeight, 58)
        XCTAssertEqual(VerificationCodeLayout.boxCorner, 12)
        XCTAssertEqual(VerificationCodeLayout.groupGap, 16)
        XCTAssertEqual(VerificationCodeLayout.digitSize, 28)
        XCTAssertEqual(VerificationCodeLayout.primaryStyle, .accent, "写真の無い画面の主ボタンが真鍮でない")
        XCTAssertGreaterThanOrEqual(VerificationCodeLayout.boxHeight, 44)
    }

    // MARK: - 画面の配線（元のコードを読む）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 中身は1つの欄（`.oneTimeCode`・数字のキーボード）。動きを減らす設定では揺らさない
    func testFieldIsOneOneTimeCodeField() throws {
        let field = try source("Features/Auth/VerificationCodeField.swift")
        for part in [".textContentType(.oneTimeCode)", ".keyboardType(.numberPad)", "guard !reduceMotion else { return }",
                     "WebTheme.danger", "WebTheme.accent", "JPFont.number(VerificationCodeLayout.digitSize, weight: .semibold",
                     ".allowsHitTesting(false)", "signin.code"] {
            XCTAssertTrue(field.contains(part), "箱に \(part) が無い")
        }
        XCTAssertEqual(field.components(separatedBy: "JPTextField(").count - 1, 1, "欄が1つでない（箱ごとに欄を作った）")
    }

    /// 登録の確認と再設定が同じ箱を使い、「登録を完了する」は無い。6桁で自動で確かめる
    func testSignInViewWiring() throws {
        let view = try source("Features/Auth/SignInView.swift")
        XCTAssertEqual(view.components(separatedBy: "VerificationCodeField(").count - 1, 1,
                       "登録の確認と再設定で箱を別々に作っている")
        XCTAssertFalse(view.contains("L(\"登録を完了する\""), "「登録を完了する」のボタンが残っている")
        let typed = try slice(view, from: "private func codeTyped", to: "/// 登録の確認: 6桁そろっていれば")
        XCTAssertTrue(typed.contains("attemptConfirmIfReady()"), "6桁で自動で確かめない")
        XCTAssertTrue(typed.contains("focusedField = .newPassword"), "再設定で新しいパスワードの欄へ移らない")
        XCTAssertTrue(typed.contains("if raw != codeEntry.code { code = codeEntry.code }"), "整えた6桁を欄へ書き戻さない")
        let attempt = try slice(view, from: "private func attemptConfirmIfReady", to: "/// 電波が戻った")
        for part in ["!auth.isWorking", "codeEntry.shouldSubmit(isOffline: connectivity.isOffline)", "codeEntry.beginCheck()"] {
            XCTAssertTrue(attempt.contains(part), "自動で確かめる条件に \(part) が無い")
        }
        let screen = try slice(view, from: "private var codeScreen", to: "/// パスワードの再設定のコードの画面か")
        for part in ["JPStateBand(kind: .offline", "codeBackButton", "changeEmailButton", "codeStatusLine",
                     "UIAccessibility.post(notification: .announcement, argument: text)", "reconnected()"] {
            XCTAssertTrue(screen.contains(part), "確認コードの画面に \(part) が無い")
        }
        XCTAssertFalse(screen.contains("tileHeader"), "確認コードの画面に写真のタイルが残っている")
        // 既存の大事な動き: 確認の後の自動ログイン・名前の控え・aliasExists の戻し
        let confirm = try slice(view, from: "private func confirmSignUp", to: "// MARK: - パスワードの再設定")
        for part in ["await auth.signIn(email: email, password: password)", "pending.forgetSignUp(email: email)",
                     "applyDisplayName(name)", "auth.lastFailure == .aliasExists", "mode = .signIn"] {
            XCTAssertTrue(confirm.contains(part), "登録の確認に \(part) が無い")
        }
        XCTAssertTrue(view.contains(".accessibilityLabel(L(\"ログインに戻る\", \"Back to sign in\"))"), "戻り道が無い")
        // 確かめ役の指摘（2026-11-23）
        let back = try slice(view, from: "private var codeBackButton", to: "} label: {")
        XCTAssertLessThan(try XCTUnwrap(back.range(of: "let wasReset = isResetCode")).lowerBound,
                          try XCTUnwrap(back.range(of: "mode = .signIn")).lowerBound, "再設定かを mode を変えた後に見ている")
        XCTAssertTrue(back.contains("if wasReset { password = \"\" }"))
        XCTAssertTrue(view.contains(".toolbar(showsCodeScreen ? .hidden : .automatic, for: .navigationBar)"),
                      "コードの画面でシートの閉じると戻るが2つ並ぶ")
        XCTAssertTrue(screen.contains("codeEntry.errorText ?? (resetPasswordVisible ? nil : auth.errorMessage)"),
                      "再設定でパスワードの節が出ていない間の失敗が出ない")
        XCTAssertTrue(screen.contains("if codeEntry.phase != .verified { focusedField = .code }"), "開いたとき焦点を当て直さない")
        let failure = try slice(view, from: "private func applyCodeFailure", to: "/// 「コードを送り直す」")
        XCTAssertTrue(failure.contains("guard codeEntry.phase == .wrong else { return }"), "送り直した後に空に戻してしまう")
        let field = try source("Features/Auth/VerificationCodeField.swift")
        XCTAssertTrue(field.contains(".onTapGesture { focus.wrappedValue = .code }"), "箱の端を押しても焦点が来ない")
    }

    private func slice(_ text: String, from start: String, to end: String) throws -> String {
        let a = try XCTUnwrap(text.range(of: start), start)
        let b = try XCTUnwrap(text.range(of: end, range: a.upperBound..<text.endIndex), end)
        return String(text[a.lowerBound..<b.lowerBound])
    }
}
