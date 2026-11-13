import XCTest
@testable import JourneyPhoto

/// 写真を大きく見る画面で、**1回押すと上下の情報が消え、もう1回で戻る**（2026-11-12 owner の要望・`ViewerChrome`）
final class ViewerChromeTests: XCTestCase {

    /// 1回押すと隠れ、もう1回で戻る
    func testSingleTapTogglesChrome() {
        var chrome = ViewerChrome()
        XCTAssertTrue(chrome.shows(voiceOver: false), "開いたときから隠れている")
        chrome.singleTap(voiceOver: false)
        XCTAssertFalse(chrome.shows(voiceOver: false), "1回押しても隠れない")
        chrome.singleTap(voiceOver: false)
        XCTAssertTrue(chrome.shows(voiceOver: false), "もう1回押しても戻らない")
    }

    /// VoiceOver 中は隠さない（題・撮影情報が読め、✕ で閉じられる）。途中で点けたら、隠していた分も出す
    func testVoiceOverAlwaysShowsChrome() {
        var chrome = ViewerChrome()
        chrome.singleTap(voiceOver: true)
        XCTAssertTrue(chrome.shows(voiceOver: true))
        XCTAssertFalse(chrome.isHidden, "VoiceOver 中の1回押しで隠す状態に入った")

        var hidden = ViewerChrome()
        hidden.singleTap(voiceOver: false)
        XCTAssertTrue(hidden.shows(voiceOver: true), "隠したあと VoiceOver を点けても出ない")
    }

    /// 短くふわっと。「視差効果を減らす」がオンなら寄りを無くす（濃さだけ）
    func testMotionIsShortAndReducible() {
        XCTAssertLessThanOrEqual(ViewerChrome.fadeDuration, 0.25)
        XCTAssertGreaterThan(ViewerChrome.fadeDuration, 0)
        XCTAssertGreaterThan(ViewerChrome.slide(reduceMotion: false), 0)
        XCTAssertEqual(ViewerChrome.slide(reduceMotion: true), 0)
    }

    // MARK: - 画面がこの決まりを使っているか

    /// 🔴 1回押しは2回押し（いいね・拡大を戻す）の**後ろ**に付ける。前に付けると、2回押しの1回目で
    /// 隠れてしまう（SwiftUI は先に付けた身振りを先に見る）
    func testSingleTapIsAttachedAfterDoubleTap() throws {
        let viewer = try source("Features/PhotoDetail/PhotoViewerView.swift")
        guard let double = viewer.range(of: ".onTapGesture(count: 2) { handleDoubleTap(photo, at: offset) }"),
              let single = viewer.range(of: ".onTapGesture { toggleChrome() }") else {
            return XCTFail("写真に1回押し・2回押しが付いていない")
        }
        XCTAssertLessThan(double.lowerBound, single.lowerBound, "1回押しが2回押しより前に付いている")
        XCTAssertTrue(viewer.contains("chrome.singleTap(voiceOver: voiceOver)"))
    }

    /// 上の列（✕・「1 / N」・共有）と下の重ね（帯・題・撮影地・撮影情報・ハート）の**両方**を隠す
    func testBothTopAndBottomFollowTheRule() throws {
        let viewer = try source("Features/PhotoDetail/PhotoViewerView.swift")
        XCTAssertTrue(viewer.contains("topBar\n                .modifier(ChromeVisibility(shown: showsChrome, edge: .top"),
                      "上の列が隠れない")
        XCTAssertTrue(viewer.contains("caption\n            }\n            .padding(.bottom, 24)\n            .frame(maxWidth: .infinity)\n            .modifier(ChromeVisibility(shown: showsChrome, edge: .bottom"),
                      "下の帯・題・ハートが隠れない")
        XCTAssertTrue(viewer.contains("private var showsChrome: Bool { chrome.shows(voiceOver: voiceOver) }"))
        // 隠している間は押せない・読み上げない（下の写真に1回押しが届き、もう一度出せる）
        XCTAssertTrue(viewer.contains(".allowsHitTesting(shown)"))
        XCTAssertTrue(viewer.contains(".accessibilityHidden(!shown)"))
        // 「視差効果を減らす」を見る
        XCTAssertTrue(viewer.contains("ViewerChrome.slide(reduceMotion: reduceMotion)"))
    }

    /// 隠したまま左右に送っても隠したまま（送りで戻すのは倍率だけ）。VoiceOver の「戻る」で閉じられる
    func testPagingKeepsChromeHiddenAndEscapeCloses() throws {
        let viewer = try source("Features/PhotoDetail/PhotoViewerView.swift")
        XCTAssertTrue(viewer.contains(".onChange(of: index) { _, _ in resetZoom() }"), "送りで倍率以外も戻している")
        let reset = member("private func resetZoom()", in: viewer)
        XCTAssertFalse(reset.contains("chrome"), "倍率を戻すときに隠す・出すも戻している")
        XCTAssertTrue(viewer.contains(".accessibilityAction(.escape) { dismiss() }"))
    }

    /// 🔴 UI テストは下の情報を**題・撮影情報の段（`viewer.caption`）**で見る。サムネイルの帯は2枚以上の投稿だけなので、
    /// 帯を必ず待つと1枚の写真で落ちる（run 1182: 開いた「夢の中」は送りの頁 1 で、帯が無く「サムネイルの帯 が出ない」で赤）
    func testUITestWatchesCaptionNotOnlyStrip() throws {
        let viewer = try source("Features/PhotoDetail/PhotoViewerView.swift")
        XCTAssertTrue(member("private var thumbnailStrip", in: viewer).contains("if photos.count > 1 {"),
                      "サムネイルの帯が1枚の写真でも出る作りに変わった（この試験の前提を見直す）")
        XCTAssertTrue(member("private var caption", in: viewer).contains(".accessibilityIdentifier(\"viewer.caption\")"),
                      "下の情報に UI テストの目印が無い")
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ui = try String(contentsOf: root.appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"),
                            encoding: .utf8)
        let test = member("func testViewerTapHidesChrome()", in: ui)
        XCTAssertFalse(test.contains("expect(strip.waitForExistence"), "1枚の写真でもサムネイルの帯を待っている")
        XCTAssertTrue(test.contains("caption.waitForExistence"), "下の情報を題・撮影情報の段で見ていない")
        // 消えたかは目印の値で見る。run 1193: 1回押した後の絵では ✕ と下の情報が消えていたのに、UI テストの木には
        // `viewer.close`・`viewer.caption` が在るまま（`exists` が真）だった。在る・無いで見ると、正しく消えても落ちる
        XCTAssertTrue(test.contains("waitChrome(\"hidden\", \"1-tap\")"), "1回押して消えたかを目印の値で見ていない")
        XCTAssertFalse(test.contains("caption.waitForNonExistence"), "隠した後も木に在る下の情報の有る無しで見ている")
        XCTAssertTrue(viewer.contains(".accessibilityValue(showsChrome ? \"shown\" : \"hidden\")"), "上下の情報の状態の目印が無い")
    }

    // MARK: - 下ごしらえ

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `head` で始まる宣言の中身（次の `{` から閉じる `}` まで）
    private func member(_ head: String, in text: String) -> String {
        guard let start = text.range(of: head) else { return "" }
        var depth = 0
        var began = false
        var out = ""
        for ch in text[start.lowerBound...] {
            out.append(ch)
            if ch == "{" { depth += 1; began = true }
            if ch == "}" { depth -= 1; if began && depth == 0 { break } }
        }
        return out
    }
}
