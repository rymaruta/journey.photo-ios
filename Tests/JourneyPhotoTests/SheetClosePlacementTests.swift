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

    /// 上のバーの無いシートの**見出しの行（中身の `HStack`）の右端**にも「閉じる」を置かない
    /// （2026-11-13 確かめ役の指摘・#187。上のバーだけ見ていて、とおまわり号の図鑑・家具の寄りの右端の真鍮の字が漏れた）。
    /// `HStack` の直下の最後の `Spacer(` より後ろ（＝右端へ押した所）に、字の「閉じる」があれば落とす。
    /// × の印は見ない——案内を消す ×・返信をやめる ×・画面いっぱいの写真の × など、シートを閉じる以外にも使う
    func testNoCloseAtTrailingEndOfContentHeaderRows() throws {
        let closeWords = ["SheetCloseButton", "Text(L(\"閉じる\"", "Text(Labels.Common.close)", "Button(L(\"閉じる\"",
                          "Button(Labels.Common.close", "Text(VisitedMapText.close)", "Text(TrunkTagText.close)"]
        var bad: [String] = []
        for (name, text) in try allSources() {
            var search = text.startIndex..<text.endIndex
            while let found = text.range(of: #"\bHStack\b"#, options: .regularExpression, range: search) {
                search = found.upperBound..<text.endIndex
                let body = Self.braceBody(text, after: found.upperBound)
                // 直下（入れ子の `{}` の外）の最後の Spacer(
                var depth = 0
                var lastSpacer: String.Index?
                var i = body.startIndex
                while i < body.endIndex {
                    switch body[i] {
                    case "{": depth += 1
                    case "}": depth -= 1
                    default:
                        if depth == 0, body[i...].hasPrefix("Spacer(") { lastSpacer = i }
                    }
                    i = body.index(after: i)
                }
                guard let lastSpacer else { continue }
                let trailing = body[lastSpacer...]
                if closeWords.contains(where: { trailing.contains($0) }) {
                    bad.append("\(name):\(text[..<found.lowerBound].components(separatedBy: "\n").count)")
                }
            }
        }
        XCTAssertEqual(bad, [], "見出しの行の右端に「閉じる」がある。閉じるは行の左端の `SheetCloseButton(onContent: true)` へ")
    }

    /// 見出しの行（`HStack`）の「閉じる」を字だけで手描きしない（2026-11-13 確かめ役の指摘・#187。接写の一覧は左端だったが
    /// 真鍮の字だけで、ほかのシートの「閉じる」（ガラス・当たり 44pt）と形が違った）。見出しの行の閉じるは部品だけ。
    /// 札の下の縁取りのボタン（行った県の祝いの「閉じる」など）は見出しの行ではないので見ない
    func testNoHandDrawnCloseInHeaderRows() throws {
        let handDrawn = ["Text(L(\"閉じる\"", "Text(Labels.Common.close)", "Text(VisitedMapText.close)", "Text(TrunkTagText.close)"]
        var bad: [String] = []
        for (name, text) in try allSources() where name != "Features/Common/SheetCloseButton.swift" {
            var search = text.startIndex..<text.endIndex
            while let found = text.range(of: #"\bHStack\b"#, options: .regularExpression, range: search) {
                search = found.upperBound..<text.endIndex
                let body = Self.braceBody(text, after: found.upperBound)
                if let word = handDrawn.first(where: { body.contains($0) }) {
                    bad.append("\(name):\(text[..<found.lowerBound].components(separatedBy: "\n").count) \(word)")
                }
            }
        }
        XCTAssertEqual(bad, [], "見出しの行に字だけの「閉じる」がある。`SheetCloseButton(onContent: true)` を使う")
    }

    /// とおまわり号の図鑑・家具の寄り・接写の一覧（2026-11-13 確かめ役の指摘・#187）: 見出しの行の左端に部品、識別子は残す
    /// （UI テスト `ScreenshotTests` が押して 44pt を測る）
    func testCamperRoomSheetsPutCloseFirst() throws {
        let dex = try source("Features/Camper/Room/CamperRoomDexView.swift")
        assertInOrder(["private var header: some View", "HStack(alignment: .top) {",
                       "SheetCloseButton(onContent: true, action: onClose)", ".accessibilityIdentifier(\"camper.room.dex.close\")",
                       "L(\"家具を集める\"", "Spacer(minLength: 0)"], in: dex, "図鑑")
        assertInOrder(["struct CamperRoomCloseUpView", "HStack {", "SheetCloseButton(onContent: true, action: onClose)",
                       ".accessibilityIdentifier(\"camper.room.closeup.close\")", "furniture.category.name",
                       "Spacer(minLength: 0)"], in: dex, "家具の寄り")
        let contact = try source("Features/Camper/Room/CamperRoomContactSheet.swift")
        assertInOrder(["HStack(spacing: 4) {", "SheetCloseButton(onContent: true, action: onClose)",
                       ".accessibilityIdentifier(\"camper.room.contact.close\")", "Spacer()",
                       "\"camper.room.contact\""], in: contact, "接写の一覧")
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
            ("Features/Stories/StoryInsightsView.swift",     // ストーリーの反応（前は見出しの行の右端→見出しの上の別の行）
             ["private var header: some View", "HStack(alignment: .top", "SheetCloseButton(onContent: true)",
              "StoryPoster(story: story)", "Spacer(minLength: 0)"]),
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

    /// 系統の字のボタンで置いていた左上の「閉じる」も部品にそろえる（2026-11-13 確かめ役の指摘・#187）。
    /// 閉じ方は前のまま（`action` に前の閉じ方をそのまま渡す）。識別子も残す
    func testToolbarCloseUsesSheetCloseButton() throws {
        let cases: [(path: String, closes: [String], ids: [String])] = [
            ("App/RootView.swift", ["SheetCloseButton(action: { showMessages = false })",
                                    "SheetCloseButton(action: { showNotifications = false })"],
             ["messages.close", "notifications.close"]),
            ("Features/Albums/InviteView.swift", ["SheetCloseButton(action: { dismiss() })"], []),
            ("Features/Auth/SignInPrompt.swift", ["SheetCloseButton(action: { dismiss() })"], []),
            ("Features/Stories/StoryComposerView.swift", ["SheetCloseButton(action: { dismiss() })"], []),
        ]
        for (path, closes, ids) in cases {
            let text = try source(path)
            XCTAssertFalse(text.contains("Button(Labels.Common.close)"), "\(path): 系統の字のボタンの「閉じる」が残っている")
            for close in closes {
                XCTAssertNotNil(text.range(of: #"ToolbarItem\(placement: \.cancellationAction\) \{\s*"#
                                           + NSRegularExpression.escapedPattern(for: close), options: .regularExpression),
                                "\(path): 左上に「\(close)」が無い")
            }
            for id in ids {
                XCTAssertNotNil(text.range(of: #"SheetCloseButton\([^\n]*\)\s*\.accessibilityIdentifier\(""#
                                           + NSRegularExpression.escapedPattern(for: id) + #""\)"#, options: .regularExpression),
                                "\(path): 「\(id)」が `SheetCloseButton` に付いていない")
            }
        }
        // ストーリーを作る画面はログインの確かめの段とログインの段の2か所
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertEqual(composer.components(separatedBy: "SheetCloseButton(action: { dismiss() })").count - 1, 2)
    }

    /// ハイライトの表紙を選ぶシート: 表紙は押した時点で決まる（`coverId = id`）ので、右上の「完了」はただ閉じるだけだった。
    /// 左上の `SheetCloseButton` にする（2026-11-13・#187）
    func testHighlightCoverPickerClosesFromLeading() throws {
        let text = try source("Features/Profile/HighlightEditorView.swift")
        guard let start = text.range(of: "private var coverPicker: some View") else { return XCTFail("表紙を選ぶシートが無い") }
        let picker = String(text[start.upperBound...].prefix(4000))
        assertInOrder(["coverId = id", "ToolbarItem(placement: .cancellationAction) {", "SheetCloseButton()",
                       ".accessibilityIdentifier(\"highlightEditor.coverDone\")"], in: picker, "表紙を選ぶシート")
        XCTAssertFalse(picker.contains("L(\"完了\", \"Done\")"), "右上の「完了」（閉じるだけ）が残っている")
        // 下へ払って閉じても選んだ表紙が戻らない（閉じるだけで決まる作りの前提）
        XCTAssertTrue(text.contains(".sheet(isPresented: $showCoverPicker) { coverPicker }"))
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
