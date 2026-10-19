import XCTest
@testable import JourneyPhoto

/// 撮った写真を奥・中・手前の 3 枚に切る（濃さの段・前景の型・決まった波）と、撮る枠の切り抜き
final class CampLayerSplitTests: XCTestCase {

    /// 霧の森の見本: 空 0.92・遠い木 0.7（稜線 30 前後）・中の木 0.45（稜線 60 前後）・近い木 0.12（稜線 90 前後）
    private func foggyForest(width: Int = 60, height: Int = 120) -> [Double] {
        var luma = [Double](repeating: 0.92, count: width * height)
        for x in 0..<width {
            let u = Double(x) / Double(width - 1)
            let far = 30 + Int(8 * sin(u * 9)), mid = 60 + Int(10 * sin(u * 13 + 1)), near = 90 + Int(6 * sin(u * 7 + 2))
            for y in 0..<height {
                let v: Double = y >= near ? 0.12 : (y >= mid ? 0.45 : (y >= far ? 0.7 : 0.92))
                luma[y * width + x] = v
            }
        }
        return luma
    }

    func testSplitsByLuminanceBands() {
        let cut = CampLayerSplit.split(luma: foggyForest(), width: 60, height: 120)
        XCTAssertEqual(cut.method, .luminance)
        XCTAssertEqual(cut.layers.count, 3)
        XCTAssertEqual(cut.width, 360)
        XCTAssertEqual(cut.height, 720, accuracy: 1e-9, "範囲の高さは幅 360 に合わせた単位")
        for layer in cut.layers {
            XCTAssertEqual(layer.points.count, 61, "稜線は 6 ずつ 61 点（板の LAY）")
            XCTAssertEqual(layer.points.first?.x, 0)
            XCTAssertEqual(layer.points.last?.x, 360)
            XCTAssertEqual(layer.top + layer.height, cut.height, accuracy: 1e-6, "どの層も範囲の下の端まで")
        }
        // 奥ほど上（奥の稜線の平均 < 中 < 手前）
        let means = cut.layers.map { l in l.points.map { l.top + $0.y }.reduce(0, +) / Double(l.points.count) }
        XCTAssertLessThan(means[0], means[1])
        XCTAssertLessThan(means[1], means[2])
        // 見本の稜線（30・60・90 行 × 6）に近い
        XCTAssertEqual(means[0], 30 * 6, accuracy: 40)
        XCTAssertEqual(means[1], 60 * 6, accuracy: 40)
        XCTAssertEqual(means[2], 90 * 6, accuracy: 40)
    }

    /// 列ごとに 奥 < 中 < 手前 の間が空く（紙が重ならずに見える）
    func testLayersKeepAGap() {
        let cut = CampLayerSplit.split(luma: foggyForest(), width: 60, height: 120)
        let gap = CampLayerSplit.minGap * cut.height
        for c in 0..<61 {
            let t = cut.layers.map { $0.top + $0.points[c].y }
            XCTAssertGreaterThanOrEqual(t[1] - t[0], gap - 0.2, "列 \(c)")
            XCTAssertGreaterThanOrEqual(t[2] - t[1], gap - 0.2, "列 \(c)")
            XCTAssertLessThanOrEqual(t[2], cut.height * (1 - CampLayerSplit.minLayerHeight) + 0.2, "手前が細くなりすぎる")
        }
    }

    /// 濃さに差が無い写真は、決まった波で 3 枚（壊れない）
    func testFlatPhotoFallsBack() {
        let flat = [Double](repeating: 0.5, count: 60 * 80)
        let cut = CampLayerSplit.split(luma: flat, width: 60, height: 80)
        XCTAssertEqual(cut.method, .fallback)
        XCTAssertEqual(cut.layers.count, 3)
        XCTAssertLessThan(cut.layers[0].top, cut.layers[1].top)
        XCTAssertLessThan(cut.layers[1].top, cut.layers[2].top)
        // 読めない（大きさが合わない）ときも
        XCTAssertEqual(CampLayerSplit.split(luma: [], width: 10, height: 10).method, .fallback)
    }

    /// 前景の型があれば、手前の 1 枚はその上の縁で切る
    func testForegroundMaskSetsTheNearLayer() {
        let w = 60, h = 120
        var mask = [Bool](repeating: false, count: w * h)
        for x in 0..<w { for y in 100..<h { mask[y * w + x] = true } }
        let cut = CampLayerSplit.split(luma: foggyForest(), width: w, height: h, foreground: mask)
        XCTAssertEqual(cut.method, .foregroundMask)
        let near = cut.layers[2]
        let mean = near.points.map { near.top + $0.y }.reduce(0, +) / 61
        // 100 行（× 6）だが、下に高さを残すので 82% で頭打ち
        XCTAssertEqual(mean, min(100 * 6, cut.height * (1 - CampLayerSplit.minLayerHeight)), accuracy: 6)
    }

    /// 紙の板は写真の輪郭より紙のフチの分だけ大きい（札の座標）
    func testRimOutline() {
        let layer = CampLayerSplit.fallback(unitHeight: 498).layers[0]
        let photo = CampCutLayers.photoOutline(layer)
        let rim = CampCutLayers.rimOutline(layer)
        XCTAssertEqual(photo.count, 61 + 4)
        XCTAssertGreaterThan(abs(CampGeometry.area(rim)), abs(CampGeometry.area(photo)))
        XCTAssertEqual(photo.first?.x, CampCutLayers.margin)
    }

    /// 撮る枠（板: 390 × 844 で x 80.4〜309.6・y 351.5〜663.9）と、映像を枠いっぱいに敷いたときの写真の範囲
    func testCropFrame() {
        let f = CampCrop.frame(width: 390, height: 844)
        XCTAssertEqual(f.x, 80.4, accuracy: 1e-9)
        XCTAssertEqual(f.y, 351.5, accuracy: 1e-9)
        XCTAssertEqual(f.w, 229.2, accuracy: 1e-9)
        XCTAssertEqual(f.h, 312.4, accuracy: 1e-9)
        // 3:4 の写真（3000 × 4000）を 390 × 724 の映像に敷く: 高さで合わせ（724 / 4000）、左右が切れる
        let r = CampCrop.photoRect(frame: (80.4, 351.5, 229.2, 312.4), view: (390, 724), photo: (3000, 4000))
        let scale = 724.0 / 4000
        XCTAssertEqual(r.w, 229.2 / scale, accuracy: 1e-6)
        XCTAssertEqual(r.y, 351.5 / scale, accuracy: 1e-6)
        XCTAssertEqual(r.x, (80.4 - (390 - 3000 * scale) / 2) / scale, accuracy: 1e-6)
        // 写真の外にはみ出さない
        let tiny = CampCrop.photoRect(frame: (0, 0, 390, 844), view: (390, 844), photo: (10, 10))
        XCTAssertLessThanOrEqual(tiny.x + tiny.w, 10 + 1e-9)
        XCTAssertLessThanOrEqual(tiny.y + tiny.h, 10 + 1e-9)
    }

    func testLuminanceWeights() {
        XCTAssertEqual(CampLayerSplit.luminance(r: 255, g: 255, b: 255), 1, accuracy: 1e-9)
        XCTAssertEqual(CampLayerSplit.luminance(r: 0, g: 255, b: 0), 0.59, accuracy: 1e-9)
    }
}
