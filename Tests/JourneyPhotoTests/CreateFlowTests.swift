import XCTest
@testable import JourneyPhoto

/// 「投稿」を押したらすぐ写真の一覧（2026-11-18 owner 採用・案 B1「投稿の入口」）。
///
/// 選ぶシート（#187）と、0.9 秒待ってから開く OS の写真選びをやめ、1.1.96 でストーリーに作った一覧を
/// 投稿とストーリーで共通にした。下の「投稿 | ストーリー」と、左右に払う切り替え
final class CreateFlowTests: XCTestCase {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 押す回数

    /// 写真1枚の投稿は 6 → 4（B2 の裏で送ると合わせて 3）。数は配線から数える
    func testTapCountToPostOnePhoto() throws {
        XCTAssertEqual(CreateFlowRules.tapsBefore, 6)
        XCTAssertEqual(CreateFlowRules.tapsWithLibrary, 4)
        XCTAssertEqual(CreateFlowRules.tapsWithBackgroundSend, 3)
        // 1回目: 下の「投稿」で、すぐ一覧（選ぶシートを挟まない）
        let root = try read("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains("""
            if tab == .post {
                select(previous == .post ? .home : previous, at: "post.revert")
                openCreateFlow(.post)
            }
"""), "下の「投稿」で一覧を開いていない")
        XCTAssertFalse(root.contains("PostSheet("), "選ぶシートが残っている")
        // 2回目: マスを押すとそのまま欄の段へ（「次へ」を挟まない）
        XCTAssertEqual(StoryLibraryRules.tapAction(selecting: false, isMarked: false, markedCount: 0, loading: false,
                                                   limit: UploadViewModel.maxSelection), .open)
        let upload = try read("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        let tap = try XCTUnwrap(upload.range(of: "private func tapLibraryItem("))
        XCTAssertTrue(upload[tap.lowerBound...].prefix(900).contains("await model.loadLibraryAssets([item.id])"),
                      "マスを押しても読み込まない")
        // 0.9 秒待って OS の写真選びを開く道は無い
        XCTAssertFalse(upload.contains("autoOpenDelay"))
        // 許可が無い段（埋め込みの写真選び）では「選択」を出さない（run 1465 の絵で押しても何も起きない「選択」が出ていた）
        XCTAssertTrue(upload.contains("onToggleSelect: libraryGridShown ? {"), "許可が無い段にも「選択」を出している")
    }

    // MARK: - 切り替え

    /// 左へ払うとストーリー、右へ払うと投稿。縦の送り・短い動きでは替えない
    func testSwipeSwitchesOnlyOnAClearHorizontalMove() {
        XCTAssertEqual(CreateFlowRules.swiped(from: .post, dx: -60, dy: 5), .story)
        XCTAssertEqual(CreateFlowRules.swiped(from: .story, dx: 60, dy: -5), .post)
        XCTAssertNil(CreateFlowRules.swiped(from: .post, dx: 60, dy: 0), "同じ向きに替えた")
        XCTAssertNil(CreateFlowRules.swiped(from: .story, dx: -80, dy: 0), "同じ向きに替えた")
        XCTAssertNil(CreateFlowRules.swiped(from: .post, dx: -30, dy: 0), "短い動きで替えた")
        XCTAssertNil(CreateFlowRules.swiped(from: .post, dx: -60, dy: 120), "縦の送りを奪った")
        XCTAssertEqual(CreateFlowRules.swipeDistance, 40, "模型の 40pt と違う")
    }

    /// 一覧の上のチップの行で始まった指は払いに数えない（チップを横に送っただけで投稿とストーリーが替わらない）
    func testSwipeStartingOnTheChipsDoesNotSwitch() throws {
        XCTAssertNil(CreateFlowRules.swiped(from: .post, dx: -80, dy: 0, startsInChips: true), "チップの行の送りで替わった")
        XCTAssertEqual(CreateFlowRules.swiped(from: .post, dx: -80, dy: 0, startsInChips: false), .story)
        let parts = try read("Sources/JourneyPhoto/Features/Common/LibraryPickParts.swift")
        XCTAssertTrue(parts.contains("startsInChips: flow.chipsFrame?.contains(value.startLocation) ?? false"))
        XCTAssertTrue(parts.contains("DragGesture(minimumDistance: 20, coordinateSpace: .global)"), "指の位置とチップの場所の座標がそろっていない")
        XCTAssertTrue(parts.contains(".onAppear { createFlow?.noteChipsFrame(geometry.frame(in: .global)) }"))
    }

    /// 一覧の段の題（SF 600 17）と格子（4列・正方形）は、owner が採った模型どおり。板とずれることを書いておく
    func testMockupDecisionsAreNoted() throws {
        let rules = try read("Sources/JourneyPhoto/Core/Text/StoryLibraryRules.swift")
        XCTAssertEqual(rules.components(separatedBy: "2026-11-18 判断（owner 採用の模型 B1 どおり）").count - 1, 2)
        let parts = try read("Sources/JourneyPhoto/Features/Common/LibraryPickParts.swift")
        XCTAssertTrue(parts.contains("2026-11-18 判断（owner 採用の模型 B1 どおり）: 題は SF 600 17"))
    }

    /// 切り替えは一覧を見ている間だけ（欄を書く・作る段で払っても書きかけを失わない）
    func testSwitcherOnlyWhileTheLibraryIsShown() throws {
        XCTAssertTrue(CreateFlowRules.showsSwitcher(libraryShown: true))
        XCTAssertFalse(CreateFlowRules.showsSwitcher(libraryShown: false))
        let parts = try read("Sources/JourneyPhoto/Features/Common/LibraryPickParts.swift")
        XCTAssertTrue(parts.contains("including: flow.libraryShown ? .all : .subviews"),
                      "作る段でも払う手が中の指の操作を奪う")
        XCTAssertTrue(parts.contains("guard flow.libraryShown,"), "欄を書いている段でも払って替わる")
        // 中の画面が一覧を離れたら知らせる（投稿は欄の段・ストーリーは作る段）
        let upload = try read("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains(".onChange(of: libraryShownForFlow) { _, shown in createFlow?.noteLibrary(shown) }"))
        let story = try read("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(story.contains(".onDisappear { createFlow?.noteLibrary(false) }"))
    }

    /// 題・字・道しるべ（前の選ぶシートの `post.choice.photo` / `post.choice.story` を切り替えが引き継ぐ）
    func testTitlesAndIdentifiers() {
        XCTAssertEqual(CreateFlowRules.title(.post), L("新規投稿", "New post"))
        XCTAssertEqual(CreateFlowRules.title(.story), L("新しいストーリー", "New story"))
        XCTAssertEqual(CreateFlowRules.segmentTitle(.post), L("投稿", "Post"))
        XCTAssertEqual(CreateFlowRules.segmentTitle(.story), L("ストーリー", "Story"))
        XCTAssertEqual(CreateFlowRules.markLimit(.post), UploadViewModel.maxSelection)
        XCTAssertEqual(CreateFlowRules.markLimit(.story), StoryQueue.maxShots)
        // 「・」「·」で区切らない（owner の好み 2026-11-12）
        for text in [CreateFlowRules.title(.post), CreateFlowRules.title(.story), StoryLibraryRules.compositionShortTitle] {
            XCTAssertFalse(text.contains("・") || text.contains("·"), text)
        }
    }

    /// 投稿の印の上限は1回に扱う枚数（10）。上限まで付いたら新しい印は付かない・外すことはできる
    func testPostMarksStopAtTheUploadLimit() {
        let limit = UploadViewModel.maxSelection
        let full = (0..<limit).map { "\($0)" }
        XCTAssertEqual(StoryLibraryRules.toggled(full, id: "x", limit: limit), full)
        XCTAssertEqual(StoryLibraryRules.toggled(full, id: "0", limit: limit).count, limit - 1)
        XCTAssertEqual(StoryLibraryRules.tapAction(selecting: true, isMarked: false, markedCount: limit, loading: false,
                                                   limit: limit), .ignore)
    }

    // MARK: - 一覧の入口

    /// 入口の画面を閉じきってから、選んだ入口（旅の写真から・構図）を呼び手が開く
    @MainActor
    func testChosenEntryIsHandedOverOnce() async {
        let flow = CreateFlow(mode: .story)
        XCTAssertEqual(flow.mode, .story)
        XCTAssertNil(flow.takeChosen())
        flow.choose(.trip)
        XCTAssertEqual(flow.takeChosen(), .trip)
        XCTAssertNil(flow.takeChosen(), "同じ入口を2回開く")
        XCTAssertFalse(flow.used)
        flow.noteLibrary(false)
        XCTAssertFalse(flow.libraryShown)
        XCTAssertTrue(flow.used, "写真を選んだのに、閉じたあとマイページ・ホームを読み直さない")
    }

    // MARK: - 一覧で選んだ写真を読む

    private func prepared(_ byte: UInt8) -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: Data([byte]), fileName: "p.jpg", contentType: "image/jpeg",
                               exif: nil, coords: nil, takenOn: nil)
    }

    @MainActor
    private func model(reading assets: [String: Data?]) -> UploadViewModel {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!, tokenProvider: StubTokenProvider(token: "t"))
        let model = UploadViewModel(uploads: UploadService(api: api), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.readLibraryAsset = { id in assets[id] ?? nil }
        model.prepareData = { data in
            ImagePreparer.Prepared(data: data, fileName: "p.jpg", contentType: "image/jpeg",
                                   exif: nil, coords: nil, takenOn: nil)
        }
        model.keepEditSource = { _ in nil }
        model.makeStripThumb = { _ in nil }
        model.setAttachesLocation(false)
        return model
    }

    /// 選んだ順に並ぶ。読めた分は受け、読めなかった枚数は黙らずに言う
    @MainActor
    func testLibraryAssetsLoadInOrderAndReportFailures() async {
        let model = model(reading: ["a": Data([1]), "b": nil, "c": Data([3])])
        await model.loadLibraryAssets(["c", "b", "a"])
        XCTAssertEqual(model.items.map { $0.prepared.data }, [Data([3]), Data([1])], "選んだ順に並ばない")
        XCTAssertFalse(model.isLoadingPicked)
        XCTAssertEqual(model.errorMessage, L("1 枚は読み込めませんでした", "1 photo(s) couldn't be loaded"))
    }

    /// 1回に扱う枚数（10）を超えて並べない（並んでいる写真と合わせて）
    @MainActor
    func testLibraryAssetsRespectTheUploadLimit() async {
        let ids = (0..<15).map { "id\($0)" }
        var assets: [String: Data?] = [:]
        for (index, id) in ids.enumerated() { assets[id] = Data([UInt8(index)]) }
        let model = model(reading: assets)
        model.append(prepared(200))
        await model.loadLibraryAssets(ids)
        XCTAssertEqual(model.items.count, UploadViewModel.maxSelection)
        XCTAssertEqual(model.items.last?.prepared.data, Data([UInt8(UploadViewModel.maxSelection - 2)]))
    }

    /// 返ってこない1枚で読み込み中のまま止まらない（1枚ごとの上限時間）
    @MainActor
    func testLibraryAssetTimesOut() async {
        let model = model(reading: [:])
        model.pickedLoadTimeout = 0.2
        model.readLibraryAsset = { _ in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return Data([9])
        }
        let started = Date()
        await model.loadLibraryAssets(["slow"])
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "上限時間を待たずに止まった・待ちすぎた")
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.errorMessage, L("写真を読み込めませんでした", "Couldn't load the photos"))
        XCTAssertFalse(model.isLoadingPicked, "読み込み中のまま残った")
    }

    /// 送っている間・読み込み中は受けない（二重に並ばない）
    @MainActor
    func testLibraryAssetsIgnoredWhileLoading() async {
        let model = model(reading: ["a": Data([1]), "b": Data([2])])
        model.readLibraryAsset = { id in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return id == "a" ? Data([1]) : Data([2])
        }
        // 1枚目を押して読み込み中になってから、2枚目を押す（押す順を決める・`async let` は始まる順が決まらない）
        let first = Task { await model.loadLibraryAssets(["a"]) }
        while !model.isLoadingPicked { await Task.yield() }
        await model.loadLibraryAssets(["b"])
        await first.value
        XCTAssertEqual(model.items.map { $0.prepared.data }, [Data([1])],
                       "読み込み中に押した別のマスが、先に押したマスを押しのけた・一緒に並んだ")
    }
}
