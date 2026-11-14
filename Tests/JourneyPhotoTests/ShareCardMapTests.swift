import XCTest
@testable import JourneyPhoto

/// SNS 共有カードの地図（案A-3・2026-11-04 owner 了承）と撮影地の折り返しの計算。
/// 描く処理は Linux では空なので、計算だけを切り出して試す（`ShareCardMap`・`ShareCardText`）。
final class ShareCardMapTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/JourneyPhoto/Resources")

    private static func shapes(_ name: String) throws -> [ShareCardMap.Shape] {
        let data = try Data(contentsOf: resources.appendingPathComponent("\(name).json"))
        return try JSONDecoder().decode([ShareCardMap.Shape].self, from: data)
    }

    private static let countries: [ShareCardMap.Shape] = (try? shapes("country-outlines")) ?? []

    private func country(_ name: String) throws -> ShareCardMap.Shape {
        try XCTUnwrap(Self.countries.first { $0.n == name }, "\(name) が国の輪郭に無い")
    }

    // MARK: - 枠の寸法

    func testMapFrameStaysInsideTheBandInEveryRatio() {
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.Layout(ratio: ratio)
            let map = layout.mapRect
            XCTAssertEqual(map.width, 286, "\(ratio)")
            XCTAssertEqual(map.height, 244, "\(ratio)")
            // 2026-11-04 owner「フェードする境界線いらない」: 地図は黒い帯の中だけ（写真に掛けない）。
            // 「撮影情報さらに小さくして地図大きくしていい」: 帯の高さいっぱい（上下の余白 12）
            XCTAssertEqual(map.minY, layout.photoBottom + 12, "\(ratio) 帯の上から 12")
            if ratio != .story {
                XCTAssertEqual(map.maxY, layout.bandRect.maxY - 12, accuracy: 0.001, "\(ratio) 帯の下から 12")
            } else {
                XCTAssertLessThanOrEqual(map.maxY, layout.bandRect.maxY - 12, "\(ratio)")
            }
            // 横: 右端は本文の右端。撮影地の字は 150 以上（括弧つき最長10字を 15 で切らず入れる）
            XCTAssertEqual(map.maxX, ShareCardMap.Layout.contentRight, "\(ratio)")
            XCTAssertGreaterThanOrEqual(ShareCardMap.Layout.placeWidthWithMap, 150, "\(ratio)")
            XCTAssertEqual(ShareCardMap.Layout.placeX + ShareCardMap.Layout.placeWidthWithMap + 8,
                           map.minX, accuracy: 0.001)
        }
    }

    func testMapFrameMeasuredValues() {
        // 4:5（1080×1350）: 帯 1022・撮影者の段 1038（アバター 76）・区切り線 1156・撮影情報 1200（高さ 52）・帯の下端 1290（下の余白 38）。
        // 地図は 286×244（x 734・y 1034）。帯の高さいっぱい（2026-11-05: アバターを 76 に縮め縦線を左へ寄せて 236 → 286）
        let portrait = ShareCardMap.Layout(ratio: .portrait)
        XCTAssertEqual(portrait.photoBottom, 1022)
        XCTAssertEqual(portrait.rowTop, 1038)
        XCTAssertEqual(portrait.separatorY, 1156)
        XCTAssertEqual(portrait.infoTop, 1200)
        XCTAssertEqual(portrait.bandRect.maxY, 1290)
        XCTAssertEqual(portrait.mapRect, CGRect(x: 734, y: 1034, width: 286, height: 244))
        // 帯の下の余白は 38。9:16 は下の段が高い（その分だけ下に空く）が、地図の大きさは同じ
        XCTAssertEqual(portrait.bandRect.maxY - (portrait.infoTop + ShareCardMap.Layout.infoHeight), 38)
        let story = ShareCardMap.Layout(ratio: .story)
        XCTAssertEqual(story.mapRect.size, portrait.mapRect.size)
        let square = ShareCardMap.Layout(ratio: .square)
        XCTAssertEqual(square.mapRect.size, portrait.mapRect.size)
        XCTAssertEqual(square.bandRect.maxY - (square.infoTop + ShareCardMap.Layout.infoHeight), 38)
    }

    /// 2026-11-04 owner「写真の角とアイコンの先頭の端が合うように」: 写真の左右の端に、中身の左右の端がそろう
    func testContentEdgesAlignWithThePhotoEdges() {
        typealias L = ShareCardMap.Layout
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.Layout(ratio: ratio)
            XCTAssertEqual(L.contentLeft, layout.photoRect.minX, "\(ratio) ロゴ・アバター・区切り線・撮影情報の左端")
            XCTAssertEqual(L.contentRight, layout.photoRect.maxX, "\(ratio) 一文・地図・区切り線の右端")
            XCTAssertEqual(layout.mapRect.maxX, layout.photoRect.maxX, "\(ratio)")
        }
    }

    /// 段の間隔（撮影者の段 → 区切り線 → 撮影情報）は上も下も 42
    func testRowGapsAreEqualInEveryRatio() {
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.Layout(ratio: ratio)
            let above = layout.separatorY - (layout.rowTop + ShareCardMap.Layout.avatarSize)
            let below = layout.infoTop - (layout.separatorY + ShareCardMap.Layout.lineWidth)
            XCTAssertEqual(above, 42, "\(ratio)")
            XCTAssertEqual(below, 42, "\(ratio)")
        }
    }

    /// 2026-11-13（owner 承認）: 撮影情報が1つも無いと、撮影者の段の下に 138 の黒い空きが残っていた
    /// （4:5 で撮影者の段の下端 1114 → 帯の下端 1290 が 176）。無いときは下の段の分だけ帯を縮め、写真を伸ばす
    func testBandShrinksWithoutShotInfo() {
        typealias L = ShareCardMap.Layout
        XCTAssertEqual(L.shotInfoBlockHeight, 138)
        // 撮影情報があるとき: 今までどおり（4:5 の写真 898・帯 268）
        let withInfo = L(ratio: .portrait)
        XCTAssertEqual(withInfo.photoRect.height, 898)
        XCTAssertEqual(withInfo.bandRect.height, 268)
        // 無いとき: 写真 898 → 1036・帯 268 → 130。撮影者の段の下端 1252 から帯の下端 1290 は 38（撮影情報の下と同じ）
        let without = L(ratio: .portrait, hasShotInfo: false)
        XCTAssertEqual(without.photoRect.height, 1036)
        XCTAssertEqual(without.bandRect.height, 130)
        XCTAssertEqual(without.rowTop, 1176)
        XCTAssertEqual(without.bandRect.maxY - (without.rowTop + L.avatarSize), 38)
        // 地図は帯の高さ（上下 12）に収まるよう比のまま縮め、右端は本文の右端
        XCTAssertEqual(without.mapRect.minY, without.photoBottom + 12)
        XCTAssertEqual(without.mapRect.height, 106)
        XCTAssertEqual(without.mapRect.width, 286 * 106 / 244, accuracy: 0.001)
        XCTAssertEqual(without.mapRect.maxX, L.contentRight, accuracy: 0.001)

        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let info = L(ratio: ratio)
            let none = L(ratio: ratio, hasShotInfo: false)
            // 空き0: 撮影者の段の下の余白は、撮影情報があるときの撮影情報の下の余白と同じ
            XCTAssertEqual(none.bandRect.maxY - (none.rowTop + L.avatarSize),
                           info.bandRect.maxY - (info.infoTop + L.infoHeight), "\(ratio) 空き0")
            XCTAssertEqual(none.photoRect.height - info.photoRect.height, 138, "\(ratio) 写真が伸びる")
            XCTAssertEqual(info.bandRect.height - none.bandRect.height, 138, "\(ratio) 帯が縮む")
            XCTAssertEqual(none.height, info.height, "\(ratio) カードの大きさは同じ")
            XCTAssertEqual(none.photoRect.maxY, none.bandRect.minY, "\(ratio)")
            // 地図は帯の中だけ
            XCTAssertGreaterThanOrEqual(none.mapRect.minY, none.bandRect.minY + 12, "\(ratio)")
            XCTAssertLessThanOrEqual(none.mapRect.maxY, none.bandRect.maxY - 12 + 0.001, "\(ratio)")
            XCTAssertEqual(none.mapRect.maxX, L.contentRight, accuracy: 0.001, "\(ratio)")
            // 9:16 は下の 75（返信欄）に地図を掛けない
            XCTAssertLessThanOrEqual(none.mapRect.maxY, none.bandRect.maxY - none.bottomInset - 12 + 0.001, "\(ratio) 返信欄")
            XCTAssertLessThanOrEqual(info.mapRect.maxY, info.bandRect.maxY - info.bottomInset - 12 + 0.001, "\(ratio) 返信欄")
            // どの比でも地図は同じ大きさ（撮影情報なしは 4:5 と同じ 106 の高さ）
            XCTAssertEqual(none.mapRect.size.height, without.mapRect.size.height, accuracy: 0.001, "\(ratio) 地図の大きさ")
            XCTAssertEqual(none.mapRect.size.width, without.mapRect.size.width, accuracy: 0.001, "\(ratio) 地図の大きさ")
            // 撮影情報があるときの地図は変えない
            XCTAssertEqual(info.mapRect, CGRect(x: 734, y: info.photoBottom + 12, width: 286, height: 244), "\(ratio)")
            // 撮影地の字の幅: 撮影情報があるときは今までどおり。地図が縮めばその分広い（地図の左端の 8 手前まで）
            XCTAssertEqual(info.placeWidth(hasMap: true), L.placeWidthWithMap, accuracy: 0.001, "\(ratio)")
            XCTAssertEqual(info.placeWidth(hasMap: false), L.placeWidthWithoutMap, "\(ratio)")
            XCTAssertEqual(none.placeWidth(hasMap: true), none.mapRect.minX - 8 - L.placeX, accuracy: 0.001, "\(ratio)")
            XCTAssertGreaterThan(none.placeWidth(hasMap: true), L.placeWidthWithMap, "\(ratio)")
        }
        // 9:16・撮影情報なしの地図: 帯 1655〜1860・返信欄 75 を除いた下端 1773 まで
        let story = L(ratio: .story, hasShotInfo: false)
        XCTAssertEqual(story.mapRect.minY, 1667)
        XCTAssertEqual(story.mapRect.maxY, 1773, accuracy: 0.001)
    }

    /// 2026-11-04 owner「フェードする境界線いらない」: 写真は帯の開始位置できれいに終わる。
    /// 写真と帯は隙間も重なりも無く接する
    func testPhotoEndsCleanlyWhereTheBandStarts() {
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.Layout(ratio: ratio)
            XCTAssertEqual(layout.photoRect.maxY, layout.bandRect.minY, "\(ratio)")
            XCTAssertEqual(layout.photoRect.minX, layout.bandRect.minX, "\(ratio)")
            XCTAssertEqual(layout.photoRect.width, layout.bandRect.width, "\(ratio)")
        }
    }

    /// 縦の線の位置: 撮影情報の3列の左端・縦罫は、上の段の縦の線にそろう
    func testInfoColumnsAlignWithRowAboveLines() {
        typealias L = ShareCardMap.Layout
        XCTAssertEqual(L.nameX, 156)
        XCTAssertEqual(L.rowDividerX, 337)
        XCTAssertEqual(L.pinX, 361)
        XCTAssertEqual(L.placeX, 411)
        XCTAssertEqual(L.mapX, 734)
        XCTAssertEqual(L.exposureX, 590)
        XCTAssertEqual(L.lensColumnWidth, 215)
        // 区切り線は地図の手前（16）で止まる
        let layout = ShareCardMap.Layout(ratio: .portrait)
        XCTAssertEqual(layout.separatorEndX(hasMap: true), 718)
        XCTAssertEqual(layout.separatorEndX(hasMap: false), 1020)
        XCTAssertEqual(L.contentLeft, 60)
        XCTAssertEqual(L.contentRight, 1020)
    }

    // MARK: - フェード型の寸法（2026-11-05・見本 F2）

    func testFadeLayoutMeasuredValues() {
        typealias F = ShareCardMap.FadeLayout
        let portrait = F(ratio: .portrait)
        XCTAssertEqual(portrait.height, 1350)
        XCTAssertEqual(portrait.base, 1350)
        XCTAssertEqual(portrait.fadeTop, 640)
        XCTAssertEqual(portrait.mapRect, CGRect(x: 640, y: 690, width: 380, height: 520))
        XCTAssertEqual(portrait.placeTop, 984)
        XCTAssertEqual(portrait.subPlaceTop, 1104)
        XCTAssertEqual(portrait.authorTop, 1164)
        XCTAssertEqual(portrait.exifCenterY, 1260)
        // 9:16 は下の 75 を空ける（Instagram の返信欄）。地図の大きさは同じ
        let story = F(ratio: .story)
        XCTAssertEqual(story.height, 1920)
        XCTAssertEqual(story.base, 1845)
        XCTAssertEqual(story.mapRect.size, portrait.mapRect.size)
        XCTAssertEqual(story.mapRect.maxY, 1845 - 140)
        // 1:1 は写真が低いので、グラデーションを短く・地図を低く
        let square = F(ratio: .square)
        XCTAssertEqual(square.fadeTop, 520)
        XCTAssertEqual(square.mapRect.height, 400)
    }

    /// どの比率でも、地名 → 市区町村 → 撮影者 → 撮影情報が重ならず、地図は撮影情報の上・右端は写真の右端
    func testFadeLayoutNeverOverlaps() {
        typealias F = ShareCardMap.FadeLayout
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let l = F(ratio: ratio)
            XCTAssertLessThan(l.placeTop + F.placeFontSize, l.subPlaceTop, "\(ratio) 地名の字が市区町村に掛かる")
            XCTAssertLessThan(l.subPlaceTop + F.subPlaceFontSize * 1.2, l.authorTop, "\(ratio)")
            // 撮影情報は 2 行（長いレンズ名）になっても行の高さ 52 の中心から上下 26
            XCTAssertLessThanOrEqual(l.authorTop + F.avatarSize, l.exifCenterY - 26, "\(ratio)")
            XCTAssertLessThanOrEqual(l.mapRect.maxY, l.exifCenterY - 26, "\(ratio)")
            XCTAssertEqual(l.mapRect.maxX, F.contentRight, "\(ratio)")
            // 左の列は地図の手前で終わる
            XCTAssertEqual(F.contentLeft + F.leftColumnWidth, l.mapRect.minX, "\(ratio)")
            // 地図の上はグラデーションの中（写真の明るい所に真鍮の線を置かない）
            XCTAssertGreaterThanOrEqual(l.mapRect.minY, l.fadeTop, "\(ratio)")
            XCTAssertGreaterThanOrEqual(l.fadeTop, 0, "\(ratio)")
        }
    }

    func testFadeStopsAreSmoothAndEndOnBlack() {
        let stops = ShareCardMap.FadeLayout.fadeStops
        XCTAssertEqual(stops.first?.location, 0)
        XCTAssertEqual(stops.first?.alpha, 0)
        XCTAssertEqual(stops.last?.location, 1)
        XCTAssertEqual(stops.last?.alpha, 1)
        XCTAssertGreaterThanOrEqual(stops.count, 6, "短い帯にしない（境目を見せない）")
        for (a, b) in zip(stops, stops.dropFirst()) {
            XCTAssertLessThan(a.location, b.location)
            XCTAssertLessThan(a.alpha, b.alpha)
            // 隣の点の濃さの差は 0.3 まで（急に濃くならない）
            XCTAssertLessThanOrEqual(b.alpha - a.alpha, 0.3)
        }
    }

    /// 2026-11-05: カードの上の隅に入れる Web の住所。サイトの本物の住所で、2行の塊が見出しに収まる
    func testSiteAddressIsTheRealDomainAndFitsTheHeader() {
        typealias L = ShareCardMap.Layout
        XCTAssertEqual(L.siteAddress, "journey-photo.com")
        XCTAssertGreaterThanOrEqual(L.siteAddressFontSize, 20, "字は最小 20（1080 幅）")
        // 一文 25 の行（約30）+ 間 + 住所 20 の行（約24）の塊は、見出しの縦線（57）より低い
        let block = 30 + L.taglineAddressGap + 24
        XCTAssertLessThanOrEqual(block, 62)
        XCTAssertLessThan(block / 2, L.header / 2 - 12, "額縁の内側に収まる")
    }

    // MARK: - 展示札・表紙の寸法（2026-11-06）

    func testLabelLayoutNeverOverlapsAndKeepsTheBottomMargin() {
        typealias L = ShareCardMap.LabelLayout
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let l = L(ratio: ratio)
            XCTAssertGreaterThan(l.photoRect.height, 500, "\(ratio) 写真が低すぎる")
            XCTAssertLessThan(l.eyebrowTop, l.placeTop, "\(ratio)")
            XCTAssertLessThan(l.placeTop + L.placeFontSize, l.ruleY, "\(ratio) 地名が罫線に掛かる")
            XCTAssertLessThan(l.ruleY, l.authorTop, "\(ratio)")
            XCTAssertLessThanOrEqual(l.authorTop + 64, l.tableTop, "\(ratio) 撮影者が表に掛かる")
            // 表の中身は、下の余白 60（9:16 は返信欄の 75 を足した所）より上で終わる
            XCTAssertLessThanOrEqual(l.tableBottom, l.height - 60 - (ratio == .story ? 75 : 0), "\(ratio)")
            // 地図は札の中（写真の下から）・右端は写真の右端・左の列と重ならない
            XCTAssertGreaterThanOrEqual(l.mapRect.minY, l.photoBottom, "\(ratio)")
            XCTAssertEqual(l.mapRect.maxX, L.contentRight, "\(ratio)")
            XCTAssertLessThanOrEqual(L.contentLeft + L.leftColumnWidth, l.mapRect.minX, "\(ratio)")
            XCTAssertLessThanOrEqual(l.mapRect.maxY, l.base - 60, "\(ratio)")
            // 表の3列は、地図と重ならず、列どうしも重ならない
            for (a, b) in zip(L.tableColumns, L.tableColumns.dropFirst()) {
                XCTAssertLessThan(a.x + a.width, b.x, "\(ratio)")
            }
            XCTAssertLessThanOrEqual((L.tableColumns.last!.x + L.tableColumns.last!.width), l.mapRect.minX, "\(ratio)")
        }
        XCTAssertEqual(L(ratio: .portrait).photoBottom, 900)
    }

    func testCoverLayoutKeepsEverythingInsideAndFadeEndsOnBlack() {
        typealias C = ShareCardMap.CoverLayout
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let l = C(ratio: ratio)
            XCTAssertGreaterThan(l.fadeTop, 0, "\(ratio)")
            XCTAssertLessThan(l.placeTop + C.placeFontSize, l.subPlaceTop + 12, "\(ratio) 地名が市区町村に掛かる")
            XCTAssertLessThan(l.subPlaceTop, l.photoBottom, "\(ratio)")
            // 地図は右端が写真の右端。左の地名の列と重ならない
            XCTAssertEqual(l.mapRect.maxX, C.contentRight, "\(ratio)")
            XCTAssertLessThanOrEqual(C.contentLeft + C.leftColumnWidth, l.mapRect.minX + 40, "\(ratio)")
            // 撮影者の行・撮影情報は、黒の上（写真の下端より下）で、下の余白 60 より上に収まる
            XCTAssertGreaterThanOrEqual(l.authorTop, l.photoBottom, "\(ratio)")
            XCTAssertLessThanOrEqual(l.authorTop + 64, l.base - 60 + 14, "\(ratio)")
            XCTAssertLessThanOrEqual(l.exifTop + 30 + 24, l.base - 60 + 14, "\(ratio)")
            // 撮影情報は撮影者の右・地図の左
            XCTAssertLessThan(C.exifX + C.exifWidth, l.mapRect.minX, "\(ratio)")
        }
        XCTAssertEqual(C(ratio: .portrait).photoBottom, 1100)
        XCTAssertEqual(C(ratio: .portrait).mapRect, CGRect(x: 760, y: 880, width: 260, height: 300))
    }

    func testAllStylesAreOfferedInOrder() {
        // 共有画面の切り替え（帯・フェード・表紙・展示札）の元になる型。保存済みの値が消えない（rawValue を変えない）
        XCTAssertEqual(SignatureShareCardRenderer.Style.allCases.map(\.rawValue),
                       ["band", "fade", "label", "cover"])
    }

    // MARK: - 残す島

    private func focusBounds(_ name: String, _ latitude: Double, _ longitude: Double) throws
        -> (bounds: ShareCardMap.Bounds, zoom: Double) {
        let shape = try country(name)
        // 島選びと縮尺の確認は、枠の寸法の変更に引きずられないよう固定の枠（旧 290×250）で測る
        let rect = CGRect(x: 722, y: 947, width: 290, height: 250)
        let focused = try XCTUnwrap(ShareCardMap.focus(shape, latitude: latitude, longitude: longitude, in: rect))
        // 前の描き方（国の全体を 250×185 に収める）と比べた縮尺
        let rings = ShareCardMap.unwrap(shape.r, aroundLongitude: longitude)
        let whole = ShareCardMap.Projection(bounds: try XCTUnwrap(ShareCardMap.Bounds(rings)),
                                            rect: CGRect(x: 0, y: 0, width: 250, height: 185))
        return (focused.projection.bounds, focused.projection.scale / whole.scale)
    }

    func testJapanMainlandDropsRemoteIslands() throws {
        // 山梨（0.5° に丸めたピン）。小笠原（27°N）・沖ノ鳥島（20°N）・南鳥島（154°E）を外す
        let (bounds, zoom) = try focusBounds("Japan", 35.5, 138.5)
        XCTAssertGreaterThan(bounds.south, 30, "小笠原・沖縄が残っている")
        XCTAssertLessThan(bounds.east, 146.5, "南鳥島が残っている")
        XCTAssertGreaterThan(bounds.north, 45, "北海道が外れている")
        XCTAssertLessThan(bounds.west, 130, "九州が外れている")
        XCTAssertEqual(zoom, 1.93, accuracy: 0.03, "板（290×245）では 1.88。枠を測って 250 にした分")
    }

    func testOkinawaKeepsOkinawa() throws {
        // 那覇（26.21, 127.68）は丸めると海の上（26.0, 127.5）。いちばん近い島＝沖縄本島が残る
        let pin = try XCTUnwrap(SignatureShareCardRenderer.approximateShareCoordinate(
            Photo.Coords(lat: 26.2124, lng: 127.6809)))
        let (bounds, zoom) = try focusBounds("Japan", pin.latitude, pin.longitude)
        XCTAssertLessThanOrEqual(bounds.south, 26.2)
        XCTAssertLessThanOrEqual(bounds.west, 127.7)
        XCTAssertGreaterThan(bounds.north, 45, "本土（一番大きい陸）も残す")
        XCTAssertEqual(zoom, 1.51, accuracy: 0.03)
    }

    func testOgasawaraKeepsOgasawara() throws {
        let (bounds, _) = try focusBounds("Japan", 27.0, 142.0)
        XCTAssertLessThanOrEqual(bounds.south, 27.0, "撮った小笠原が外れている")
        XCTAssertGreaterThanOrEqual(bounds.east, 142.1)
        XCTAssertLessThan(bounds.east, 146.5, "南鳥島は 60km より遠い")
    }

    func testFranceDropsOverseasDepartments() throws {
        let (bounds, zoom) = try focusBounds("France", 48.5, 2.5)
        XCTAssertGreaterThan(bounds.west, -6)
        XCTAssertLessThan(bounds.east, 10)
        XCTAssertGreaterThan(bounds.south, 41)
        XCTAssertLessThan(bounds.north, 52)
        XCTAssertEqual(zoom, 12.98, accuracy: 0.2)
    }

    func testHawaiiKeepsHawaiiAndMainland() throws {
        let (bounds, _) = try focusBounds("United States of America", 21.5, -158.0)
        XCTAssertLessThanOrEqual(bounds.west, -158, "撮ったハワイが外れている")
        XCTAssertLessThan(bounds.south, 21.5)
        XCTAssertGreaterThan(bounds.east, -70, "一番大きい陸（本土）も残す")
        XCTAssertLessThan(bounds.north, 50, "アラスカは 60km より遠い")
    }

    func testUSMainlandDropsHawaiiAndAlaska() throws {
        let (bounds, _) = try focusBounds("United States of America", 40.5, -74.0)
        XCTAssertGreaterThan(bounds.west, -125)
        XCTAssertGreaterThan(bounds.south, 24)
        XCTAssertLessThan(bounds.north, 50)
    }

    func testItalyKeepsSicilyAndSardinia() throws {
        let (bounds, zoom) = try focusBounds("Italy", 41.5, 12.5)
        XCTAssertLessThan(bounds.south, 37, "シチリア")
        XCTAssertLessThan(bounds.west, 8.5, "サルデーニャ")
        XCTAssertEqual(zoom, 1.38, accuracy: 0.03)
    }

    func testFocusAcrossAntimeridianStaysNarrow() throws {
        // フィジーは ±180° をまたぐ。開いて 360° 幅にならない
        let (bounds, _) = try focusBounds("Fiji", -16.5, 179.8)
        XCTAssertLessThan(bounds.east - bounds.west, 10)
        let (russia, _) = try focusBounds("Russia", 66.0, -179.0)
        XCTAssertLessThan(russia.east - russia.west, 200)
    }

    // MARK: - 塗る県

    func testPrefectureNameFromShareCardLocation() {
        XCTAssertEqual(ShareCardMap.prefectureName(in: "千葉県（市原市）"), "千葉県")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "山梨県（山中湖村）"), "山梨県")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "北海道（札幌市）"), "北海道")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "東京都"), "東京都")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "清水寺 (京都府, 京都市)"), "京都府")
        XCTAssertNil(ShareCardMap.prefectureName(in: "Florence, Italy"))
        XCTAssertNil(ShareCardMap.prefectureName(in: "Versailles, Île-de-France, フランス"))
        XCTAssertNil(ShareCardMap.prefectureName(in: "イヴリーヌ県（フランス）"), "海外の「県」は塗らない")
        XCTAssertNil(ShareCardMap.prefectureName(in: "千葉"), "県名がそのまま無ければ塗らない")
        XCTAssertNil(ShareCardMap.prefectureName(in: nil))
    }

    func testBundledPrefecturesMatchRegionList() throws {
        let prefectures = try Self.shapes("japan-prefectures")
        XCTAssertEqual(prefectures.map(\.n), RegionList.prefectures)
        let yamanashi = try XCTUnwrap(prefectures.first { $0.n == "山梨県" })
        // 山中湖（35.42, 138.87）が山梨県の輪の中
        XCTAssertTrue(yamanashi.r.contains {
            ShareCardMap.ringContains($0, longitude: 138.87, latitude: 35.42)
        })
        let okinawa = try XCTUnwrap(prefectures.first { $0.n == "沖縄県" })
        XCTAssertFalse(okinawa.r.contains {
            ShareCardMap.ringContains($0, longitude: 138.87, latitude: 35.42)
        })
    }

    func testPrefectureShapeRequiresNearbyPin() throws {
        let prefectures = try Self.shapes("japan-prefectures")
        XCTAssertEqual(ShareCardMap.prefectureShape(named: "千葉県", among: prefectures,
                                                    latitude: 35.5, longitude: 140.0)?.n, "千葉県")
        // 文字は千葉県なのにピンが沖縄: 食い違うので塗らない
        XCTAssertNil(ShareCardMap.prefectureShape(named: "千葉県", among: prefectures,
                                                  latitude: 26.0, longitude: 127.5))
        XCTAssertNil(ShareCardMap.prefectureShape(named: nil, among: prefectures,
                                                  latitude: 35.5, longitude: 140.0))
    }


    func testEnglishPrefectureNamesAreFilled() throws {
        // 英語の環境の日本の写真でも県を塗る（2026-11-04 確かめ役の指摘）
        XCTAssertEqual(ShareCardMap.prefectureName(in: "Kyoto, (Higashiyama)"), "京都府")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "Miyagi Prefecture"), "宮城県")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "Hyōgo Prefecture"), "兵庫県")
        XCTAssertEqual(ShareCardMap.prefectureName(in: "Tokyo"), "東京都")
        XCTAssertNil(ShareCardMap.prefectureName(in: "Paris, (Versailles)"))
        XCTAssertEqual(ShareCardMap.englishPrefectures.count, RegionList.prefectures.count)
    }

    // MARK: - 撮影地の2行（2026-11-04 owner）

    private func lines(_ raw: String?) -> [String] {
        LocationMatch.shareCardPlace(raw)?.lines ?? []
    }

    func testJapanPlaceIsPrefectureThenCity() {
        XCTAssertEqual(lines("月崎, 大多喜里見線, 市原市, 千葉県, 290-0000, 日本"), ["千葉県", "（市原市）"])
        XCTAssertEqual(lines("山中湖村, 山梨県, 日本"), ["山梨県", "（山中湖村）"], "座標からの自動入力の形")
        XCTAssertEqual(lines("富士山, 静岡県, 日本"), ["静岡県"], "市区町村が無ければ1行")
        XCTAssertEqual(lines("東京タワー, 港区, 東京都, 105-0011, 日本"), ["東京都", "（港区）"])
        XCTAssertEqual(lines("札幌市時計台, 中央区, 札幌市, 北海道, 060-0001, 日本"), ["北海道", "（札幌市）"])
        XCTAssertEqual(lines("横浜赤レンガ倉庫, 中区, 横浜市, 神奈川県, 231-0001, 日本"), ["神奈川県", "（横浜市）"])
        XCTAssertEqual(lines("北海道"), ["北海道"])
        XCTAssertEqual(lines("千葉県（市原市）"), ["千葉県", "（市原市）"], "shareCardDisplay の形も割る")
        XCTAssertEqual(lines("宮城県, 白石市, 蔵王キツネ村"), ["宮城県", "（白石市）"], "人が大きい順に打った形")
    }

    func testJapanPlaceInEnglish() {
        XCTAssertEqual(lines("Kiyomizu-dera, 1, Kiyomizu, Higashiyama Ward, Kyoto, Kyoto Prefecture, 605-0862, Japan"),
                       ["Kyoto", "(Higashiyama)"])
        XCTAssertEqual(lines("Zao Fox Village, Minamizao Shichikashuku Line, Fukuoka Hachimiya, Shiroishi, Miyagi Prefecture, 989-0733, Japan"),
                       ["Miyagi", "(Shiroishi)"])
        XCTAssertEqual(lines("Tokyo, Japan"), ["Tokyo"])
    }

    func testOverseasPlaceIsCountryThenSmallestName() {
        XCTAssertEqual(lines("ヴェルサイユ, Versailles, Yvelines, イル＝ド＝フランス地域圏, フランス・メトロポリテーヌ, 78000, フランス"),
                       ["フランス", "（ヴェルサイユ）"])
        XCTAssertEqual(lines("ニューヨーク, ニューヨーク州, アメリカ合衆国"), ["アメリカ合衆国", "（ニューヨーク）"])
        XCTAssertEqual(lines("ローマ, ラツィオ州, イタリア"), ["イタリア", "（ローマ）"])
        XCTAssertEqual(lines("ソウル, 韓国"), ["韓国", "（ソウル）"])
        // ラテン文字だけなら半角の括弧（中身との間に空白を入れない）
        XCTAssertEqual(lines("Versailles, Yvelines, Île-de-France, Metropolitan France, 78000, France"),
                       ["France", "(Versailles)"])
        XCTAssertEqual(lines("Paris, Île-de-France, France"), ["France", "(Paris)"])
        // 人が打った短い文字・大きい順の英文は1行のまま
        XCTAssertEqual(lines("山中湖"), ["山中湖"])
        XCTAssertEqual(lines("Paris"), ["Paris"])
        XCTAssertEqual(lines("オペラ・ガルニエ（パリ）"), ["オペラ・ガルニエ（パリ）"])
        XCTAssertEqual(lines("Miyagi Prefecture, Shiroishi, Zao Fox Village"),
                       ["Miyagi Prefecture, Shiroishi, Zao Fox Village"])
        XCTAssertEqual(lines(nil), [])
        XCTAssertEqual(lines("  "), [])
    }

    /// Web の app/data/photos.json の 30 件の `location`（2026-11-04 に写した実データ）
    func testAllWebSampleLocations() {
        let cases: [(String?, [String])] = [
            ("山中湖", ["山中湖"]), ("山中湖", ["山中湖"]), ("バルセロナ", ["バルセロナ"]), ("パリ", ["パリ"]),
            ("大阪", ["大阪"]), ("東京", ["東京"]), ("東京", ["東京"]), ("フィンランド", ["フィンランド"]),
            (nil, []), ("福岡", ["福岡"]), ("フランス", ["フランス"]), (nil, []), (nil, []),
            ("フランス ヴェルサイユ", ["フランス ヴェルサイユ"]), ("パリ, フランス", ["フランス", "（パリ）"]),
            ("フランス ヴェルサイユ", ["フランス ヴェルサイユ"]), ("北海道", ["北海道"]),
            ("オペラ・ガルニエ（パリ）", ["オペラ・ガルニエ（パリ）"]),
            ("香川県 観音寺市 高屋神社", ["香川県", "（観音寺市）"]),
            (nil, []), (nil, []), (nil, []), (nil, []), (nil, []), (nil, []), (nil, []), (nil, []), (nil, []), (nil, []),
            ("茨城県 ひたちなか市 国営ひたち海浜公園", ["茨城県", "（ひたちなか市）"]),
        ]
        XCTAssertEqual(cases.count, 30)
        for (raw, expected) in cases {
            XCTAssertEqual(lines(raw), expected, raw ?? "nil")
        }
    }

    // MARK: - 字の収め方

    /// 和文は1字＝字の大きさ、欧文は半分で測る（Linux には字の形が無いため）
    private func measure(_ text: String, _ size: CGFloat) -> CGFloat {
        text.reduce(CGFloat(0)) { width, character in
            width + (character.isASCII || "Îé".contains(character) ? size * 0.5 : size)
        }
    }

    func testPlaceLinesShareOneSizeAndNeverWrap() {
        let fitted = ShareCardText.fitLines(["山梨県", "（山中湖村）"], maxWidth: 140, preferredSize: 26,
                                            minimumSize: 18.72, measure: measure)
        // 2行目（6字）が入る 23 に、1行目もそろえる
        XCTAssertEqual(fitted.size, 23)
        XCTAssertEqual(fitted.lines, ["山梨県", "（山中湖村）"])
        XCTAssertFalse(fitted.truncated)
    }

    func testLongOverseasCityKeepsClosingBracket() {
        let fitted = ShareCardText.fitLines(["フランス", "（サン＝ジェルマン＝アン＝レー）"], maxWidth: 140,
                                            preferredSize: 26, minimumSize: 18.72, measure: measure)
        XCTAssertTrue(fitted.truncated)
        XCTAssertEqual(fitted.size, 18.72)
        XCTAssertEqual(fitted.lines[0], "フランス")
        XCTAssertTrue(fitted.lines[1].hasPrefix("（サン"), fitted.lines[1])
        XCTAssertTrue(fitted.lines[1].hasSuffix("…）"), fitted.lines[1])
        XCTAssertLessThanOrEqual(measure(fitted.lines[1], fitted.size), 140)
        let latin = ShareCardText.fitLines(["France", "(Saint-Germain-en-Laye-sur-Seine)"], maxWidth: 140,
                                           preferredSize: 26, minimumSize: 18.72, measure: measure)
        XCTAssertTrue(latin.lines[1].hasSuffix("…)"), latin.lines[1])
    }

    func testPlaceTwoLinesFitInsideRowAndCenterOnAvatar() {
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.Layout(ratio: ratio)
            let top = layout.rowCenterY - ShareCardMap.Layout.placeHeight / 2
            let bottom = layout.rowCenterY + ShareCardMap.Layout.placeHeight / 2
            // 撮影者の段（アバターの高さ）の中に収まり、区切り線に当たらない
            XCTAssertGreaterThanOrEqual(top, layout.rowTop, "\(ratio)")
            XCTAssertLessThanOrEqual(bottom, layout.rowTop + ShareCardMap.Layout.avatarSize, "\(ratio)")
            XCTAssertLessThan(bottom, layout.separatorY, "\(ratio)")
        }
    }

    func testSegmentsBreakOnlyAtSeparators() {
        XCTAssertEqual(ShareCardText.segments("Versailles, Île-de-France, フランス"),
                       ["Versailles, ", "Île-de-France, ", "フランス"])
        XCTAssertEqual(ShareCardText.segments("清水寺 (京都府, 京都市)"), ["清水寺 ", "(京都府, 京都市)"],
                       "括弧の中では折らない")
        XCTAssertEqual(ShareCardText.segments("東京・浅草、雷門"), ["東京・", "浅草、", "雷門"])
        // 「/」は後ろが空白のときだけ（「f/2.8」で折らない）
        XCTAssertEqual(ShareCardText.segments("NIKKOR Z 24-70mm f/2.8 S"),
                       ["NIKKOR ", "Z ", "24-70mm ", "f/2.8 ", "S"])
        XCTAssertEqual(ShareCardText.segments("A / B"), ["A ", "/ ", "B"])
    }

    func testEquipmentFitShrinksWithoutMidWordBreak() {
        let fitted = ShareCardText.fit("Hasselblad XCD 35-100E f/2.8-4 Zoom Lens", maxWidth: 120,
                                       preferredSize: 22, minimumSize: 7, step: 0.5,
                                       maxLines: { _ in 3 }, measure: measure)
        XCTAssertFalse(fitted.truncated)
        XCTAssertEqual(fitted.lines.joined(separator: " ").split(separator: " "),
                       "Hasselblad XCD 35-100E f/2.8-4 Zoom Lens".split(separator: " "))
        for line in fitted.lines { XCTAssertLessThanOrEqual(measure(line, fitted.size), 120) }
    }

    /// 島選びの所要時間（輪の多い国）。Mac の記録に出す（2026-11-04 確かめ役の指摘）
    func testFocusTimeForCountriesWithManyIslands() throws {
        for (name, latitude, longitude) in [("Canada", 45.5, -73.5), ("Russia", 55.5, 37.5),
                                           ("United States of America", 40.5, -74.0),
                                           ("Indonesia", -6.0, 107.0)] {
            let shape = try country(name)
            let start = Date()
            _ = ShareCardMap.focus(shape, latitude: latitude, longitude: longitude,
                                   in: ShareCardMap.Layout(ratio: .portrait).mapRect)
            let seconds = Date().timeIntervalSince(start)
            print("SHARECARD-TIME \(name) rings=\(shape.r.count) seconds=\(String(format: "%.3f", seconds))")
            XCTAssertLessThan(seconds, 2, "\(name) の島選びが重い")
        }
    }

    #if !os(Linux)
    /// 2026-11-04 owner「文字とアイコン中央がずれてる」: 大文字の高さの中心がマークの中心にそろう
    /// （UIKit の字の寸法を使うので、Linux の模型では流さない）
    func testWordmarkCapHeightCenterMatchesMarkCenter() {
        let markMid = ShareCardMap.Layout.headerMarkY + ShareCardMap.Layout.headerMarkSize / 2
        let font = SignatureShareCardRenderer.wordmarkFont()
        let top = SignatureShareCardRenderer.wordmarkTop(markMidY: markMid)
        let capCenter = top + font.ascender - font.capHeight / 2
        XCTAssertEqual(capCenter, markMid, accuracy: 0.01)
    }
    #endif

    /// 上の帯（高さ 124）。マークの中心・区切り線の中心・一文の中心がどれも、額縁の内側と写真の真ん中（帯の中心）にそろい、
    /// 中身の上下の余白が同じ 26。額縁にも写真にも当たらない
    func testHeaderBandCentersItsContentAndKeepsItInside() {
        typealias L = ShareCardMap.Layout
        XCTAssertEqual(L.header, 124)
        let inner = L.frameInset + L.frameWidth
        XCTAssertEqual(L.headerCenter, (inner + L.header) / 2, accuracy: 0.001)
        XCTAssertEqual(L.headerMarkY + L.headerMarkSize / 2, L.headerCenter, accuracy: 0.001)
        let dividerTop = L.headerCenter - 29, dividerBottom = L.headerCenter + 28
        XCTAssertEqual(dividerTop - inner, 26, accuracy: 1, "額縁の内側から 26")
        XCTAssertEqual(L.header - dividerBottom, 26, accuracy: 1.5, "写真まで 26")
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let layout = ShareCardMap.Layout(ratio: ratio)
            XCTAssertEqual(layout.photoRect.minY, L.header, "\(ratio) 写真は帯の下から")
            XCTAssertGreaterThan(layout.photoRect.height, 0)
        }
    }

    // MARK: - 撮影情報の罫（2026-11-12）

    /// 撮影情報の列の間の縦罫は、両側の列に字があるときだけ。無い写真では1本も描かない
    /// （run 1194 の共有カードで、一番下に中身の無い段が縦の線だけ残っていた）
    func testInfoDividersOnlyBetweenFilledColumns() {
        XCTAssertEqual(ShareCardMap.infoDividerIndices(filled: [false, false, false]), [])
        XCTAssertEqual(ShareCardMap.infoDividerIndices(filled: [true, true, true]), [0, 1])
        XCTAssertEqual(ShareCardMap.infoDividerIndices(filled: [true, false, false]), [])
        XCTAssertEqual(ShareCardMap.infoDividerIndices(filled: [false, true, false]), [])
        XCTAssertEqual(ShareCardMap.infoDividerIndices(filled: [false, false, true]), [])
        XCTAssertEqual(ShareCardMap.infoDividerIndices(filled: [true, true, false]), [0])
        XCTAssertEqual(ShareCardMap.infoDividerIndices(filled: [false, true, true]), [1])
        // 真ん中が空なら、空の欄を囲む線は描かない
        XCTAssertEqual(ShareCardMap.infoDividerIndices(filled: [true, false, true]), [])
        XCTAssertEqual(ShareCardMap.infoDividerIndices(filled: []), [])
        // 帯の型の縦罫の x は、上の段の縦の線と、撮影値の列の 12 手前
        let L = ShareCardMap.Layout.self
        XCTAssertEqual(L.infoDividerXs, [L.rowDividerX, L.exposureX - 12])
    }
}
