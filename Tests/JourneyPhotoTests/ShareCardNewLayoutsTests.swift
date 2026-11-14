import XCTest
@testable import JourneyPhoto

/// 共有カードの新しい3つの型（プリント・切符・シネマ・2026-11-14）の寸法が、どの比でも安全域に収まること。
/// 描いた画像の画素での点検は `ShareCardAuditTests`（Mac）
final class ShareCardNewLayoutsTests: XCTestCase {
    typealias R = SignatureShareCardRenderer
    static let ratios: [R.Ratio] = [.portrait, .story, .square]

    func testTextBaseIsInsideTheSafeAreaInEveryRatio() {
        XCTAssertEqual(ShareCardMap.textBase(ratio: .portrait), 1350 - 72)
        XCTAssertEqual(ShareCardMap.textBase(ratio: .square), 1080 - 72)
        // 9:16 は下 20%（384）の上
        XCTAssertEqual(ShareCardMap.textBase(ratio: .story), 1536)
        for ratio in Self.ratios {
            XCTAssertLessThanOrEqual(ShareCardMap.textBase(ratio: ratio), ShareCardSafeArea.rect(ratio: ratio).maxY, "\(ratio)")
        }
        XCTAssertGreaterThanOrEqual(ShareCardMap.newStyleMargin, ShareCardSafeArea.rect(ratio: .portrait).minX)
    }

    func testPrintLayout() {
        typealias P = ShareCardMap.PrintLayout
        for ratio in Self.ratios {
            let layout = P(ratio: ratio)
            let safe = ShareCardSafeArea.rect(ratio: ratio)
            XCTAssertGreaterThanOrEqual(P.contentLeft, safe.minX, "\(ratio)")
            XCTAssertLessThanOrEqual(P.contentRight, safe.maxX, "\(ratio)")
            // 字は下から: 撮影地 → 市区町村 → 撮影者 → 撮影情報（撮影情報の行 20pt ≒ 24 が下端に収まる）
            XCTAssertLessThan(layout.placeTop, layout.subPlaceTop, "\(ratio)")
            XCTAssertLessThan(layout.subPlaceTop, layout.authorTop, "\(ratio)")
            XCTAssertLessThan(layout.authorTop, layout.infoTop, "\(ratio)")
            XCTAssertLessThanOrEqual(layout.infoTop + 24, layout.base + 0.001, "\(ratio)")
            XCTAssertGreaterThanOrEqual(layout.placeTop, safe.minY, "\(ratio) 字が上の帯に入る")
            // 写真は上と左右のフチが同じ 72。高さは十分
            XCTAssertEqual(layout.photoRect.minX, 72)
            XCTAssertEqual(layout.photoRect.minY, 72)
            XCTAssertEqual(layout.photoRect.maxX, 1008)
            XCTAssertEqual(layout.photoRect.maxY + 40, layout.placeTop)
            XCTAssertGreaterThan(layout.photoRect.height, 600, "\(ratio)")
        }
    }

    func testTicketLayout() {
        typealias T = ShareCardMap.TicketLayout
        XCTAssertEqual(T.contentLeft, 72)
        XCTAssertEqual(T.contentRight, 1008)
        for ratio in Self.ratios {
            let layout = T(ratio: ratio)
            let safe = ShareCardSafeArea.rect(ratio: ratio)
            // 切符の外形は画像の中（下は 40 以上空く）。字の下端は安全域の中
            XCTAssertLessThanOrEqual(layout.ticketRect.maxY, layout.height - 40 + 0.001, "\(ratio)")
            XCTAssertLessThanOrEqual(layout.base, safe.maxY, "\(ratio)")
            XCTAssertGreaterThanOrEqual(layout.stubTop, safe.minY, "\(ratio)")
            // 写真 → ミシン目 → 半券の順。地図は半券の右の列、字の列と重ならない
            XCTAssertLessThan(layout.photoRect.maxY, layout.perforationY, "\(ratio)")
            XCTAssertLessThan(layout.perforationY, layout.stubTop, "\(ratio)")
            XCTAssertGreaterThan(layout.photoRect.height, 600, "\(ratio)")
            XCTAssertGreaterThanOrEqual(layout.mapRect.minX, T.contentLeft + T.leftColumnWidth, "\(ratio)")
            XCTAssertEqual(layout.mapRect.maxX, T.contentRight)
            XCTAssertEqual(layout.mapRect.maxY, layout.base, accuracy: 0.001)
            XCTAssertGreaterThan(layout.mapRect.height, 100, "\(ratio)")
        }
    }

    func testCinemaLayout() {
        typealias C = ShareCardMap.CinemaLayout
        for ratio in Self.ratios {
            let layout = C(ratio: ratio)
            let safe = ShareCardSafeArea.rect(ratio: ratio)
            // 写真は左右の端まで。字は写真の下の黒い帯の上だけ
            XCTAssertEqual(layout.photoRect.minX, 0)
            XCTAssertEqual(layout.photoRect.width, 1080)
            XCTAssertGreaterThan(layout.placeTop, layout.photoRect.maxY, "\(ratio)")
            XCTAssertLessThanOrEqual(layout.infoTop + 24, layout.base, "\(ratio)")
            XCTAssertLessThanOrEqual(layout.base, safe.maxY, "\(ratio)")
            XCTAssertGreaterThanOrEqual(C.contentLeft, safe.minX)
            XCTAssertGreaterThan(layout.photoRect.height, 600, "\(ratio)")
        }
    }

    /// 型の並び: 7つ・重ならない・既定の帯が先頭（既定は変えない）。名前は1語で「・」を使わない
    func testStyleChoiceOrder() {
        let order = ShareCardStyleChoice.order
        XCTAssertEqual(order.count, R.Style.allCases.count)
        XCTAssertEqual(Set(order.map(\.rawValue)), Set(R.Style.allCases.map(\.rawValue)))
        XCTAssertEqual(order.first, .band)
        XCTAssertEqual(Array(order.suffix(3)), [.printed, .ticket, .cinema])
        for style in order {
            let title = ShareCardStyleChoice.title(style)
            XCTAssertFalse(title.isEmpty)
            XCTAssertFalse(title.contains("・"), title)
        }
    }
}
