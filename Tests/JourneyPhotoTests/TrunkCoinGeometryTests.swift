import XCTest
@testable import JourneyPhoto

/// 羅針盤の硬貨（`TrunkCoinGeometry`・札 #716・2026-11-23 owner 採用）。
/// 前の真鍮の円盤は 16pt 以下で真鍮の丸になり、未読の点や件数バッジと紛れた。大きさの段ごとに描く量と、
/// 倒したときの楕円と厚み、重ねた硬貨、0枚の影絵を見張る
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

    /// 🔴 大きさの段: 14〜23 は縁、黒い面、太い星、点だけ。24〜31 でギザ、明暗の星、留め、内輪、北の印。32〜 で縁の目盛り 24 本
    func testTiersAddDetailWithSize() {
        for size in [14.0, 16, 20, 23.9] {
            let g = TrunkCoinGeometry(size: size)
            XCTAssertEqual(g.tier, .small, "\(size)pt")
            XCTAssertNotNil(g.flatStar, "\(size)pt に太い星が無い（真鍮の丸に戻る）")
            XCTAssertTrue(g.arms.isEmpty)
            XCTAssertEqual(g.knurlCount, 0, "\(size)pt にギザを描くと潰れる")
            XCTAssertFalse(g.showsInnerRing)
            XCTAssertFalse(g.showsNorthMark)
            XCTAssertEqual(g.tickCount, 0)
            XCTAssertEqual(g.outlineWidth, 3, "小さい硬貨の縁の暗い線を太くしていない")
            XCTAssertEqual(g.hubRadius, 0)
            XCTAssertGreaterThan(g.pinRadius, 0, "真ん中の黒い点が無い")
        }
        for size in [24.0, 26, 31.9] {
            let g = TrunkCoinGeometry(size: size)
            XCTAssertEqual(g.tier, .medium, "\(size)pt")
            XCTAssertNil(g.flatStar)
            XCTAssertEqual(g.arms.count, 8, "東西南北と斜めの腕")
            XCTAssertEqual(g.knurlCount, 72)
            XCTAssertTrue(g.showsInnerRing)
            XCTAssertTrue(g.showsNorthMark)
            XCTAssertEqual(g.tickCount, 0, "\(size)pt に目盛りを描くと詰まる")
        }
        for size in [32.0, 48, 96, 116] {
            let g = TrunkCoinGeometry(size: size)
            XCTAssertEqual(g.tier, .large, "\(size)pt")
            XCTAssertEqual(g.tickCount, 24)
        }
        // 6本ごとに太く長い目盛り
        XCTAssertLessThan(TrunkCoinGeometry.tickInner(0), TrunkCoinGeometry.tickInner(1))
        XCTAssertGreaterThan(TrunkCoinGeometry.tickWidth(6), TrunkCoinGeometry.tickWidth(7))
    }

    /// 星は北が一番長い（針が北を指す）。腕は黒い面（半径 40）の内に収まる
    func testNeedlePointsNorthInsideTheFace() {
        let g = TrunkCoinGeometry(size: 48)
        let north = g.arms.filter { $0.angle == 0 }
        XCTAssertEqual(north.count, 1)
        XCTAssertEqual(g.arms.map(\.length).max(), north[0].length, "北の腕が一番長くない")
        for arm in g.arms { XCTAssertLessThan(arm.length, TrunkCoinGeometry.faceRadius, "腕が黒い面からはみ出す") }
        XCTAssertEqual(g.arms.filter(\.cardinal).count, 4)
        // 小さい段の星も面の内。8 点で、北の点が真上
        let flat = TrunkCoinGeometry(size: 16).flatStar!
        let pts = TrunkCoinGeometry.starPoints(flat)
        XCTAssertEqual(pts.count, 8)
        XCTAssertEqual(pts[0].x, 50, accuracy: 0.0001)
        XCTAssertEqual(pts[0].y, 50 - flat.length, accuracy: 0.0001)
        XCTAssertLessThan(flat.length, TrunkCoinGeometry.faceRadius)
        // 下に重ねる斜めの星は 45° 回してある
        let back = TrunkCoinGeometry.starPoints(TrunkCoinGeometry.backStar)
        XCTAssertGreaterThan(back[0].x, 50, "斜めの星が回っていない")
    }

    /// 倒した硬貨: 楕円（cos）になり、下に厚みの帯（直径の 8% × sin）
    func testTiltedCoinBecomesAnEllipseWithThickness() {
        let g = TrunkCoinGeometry(size: 88, tilt: 60)
        XCTAssertEqual(g.squash, 0.5, accuracy: 0.0001)
        XCTAssertEqual(g.edgeDepth, 88 * 0.08 * sin(60 * Double.pi / 180), accuracy: 0.0001)
        XCTAssertEqual(g.drawnHeight, 44 + g.edgeDepth, accuracy: 0.0001)
        XCTAssertGreaterThan(TrunkCoinGeometry(size: 88, tilt: 120).squash, 0.15)
        XCTAssertEqual(TrunkCoinGeometry(size: 88, tilt: -10).squash, 1, accuracy: 0.0001)
        XCTAssertEqual(TrunkCoinGeometry(size: 14).shadowRadius, 0, "行の字と並ぶ小さな印に影を落とす")
    }

    /// 🔴 重ねた硬貨: 手元の枚数だけ（5枚まで描き、数は字で）。0枚でも影絵を1枚
    func testStackDrawsUpToFiveAndAShadowAtZero() {
        XCTAssertEqual(TrunkCoinStack.drawn(0), 1)
        XCTAssertTrue(TrunkCoinStack.isEmpty(0))
        XCTAssertEqual(TrunkCoinStack.drawn(3), 3)
        XCTAssertEqual(TrunkCoinStack.drawn(12), 5, "5枚を越えて描く")
        XCTAssertFalse(TrunkCoinStack.isEmpty(1))
        XCTAssertGreaterThan(TrunkCoinStack.height(coins: 3, size: 26), TrunkCoinStack.height(coins: 1, size: 26))
        XCTAssertEqual(TrunkCoinStack.height(coins: 9, size: 26), TrunkCoinStack.height(coins: 5, size: 26), accuracy: 0.0001)
        XCTAssertEqual(TrunkCoinStack.xShift(1), 1.5)
        XCTAssertEqual(TrunkCoinStack.xShift(2), 0)
    }

    /// 案内の真ん中の3枚: 奥の2枚は倒した楕円で小さく、手前の1枚は正面で大きく、針は北
    func testWelcomeStageStacksTiltedCoinsBehindAFrontCoin() {
        let coins = TrunkWelcomeText.stageCoins
        XCTAssertEqual(coins.count, 3)
        let front = coins[coins.count - 1]
        XCTAssertEqual(front.tilt, 0, "手前の1枚が正面でない")
        XCTAssertEqual(front.turn, 0, "手前の羅針盤が北を指していない")
        for back in coins.dropLast() {
            let g = TrunkCoinGeometry(size: back.size, tilt: back.tilt)
            XCTAssertGreaterThan(g.squash, 0.3)
            XCTAssertLessThan(g.squash, 0.7)
            XCTAssertLessThan(back.size, front.size)
            XCTAssertNotEqual(back.rotation, 0)
            XCTAssertGreaterThan(back.y, front.y)
        }
    }

    /// 🔴 どの画面の硬貨も羅針盤の部品1つ。昔の円盤（COIN の刻印）を残さない
    func testEveryScreenDrawsTheCompassCoin() throws {
        let mark = try source("Features/Trunk/TrunkCoinMark.swift")
        XCTAssertTrue(mark.contains("TrunkCoinNeedle(geometry: g)\n                    .rotationEffect(.degrees(turn))"), "星を別の層にして回していない")
        XCTAssertTrue(mark.contains("Circle().fill(Color.white.opacity(TrunkPartsBoxText.missingShadowOpacity))"), "0枚が影絵でない")
        XCTAssertFalse(mark.contains("Text(verbatim: \"COIN\")"), "硬貨に COIN の刻印が残っている")
        let gacha = try source("Features/Trunk/TrunkGachaView.swift")
        XCTAssertFalse(gacha.contains("struct TrunkCoinMark"), "古い硬貨が残っている")
        XCTAssertTrue(gacha.contains("TrunkCoinStackView(coins: coins, size: 26, liftTop: inserting)"), "機械の数の行が重ねた硬貨でない")
        XCTAssertTrue(try source("Features/Trunk/TrunkView.swift").contains("TrunkCoinMark(size: 20)"))
        XCTAssertTrue(try source("Features/Trunk/TrunkPartsBoxView.swift").contains("TrunkCoinMark(size: 14)"))
        XCTAssertTrue(try source("Features/Profile/CoverOfferView.swift").contains("TrunkCoinMark(size: 16)"))
        let arrived = try source("Features/Trunk/LabelArrivedView.swift")
        XCTAssertTrue(arrived.contains("TrunkCoinMark(size: 14, turn:"), "届いた画面の札の硬貨が羅針盤でない")
        let welcome = try source("Features/Trunk/TrunkWelcomeView.swift")
        XCTAssertTrue(welcome.contains("TrunkCoinShowcase(size: coin.size)"), "はじめての硬貨の手前の1枚が大きい絵でない")
        XCTAssertTrue(welcome.contains("TrunkCoinMark(size: coin.size, tilt: coin.tilt, turn: coin.turn)"))
        XCTAssertTrue(welcome.contains("TrunkCoinMark(size: 26)"), "「硬貨 +10 枚」の左の印が同じ部品でない")
    }
}
