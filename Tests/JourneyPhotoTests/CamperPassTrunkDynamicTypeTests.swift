import XCTest
@testable import JourneyPhoto

/// 🔴 **キャンピングカー・すれちがい（乗車券）・サポーター証・トランクの画面の字は Dynamic Type に付いてくる**
/// （2026-10-21・`StoryDynamicTypeTests` と同じ見方）。
///
/// 以前は `.system(size: 12)` のような固定の大きさで、文字を大きくしている人にも小さいままだった。
/// `JPFont` の段（`.caption`・`.footnote`・`.bodyEmphasis`…）か、標準に無い大きさ（14）は `jpSystemFont` に替えた。
/// 横に並べた札・ボタンは、アクセシビリティの大きさで縦に積む（`ViewThatFits`・`dynamicTypeSize`）。
///
/// 画面は Linux で描けないので、**ソースに固定の大きさの字が戻っていないこと**を見る。
///
/// 固定のままでよいもの:
/// - **記号**（`Image(systemName:)`）: 44pt の丸・決まった幅の枠に入れた印（閉じる・戻る・選んだ印など）
/// - **物に刷った字**（下の `allowed`）: トランクの刻印・縫い付けの札・硬貨の口の COIN・券面の見本の「PRO」の札
/// - **対象のファイルに入れていないもの**: きっぷの表と裏（`PassCards`・`PassFaces`・`PassBacks`。
///   `PassCardStyle` の字組の注記: 札は寸法の決まった物で、中身は読み上げで読める）と、トランクの絵
///   （`TrunkBoxView`・`TrunkFaceView`・`TrunkLabelView`・`TrunkPartView`）、3D の場面の中の字
final class CamperPassTrunkDynamicTypeTests: XCTestCase {

    /// 物に刷った字（行の中身の一部で当てる）
    private static let allowed: [String: [String]] = [
        // カプセルの機械の硬貨の口・硬貨の刻印（紙や金属に刷った字・読み上げから外している）
        "Trunk/TrunkGachaView.swift": [".font(.system(size: 7, weight: .bold))", ".font(.system(size: g.letterSize, weight: .bold))"],
        // ふたの裏の「ほか N」（64pt の丸の中）と縫い付けの札（22pt の革の札）
        "Trunk/TrunkInsideView.swift": [".font(.system(size: 12, weight: .semibold).monospacedDigit())",
                                        ".font(.system(size: 11, weight: .semibold).monospacedDigit())"],
        // 券面の見本の角の「PRO」の札（見本の絵の上に重ねる小さな札。読み上げは「Pro で選べます」）
        "Pass/PassCardPickView.swift": ["Text(\"PRO\").font(.system(size: 11, weight: .semibold))"],
    ]

    private static let files = [
        "Camper/CamperGarageView.swift",
        "Camper/CamperVisitView.swift",
        "Pass/PassBookView.swift",
        "Pass/PassCardMenu.swift",
        "Pass/PassCardPickView.swift",
        "Pass/PassHomeSlot.swift",
        "Pass/PassSettingsView.swift",
        "Pass/PassSpinCard.swift",
        "Pass/PassViewerView.swift",
        "Pro/SupporterCardView.swift",
        "Trunk/LabelArrivedView.swift",
        "Trunk/TheirTrunkView.swift",
        "Trunk/TrunkGachaView.swift",
        "Trunk/TrunkInsideView.swift",
        "Trunk/TrunkModelsView.swift",
        "Trunk/TrunkOpenView.swift",
        "Trunk/TrunkParts.swift",
        "Trunk/TrunkPartsBoxView.swift",
        "Trunk/TrunkPocketView.swift",
        "Trunk/TrunkRerollView.swift",
        "Trunk/TrunkSpinViewer.swift",
        "Trunk/TrunkStickView.swift",
        "Trunk/TrunkView.swift",
        "Trunk/TrunkWelcomeView.swift",
    ]

    private static var features: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features")
    }

    func testScreensDoNotUseFixedTextSizes() throws {
        for file in Self.files {
            let source = try String(contentsOf: Self.features.appendingPathComponent(file), encoding: .utf8)
            let lines = source.components(separatedBy: "\n")
            let fixed = lines.enumerated().filter { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // 注記（`//`）の中は数えない
                guard !trimmed.hasPrefix("//"), line.contains(".system(size:") else { return false }
                if (Self.allowed[file] ?? []).contains(where: { line.contains($0) }) { return false }
                // 記号: 同じ行か、すぐ上の行が `Image(systemName:`
                let previous = index > 0 ? lines[index - 1] : ""
                return !(line.contains("Image(systemName:") || previous.contains("Image(systemName:"))
            }
            XCTAssertTrue(fixed.isEmpty,
                          "\(file) に固定の大きさの字が残っている: "
                          + fixed.map { "\($0.offset + 1)行" }.joined(separator: ", "))
        }
    }

    /// 部品（`marker` で始まるメンバー）の本体だけを切り出す。字下げ 4 の閉じ括弧（`\n    }\n`）まで
    private static func member(_ marker: String, in source: String) -> String? {
        guard let start = source.range(of: marker) else { return nil }
        let rest = source[start.lowerBound...]
        guard let end = rest.range(of: "\n    }\n") else { return String(rest) }
        return String(rest[..<end.upperBound])
    }

    /// 横に並べた札・ボタンは、アクセシビリティの大きさで縦に積む。**その部品の中で**、横並びと縦積みの両方があり、
    /// 切り替えの条件があることを見る（HStack だけに戻すと落ちる）
    func testRowsStackAtAccessibilitySizes() throws {
        let expectations: [(file: String, member: String, needles: [String])] = [
            ("Camper/CamperGarageView.swift", "private var statsRow: some View {",
             ["typeSize.isAccessibilitySize", "VStack(spacing: 8) { statTiles }", "HStack(spacing: 8) { statTiles }"]),
            ("Camper/CamperGarageView.swift", "private var stagesRow: some View {",
             ["typeSize.isAccessibilitySize", "VStack(spacing: 8) { stageButtons }", "HStack(spacing: 8) { stageButtons }"]),
            ("Camper/CamperGarageView.swift", "private var partsGrid: some View {",
             ["count: typeSize.isAccessibilitySize ? 2 : 3"]),
            ("Camper/CamperVisitView.swift", "private func tiles(_ state: CamperVisitState) -> some View {",
             ["typeSize.isAccessibilitySize", "VStack(spacing: 10) { tileItems(state) }"]),
            ("Camper/CamperVisitView.swift", "private var actions: some View {",
             ["typeSize.isAccessibilitySize", "VStack(spacing: 8) { actionButtons }"]),
            ("Trunk/TrunkPocketView.swift", "private func actionBar(_ state: TrunkState) -> some View {",
             ["ViewThatFits(in: .horizontal)", "HStack(spacing: 8) { actionButtons(state, selected: selected) }",
              "VStack(spacing: 8) { actionButtons(state, selected: selected) }"]),
            ("Trunk/TrunkPocketView.swift", "private func header(_ state: TrunkState) -> some View {",
             ["ViewThatFits(in: .horizontal)", "VStack(alignment: .leading, spacing: 4) {"]),
            ("Trunk/LabelArrivedView.swift", "private var chips: some View {",
             ["typeSize.isAccessibilitySize", "VStack(alignment: .leading, spacing: 8) { chipItems }",
              "HStack(spacing: 8) { chipItems }"]),
            ("Trunk/TrunkSpinViewer.swift", "private var viewButtons: some View {",
             ["count: typeSize.isAccessibilitySize ? 2 : 4"]),
            // 既定の大きさは 96 ちょうど（下限だけにすると既定でも札が縦に伸びる・Mac run 639）
            ("Trunk/TrunkRerollView.swift", "private func candidate(",
             ["maxHeight: typeSize.isAccessibilitySize ? nil : 96", "vertical: typeSize.isAccessibilitySize"]),
            ("Trunk/TrunkView.swift", "private func statCell(", ["lineLimit(typeSize.isAccessibilitySize ? 3 : 1)"]),
            ("Trunk/TrunkParts.swift", "struct TrunkButtonFace: View {", ["lineLimit(typeSize.isAccessibilitySize ? 3 : 1)"]),
            ("Pass/PassViewerView.swift", "private func actions(_ content: PassCardContent) -> some View {",
             ["ViewThatFits(in: .horizontal)", "VStack(spacing: JPSpace.xs) { actionButtons(content, thanked: thanked) }"]),
            ("Pass/PassSpinCard.swift", "struct PassSpinCard: View {", ["ViewThatFits(in: .horizontal)", "flipButton"]),
            ("Pro/SupporterCardView.swift", "private func yearsSection(width: Double) -> some View {",
             ["ViewThatFits(in: .horizontal)", "monthCount(month)"]),
        ]
        for (file, marker, needles) in expectations {
            let source = try String(contentsOf: Self.features.appendingPathComponent(file), encoding: .utf8)
            guard let body = Self.member(marker, in: source) else {
                XCTFail("\(file) に \(marker) が無い")
                continue
            }
            for needle in needles {
                XCTAssertTrue(body.contains(needle), "\(file) の \(marker) に大きい字の並びの切り替え（\(needle)）が無い")
            }
        }
    }

    /// トランクのボタンの字（既定 15・17）は、いちばん近い文字の種類で出る（固定の大きさに戻さない）
    func testTrunkButtonSizesMapToTextStyles() {
        XCTAssertEqual(JPFont.numberStyle(size: 15, relativeTo: .body), .subheadline)
        XCTAssertEqual(JPFont.numberStyle(size: 17, relativeTo: .body), .body)
    }

    /// 送らない束の画面の上限は、読める大きさまで（小さく止めすぎない）・ボタンを押し出さない大きさ
    func testPassViewerTypeLimit() {
        XCTAssertGreaterThanOrEqual(PassViewerView.typeLimit, .xxLarge)
        XCTAssertLessThan(PassViewerView.typeLimit, .accessibility1)
    }
}
