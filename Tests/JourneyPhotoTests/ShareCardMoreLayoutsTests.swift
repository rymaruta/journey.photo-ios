import XCTest
@testable import JourneyPhoto

/// 共有カードの次の3つの型（額装・フィルム・縦書き・2026-11-14）の寸法が、どの比でも安全域に収まること。
/// 描いた画像の画素での点検（安全域・明暗の比・切れ・重なり・SNS ごとの切り取り）は `ShareCardAuditTests`（Mac）
final class ShareCardMoreLayoutsTests: XCTestCase {
    typealias R = SignatureShareCardRenderer
    static let ratios: [R.Ratio] = [.portrait, .story, .square]

    func testMatLayout() {
        typealias M = ShareCardMap.MatLayout
        for ratio in Self.ratios {
            let layout = M(ratio: ratio)
            let safe = ShareCardSafeArea.rect(ratio: ratio)
            // 上のロゴの行（マーク 28 の上端 = 中心 − 14）は安全域の中。9:16 はフィードの 4:5 の切り取り + 6% の下
            XCTAssertGreaterThanOrEqual(layout.brandCenterY - 14, safe.minY, "\(ratio)")
            XCTAssertGreaterThanOrEqual(M.contentLeft, safe.minX)
            // 下から: 撮影地 → 市区町村 → 撮影者 → 住所。住所の行（20pt ≒ 24）が下端に収まる
            XCTAssertLessThan(layout.placeTop, layout.subPlaceTop, "\(ratio)")
            XCTAssertLessThan(layout.subPlaceTop, layout.authorTop, "\(ratio)")
            XCTAssertLessThan(layout.authorTop, layout.addressTop, "\(ratio)")
            XCTAssertLessThanOrEqual(layout.addressTop + 24, safe.maxY, "\(ratio)")
            // 写真は左右のマット 96 の内側。字の余白 72 より広い（額に入れた形）
            XCTAssertEqual(layout.photoRect.minX, 96)
            XCTAssertEqual(layout.photoRect.maxX, 984)
            XCTAssertGreaterThan(M.matSide, M.margin)
            XCTAssertGreaterThan(layout.photoRect.height, 600, "\(ratio)")
        }
        XCTAssertEqual(M(ratio: .portrait).brandTop, 72)
        XCTAssertEqual(M(ratio: .story).brandTop, 354)
    }

    /// 額の色: どんな写真の色でも、白の字 7:1 以上・灰（#B8B8B8）の字 4.5:1 以上。色相は写真のまま
    func testMatColorKeepsTextReadableForAnyPhoto() {
        let white = ShareCardSafeArea.luminance(red: 255, green: 255, blue: 255)
        let gray = ShareCardSafeArea.luminance(red: 184, green: 184, blue: 184)
        let samples: [(Double, Double, Double)] = [
            (255, 255, 255), (0, 0, 0), (158, 204, 250), (250, 120, 30), (30, 160, 60), (128, 128, 128),
            (255, 0, 0), (0, 0, 255), (220, 190, 140), (12, 40, 90)
        ]
        for sample in samples {
            let mat = ShareCardMap.MatColor.color(red: sample.0, green: sample.1, blue: sample.2)
            let luminance = ShareCardSafeArea.luminance(red: mat.red, green: mat.green, blue: mat.blue)
            XCTAssertLessThanOrEqual(luminance, ShareCardMap.MatColor.targetLuminance + 0.001, "\(sample)")
            XCTAssertGreaterThanOrEqual(ShareCardSafeArea.contrast(white, luminance), 7, "\(sample)")
            XCTAssertGreaterThanOrEqual(ShareCardSafeArea.contrast(gray, luminance), 4.5, "\(sample)")
        }
        // 青い空の写真 → 青い額（青が一番強い）。灰の写真 → 色の無い額
        let sky = ShareCardMap.MatColor.color(red: 158, green: 204, blue: 250)
        XCTAssertGreaterThan(sky.blue, sky.red)
        let neutral = ShareCardMap.MatColor.color(red: 128, green: 128, blue: 128)
        XCTAssertEqual(neutral.red, neutral.blue, accuracy: 0.5)
    }

    func testFilmLayout() {
        typealias F = ShareCardMap.FilmLayout
        for ratio in Self.ratios {
            let layout = F(ratio: ratio)
            let safe = ShareCardSafeArea.rect(ratio: ratio)
            // フィルム → 撮影地 → 撮影値 → 機材 → 撮影者。撮影者の行（24pt ≒ 29）が下端に収まる
            XCTAssertLessThan(layout.stripRect.maxY, layout.placeTop, "\(ratio)")
            XCTAssertLessThan(layout.placeTop, layout.heroTop, "\(ratio)")
            XCTAssertLessThan(layout.heroTop, layout.gearTop, "\(ratio)")
            XCTAssertLessThan(layout.gearTop, layout.authorTop, "\(ratio)")
            XCTAssertLessThanOrEqual(layout.authorTop + 29, safe.maxY, "\(ratio)")
            XCTAssertGreaterThanOrEqual(layout.placeTop, safe.minY, "\(ratio)")
            // 写真は穴の列の内側。穴はフィルムの中
            XCTAssertGreaterThan(layout.photoRect.height, 500, "\(ratio)")
            for hole in layout.holeRects {
                XCTAssertTrue(layout.stripRect.contains(hole), "\(ratio) \(hole)")
                XCTAssertFalse(hole.intersects(layout.photoRect), "\(ratio) \(hole)")
            }
            XCTAssertEqual(layout.holeRects.count, 36)
        }
        // 9:16 はフィードの 4:5 の切り取りの上端（285）からフィルムを始める
        XCTAssertEqual(F(ratio: .story).stripTop, 285)
        XCTAssertEqual(F(ratio: .portrait).stripTop, 56)
    }

    func testTanzakuLayout() {
        typealias T = ShareCardMap.TanzakuLayout
        for ratio in Self.ratios {
            let layout = T(ratio: ratio)
            let safe = ShareCardSafeArea.rect(ratio: ratio)
            XCTAssertGreaterThanOrEqual(layout.placeTop, safe.minY, "\(ratio)")
            XCTAssertLessThanOrEqual(layout.authorTop + 29, safe.maxY, "\(ratio)")
            // 列は安全域の右端の内側。撮影地の列（76 の字）と市区町村の列（30 の字）は重ならない
            XCTAssertLessThanOrEqual(T.placeColumnX + T.placeFontSize / 2 + 2, safe.maxX)
            XCTAssertLessThan(T.subColumnX + T.subFontSize / 2 + 2, T.placeColumnX - T.placeFontSize / 2 - 2)
            XCTAssertLessThanOrEqual(layout.sealRect.maxX, safe.maxX)
            XCTAssertLessThan(layout.photoRect.maxX, T.columnLeft)
            // 撮影地は印の上で、4 字（「和歌山県」）が大きさを下げずに入る
            XCTAssertGreaterThan(layout.placeBottom - layout.placeTop, 4 * T.placeFontSize * T.verticalAdvance, "\(ratio)")
            XCTAssertGreaterThan(layout.photoRect.height, 600, "\(ratio)")
        }
    }

    func testVerticalText() {
        typealias V = ShareCardMap.VerticalText
        XCTAssertTrue(V.stacks("京都府"))
        XCTAssertTrue(V.stacks("東牟婁郡那智勝浦町"))
        XCTAssertTrue(V.stacks("ニセコアンヌプリ"))
        XCTAssertFalse(V.stacks("Saint-Germain-en-Laye"))
        XCTAssertFalse(V.stacks("Kyoto"))
        XCTAssertFalse(V.stacks(""))
        XCTAssertTrue(V.rotatesInColumn("ー"))
        XCTAssertFalse(V.rotatesInColumn("京"))
        // 入るときは大きさのまま。入らなければ下限まで縮め、それでも入らなければ最後を「︙」に
        let fits = V.fit(count: 4, maxHeight: 1000, size: 76, minimumSize: 40)
        XCTAssertEqual(fits.size, 76)
        XCTAssertFalse(fits.truncated)
        let shrinks = V.fit(count: 12, maxHeight: 700, size: 76, minimumSize: 40)
        XCTAssertLessThan(shrinks.size, 76)
        XCTAssertFalse(shrinks.truncated)
        let cut = V.fit(count: 40, maxHeight: 700, size: 76, minimumSize: 40)
        XCTAssertEqual(cut.size, 40)
        XCTAssertTrue(cut.truncated)
        XCTAssertEqual(cut.shown, Int(700 / (40 * 1.08)))
    }
}
