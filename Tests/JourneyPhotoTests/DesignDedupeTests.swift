import XCTest
@testable import JourneyPhoto

/// **v2 の重複を土台1つに寄せたものが、画面に戻ってこないことの見張り**（2026-10-14）。
///
/// デザイン v2 を7人の担当が並行で作り、同じ形の部品が画面ごとに書かれていた
/// （節の見出し・札の地・灰の面・線の小ボタン）。見た目を変えずに土台へ寄せたので、
/// `Features/` を読んで「同じ形を直に書いた所」が増えていないかを見る。
final class DesignDedupeTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
    }

    /// 注記（`//`）の行を除いたソース
    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: sourceRoot.appendingPathComponent(path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `Features/` の全ファイル（相対パス → 注記を除いた中身）
    private func featureSources() throws -> [(path: String, text: String)] {
        let features = sourceRoot.appendingPathComponent("Features")
        guard let walker = FileManager.default.enumerator(at: features, includingPropertiesForKeys: nil) else {
            XCTFail("Features が読めない")
            return []
        }
        var out: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let rel = "Features/" + url.path.replacingOccurrences(of: features.path + "/", with: "")
            out.append((rel, try source(rel)))
        }
        XCTAssertGreaterThan(out.count, 50, "Features のファイルを見つけられていない")
        return out.sorted { $0.0 < $1.0 }
    }

    private func matches(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            XCTFail("正規表現が壊れている: \(pattern)")
            return 0
        }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    // MARK: - 札の地

    /// 「地＋白 8% の縁＋角 16」を `Features/` に直に書かない（`.jpCardFace()` を使う）
    func testNoHandWrittenCardFaceInFeatures() throws {
        let face = #"\.background\([^\n]*in: RoundedRectangle\(cornerRadius: (JPRadius\.l|16)\)\)\s*"#
            + #"\.overlay\(RoundedRectangle\(cornerRadius: (JPRadius\.l|16)\)\s*"#
            + #"\.strokeBorder\((WebTheme\.hairline|Color\.white\.opacity\(0\.08\))"#
        for (path, text) in try featureSources() {
            XCTAssertEqual(matches(face, in: text), 0, "\(path) が札の地を直に書いている（.jpCardFace() を使う）")
            XCTAssertEqual(matches(#"cornerRadius: 16\)\s*\.strokeBorder\(Color\.white\.opacity\(0\.08\)"#, in: text), 0,
                           "\(path) が角 16・白 8% の縁を数で書いている")
        }
    }

    /// 札の地は1か所（`JPCard` もそこを通る）。寄せた札が土台を使っている
    func testCardFaceIsShared() throws {
        let parts = try source("Core/Design/FormParts.swift")
        XCTAssertTrue(parts.contains(".background(fill ?? WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.l))"))
        XCTAssertTrue(parts.contains(".overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))"))
        XCTAssertEqual(parts.components(separatedBy: "strokeBorder(WebTheme.hairline").count - 1, 1,
                       "FormParts に札の縁が2つある（JPCard は jpCardFace を通す）")
        let uses: [String: String] = [
            "Features/Trips/TripPlansView.swift": ".jpCardFace()",
            "Features/Trips/OfflineTripCard.swift": ".jpCardFace()",
            "Features/Gallery/DailyThemeCard.swift": ".jpCardFace()",
            "Features/Gallery/HomeTopCardView.swift": ".jpCardFace()",
            "Features/Profile/BadgeShelfView.swift": ".jpCardFace()",
            "Features/Trips/TripPlanDetailView.swift": ".jpCardFace()",
            "Features/Spots/SpotDetailParts.swift": ".jpCardFace()",
            "Features/Profile/NameSideBadgeView.swift": ".jpCardFace(fill: WebTheme.background)",
            "Features/Trips/TripBookView.swift": ".jpCardFace(fill: Self.cellColor)",
            "Features/Profile/SavedSpotsMapView.swift": ".jpCardFace(fill: WebTheme.surface)",
            "Features/Trips/TripPickerDraftView.swift": ".jpCardFace(fill: WebTheme.surface)",
        ]
        for (path, call) in uses {
            XCTAssertTrue(try source(path).contains(call), "\(path) が共通の札の地（\(call)）を使っていない")
        }
    }

    // MARK: - 節の見出し

    /// 眉と題の間は板 Components 05 の 6。見出しはその値を通る
    func testSectionHeadingGapIsTheBoardValue() throws {
        XCTAssertEqual(JPSectionHeadingLayout.eyebrowGap, 6)
        let heading = try source("Features/Common/SectionHeading.swift")
        XCTAssertTrue(heading.contains("VStack(alignment: .leading, spacing: JPSectionHeadingLayout.eyebrowGap)"))
    }

    /// 「眉（JPEyebrowLine）→ 明朝 22 の題」を `JPSectionHeading` の外で組まない
    func testNoHandWrittenSectionHeadingInFeatures() throws {
        // 眉の直後（5 行以内）に明朝 22 の題
        let pattern = #"JPEyebrowLine\([^\n]*(\n[^\n]*){0,5}\.font\(JPFont\.cardTitle\)"#
        for (path, text) in try featureSources() where path != "Features/Common/SectionHeading.swift" {
            XCTAssertEqual(matches(pattern, in: text), 0, "\(path) が節の見出しを直に組んでいる（JPSectionHeading を使う）")
        }
        let spot = try source("Features/Spots/SpotDetailParts.swift")
        XCTAssertTrue(spot.contains("JPSectionHeading(eyebrow: eyebrow, spoken: spoken, title: title, titleLineLimit: nil)"))
        let book = try source("Features/Trips/TripBookView.swift")
        XCTAssertTrue(book.contains("JPSectionHeading(eyebrow: \"DAY"))
    }

    // MARK: - 灰の面

    /// 面の段は暗い → 明るいの順で、値は v2 の板のまま
    func testSurfaceStepsKeepTheirValues() {
        XCTAssertEqual(BrandPalette.surface3, 0x1A1A1C)
        XCTAssertEqual(BrandPalette.surface4, 0x1C1C1E)
        XCTAssertEqual(BrandPalette.surface5, 0x1E1E20)
        XCTAssertEqual(BrandPalette.surface6, 0x28282A)
        XCTAssertEqual(BrandPalette.surface7, 0x2A2A2C)
        XCTAssertEqual(BrandPalette.surface8, 0x2C2C2E)
        let lum = BrandPalette.surfaceSteps.map(BrandPalette.luminance)
        XCTAssertEqual(lum, lum.sorted(), "面の段が明るさの順に並んでいない")
        XCTAssertEqual(Set(BrandPalette.surfaceSteps).count, BrandPalette.surfaceSteps.count, "同じ値の段が2つある")
        // 寄せた先が土台の値を読む
        XCTAssertEqual(RaisedTile.hex, BrandPalette.surface3)
        XCTAssertEqual(JPLoadingState.boneGray, BrandPalette.surface4)
        XCTAssertEqual(StoryViewerMetrics.replyFieldFocusedFill, BrandPalette.surface4)
        XCTAssertEqual(StoryViewerMetrics.confirmFill, BrandPalette.surface6)
    }

    func testThemeExposesSurfaceSteps() throws {
        let theme = try source("Core/Design/WebTheme.swift")
        for n in 3...8 {
            XCTAssertTrue(theme.contains("static let surface\(n) = rgb(BrandPalette.surface\(n))"), "WebTheme.surface\(n) が無い")
        }
    }

    /// 面の段の灰を `Features/` に数で書かない（`WebTheme.surfaceN` から読む）
    func testNoHandWrittenSurfaceGraysInFeatures() throws {
        let hexLiteral = #"0x(1A1A1C|1C1C1E|1E1E20|28282A|2A2A2C|2C2C2E)\b"#
        let rgbLiteral = #"Color\(red: 0x(1A|1C|1E|28|2A|2C) / 255(\.0)?, green: 0x(1A|1C|1E|28|2A|2C) / 255(\.0)?, blue: 0x(1C|1E|20|2A|2C|2E) / 255"#
        for (path, text) in try featureSources() {
            XCTAssertEqual(matches(hexLiteral, in: text), 0, "\(path) が面の段の灰を数で書いている")
            XCTAssertEqual(matches(rgbLiteral, in: text), 0, "\(path) が面の段の灰を Color(red:) で書いている")
        }
        let story = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(story.contains("sheetColor = WebTheme.surface5"))
        XCTAssertTrue(story.contains("confirmFill = WebTheme.surface6.opacity("))
        XCTAssertTrue(story.contains("replyFocusedFill = WebTheme.surface4.opacity("))
        let upload = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains(".background(WebTheme.surface7, in: Circle())"))
        XCTAssertTrue(upload.contains("segmentSelectedFill = WebTheme.surface8"))
    }

    // MARK: - 線の小ボタン

    /// 線の小ボタンの値（板 Components 01: 44 と 36・白 14%・危険は 40%）
    func testOutlineButtonMetrics() {
        XCTAssertEqual(JPOutlineSize.regular.height, 44)
        XCTAssertEqual(JPOutlineSize.inline.height, 36)
        XCTAssertEqual(JPOutlineSize.regular.tapSlack, 0)
        XCTAssertEqual(JPOutlineSize.inline.tapSlack, 4, "見た目 36 の当たりが 44 にならない")
        XCTAssertEqual(JPOutlineTone.dangerLineOpacity, 0.4)
        XCTAssertEqual(JPOutlineTone.strongFillOpacity, 0.16)
        XCTAssertEqual(JPOutlineTone.strongLineOpacity, 0.5)
    }

    /// 3つの線のボタンが同じ面（`jpCapsuleFace`）を通る
    func testOutlineButtonsShareOneFace() throws {
        let parts = try source("Core/Design/FormParts.swift")
        XCTAssertEqual(parts.components(separatedBy: "Capsule().strokeBorder(").count - 1, 1,
                       "丸いボタンの縁が FormParts に2つある（jpCapsuleFace を通す）")
        XCTAssertEqual(parts.components(separatedBy: ".jpCapsuleFace(").count - 1, 2,
                       "jpPillButton と jpOutlineButton が同じ面を通っていない")
        XCTAssertTrue(try source("Features/Trips/TripParts.swift").contains(".jpOutlineButton(.regular, tone:"))
        XCTAssertTrue(try source("Features/Profile/ProfileV2Parts.swift").contains(".jpOutlineButton(.inline)"))
    }

    /// 白 14% の線のカプセルを画面に直に書いた所を増やさない。
    /// いま残っている5つは値が板の線のボタンと違う（内側 12・18・20、高さ 32、字の白 95% など）ので
    /// 見た目を変えずには寄せられなかった（2026-10-14）。**この一覧は減らすだけ**
    func testHandWrittenOutlineCapsulesOnlyShrink() throws {
        let known: Set<String> = [
            "Features/Profile/BadgeShelfView.swift",
            "Features/Settings/BlockedUsersView.swift",
            "Features/Trips/OfflineTripView.swift",
            "Features/Common/ErrorBanner.swift",
            "Features/Albums/AlbumsView.swift",
        ]
        for (path, text) in try featureSources() {
            let count = matches(#"Capsule\(\)\.strokeBorder\((WebTheme\.line|Color\.white\.opacity\(0\.14\))"#, in: text)
            if known.contains(path) {
                XCTAssertLessThanOrEqual(count, 1, "\(path) の線のカプセルが増えている")
            } else {
                XCTAssertEqual(count, 0, "\(path) が線の小ボタンを直に書いている（jpOutlineButton を使う）")
            }
        }
    }
}
