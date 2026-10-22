import XCTest
@testable import JourneyPhoto

/// 部屋の下の板（2026-10-22 owner の実機 1.1.37「操作感も悪い」）: 板の高さの分け方・模様替えの見本と下のボタン
final class CamperRoomSheetTests: XCTestCase {

    // MARK: 板の高さ

    /// 板は中身が要るだけの高さを取り、部屋の絵は残り全部。owner の実機は「部屋の絵 56%・板は残り」の決め打ちで、
    /// 模様替えの板（要る高さ 約 330）が 240 ほどに押し込まれ、見本の名前が説明と重なった
    func testPanelGetsWhatItNeeds() {
        // iPhone 15 Pro: 852 − 安全域 93 − 見出し 48 − 部屋のタブ 44 ≈ 667
        let total = 667.0
        for need in [230.0, 330.0, 400.0] {
            let fit = CamperRoomSheetFit.split(total: total, need: need)
            XCTAssertEqual(fit.panel, need, accuracy: 0.001, "要る高さ \(need) の板が削られる")
            XCTAssertEqual(fit.scene + fit.panel, total, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(fit.scene, CamperRoomSheetFit.minScene)
            XCTAssertFalse(CamperRoomSheetFit.scrolls(need: need, panel: fit.panel))
        }
        // 前の決め方（部屋の絵 = min(460, max(300, 画面 × 0.56))）では、模様替えの板が要る高さに足りなかった
        let old = min(460, max(300, (total + 92) * 0.56))
        XCTAssertLessThan(total - old, 330, "前の決め方の再現が違う")
    }

    /// 大きい文字で中身が伸びても、部屋の絵に最低限を残し、板の方を送る。小さい画面でも板は半分近く取れる
    func testLargeTextScrollsThePanelAndKeepsTheRoom() {
        let total = 667.0
        let fit = CamperRoomSheetFit.split(total: total, need: 1_100)
        XCTAssertEqual(fit.scene, CamperRoomSheetFit.minScene, accuracy: 0.001)
        XCTAssertTrue(CamperRoomSheetFit.scrolls(need: 1_100, panel: fit.panel))
        // iPhone SE（667 − 安全域 20 − 見出し・タブ 92 ≈ 555）・アクセシビリティの大きさ
        let small = CamperRoomSheetFit.split(total: 420, need: 1_100)
        XCTAssertGreaterThanOrEqual(small.panel, 420 * CamperRoomSheetFit.minPanelShare - 0.001)
        XCTAssertEqual(small.scene + small.panel, 420, accuracy: 0.001)
        // 写真を飾る板は一覧を中で送るので、決まった割合
        let photos = CamperRoomSheetFit.split(total: total, need: 0, photos: true)
        XCTAssertEqual(photos.panel, total * CamperRoomSheetFit.photosShare, accuracy: 0.001)
    }

    // MARK: 模様替え

    /// 持っていない柄も空の札にしない: 名前・鍵（いま / 要る数）・近日を持ち、部品の id で外まわりの図鑑へ行ける
    func testStyleChoicesShowLockedPatterns() throws {
        var stats = CamperStats()
        stats.posts = 12
        let starter = CamperCatalog.owned(stats)
        let walls = CamperRoomStyleBoard.choices(.wall, partsOwned: starter, stats: stats)
        XCTAssertEqual(walls.map(\.key), CamperCatalog.parts(.wallWood).map(\.key))
        XCTAssertEqual(walls.first?.state, .owned)
        let birch = try XCTUnwrap(walls.first { $0.key == "plywood_birch" })
        XCTAssertEqual(birch.state, .locked(have: 12, need: 50))
        XCTAssertEqual(birch.progressText, "12 / 50")
        XCTAssertEqual(birch.fraction, 12.0 / 50.0, accuracy: 0.0001)
        XCTAssertEqual(birch.partId, "wall_wood.plywood_birch")
        XCTAssertEqual(birch.name, "樺の合板", "持っていない柄も名前を出す（「まだ」にしない）")
        let herringbone = try XCTUnwrap(walls.first { $0.key == "herringbone" })
        XCTAssertEqual(herringbone.state, .soon)
        XCTAssertNotNil(herringbone.progressText)
        // 床も同じ。カーテンと灯りは最初から全部選べる（部品の id は無い）
        XCTAssertTrue(CamperRoomStyleBoard.choices(.floor, partsOwned: starter, stats: stats).contains { !$0.owned })
        for tab in [CamperRoomStyleTab.curtain, .light] {
            let colors = CamperRoomStyleBoard.choices(tab, partsOwned: [], stats: stats)
            XCTAssertGreaterThan(colors.count, 1)
            XCTAssertTrue(colors.allSatisfy { $0.owned && $0.partId == nil && $0.progressText == nil })
        }
        // 集め終えたら持っている札になる
        var many = CamperStats()
        many.posts = 60
        let birchOwned = CamperRoomStyleBoard.choices(.wall, partsOwned: CamperCatalog.owned(many), stats: many).first { $0.key == "plywood_birch" }
        XCTAssertEqual(birchOwned?.state, .owned)
    }

    /// 下のボタン: 変えていなければ「閉じる」（「これにする」を光らせない）。変えたら「元に戻す」と「これにする」
    func testStyleFooterOnlyOffersUseThisAfterAChange() {
        let start = CamperRoomStyle()
        XCTAssertEqual(CamperRoomStyleBoard.footer(entry: start, now: start), .close)
        XCTAssertEqual(CamperRoomStyleBoard.footer(entry: nil, now: start), .close)
        for tab in CamperRoomStyleTab.allCases {
            let other = CamperRoomStyleBoard.choices(tab, partsOwned: CamperCatalog.owned(CamperStats()), stats: CamperStats())
                .map(\.key).first { $0 != CamperRoomStyleBoard.key(start, tab) } ?? "x"
            let changed = CamperRoomStyleBoard.with(start, tab, key: other)
            XCTAssertEqual(CamperRoomStyleBoard.key(changed, tab), other, tab.rawValue)
            XCTAssertEqual(CamperRoomStyleBoard.footer(entry: start, now: changed), .revertOrKeep, tab.rawValue)
            // 元の柄に戻したら、また「閉じる」
            let back = CamperRoomStyleBoard.with(changed, tab, key: CamperRoomStyleBoard.key(start, tab))
            XCTAssertEqual(CamperRoomStyleBoard.footer(entry: start, now: back), .close, tab.rawValue)
        }
    }

    /// 札の説明: 灯りは夜にして見せると言う。鍵の柄がある札だけ「試せる」と言う
    func testStyleNotes() {
        XCTAssertTrue(CamperRoomStyleBoard.note(.light, hasLocked: false).contains("夜"))
        XCTAssertTrue(CamperRoomStyleBoard.note(.wall, hasLocked: true).contains("試せる"))
        XCTAssertFalse(CamperRoomStyleBoard.note(.wall, hasLocked: false).contains("試せる"))
        XCTAssertEqual(CamperRoomStyleTab.allCases.map(\.name), ["壁紙", "床", "カーテン", "灯り"])
        XCTAssertEqual(CamperRoomStyleTab.wall.partCategory, .wallWood)
        XCTAssertNil(CamperRoomStyleTab.light.partCategory)
    }

    // MARK: 部屋の絵の初めの向き

    /// 初めの向きは、見える部屋（奥と横の壁は天井まで・手前の切った壁は切った高さ）が絵の真ん中に、縁を残して収まる。
    /// owner の実機（2026-10-22）は部屋の絵が上へ押し出されて切れ、下に大きな黒い空きがあった
    func testOverviewFitsAndCentersTheRoom() throws {
        let sizes = [CGSize(width: 390, height: 250), CGSize(width: 390, height: 330), CGSize(width: 390, height: 430),
                     CGSize(width: 390, height: 520), CGSize(width: 430, height: 380)]
        var oldCut = 0
        for kind in CamperRoomKind.rooms(.trailer) {
            let layout = CamperRoomLayout.make(kind, stage: .trailer)
            for vp in sizes {
                let w = Double(vp.width), h = Double(vp.height)
                let cam = CamperRoomCamera.overview(layout, viewport: vp)
                let box = try XCTUnwrap(cam.shellBox(layout, viewport: vp))
                let label = "\(kind) \(Int(w))×\(Int(h))"
                XCTAssertGreaterThanOrEqual(Double(box.minY), h * 0.04, "\(label): 上が切れる・縁が無い（\(box)）")
                XCTAssertLessThanOrEqual(Double(box.maxY), h * 0.96, "\(label): 下が切れる（\(box)）")
                XCTAssertGreaterThanOrEqual(Double(box.minX), w * 0.04, "\(label): 左が切れる（\(box)）")
                XCTAssertLessThanOrEqual(Double(box.maxX), w * 0.96, "\(label): 右が切れる（\(box)）")
                XCTAssertEqual(Double(box.minY), h - Double(box.maxY), accuracy: h * 0.03, "\(label): 上か下へ寄っている（\(box)）")
                XCTAssertEqual(Double(box.minX), w - Double(box.maxX), accuracy: w * 0.03, "\(label): 左か右へ寄っている（\(box)）")
                // 向き・見下ろしは変えない（指で回す・寄るの始まりは同じ）
                XCTAssertEqual(cam.yaw, CamperRoomCamera.overview(layout).yaw)
                XCTAssertEqual(cam.pitch, CamperRoomCamera.overview(layout).pitch)
                let old = try XCTUnwrap(CamperRoomCamera.overview(layout).shellBox(layout, viewport: vp))
                if old.minY < 0 || old.maxX > vp.width || old.minX < 0 { oldCut += 1 }
            }
        }
        XCTAssertGreaterThan(oldCut, 0, "前の初めの向きで切れる絵の再現が無い")
        // 寄った所から二度押しで戻る先は、絵に合わせた向き
        let layout = CamperRoomLayout.make(.car, stage: .camper)
        let home = CamperRoomCamera.overview(layout, viewport: CGSize(width: 390, height: 430))
        // 絵に合わせた初めの向きから二度押しすると、本当に寄る（初めの倍率が寄った扱いの線より下）
        XCTAssertLessThan(home.zoom, CamperRoomCamera.doubleTapZoom * 0.75)
        let near = home.doubleTapped(floor: CV3(40, 0, 30), layout: layout, home: home)
        XCTAssertNotEqual(near, home)
        XCTAssertEqual(near.zoom, CamperRoomCamera.doubleTapZoom, accuracy: 0.001)
        XCTAssertEqual(near.doubleTapped(floor: nil, layout: layout, home: home), home)
    }

    // MARK: 模様替えの途中の状態

    private func lockedBirch() throws -> CamperRoomStyleChoice {
        try XCTUnwrap(CamperRoomStyleBoard.choices(.wall, partsOwned: CamperCatalog.owned(CamperStats()), stats: CamperStats())
            .first { !$0.owned && $0.key == "plywood_birch" })
    }

    /// 見本は映すだけで覚えない。見本をやめると元の柄。見本だけでは「これにする」を光らせない
    func testTrialIsShownButNotSaved() throws {
        let layout = CamperRoomLayout.make(.car, stage: .camper)
        let editor = CamperRoomEditor(doc: CamperRoomRules.starterDocument(layout), layout: layout)
        let saved = editor.doc.style
        var session = CamperRoomStyleSession()
        session.begin(saved)
        session.trial = try lockedBirch()
        XCTAssertEqual(session.shown(saved, tab: .wall).wall, "plywood_birch", "見本が部屋に映らない")
        XCTAssertEqual(editor.doc.style, saved, "見本で覚えた柄が変わった")
        XCTAssertEqual(session.footer(now: editor.doc.style), .close, "見本だけで「これにする」が出る")
        // 床の札では、壁の見本の鍵で床を書き換えない（札ごとに重ねる）
        XCTAssertEqual(session.shown(saved, tab: .floor).wall, saved.wall)
        session.trial = nil
        XCTAssertEqual(session.shown(saved, tab: .wall), saved, "見本をやめても元に戻らない")
    }

    /// 部屋を替えたら、前の部屋の見本と入った時の柄を持ち越さない（確かめ役 2026-10-22: 部屋 B で何も触らないのに
    /// 「これにする／元に戻す」が光り、「元に戻す」で部屋 A の柄が B に書かれた）
    func testRoomChangeStartsTheStyleSessionOver() throws {
        var a = CamperRoomStyle()
        a.curtain = "indigo"
        var b = CamperRoomStyle()
        b.wall = "dark_walnut"
        var session = CamperRoomStyleSession()
        session.begin(CamperRoomStyle())
        // 部屋 A で柄を変えた（変えた後なので「元に戻す・これにする」）
        XCTAssertEqual(session.footer(now: a), .revertOrKeep)
        session.trial = try lockedBirch()
        // 部屋 B へ
        session.roomChanged(to: b)
        XCTAssertNil(session.trial, "前の部屋の見本が残る")
        XCTAssertEqual(session.entry, b, "入った時の柄が前の部屋のまま")
        XCTAssertEqual(session.footer(now: b), .close, "部屋 B で何も触らないのに「これにする」")
        // 模様替えの外で部屋を替えても、模様替えは始まらない
        var outside = CamperRoomStyleSession()
        outside.roomChanged(to: b)
        XCTAssertFalse(outside.active)
        XCTAssertNil(outside.entry)
        session.end()
        XCTAssertFalse(session.active)
        XCTAssertNil(session.trial)
    }
}
