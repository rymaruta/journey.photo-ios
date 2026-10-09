import XCTest
@testable import JourneyPhoto

/// メダルを回す全画面で、右上の × が画面の外へ押し出されて戻れなかった（2026-10-09 owner の実機の絵:
/// 初期ユーザーのメダルで × が無く、中身が右へずれ、説明の1行が右端で切れていた）。
///
/// 初期ユーザーの後光（硬貨の 1.3 倍）は**どの機種でも画面の幅を超える**。それが組みの大きさに効くと、
/// 組みが画面より広くなって × が外へ出る。後光は硬貨の背景に置き、組みは画面の大きさに固定する
final class MedalViewerLayoutTests: XCTestCase {

    /// iPhone の縦の幅（SE〜Pro Max・iPad の分割表示の狭い幅も含めて）
    private let widths: [Double] = [320, 375, 390, 393, 402, 414, 428, 430, 440]

    func testCoinFitsTheScreenWidth() {
        for width in widths {
            let coin = MedalTextureLayout.coinSide(screenWidth: width)
            XCTAssertLessThanOrEqual(coin, width - 40, "幅 \(width): 硬貨が左右 20pt の余白を割る")
        }
    }

    /// 後光は画面より広い。**だから組みの大きさに効かせてはいけない**（下の見張り）
    func testHaloIsWiderThanTheScreen() {
        for width in [375.0, 393, 430] {
            let coin = MedalTextureLayout.coinSide(screenWidth: width)
            XCTAssertGreaterThan(MedalTextureLayout.haloSide(coin: coin), width)
        }
    }

    func testHaloAndCloseButtonDoNotWidenTheLayout() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Profile/MedalViewerView.swift"), encoding: .utf8)
        // 組みは画面の大きさに固定し、× は画面いっぱいの枠の右上に重ねる
        XCTAssertTrue(source.contains(".frame(width: geo.size.width, height: geo.size.height)"))
        XCTAssertTrue(source.contains(".overlay(alignment: .topTrailing) { closeButton }"))
        XCTAssertFalse(source.contains("ZStack(alignment: .topTrailing)"), "× を中身と並べて組まない")
        // 後光は硬貨の背景（組みの大きさに効かない）
        let background = try XCTUnwrap(source.range(of: ".background {\n            if badge.key == \"earlyUser\""))
        let halo = try XCTUnwrap(source.range(of: "MedalTextureLayout.haloSide(coin: coin)"))
        XCTAssertLessThan(background.lowerBound, halo.lowerBound)
    }
}
