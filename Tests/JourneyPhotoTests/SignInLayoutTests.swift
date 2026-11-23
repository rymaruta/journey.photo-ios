import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ログイン・新規登録の画面の置き方（2026-11-23・模型 NL2x で見つかった2つ）。
///
/// 1. Apple・Google のボタンが答えの後から出て、メールの欄が約 150pt ずれた
///    → 前回の答えを覚えて最初からその形で描く。画面の下から積むので、出し入れで欄が動かない（上の写真とロゴが縮む）
/// 2. 失敗の文が1画面の下端より下に出ていた・小さい画面の新規登録で「登録する」が下端にかかった
///    → 失敗の文は欄のすぐ上。owner「スクロールしないといけないのが嫌だ」: 送らずに全部が1画面に収まる（模型 NL2x の寸法）
///
/// 画面は Linux の模型では描けないので、**決まりの値**と**書いてあること**を見る。直しを戻すと落ちる
final class SignInLayoutTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suite = "SignInLayoutTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        StubProtocol.reset()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        StubProtocol.reset()
        try await super.tearDown()
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    private func slice(_ text: String, from start: String, to end: String) throws -> String {
        let lower = try XCTUnwrap(text.range(of: start), "「\(start)」が見つからない")
        let upper = try XCTUnwrap(text.range(of: end, range: lower.upperBound..<text.endIndex), "「\(end)」が見つからない")
        return String(text[lower.lowerBound..<upper.lowerBound])
    }

    private func position(of part: String, in text: String) throws -> String.Index {
        try XCTUnwrap(text.range(of: part), "「\(part)」が見つからない").lowerBound
    }

    private func api() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "https://api.example.test")!,
                         tokenProvider: StubTokenProvider(token: nil),
                         session: URLSession(configuration: config))
    }

    // MARK: - 1. 前回の答えを覚える

    /// 覚えが無い（初めて）ときは出さない形から。Apple と Google は別々に覚える
    func testMemoryStartsHiddenAndKeepsEachProvider() {
        let memory = ExternalSignInMemory(defaults: defaults)
        XCTAssertNil(memory.remembered(.apple))
        XCTAssertFalse(memory.initiallyShown(.apple), "初めては出さない形から始める")
        XCTAssertFalse(memory.initiallyShown(.google))

        memory.remember(true, for: .apple)
        memory.remember(false, for: .google)
        XCTAssertTrue(memory.initiallyShown(.apple), "前回「使える」なら最初から出す（答えを待って欄をずらさない）")
        XCTAssertFalse(memory.initiallyShown(.google))
        XCTAssertEqual(memory.remembered(.google), false, "「使えない」もはっきり覚える")
    }

    /// 確かめられなかった（圏外・サーバーの不調）は、覚えも今の形も変えない
    func testUnknownAnswerKeepsMemoryAndShape() {
        let memory = ExternalSignInMemory(defaults: defaults)
        memory.remember(true, for: .apple)
        memory.remember(nil, for: .apple)
        XCTAssertEqual(memory.remembered(.apple), true, "圏外で開いただけで、次からボタンが消えてはいけない")

        XCTAssertTrue(ExternalSignInMemory.shown(current: true, answer: nil))
        XCTAssertFalse(ExternalSignInMemory.shown(current: false, answer: nil))
        XCTAssertFalse(ExternalSignInMemory.shown(current: true, answer: false), "答えが変わったら替える")
        XCTAssertTrue(ExternalSignInMemory.shown(current: false, answer: true))
    }

    /// 動きを減らす設定では動かさずに替える
    func testChangeFollowsReduceMotion() {
        XCTAssertNil(ExternalSignInMemory.changeDuration(reduceMotion: true))
        XCTAssertEqual(ExternalSignInMemory.changeDuration(reduceMotion: false), 0.25)
    }

    /// ログアウト・退会で覚えを消す（`settleSignedOut` は両方の道が通る）
    @MainActor
    func testSignOutForgetsMemory() async {
        let memory = ExternalSignInMemory(defaults: defaults)
        memory.remember(true, for: .apple)
        memory.remember(true, for: .google)
        let auth = AuthStore()
        auth.externalSignInMemory = memory
        auth.settleSignedOut()
        XCTAssertNil(memory.remembered(.apple), "ログアウト・退会で Apple の覚えが残っている")
        XCTAssertNil(memory.remembered(.google), "ログアウト・退会で Google の覚えが残っている")
    }

    /// 404（口がまだ無い）と読めない答えは「使えない」、圏外・5xx は「分からない」
    func testAvailabilityErrorsSplitIntoNoAndUnknown() {
        XCTAssertEqual(ExternalSignInAvailability.answer(for: APIError.server(status: 404, message: "")), false)
        XCTAssertEqual(ExternalSignInAvailability.answer(for: APIError.decoding("x")), false)
        XCTAssertNil(ExternalSignInAvailability.answer(for: APIError.unreachable))
        XCTAssertNil(ExternalSignInAvailability.answer(for: APIError.server(status: 503, message: "")))
    }

    func testServiceAvailabilityReadsServer() async {
        StubProtocol.respond(path: "/auth/apple/status", status: 200, body: #"{"available":true}"#)
        let yes = await AppleSignInService(api: api()).availability()
        XCTAssertEqual(yes, true)

        StubProtocol.reset()
        StubProtocol.respond(path: "/elsewhere", status: 200, body: "{}")   // 当てはまる道が無い＝404
        let missing = await GoogleSignInService(api: api()).availability()
        XCTAssertEqual(missing, false, "口がまだ無い本番は「使えない」と覚える")

        StubProtocol.reset()
        StubProtocol.respond(path: "/auth/google/status", status: 503, body: #"{"error":"x"}"#)
        let down = await GoogleSignInService(api: api()).availability()
        XCTAssertNil(down, "サーバーの不調は前回の答えを変えない")
        let downBool = await GoogleSignInService(api: api()).isAvailable()
        XCTAssertFalse(downBool, "isAvailable は今までどおり false")
    }

    /// 画面: 最初は覚えで描く・答えで覚えを書き換える・ログアウトで消す
    func testViewDrawsFromMemory() throws {
        let view = try source("Features/Auth/SignInView.swift")
        XCTAssertTrue(view.contains("@State private var appleAvailable = ExternalSignInMemory().initiallyShown(.apple)"))
        XCTAssertTrue(view.contains("@State private var googleAvailable = ExternalSignInMemory().initiallyShown(.google)"))
        XCTAssertFalse(view.contains("@State private var appleAvailable = false"), "答えを待ってから出す形に戻っている")
        let refresh = try slice(view, from: "private func refreshExternal", to: "private func startGoogle")
        XCTAssertTrue(refresh.contains("externalMemory.remember(answer, for: provider)"))
        XCTAssertTrue(refresh.contains("ExternalSignInMemory.changeDuration(reduceMotion: reduceMotion)"),
                      "動きを減らす設定を見ていない")
        let store = try source("Core/Auth/AuthStore.swift")
        let settle = try slice(store, from: "func settleSignedOut()", to: "state = .signedOut")
        XCTAssertTrue(settle.contains("externalSignInMemory.forget()"))
    }

    /// 並び（模型 NL2x の案）: Apple → Google → 失敗の文 → メール → パスワード → 主ボタン → 切り替えの一行
    func testOrderStacksFromBottom() throws {
        let view = try source("Features/Auth/SignInView.swift")
        let section = try slice(view, from: "private var credentialsSection", to: "/// 下の切り替えの一行")
        let order = ["externalSection", "\n            messages\n", "signin.email", "signin.password", "signin.submit", "switchLine"]
        let positions = try order.map { try position(of: $0, in: section) }
        XCTAssertEqual(positions, positions.sorted(), "並びが Apple と Google → 失敗の文 → 欄 → 主ボタン → 切り替え でない")
        let stack = try slice(view, from: "private var externalSection", to: "private func refreshExternal")
        XCTAssertLessThan(try position(of: "appleButton", in: stack), try position(of: "googleButton", in: stack),
                          "Apple のボタンがいちばん上でない")
        XCTAssertTrue(view.contains(".frame(height: metrics.external)"), "Apple と Google の高さがそろっていない")
        // 上の段は見せられる高さから下の段を引いた残り（下から積む）
        XCTAssertTrue(view.contains(".frame(height: SignInLayout.headHeight(viewport: viewportHeight, form: formHeight, density: density))"))
        XCTAssertTrue(view.contains(".onGeometryChange(for: CGFloat.self) { $0.size.height } action: { formHeight = $0 }"))
        XCTAssertTrue(view.contains("if focusedField == nil { viewportHeight = height }"),
                      "キーボードが出て形が替わると、打ち始めに欄が跳ねる")
    }

    /// 枠つきの「アカウントを作る」をやめ、1行（リンクは真鍮）
    func testSwitchIsOneLineWithBrassLink() throws {
        let view = try source("Features/Auth/SignInView.swift")
        let line = try slice(view, from: "private var switchLine", to: "/// 外のアカウントの入口")
        for part in [#"L("はじめての方は", "New here?")"#, #"L("アカウントを作る", "Create an account")"#,
                     #"L("アカウントをお持ちの方は", "Have an account?")"#, "WebTheme.accent", "signin.switch",
                     "minHeight: SignInLayout.switchHeight"] {
            XCTAssertTrue(line.contains(part), "切り替えの一行に \(part) が無い")
        }
        let section = try slice(view, from: "private var credentialsSection", to: "/// 外のアカウントの入口")
        XCTAssertFalse(section.contains("jpPillButton(.outline)"), "ログインと新規登録に枠つきの切り替えが残っている")
        XCTAssertGreaterThanOrEqual(SignInLayout.switchHeight, 44)
    }

    // MARK: - 2. 失敗の文と、送らずに全部が1画面に見える

    /// 失敗の文は欄のすぐ上。出たら読み上げる。板どおり danger・13pt・丸に！の印
    func testErrorSitsRightAboveFieldsAndIsAnnounced() throws {
        let view = try source("Features/Auth/SignInView.swift")
        let messages = try slice(view, from: "private var messages", to: "/// 欄（いちばん詰めた形では")
        for part in ["WebTheme.danger", "JPFont.footnote", "exclamationmark.circle", "signin.error"] {
            XCTAssertTrue(messages.contains(part), "失敗の文に \(part) が無い")
        }
        XCTAssertFalse(view.contains("Text(error).foregroundStyle(WebTheme.danger).font(.callout)"),
                       "いちばん下に出す前の失敗の文が残っている")
        XCTAssertTrue(view.contains("UIAccessibility.post(notification: .announcement, argument: message)"),
                      "失敗の文を読み上げに伝えていない")
    }

    /// 失敗の文は欄に付けて置く: どの形でも、失敗の文の下端から打つ所まで 40pt 未満（UI テスト
    /// `testSignInFailureIsVisibleAboveFields` の上限。Mac run 1769 は並びの間 12 のままで 47.67pt）
    func testErrorHugsTheFirstField() throws {
        XCTAssertLessThanOrEqual(SignInLayout.errorGap, 4)
        for density in SignInLayout.Density.allCases {
            XCTAssertLessThan(SignInLayout.errorToFieldText(density), 40, "失敗の文が欄から離れている（\(density)）")
        }
        let view = try source("Features/Auth/SignInView.swift")
        let messages = try slice(view, from: "private var messages", to: "/// 欄（いちばん詰めた形では")
        XCTAssertTrue(messages.contains(".padding(.bottom, showsCredentials ? SignInLayout.errorGap - metrics.gap : 0)"),
                      "失敗の文が並びの間のまま欄から離れている")
    }

    /// 模型 NL2x の寸法
    func testMetricsMatchMock() {
        XCTAssertEqual(SignInLayout.metrics(.regular),
                       .init(external: 50, externalGap: 10, field: 50, primary: 52, gap: 12, tagline: true, fieldLabels: true, orLine: true))
        XCTAssertEqual(SignInLayout.metrics(.compact),
                       .init(external: 46, externalGap: 8, field: 44, primary: 48, gap: 10, tagline: false, fieldLabels: true, orLine: true))
        XCTAssertEqual(SignInLayout.metrics(.tight).gap, 8)
        XCTAssertFalse(SignInLayout.metrics(.tight).fieldLabels)
        for density in SignInLayout.Density.allCases {
            let m = SignInLayout.metrics(density)
            XCTAssertGreaterThanOrEqual(min(m.external, m.field, m.primary), 44, "押せるものが 44 未満（\(density)）")
        }
        XCTAssertEqual(SignInLayout.compactTypeLimit, .xxxLarge)
    }

    /// 375×667 で見せられる高さ（タブ: 667 − 上 20 − 見出し 44 − タブ 49 ≈ 554、シート: 見出し 56 を引いて約 581、見出しなしのタブ 598）
    private let smallViewports: [CGFloat] = [554, 581, 598]

    /// 小さい画面でも、新規登録（3つの欄、Apple と Google、お願いの一文、失敗の文まで）が送らずに1画面に収まる
    func testEverythingFitsOnSmallScreen() {
        for viewport in smallViewports {
            for signUp in [true, false] {
                for external in [0, 2] {
                    for reason in [false, true] {
                        let density = SignInLayout.density(viewport: viewport, signUp: signUp, externalCount: external,
                                                           hasReason: reason, largeText: false)
                        let need = SignInLayout.need(density, signUp: signUp, externalCount: external, hasReason: reason)
                        XCTAssertLessThanOrEqual(need, viewport,
                                                 "高さ \(viewport)・登録 \(signUp)・外 \(external)・一文 \(reason) で収まらない（\(density) \(need)）")
                    }
                }
            }
        }
        // 前の作り（帯 380 決め打ち・ロゴの始まり 250、枠つきの切り替え）では 375×667 の新規登録が収まらなかった
        XCTAssertGreaterThan(250 + SignInLayout.formNeed(.regular, signUp: true, externalCount: 2, hasReason: false), 598)
    }

    /// 大きい画面は板どおりの寸法、大きい字はいちばん詰めた形（字の上限つき）。測れる前は板どおり
    func testDensityChoice() {
        XCTAssertEqual(SignInLayout.density(viewport: 0, signUp: true, externalCount: 2, hasReason: true, largeText: false), .regular)
        XCTAssertEqual(SignInLayout.density(viewport: 760, signUp: false, externalCount: 2, hasReason: false, largeText: false), .regular)
        XCTAssertEqual(SignInLayout.density(viewport: 598, signUp: false, externalCount: 2, hasReason: false, largeText: false), .compact)
        XCTAssertEqual(SignInLayout.density(viewport: 900, signUp: true, externalCount: 2, hasReason: false, largeText: true), .tight)
    }

    /// 上の段は残りの高さ。ロゴが入る高さより低くはしない（そのときは送れる）
    func testHeadTakesTheRest() {
        XCTAssertEqual(SignInLayout.headHeight(viewport: 0, form: 400, density: .regular), 380, "測れる前は板の高さ")
        XCTAssertEqual(SignInLayout.headHeight(viewport: 700, form: 500, density: .regular), 200)
        XCTAssertEqual(SignInLayout.headHeight(viewport: 500, form: 900, density: .compact), SignInLayout.headMin(.compact))
        // 下の段が伸びた分だけ上が縮む（下から積む: 欄は動かない）
        let before = SignInLayout.headHeight(viewport: 700, form: 500, density: .regular)
        let after = SignInLayout.headHeight(viewport: 700, form: 536, density: .regular)
        XCTAssertEqual(before - after, 36)
    }
}
