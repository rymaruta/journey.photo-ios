import XCTest
import Photos
@testable import JourneyPhoto

/// 🔴 **App Store の審査の差し戻し（2026-11-25・1.1.119 (1)・札 #604）への直しを守る。**
///
/// - 1.2（利用者の投稿）: 登録・ログインの前の同意の画面に「不適切な投稿といやがらせは一切許さない」と、何に同意するかを出す
/// - 5.1.1(iv)（許可の前の説明）: 自前の説明に「許可」の字のボタンと「あとで」を置かない。説明のあとは必ず iOS の確認へ
/// - 5.2.5（WeatherKit）: 天気を出す所に Apple Weather の印と法的な出典のリンクを出す
///
/// 画面は Linux で描けないので、言葉と決まりは値で、画面のつなぎはソースで見る（消したら落ちるのが目的）
@MainActor
final class AppReviewFixesTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 注記（`//`）を除いたソース
    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - 1.2 規約への同意

    func testLegalGateSaysZeroTolerance() {
        XCTAssertTrue(LegalGateText.zeroTolerance.contains("一切許しません"))
        XCTAssertTrue(LegalGateText.zeroTolerance.contains("不適切な投稿"))
        XCTAssertTrue(LegalGateText.zeroTolerance.contains("いやがらせ"))
        XCTAssertTrue(LegalGateText.zeroTolerance.contains("削除"))
        XCTAssertTrue(LegalGateText.zeroTolerance.contains("利用を止めます"))
        XCTAssertTrue(LegalGateText.agree.contains("利用規約に同意"))
        XCTAssertTrue(LegalGateText.agreeNote.contains("ログインや登録の前"))
        // 中黒で区切らない（CLAUDE.md）
        for text in [LegalGateText.zeroTolerance, LegalGateText.howToReport, LegalGateText.agree, LegalGateText.agreeNote] {
            XCTAssertFalse(text.contains("・") || text.contains("·"), text)
        }
    }

    func testLegalGateWiresTheWords() throws {
        let view = try source("Features/Legal/LegalGateView.swift")
        XCTAssertTrue(view.contains("Text(LegalGateText.zeroTolerance)"), "同意の画面に「一切許さない」が出ていない")
        XCTAssertTrue(view.contains("Text(LegalGateText.agree)"), "同意のボタンが何に同意するかを言っていない")
        XCTAssertTrue(view.contains("Text(LegalGateText.agreeNote)"))
        XCTAssertTrue(view.contains(".accessibilityIdentifier(\"legal.agree\")"))
        // 英語の版もそろえる（審査は英語で読む）
        let english = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Legal/LegalGateView.swift"),
                                 encoding: .utf8)
        XCTAssertTrue(english.contains("zero tolerance for objectionable content and abusive users"))
        XCTAssertTrue(english.contains("Terms of Use (EULA)"))
    }

    /// 規約の中身を変えたので版を上げた（前の版に同意した人にもう一度出る）。Web の `LEGAL_CONSENT_VERSION` と同じ数
    func testConsentVersionWasRaised() {
        XCTAssertGreaterThanOrEqual(LegalConsent.currentVersion, 2)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(1, forKey: "legal.consent.version")
        XCTAssertTrue(LegalConsent(defaults: defaults).needsConsent, "前の版に同意した人に、新しい規約の同意が出ない")
    }

    /// 同意の画面は、タブ（ログインの入口）より先に出る
    func testGateComesBeforeTabs() throws {
        let rootView = try source("App/RootView.swift")
        guard let gate = rootView.range(of: "} else if consent.needsConsent {"),
              let tabs = rootView.range(of: "tabsWithFoundingGift\n") else { return XCTFail("同意の分かれ道が無い") }
        XCTAssertLessThan(gate.lowerBound, tabs.lowerBound)
    }

    // MARK: - 5.1.1(iv) 許可の前の説明

    func testPhotoAccessIsAskedOnAppear() {
        XCTAssertTrue(PhotoAccessAsk.asksOnAppear(.notDetermined))
        XCTAssertFalse(PhotoAccessAsk.asksOnAppear(.denied))
        XCTAssertFalse(PhotoAccessAsk.asksOnAppear(.authorized))
        XCTAssertFalse(PhotoAccessAsk.asksOnAppear(.limited))
    }

    /// 自前の説明の画面に「許可」の字のボタンも、先送りの「あとで」「今はしない」も置かない
    func testPrimersHaveNoAllowOrLaterButtons() throws {
        let primers = ["Features/Trips/LibraryTripFlowView.swift", "Features/Trips/DeviceTripShelf.swift",
                       "Features/Settings/PushPrimerView.swift"]
        let forbidden = ["L(\"あとで\"", "L(\"今はしない\"", "L(\"写真へのアクセスを許可\"", "L(\"許可する\"",
                         "L(\"オンにする\"", "\"Not now\")", "onLater"]
        for path in primers {
            let text = try source(path)
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "\(path) に \(word) が残っている（審査 5.1.1(iv)）")
            }
        }
    }

    func testLibraryTripFlowAsksTheSystemDirectly() throws {
        let flow = try source("Features/Trips/LibraryTripFlowView.swift")
        XCTAssertTrue(flow.contains("if PhotoAccessAsk.asksOnAppear(model.status) { await model.requestAccess() }"),
                      "「旅の写真から」が開いたときに iOS の確認を出していない")
        XCTAssertTrue(flow.contains("L(\"設定を開く\", \"Open Settings\")"), "断られた人を設定のアプリへ案内していない")
    }

    func testPushPrimerOnlyContinues() throws {
        XCTAssertEqual(PushPrimerText.proceed, "続ける")
        let view = try source("Features/Settings/PushPrimerView.swift")
        XCTAssertTrue(view.contains("Text(PushPrimerText.proceed)"))
        XCTAssertTrue(view.contains("await push.enable()"), "「続ける」が iOS の確認へ進まない")
        XCTAssertTrue(view.contains(".sheetSwipeGuard(.hold)"), "通知の説明を下に引いて閉じられる")
        XCTAssertFalse(view.contains("Button { dismiss() }"), "通知の説明に閉じるだけのボタンが残っている")
    }

    func testDeviceTripCardOnlyContinues() throws {
        let card = try source("Features/Trips/DeviceTripShelf.swift")
        XCTAssertTrue(card.contains("Text(L(\"続ける\", \"Continue\"))"))
        XCTAssertFalse(card.contains("store.dismissIntro()"), "端末の写真の札に先送りの道が残っている")
    }

    // MARK: - 5.2.5 WeatherKit の出典

    func testAttributionDecodesTheDarkMark() throws {
        let json = #"{"logoDark@3x":"/assets/branding/ja/Apple_Weather_wht_ja_3X_090122.png","logoDark@2x":"/assets/branding/ja/Apple_Weather_wht_ja_2X_090122.png","logoLight@3x":"/assets/branding/ja/Apple_Weather_blk_ja_3X_090122.png","serviceName":"Apple Weather"}"#
        let marks = try XCTUnwrap(WeatherAttribution.decode(Data(json.utf8)))
        XCTAssertEqual(marks.serviceName, "Apple Weather")
        XCTAssertEqual(marks.darkMark.absoluteString,
                       "https://weatherkit.apple.com/assets/branding/ja/Apple_Weather_wht_ja_3X_090122.png")
        XCTAssertEqual(WeatherAttributionMarks.markHeight, 14)
    }

    func testAttributionRejectsOtherHostsAndBrokenAnswers() {
        XCTAssertNil(WeatherAttribution.decode(Data(#"{"logoDark@3x":"https://example.com/x.png"}"#.utf8)))
        XCTAssertNil(WeatherAttribution.decode(Data(#"{"logoDark@3x":"http://weatherkit.apple.com/x.png"}"#.utf8)))
        XCTAssertNil(WeatherAttribution.decode(Data("not json".utf8)))
        XCTAssertNil(WeatherAttribution.decode(Data(#"{"serviceName":"Apple Weather"}"#.utf8)))
    }

    func testAttributionEndpointAndTextMark() {
        XCTAssertEqual(WeatherAttribution.endpoint(language: "ja").absoluteString, "https://weatherkit.apple.com/attribution/ja")
        XCTAssertEqual(WeatherAttribution.language(preferred: "ja"), "ja")
        XCTAssertEqual(WeatherAttribution.language(preferred: "fr"), "en")
        // 2026-11-26（審査 5.2.5）: 字の印に Apple のロゴの字（U+F8FF）を使わない
        XCTAssertFalse(WeatherAttribution.textMark.contains("\u{F8FF}"), "字の印に Apple のロゴの字が残っている")
        XCTAssertEqual(WeatherAttribution.textMark, "Apple Weather")
    }

    /// 一覧の頭に印と法的な出典を出す（下の注記の後ろだけにしない）
    func testForecastShowsMarkAndLegalLinkAtTheTop() throws {
        let view = try source("Features/Pro/LightForecastView.swift")
        guard let row = view.range(of: "attributionRow(forecast)\n"),
              let cards = view.range(of: "ForEach(LightForecastText.cards(forecast, now: loadedAt))") else {
            return XCTFail("天気の出典の行が一覧に無い")
        }
        XCTAssertLessThan(row.lowerBound, cards.lowerBound, "天気の出典が札より後ろにある")
        XCTAssertTrue(view.contains("Link(destination: forecast.attribution.legalURL)"))
        XCTAssertTrue(view.contains(".accessibilityIdentifier(\"lightForecast.appleWeather\")"))
        XCTAssertTrue(view.contains("weatherMarks = await WeatherAttribution.load()"))
        XCTAssertEqual(LightForecastText.legalLink, "天気データの法的な出典")
    }
}
