import XCTest
@testable import JourneyPhoto

/// 旅のトランクの次の版（2026-10-18・板「旅のトランク」）: 回したときの面・ふたを開ける・中身
final class TrunkInsideTests: XCTestCase {

    private func look(_ model: TrunkModel, posts: Int = 50) -> TrunkLook {
        TrunkLooks.look(model, stage: TrunkAging.stage(posts: posts))
    }

    private func badge(_ key: String, _ tier: Int = 1) -> EarnedBadge {
        EarnedBadge(key: key, tier: tier, at: "2026-10-01T09:00:00Z")
    }

    // MARK: - 回したときの面（板 TrunkFaces）

    /// 寸法は板の注記どおり（胴 360×268・側面 86×268・上下 360×86）
    func testFaceSizes() {
        XCTAssertEqual(TrunkFaces.size(.left).w, 86)
        XCTAssertEqual(TrunkFaces.size(.left).h, 268)
        XCTAssertEqual(TrunkFaces.size(.right).w, 86)
        XCTAssertEqual(TrunkFaces.size(.top).w, 360)
        XCTAssertEqual(TrunkFaces.size(.top).h, 86)
        XCTAssertEqual(TrunkFaces.size(.bottom).h, 86)
        XCTAssertEqual(TrunkFaces.size(.back).w, 360)
        XCTAssertEqual(TrunkFaces.size(.back).h, 268)
        XCTAssertEqual(TrunkFaces.depth / TrunkLooks.bodyWidth, 0.24, accuracy: 0.005, "厚みは横の 0.24（回す箱と同じ）")
    }

    /// ふたの合わせ目は正面から 26。展開図の向き（側面は正面の辺が内側・上は下・底は上）。背面には無い
    func testSeamFollowsTheNet() {
        XCTAssertEqual(TrunkFaces.seam(.left)?.position, 60)
        XCTAssertEqual(TrunkFaces.seam(.left)?.horizontal, false)
        XCTAssertEqual(TrunkFaces.seam(.right)?.position, 26)
        XCTAssertEqual(TrunkFaces.seam(.top)?.position, 60)
        XCTAssertEqual(TrunkFaces.seam(.top)?.horizontal, true)
        XCTAssertEqual(TrunkFaces.seam(.bottom)?.position, 26)
        XCTAssertNil(TrunkFaces.seam(.back))
        XCTAssertEqual(TrunkFaces.seamThickness(.aluminum), 6, "アルミは金属の縁")
        XCTAssertEqual(TrunkFaces.seamThickness(.leather), 3)
    }

    /// 前開き: 蝶番は**底の前寄り**だけ（合わせ目をまたぐ 28×16 を2つ）。持ち手は上の面に残す
    func testHingesOnTheBottomFrontAndHandleOnTop() {
        for side in TrunkFaceSide.allCases where side != .bottom {
            XCTAssertTrue(TrunkFaces.hinges(side).isEmpty, "\(side) に蝶番がある")
            if side != .top { XCTAssertNil(TrunkFaces.handle(side), "\(side) に持ち手がある") }
        }
        let hinges = TrunkFaces.hinges(.bottom)
        XCTAssertEqual(hinges.map(\.x), [64, 268])
        for h in hinges {
            XCTAssertEqual(h.w, 28)
            XCTAssertEqual(h.h, 16)
            XCTAssertLessThan(h.y, 26, "合わせ目（正面から 26）をまたいでいない")
            XCTAssertGreaterThan(h.maxY, 26)
            XCTAssertLessThan(h.midY, TrunkFaces.depth / 2, "蝶番が前寄りでない（底の絵は上が正面）")
        }
        let handle = TrunkFaces.handle(.top)
        XCTAssertEqual(handle?.x, 128)
        XCTAssertEqual(handle?.w, 104)
        XCTAssertEqual(handle?.h, 14, "太さ 10 の持ち手は 14 の帯")
        XCTAssertEqual(TrunkFaces.handle(.top, thickness: 9)?.h, 13, "付けた持ち手の太さを使っていない")
        XCTAssertEqual(TrunkFaces.handleClips(.top).count, 2)
    }

    /// 型で違う底の足（ゴム・革の当て・木の滑り材と鋲・金の足・真鍮の足）
    func testFeetDifferByModel() {
        XCTAssertTrue(TrunkFaces.feet(.left, model: .leather).feet.isEmpty, "底のほかに足がある")
        func kinds(_ m: TrunkModel) -> Set<String> {
            Set(TrunkFaces.feet(.bottom, model: m).feet.map { "\($0.kind)" })
        }
        XCTAssertEqual(TrunkFaces.feet(.bottom, model: .aluminum).feet.first?.kind, .rubber)
        XCTAssertEqual(TrunkFaces.feet(.bottom, model: .clipper).feet.first?.kind, .rubber)
        XCTAssertEqual(TrunkFaces.feet(.bottom, model: .kori).feet.first?.kind, .leatherPad)
        XCTAssertEqual(TrunkFaces.feet(.bottom, model: .urushi).feet.first?.kind, .metal(.gilt))
        XCTAssertEqual(TrunkFaces.feet(.bottom, model: .sleeper).feet.first?.kind, .metal(.brass))
        let steamer = TrunkFaces.feet(.bottom, model: .steamer)
        XCTAssertEqual(steamer.runners.count, 2, "船旅の衣装箱に木の滑り材2本が無い")
        XCTAssertEqual(steamer.feet.count, 6)
        XCTAssertTrue(steamer.feet.allSatisfy { $0.kind == .stud })
        XCTAssertEqual(kinds(.captain), kinds(.steamer))
        XCTAssertEqual(TrunkFaces.feet(.bottom, model: .leather).feet.count, 4)
    }

    /// 桟とベルトの回り込み（板 TrunkFaces の注記）。型ごとの素材は正面の `TrunkLook` から
    func testBandsWrapAround() {
        // 船旅: 側面は横の桟（上下）と、真ん中の縦の桟1本
        let side = TrunkFaces.bands(.left, look: look(.steamer))
        XCTAssertEqual(side.filter(\.horizontal).map(\.position), [0, 254])
        let vertical = side.filter { !$0.horizontal }
        XCTAssertEqual(vertical.count, 1)
        XCTAssertEqual(vertical.first?.position, (86 - 18) / 2)
        // 上の面: 縦の桟が通り、上の縁の桟（y 0）が両端に
        let top = TrunkFaces.bands(.top, look: look(.steamer))
        XCTAssertEqual(top.filter { !$0.horizontal }.map(\.position), [96, 246])
        XCTAssertEqual(top.filter(\.horizontal).map(\.position), [0, 72.0])
        // 底: 下の縁の桟（y 254）
        XCTAssertEqual(TrunkFaces.bands(.bottom, look: look(.steamer)).filter(\.horizontal).count, 2)
        // 寝台列車の真鍮の帯は下で一周（側面に出る・上の面には出ない）
        XCTAssertTrue(TrunkFaces.bands(.left, look: look(.sleeper)).contains { $0.brass && $0.horizontal })
        XCTAssertTrue(TrunkFaces.bands(.top, look: look(.sleeper)).isEmpty)
        // 背面は正面と同じ
        XCTAssertEqual(TrunkFaces.bands(.back, look: look(.captain)).count, look(.captain).bars.count)
        // ベルト・帯が見える面
        XCTAssertEqual(TrunkFaceSide.allCases.filter(TrunkFaces.showsStraps), [.top, .bottom, .back])
        XCTAssertEqual(TrunkFaceSide.allCases.filter(TrunkFaces.showsRail), [.left, .right, .back])
    }

    /// 鋲の列は面の幅に並べ直す（アルミの縁の列は上と底に、上下の縁沿い）
    func testRivetRows() {
        let top = TrunkFaces.rivets(.top, look: look(.aluminum))
        XCTAssertEqual(Set(top.map(\.y)), [8, 78], "上の面の鋲が縁に沿っていない")
        XCTAssertTrue(top.allSatisfy { $0.x >= 22 && $0.x <= 338 })
        XCTAssertFalse(TrunkFaces.rivets(.bottom, look: look(.aluminum)).isEmpty)
        let side = TrunkFaces.rivets(.left, look: look(.clipper))
        XCTAssertTrue(side.allSatisfy { $0.x >= 12 && $0.x <= 74 }, "側面の鋲が側面の幅に収まっていない")
        XCTAssertEqual(TrunkFaces.rivets(.left, look: look(.steamer)).filter(\.slat).count, 4)
        XCTAssertTrue(TrunkFaces.rivets(.top, look: look(.leather)).isEmpty)
    }

    /// 角金具は3つの面にまたがる（側面・上・底は厚みの 46% まで）
    func testCornerCaps() {
        XCTAssertEqual(TrunkFaces.cornerSize(.left, look: look(.captain)), 40, "船長の 46 が側面で縮まない")
        XCTAssertEqual(TrunkFaces.cornerSize(.back, look: look(.captain)), 46)
        XCTAssertEqual(TrunkFaces.cornerSize(.top, look: look(.clipper)), 30)
    }

    /// 古び方は正面と同じ段（`TrunkAging.stage`）。投稿 0 では擦れ無し、増えるほど強く。金属の型は擦れない
    func testAgingMatchesTheFront() {
        XCTAssertNil(TrunkFaces.edgeWear(.leather, stage: TrunkAging.stage(posts: 0)))
        let some = TrunkFaces.edgeWear(.leather, stage: TrunkAging.stage(posts: 30))
        let more = TrunkFaces.edgeWear(.leather, stage: TrunkAging.stage(posts: 100))
        XCTAssertNotNil(some)
        XCTAssertGreaterThan(more?.alpha ?? 0, some?.alpha ?? 1)
        XCTAssertGreaterThan(more?.width ?? 0, some?.width ?? 1)
        XCTAssertNil(TrunkFaces.edgeWear(.aluminum, stage: 1))
        XCTAssertNil(TrunkFaces.edgeWear(.urushi, stage: 1))
        XCTAssertEqual(TrunkFaces.bindingWidth(look(.leather)), 7, "縁の革が正面（9）より 2 細くない")
        XCTAssertEqual(TrunkFaces.bindingWidth(look(.urushi)), 5, "5 より細くしない")
        XCTAssertEqual(TrunkFaces.bindingWidth(look(.steamer)), 0)
    }

    /// 漆・星図だけ側面に絵、背面は金蒔絵（丸紋なし）と星座の続き
    func testSideAndBackArt() {
        XCTAssertEqual(TrunkFaces.sideArt(.urushi, side: .left), .waves(tile: 43))
        XCTAssertEqual(TrunkFaces.sideArt(.urushi, side: .top), .waves(tile: 60))
        XCTAssertEqual(TrunkFaces.sideArt(.starchart, side: .bottom), .stars)
        XCTAssertNil(TrunkFaces.sideArt(.urushi, side: .back))
        XCTAssertNil(TrunkFaces.sideArt(.leather, side: .left))
        XCTAssertEqual(TrunkFaces.backArt(.urushi), .makie)
        XCTAssertNil(TrunkFaces.backArt(.captain), "羅針盤が背面にも出る")
        XCTAssertEqual(TrunkArtwork.backStrokes(.makie).count, TrunkArtwork.strokes(.makie).count - 2, "丸紋が背面に残る")
        XCTAssertFalse(TrunkArtwork.backStrokes(.stars).isEmpty)
    }

    /// 向きのボタン（正面・側面・上と背面・底）。底は下から見上げる・上と背面は上から
    func testSpinViews() {
        let views = TrunkFaces.views
        XCTAssertEqual(views.map(\.id), ["front", "side", "topBack", "bottom"])
        XCTAssertLessThan(views[3].pitch, -1, "底が見えない傾き")
        XCTAssertGreaterThan(views[2].pitch, 0.5)
        XCTAssertEqual(abs(views[1].yaw), .pi / 2, accuracy: 0.001)
    }

    // MARK: - ふたを開ける（板 TrunkOpen）

    /// 指を離すと近い方へ（半分を越えたら開き切る）
    func testLidSettlesToTheNearerSide() {
        XCTAssertEqual(TrunkLid.settled(0.51), 1)
        XCTAssertEqual(TrunkLid.settled(0.5), 0)
        XCTAssertEqual(TrunkLid.settled(0.08), 0)
        XCTAssertEqual(TrunkLid.settled(0.97), 1)
        XCTAssertEqual(TrunkLid.toggled(0), 1)
        XCTAssertEqual(TrunkLid.toggled(1), 0)
        XCTAssertEqual(TrunkLid.toggled(0.5), 0)
        XCTAssertEqual(TrunkLid.toggleTitle(0), L("ふたを開ける", "Open the lid"))
        XCTAssertEqual(TrunkLid.toggleTitle(1), L("ふたを閉じる", "Close the lid"))
    }

    /// 引き下ろすと開く（320 で開き切る）・範囲の外へ出ない
    func testLidDrag() {
        XCTAssertEqual(TrunkLid.dragged(from: 0, dy: 160), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TrunkLid.dragged(from: 0, dy: 900), 1)
        XCTAssertEqual(TrunkLid.dragged(from: 1, dy: -900), 0)
        XCTAssertEqual(TrunkLid.dragged(from: 0.3, dy: -32), 0.2, accuracy: 0.0001)
    }

    /// 0 → 180°。90° を越えたらふたの裏。開け始めの 10% で錠前の板が起き切る
    func testLidAngleAndClasp() {
        XCTAssertEqual(TrunkLid.angle(0), 0)
        XCTAssertEqual(TrunkLid.angle(1), 180)
        XCTAssertFalse(TrunkLid.showsInside(0.5))
        XCTAssertTrue(TrunkLid.showsInside(0.51))
        XCTAssertEqual(TrunkLid.claspProgress(0.05), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TrunkLid.claspProgress(0.2), 1)
        XCTAssertEqual(TrunkLid.claspAngle(0.1), 140)
        XCTAssertEqual(TrunkLid.baseTop(0), 184)
        XCTAssertEqual(TrunkLid.baseTop(1), 40)
        // 開き切ったふた（胴の下 268）が舞台（584）に収まる
        XCTAssertLessThanOrEqual(TrunkLid.baseTop(1) + 268 * 2, TrunkLid.stageHeight)
        XCTAssertFalse(TrunkLid.hingesVisible(0.5))
        XCTAssertTrue(TrunkLid.hingesVisible(0.6))
        XCTAssertTrue(TrunkLid.isOpen(1))
        XCTAssertFalse(TrunkLid.isOpen(0.98))
    }

    /// 開き具合を読み上げる（「開き具合 38%」）
    func testLidReadsItsAmount() {
        XCTAssertEqual(TrunkLid.percentText(0.384), "38%")
        XCTAssertEqual(TrunkLid.accessibilityValue(0.384), L("開き具合 38%", "Open 38%"))
        XCTAssertEqual(TrunkLid.stepped(0.9, up: true), 1)
        XCTAssertEqual(TrunkLid.stepped(0.1, up: false), 0)
        XCTAssertNotEqual(TrunkLid.hint(0), TrunkLid.hint(1))
    }

    // MARK: - 中身

    /// メダルの台は 8 枠。8 枚までは全部、9 枚からは 7 枚と「ほか N」
    func testMedalSlots() {
        let keys = ["earlyUser", "first", "prefectures", "countries", "seasons", "morning", "night", "books", "wish"]
        let eight = TrunkInsideContents(medals: keys.prefix(8).map { badge($0) }, showsCard: false, ticketCount: 0)
        XCTAssertEqual(eight.slots.count, 8)
        XCTAssertEqual(eight.overflow, 0)
        XCTAssertFalse(eight.slots.contains(.more(1)))
        XCTAssertEqual(eight.slots.last, .medal(badge("books")))

        let nine = TrunkInsideContents(medals: keys.map { badge($0) }, showsCard: false, ticketCount: 0)
        XCTAssertEqual(nine.slots.count, 8)
        XCTAssertEqual(nine.overflow, 2)
        XCTAssertEqual(nine.slots.last, .more(2))
        XCTAssertEqual(nine.hiddenMedals.map(\.key), ["books", "wish"])
        XCTAssertEqual(nine.fanMedals.count, 2)
        XCTAssertEqual(nine.title(.more), L("ほかのメダル 2 枚", "2 more medals"))

        let none = TrunkInsideContents(medals: [], showsCard: true, ticketCount: 0)
        XCTAssertTrue(none.slots.allSatisfy { $0 == .empty })
        XCTAssertEqual(none.medalTab, L("メダル", "Medals"))
        XCTAssertEqual(nine.medalTab, L("メダル 9", "Medals 9"))
    }

    /// 「ほか N」はちょうど 7 枚目のあとから
    func testOverflowKeepsSevenOnTheLid() {
        let keys = (1...12).map { "k\($0)" }
        let c = TrunkInsideContents(medals: keys.map { badge($0) }, showsCard: false, ticketCount: 0)
        XCTAssertEqual(c.overflow, 5)
        XCTAssertEqual(c.slots.compactMap { if case .medal(let b) = $0 { return b.key } else { return nil } }, Array(keys.prefix(7)))
        XCTAssertEqual(c.hiddenMedals.map(\.key), Array(keys.suffix(5)))
        XCTAssertEqual(c.fanMedals.count, 3)
    }

    /// 本物の持ち物から: 知らない鍵は出さない・**Pro でない人に会員証を出さない**
    func testContentsFromRealData() {
        let set = BadgeSet([badge("first"), badge("prefectures", 2), badge("unknownKey"), badge("supporter")])
        let free = TrunkInsideContents(badges: set, isPro: false, ticketCount: 3)
        XCTAssertFalse(free.showsCard, "Pro でない人に会員証が入る（サポーターの印が残っていても）")
        XCTAssertFalse(free.medals.contains { $0.key == "unknownKey" })
        XCTAssertEqual(free.medals.map(\.key), ["first", "prefectures", "supporter"], "台帳の順でない")
        XCTAssertEqual(free.ticketTab, L("乗車券 3", "Tickets 3"))
        let pro = TrunkInsideContents(badges: set, isPro: true, ticketCount: 0)
        XCTAssertTrue(pro.showsCard)
        XCTAssertEqual(pro.ticketTab, L("乗車券", "Tickets"))
    }

    /// 空のトランク: メダルも会員証も乗車券も無いときだけ
    func testEmptyTrunk() {
        XCTAssertTrue(TrunkInsideContents(badges: BadgeSet(), isPro: false, ticketCount: 0).isEmpty)
        XCTAssertFalse(TrunkInsideContents(badges: BadgeSet(), isPro: true, ticketCount: 0).isEmpty, "Pro の人の会員証が空扱い")
        XCTAssertFalse(TrunkInsideContents(badges: BadgeSet(), isPro: false, ticketCount: 1).isEmpty)
        XCTAssertFalse(TrunkInsideContents(badges: BadgeSet([badge("first")]), isPro: false, ticketCount: 0).isEmpty)
        XCTAssertEqual(TrunkInsideEmpty.rows.map(\.shape), [.medal, .card, .ticket])
        XCTAssertEqual(TrunkInsideEmpty.actionTitle, L("写真を投稿する", "Post a photo"))
    }

    /// 「中身を手に取る」で最初に持ち上げるもの・出口の名前
    func testFirstItemAndExits() {
        let all = TrunkInsideContents(medals: [badge("first")], showsCard: true, ticketCount: 4)
        XCTAssertEqual(all.firstItem, .medal(badge("first")))
        XCTAssertEqual(TrunkInsideContents(medals: [], showsCard: true, ticketCount: 4).firstItem, .card)
        XCTAssertEqual(TrunkInsideContents(medals: [], showsCard: false, ticketCount: 4).firstItem, .tickets)
        XCTAssertNil(TrunkInsideContents(medals: [], showsCard: false, ticketCount: 0).firstItem)
        XCTAssertEqual(all.actionTitle(.medal(badge("first"))), L("メダルを回して見る", "Turn the medal"))
        XCTAssertEqual(all.actionTitle(.more), L("バッジの棚で見る", "See them on the badge shelf"))
        XCTAssertEqual(all.actionTitle(.card), L("サポーター証を開く", "Open the supporter card"))
        XCTAssertEqual(all.actionTitle(.tickets), L("すれちがい帳を開く", "Open the pass book"))
        XCTAssertTrue(all.subtitle(.tickets).contains("4"))
    }

    // MARK: - 内張り（板 InsideModels・Linings）

    /// 型ごとの既定の内張り（板 InsideModels の名前）
    func testDefaultLiningPerModel() {
        let ja: [TrunkModel: String] = [
            .leather: "生成りの綾織", .canvas: "生成りの帆布", .aluminum: "灰のフェルト", .steamer: "船旅の紙張り（小花）",
            .urushi: "朱の漆", .kori: "柳の編み目", .sleeper: "臙脂のモケット（座席の布）", .clipper: "灰青のキルト",
            .captain: "生成りの帆布", .starchart: "紺の絹",
        ]
        for model in TrunkModel.allCases {
            let lining = TrunkInsideLooks.lining(model: model, equipped: .none)
            XCTAssertNil(lining.partId)
            XCTAssertEqual(lining.name, L(ja[model] ?? "", lining.name), "\(model) の内張りの名前が板と違う")
        }
        XCTAssertTrue(TrunkInsideLooks.look(.urushi).gildEdge)
        XCTAssertTrue(TrunkInsideLooks.look(.starchart).gildEdge)
        XCTAssertTrue(TrunkInsideLooks.look(.sleeper).brassBand)
        XCTAssertTrue(TrunkInsideLooks.look(.captain).brassBand)
        XCTAssertNil(TrunkInsideLooks.look(.aluminum).stitch)
        XCTAssertEqual(TrunkInsideLooks.look(.aluminum).metal, TrunkInsideLooks.chrome)
        XCTAssertEqual(TrunkInsideLooks.look(.urushi).metal, TrunkInsideLooks.gilt)
    }

    /// 内張りの部品を付けると内張りだけがその布（12点・台と仕切りは型のまま）
    func testEquippedLiningReplacesOnlyTheLining() {
        for part in TrunkPartCatalog.parts(of: .lining) {
            let lining = TrunkInsideLooks.lining(model: .leather, equipped: TrunkEquipped(lining: part.id))
            XCTAssertEqual(lining.partId, part.id)
            XCTAssertEqual(lining.name, part.name)
        }
        XCTAssertEqual(TrunkPartCatalog.parts(of: .lining).count, 12)
        let velvet = TrunkInsideLooks.lining(model: .canvas, equipped: TrunkEquipped(lining: "lining.7"))
        XCTAssertEqual(velvet.name, "紺の天鵞絨")
        // 場所の違う id・知らない id は型の既定のまま
        XCTAssertNil(TrunkInsideLooks.lining(model: .canvas, equipped: TrunkEquipped(lining: "handle.1")).partId)
        XCTAssertNil(TrunkInsideLooks.lining(model: .canvas, equipped: TrunkEquipped(lining: "lining.99")).partId)
    }

    /// 読み上げ: 型・内張り・中身の数
    func testInsideAccessibilityLabel() {
        let c = TrunkInsideContents(medals: [badge("first")], showsCard: true, ticketCount: 12)
        let label = c.accessibilityLabel(model: .leather, lining: TrunkInsideLooks.lining(model: .leather, equipped: .none))
        XCTAssertTrue(label.contains(TrunkText.info(.leather).name))
        XCTAssertTrue(label.contains("12"))
        XCTAssertEqual(TrunkInsideContents.slotLabel(.more(3)), L("ほかのメダル 3 枚", "3 more medals"))
    }
}
