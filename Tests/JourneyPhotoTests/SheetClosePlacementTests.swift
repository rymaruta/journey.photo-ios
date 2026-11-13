import XCTest

/// シートの「閉じる」は左上のシートの「閉じる」（`SheetCloseButton`）にそろえる（2026-11-13 owner 承認・#187）。
///
/// 前は画面ごとにばらばらだった: 右上のガラスの「閉じる」（行きたい場所を探す・元の写真を選ぶ・ストーリーに ほか）・
/// 左上の ×（名前の横）・右上の ×（意見を送る・通報・投稿する・構図）・真鍮や白の字だけの「閉じる」
/// （行った県の札・硬貨のお礼・トランクの札）。右上は「保存」「投稿する」など**決める操作だけ**にする。
/// 画面は Linux で描けないので、書いてあるもので固定する（`NoDiscardWordingTests` と同じ作り）
final class SheetClosePlacementTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func allSources() throws -> [(name: String, text: String)] {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        return try files.map { ($0.path.replacingOccurrences(of: root.path + "/", with: ""),
                                try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// `text` の中で `parts` がこの順に出ること
    private func assertInOrder(_ parts: [String], in text: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        var from = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: from..<text.endIndex) else {
                return XCTFail("\(what): 「\(part)」が順に出てこない（\(parts)）", file: file, line: line)
            }
            from = found.upperBound
        }
    }

    /// `index` の後の最初の `{` から、対応する `}` までの中身（置き場の中身）
    private static func braceBody(_ text: String, after index: String.Index) -> String {
        guard let open = text[index...].firstIndex(of: "{") else { return "" }
        var depth = 0
        var i = open
        while i < text.endIndex {
            if text[i] == "{" { depth += 1 }
            if text[i] == "}" {
                depth -= 1
                if depth == 0 { return String(text[text.index(after: open)..<i]) }
            }
            i = text.index(after: i)
        }
        return String(text[open...])
    }

    // MARK: - 右上（決める操作の場所）に閉じるを置かない

    /// 右上の置き場（`topBarTrailing`・`confirmationAction`・`primaryAction`・`navigationBarTrailing`）の
    /// 中身に、閉じる系（`SheetCloseButton`・「閉じる」の字・× の印の閉じる）が無いこと
    func testNoCloseInTrailingToolbarSlots() throws {
        let slot = #"ToolbarItem(Group)?\(placement: \.(topBarTrailing|confirmationAction|primaryAction|navigationBarTrailing)\)"#
        let closeLike = ["SheetCloseButton", "Labels.Common.close", "L(\"閉じる\"", "VisitedMapText.close",
                         "TrunkTagText.close", "systemName: \"xmark\""]
        var bad: [String] = []
        for (name, text) in try allSources() {
            var search = text.startIndex..<text.endIndex
            while let found = text.range(of: slot, options: .regularExpression, range: search) {
                let body = Self.braceBody(text, after: found.upperBound)
                if closeLike.contains(where: { body.contains($0) }) {
                    let line = text[..<found.lowerBound].components(separatedBy: "\n").count
                    bad.append("\(name):\(line)")
                }
                search = found.upperBound..<text.endIndex
            }
        }
        XCTAssertEqual(bad, [], "右上（決める操作の場所）に「閉じる」がある。閉じるは左上の `SheetCloseButton`（cancellationAction）へ")
    }

    // MARK: - 洗い出した所が左上の SheetCloseButton になっていること

    /// 上のバーに置く所（`cancellationAction` の `SheetCloseButton`）
    func testToolbarSheetsUseLeadingSheetClose() throws {
        let files = [
            "Features/Messages/DMTripViews.swift",          // 旅行プランの下書き・旅行プランに入れる
            "Features/Trips/TripDayMapView.swift",          // n 日目の地図
            "Features/Trips/TripLegViews.swift",            // 区間のシート（2か所）
            "Features/Trips/TripCreateView.swift",          // 旅行プランを作る
            "Features/Trips/TripAddSheet.swift",            // 旅行プランに入れる
            "Features/Trips/SpotSwipeView.swift",           // 行きたい場所を探す
            "Features/Stories/StoryRepliesSheet.swift",     // ストーリーの返信
            "Features/Upload/InspiredPickerView.swift",     // 元の写真を選ぶ
            "Features/Common/TravelStorySheet.swift",       // ストーリーに
            "Features/Common/SignatureShareCardSheet.swift",// SNSに共有
            "Features/Map/NearbyPhotosSheet.swift",         // 近くの写真
            "Features/Profile/NameSideBadgeView.swift",     // 名前の横（前は左上の ×）
            "Features/Trips/LibraryTripFlowView.swift",     // 写真の旅（前は左上の ×）
        ]
        for path in files {
            let text = try source(path)
            XCTAssertNotNil(text.range(of: #"ToolbarItem\(placement: \.cancellationAction\) \{\s*SheetCloseButton\(\)"#,
                                       options: .regularExpression),
                            "\(path): 左上（cancellationAction）の `SheetCloseButton` が無い")
            XCTAssertFalse(text.contains(".accessibilityLabel(Labels.Common.close)"),
                           "\(path): × の印の閉じるが残っている")
        }
        // 区間のシートは2つの姿（狭い・広い）の両方
        let legs = try source("Features/Trips/TripLegViews.swift")
        XCTAssertEqual(legs.components(separatedBy: "ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }").count - 1, 2)
    }

    /// 上のバーが無いシート: 見出しの行の**左端**に `SheetCloseButton(onContent: true)`（題や Spacer より前）
    func testContentHeaderSheetsPutCloseFirst() throws {
        let cases: [(path: String, order: [String])] = [
            ("Features/Settings/FeedbackSheet.swift",        // 意見を送る（前は右上の ×）
             ["SheetCloseButton(onContent: true)", ".disabled(isSending)", "L(\"意見を送る\"", "Spacer(minLength: 0)"]),
            ("Features/Social/ReportSheet.swift",            // 通報（前は右上の ×）
             ["SheetCloseButton(onContent: true)", ".disabled(isWorking)", "L(\"書かれた字を通報\"", "Spacer(minLength: 0)"]),
            ("Features/Upload/PostSheet.swift",              // 投稿する（前は右の × の丸）
             ["SheetCloseButton(onContent: true)", "L(\"投稿する\", \"Create\")", "Spacer(minLength: 0)"]),
            ("Features/Spots/CompositionPicker.swift",       // 構図（前は右の × の丸）
             ["SheetCloseButton(onContent: true)", "\"composition.close\"", "L(\"構図\"", "Spacer(minLength: 0)"]),
            ("Features/Profile/VisitedPrefectureCard.swift", // 行った県の札（前は右の真鍮の字）
             ["SheetCloseButton(onContent: true, action: onClose)", "\"visitedMap.card.close\"",
              "Text(prefecture)", "Spacer(minLength: 0)"]),
            ("Features/Trunk/TrunkWelcomeView.swift",        // はじめての硬貨・硬貨のお礼（前は右上の白の字）
             ["SheetCloseButton(onContent: true)", "\"\\(copy.id).close\"", "Spacer()"]),
            ("Features/Trunk/LabelArrivedView.swift",        // ラベルが届いた（投稿のお礼）
             ["SheetCloseButton(onContent: true)", "\"trunk.arrived.close\"", "Spacer()"]),
            ("Features/Trunk/TrunkGachaView.swift",          // カプセルを開けた
             ["SheetCloseButton(onContent: true)", "\"trunk.gachaOpen.close\"", "Spacer()"]),
            ("Features/Trunk/TrunkRerollView.swift",         // 図柄を作り直す
             ["SheetCloseButton(onContent: true)", "\"trunk.reroll.close\"", "Spacer()"]),
            ("Features/Trunk/TrunkPartsBoxView.swift",       // 部品のシート
             ["SheetCloseButton(onContent: true)", "\"trunk.partSheet.close\"", "TrunkGachaText.eyebrow(part)", "Spacer()"]),
            ("Features/Drafts/DraftsView.swift",             // 下書きについて
             ["SheetCloseButton(onContent: true)", "DraftsText.aboutTitle", "Spacer(minLength: 0)"]),
            ("Features/Stories/StoryInsightsView.swift",     // ストーリーの反応（前は見出しの行の右端）
             ["SheetCloseButton(onContent: true)", "header", "private var header: some View"]),
        ]
        for (path, order) in cases {
            let text = try source(path)
            assertInOrder(order, in: text, path)
            // 前の閉じる（右の字・× の印）を残さない
            XCTAssertFalse(text.contains("Text(Labels.Common.close)"), "\(path): 字だけの「閉じる」が残っている")
            XCTAssertFalse(text.contains("Text(VisitedMapText.close)"), "\(path): 字だけの「閉じる」が残っている")
            XCTAssertFalse(text.contains(".accessibilityLabel(Labels.Common.close)"), "\(path): × の印の閉じるが残っている")
        }
    }

    // MARK: - UI テストが押す識別子を変えない

    /// UI テスト（`ScreenshotTests`）が押す・大きさを測る識別子が、`SheetCloseButton` に付いたまま残っていること
    func testCloseIdentifiersKept() throws {
        let kept: [(path: String, id: String)] = [
            ("Features/Upload/InspiredPickerView.swift", "inspiredPicker.close"),
            ("Features/Common/TravelStorySheet.swift", "travelStory.close"),
            ("Features/Map/NearbyPhotosSheet.swift", "nearby.close"),
            ("Features/Profile/VisitedPrefectureCard.swift", "visitedMap.card.close"),
            ("Features/Spots/CompositionPicker.swift", "composition.close"),
            ("Features/Trunk/TrunkWelcomeView.swift", "\\(copy.id).close"),
            ("Features/Trunk/LabelArrivedView.swift", "trunk.arrived.close"),
            ("Features/Trunk/TrunkGachaView.swift", "trunk.gachaOpen.close"),
            ("Features/Trunk/TrunkRerollView.swift", "trunk.reroll.close"),
            ("Features/Trunk/TrunkPartsBoxView.swift", "trunk.partSheet.close"),
        ]
        for (path, id) in kept {
            let text = try source(path)
            let pattern = #"SheetCloseButton\([^)]*\)\s*\.accessibilityIdentifier\(""#
                + NSRegularExpression.escapedPattern(for: id) + #""\)"#
            XCTAssertNotNil(text.range(of: pattern, options: .regularExpression),
                            "\(path): 「\(id)」が `SheetCloseButton` に付いていない（UI テストが押せなくなる）")
        }
    }

    /// 部品: 字は「閉じる」、当たりは 44pt。バーの外はガラス（板の「ガラス」= `jpGlass`）
    func testSheetCloseButtonShape() throws {
        let text = try source("Features/Common/SheetCloseButton.swift")
        XCTAssertEqual(text.components(separatedBy: "Text(Labels.Common.close)").count - 1, 2, "バーの中と外で字が違う")
        XCTAssertEqual(text.components(separatedBy: ".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)").count - 1, 2,
                       "当たりが 44pt でない形がある")
        XCTAssertTrue(text.contains(".jpGlass(in: Capsule())"), "バーの外の「閉じる」がガラスでない")
    }
}
