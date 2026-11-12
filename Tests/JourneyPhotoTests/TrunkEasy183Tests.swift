import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 1.1.83 の案「トランクと旅の画面のデザイン」（2026-11-12 判断）: 主ボタン1つで最後まで・押せばすぐ決まり、
/// 「取り消す」「ひとつ戻す」で戻す。v2 の値にそろえる
final class TrunkEasy183Tests: XCTestCase {

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

    // MARK: 00 共通の直し

    /// 🔴 ボタンは板の2つの高さだけ（主 50・副 44）。前の 52・角 14 に戻したら落ちる
    func testButtonHeightsAreV2() throws {
        XCTAssertEqual(TrunkButtonFace.height(.main), 50)
        XCTAssertEqual(TrunkButtonFace.height(.mainOnPhoto), 50)
        XCTAssertEqual(TrunkButtonFace.height(.secondary), 44)
        XCTAssertEqual(TrunkButtonFace.height(.danger), 44)
        let parts = try source("Features/Trunk/TrunkParts.swift")
        XCTAssertTrue(parts.contains("jpCapsuleFace("), "ボタンが丸いボタンの面を通っていない")
        XCTAssertFalse(parts.contains("RoundedRectangle(cornerRadius: 14))\n            .contentShape(RoundedRectangle(cornerRadius: 14))"),
                       "角 14 の自前のボタンが残っている")
        // 呼び手が 48・52 の高さを渡していない（手荷物タグのシートの Mac の実測の 48 だけは残す）
        let dir = root.appendingPathComponent("Sources/JourneyPhoto/Features/Trunk")
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) where name.hasSuffix(".swift") && name != "TrunkTagsView.swift" {
            let text = try source("Features/Trunk/" + name)
            XCTAssertFalse(text.contains("kind: .secondary, height:"), "\(name) が副ボタンの高さを渡している")
        }
    }

    /// 🔴 札・線・届いた画面の札は v2 の値（v1 の #121212・#1A1A1A・#201B11 に戻したら落ちる）
    func testTrunkStyleIsV2() throws {
        let parts = try source("Features/Trunk/TrunkParts.swift")
        XCTAssertTrue(parts.contains("static let cell = WebTheme.card"))
        XCTAssertTrue(parts.contains("static let line = WebTheme.hairline"))
        XCTAssertTrue(parts.contains("static let chip = WebTheme.accentSoft"))
        for old in ["0x121212", "0x1A1A1A", "0x201B11"] {
            XCTAssertFalse(parts.contains(old), "v1 の値 \(old) が残っている")
        }
        XCTAssertTrue(parts.contains("strokeBorder(WebTheme.hairline"), "札に白 8% の縁が無い")
    }

    // MARK: 取り消し（知らせに添える）

    @MainActor
    func testToastUndoRunsOnceAndClears() async {
        let toasts = ToastCenter()
        var runs = 0
        toasts.show("付けました", undo: ToastCenter.Undo(title: "取り消す") { runs += 1; return true })
        XCTAssertNotNil(toasts.undo)
        await toasts.performUndo()
        await toasts.performUndo()
        XCTAssertEqual(runs, 1, "取り消しが2回流れた")
        XCTAssertNil(toasts.current, "取り消したのに知らせが残る")
        // 取り消しの無い知らせに替わったら、前の取り消しは消える（別の知らせで前の操作を戻さない）
        toasts.show("付けました", undo: ToastCenter.Undo(title: "取り消す") { runs += 1; return true })
        toasts.show("ほかの知らせ")
        XCTAssertNil(toasts.undo)
        XCTAssertEqual(ToastCenter.undoDuration, 6)
    }

    /// 🔴 取り消しに失敗したら、失敗の知らせで一言（黙って消さない・2026-11-12 確かめ役の指摘）
    @MainActor
    func testToastUndoFailureIsTold() async throws {
        let toasts = ToastCenter()
        toasts.show("付けました", undo: ToastCenter.Undo(title: "取り消す") { false })
        await toasts.performUndo()
        let shown = try XCTUnwrap(toasts.current, "取り消せなかったのに何も言わない")
        XCTAssertEqual(shown.kind, .failure)
        XCTAssertEqual(shown.text, "取り消せませんでした。電波のあるところでもう一度お試しください")
        XCTAssertNil(toasts.undo, "失敗の知らせにまた取り消しが付いている")
        // 部品・型・届いた画面の取り消しは、戻せたかを返す（成否を捨てない）
        for path in ["Features/Trunk/TrunkGachaView.swift", "Features/Trunk/TrunkPartsBoxView.swift"] {
            XCTAssertTrue(try source(path).contains("{ [model] in await model.equip(before) })"), "\(path) の取り消しが成否を返さない")
        }
        XCTAssertTrue(try source("Features/Trunk/TrunkViewModel.swift").contains("{ [weak self] in await self?.setModel(before) ?? false })"))
        XCTAssertTrue(try source("Features/Trunk/LabelArrivedView.swift").contains("await model.unstickAll(stuck) == stuck.count"))
    }

    // MARK: ラベルが届いた（何枚もは「まとめて貼る」1回）

    func testArrivalCopy() {
        XCTAssertEqual(TrunkArrivalCopy.stickTitle(count: 3), "3 枚まとめて貼る")
        XCTAssertEqual(TrunkArrivalCopy.stickTitle(count: 1), "トランクに貼る")
        XCTAssertEqual(TrunkArrivalCopy.title(count: 3, place: "京都"), "ラベルが 3 枚届きました")
        XCTAssertEqual(TrunkArrivalCopy.title(count: 1, place: "京都"), "京都のラベルが届きました")
        XCTAssertEqual(TrunkArrivalCopy.thanks(count: 3, photoTitle: "鴨川の夕暮れ"), "「鴨川の夕暮れ」ほか 2 枚を投稿したお礼です")
        XCTAssertEqual(TrunkArrivalCopy.laterTitle, "あとで貼る（手持ちへ）")
        XCTAssertEqual(TrunkText.arrivalStuckNotice(count: 3), "空いている所へおまかせで貼りました")
        XCTAssertEqual(TrunkText.arrivalStuckNotice(count: 1), "トランクに貼りました")
    }

    /// 🔴 まとめて貼る: 3 枚を1回で貼り（置き場はおまかせ）、取り消しで3枚とも手持ちへ戻る
    @MainActor
    func testStickAllAndUndo() async throws {
        let model = TrunkViewModel(preview: .sample, previewPro: false)
        await model.load(offline: false)
        let pocket = try XCTUnwrap(model.state?.pocket)
        XCTAssertGreaterThanOrEqual(pocket.count, 3)
        let ids = Array(pocket.prefix(3).map(\.id))
        let stuckBefore = model.state?.stuck.count ?? 0
        let done = await model.stickAll(ids)
        XCTAssertEqual(done, ids, "3 枚を1回で貼れていない")
        XCTAssertEqual(model.state?.stuck.count, stuckBefore + 3)
        XCTAssertTrue(ids.allSatisfy { id in model.state?.pocket.contains { $0.id == id } == false })
        let undone = await model.unstickAll(done)
        XCTAssertEqual(undone, 3)
        XCTAssertTrue(ids.allSatisfy { id in model.state?.pocket.contains { $0.id == id } == true }, "取り消しで手持ちへ戻らない")
        XCTAssertEqual(model.state?.stuck.count, stuckBefore)
    }

    /// 届いた画面で貼った枚数と取り消しを、閉じたあとの知らせへ渡す（受け取ったら下ろす）
    @MainActor
    func testArrivalUndoIsHandedToTheNotice() async {
        let arrivals = TrunkArrivals()
        var undone = false
        arrivals.noteStuckFromArrival(count: 3) { undone = true; return true }
        XCTAssertEqual(arrivals.stuckNotice, "空いている所へおまかせで貼りました")
        let undo = arrivals.consumeArrivalUndo()
        XCTAssertNotNil(undo)
        XCTAssertNil(arrivals.consumeArrivalUndo(), "取り消しを2回渡した")
        XCTAssertTrue(arrivals.consumeStuckFromArrival())
        _ = await undo?()
        XCTAssertTrue(undone)
        let view = try? source("Features/Trunk/LabelArrivedView.swift")
        XCTAssertTrue(view?.contains("kind: .mainOnPhoto") ?? false, "写真のある画面の主ボタンが白でない")
        XCTAssertTrue(view?.contains("await model.stickAll(") ?? false, "まとめて貼っていない")
        let root = try? source("App/RootView.swift")
        XCTAssertTrue(root?.contains("trunkArrivals.consumeArrivalUndo()") ?? false, "閉じたあとの知らせに取り消しが無い")
    }

    /// まとめて貼る途中で貼れなかった分は「N 枚は手持ちにあります」と言う（黙って閉じない）
    @MainActor
    func testArrivalPartialStickSaysWhatIsLeft() async throws {
        XCTAssertEqual(TrunkText.arrivalStuckNotice(count: 1, left: 2), "1 枚貼りました。2 枚は手持ちにあります")
        let arrivals = TrunkArrivals()
        arrivals.noteStuckFromArrival(count: 2, left: 1)
        XCTAssertEqual(arrivals.stuckNotice, "2 枚貼りました。1 枚は手持ちにあります")
        XCTAssertTrue(try source("Features/Trunk/LabelArrivedView.swift").contains("left: ids.count - stuck.count"))
    }

    // MARK: カプセルの機械（ボタン1つ＋ハンドル）

    /// 🔴 自分で回す: 12 歩で1周し、目盛りを 12 越える
    func testAutoTurnCompletesOneTurn() {
        var crank = TrunkCrank()
        var ticks = 0
        for _ in 0..<TrunkGachaFlow.autoSteps { ticks += crank.autoAdvance() }
        XCTAssertTrue(crank.isDone)
        XCTAssertEqual(ticks, 12)
        XCTAssertEqual(crank.autoAdvance(), 0, "1周の後も回った")
    }

    /// 🔴 指を離したとき: 1周＝回す・押しただけ＝自分で1周・途中＝元へ戻る（硬貨は減らない＝サーバーに聞かない）
    func testReleaseDecidesDrawAutoOrSpringBack() {
        var tapped = TrunkCrank()
        tapped.begin(dx: 10, dy: 0)
        tapped.drag(dx: 10, dy: 0.5)
        XCTAssertEqual(TrunkGachaFlow.release(tapped), .autoTurn)

        var half = TrunkCrank()
        half.begin(dx: 10, dy: 0)
        half.drag(dx: 0, dy: 10)      // 右へ 90°
        half.drag(dx: -10, dy: 0)     // さらに 90°
        XCTAssertFalse(half.isDone)
        XCTAssertEqual(TrunkGachaFlow.release(half), .springBack, "途中で離したのに戻らない")
        half.letGo()
        XCTAssertFalse(half.isHolding)

        var full = TrunkCrank()
        for _ in 0..<TrunkGachaFlow.autoSteps { full.autoAdvance() }
        XCTAssertEqual(TrunkGachaFlow.release(full), .draw)
    }

    func testGachaCopyAndWiring() throws {
        XCTAssertEqual(TrunkGachaText.spinTitle(coins: 3), "硬貨を入れて回す")
        XCTAssertEqual(TrunkGachaText.spinTitle(coins: 0), "硬貨がありません")
        XCTAssertTrue(TrunkGachaText.unreachable.contains("硬貨は減っていません"))
        let view = try source("Features/Trunk/TrunkGachaView.swift")
        XCTAssertTrue(view.contains("case .springBack: springBack()"), "途中で離しても戻らない")
        XCTAssertTrue(view.contains("TrunkGachaText.spinTitle(coins: coins)"))
        XCTAssertFalse(view.contains("TrunkGachaText.insertTitle(coins: coins)"), "「硬貨を入れる」だけのボタンが残っている")
        XCTAssertTrue(view.contains("tabRouter.openPost(.photo)"), "硬貨 0 の一手（投稿へ）が無い")
        XCTAssertTrue(view.contains("undo: ToastCenter.Undo(title: TrunkText.undoTitle)"), "付けたあとに取り消しが無い")
    }

    /// 🔴 送ったあとに切れた・時間切れは、読み直した硬貨の数で言い分ける（「硬貨は減っていません」と決めつけない）
    func testGachaUnsureMessages() {
        XCTAssertEqual(TrunkGachaText.afterUnsure(coinsBefore: 3, coinsAfter: 3), "回せませんでした。硬貨は減っていません")
        XCTAssertEqual(TrunkGachaText.afterUnsure(coinsBefore: 3, coinsAfter: 2), "回っていました。出た部品は部品箱に入っています")
        XCTAssertEqual(TrunkGachaText.afterUnsure(coinsBefore: 3, coinsAfter: nil),
                       "回ったか確かめられませんでした。電波のあるところで部品箱を開くと分かります")
        XCTAssertFalse(TrunkGachaText.afterUnsure(coinsBefore: 3, coinsAfter: nil).contains("減っていません"))
    }

    /// 自分で回している途中に画面を離れたら、止めて元へ戻し送らない
    func testAutoTurnStopsWhenLeaving() throws {
        XCTAssertTrue(TrunkGachaFlow.keepsAutoTurning(visible: true))
        XCTAssertFalse(TrunkGachaFlow.keepsAutoTurning(visible: false))
        let view = try source("Features/Trunk/TrunkGachaView.swift")
        XCTAssertTrue(view.contains("guard TrunkGachaFlow.keepsAutoTurning(visible: visible) else {\n                crank = TrunkCrank()\n                phase = .idle\n                return"),
                      "画面を離れても回り続ける")
        XCTAssertTrue(view.contains("await model.gacha(offline: connectivity.isOffline)"), "送る前の圏外を渡していない")
    }

    // MARK: 部品箱・付け替え（押すとすぐ保存・ひとつ戻す）

    func testPartsBoxAndEquipWiring() throws {
        let box = try source("Features/Trunk/TrunkPartsBoxView.swift")
        XCTAssertTrue(box.contains("viewing = part"), "持っている部品を押してもシートが出ない")
        XCTAssertTrue(box.contains("TrunkPartSheet(model: model, part: part)"))
        XCTAssertTrue(box.contains("TrunkKindTab("), "種類が選んでいるタブ（真鍮の字と下線）でない")
        XCTAssertFalse(box.contains("付け替えを保存していません"), "保存の確かめが残っている")
        XCTAssertFalse(box.contains("trunk.equip.save"), "右上の保存が残っている")
        XCTAssertTrue(box.contains("trunk.equip.undo"), "「ひとつ戻す」が無い")
        XCTAssertTrue(box.contains("trunk.parts.coins"), "硬貨のチップから機械へ行けない")
    }

    /// 付け替えは押すたびに保存され、前の付け方へ戻せる（見本で）
    @MainActor
    func testEquipSavesImmediatelyAndCanStepBack() async {
        let model = TrunkViewModel(preview: .sample, previewPro: false)
        await model.load(offline: false)
        let before = model.state?.equipped
        let next = TrunkEquipped(lock: "lock.1")
        let saved = await model.equip(next)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.state?.equipped.lock, "lock.1")
        if let before {
            let back = await model.equip(before)
            XCTAssertTrue(back)
        }
        XCTAssertEqual(model.state?.equipped, before)
    }

    // MARK: ふた・型

    func testLidOpensOnArrival() throws {
        XCTAssertTrue(TrunkLidCopy.opensOnAppear(p: 0, dragging: false, holding: false))
        XCTAssertFalse(TrunkLidCopy.opensOnAppear(p: 1, dragging: false, holding: false))
        XCTAssertFalse(TrunkLidCopy.opensOnAppear(p: 0, dragging: true, holding: false))
        XCTAssertEqual(TrunkLidCopy.hint(1), "押すと手に取れます\nふたを上へ払うと閉じます")
        let open = try source("Features/Trunk/TrunkOpenView.swift")
        XCTAssertTrue(open.contains("if TrunkLidCopy.opensOnAppear(p: p, dragging: dragStart != nil, holding: held != nil) { settle(to: 1) }"))
        XCTAssertFalse(open.contains("\"trunk.open.toggle\""), "「ふたを開ける」のボタンが残っている")
        XCTAssertTrue(open.contains("if voiceOver {"), "開き具合の棒が読み上げのとき以外も出ている")
        let models = try source("Features/Trunk/TrunkModelsView.swift")
        XCTAssertEqual(models.components(separatedBy: "model.setModelUndoable(").count - 1, 2, "型を替えたときに取り消しが無い")
    }

    /// 🔴 開いたふたを上へ払うと閉じる（半分まで引かなくても・払った勢いで決める）。ゆっくりなら近い方へ
    func testLidFlickUpCloses() throws {
        // 開き切った所から上へ 100pt 払い、勢いで 400pt 先まで行く見込み → 閉じる
        XCTAssertEqual(TrunkLidCopy.settled(from: 1, predictedDy: -400), 0)
        // 前の決め方（今の位置だけ）では、100pt では開いたまま（この差が直し）
        XCTAssertEqual(TrunkLid.settled(TrunkLid.dragged(from: 1, dy: -100)), 1)
        // ゆっくり 100pt で離した（見込み＝今の位置）→ 開いたまま
        XCTAssertEqual(TrunkLidCopy.settled(from: 1, predictedDy: -100), 1)
        // 閉じた所から下へ払うと開く
        XCTAssertEqual(TrunkLidCopy.settled(from: 0, predictedDy: 400), 1)
        let open = try source("Features/Trunk/TrunkOpenView.swift")
        XCTAssertTrue(open.contains("TrunkLidCopy.settled(from: $0, predictedDy: Double(value.predictedEndTranslation.height)"),
                      "指を離したときに払った勢いを見ていない")
        // 空のトランクの空き枠の破線は板の line（白 14%）。生の白 35% に戻したら落ちる
        XCTAssertEqual(open.components(separatedBy: "strokeBorder(WebTheme.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))").count - 1, 3)
        XCTAssertFalse(open.contains("Color.white.opacity(0.35), style: StrokeStyle"))
    }

    /// 部品箱の圏外は上の帯（前に見た部品箱を出したまま）
    func testPartsBoxOfflineBand() throws {
        XCTAssertEqual(TrunkPartsOfflineCopy.title, "電波が届いていません")
        XCTAssertEqual(TrunkPartsOfflineCopy.detail, "前に見た部品箱を出しています。付け替えは電波が戻ってから")
        let box = try source("Features/Trunk/TrunkPartsBoxView.swift")
        XCTAssertTrue(box.contains("if connectivity.isOffline {\n                        OfflineBanner(title: TrunkPartsOfflineCopy.title"),
                      "圏外の帯が無い")
    }

    /// 型を押してすぐ替え、取り消しで前の型へ戻る（見本で）
    @MainActor
    func testModelSwitchUndo() async throws {
        let model = TrunkViewModel(preview: .sample, previewPro: false)
        await model.load(offline: false)
        let before = try XCTUnwrap(model.state?.effectiveModel)
        let other = try XCTUnwrap(TrunkModel.free.first { $0 != before })
        let toasts = ToastCenter()
        await model.setModelUndoable(other, toasts: toasts)
        XCTAssertEqual(model.state?.effectiveModel, other)
        XCTAssertNotNil(toasts.undo)
        await toasts.performUndo()
        XCTAssertEqual(model.state?.effectiveModel, before, "取り消しで前の型に戻らない")
    }
}

/// 1.1.83 の案の旅の画面（行った県・近くの写真・撮影地・今日の一問・とおまわり号）
final class TravelScreens183Tests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    private func photo(_ id: String, location: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\",\"location\":\"\(location)\"}".utf8))
    }

    /// 🔴 候補のチップを押すとその場で記録（札を開かない）。取り消しで戻る
    @MainActor
    func testCandidateChipRecordsAtOnce() async throws {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let m = VisitedMapModel(store: VisitedPrefectureStore(defaults: d))
        m.open(userId: "u")
        m.applyPhotos([try photo("a", location: "長野県"), try photo("b", location: "長野県")], spots: [])
        XCTAssertEqual(m.candidates, ["長野県"])
        m.recordCandidate("長野県")
        XCTAssertEqual(m.record.count("長野県"), 1)
        XCTAssertNil(m.selected, "札を開いた")
        XCTAssertEqual(m.toast?.offersUndo, true, "取り消しが無い")
        m.undo()
        XCTAssertEqual(m.record.count("長野県"), 0)
        // 候補でない県は押しても記録しない
        m.recordCandidate("沖縄県")
        XCTAssertEqual(m.record.count("沖縄県"), 0)
        // 県の札の写真（その県で撮った自分の写真）
        XCTAssertEqual(m.photosByPrefecture["長野県"]?.map(\.id), ["a", "b"])
        let screen = try source("Features/Profile/VisitedMapScreen.swift")
        XCTAssertTrue(screen.contains("Button { model.recordCandidate(name) }"))
        XCTAssertTrue(screen.contains("\"visitedMap.more\""), "「…」に畳んでいない")
        XCTAssertFalse(screen.contains("textButton(VisitedMapText.allVisited47"), "足元の行が残っている")
        XCTAssertTrue(try source("Features/Profile/VisitedPrefectureCard.swift").contains("photosBlock"))
    }

    func testNearbyHelpers() throws {
        XCTAssertEqual(NearbyPhotos.widerRadius(than: 5), 10)
        XCTAssertNil(NearbyPhotos.widerRadius(than: NearbyPhotos.radiusChoices.last ?? 0))
        XCTAssertEqual(NearbyPhotos.chipLabel(km: 0.4), "1km内")
        XCTAssertEqual(NearbyPhotos.chipLabel(km: 2.4), "約2km")
        let sheet = try source("Features/Map/NearbyPhotosSheet.swift")
        XCTAssertFalse(sheet.contains("List {"), "系統の List が残っている")
        XCTAssertFalse(sheet.contains(".pickerStyle(.segmented)"), "灰のセグメントが残っている")
        XCTAssertTrue(sheet.contains("LazyVGrid(columns: columns, spacing: 2)"), "写真の格子でない")
        XCTAssertTrue(sheet.contains("PillChip("), "範囲が丸チップでない")
        // 画面写真（地図の「近くの写真」から開く）
        XCTAssertTrue(try source("Features/Map/PhotoMapView.swift").contains(".accessibilityIdentifier(\"map.nearby\")"))
        let shots = try String(contentsOf: root.appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"), encoding: .utf8)
        XCTAssertTrue(shots.contains("func testCapturesNearbyPhotos()"))
    }

    func testSpotDetailGridIsRightUnderActions() throws {
        let detail = try source("Features/Spots/SpotDetailView.swift")
        let a = try XCTUnwrap(detail.range(of: "                actions\n"))
        let g = try XCTUnwrap(detail.range(of: "                spotPhotos\n"))
        let n = try XCTUnwrap(detail.range(of: "                nearbySpotRow\n"))
        XCTAssertLessThan(a.lowerBound, g.lowerBound)
        XCTAssertLessThan(g.lowerBound, n.lowerBound, "写真の格子が行動の札の直下にない")
        XCTAssertEqual(SpotPhotoGrid.previewCount, 9)
        XCTAssertFalse(detail.contains(".frame(width: 118)"), "横の帯が残っている")
    }

    func testQuizChoiceLookAndButtons() throws {
        XCTAssertEqual(DailyQuizChoiceLook(answered: false, isAnswer: true, isChosen: false), .plain)
        XCTAssertEqual(DailyQuizChoiceLook(answered: true, isAnswer: true, isChosen: false), .answer)
        XCTAssertEqual(DailyQuizChoiceLook(answered: true, isAnswer: true, isChosen: true), .answer)
        XCTAssertEqual(DailyQuizChoiceLook(answered: true, isAnswer: false, isChosen: true), .wrongChoice)
        XCTAssertEqual(DailyQuizChoiceLook(answered: true, isAnswer: false, isChosen: false), .faded)
        let quiz = try source("Features/Gallery/DailyQuizView.swift")
        XCTAssertTrue(quiz.contains(".jpPillButton(.main(onPhoto: true))"), "写真のある画面の主ボタンが白でない")
        XCTAssertFalse(quiz.contains(".background(WebTheme.accentFill, in: Capsule())"), "主ボタンが真鍮の塗りのまま")
        XCTAssertTrue(quiz.contains("minHeight: JPHeight.row"), "選択肢が 52 でない")
        XCTAssertTrue(quiz.contains("DailyQuizSkeleton()"), "読み込み中が骨格でない")
    }

    func testCamperVisitCardsAndSkeleton() throws {
        let visit = try source("Features/Camper/CamperVisitView.swift")
        XCTAssertTrue(visit.contains("CamperVisitSkeleton()"), "読み込み中が回る輪のまま")
        XCTAssertFalse(visit.contains("友達の車を読み込んでいます…"))
        XCTAssertEqual(visit.components(separatedBy: "CamperVisitActionCard(icon:").count - 1, 2, "贈る・薪が2枚の札でない")
    }
}

/// カプセルの機械の失敗の言い分け（本物の口を台本で返す・2026-11-12 確かめ役の指摘）
final class TrunkGachaFailure183Tests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        session = URLSession(configuration: config)
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    @MainActor
    private func loadedModel(coins: Int) async -> TrunkViewModel {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil)
        model.bind(TrunkService(api: api))
        ScriptedProtocol.script = [.init(match: "/user/trunk", status: 200,
                                         body: #"{"pocket":[],"stuck":[],"coins":\#(coins)}"#, once: true)]
        await model.load(offline: false)
        return model
    }

    /// 送る前から圏外: 送らない。このときだけ「硬貨は減っていません」
    @MainActor
    func testOfflineDoesNotSend() async {
        let model = await loadedModel(coins: 3)
        ScriptedProtocol.calls = []
        let got = await model.gacha(offline: true)
        XCTAssertNil(got)
        XCTAssertFalse(ScriptedProtocol.calls.contains { $0.path.contains("/gacha") }, "圏外なのに送った")
        XCTAssertEqual(model.actionError, TrunkGachaText.unreachable)
    }

    /// 送ったあとに失敗（サーバーが 502）: 読み直した硬貨が同じなら「減っていません」、減っていたら「部品箱に」
    @MainActor
    func testUnsureFailureComparesCoins() async {
        let model = await loadedModel(coins: 3)
        ScriptedProtocol.script = [.init(match: "/user/trunk/gacha", status: 502, body: ""),
                                   .init(match: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[],"coins":3}"#)]
        _ = await model.gacha()
        XCTAssertEqual(model.actionError, "回せませんでした。硬貨は減っていません")

        ScriptedProtocol.script = [.init(match: "/user/trunk/gacha", status: 502, body: ""),
                                   .init(match: "/user/trunk", status: 200, body: #"{"pocket":[],"stuck":[],"coins":2}"#)]
        _ = await model.gacha()
        XCTAssertEqual(model.actionError, "回っていました。出た部品は部品箱に入っています")
        XCTAssertEqual(model.state?.coins, 2)

        // 読み直しも失敗: 分からないと言う（「減っていません」と言わない）
        ScriptedProtocol.script = [.init(match: "/user/trunk/gacha", status: 502, body: ""),
                                   .init(match: "/user/trunk", status: 502, body: "")]
        _ = await model.gacha()
        XCTAssertEqual(model.actionError, TrunkGachaText.afterUnsure(coinsBefore: 2, coinsAfter: nil))
    }
}

/// 2026-11-12 の決まり: 新しく足した画面の文を「·」「・」で区切らない（改行・字の色や太さ・余白・「、」で分ける）
final class NoDotSeparator183Tests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testNewTextsHaveNoDotSeparators() throws {
        // 1.1.83 の章で足した言葉の置き場（TrunkEasy.swift は丸ごと新しい）
        let easy = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Core/Text/TrunkEasy.swift"), encoding: .utf8)
        for line in easy.components(separatedBy: "\n") where line.contains("L(") {
            XCTAssertFalse(line.contains(" · ") || line.contains("・"), "区切りの記号がある: \(line)")
        }
        // 実際の文
        for text in [TrunkLidCopy.hint(0), TrunkLidCopy.hint(1), TrunkPartsOfflineCopy.detail,
                     TrunkText.arrivalStuckNotice(count: 2, left: 1), VisitedMapText.recordCandidateAction,
                     TrunkGachaText.afterUnsure(coinsBefore: 1, coinsAfter: nil)] {
            XCTAssertFalse(text.contains(" · "), "「·」で区切っている: \(text)")
        }
        // 前に「·」で区切っていた所（確かめ役が挙げた 6 か所）
        let checks: [(String, String)] = [
            ("Features/Profile/VisitedPrefectureCard.swift", "で撮った写真 · "),
            ("Features/Camper/CamperVisitView.swift", "1日1回 · "),
            ("Features/Trunk/TrunkPartsBoxView.swift", "\"· \" + L(\"カプセルを回す\""),
            ("Features/Trunk/TrunkPartsBoxView.swift", "枚 · カプセルを回す"),
            ("Core/Text/VisitedMapText.swift", "· 記録する"),
        ]
        for (path, old) in checks {
            let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
            XCTAssertFalse(text.contains(old), "\(path) に「·」の区切りが残っている")
        }
    }
}
