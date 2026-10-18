import XCTest
@testable import JourneyPhoto

/// 硬貨の形（`TrunkCoinGeometry`・2026-10-18）。前は真鍮の放射の塗りの丸だけで、大きく描くと金色の玉に見えた。
/// 平たい円盤（縁の段・一段下がった面・浮き彫りの内輪・COIN の刻印）と、倒したときの楕円と厚みを見張る
final class TrunkCoinGeometryTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 正面の硬貨: 真円・厚みなし。縁は直径の 11%、内輪はその内側にもう一段
    func testFrontCoinIsAFlatDiscWithARim() {
        let g = TrunkCoinGeometry(size: 116)
        XCTAssertEqual(g.squash, 1, accuracy: 0.0001, "正面なのに潰れている")
        XCTAssertEqual(g.edgeDepth, 0, accuracy: 0.0001, "正面なのに厚みの帯が見える")
        XCTAssertEqual(g.rimWidth, 116 * 0.11, accuracy: 0.0001)
        XCTAssertGreaterThan(g.ringInset, g.rimWidth, "内輪が縁の上に重なっている（段が無い）")
        XCTAssertLessThan(g.ringInset, g.size * 0.3, "内輪が真ん中に寄りすぎて刻印とぶつかる")
        XCTAssertTrue(g.showsLetters)
        XCTAssertEqual(g.letterSize, 116 * 0.17, accuracy: 0.0001)
        XCTAssertEqual(g.drawnHeight, 116, accuracy: 0.0001)
    }

    /// 倒した硬貨: 楕円（cos）になり、下に厚みの帯（直径の 8% × sin）
    func testTiltedCoinBecomesAnEllipseWithThickness() {
        let g = TrunkCoinGeometry(size: 88, tilt: 60)
        XCTAssertEqual(g.squash, 0.5, accuracy: 0.0001)
        XCTAssertEqual(g.edgeDepth, 88 * 0.08 * sin(60 * Double.pi / 180), accuracy: 0.0001)
        XCTAssertEqual(g.drawnHeight, 44 + g.edgeDepth, accuracy: 0.0001)
        // 倒しすぎない（真横の線にしない）・負の角度は正面に
        XCTAssertGreaterThan(TrunkCoinGeometry(size: 88, tilt: 120).squash, 0.15)
        XCTAssertEqual(TrunkCoinGeometry(size: 88, tilt: -10).squash, 1, accuracy: 0.0001)
    }

    /// 小さな印（行の字の横の 14〜26pt）も同じ形（縁・面・内輪）。字だけは読めない大きさで描かない
    func testSmallMarksKeepTheSameShape() {
        for size in [14.0, 16, 26] {
            let g = TrunkCoinGeometry(size: size)
            XCTAssertGreaterThanOrEqual(g.rimWidth, 1.5, "\(size)pt の縁が細すぎて見えない")
            XCTAssertGreaterThan(g.ringInset, g.rimWidth, "\(size)pt に段が無い")
            XCTAssertLessThan(g.ringInset * 2, size, "\(size)pt の内輪がつぶれる")
        }
        XCTAssertFalse(TrunkCoinGeometry(size: 16).showsLetters)
        XCTAssertTrue(TrunkCoinGeometry(size: 26).showsLetters)
        XCTAssertEqual(TrunkCoinGeometry(size: 14).shadowRadius, 0, "行の字と並ぶ小さな印に影を落とす")
    }

    /// 案内の真ん中の3枚: 奥の2枚は倒した楕円で小さく、手前の1枚は正面で大きい（手前が最後＝上に描かれる）
    func testWelcomeStageStacksTiltedCoinsBehindAFrontCoin() {
        let coins = TrunkWelcomeText.stageCoins
        XCTAssertEqual(coins.count, 3)
        let front = coins[coins.count - 1]
        XCTAssertEqual(front.tilt, 0, "手前の1枚が正面でない")
        for back in coins.dropLast() {
            let g = TrunkCoinGeometry(size: back.size, tilt: back.tilt)
            XCTAssertGreaterThan(g.squash, 0.3, "奥の硬貨が倒れすぎて線に見える")
            XCTAssertLessThan(g.squash, 0.7, "奥の硬貨が倒れていない（奥行きが出ない）")
            XCTAssertLessThan(back.size, front.size, "奥の硬貨が手前より大きい")
            XCTAssertNotEqual(back.rotation, 0, "奥の硬貨が傾いていない")
            XCTAssertGreaterThan(back.y, front.y, "奥の硬貨が手前の上に浮いている")
        }
        XCTAssertLessThan(coins[0].x, 0)
        XCTAssertGreaterThan(coins[1].x, 0)
    }

    /// どの画面の硬貨もこの部品1つ。昔の放射の塗りの丸（玉に見える）を残さない
    func testEveryScreenDrawsTheSameCoin() throws {
        let gacha = try source("Features/Trunk/TrunkGachaView.swift")
        XCTAssertTrue(gacha.contains("TrunkCoinGeometry(size: size, tilt: tilt)"))
        XCTAssertTrue(gacha.contains(".padding(g.rimWidth)"), "縁の段が無い")
        XCTAssertTrue(gacha.contains(".padding(g.ringInset)"), "浮き彫りの内輪が無い")
        XCTAssertTrue(gacha.contains("Text(verbatim: \"COIN\")\n                    .font(.system(size: g.letterSize, weight: .bold))"), "刻印が無い")
        XCTAssertFalse(gacha.contains("center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.7"),
                       "玉に見える前の塗りが残っている")
        XCTAssertTrue(gacha.contains("TrunkCoinMark(size: 26)"), "カプセルの機械の数の行が同じ部品でない")
        let welcome = try source("Features/Trunk/TrunkWelcomeView.swift")
        XCTAssertTrue(welcome.contains("TrunkCoinMark(size: coin.size, tilt: coin.tilt, turn: coin.turn)"))
        XCTAssertTrue(welcome.contains("TrunkCoinMark(size: 26)"), "「硬貨 +10 枚」の左の印が同じ部品でない")
    }
}
