import XCTest
@testable import JourneyPhoto

/// 羅針盤の硬貨とカプセルの機械（札 #716）・かけらの切符（札 #713）。2026-11-23 owner 採用の案の頁の時間、曲線、言葉と、
/// 画面のつなぎを見張る
final class TrunkCoinMachineTests: XCTestCase {

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

    // MARK: 回すときの手ざわり

    /// 🔴 引っかかり: 目盛りの間は指の 45% だけ進み、72% を越えると次の目盛りへ跳ぶ
    func testDetentDragsThenSnapsToTheNextTick() {
        XCTAssertEqual(TrunkCrank.detent(raw: 0), 0)
        XCTAssertEqual(TrunkCrank.detent(raw: 10), 30 * 0.45 * (10.0 / 30 / 0.72), accuracy: 0.0001, "目盛りの間で重くない")
        XCTAssertLessThan(TrunkCrank.detent(raw: 21), 30 * 0.45 + 0.0001, "72% より手前で跳んだ")
        XCTAssertEqual(TrunkCrank.detent(raw: 21.7), 30, "72% を越えても跳ばない")
        XCTAssertEqual(TrunkCrank.detent(raw: 30), 30)
        XCTAssertEqual(TrunkCrank.detent(raw: 352), 360, "最後の目盛りで1周にならない")
        XCTAssertEqual(TrunkCrank.detent(raw: 400), 360)
        // 指を動かすと見せる角度は目盛りの上か、目盛りの間の 45% までのどこか
        for raw in stride(from: 0.0, through: 360, by: 0.5) {
            let shown = TrunkCrank.detent(raw: raw)
            let within = shown.truncatingRemainder(dividingBy: 30)
            XCTAssertTrue(within < 30 * 0.45 + 0.0001 || within > 29.9999, "\(raw)° で目盛りの間に止まる: \(shown)")
        }
    }

    /// 🔴 指で回すと、跳んだ回だけカチッ（目盛り 12 個）。ハンドルの角度は 0°（北の目盛り）から
    func testCrankClicksOnlyWhenItSnaps() {
        var c = TrunkCrank()
        XCTAssertEqual(c.angle, 0, "北の目盛りから回らない")
        XCTAssertEqual(c.litTicks, 0)
        c.begin(dx: 10, dy: 0)
        // 3 時から 20° だけ指を回す: まだ跳ばない
        let a = 20.0 * .pi / 180
        XCTAssertEqual(c.drag(dx: 10 * cos(a), dy: 10 * sin(a)), 0, "跳ぶ前にカチッと鳴った")
        XCTAssertLessThan(c.angle, 14)
        // 25° まで: 跳ぶ（1つ）
        let b = 25.0 * .pi / 180
        XCTAssertEqual(c.drag(dx: 10 * cos(b), dy: 10 * sin(b)), 1)
        XCTAssertEqual(c.angle, 30)
        XCTAssertEqual(c.litTicks, 1)
        var full = TrunkCrank()
        var clicks = 0
        for _ in 0..<TrunkGachaFlow.autoSteps { clicks += full.autoAdvance() }
        XCTAssertEqual(clicks, 12)
        XCTAssertEqual(full.litTicks, 12)
    }

    // MARK: 時間と曲線

    func testBezierMatchesCSS() {
        XCTAssertEqual(TrunkBezier.linear.value(0.3), 0.3, accuracy: 0.001)
        XCTAssertEqual(TrunkBezier.easeInOut.value(0.5), 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(TrunkBezier.easeOut.value(0.3), 0.3)
        // 行き過ぎる曲線は途中で 1 を越える（ボタンで回す1歩・溜めの戻り）
        let over = (1...99).map { TrunkMotion.autoStepCurve.value(Double($0) / 100) }.max() ?? 0
        XCTAssertGreaterThan(over, 1, "行き過ぎない")
        XCTAssertEqual(TrunkMotion.autoStepCurve.value(1), 1)
    }

    /// 🔴 針は -38° から揺れて北（0°）で止まる（1.15 秒・案の頁のキーフレーム）
    func testNeedleWobblesAndStopsNorth() {
        XCTAssertEqual(TrunkMotion.needleAngle(elapsed: 0), -38, accuracy: 0.0001)
        XCTAssertEqual(TrunkMotion.needleAngle(elapsed: 0.2 * 1.15), 22, accuracy: 0.0001)
        XCTAssertEqual(TrunkMotion.needleAngle(elapsed: 0.4 * 1.15), -12, accuracy: 0.0001)
        XCTAssertEqual(TrunkMotion.needleAngle(elapsed: 1.15), 0, accuracy: 0.0001)
        XCTAssertEqual(TrunkMotion.needleAngle(elapsed: 9), 0, accuracy: 0.0001, "止まったあとも揺れる")
        // 縁の光は 24 本目まで順に点いて消える
        XCTAssertEqual(TrunkMotion.rimLightOpacity(arc: 0, elapsed: 0.95 * 0.18), 0.9, accuracy: 0.001)
        XCTAssertEqual(TrunkMotion.rimLightOpacity(arc: 23, elapsed: 0.5), 0, "まだの弧が点いた")
        XCTAssertEqual(TrunkMotion.rimLightOpacity(arc: 23, elapsed: TrunkMotion.pickUpSeconds), 0, accuracy: 0.001)
    }

    /// 🔴 カプセルが落ちる: 0.62 秒。55% で底に着き、76% で 11pt 弾み、100% で止まる
    func testCapsuleDropsLandsAndBouncesOnce() {
        XCTAssertEqual(TrunkMotion.dropOffset(elapsed: 0), -64, accuracy: 0.0001)
        XCTAssertEqual(TrunkMotion.dropOffset(elapsed: TrunkMotion.landsAt), 0, accuracy: 0.0001, "底に着く時刻がずれた")
        XCTAssertEqual(TrunkMotion.dropOffset(elapsed: 0.62 * 0.76), -11, accuracy: 0.0001)
        XCTAssertEqual(TrunkMotion.dropOffset(elapsed: 0.62), 0, accuracy: 0.0001)
        XCTAssertEqual(TrunkMotion.landsAt, 0.341, accuracy: 0.001)
        // 弾むのは1回だけ（底に着いたあと、上へ上がって戻るのは1度）
        var ups = 0
        var last = 0.0
        var rising = false
        for i in 0...620 {
            let y = TrunkMotion.dropOffset(elapsed: Double(i) / 1000)
            if y < last - 1e-6 && !rising && Double(i) / 1000 > TrunkMotion.landsAt { rising = true; ups += 1 }
            if y > last + 1e-6 { rising = false }
            last = y
        }
        XCTAssertEqual(ups, 1, "弾みの回数が1回でない")
    }

    /// 硬貨をもらう瞬間: 上から回りながら落ち、札の 14pt（40 の 0.35 倍）に収まる
    func testCoinFallEndsInTheChip() {
        XCTAssertEqual(TrunkMotion.coinFallY.value(0), -170)
        XCTAssertEqual(TrunkMotion.coinFallY.value(1), 0)
        XCTAssertEqual(TrunkMotion.coinFallOpacity.value(0), 0)
        XCTAssertEqual(TrunkMotion.coinFallSize * TrunkMotion.coinFallScale.value(1), 14, accuracy: 0.0001, "札の硬貨と大きさが合わない")
        XCTAssertEqual(TrunkMotion.coinFlip.value(0.2), 0.1, accuracy: 0.0001, "回っていない")
        XCTAssertEqual(TrunkMotion.coinFlip.value(1), 1)
        XCTAssertEqual(TrunkMotion.chipBump.value(0.45), 1.07, accuracy: 0.0001)
    }

    /// 開けた画面の衝撃の輪、きらめき、揺れ、層のずれは、決まった値で終わり、決まった範囲で動く
    func testOpenEffectsStayInRange() {
        XCTAssertEqual(TrunkMotion.shock(elapsed: 0).scale, 0.3, accuracy: 0.0001)
        XCTAssertEqual(TrunkMotion.shock(elapsed: 0.7).opacity, 0)
        XCTAssertEqual(TrunkMotion.shock(elapsed: -0.1).opacity, 0, "割れる前に輪が出た")
        XCTAssertEqual(TrunkMotion.twinkle(elapsed: 1, delay: 2).opacity, 0, "遅れの前に瞬いた")
        XCTAssertEqual(TrunkMotion.twinkle(elapsed: 1.3, delay: 0).opacity, 1, accuracy: 0.001)
        for t in stride(from: 0.0, through: 7.2, by: 0.1) {
            let y = TrunkMotion.bob(elapsed: t)
            XCTAssertLessThanOrEqual(y, 0.0001)
            XCTAssertGreaterThanOrEqual(y, -TrunkMotion.bobHeight - 0.0001)
        }
        let a = TrunkMotion.jostle(layer: 0, beat: 3, k: 0.7), b = TrunkMotion.jostle(layer: 0, beat: 3, k: 0.7)
        XCTAssertEqual(a.dx, b.dx, "同じ回と層でずれが変わる")
        for layer in 0..<3 {
            for beat in 0..<50 {
                let j = TrunkMotion.jostle(layer: layer, beat: beat, k: 1)
                XCTAssertLessThanOrEqual(abs(j.dx), 3.2 + 0.0001)
                XCTAssertLessThan(j.dy, 0, "上へずれない")
                XCTAssertGreaterThanOrEqual(j.dy, -4.2 - 0.0001)
            }
        }
        XCTAssertEqual(TrunkMotion.sweep(elapsed: 1).opacity, 0, "休みの間に光が走った")
        XCTAssertGreaterThan(TrunkMotion.sweep(elapsed: 6 * 0.65).opacity, 0.9)
    }

    // MARK: かけらの切符（札 #713）

    /// 🔴 5つの切れ端で1枚の切符。隣の切れ端は同じ裂け目を分け合い、端は切符の端
    func testFragmentPiecesTileTheTicket() {
        XCTAssertEqual(TrunkFragmentTicket.pieces, 5)
        let first = TrunkFragmentTicket.piece(0), last = TrunkFragmentTicket.piece(4)
        XCTAssertEqual(first.map(\.x).min(), 0)
        XCTAssertEqual(last.map(\.x).max(), TrunkFragmentTicket.width)
        for i in 0..<4 {
            let right = TrunkFragmentTicket.piece(i).filter { $0.x > Double(i) * 20 + 10 }
            let nextLeft = TrunkFragmentTicket.piece(i + 1).filter { $0.x < Double(i + 1) * 20 + 10 }
            XCTAssertEqual(Set(right.map { "\($0.x),\($0.y)" }), Set(nextLeft.map { "\($0.x),\($0.y)" }),
                           "\(i) と \(i + 1) の裂け目がずれて隙間ができる")
        }
        // 裂け目は上から下まで（ぎざぎざ）
        let cut = TrunkFragmentTicket.cutLine(20)
        XCTAssertEqual(cut.first?.y, 0)
        XCTAssertEqual(cut.last?.y ?? 0, TrunkFragmentTicket.height, accuracy: 0.0001)
        XCTAssertNotEqual(cut[0].x, cut[1].x, "裂け目がまっすぐ")
        XCTAssertEqual(TrunkFragmentTicket.filled(9), 5)
        XCTAssertEqual(TrunkFragmentTicket.filled(-1), 0)
    }

    func testFragmentWording() {
        XCTAssertEqual(TrunkFragmentText.count(3), "3 / 5")
        XCTAssertEqual(TrunkFragmentText.tileCaption(3), "3 / 5")
        XCTAssertEqual(TrunkFragmentText.tileCaption(5), "交換できます")
        XCTAssertEqual(TrunkFragmentText.chip(1), "かけら +1")
    }

    /// 🔴 投稿のお礼のかけら（札 #713）: 今のサーバーは返さない（0）。返したら届いた画面の札と知らせに出る
    @MainActor
    func testPostRewardFragmentIsReadWhenTheServerSendsIt() async {
        XCTAssertEqual(TrunkDealt.read(Data(#"{"coin": 1}"#.utf8)).fragment, 0, "返さないサーバーでかけらを出した")
        XCTAssertEqual(TrunkDealt.read(Data(#"{"coin": 1, "fragment": 1}"#.utf8)).fragment, 1)
        XCTAssertEqual(TrunkDealt.read(Data(#"{"fragment": 7}"#.utf8)).fragment, 0, "0 か 1 の外の値を読んだ")
        let arrivals = TrunkArrivals()
        arrivals.deliver(TrunkDealt(coin: 1, fragment: 1), photoTitle: "")
        XCTAssertEqual(arrivals.consumeNotice()?.text, "硬貨を1枚もらいました。カプセルの機械で使えます。 かけらも1つもらいました。",
                       "文のつなぎに「。」が無い")
        let onlyFragment = TrunkArrivals()
        onlyFragment.deliver([], notice: nil, coins: 0, fragments: 1)
        XCTAssertEqual(onlyFragment.consumeNotice(), .fragments(1))
        let coinsOnly = TrunkArrivals()
        coinsOnly.deliver(TrunkDealt(coin: 1), photoTitle: "")
        XCTAssertEqual(coinsOnly.consumeNotice(), .coins(1), "かけらが無いのに知らせが変わった")
        let view = try? source("Features/Trunk/LabelArrivedView.swift")
        XCTAssertTrue(view?.contains("if batch.fragments > 0 {") == true, "届いた画面にかけらの札が無い")
    }

    // MARK: 言葉（案の頁の「言葉」の表）

    /// 🔴 実況の文を消し、結果と次にできることだけ
    func testMachineWording() {
        XCTAssertEqual(TrunkGachaText.spinTitle(coins: 3), "硬貨を入れて回す")
        XCTAssertEqual(TrunkGachaText.spinHint(coins: 3, phase: .idle), "ハンドルを指で回しても出ます")
        XCTAssertEqual(TrunkGachaText.spinHint(coins: 0, phase: .idle), "公開の投稿1件で、硬貨を1枚もらえます（1日3枚まで）")
        XCTAssertEqual(TrunkGachaText.spinHint(coins: 3, phase: .idle, offline: true), "電波が戻ると回せます")
        XCTAssertEqual(TrunkGachaText.spinHint(coins: 3, phase: .turning), "途中で離すと戻ります。硬貨は減りません")
        XCTAssertEqual(TrunkGachaText.spinHint(coins: 3, phase: .waiting), "", "待つ間に実況の文が出る")
        XCTAssertEqual(TrunkGachaText.spinHint(coins: 3, phase: .out), "", "出たときに実況の文が出る")
        XCTAssertEqual(TrunkGachaText.turningTitle, "ハンドルを右へ回す")
        XCTAssertEqual(TrunkGachaText.offlineNote, "電波が無いので回せません。硬貨は減りません")
        let kiku = TrunkPartCatalog.part("lock.2")!
        XCTAssertEqual(TrunkGachaText.openTitle(kiku), "真鍮の錠前「菊」が出ました")
        XCTAssertEqual(TrunkGachaText.freshNote, "どの型のトランクにも付けられます")
        XCTAssertEqual(TrunkGachaText.duplicateNote(fragments: 3), "持っている部品でした。かけらを1つもらいました（3 / 5）")
        XCTAssertEqual(TrunkGachaText.agingNote, "トランクと一緒に\n古びていきます")
        XCTAssertEqual(TrunkGachaText.keepTitle, "部品箱に入れる")
        XCTAssertEqual(TrunkGachaText.againTitle, "もう1回まわす")
        XCTAssertEqual(TrunkGachaText.equippedNotice(kiku), "「菊」をトランクに付けました")
        XCTAssertEqual(TrunkGachaText.arrivedWhileAway(TrunkGachaResult(part: kiku, duplicate: true, fragments: 3, coins: 0)),
                       "「菊」は持っている部品でした。かけらを1つもらいました")
        XCTAssertEqual(TrunkText.coinNotice(1), "硬貨を1枚もらいました。カプセルの機械で使えます")
        XCTAssertEqual(TrunkText.coinAlsoNotice(1), "硬貨は1枚もらいました。")
        XCTAssertEqual(TrunkText.coinChip(1), "硬貨 +1", "札は変えない")
        for text in [TrunkGachaText.spinHint(coins: 3, phase: .idle), TrunkGachaText.turningTitle] {
            XCTAssertFalse(text.contains("まわ"), "「回す」をひらがなで書いた: \(text)")
        }
    }

    /// 🔴 開けた画面のボタン: 新しい部品は「トランクに付ける」、持っている部品は硬貨があれば「もう1回まわす」、無ければ「部品箱に入れる」
    func testOpenScreenActions() {
        XCTAssertEqual(TrunkGachaText.openActions(duplicate: false, coins: 0), .equip)
        XCTAssertEqual(TrunkGachaText.openActions(duplicate: false, coins: 3), .equip)
        XCTAssertEqual(TrunkGachaText.openActions(duplicate: true, coins: 2), .again)
        XCTAssertEqual(TrunkGachaText.openActions(duplicate: true, coins: 0), .keep)
    }

    // MARK: 画面のつなぎ

    func testMachineWiring() throws {
        let gacha = try source("Features/Trunk/TrunkGachaView.swift")
        XCTAssertTrue(gacha.contains(".disabled(!idleControls.canTurn)"), "圏外でもボタンが押せる")
        XCTAssertTrue(gacha.contains("Text(TrunkGachaText.offlineNote)"), "圏外の一言を回す前に出していない")
        XCTAssertTrue(gacha.contains("guard !cannotTurn else {\n                        if !wiggledThisTouch { wiggledThisTouch = true; wiggle() }"),
                      "0枚・圏外でハンドルを触っても揺れない")
        XCTAssertTrue(gacha.contains("guard TrunkGachaFlow.afterOpenClosed(again: again, coins: coins, offline: offline) else { return }"),
                      "閉じたあとの「もう1回まわす」が決まりを通っていない")
        XCTAssertTrue(gacha.contains("TrunkGachaFlow.shownCoins(stored: model.state?.coins ?? 0, phase: phase, inserting: inserting)"))
        XCTAssertTrue(gacha.contains("await insertCoin()"), "硬貨が入れ口へ飛ばない")
        XCTAssertTrue(gacha.contains("let wound = Task { await windUpTurn() }"), "1周で溜めていない")
        XCTAssertTrue(gacha.contains("TrunkGachaCrankTicks(lit:"), "ハンドルの目盛りが無い")
        XCTAssertTrue(gacha.contains("TrunkMotion.dropOffset(elapsed:"), "落ちて弾まない")
        XCTAssertTrue(gacha.contains(".scaleEffect(x: 1, y: flap, anchor: .top)"), "取り出し口のふたが無い")
        XCTAssertTrue(gacha.contains("onAgain: { againRequested = true }"), "「もう1回まわす」が機械へつながらない")
        XCTAssertTrue(gacha.contains("TrunkFragmentPieceView(index:"), "開けた画面でかけらが札へ飛ばない")
        XCTAssertTrue(gacha.contains("TrunkFragmentTicketView(filled: ticketCount, width: 84)"))
        XCTAssertTrue(gacha.contains("TrunkGachaRays()"), "光の放射が無い")
        // 動きを減らす設定では、終わった形をすぐ出す
        XCTAssertTrue(gacha.contains("if reduceMotion {\n            shownFragments = result.fragments"))
        XCTAssertTrue(gacha.contains("guard !reduceMotion, stackFrame != .zero"), "動きを減らす設定でも硬貨が飛ぶ")
        // 重い描き方は1枚にまとめる
        XCTAssertGreaterThanOrEqual(gacha.components(separatedBy: ".drawingGroup()").count - 1, 3)
        let box = try source("Features/Trunk/TrunkPartsBoxView.swift")
        XCTAssertFalse(box.contains("struct TrunkFragmentMark"), "真鍮のひし形が残っている")
        XCTAssertTrue(box.contains("TrunkFragmentTicketView(filled: exchanged ? TrunkPartsBoxText.fragmentsPerExchange : fragments, width: 84)"),
                      "交換のシートに切符が無い")
        let home = try source("Features/Trunk/TrunkView.swift")
        XCTAssertTrue(home.contains("TrunkFragmentText.tilePlacement(fragments: state.fragments, accessibilitySize: typeSize.isAccessibilitySize)"),
                      "トランクの部品箱のカードにかけらが無い")
        XCTAssertTrue(try source("Features/Trunk/LabelArrivedView.swift").contains("TrunkMotion.coinFallY.value(p)"),
                      "届いた画面で硬貨が落ちてこない")
    }

    // MARK: 確かめ役の指摘（2026-11-23）

    /// 🔴 開けた画面の時計: 一度きりの動き（割れる、輪、切れ端が飛ぶ）が終わったら 30 コマ毎秒に落とし、画面に出ていない間は止める
    func testOpenClockSettlesAndStops() {
        for duplicate in [false, true] {
            let settle = TrunkOpenClock.settleAt(duplicate: duplicate)
            XCTAssertGreaterThanOrEqual(settle, TrunkOpenClock.partAt + TrunkMotion.shockSeconds, "輪が広がり切る前に落とす")
            XCTAssertGreaterThanOrEqual(settle, TrunkMotion.openDelay + TrunkMotion.splitSeconds)
            XCTAssertLessThan(settle, 3, "一度きりの動きが長すぎる（毎コマの時計が止まらない）")
            // 落としたあとは一度きりの動きが動かない
            XCTAssertEqual(TrunkMotion.shock(elapsed: settle - TrunkOpenClock.partAt).opacity, 0)
        }
        XCTAssertGreaterThanOrEqual(TrunkOpenClock.settleAt(duplicate: true), TrunkOpenClock.fragmentDoneAt, "切れ端が入る前に落とす")
        XCTAssertNil(TrunkOpenClock.frameInterval(settled: false))
        XCTAssertEqual(TrunkOpenClock.frameInterval(settled: true), 1.0 / 30)
        XCTAssertTrue(TrunkOpenClock.paused(started: false, visible: true), "動きを減らす設定で時計が回る")
        XCTAssertTrue(TrunkOpenClock.paused(started: true, visible: false), "画面に出ていないのに時計が回る")
        XCTAssertFalse(TrunkOpenClock.paused(started: true, visible: true))
        let open = try? source("Features/Trunk/TrunkGachaView.swift")
        let body = open.flatMap { text in text.range(of: "struct TrunkGachaOpenView").map { String(text[$0.upperBound...]) } } ?? ""
        XCTAssertEqual(body.components(separatedBy: "TimelineView(").count - 1, 1, "開けた画面の時計が舞台の外も包んでいる")
    }

    /// 🔴 硬貨が6枚以上でも、入れたいちばん上が回り始めて戻って見えない（入れる間から1枚引いた数のまま）
    func testInsertedCoinStaysGoneWhileTurning() {
        for stored in [1, 3, 5, 6, 9] {
            let inserting = TrunkGachaFlow.shownCoins(stored: stored, phase: .idle, inserting: true)
            let turning = TrunkGachaFlow.shownCoins(stored: stored, phase: .turning, inserting: false)
            let waiting = TrunkGachaFlow.shownCoins(stored: stored, phase: .waiting, inserting: false)
            XCTAssertEqual(inserting, stored - 1)
            XCTAssertEqual(turning, inserting, "\(stored) 枚: 回り始めると数が戻る")
            XCTAssertEqual(TrunkCoinStack.drawn(turning), TrunkCoinStack.drawn(inserting), "\(stored) 枚: 重ねた絵が戻る")
            XCTAssertEqual(waiting, turning)
        }
        XCTAssertEqual(TrunkGachaFlow.shownCoins(stored: 6, phase: .idle, inserting: false), 6)
        XCTAssertEqual(TrunkGachaFlow.shownCoins(stored: 0, phase: .turning, inserting: false), 0)
    }

    /// 🔴 圏外: 回す前に一言、ボタンは押せず、ハンドルは揺れるだけ。0枚は投稿への一手で一言は出さない
    func testOfflineAndZeroCoinControls() {
        let offline = TrunkGachaFlow.idle(coins: 3, offline: true)
        XCTAssertFalse(offline.canTurn, "圏外でボタンが押せる")
        XCTAssertTrue(offline.offlineNote, "圏外の一言が出ない")
        XCTAssertFalse(offline.crankTurns, "圏外でハンドルが回り始める")
        let zero = TrunkGachaFlow.idle(coins: 0, offline: false)
        XCTAssertFalse(zero.canTurn)
        XCTAssertFalse(zero.offlineNote, "0枚に圏外の一言が出る")
        XCTAssertFalse(zero.crankTurns)
        XCTAssertFalse(TrunkGachaFlow.idle(coins: 0, offline: true).offlineNote, "0枚は投稿の一手が先")
        XCTAssertTrue(TrunkGachaFlow.idle(coins: 3, offline: false).canTurn)
        XCTAssertFalse(TrunkGachaFlow.idle(coins: 3, offline: false, busy: true).canTurn, "送っている間に押せる")
        // 開けた画面を閉じたあと: 「もう1回まわす」なら続けて回す（圏外・0枚・押していないなら回さない）
        XCTAssertTrue(TrunkGachaFlow.afterOpenClosed(again: true, coins: 2, offline: false))
        XCTAssertFalse(TrunkGachaFlow.afterOpenClosed(again: false, coins: 2, offline: false), "閉じただけで回った")
        XCTAssertFalse(TrunkGachaFlow.afterOpenClosed(again: true, coins: 2, offline: true), "圏外なのに続けて回った")
        XCTAssertFalse(TrunkGachaFlow.afterOpenClosed(again: true, coins: 0, offline: false))
        // 押しただけ（動きが少ない）は、ボタンと同じ道（硬貨が入れ口へ飛ぶ）
        var tapped = TrunkCrank()
        tapped.begin(dx: 10, dy: 0)
        XCTAssertEqual(TrunkGachaFlow.release(tapped), .autoTurn)
    }

    /// 🔴 届いた一言: 硬貨・いっぱい・容量のどれと重なっても、かけらを消さず、文は「。」でつなぐ
    @MainActor
    func testFragmentNoticeSurvivesOtherNotices() async {
        let full = TrunkArrivals()
        full.deliver([], notice: .full, coins: 1, fragments: 1)
        let fullText = full.consumeNotice()?.text ?? ""
        XCTAssertTrue(fullText.contains("かけらも1つもらいました。"), "いっぱいの一言でかけらが消えた: \(fullText)")
        XCTAssertTrue(fullText.contains(TrunkText.coinAlsoNotice(1)), "硬貨が消えた")
        let storage = TrunkArrivals()
        storage.deliver([], notice: .storage, coins: 0, fragments: 1)
        XCTAssertEqual(storage.consumeNotice(), .withFragments(.storage, 1))
        // サーバーの確かめ役の指摘（#713）: 容量切れで硬貨とかけらが届いた回も、かけらを言う
        let storageCoins = TrunkArrivals()
        storageCoins.deliver(TrunkDealt(labelSkipped: .storage, coin: 1, fragment: 1), photoTitle: "")
        let storageNotice = storageCoins.consumeNotice()
        XCTAssertEqual(storageNotice, .withFragments(.storageAndCoins(1), 1))
        XCTAssertTrue(storageNotice?.text.hasSuffix(TrunkText.fragmentAlsoNotice(1)) == true, "容量切れの一言でかけらが黙って増える")
        let fullCoins = TrunkArrivals()
        fullCoins.deliver(TrunkDealt(labelSkipped: .full, coin: 1, fragment: 1), photoTitle: "")
        XCTAssertEqual(fullCoins.consumeNotice(), .withFragments(.fullAndCoins(1), 1), "いっぱいの一言でかけらが黙って増える")
        XCTAssertEqual(TrunkArrivals.Notice.joined("硬貨をもらいました", "かけらも"), "硬貨をもらいました。 かけらも")
        XCTAssertEqual(TrunkArrivals.Notice.joined("届きました。", "かけらも"), "届きました。 かけらも")
    }

    /// 🔴 トランクの部品箱のカード: 既定は印の右、アクセシビリティの大きさは名前の行の下。字は 12pt を下回らない
    func testTileFragmentsFit() throws {
        XCTAssertNil(TrunkFragmentText.tilePlacement(fragments: 0, accessibilitySize: false))
        XCTAssertEqual(TrunkFragmentText.tilePlacement(fragments: 3, accessibilitySize: false), .beside)
        XCTAssertEqual(TrunkFragmentText.tilePlacement(fragments: 3, accessibilitySize: true), .below)
        XCTAssertGreaterThanOrEqual(TrunkFragmentText.tileFontSize * TrunkFragmentText.tileMinimumScale, 12 - 1e-9, "12pt を下回って縮む")
        let home = try source("Features/Trunk/TrunkView.swift")
        let start = try XCTUnwrap(home.range(of: "private func fragmentCaption("))
        let caption = String(home[start.lowerBound...].prefix(900))
        XCTAssertFalse(caption.contains(".fixedSize()"), "字を固定の幅にしてカードの外へ出す")
        XCTAssertTrue(caption.contains(".minimumScaleFactor(TrunkFragmentText.tileMinimumScale)"))
    }

    /// 交換のシート: 頼んでから閉じるまでボタンを押せない
    func testExchangeLocksUntilClosed() throws {
        XCTAssertTrue(TrunkPartsBoxText.exchangeLocked(busy: false, exchanging: true), "交換が通って閉じるまでの間に押せる")
        XCTAssertTrue(TrunkPartsBoxText.exchangeLocked(busy: true, exchanging: false))
        XCTAssertFalse(TrunkPartsBoxText.exchangeLocked(busy: false, exchanging: false))
        let box = try source("Features/Trunk/TrunkPartsBoxView.swift")
        XCTAssertTrue(box.contains("exchanging = true\n        guard await model.exchange(part.id) else {\n            exchanging = false"))
    }
}
