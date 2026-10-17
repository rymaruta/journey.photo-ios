import XCTest
@testable import JourneyPhoto

/// 旅のトランクの次の版（2026-10-17）: 部品の台帳・描き方・付け替えの決まり・カプセルの機械・応答の読み方
final class TrunkPartsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }

    // MARK: 台帳（モック Parts.dc.html の並び・名前・段）

    /// モックの各行の名前（並び順がそのまま id の番号）
    private let mockNames: [TrunkPartKind: [String]] = [
        .handle: ["茶の革", "黒の革", "赤の革", "鹿革", "籐巻き", "麻縄", "赤の組紐", "真鍮の輪", "銀の輪", "飴色の樹脂", "黒檀の握り", "金の鎖"],
        .corner: ["打ち出しの真鍮", "鋲の真鍮", "唐草の彫り", "銀", "銅", "黒鉄", "斜めの線彫り", "クローム", "厚革", "透かしの真鍮", "緑青の青銅", "金の唐草"],
        .lock: ["無地の錠前", "菊", "桜", "青海波", "羅針盤", "船の舵", "寝台列車", "貝", "南京錠", "ダイヤル錠", "双子の留め金", "金の星"],
        .lining: ["縞の綿", "格子の綿", "千鳥格子", "麻", "市松", "青海波", "紺の天鵞絨", "赤の天鵞絨", "地図の柄", "星の柄", "絹の更紗", "金襴"],
        .tag: ["空の便", "船旅", "夜行列車", "一等船室", "ホテルの札", "手小荷物", "航空便", "こわれもの", "和紙の荷札", "革の名札", "木の名札", "真鍮の名札"],
        .pin: ["鳥居", "富士", "桜", "灯台", "紅葉", "飛行機", "汽船", "ゴンドラ", "波", "羅針盤", "夜行列車", "金の星"],
        .patch: ["京都", "北海道", "沖縄", "富士山", "パリ", "北欧", "登山", "船乗り", "桜の旅", "空の旅", "世界一周", "金糸の紅葉"],
        .charm: ["鳥居", "灯台", "ゴンドラ", "桜", "飛行機", "汽船", "貝", "羅針盤", "紅葉", "富士", "ハート", "金の星"],
        .key: ["真鍮の涙", "真鍮のひし形", "銀の楕円", "赤い札", "紺の札", "緑の札", "木の札", "飴色の札", "銅の札", "寝台車", "船室", "金の鍵"],
    ]

    /// モックの段（0 ふつう・1 めずらしい・2 とてもめずらしい）
    private let mockRarity: [TrunkPartKind: [Int]] = [
        .handle: [0, 0, 1, 0, 1, 0, 1, 0, 1, 1, 2, 2],
        .corner: [0, 0, 1, 0, 0, 0, 1, 1, 0, 1, 2, 2],
        .lock: [0, 1, 1, 0, 1, 1, 1, 0, 0, 1, 0, 2],
        .lining: [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2],
        .tag: [0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 1, 2],
        .pin: [0, 0, 1, 0, 0, 0, 1, 1, 0, 1, 1, 2],
        .patch: [0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 2],
        .charm: [0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 1, 2],
        .key: [0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 2],
    ]

    func testCatalogIsNineKindsOfTwelve() {
        XCTAssertEqual(TrunkPartKind.allCases.count, 9)
        XCTAssertEqual(TrunkPartCatalog.all.count, 108)
        XCTAssertEqual(Set(TrunkPartCatalog.all.map(\.id)).count, 108, "id が重なっている")
        for kind in TrunkPartKind.allCases {
            let parts = TrunkPartCatalog.parts(of: kind)
            XCTAssertEqual(parts.count, 12, "\(kind)")
            XCTAssertEqual(parts.map(\.id), (1...12).map { "\(kind.rawValue).\($0)" }, "\(kind) の id が並び順でない")
            XCTAssertEqual(parts.map(\.name), mockNames[kind], "\(kind) の名前がモックと違う")
            XCTAssertEqual(parts.map(\.rarity.rawValue), mockRarity[kind], "\(kind) の段がモックと違う")
            XCTAssertTrue(parts.allSatisfy { $0.look.kind == kind }, "\(kind) に別の種類の見た目が入っている")
        }
    }

    func testRarityCountsAndOdds() {
        XCTAssertEqual(TrunkPartCatalog.count(.common), 54)
        XCTAssertEqual(TrunkPartCatalog.count(.rare), 42)
        XCTAssertEqual(TrunkPartCatalog.count(.veryRare), 12)
        XCTAssertEqual(TrunkPartRarity.allCases.map(\.percent), [70, 25, 5])
        XCTAssertEqual(TrunkGachaText.perPart(.common), 1.3, accuracy: 0.001)
        XCTAssertEqual(TrunkGachaText.perPart(.rare), 0.6, accuracy: 0.001)
        XCTAssertEqual(TrunkGachaText.perPart(.veryRare), 0.42, accuracy: 0.001)
        XCTAssertEqual(TrunkGachaText.percentText(0.42), "0.42%")
        // 段の確率 × 段の点数で 100% に戻る（1点あたりは丸めた値なので少しずれる）
        let total = TrunkPartRarity.allCases.reduce(0.0) { $0 + TrunkGachaText.perPart($1) * Double(TrunkPartCatalog.count($1)) }
        XCTAssertEqual(total, 100, accuracy: 0.5)
    }

    func testLookupAndCapacity() {
        XCTAssertEqual(TrunkPartCatalog.part("lock.2")?.name, "菊")
        XCTAssertNil(TrunkPartCatalog.part("lock.13"))
        XCTAssertNil(TrunkPartCatalog.part("hat.1"))
        XCTAssertEqual(TrunkPartKind.pin.capacity, 3)
        XCTAssertEqual(TrunkPartKind.patch.capacity, 2)
        XCTAssertEqual(TrunkPartKind.lock.capacity, 1)
    }

    /// 見た目の値の見本（モックの値をそのまま写したか）
    func testLooksCopyTheMock() {
        guard case .lock(let kiku)? = TrunkPartCatalog.part("lock.2")?.look else { return XCTFail() }
        XCTAssertEqual(kiku.metal, .brass)
        XCTAssertEqual(kiku.shape, .plate)
        XCTAssertEqual(kiku.emblem, .kiku)
        guard case .handle(let rope)? = TrunkPartCatalog.part("handle.7")?.look else { return XCTFail() }
        XCTAssertEqual(rope.width, 9)
        XCTAssertEqual(rope.clip, .gold)
        guard case .key(let red)? = TrunkPartCatalog.part("key.4")?.look else { return XCTFail() }
        XCTAssertEqual(red.no, "418")
        XCTAssertEqual(red.fobPaint, .solid(TrunkRGBA(0x8C2F2B)))
        guard case .pin(let ship)? = TrunkPartCatalog.part("pin.7")?.look else { return XCTFail() }
        XCTAssertEqual(ship.shape, .square)
        XCTAssertEqual(ship.ink, TrunkRGBA(0xE7C77A))
        XCTAssertEqual(TrunkPartMetal.brass.tones.mid, TrunkRGBA(0xC9A66B))
        XCTAssertEqual(TrunkPartMetal.iron.ink, TrunkRGBA(r: 230, g: 230, b: 235, a: 0.75))
    }

    // MARK: 描き方

    /// 手順の中の点を、置き方を畳んで全部集める
    private func points(_ ops: [TrunkPartOp], _ t: TrunkPartTransform = .identity) -> [SVGPath.Point] {
        var out: [SVGPath.Point] = []
        func add(_ segments: [SVGPath.Segment]) {
            for s in segments {
                switch s {
                case .move(let p), .line(let p): out.append(t.apply(p))
                case let .cubic(_, _, to): out.append(t.apply(to))
                case let .quad(_, to): out.append(t.apply(to))
                case .close: break
                }
            }
        }
        for op in ops {
            switch op {
            case let .fill(segments, _, _, _): add(segments)
            case let .stroke(segments, _, _, _, _): add(segments)
            case let .group(children, inner, _): out += points(children, inner.within(t))
            case .text: break
            }
        }
        return out
    }

    func testDrawingIsDeterministicAndInsideTheBox() {
        for part in TrunkPartCatalog.all {
            let a = TrunkPartDrawing.ops(part), b = TrunkPartDrawing.ops(part)
            XCTAssertEqual(a, b, "\(part.id) の描き方が呼ぶたびに違う")
            XCTAssertFalse(a.isEmpty, part.id)
            let pts = points(a)
            XCTAssertFalse(pts.isEmpty, part.id)
            for p in pts {
                XCTAssertTrue((-2...98).contains(p.x) && (-2...98).contains(p.y), "\(part.id) が 96 の枠からはみ出す: \(p)")
            }
        }
    }

    func testTextsComeFromTheSpec() {
        // 鍵の札の字（HOTEL・番号）・タグの2行・ワッペンの字・ダイヤルの数字
        let key = TrunkPartDrawing.textColumns(TrunkPartDrawing.ops(TrunkPartCatalog.part("key.5")!))
        XCTAssertEqual(key.flatMap(\.items).compactMap { if case .text(let t, _) = $0 { return t.text } else { return nil } },
                       ["RYOKAN", "桐"])
        let tag = TrunkPartDrawing.textColumns(TrunkPartDrawing.ops(TrunkPartCatalog.part("tag.1")!))
        XCTAssertEqual(tag.count, 1)
        XCTAssertEqual(tag[0].transform.rotation, -6, "タグの字が札と一緒に傾いていない")
        XCTAssertTrue(tag[0].items.contains { if case .bar = $0 { return true } else { return false } }, "紙のタグにバーコードが無い")
        let leatherTag = TrunkPartDrawing.textColumns(TrunkPartDrawing.ops(TrunkPartCatalog.part("tag.10")!))
        XCTAssertFalse(leatherTag[0].items.contains { if case .bar = $0 { return true } else { return false } }, "革の名札にバーコード")
        let dial = TrunkPartDrawing.textColumns(TrunkPartDrawing.ops(TrunkPartCatalog.part("lock.10")!))
        XCTAssertEqual(dial.flatMap(\.items).count, 3)
        XCTAssertEqual(TrunkPartDrawing.patchTextSize("KYOTO"), 9)
        XCTAssertEqual(TrunkPartDrawing.patchTextSize("TWELVELETTER"), 6, "長い字は `58 / 字数 × 1.25` に縮める")
    }

    func testCSSRadiusScaling() {
        // ワッペンの盾: 10 10 40 40 を 66 幅に（40 + 40 > 66 なので 66/80 に縮む）
        let r = TrunkRect(x: 0, y: 0, w: 66, h: 74)
        let segments = TrunkShapes.cssRect(r, rx: [10, 10, 40, 40])
        guard case .move(let start) = segments.first else { return XCTFail() }
        XCTAssertEqual(start.x, 10 * 66.0 / 80, accuracy: 0.0001)
        XCTAssertEqual(TrunkShapes.bounds(segments), r)
    }

    func testRelativeArcIsParsed() {
        // 汽車の車輪（`a3 3 0 1 0 0.1 0`）を読み落とさない（大文字だけ読んでいた頃は車輪が消えた）
        let segments = SVGPath.parse(TrunkPartIcon.train.d)
        let moves = segments.filter { if case .move = $0 { return true } else { return false } }.count
        XCTAssertEqual(moves, 3)
        XCTAssertTrue(segments.contains { if case .cubic = $0 { return true } else { return false } })
    }

    // MARK: トランクに付けた部品

    func testFittingsOnTheTrunk() {
        let f = TrunkFittings(TrunkSample.equipped)
        XCTAssertEqual(f.handle?.id, "handle.7")
        XCTAssertEqual(f.handlePaint?.thickness, 9, "赤の組紐は太さ 9（モック PartsOnTrunk の handleW）")
        XCTAssertEqual(f.lockMetal, .brass)
        XCTAssertNotNil(f.cornerPaint)
        let placed = f.placements
        XCTAssertEqual(placed.filter(\.onBody).count, 3, "ピン2つとワッペン1つ")
        XCTAssertEqual(placed.filter { !$0.onBody }.map(\.part.kind), [.tag, .charm, .key])
        // モック Equip のピン 1 つ目: `left: 92; top: 132`（トランクは上 20）・縮み 0.52・中心は左上
        let pin = placed[0]
        XCTAssertEqual(pin.x, 92)
        XCTAssertEqual(pin.y, 112)
        // チャーム: `transform-origin: 50% 0` を残す（縮めた枠の左上は 96 × 0.4 × 0.5 だけ右へ）
        let charm = placed.first { $0.part.kind == .charm }!
        XCTAssertEqual(charm.x, 112 + 0.5 * 96 * 0.4, accuracy: 0.0001)
        XCTAssertTrue(TrunkFittings.none.isEmpty)
        XCTAssertNil(TrunkFittings(TrunkEquipped(lock: "handle.1")).lock, "場所の合わない部品を付けた")
        // 籐巻き（13）は持ち手の輪を潰さないよう 10 で止める
        XCTAssertEqual(TrunkFittings(TrunkEquipped(handle: "handle.5")).handlePaint?.thickness, 10)
    }

    func testEquipRules() {
        let pin = { (n: Int) in TrunkPartCatalog.part("pin.\(n)")! }
        var e = TrunkEquipped()
        e = TrunkEquipText.toggling(pin(1), on: e).equipped
        e = TrunkEquipText.toggling(pin(2), on: e).equipped
        e = TrunkEquipText.toggling(pin(3), on: e).equipped
        XCTAssertEqual(e.pins, ["pin.1", "pin.2", "pin.3"])
        let full = TrunkEquipText.toggling(pin(4), on: e)
        XCTAssertTrue(full.full, "4つ目のピンを付けられた")
        XCTAssertEqual(full.equipped, e)
        XCTAssertEqual(TrunkEquipText.toggling(pin(2), on: e).equipped.pins, ["pin.1", "pin.3"], "押し直しで外れない")
        // 開けた画面の「付ける」も、いっぱいなら黙って外さずに断る（付け替えの画面と同じ）
        let fromCapsule = TrunkEquipText.equipping(pin(4), on: e)
        XCTAssertTrue(fromCapsule.full, "いっぱいなのに付けた")
        XCTAssertEqual(fromCapsule.equipped.pins, ["pin.1", "pin.2", "pin.3"], "古いピンを黙って外した")
        XCTAssertEqual(TrunkEquipText.equipping(pin(4), on: TrunkEquipped(pins: ["pin.1"])).equipped.pins, ["pin.1", "pin.4"])
        let lock = TrunkPartCatalog.part("lock.3")!
        let withLock = TrunkEquipText.equipping(lock, on: TrunkEquipped(lock: "lock.1")).equipped
        XCTAssertEqual(withLock.lock, "lock.3", "1つの場所は置き換え")
        XCTAssertNil(TrunkEquipText.toggling(lock, on: withLock).equipped.lock, "押し直しで外れない")
        XCTAssertEqual(TrunkEquipText.clearing(.pin, on: e).pins, [])
        XCTAssertNil(TrunkEquipText.outline(.lining), "見えない内張りに枠を出した")
    }

    func testEquipBodySendsNulls() throws {
        let body = TrunkEquipped(handle: "handle.2", pins: ["pin.1", "pin.2", "pin.3", "pin.4"])
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["handle"] as? String, "handle.2")
        XCTAssertTrue(json["lock"] is NSNull, "外した場所を null で送っていない（サーバーは無い鍵を「触らない」と読む）")
        XCTAssertEqual(json["pins"] as? [String], ["pin.1", "pin.2", "pin.3"], "4つ目まで送った")
        XCTAssertEqual(json["patches"] as? [String], [])
        XCTAssertEqual(Set(json.keys), ["handle", "corner", "lock", "lining", "tag", "charm", "key", "pins", "patches"])
    }

    // MARK: 応答の読み方（どれも包みで・欠けても投げない）

    func testStateReadsPartsAndCoins() throws {
        let json = """
        {"pocket": [], "stuck": [
           {"id": "s-1", "kind": "place", "place": {"name": "京都"}, "seed": 1, "at": "2026-01-01T00:00:00Z",
            "pos": {"x": 0.25, "y": 0.5, "rot": -12.5}},
           {"id": "s-2", "kind": "place", "place": {"name": "札幌"}, "seed": 2, "at": "2026-01-01T00:00:00Z",
            "pos": {"x": 1.5, "y": 0.5, "rot": 0}},
           {"id": "s-3", "kind": "place", "place": {"name": "那覇"}, "seed": 3, "at": "2026-01-01T00:00:00Z",
            "pos": {"x": 0.5, "y": 0.5, "rot": 45}}
         ],
         "coins": "3", "fragments": 7,
         "parts": ["lock.2", "lock.2", "hat.9", "pin.1", "pin.2", "pin.3", "pin.4", 12, "handle.1"],
         "equipped": {"handle": "handle.1", "lock": "lock.9", "corner": "handle.1", "pins": ["pin.1", "pin.4", "pin.2", "pin.3"],
                      "patches": null, "key": 5}}
        """
        let s = try decode(TrunkState.self, json)
        XCTAssertEqual(s.coins, 3, "文字の数を読まなかった")
        XCTAssertEqual(s.fragments, 7)
        XCTAssertEqual(s.parts, ["lock.2", "pin.1", "pin.2", "pin.3", "pin.4", "handle.1"], "知らない id・重なり・数を落としていない")
        XCTAssertEqual(s.equipped.handle, "handle.1")
        XCTAssertNil(s.equipped.lock, "持っていない部品を付けたまま")
        XCTAssertNil(s.equipped.corner, "場所の合わない部品を付けたまま")
        XCTAssertEqual(s.equipped.pins, ["pin.1", "pin.4", "pin.2"], "ピンを 3 つで切っていない")
        XCTAssertEqual(s.equipped.patches, [])
        XCTAssertEqual(s.stuck[0].pos, TrunkPos(x: 0.25, y: 0.5, rot: -12.5))
        XCTAssertNil(s.stuck[1].pos, "範囲の外の置き場を読んだ")
        XCTAssertNil(s.stuck[2].pos, "30° を越える傾きを読んだ")
    }

    func testOldServerWithoutPartsStillReads() throws {
        let s = try decode(TrunkState.self, #"{"pocket": [], "stuck": []}"#)
        XCTAssertEqual(s.coins, 0)
        XCTAssertEqual(s.parts, [])
        XCTAssertEqual(s.fragments, 0)
        XCTAssertEqual(s.equipped, .none)
        let broken = try decode(TrunkState.self, #"{"pocket": [], "coins": -4, "fragments": "x", "equipped": "lock.1", "parts": "lock.1"}"#)
        XCTAssertEqual(broken.coins, 0)
        XCTAssertEqual(broken.fragments, 0)
        XCTAssertEqual(broken.parts, [])
        XCTAssertEqual(broken.equipped, .none)
    }

    func testDealtCoin() throws {
        XCTAssertEqual(TrunkDealt.read(Data(#"{"label": null, "labelSkipped": "off", "coin": 1}"#.utf8)).coin, 1)
        XCTAssertEqual(TrunkDealt.read(Data(#"{"coin": "1"}"#.utf8)).coin, 1)
        XCTAssertEqual(TrunkDealt.read(Data(#"{"coin": 5}"#.utf8)).coin, 0, "0 か 1 の外の値を読んだ")
        XCTAssertEqual(TrunkDealt.read(Data(#"{"label": null}"#.utf8)).coin, 0)
        XCTAssertEqual(TrunkDealt.read(Data("[]".utf8)).coin, 0)
    }

    func testGachaResult() throws {
        let r = try decode(TrunkGachaResult.self,
                           #"{"part": {"id": "lock.2", "kind": "lock", "rarity": 1, "name": "菊"}, "duplicate": false, "fragments": 3, "coins": 1}"#)
        XCTAssertEqual(r.part.name, "菊")
        XCTAssertEqual(r.coins, 1)
        XCTAssertThrowsError(try decode(TrunkGachaResult.self, #"{"part": {"id": "lock.99"}, "coins": 0}"#),
                             "台帳に無い部品を「出た」と見せた")
        let before = TrunkSample.state(isPro: false)
        let after = r.applied(to: before)
        XCTAssertEqual(after.coins, 1)
        XCTAssertEqual(after.fragments, 3)
        XCTAssertEqual(after.parts.filter { $0 == "lock.2" }.count, 1, "持っている部品を二重に足した")
        let fresh = TrunkGachaResult(part: TrunkPartCatalog.part("charm.12")!, duplicate: false, fragments: 3, coins: 1)
        XCTAssertEqual(fresh.applied(to: before).parts.first, "charm.12")
        XCTAssertEqual(after.pocket, before.pocket, "部品のほかを書き換えた")
    }

    // MARK: 硬貨 0・かけら不足の表示

    func testNoCoinsAndFragmentsWording() {
        XCTAssertEqual(TrunkGachaText.insertTitle(coins: 0), "硬貨がありません")
        XCTAssertEqual(TrunkGachaText.insertTitle(coins: 2), "硬貨を入れる")
        XCTAssertEqual(TrunkGachaText.hint(coins: 0, phase: .idle), "公開の投稿1件で1枚もらえます")
        XCTAssertEqual(TrunkGachaText.exchangeNote(fragments: 3, selected: nil), "まだ持っていない部品から選べます · あと 2 つ")
        XCTAssertFalse(TrunkPartsBoxText.canExchange(fragments: 4))
        XCTAssertTrue(TrunkPartsBoxText.canExchange(fragments: 5))
        XCTAssertEqual(TrunkPartsBoxText.filledFragments(12), 5)
        XCTAssertEqual(TrunkText.refusal(code: "noCoins", fallback: "x"), "硬貨がありません。公開の投稿1件で1枚もらえます。")
        XCTAssertEqual(TrunkText.refusal(code: "notEnoughFragments", fallback: "x"), "かけらが足りません。5つで1つ交換できます。")
        XCTAssertEqual(TrunkGachaText.title(TrunkPartCatalog.part("lock.2")!), "真鍮の錠前「菊」", "モックの見出しの形")
        XCTAssertEqual(TrunkGachaText.title(TrunkPartCatalog.part("lock.12")!), "錠前「金の星」", "金属の名前を重ねた")
        let kiku = TrunkPartCatalog.part("lock.2")!
        XCTAssertEqual(TrunkGachaText.arrivedWhileAway(TrunkGachaResult(part: kiku, duplicate: false, fragments: 0, coins: 0)),
                       "カプセルの「菊」が部品箱に入りました。")
        XCTAssertTrue(TrunkGachaText.arrivedWhileAway(TrunkGachaResult(part: kiku, duplicate: true, fragments: 1, coins: 0))
            .contains("かけら"))
    }

    @MainActor
    func testPreviewGachaAndExchange() async {
        let model = TrunkViewModel(preview: .sample, previewPro: false)
        await model.load(offline: false)
        XCTAssertEqual(model.state?.coins, 2)
        let first = await model.gacha()
        XCTAssertEqual(first?.part.id, TrunkSample.gachaOrder[0])
        XCTAssertEqual(model.state?.coins, 1)
        XCTAssertEqual(first?.duplicate, true, "見本は菊を持っている")
        XCTAssertEqual(model.state?.fragments, 4)
        _ = await model.gacha()
        XCTAssertEqual(model.state?.coins, 0)
        XCTAssertTrue(model.state?.parts.contains("charm.12") ?? false)
        let none = await model.gacha()
        XCTAssertNil(none, "硬貨 0 で回った")
        XCTAssertEqual(model.actionError, TrunkText.refusal(code: "noCoins", fallback: ""))
        // かけら 4 では交換しない
        let before = model.state
        await model.exchange("key.12")
        XCTAssertEqual(model.state?.parts, before?.parts, "かけらが足りないのに交換した")
    }

    @MainActor
    func testPreviewEquipSanitizes() async {
        let model = TrunkViewModel(preview: .sample, previewPro: false)
        await model.load(offline: false)
        await model.equip(TrunkEquipped(handle: "handle.12", lock: "lock.1"))
        XCTAssertNil(model.state?.equipped.handle, "持っていない部品を付けた")
        XCTAssertEqual(model.state?.equipped.lock, "lock.1")
    }

    // MARK: 届いた硬貨

    @MainActor
    func testCoinsArriveWithTheLabelOrAlone() async {
        let arrivals = TrunkArrivals()
        arrivals.deliver([.init(label: TrunkSample.arrived, photoTitle: "")], notice: nil, coins: 1)
        arrivals.deliver([.init(label: TrunkSample.pocket[0], photoTitle: "")], notice: nil, coins: 1)
        XCTAssertEqual(arrivals.consume()?.coins, 2, "束の硬貨を足していない")
        arrivals.deliver(TrunkDealt(label: nil, labelSkipped: .off, coin: 1), photoTitle: "")
        XCTAssertEqual(arrivals.consumeNotice(), .coins(1), "受け取らない設定の人に硬貨が届いたことを言わない")
        arrivals.deliver(TrunkDealt(label: nil, labelSkipped: .full, coin: 1), photoTitle: "")
        let full = arrivals.consumeNotice()
        XCTAssertEqual(full, .fullAndCoins(1), "いっぱいのときに硬貨が届いたことを言わない")
        XCTAssertEqual(full?.text, TrunkText.fullNotice + " " + TrunkText.coinAlsoNotice(1))
        arrivals.deliver(TrunkDealt(label: nil, labelSkipped: .full, coin: 0), photoTitle: "")
        XCTAssertEqual(arrivals.consumeNotice(), .full)
        arrivals.deliver(TrunkDealt(label: nil, labelSkipped: .daily, coin: 0), photoTitle: "")
        XCTAssertFalse(arrivals.hasPending)
        XCTAssertEqual(TrunkText.coinChip(1), "硬貨 +1")
    }

    // MARK: カプセルの機械

    func testCrankTurnsOnlyForward() {
        var c = TrunkCrank()
        // 右回り（時計回り）に 90° ずつ指を回す: 3 時 → 6 時 → 9 時 → 12 時 → 3 時
        c.begin(dx: 10, dy: 0)
        var ticks = 0
        for (dx, dy) in [(0.0, 10.0), (-10, 0), (0, -10), (10, 0)] { ticks += c.drag(dx: dx, dy: dy) }
        XCTAssertTrue(c.isDone)
        XCTAssertEqual(c.percent, 100)
        XCTAssertEqual(ticks, 12, "30° ごとの目盛り")
        XCTAssertEqual(c.end(), 0, "回したあとに離したのを「押した」と数えた")

        var back = TrunkCrank()
        back.begin(dx: 10, dy: 0)
        back.drag(dx: 0, dy: 10)       // +90
        back.drag(dx: 10, dy: 0)       // -90 は 0.15 倍だけ戻る
        XCTAssertEqual(back.percent, Int(TrunkRGBA.jsRound((90 - 13.5) / 3.6)))
    }

    func testCrankTapIsAQuarter() {
        var c = TrunkCrank()
        XCTAssertEqual(c.tap(), 3)
        c.begin(dx: 10, dy: 0)
        XCTAssertEqual(c.end(), 3, "押しただけで 4 分の 1 回らない")
        c.tap()
        c.tap()
        XCTAssertTrue(c.isDone)
        XCTAssertEqual(c.tap(), 0, "1 周のあとも回った")
    }

    func testCapsulesStayInTheGlobe() {
        let all = TrunkCapsules.all
        XCTAssertEqual(all, TrunkCapsules.all)
        XCTAssertGreaterThan(all.count, 12)
        for c in all {
            let dx = c.x + 23 - 130, dy = c.y + 23 - 130
            XCTAssertLessThanOrEqual((dx * dx + dy * dy).squareRoot(), 130, "球の外のカプセル")
        }
    }
}
