import XCTest
@testable import JourneyPhoto

/// 旅のトランクの画面のつなぎ（画面は Linux で動かせないので、書き方を見張る・2026-10-17）
final class TrunkWiringTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func trunkFiles() throws -> [(String, String)] {
        let dir = root.appendingPathComponent("Sources/JourneyPhoto/Features/Trunk")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }.sorted()
        XCTAssertGreaterThanOrEqual(names.count, 8)
        return try names.map { ($0, try source("Features/Trunk/" + $0)) }
    }

    /// 持っていない部品の影は白 10% 前後の一色の影絵（2026-10-17 owner。板の黒 35% は #121212 の札で見えない）。
    /// 持っていない部品を描く所はどこも同じ見た目（画面ごとに割らない）
    func testMissingPartShadowIsFaintWhite() throws {
        XCTAssertGreaterThanOrEqual(TrunkPartsBoxText.missingShadowOpacity, 0.08)
        XCTAssertLessThanOrEqual(TrunkPartsBoxText.missingShadowOpacity, 0.12)
        let box = try source("Features/Trunk/TrunkPartsBoxView.swift")
        XCTAssertTrue(box.contains("Color.white.opacity(TrunkPartsBoxText.missingShadowOpacity)"), "影が白の影絵でない")
        XCTAssertTrue(box.contains(".mask { TrunkPartView(part: part, shadow: false) }"), "形の影絵でなく色・質感が出る")
        var masks = 0
        for (name, text) in try trunkFiles() {
            // 部品の形を型に抜く所（＝持っていない部品の影）は、どこも同じ影の色で塗る。
            // 抜く修飾子の連なりをさかのぼり、その頭（塗る色）が白の影の値であることを1か所ずつ見る
            let lines = text.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains(".mask { TrunkPartView(") {
                masks += 1
                var head = i
                while head > 0, lines[head].trimmingCharacters(in: .whitespaces).hasPrefix(".") { head -= 1 }
                XCTAssertEqual(lines[head].trimmingCharacters(in: .whitespaces),
                               "Color.white.opacity(TrunkPartsBoxText.missingShadowOpacity)",
                               "\(name):\(i + 1) の影が部品箱と違う色")
            }
        }
        XCTAssertGreaterThanOrEqual(masks, 1, "影の描き方が見つからない（見張りが空振りしている）")
    }

    /// 自分の手で貼る画面: 運んで離した送信も committer の予定に入れる（「保存せずに閉じる」で取り消せる）。
    /// 閉じたら「ひとつ戻す」への積み（`onSaved`）を外して画面を抱え込まない
    func testStickSendsThroughTheCommitter() throws {
        let stick = try source("Features/Trunk/TrunkStickView.swift")
        XCTAssertFalse(stick.contains("places.commit("), "予定の外で送っている（保存せずに閉じても取り消せない）")
        XCTAssertTrue(stick.contains("places.schedule(id, delay: 0) { outcome, closed in"))
        XCTAssertTrue(stick.contains("places.onSaved = nil"), "閉じても onSaved が画面を抱え込む")
    }

    /// 入口はマイページの旅の記録の札（名前の付いた行・画面写真の試験が押す）
    func testEntryFromMyPage() throws {
        let page = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(page.contains("NavigationLink { TrunkView(ownerName: model.profile?.name) }"))
        XCTAssertTrue(page.contains(#".accessibilityIdentifier("trips.trunk")"#))
    }

    /// 投稿が全部上がった所でラベルを渡し、`RootView` がほかの画面が閉じてから出す
    func testArrivalIsPresentedAfterPosting() throws {
        let upload = try source("Features/Upload/UploadViewModel.swift")
        XCTAssertTrue(upload.contains("TrunkArrivals.shared.deliver("), "投稿の成功で届いたラベルを渡していない")
        XCTAssertTrue(upload.contains("outcome.label = saved.label"))
        let rootView = try source("App/RootView.swift")
        XCTAssertTrue(rootView.contains("}) { batch in LabelArrivedView(batch: batch) }"))
        XCTAssertTrue(rootView.contains("tabsWithTrunkArrival"), "届いた画面の修飾子が繋がっていない")
        XCTAssertTrue(rootView.contains("toasts.show(notice.text, kind: .info)"), "いっぱいのときの一言が無い")
        XCTAssertTrue(rootView.contains("until: PostModalGate.trunkMayShow"), "届いた画面が順番の決まりを通っていない")
        XCTAssertTrue(rootView.contains("guard PostModalGate.reviewMayAsk(postModalSnapshot())"), "評価のお願いが順番の決まりを通っていない")
    }

    /// 窓口は `TrunkService` 1つで、`AppEnvironment` が組む
    func testServiceIsWired() throws {
        let env = try source("App/AppEnvironment.swift")
        XCTAssertTrue(env.contains("self.trunk = TrunkService(api: api)"))
        for path in ["Features/Trunk/TrunkView.swift", "Features/Trunk/LabelArrivedView.swift"] {
            // 見ている人も渡す（硬貨の知らせを自分の人のものだけ受ける・2026-10-18）
            XCTAssertTrue(try source(path).contains("model.bind(environment.trunk, userId: auth.userId)"), path)
        }
    }

    /// 画面に「捨てる」を出さない（削除）・英語も用意する・系統の赤を行に出さない（危険は `WebTheme.danger`）
    func testWordingAndColors() throws {
        for (name, text) in try trunkFiles() {
            XCTAssertFalse(text.contains("捨て"), "\(name) に「捨てる」がある")
            XCTAssertFalse(text.contains("Color.red"), "\(name) に系統の赤")
            // 日本語の字を `L(` の外で `Text("…")` に直に書いていない（紙のラベルの刷りの字は `spec` から来る）
            for line in text.components(separatedBy: "\n") where line.contains("Text(\"") {
                let inside = line.components(separatedBy: "Text(\"").dropFirst().map { $0.prefix { $0 != "\"" } }
                for literal in inside where literal.unicodeScalars.contains(where: { $0.value >= 0x3000 }) {
                    XCTFail("\(name) に英語の無い字: \(literal)")
                }
            }
        }
        let pocket = try source("Features/Trunk/TrunkPocketView.swift")
        XCTAssertTrue(pocket.contains("kind: .danger"), "削除が危険の字になっていない")
        XCTAssertTrue(pocket.contains(".confirmationDialog("), "削除を確かめていない")
    }

    /// 真鍮は黒い地の上だけ（写真の上に置く画面は無い）・押せるものは 44pt
    func testTapTargets() throws {
        let parts = try source("Features/Trunk/TrunkParts.swift")
        XCTAssertTrue(parts.contains(".frame(minHeight: 52)"), "札の行が 52 でない")
        for path in ["Features/Trunk/TrunkRerollView.swift", "Features/Trunk/LabelArrivedView.swift",
                     "Features/Trunk/TrunkSpinViewer.swift"] {
            XCTAssertTrue(try source(path).contains("WebTheme.minTapTarget"), "\(path) の閉じるが 44pt でない")
        }
    }

    /// 手に取って回す: メダルと同じ仕組みに箱の形を足し、表に胴の絵を貼る
    func testSpinUsesTheMedalViewer() throws {
        let medal = try source("Features/Profile/MedalViewerView.swift")
        XCTAssertTrue(medal.contains("case box(aspect: Double, depth: Double, corner: Double, handle: SpinRGB)"))
        XCTAssertTrue(medal.contains("addHandle(aspect: aspect, depth: depth, color: handle)"))
        let spin = try source("Features/Trunk/TrunkSpinViewer.swift")
        XCTAssertTrue(spin.contains("MedalCoinView(textures: textures"))
        XCTAssertTrue(spin.contains("TrunkBoxView(model: model, posts: posts, stuck: stuck, ownerName: ownerName, bodyOnly: true,\n                                        parts: parts, wrinkles: wrinkles))"),
                      "回す画面の表に付けた部品とよれが出ない（2026-10-17 次の版）")
        XCTAssertTrue(spin.contains(".accessibilityAction(named: L(\"裏返す\", \"Turn over\"))"))
    }

    /// 4つの状態（読み込み中・空・失敗・圏外）を出し分ける
    func testFourStates() throws {
        let main = try source("Features/Trunk/TrunkView.swift")
        for id in ["trunk.loading", "trunk.failed", "trunk.offline", "trunk.empty"] {
            XCTAssertTrue(main.contains("\"\(id)\""), "\(id) が無い")
        }
        XCTAssertTrue(try source("Features/Trunk/TrunkPocketView.swift").contains("trunk.pocket.empty"))
    }

    /// 画面写真の見本の鍵は Debug だけ（Release では必ず効かない）
    func testPreviewKeysAreDebugOnly() throws {
        let preview = try source("Core/Auth/PreviewSession.swift")
        XCTAssertTrue(preview.contains("static let trunkSampleKey = \"JPPreviewTrunk\""))
        XCTAssertTrue(preview.contains("static let trunkArrivedKey = \"JPPreviewTrunkArrived\""))
        XCTAssertNil(PreviewSession.trunkSample, "テストでは見本が効いていない")
        // 次の版（2026-10-17）: 硬貨の枚数の見本（カプセルの機械の「硬貨がありません」を撮る）
        XCTAssertTrue(preview.contains("static let trunkCoinsKey = \"JPPreviewTrunkCoins\""))
        XCTAssertNil(PreviewSession.trunkCoins)
        // ふたを開けた画面写真の会員証（2026-10-18）: 見本のサポーターの番号も Debug だけ・入っている本人だけ
        XCTAssertTrue(preview.contains("static let supporterKey = \"JPPreviewSupporter\""))
        XCTAssertNil(PreviewSession.supporter)
        let shots = try String(contentsOf: root.appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"), encoding: .utf8)
        XCTAssertTrue(shots.contains("\"-JPPreviewPro\", \"YES\", \"-JPPreviewSupporter\", \"7\""),
                      "ふたを開けた画面写真に会員証が出ない（見本の利用者の公開プロフィールに番号が無い）")
    }

    /// 知らせ: 押して進む画面には重ねず（`RootView` の全体の知らせ）、全画面の届いた画面にだけ置く。
    /// 画面の組みは Linux で描けないので書き方で見る（振る舞いは Mac の画面写真）
    func testToastPlacement() throws {
        for path in ["Features/Trunk/TrunkView.swift", "Features/Trunk/TrunkPocketView.swift"] {
            XCTAssertFalse(try source(path).contains("ToastOverlay()"), "\(path) で知らせが二重に出る")
        }
        XCTAssertTrue(try source("Features/Trunk/LabelArrivedView.swift").contains(".overlay(alignment: .top) { ToastOverlay() }"),
                      "届いた画面の上で知らせが隠れる")
    }

    /// 評価のお願いの判断の最中は届いた画面を待たせる配線（`reviewDeciding`）と、残った束の出し直し
    func testReviewDecidingIsWired() throws {
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("reviewDeciding = true\n            defer { reviewDeciding = false }"),
                      "評価のお願いの判断の最中を印にしていない")
        XCTAssertTrue(root.contains("pushPrimerShowing: showPushPrimer, reviewDeciding: reviewDeciding,"),
                      "判断の最中を順番の決まりに渡していない")
        XCTAssertTrue(root.contains("trunkPending: trunkArrivals.blocksReview()"), "残った束が評価をずっと止める")
        XCTAssertTrue(root.contains(".onChange(of: showPushPrimer) { _, showing in\n                if !showing, trunkArrivals.hasPending { offerTrunkArrivalWhenIdle() }"),
                      "通知の説明が閉じても残った束を出し直さない")
        XCTAssertTrue(root.contains(".onChange(of: reviewDeciding) { _, deciding in\n                if !deciding, trunkArrivals.hasPending { offerTrunkArrivalWhenIdle() }"),
                      "評価の判断が終わっても残った束を出し直さない")
        XCTAssertTrue(root.contains("if trunkArrivals.consumeStuckFromArrival() { toasts.show("),
                      "届いた画面で貼った知らせを閉じ切ってから出していない")
        let arrived = try source("Features/Trunk/LabelArrivedView.swift")
        XCTAssertFalse(arrived.contains("toasts.show(L(\"トランクに貼りました\""), "届いた画面の上でも知らせを出している（2つ見える）")
    }

    /// マイページの入口は口が読めたときだけ出す配線
    func testMyPageEntryIsGated() throws {
        let page = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(page.contains("if trunkAvailability.isAvailable {\n                NavigationLink { TrunkView("),
                      "口が無いのに入口を出している")
        XCTAssertTrue(page.contains("await trunkAvailability.refresh(userId: auth.userId, service: environment.trunk)"))
        XCTAssertTrue(page.contains("service: environment.trunk, force: true)"), "前面に戻ったときに確かめ直していない")
        let edit = try source("Features/Profile/EditPhotoView.swift")
        XCTAssertTrue(edit.contains("if patch.published == true {\n                TrunkArrivals.shared.deliver(dealt,"),
                      "下書きを公開しても届いた画面を出さない")
    }

    /// 🔴 入れ物（VStack・ZStack・EmptyState・ScrollView）に付けた目印は、**本物の SwiftUI では中の子に
    /// 降りて、子のボタンの目印を上書きする**（run 464: `trunk.empty` が「写真を投稿」の `trunk.emptyPost` を
    /// 消し、作り直し・届いた画面のボタンも見つからなかった）。模型（Shims）は目印を素通しで、この上書きを
    /// 再現しない。入れ物の目印の直前には必ず `.accessibilityElement(children: .contain)` を置く
    func testContainerIdentifiersDoNotOverrideChildren() throws {
        let containers = ["trunk.arrived", "trunk.models.screen", "trunk.proModels.screen", "trunk.pocket.empty",
                          "trunk.reroll", "trunk.loading", "trunk.failed", "trunk.offline", "trunk.empty", "trunk.screen",
                          // 次の版（2026-10-17）
                          "trunk.stick", "trunk.gacha", "trunk.gachaOpen", "trunk.odds", "trunk.parts", "trunk.equip",
                          // ふたを開ける（2026-10-18）
                          "trunk.open.screen", "trunk.open.stage", "trunk.open.empty", "trunk.hold"]
        var found = Set<String>()
        for (name, text) in try trunkFiles() {
            let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            for (k, line) in lines.enumerated() {
                for id in containers where line == ".accessibilityIdentifier(\"\(id)\")" {
                    found.insert(id)
                    XCTAssertEqual(k > 0 ? lines[k - 1] : "", ".accessibilityElement(children: .contain)",
                                   "\(name) の \(id) が子のボタンの目印を上書きする")
                }
            }
        }
        XCTAssertEqual(found, Set(containers), "見張る目印が見つからない（名前が変わった？）")
    }

    /// 次の版（2026-10-17）: トランクの画面に「ラベルを貼る」「部品箱」「カプセルの機械（硬貨の数）」の入口があり、
    /// 部品はトランクの絵と回す画面に映る。画面写真の試験が各画面を1枚ずつ撮る
    func testNextVersionEntriesAndScreenshots() throws {
        let main = try source("Features/Trunk/TrunkView.swift")
        for id in ["trunk.stick.open", "trunk.partsBox", "trunk.gacha.open"] {
            XCTAssertTrue(main.contains("\"\(id)\""), "\(id) の入口が無い")
        }
        XCTAssertTrue(main.contains("Text(L(\"硬貨 \\(state.coins)\""), "入口に硬貨の数が無い")
        XCTAssertTrue(main.contains("parts: state.equipped"), "トランクの絵に付けた部品を渡していない")
        let shots = try String(contentsOf: root.appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"), encoding: .utf8)
        for name in ["97-ラベルを貼る", "98-カプセルの機械", "98a-カプセルを開けた", "98b-中身と確率", "99-部品箱", "99a-部品を付け替える",
                     "98c-カプセルの機械（硬貨がありません）"] {
            XCTAssertTrue(shots.contains("\"\(name)\""), "画面写真 \(name) が無い")
        }
        // 触覚（貼る・目盛り・落ちる）と「視差効果を減らす」
        let stick = try source("Features/Trunk/TrunkStickView.swift")
        XCTAssertTrue(stick.contains(".sensoryFeedback(.impact(weight: .medium), trigger: stickTicks)"))
        XCTAssertTrue(stick.contains("guard !reduceMotion else { return }"), "貼る弾みを「視差効果を減らす」で止めていない")
        let gacha = try source("Features/Trunk/TrunkGachaView.swift")
        XCTAssertTrue(gacha.contains(".sensoryFeedback(.selection, trigger: ticks)"), "ハンドルの目盛りに触覚が無い")
        XCTAssertTrue(gacha.contains(".sensoryFeedback(.impact(weight: .heavy), trigger: drops)"), "カプセルが落ちたときに触覚が無い")
        XCTAssertTrue(gacha.contains("TrunkGachaOddsView()"), "中身と確率への入口が無い")
        XCTAssertTrue(gacha.contains("if reduceMotion {"), "落ちる弾みを「視差効果を減らす」で止めていない")
        XCTAssertFalse(gacha.contains("Text(L(\"枚\", \"\"))"), "英語で空の字と余白が残る")
        XCTAssertTrue(gacha.contains("if !unit.isEmpty {"))
    }

    /// 回して間もなく閉じても保存する。送れなければ閉じずに「もう一度」「保存せずに閉じる」を聞く
    /// （送る順序・数え方は `TrunkPlaceCommitterTests` が振る舞いで見る）
    func testStickScreenFlushesOnClose() throws {
        let stick = try source("Features/Trunk/TrunkStickView.swift")
        XCTAssertTrue(stick.contains("let ok = await places.flush()"), "「完了」が溜まった置き場を送らずに閉じる")
        XCTAssertTrue(stick.contains("if ok { dismiss() } else { showSaveFailed = true }"), "送れなかったのに閉じる・出る道が無い")
        XCTAssertTrue(stick.contains("Button(L(\"保存せずに閉じる\", \"Close without saving\"))"))
        XCTAssertTrue(stick.contains("places.discardAll()\n                dismiss()"), "保存せずに閉じても送る")
        XCTAssertTrue(stick.contains("Text(L(\"保存しています\", \"Saving\"))"), "送っている間に何も出さない")
        XCTAssertTrue(stick.contains(".onDisappear {\n            places.sendLeftovers()"), "閉じたときに残りを捨てる")
        XCTAssertFalse(stick.contains("捨て"))
        // 2本指: 取り消されても下がる印・回し始めたラベルを送ってから印を下げる
        XCTAssertTrue(stick.contains("@GestureState private var rotating = false"))
        XCTAssertTrue(stick.contains(".updating($rotating) { _, state, _ in state = true }"))
        XCTAssertTrue(stick.contains(".onChange(of: rotating) { _, now in"), "取り消されたときに回した1枚を送らない")
        XCTAssertTrue(stick.contains("if let id = rotatingId { places.schedule(id, delay: 0) }"))
        XCTAssertTrue(stick.contains("guard !rotatedDuringDrag else {"), "2本指のあとの離しで選び直す")
        XCTAssertTrue(stick.contains("guard outcome == .saved else { return }"), "断られたのに、運んだよれ・音が付く")
        XCTAssertTrue(stick.contains("guard !closed else { return }"), "閉じた先の画面で音・触覚が出る")
        let committer = try source("Features/Trunk/TrunkPlaceCommitter.swift")
        XCTAssertTrue(committer.contains("guard !Task.isCancelled else { return }\n            switch outcome {\n            case .busy? where attempt < 5:"),
                      "取り消したあとに予定を作り直す")
    }

    /// よれ（貼り直した紙）は貼る画面だけでなく、トランクを描くどの画面にも同じく出す（画面ごとに見た目を割らない）
    func testWrinklesReachEveryTrunk() throws {
        for path in ["Features/Trunk/TrunkView.swift", "Features/Trunk/TrunkPartsBoxView.swift"] {
            XCTAssertTrue(try source(path).contains("wrinkles: TrunkWrinkles(userId: auth.userId).strengths"), "\(path) によれが無い")
        }
        XCTAssertTrue(try source("Features/Trunk/TrunkStickView.swift").contains("wrinkles: wrinkles, pop: pop"))
        XCTAssertTrue(try source("Features/Trunk/TrunkBoxView.swift").contains("parts: parts, wrinkles: wrinkles,\n                     tagsFrom: tagsFrom)"),
                      "TrunkFigure がよれを箱に渡していない")
    }

    /// ふたを開ける（2026-10-18・板 TrunkOpen・InsideHold・InsideEmpty）: 入口・前開き・本物の中身・出口・触覚
    func testOpenLidIsWired() throws {
        let main = try source("Features/Trunk/TrunkView.swift")
        XCTAssertTrue(main.contains("TrunkOpenView(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,"),
                      "トランクの画面からふたを開けられない")
        XCTAssertTrue(main.contains(#".accessibilityIdentifier("trunk.open")"#))
        let open = try source("Features/Trunk/TrunkOpenView.swift")
        // 前開き: 下の辺が軸で手前へ倒れる
        XCTAssertTrue(open.contains(".rotation3DEffect(.degrees(-pose.angle), axis: (x: 1, y: 0, z: 0), anchor: .bottom,"))
        // 途中の値から描く（Animatable）・平らなふたへは動きの終わりに
        XCTAssertTrue(open.contains("struct TrunkLidStage: ViewModifier, Animatable {"))
        XCTAssertTrue(open.contains("var animatableData: Double {\n        get { p }\n        set { p = newValue }"))
        XCTAssertTrue(open.contains("let pose = TrunkLid.pose(p)"))
        XCTAssertTrue(open.contains("} completion: {"), "平らなふたへの差し替えが動きの終わりでない")
        XCTAssertTrue(open.contains("duration: TrunkLid.settleDuration"))
        // 閉じている・途中のふたは読ませない。読み上げで1段ずつ開け閉め
        XCTAssertTrue(open.contains(".accessibilityHidden(!flat)"))
        XCTAssertTrue(open.contains(".accessibilityAdjustableAction { direction in"))
        XCTAssertTrue(open.contains("move(to: TrunkLid.stepped(p, up: up))"))
        // 引く指と送り: 収まるときは引く指が先、送りがあるときは両方
        XCTAssertTrue(open.contains(".modifier(LidDragPriority(overflows: overflows, gesture: drag(scale: k)))"))
        // 枝分けで View を替えず、効かせない方を GestureMask で止める（舞台を作り直さない）
        XCTAssertTrue(open.contains(".highPriorityGesture(gesture, including: Self.highPriorityMask(overflows: overflows))\n            .simultaneousGesture(gesture, including: Self.simultaneousMask(overflows: overflows))"))
        XCTAssertTrue(open.contains("static func highPriorityMask(overflows: Bool) -> GestureMask { overflows ? .subviews : .all }"))
        XCTAssertTrue(open.contains("static func simultaneousMask(overflows: Bool) -> GestureMask { overflows ? .all : .subviews }"))
        let priority = open.components(separatedBy: "private struct LidDragPriority")[1]
        XCTAssertFalse(priority.contains("if overflows {"), "枝分けで舞台がまるごと作り直される")
        // 100% まで引いて離した・合図が来なかったときの逃げ道
        XCTAssertTrue(open.contains("guard TrunkLid.needsMotion(from: p, to: target) else {\n            lidSettled = TrunkLid.isOpen(target)\n            return"))
        XCTAssertTrue(open.contains("if TrunkLid.isOpen(p), dragStart == nil { lidSettled = true }"))
        // 動きの途中のコマで正面の絵・胴の中を作り直さない（1度だけ絵にして使い回す）
        XCTAssertTrue(open.contains(".task(id: snapshotKey) {\n            if let images = await TrunkLidImages.make(stage(contents)) { lidImages = images }"))
        // 描く前に1コマ待ち、取り消されたら描かない
        XCTAssertTrue(open.contains("do { try await Task.sleep(for: .milliseconds(16)) } catch { return nil }\n        guard !Task.isCancelled else { return nil }"))
        // 合図: 正面の絵に効くものは入れ、生で描く乗車券の写真は入れない
        let key = open.components(separatedBy: "private struct LidSnapshotKey: Equatable {")[1].components(separatedBy: "}")[0]
        for field in ["let model: TrunkModel", "let posts: Int", "let stuck: [TrunkLabel]", "let parts: TrunkEquipped",
                      "let wrinkles: [String: Double]", "let ownerName: String?", "let contents: TrunkInsideContents"] {
            XCTAssertTrue(key.contains(field), "ふたの絵の描き直しの合図に \(field) が無い（親が新しくなっても古い絵が残る）")
        }
        XCTAssertFalse(key.contains("photos"), "写真が届くたびに5枚描き直す")
        // 影の無い層は余白なし（絵を小さく持つ）
        XCTAssertTrue(open.contains("w: TrunkLooks.canvasWidth, h: 40, pad: 0),"))
        XCTAssertTrue(open.contains("w: TrunkInsideView.width, h: TrunkInsideView.height, pad: 0))"))
        for use in ["images?.front", "images?.lidInside", "images?.handle", "images?.baseBelow", "images?.baseAbove"] {
            XCTAssertTrue(open.contains(use), "\(use) を使い回していない")
        }
        XCTAssertTrue(open.contains("settle(to: TrunkLid.settled(p))"), "指を離しても近い方へ寄らない")
        XCTAssertTrue(open.contains(".accessibilityValue(TrunkLid.accessibilityValue(p))"), "開き具合を読み上げない")
        // 本物の中身（新しい通信は増やさない: 自分のプロフィールと端末の中のすれちがい帳）
        XCTAssertTrue(open.contains("environment.profiles.myProfile()"))
        XCTAssertTrue(open.contains("isPro: profile?.isPro ?? false"), "会員証の出し分けが Pro を見ていない")
        XCTAssertTrue(open.contains("supporter: profile?.supporterInfo"), "サポーター証の中身を見ていない")
        XCTAssertTrue(open.contains("pass.book(hiding: hidden.snapshot)"), "乗車券がすれちがい帳から来ていない")
        // 出口は今ある画面
        XCTAssertTrue(open.contains("MedalViewerView(badge: badge,"))
        XCTAssertTrue(open.contains("BadgeShelfView(mode: .mine, preloaded: profile)"))
        XCTAssertTrue(open.contains("SupporterCardView(profile: profile)"))
        XCTAssertTrue(open.contains("PassBookView()"))
        XCTAssertTrue(open.contains("tabRouter.openPost(.photo)"), "空のトランクから投稿へ行けない")
        // 触覚と「視差効果を減らす」
        XCTAssertTrue(open.contains(".sensoryFeedback(.impact(weight: .medium), trigger: landings)"))
        XCTAssertTrue(open.contains(".sensoryFeedback(.selection, trigger: picks)"))
        XCTAssertTrue(open.contains("if reduceMotion {"))
        XCTAssertTrue(open.contains("TrunkSound" + ".tick()"), "持ち上げたときに音が無い")
        // 押せるもの 44pt 以上（棒の行・ボタン 48・主ボタン 52）
        XCTAssertTrue(open.contains(".frame(minHeight: WebTheme.minTapTarget)"))
        XCTAssertTrue(open.contains("kind: .secondary, height: 48"))
        // 画面写真（ふたを開けた・中身を手に取った・空のトランク・回した側面）
        let shots = try String(contentsOf: root.appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"), encoding: .utf8)
        for name in ["100a-ふたを開けた", "100b-中身を手に取った（メダル）", "100e-空のトランク", "91a-回した側面", "91c-回した底（蝶番と足）"] {
            XCTAssertTrue(shots.contains("\"\(name)\""), "画面写真 \(name) が無い")
        }
    }

    /// 回したときの面: 裏・左右・上・底を板 TrunkFaces の面で貼る（1色の側面に戻さない）
    func testSpinUsesTheFaces() throws {
        let spin = try source("Features/Trunk/TrunkSpinViewer.swift")
        XCTAssertTrue(spin.contains("let back = render(TrunkFaceView(model: model, posts: posts, side: .back, parts: parts))"),
                      "裏がラベルの無い正面のまま（尾錠と錠前が背面に出る）")
        for side in ["left", "right", "top", "bottom"] {
            XCTAssertTrue(spin.contains("render(TrunkFaceView(model: model, posts: posts, side: .\(side), parts: parts))"), side)
        }
        XCTAssertTrue(spin.contains("box: boxFaces, aim: aim)"))
        let medal = try source("Features/Profile/MedalViewerView.swift")
        XCTAssertTrue(medal.contains("buildBox(aspect: aspect, depthRatio: depth, cornerRatio: corner)"))
        XCTAssertTrue(medal.contains("shape.materials = [handleCap, handleCap, handleSide]"), "持ち手が1色のまま")
        // 向きのボタン: 着いたら止める・裏返すと寄せを外す・最初は板の -34°
        XCTAssertTrue(medal.contains("aimHeld = true\n                velocity = 0"), "向きに着いても止まらない")
        XCTAssertTrue(medal.contains("} else if aimHeld {\n            return"))
        XCTAssertTrue(medal.contains("flipTarget = Float(SpinMotion.flipTarget(from: Double(yaw)))\n        aimTarget = nil\n        aimHeld = false"), "裏返すと向きの寄せとぶつかる")
        XCTAssertTrue(medal.contains("private static let boxRestingYaw: Float = -34 * .pi / 180"))
        XCTAssertTrue(medal.contains("for x in TrunkFaces.handleClipCenters.map("), "立体の付け根が絵とずれる")
        // 描く順: 表を先に、残りは処理を一度返してから
        XCTAssertTrue(spin.contains("do { try await Task.sleep(for: .milliseconds(16)) } catch { return }\n            guard !Task.isCancelled else { return }\n            boxFaces = " + "TrunkTextures" + ".box("))
        XCTAssertFalse(medal.contains("buildCard(aspect: aspect, cornerRatio: corner, thicknessRatio: depth, glossyEdge: false)"),
                       "箱が押し出しの形（側面が1つの材質）に戻っている")
        // 正面と同じ描き方を使う（2度書かない）
        let face = try source("Features/Trunk/TrunkFaceView.swift")
        for shared in ["TrunkSkin(look: look", "TrunkBandStrips(look: look", "TrunkCornerCap(look: look", "TrunkRivetFace(",
                       "TrunkHardwareFace(look: look"] {
            XCTAssertTrue(face.contains(shared), "\(shared) を使っていない")
        }
        let box = try source("Features/Trunk/TrunkBoxView.swift")
        XCTAssertTrue(box.contains("TrunkSkin(look: look, w: Self.W, h: Self.H)"))
        XCTAssertTrue(box.contains("TrunkEdgeWear(look: look, w: Self.W, h: Self.H, corner: 16, front: true)"),
                      "正面に縁の擦れが無い（回したときの面とそろわない）")
    }

    /// 🔴 胴の地（`TrunkSkin`）は押せる（c6865c9a で地ごと押せなくなり、ラベルの少ない人が革の面を押しても
    /// 回す画面が開かなかった）。古びの層だけが押すのを通す。トランクのボタンは枠いっぱいが押せる
    func testTrunkBodyStaysTappable() throws {
        let box = try source("Features/Trunk/TrunkBoxView.swift")
        let parts = box.components(separatedBy: "struct TrunkSkin: View {")
        XCTAssertEqual(parts.count, 2)
        let skinBody = parts[1].components(separatedBy: "@ViewBuilder")[0]
        XCTAssertTrue(skinBody.contains("surface(look.surface)"), "TrunkSkin の body が見つからない（見張りが空振り）")
        XCTAssertFalse(skinBody.contains(".allowsHitTesting(false)"), "胴の地がまるごと押せない")
        let main = try source("Features/Trunk/TrunkView.swift")
        XCTAssertTrue(main.contains(".contentShape(Rectangle())\n            }\n            .buttonStyle(TrunkPressStyle())"),
                      "トランクのボタンの押せる範囲が絵の層まかせ")
    }
}

