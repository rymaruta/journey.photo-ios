import XCTest

/// 計測のための単体の試しを、**名指しした回だけ**走らせる門（CLAUDE.md「計測は名指しした回だけ」）。
///
/// 2026-11-20（札 #652・run 1602）: Xcode 27 のシミュレーターで端末の AI が使えるようになり、`OnDeviceAIProbeTests`
/// （10組を端末の AI に通す試し）が 138秒かかって1本の上限 60秒を超え、ふだんの単体テストの回を止めた（run 1600 では 16.7秒）。
///
/// 名指しは次のどちらか:
/// - `inputs[screens]` に名前を書く（`Tools/xcode-test.sh` が `TEST_RUNNER_JP_SCREENS` にして渡し、テストでは `JP_SCREENS`）
/// - 環境変数 `JP_MEASURE=<名前>`（手元で流すとき。`all` で全部）
enum MeasureGate {

    static func isNamed(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        let key = name.lowercased()
        if let measure = environment["JP_MEASURE"]?.lowercased(), measure == "all" || measure.contains(key) { return true }
        guard let screens = environment["JP_SCREENS"], !screens.isEmpty else { return false }
        return screens.split(whereSeparator: { $0 == "," || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .contains { !$0.isEmpty && key.contains($0) }
    }

    static func skipReason(_ name: String) -> String {
        "計測のための試しなので、名指しした回だけ走る（inputs[screens]=\(name) か JP_MEASURE=\(name)）"
    }
}

/// 門の決まりと、計測の試しが門を通っていること（門を外すと、ふだんの回でも走ってしまう）
final class MeasureGateTests: XCTestCase {

    func testOnlyNamedRunsMeasure() {
        let name = "OnDeviceAIProbeTests"
        XCTAssertFalse(MeasureGate.isNamed(name, environment: [:]), "ふだんの回で走る")
        XCTAssertFalse(MeasureGate.isNamed(name, environment: ["JP_SCREENS": ""]))
        XCTAssertFalse(MeasureGate.isNamed(name, environment: ["JP_SCREENS": "testSearchAsk, testCapturesSearchAsk"]))
        XCTAssertFalse(MeasureGate.isNamed(name, environment: ["JP_SCREENS": "all"]), "全部の回でも計測は走らせない")
        XCTAssertTrue(MeasureGate.isNamed(name, environment: ["JP_SCREENS": "testSearchAsk, OnDeviceAIProbeTests"]))
        XCTAssertTrue(MeasureGate.isNamed(name, environment: ["JP_SCREENS": "OnDeviceAIProbe"]))
        XCTAssertTrue(MeasureGate.isNamed(name, environment: ["JP_MEASURE": "OnDeviceAIProbeTests"]))
        XCTAssertTrue(MeasureGate.isNamed(name, environment: ["JP_MEASURE": "all"]))
    }

    func testProbeAndScriptGoThroughTheGate() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let probe = try String(contentsOf: root.appendingPathComponent("Tests/JourneyPhotoTests/OnDeviceAIProbeTests.swift"), encoding: .utf8)
        let body = try XCTUnwrap(probe.range(of: "func testJapaneseQualityOfOnDeviceSuggestions()"))
        let head = probe[body.upperBound...].prefix(400)
        XCTAssertTrue(head.contains("guard MeasureGate.isNamed(Self.measureName) else"), "計測の試しが門を通っていない（ふだんの回でも走る）")
        XCTAssertTrue(head.contains("throw XCTSkip("))
        XCTAssertFalse(probe[body.upperBound...].prefix(120).contains("let status"), "門より先に端末の AI を見ている")
        let script = try String(contentsOf: root.appendingPathComponent("Tools/xcode-test.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("export TEST_RUNNER_JP_SCREENS=\"${SCREENS:-}\""), "名指しがテストに届かない")
        let workflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/ios-testflight.yml"), encoding: .utf8)
        XCTAssertTrue(workflow.contains("SCREENS: ${{ inputs.screens }}\n        run: bash Tools/xcode-test.sh unit"))
    }
}
