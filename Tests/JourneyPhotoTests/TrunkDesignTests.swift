import XCTest
@testable import JourneyPhoto

/// 旅のトランクの描き方の数（モック Trunk・Label・Aging の式・2026-10-17）
final class TrunkDesignTests: XCTestCase {

    private func label(_ id: String = "p1", kind: TrunkLabel.Kind = .season, name: String = "京都",
                       latin: String? = "Kyoto", country: String? = "日本", season: TrunkLabel.Season? = .spring,
                       timeslot: TrunkLabel.Timeslot? = nil, milestone: TrunkLabel.Milestone? = nil,
                       seed: Int = 41_207, foil: Bool = false) -> TrunkLabel {
        TrunkLabel(id: id, photoId: id, kind: kind, place: .init(name: name, latin: latin, country: country),
                   season: season, timeslot: timeslot, milestone: milestone, seed: seed,
                   at: "2026-04-03T09:00:00Z", foil: foil)
    }

    // MARK: 決まった描き方

    /// 同じ入力なら必ず同じ図柄（作り直すまで変わらない・端末をまたいでも同じ）
    func testSameInputGivesSameSpec() {
        let a = TrunkLabelDesign.spec(for: label())
        let b = TrunkLabelDesign.spec(for: label("other-id"))
        XCTAssertEqual(a, b, "id は図柄に効かない（種と土地と系統だけ）")
        XCTAssertEqual(a, TrunkLabelDesign.spec(for: label()))
    }

    /// 乱数は `Hasher`（起動ごとに変わる）を使わない。FNV-1a と SplitMix64 の値を固定で見張る
    func testRandomIsStableAcrossLaunches() {
        XCTAssertEqual(TrunkRandom.fnv1a(""), 0xCBF2_9CE4_8422_2325)
        XCTAssertEqual(TrunkRandom.fnv1a("a"), 0xAF63_DC4C_8601_EC8C)
        var r1 = TrunkRandom(seed: 12345, salt: "season|京都")
        var r2 = TrunkRandom(seed: 12345, salt: "season|京都")
        let first = (0..<8).map { _ in r1.next() }
        XCTAssertEqual(first, (0..<8).map { _ in r2.next() })
        XCTAssertEqual(Set(first).count, 8, "並びが詰まっている")
        // 0..<n に収まる
        var r3 = TrunkRandom(seed: 7, salt: "x")
        for _ in 0..<200 { XCTAssertTrue((0..<10).contains(r3.int(10))) }
        for _ in 0..<200 { let u = r3.unit(); XCTAssertTrue(u >= 0 && u < 1) }
    }

    /// 種を替えると図柄が替わる（作り直しの候補が「いまの」と同じばかりにならない）
    func testDifferentSeedsGiveVariety() {
        let specs = (1...40).map { TrunkLabelDesign.spec(for: label(seed: $0 * 7919)) }
        XCTAssertGreaterThan(Set(specs.map(\.shape)).count, 5, "形が偏っている")
        XCTAssertGreaterThan(Set(specs.map { $0.bg.css }).count, 1, "色が1つしか出ない")
        XCTAssertGreaterThan(Set(specs.map { $0.rot }).count, 5)
        for s in specs {
            XCTAssertTrue((-7...7).contains(Int(s.rot)), "傾きが ±7 度を越えた")
            XCTAssertTrue(s.misreg >= 0.2 && s.misreg <= 1.0, "刷りのずれが範囲外")
        }
    }

    /// 季節・時刻・節目で、絵と色の組が決まる（土地と季節は作り直しても替わらない）
    func testThemeDecidesArtAndPalette() {
        for seed in 1...30 {
            let spring = TrunkLabelDesign.spec(for: label(seed: seed))
            XCTAssertTrue(TrunkLabelDesign.arts["spring"]!.contains(spring.art!), "春なのに \(spring.art!)")
            let night = TrunkLabelDesign.spec(for: label(kind: .timeslot, season: .summer, timeslot: .night, seed: seed))
            XCTAssertTrue(TrunkLabelDesign.arts["night"]!.contains(night.art!), "夜なのに \(night.art!)")
            let first = TrunkLabelDesign.spec(for: label(kind: .milestone, milestone: .first, seed: seed))
            XCTAssertEqual(first.art, .camera)
            let country = TrunkLabelDesign.spec(for: label(kind: .milestone, country: "フィンランド", milestone: .firstCountry, seed: seed))
            XCTAssertTrue([TrunkLabelArt.globe, .plane].contains(country.art!))
            let abroad = TrunkLabelDesign.spec(for: label(kind: .place, name: "パリ", latin: "Paris", country: "フランス",
                                                          season: nil, seed: seed))
            XCTAssertTrue(TrunkLabelDesign.arts["abroad"]!.contains(abroad.art!))
        }
    }

    /// 100 枚目は箔押しの節目（モック Labels）・箔押しの印のラベルは金の地
    func testFoil() {
        XCTAssertTrue(TrunkLabelDesign.spec(for: label(kind: .milestone, milestone: .posts100)).foil)
        let foil = TrunkLabelDesign.spec(for: label(foil: true))
        XCTAssertTrue(foil.foil)
        XCTAssertEqual(foil.bg.css, "#3a2a12")
        XCTAssertEqual(foil.ac.css, "#fff1c4")
        XCTAssertFalse(TrunkLabelDesign.spec(for: label()).foil)
    }

    /// 刷る3行（紙の文字なので画面の言語で変えない）
    func testTexts() {
        let spring = TrunkLabelDesign.texts(label())
        XCTAssertEqual(spring.t1, "KYOTO")
        XCTAssertEqual(spring.t2, "京都")
        XCTAssertEqual(spring.t3, "SPRING · 春")
        let dusk = TrunkLabelDesign.texts(label(kind: .timeslot, name: "直島", latin: nil, season: .summer, timeslot: .dusk))
        XCTAssertEqual(dusk.t1, "SUNSET", "欧文の名が無ければ時刻の言葉")
        XCTAssertEqual(dusk.t3, "SUNSET · 夕焼け", "時刻のラベルは季節より時刻を刷る")
        let ten = TrunkLabelDesign.texts(label(kind: .milestone, name: "", latin: nil, milestone: .posts10))
        XCTAssertEqual(ten.t1, "TEN")
        XCTAssertEqual(ten.t2, "10 枚目")
        XCTAssertEqual(ten.t3, "PHOTOS")
        let blank = TrunkLabelDesign.texts(label(kind: .place, name: "", latin: nil, country: nil, season: nil))
        XCTAssertEqual(blank.t2, "旅の記録", "撮影地も日付も無い投稿でも空の札にしない")
        XCTAssertEqual(TrunkLabelDesign.caption(label()), "京都 · 春")
        XCTAssertEqual(TrunkLabelDesign.serial(label()), "2026.04.03")
    }

    // MARK: 寸法（モック Label の式）

    /// 260×176 の楕円（届いた画面の大きさ）を、モックの JavaScript の式で計算した値と比べる
    func testLabelLayoutMatchesMock() {
        let spec = TrunkLabelSpec(shape: .oval, bg: TrunkRGBA(0xF3E6CC), fg: TrunkRGBA(0x8E2A22), ac: TrunkRGBA(0xD98A7E),
                                  t1: "KYOTO", t2: "京都", t3: "SPRING · 桜", art: .sakura, rot: -4, misreg: 0.6, foil: false)
        let l = TrunkLabelLayout(w: 260, h: 176, spec: spec)
        XCTAssertEqual(l.border1, 6.2, accuracy: 1e-9)      // max(1.5, round(176*0.035*10)/10)
        XCTAssertEqual(l.border2, 13.4, accuracy: 1e-9)     // b1*2+1
        XCTAssertEqual(l.innerPaper, 13.4 + 2.48, accuracy: 1e-9)
        XCTAssertEqual(l.innerWidth, 192.4, accuracy: 1e-9)
        XCTAssertEqual(l.t2Size, 33.44, accuracy: 1e-9)     // min(h*0.19, innerW/len*0.96)
        XCTAssertEqual(l.t1Size, 13.2, accuracy: 1e-9)      // min(h*0.075, innerW/max(4,len)*1.25)
        XCTAssertEqual(l.t3Size, 11.264, accuracy: 1e-9)    // 「SPRING · 桜」は11字
        XCTAssertEqual(l.artHeight, 47.52, accuracy: 1e-9)
        XCTAssertEqual(l.artWidth, 192.4 * 0.78, accuracy: 1e-9)
        XCTAssertEqual(l.misregistration, 1.0 * (176.0 / 120), accuracy: 1e-9)
        XCTAssertEqual(l.padBottom, 0)
        XCTAssertFalse(l.showsCurl)
        // 小さいラベルの縁は 1.5 で止まる・ひし形は字を 0.85 倍・盾形は下を空ける
        XCTAssertEqual(TrunkLabelLayout(w: 40, h: 30, spec: spec).border1, 1.5)
        let diamond = TrunkLabelLayout(w: 96, h: 96, spec: spec.withShape(.diamond))
        XCTAssertEqual(diamond.t2Size, min(96 * 0.19, 96 * 0.52 / 2 * 0.96) * 0.85, accuracy: 1e-9)
        XCTAssertEqual(TrunkLabelLayout(w: 124, h: 96, spec: spec.withShape(.shield)).padBottom, 96 * 0.22, accuracy: 1e-9)
    }

    /// 古びたラベル: 0.45 を越えるとめくれ、色は彩度が落ちてセピアに寄る
    func testLabelAgingFadesAndCurls() {
        let spec = TrunkLabelDesign.spec(for: label())
        let old = TrunkLabelLayout(w: 100, h: 66, spec: spec, age: 0.6)
        XCTAssertTrue(old.showsCurl)
        XCTAssertEqual(old.curlSize, 66 * 0.16, accuracy: 1e-9)
        XCTAssertFalse(TrunkLabelLayout(w: 100, h: 66, spec: spec, age: 0.45).showsCurl)
        let red = TrunkRGBA(0xC8352A)
        let faded = old.faded(red)
        XCTAssertLessThan(faded.r - faded.b, red.r - red.b, "彩度が落ちていない")
        XCTAssertEqual(TrunkLabelLayout(w: 100, h: 66, spec: spec, age: 0).faded(red), red, "新しいラベルは褪せない")
        XCTAssertEqual(TrunkLabelLayout(w: 100, h: 66, spec: spec, age: 3).age, 1, "古びは 1 で止まる")
    }

    /// 形: 星形は 56 の頂点・枠に収めた大きさは形の縦横の比を保つ
    func testShapes() {
        XCTAssertEqual(TrunkLabelShape.burstPoints.count, 56)
        XCTAssertEqual(TrunkLabelShape.burstPoints[0], .init(x: 1.0, y: 0.5))
        XCTAssertEqual(TrunkLabelShape.allCases.count, 10)
        XCTAssertEqual(TrunkLabelArt.allCases.count, 22)
        let oval = TrunkLabelShape.oval.fitted(maxWidth: 92, maxHeight: 76)
        XCTAssertEqual(oval.w, 92)
        XCTAssertEqual(oval.h, 60.5, accuracy: 0.05)
        let circle = TrunkLabelShape.circle.fitted(maxWidth: 92, maxHeight: 76)
        XCTAssertEqual(circle.w, 76)
        XCTAssertEqual(circle.h, 76)
        if case .polygon(let pts) = TrunkLabelShape.shield.outline {
            XCTAssertEqual(pts.count, 5)
        } else { XCTFail("盾形が多角形でない") }
        XCTAssertEqual(TrunkLabelShape.ticket.outline, .rounded(4))
        // 絵は全部、書き方が読める（空の絵が無い）
        for art in TrunkLabelArt.allCases {
            let strokes = TrunkArtwork.strokes(art)
            XCTAssertFalse(strokes.isEmpty, "\(art)")
            for s in strokes { XCTAssertFalse(s.segments.isEmpty, "\(art) に読めない筆がある") }
        }
        for art in [TrunkArt.makie, .compass, .stars] {
            XCTAssertFalse(TrunkArtwork.strokes(art).isEmpty)
        }
    }

    // MARK: 色

    /// モックの `mix(a, b, t)` と同じ丸め（Math.round・.5 は大きい方へ）
    func testMixMatchesMock() {
        XCTAssertEqual(TrunkRGBA.mix(0x7E4828, 0xA06D45, 0).css, "#7e4828")
        XCTAssertEqual(TrunkRGBA.mix(0x7E4828, 0xA06D45, 1).css, "#a06d45")
        // g: 72 + (109-72)*0.5 = 90.5 → 91、b: 40 + 29*0.5 = 54.5 → 55
        XCTAssertEqual(TrunkRGBA.mix(0x7E4828, 0xA06D45, 0.5).css, "#8f5b37")
        XCTAssertEqual(TrunkRGBA(css: "#C9A66B"), TrunkRGBA(0xC9A66B))
        XCTAssertNil(TrunkRGBA(css: "#C9A6"))
    }

    /// CSS の `saturate`・`sepia`・`brightness` の行列
    func testCSSFilters() {
        let gray = TrunkRGBA(0xFF0000).filtered(saturate: 0)
        XCTAssertEqual(gray.r, 0.213 * 255, accuracy: 1e-6)
        XCTAssertEqual(gray.g, 0.213 * 255, accuracy: 1e-6)
        let sepia = TrunkRGBA(0xFFFFFF).filtered(sepia: 1)
        XCTAssertEqual(sepia.r, 255)
        XCTAssertEqual(sepia.b, 0.937 * 255, accuracy: 1e-6)
        XCTAssertEqual(TrunkRGBA(0x808080).filtered(brightness: 0.5).r, 64)
        XCTAssertEqual(TrunkRGBA(0x123456).filtered(), TrunkRGBA(0x123456))
    }

    /// CSS の角度のグラデーションの始まりと終わり
    func testGradientEndpoints() {
        let down = TrunkGradient.endpoints(angle: 180, width: 360, height: 268)
        XCTAssertEqual(down.start.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(down.start.y, 0, accuracy: 1e-9)
        XCTAssertEqual(down.end.y, 1, accuracy: 1e-9)
        let right = TrunkGradient.endpoints(angle: 90, width: 100, height: 50)
        XCTAssertEqual(right.start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(right.end.x, 1, accuracy: 1e-9)
        XCTAssertEqual(right.end.y, 0.5, accuracy: 1e-9)
        let diagonal = TrunkGradient.endpoints(angle: 135, width: 40, height: 40)
        XCTAssertEqual(diagonal.start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(diagonal.start.y, 0, accuracy: 1e-9)
        XCTAssertEqual(diagonal.end.x, 1, accuracy: 1e-9)
        XCTAssertEqual(diagonal.end.y, 1, accuracy: 1e-9)
    }

    // MARK: SVG の書き方

    func testSVGPathParsesMockCommands() {
        let rect = SVGPath.parse("M4 46 V30 H16 V24 H26 V46 Z")
        XCTAssertEqual(rect.first, .move(.init(x: 4, y: 46)))
        XCTAssertEqual(rect[1], .line(.init(x: 4, y: 30)))
        XCTAssertEqual(rect[2], .line(.init(x: 16, y: 30)))
        XCTAssertEqual(rect.last, .close)
        // 負の数がつながった書き方（「C80 -2 100 22」）
        let curve = SVGPath.parse("M0 26 C20 6 40 30 60 12 C80 -2 100 22 120 8")
        XCTAssertEqual(curve.count, 3)
        XCTAssertEqual(curve[2], .cubic(c1: .init(x: 80, y: -2), c2: .init(x: 100, y: 22), to: .init(x: 120, y: 8)))
        // M のあとの続きの座標は直線
        XCTAssertEqual(SVGPath.parse("M0 0 10 10"), [.move(.init(x: 0, y: 0)), .line(.init(x: 10, y: 10))])
    }

    /// 弧: 太陽の半円（M30 40 A30 30 0 0 1 90 40）は頂点 (60, 10) を通って (90, 40) に着く
    func testSVGArcSemicircle() {
        let sun = SVGPath.parse("M30 40 A30 30 0 0 1 90 40 Z")
        let cubics = sun.compactMap { seg -> SVGPath.Point? in
            if case let .cubic(_, _, to) = seg { return to }
            return nil
        }
        XCTAssertEqual(cubics.count, 2, "半円は 90° の曲線2本")
        XCTAssertEqual(cubics[0].x, 60, accuracy: 1e-6)
        XCTAssertEqual(cubics[0].y, 10, accuracy: 1e-6, "上に膨らむ（sweep=1）")
        XCTAssertEqual(cubics[1], .init(x: 90, y: 40))
        // 半径が足りない弧（月の内側 r16 で弦 34）は広げて半円にする
        let moon = SVGPath.parse("M70 4 A20 20 0 1 0 86 34 A16 16 0 1 1 70 4 Z")
        guard case let .cubic(_, _, end) = moon[moon.count - 2] else { return XCTFail("月の終わりが曲線でない") }
        XCTAssertEqual(end, .init(x: 70, y: 4))
        // 外の弧は左（中心 ≒ (68.7, 24)）を回る: どこかで x が 50 を割る
        let xs = moon.compactMap { seg -> Double? in
            if case let .cubic(_, _, to) = seg { return to.x }
            return nil
        }
        XCTAssertLessThan(xs.min() ?? 100, 50.5)
    }

    func testCircleAndRect() {
        let c = SVGPath.circle(cx: 10, cy: 10, r: 5)
        XCTAssertEqual(c.first, .move(.init(x: 15, y: 10)))
        XCTAssertEqual(c.count, 6)
        XCTAssertEqual(SVGPath.rect(x: 0, y: 0, w: 10, h: 4).count, 5)
        XCTAssertEqual(SVGPath.rect(x: 0, y: 0, w: 10, h: 4, r: 2).count, 10)
        let moved = SVGPath.translate([.move(.init(x: 0, y: -26))], dx: 180, dy: 40)
        XCTAssertEqual(moved, [.move(.init(x: 180, y: 14))])
    }

    // MARK: 古び方（モック Aging・MaterialAging）

    func testAgingIsContinuousByPosts() {
        XCTAssertEqual(TrunkAging.stage(posts: 0), 0)
        XCTAssertEqual(TrunkAging.stage(posts: 1), 0.01, accuracy: 1e-12)
        XCTAssertEqual(TrunkAging.stage(posts: 45), 0.45, accuracy: 1e-12)
        XCTAssertEqual(TrunkAging.stage(posts: 100), 1)
        XCTAssertEqual(TrunkAging.stage(posts: 500), 1)
        XCTAssertEqual(TrunkAging.stage(posts: -3), 0)
        // 投稿1件ごとに少しずつ（段にならない）
        let steps = (0...100).map { TrunkAging.stage(posts: $0) }
        XCTAssertEqual(Set(steps).count, 101)
        XCTAssertEqual([0, 19, 20, 49, 50, 79, 80, 120].map(TrunkAging.tagCount), [0, 0, 1, 1, 2, 2, 3, 3])
        // 古いラベルほど褪せる（モックの st * (1 - k/n) * 1.05）
        XCTAssertEqual(TrunkAging.labelAge(index: 0, count: 7, stage: 0.55), 0.5775, accuracy: 1e-12)
        XCTAssertEqual(TrunkAging.labelAge(index: 6, count: 7, stage: 0.55), 0.55 * (1.0 / 7) * 1.05, accuracy: 1e-12)
        XCTAssertEqual(TrunkAging.labelAge(index: 0, count: 1, stage: 1), 1)
        XCTAssertEqual(TrunkAging.latestMilestone(posts: 2)?.posts, nil)
        XCTAssertEqual(TrunkAging.latestMilestone(posts: 20)?.posts, 20)
        XCTAssertEqual(TrunkAging.latestMilestone(posts: 99)?.posts, 80)
    }

    /// 型ごとの色は古び方で動く（新品と投稿 100 で別の色・金具はくすむ）
    func testModelLooksAgeWithPosts() {
        for model in TrunkModel.allCases {
            let fresh = TrunkLooks.look(model, stage: 0)
            let old = TrunkLooks.look(model, stage: 1)
            XCTAssertEqual(fresh.model, model)
            if model == .aluminum || model == .clipper {
                // アルミは地の色ではなく擦り傷で古びる
                XCTAssertGreaterThan(old.scratch, fresh.scratch, "\(model) に擦り傷が増えない")
            } else {
                XCTAssertNotEqual(fresh.surface, old.surface, "\(model) の地が古び方で変わらない")
            }
        }
        // 革: 新品は #7e4828、投稿 100 で #a06d45（モックの値）
        if case let .radial(inner, _, _, _, _) = TrunkLooks.look(.leather, stage: 0).surface {
            XCTAssertEqual(inner.css, "#7e4828")
        } else { XCTFail() }
        if case let .radial(inner, _, _, _, _) = TrunkLooks.look(.leather, stage: 1).surface {
            XCTAssertEqual(inner.css, "#a06d45")
        } else { XCTFail() }
        XCTAssertEqual(TrunkMetal.brass.stops(0)[1].color.css, "#c9a66b")
        XCTAssertEqual(TrunkMetal.brass.stops(1)[1].color.css, "#957a48")
        // 部品: アルミの留め金・漆の組紐・柳行李の縄と革の留め・寝台列車と飛行艇の名札・船長の羅針盤・星図
        XCTAssertTrue(TrunkLooks.look(.aluminum, stage: 0).latches)
        XCTAssertNotNil(TrunkLooks.look(.urushi, stage: 0).cords)
        XCTAssertNotNil(TrunkLooks.look(.kori, stage: 0).hemp)
        XCTAssertTrue(TrunkLooks.look(.kori, stage: 0).lock.tab)
        XCTAssertEqual(TrunkLooks.look(.sleeper, stage: 0).plate, .brass)
        XCTAssertEqual(TrunkLooks.look(.clipper, stage: 0).plate, .chrome)
        XCTAssertEqual(TrunkLooks.look(.captain, stage: 0).art, .compass)
        XCTAssertEqual(TrunkLooks.look(.starchart, stage: 0).art, .stars)
        XCTAssertEqual(TrunkLooks.look(.urushi, stage: 0).art, .makie)
        XCTAssertEqual(TrunkLooks.look(.aluminum, stage: 0.5).scratch, 0.5)
        XCTAssertEqual(TrunkLooks.look(.clipper, stage: 1).scratch, 0.7, accuracy: 1e-12)
        // 鋲: アルミは上下2列・24 ごと（22〜338）、衣装箱は桟の上に4つずつ
        let aluminum = TrunkLooks.rivets(TrunkLooks.look(.aluminum, stage: 0))
        XCTAssertEqual(aluminum.count, 2 * 14)
        let steamer = TrunkLooks.rivets(TrunkLooks.look(.steamer, stage: 0))
        XCTAssertEqual(steamer.count, 8)
        XCTAssertEqual(TrunkLooks.lockTop(TrunkLooks.look(.leather, stage: 0)), 84 - 15 + 2.5)
        XCTAssertEqual(TrunkLooks.lockTop(TrunkLooks.look(.kori, stage: 0)), 80)
    }

    /// 貼ったラベルの置き場: 11 か所・新しい 11 枚・古いほど褪せる・置き場の中に収まる
    func testSlotPlacement() {
        let stuck = (0..<14).map { label("s\($0)", seed: 100 + $0) }  // 新しい順
        let placed = TrunkSlots.place(stuck, stage: 1)
        XCTAssertEqual(placed.count, 11)
        XCTAssertEqual(placed.last?.label.id, "s0", "いちばん新しいラベルが出ていない")
        XCTAssertEqual(placed.first?.label.id, "s10", "並べる 11 枚の中で古い順に置く")
        XCTAssertGreaterThan(placed[0].age, placed[10].age)
        for (k, p) in placed.enumerated() {
            let slot = TrunkSlots.slots[TrunkSlots.order[k]]
            XCTAssertGreaterThanOrEqual(p.x, slot.x - 1e-9)
            XCTAssertLessThanOrEqual(p.x + p.w, slot.x + slot.w + 1e-9)
            XCTAssertLessThanOrEqual(p.y + p.h, slot.y + slot.h + 1e-9)
        }
        XCTAssertEqual(TrunkSlots.place([], stage: 1), [])
        XCTAssertEqual(Set(TrunkSlots.order).count, 11)
    }
}

private extension TrunkLabelSpec {
    func withShape(_ shape: TrunkLabelShape) -> TrunkLabelSpec {
        TrunkLabelSpec(shape: shape, bg: bg, fg: fg, ac: ac, t1: t1, t2: t2, t3: t3, art: art, rot: rot,
                       misreg: misreg, foil: foil)
    }
}
