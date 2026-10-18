import XCTest
@testable import JourneyPhoto

/// 写真で作るキャンプ場の部品の台帳（板 CampDex・版 25 と、付箋「id の一覧」「集める」）
final class CampCatalogTests: XCTestCase {

    /// 付箋「id の一覧」をそのまま写したもの（並びも板どおり）
    private let boardIds: [String: [String]] = [
        "tent": ["ridge_canvas", "dome", "tipi", "bell"],
        "tarp": ["flat_rect", "hexa_wing", "diamond", "bivy_lean"],
        "sleeping": ["bag_rect", "bag_mummy", "cot", "hammock_net"],
        "fire_ring": ["stone_ring", "steel_pit", "trench", "brazier_cone"],
        "cookware": ["kettle", "skillet", "dutch_oven", "percolator"],
        "firewood": ["split_stack", "log_round", "bundle_rope", "kindling_crate"],
        "lantern": ["oil_hurricane", "gas_mantle", "candle_brass", "led_cylinder"],
        "string_lights": ["bulbs", "flags_cotton", "paper_lanterns", "fairy_wire"],
        "torch": ["solar_stake", "tiki", "bamboo", "iron_basket"],
        "chair": ["low_sling", "log_stool", "rocking", "bench_plank"],
        "table": ["folding_roll", "log_slab", "cable_spool", "stump"],
        "rug": ["striped", "checker_picnic", "braided_round", "fringed_wool"],
        "tree": ["pine", "birch", "maple", "cedar_tall"],
        "rock": ["boulder", "flat_slab", "stacked_cairn", "mossy_pair"],
        "flora": ["wildflowers", "fern", "mushrooms", "reeds"],
        "water": ["pond_round", "stream", "waterfall_small", "spring_well"],
        "path": ["stepping_stones", "gravel", "boardwalk", "log_rounds"],
        "fence": ["rope_post", "split_rail", "wattle", "stone_wall"],
        "sign": ["hanging_board", "arrow_post", "carved_stump", "mailbox"],
        "cooler": ["hard_box", "soft_bag", "wooden_chest", "metal_tank"],
        "backpack": ["rucksack", "frame_pack", "duffel", "basket_pack"],
        "tool": ["rope_coil", "axe", "bow_saw", "shovel"],
        "island_edge": ["grass_lip", "flower_lip", "moss_drip", "snow_lip"],
        "island_base": ["cone_rock", "stepped_layers", "roots_hanging", "floating_stones"],
    ]

    /// 付箋「集める」の要サーバー 17
    private let serverIds: Set<String> = [
        "tent.bell", "tarp.hexa_wing", "fire_ring.brazier_cone", "cookware.dutch_oven", "string_lights.paper_lanterns",
        "string_lights.fairy_wire", "chair.bench_plank", "table.cable_spool", "rug.fringed_wool", "rock.mossy_pair",
        "water.waterfall_small", "fence.wattle", "sign.carved_stump", "sign.mailbox", "cooler.wooden_chest",
        "island_edge.moss_drip", "island_base.floating_stones",
    ]

    func testTwentyFourCategoriesOfFour() {
        XCTAssertEqual(CampCatalog.categories.count, 24)
        XCTAssertEqual(CampCatalog.allParts.count, 96)
        for c in CampCatalog.categories {
            XCTAssertEqual(c.parts.count, 4, c.key)
            XCTAssertEqual(c.parts.map(\.key), boardIds[c.key], "\(c.key) の部品が付箋の並びと違う")
            XCTAssertTrue(c.parts.allSatisfy { $0.category == c.key })
        }
        XCTAssertEqual(Set(CampCatalog.categories.map(\.key)), Set(boardIds.keys))
    }

    /// id は `camp.分類.部品`（英小文字と _ だけ）。キャンピングカー（`camper.`）と重ならない
    func testIdsAreUniqueAndPrefixed() throws {
        let ids = CampCatalog.allParts.map(\.id)
        XCTAssertEqual(Set(ids).count, 96)
        let pattern = try NSRegularExpression(pattern: "^camp\\.[a-z_]+\\.[a-z_]+$")
        for id in ids {
            XCTAssertNotNil(pattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)), id)
            XCTAssertFalse(id.hasPrefix("camper."), id)
        }
        XCTAssertEqual(CampCatalog.part("camp.tent.ridge_canvas")?.name.isEmpty, false)
        XCTAssertEqual(CampCatalog.part("tent.dome")?.id, "camp.tent.dome")
        XCTAssertNil(CampCatalog.part("camper.tent.dome"))
    }

    /// 端末だけ 79・要サーバー 17（付箋どおりの 17 個）
    func testDeviceAndServerSplit() {
        let server = Set(CampCatalog.allParts.filter(\.needsServer).map(\.boardId))
        XCTAssertEqual(server, serverIds)
        XCTAssertEqual(CampCatalog.collectible.count, 79)
    }

    /// 珍しさ: いつもの 23 ／ときどき 32 ／めずらしい 31 ／とても珍しい 10
    func testRarityCounts() {
        let count = { (r: CampRarity) in CampCatalog.allParts.filter { $0.rarity == r }.count }
        XCTAssertEqual(count(.common), 23)
        XCTAssertEqual(count(.uncommon), 32)
        XCTAssertEqual(count(.rare), 31)
        XCTAssertEqual(count(.epic), 10)
        XCTAssertEqual(CampRarity.epic.marks, 4)
    }

    /// 1 分類に 1 つ「いつもの」を最初から持つ。水だけは最初は空き
    func testStartersOnePerCategoryExceptWater() {
        XCTAssertEqual(CampCatalog.starters.count, 23)
        for c in CampCatalog.categories {
            let starters = c.parts.filter(\.isStarter)
            if c.key == "water" {
                XCTAssertTrue(starters.isEmpty, "水は最初は空き")
            } else {
                XCTAssertEqual(starters.count, 1, c.key)
                XCTAssertEqual(starters.first?.rarity, .common, c.key)
            }
        }
        // いつもの = 最初から（珍しさと条件が食い違わない）
        XCTAssertTrue(CampCatalog.allParts.filter { $0.rarity == .common }.allSatisfy(\.isStarter))
    }

    /// 置き場所 8 の表（分類・部品・要サーバー）
    func testPlaceTable() {
        let expected: [CampPlace: (Int, Int, Int)] = [
            .shelter: (3, 12, 2), .fire: (3, 12, 2), .light: (3, 12, 2), .furniture: (3, 12, 3),
            .nature: (4, 16, 2), .ground: (3, 12, 3), .gear: (3, 12, 1), .island: (2, 8, 2),
        ]
        XCTAssertEqual(CampPlace.allCases.count, 8)
        for place in CampPlace.allCases {
            let cats = CampCatalog.categories(in: place)
            let parts = cats.flatMap(\.parts)
            XCTAssertEqual(cats.count, expected[place]!.0, place.rawValue)
            XCTAssertEqual(parts.count, expected[place]!.1, place.rawValue)
            XCTAssertEqual(parts.filter(\.needsServer).count, expected[place]!.2, place.rawValue)
        }
    }

    /// 条件の数（板の札の文と合っている・代表）
    func testUnlockTargets() {
        XCTAssertEqual(CampCatalog.part("tent.dome")?.unlock, .subject(.mountain, 10))
        XCTAssertEqual(CampCatalog.part("sleeping.hammock_net")?.unlock, .season(.summer, 30))
        XCTAssertEqual(CampCatalog.part("lantern.candle_brass")?.unlock, .fullMoonNight)
        XCTAssertEqual(CampCatalog.part("torch.tiki")?.unlock, .subjectAtTime(.seaside, .evening, 5))
        XCTAssertEqual(CampCatalog.part("flora.mushrooms")?.unlock, .subjectInSeason(.forest, .autumn, 5))
        XCTAssertEqual(CampCatalog.part("fence.stone_wall")?.unlock, .prefectures(15))
        XCTAssertEqual(CampCatalog.part("rug.braided_round")?.unlock, .places(8))
        XCTAssertEqual(CampCatalog.part("chair.rocking")?.unlock, .samePlace(10))
        XCTAssertEqual(CampCatalog.part("tree.birch")?.unlock, .highland(5))
        XCTAssertEqual(CampCatalog.part("rock.stacked_cairn")?.unlock, .summit)
        XCTAssertEqual(CampCatalog.part("torch.iron_basket")?.unlock, .yearRound)
        XCTAssertEqual(CampCatalog.part("cookware.percolator")?.unlock, .time(.predawn, 3))
        XCTAssertEqual(CampCatalog.part("table.log_slab")?.unlock, .photos(100))
        XCTAssertEqual(CampCatalog.part("tent.bell")?.unlock, .server(.friends))
        XCTAssertEqual(CampCatalog.part("tarp.hexa_wing")?.unlock, .server(.weather))
    }

    /// 板の 3D に形がある 9 個は、どれも台帳に在る「いつもの」
    func testModeledPartsExist() {
        XCTAssertEqual(CampCatalog.modeled.count, 9)
        for id in CampCatalog.modeled {
            XCTAssertEqual(CampCatalog.part(id)?.isStarter, true, id)
        }
    }

    /// 96 個とも絵がある。絵は 120 × 96 の枠に収まり、読めない命令が無い
    func testEveryPartHasBoardArt() {
        XCTAssertEqual(CampDexArt.sources.count, 96)
        for part in CampCatalog.allParts {
            let art = CampDexArt.elements(for: part.id)
            XCTAssertGreaterThanOrEqual(art.count, 3, "\(part.id) の絵が無い")
            for e in art {
                let b = e.bounds
                XCTAssertGreaterThanOrEqual(b.x, -10, part.id)
                XCTAssertLessThanOrEqual(b.x + b.w, 130, part.id)
                XCTAssertLessThanOrEqual(b.y + b.h, 106, part.id)
                if case .gradient(let g) = e.fill { XCTAssertNotNil(CampDexArt.gradients[g], "\(part.id): \(g)") }
                if case .gradient(let g) = e.stroke { XCTAssertNotNil(CampDexArt.gradients[g], "\(part.id): \(g)") }
            }
        }
    }

    /// 絵の path を読む（相対・H/V・Q/T・M の後の続きの座標は線）
    func testPathParser() {
        let ops = CampDexArt.parsePath("M10 20 l5 0 H30 v-5 Q40 10 50 15 T70 15 C1 2 3 4 5 6 Z")
        XCTAssertEqual(ops, [
            .move(CampVec2(10, 20)), .line(CampVec2(15, 20)), .line(CampVec2(30, 20)), .line(CampVec2(30, 15)),
            .quad(CampVec2(40, 10), CampVec2(50, 15)), .quad(CampVec2(60, 20), CampVec2(70, 15)),
            .cubic(CampVec2(1, 2), CampVec2(3, 4), CampVec2(5, 6)), .close,
        ])
        XCTAssertEqual(CampDexArt.parsePath("M0 0 10 10 20 0"), [.move(CampVec2(0, 0)), .line(CampVec2(10, 10)), .line(CampVec2(20, 0))])
        XCTAssertEqual(CampDexArt.parsePath("M1-2L3.5.5"), [.move(CampVec2(1, -2)), .line(CampVec2(3.5, 0.5))])
        XCTAssertEqual(CampDexArt.paint("#abc"), .color(0xAABBCC))
        XCTAssertEqual(CampDexArt.paint("url(#dxwood)"), .gradient("dxwood"))
        XCTAssertNil(CampDexArt.paint("none"))
        let e = CampDexArt.parse(##"<path d="M0 0 L1 1" fill="none" stroke="#fff" stroke-width="1.6" stroke-dasharray="2 1.5"/>"##)
        XCTAssertEqual(e.count, 1)
        XCTAssertNil(e[0].fill)
        XCTAssertEqual(e[0].stroke, .color(0xFFFFFF))
        XCTAssertEqual(e[0].dash, [2, 1.5])
    }
}
