import XCTest
@testable import JourneyPhoto

/// Pro の案内に旅のトランクの利点を足した（2026-10-18 判断）。並び・トランクから開いたときの並び・
/// 中身の数（サーバーの決まりと同じ）・言ってはいけない言葉・トランクの口が「トランクから」と渡していることを見張る
final class PaywallTrunkBenefitTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    // MARK: - 並び

    /// ふだんの並び: トランクは特別な乗車券の次（いちばん下）。5つ
    func testDefaultOrderPutsTrunkAfterPassTicket() {
        XCTAssertEqual(ProBenefit.all.map(\.icon), [.light, .offline, .chapter, .card, .trunk])
        XCTAssertEqual(ProBenefit.ordered(for: .general), ProBenefit.all)
    }

    /// トランクから開いたとき: トランクがいちばん上、残りはふだんの順のまま
    func testTrunkOriginPutsTrunkFirst() {
        let order = ProBenefit.ordered(for: .trunk).map(\.icon)
        XCTAssertEqual(order, [.trunk, .light, .offline, .chapter, .card])
        XCTAssertEqual(Set(order), Set(ProBenefit.all.map(\.icon)), "並べ替えで利点が増えた・減った")
        XCTAssertEqual(PaywallOrigin.trunk.leadingBenefit, .trunk)
        XCTAssertNil(PaywallOrigin.general.leadingBenefit)
    }

    /// 案内の画面は開いた口に合わせた並びを使う（`ProBenefit.all` を直に回さない）
    func testPaywallViewUsesOrigin() throws {
        let view = try source("Features/Pro/PaywallView.swift")
        XCTAssertTrue(view.contains("ForEach(ProBenefit.ordered(for: origin))"))
        XCTAssertTrue(view.contains("var origin: PaywallOrigin = .general"))
        XCTAssertTrue(view.contains("paywall.benefit."), "利点に UI テストの目印が無い")
    }

    /// 旅のトランクの Pro の口（作り直す・特別なトランク・手持ちの上限・届いたラベル）は「トランクから」と渡す
    func testTrunkEntrancesPassTrunkOrigin() throws {
        for file in ["TrunkView", "LabelArrivedView", "TrunkPocketView", "TrunkModelsView"] {
            let text = try source("Features/Trunk/\(file).swift")
            XCTAssertTrue(text.contains("PaywallView(origin: .trunk)"), "\(file) がトランクからと渡していない")
            XCTAssertFalse(text.contains("PaywallView()"), "\(file) にふだんの並びの案内が残っている")
        }
    }

    // MARK: - 中身

    /// 数はサーバーの決まり（`PRO_MODELS` 6・`REROLLS_PER_MONTH` 3・`POCKET_LIMIT_PRO` 150・`POCKET_LIMIT_FREE` 30）
    func testTrunkBenefitStatesServerNumbers() {
        let trunk = ProBenefit.trunk
        XCTAssertEqual(trunk.icon, .trunk)
        XCTAssertEqual(trunk.title, "旅のトランクをもっと")
        XCTAssertEqual(trunk.body, "特別なトランク 6 型。ラベルの図柄を月 3 回作り直せて、手持ちは 150 枚まで（無料は 30 枚）")
        XCTAssertEqual(TrunkModel.pro.count, 6)
        XCTAssertEqual(ProBenefit.trunkRerollsPerMonth, 3)
        XCTAssertEqual(TrunkState.proLimit, 150)
        XCTAssertEqual(TrunkState.freeLimit, 30)
    }

    /// 言ってはいけない言葉（トランクの説明の決まり）: 「捨てる」「必ず」「確定」。硬貨（買えない・Pro でも増えない）にも触れない。
    /// 日本語は値で、英語は書いた文（`static var trunk` の中）で見る
    func testNoForbiddenWords() throws {
        for benefit in ProBenefit.all {
            for word in ["捨て", "必ず", "確定", "硬貨", "カプセル"] {
                XCTAssertFalse(benefit.title.contains(word) || benefit.body.contains(word), "「\(word)」: \(benefit.title)")
            }
        }
        let view = try source("Features/Pro/PaywallView.swift")
        let start = try XCTUnwrap(view.range(of: "static var trunk: ProBenefit {"))
        let end = try XCTUnwrap(view.range(of: "static let trunkRerollsPerMonth"))
        let block = view[start.upperBound..<end.lowerBound].lowercased()
        for word in ["捨て", "必ず", "確定", "硬貨", "guarantee", "always", "discard", "throw away", "coin", "capsule"] {
            XCTAssertFalse(block.contains(word), "トランクの利点に「\(word)」")
        }
    }

    /// 線の絵（トランク）がある。ほかの絵と同じ作り（24 の升目・線だけ・角 2.5 の胴）
    /// （Linux の模型の `Path` は描かないので、書いた文で見る）
    func testTrunkIconDraws() throws {
        XCTAssertTrue(ProIcon.allCases.contains(.trunk))
        let icons = try source("Features/Pro/ProIcons.swift")
        let start = try XCTUnwrap(icons.range(of: "case .trunk:"))
        let block = icons[start.upperBound...]
        XCTAssertTrue(block.contains("addRoundedRect(in: CGRect(x: 3 * k, y: 7.5 * k"), "トランクの胴が無い")
        XCTAssertFalse(icons.contains(".fill("), "線の絵に塗りがある")
    }
}
