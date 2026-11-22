import XCTest
@testable import JourneyPhoto

/// 1.1.83「画面デザインの案」第4章 投稿まわりのデザイン（2026-11-12 判断）。
///
/// 投稿シート・新規投稿・下書きの一覧・旅の写真からまとめて・この写真を見て撮影の「推奨」。
/// 画面の部品は Linux で動かせないので、決まりは値で、配線は元のコードを読んで確かめる
@MainActor
final class PostScreensDesign183Tests: XCTestCase {

    // MARK: - 道具

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `start` から次の `end` の手前まで
    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let head = text.range(of: start) else { return "" }
        let rest = text[head.upperBound...]
        guard let tail = rest.range(of: end) else { return String(rest) }
        return String(rest[..<tail.lowerBound])
    }

    private func assertInOrder(_ parts: [String], in text: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: cursor..<text.endIndex) else {
                XCTFail("\(what): 「\(part)」が順に無い", file: file, line: line)
                return
            }
            cursor = found.upperBound
        }
    }

    // MARK: - 01 投稿シート

    /// 2026-11-18（案 B1・owner 採用）: 選ぶシートはやめ、カメラの2つの入口は**写真の一覧の先頭のマス**へ移した
    /// （カメラ → 構図 → 写真）。構図のマスは投稿の入口の中で、カメラのある端末だけ。地は一段浮かせた面（surface-3）
    func testCreateFlowPutsCameraAndCompositionFirst() async throws {
        let grid = try source("Features/Common/LibraryGrid.swift")
        let body = slice(grid, from: "LazyVGrid(columns: columns", to: "if loaded && items.isEmpty")
        assertInOrder(["cameraCell", "if let onComposition { compositionCell(onComposition) }", "ForEach(items)"],
                      in: body, "一覧の先頭（カメラ → 構図 → 写真）")
        XCTAssertTrue(grid.contains("RaisedTile.fill"), "カメラのマスの地が一段浮かせた面でない")
        let upload = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("onComposition: createFlow != nil && CameraPicker.isAvailable\n                                ? { chooseFlowEntry(.composition) } : nil,"),
                      "構図のマスが投稿の入口の中だけ・カメラのある端末だけになっていない")
        XCTAssertNil(try? source("Features/Upload/PostSheet.swift"), "前の選ぶシートが残っている")
    }

    /// 下書きがあれば、一覧の上のチップから直に一覧へ（投稿 → 下書き → 1件 の3回のまま）
    func testLibraryDraftsChipOpensDraftsDirectly() async throws {
        XCTAssertEqual(CreateFlowRules.entries(inCreateFlow: true, drafts: 0), [.trip])
        XCTAssertEqual(CreateFlowRules.entries(inCreateFlow: true, drafts: 2), [.trip, .drafts(2)])
        XCTAssertEqual(CreateFlowRules.entries(inCreateFlow: false, drafts: 1), [.drafts(1)],
                       "テーマ・観光スポットから開いた投稿の画面に「旅の写真から」が出る")
        let parts = try source("Features/Common/LibraryPickParts.swift")
        let chip = slice(parts, from: "case .drafts(let count):", to: "private func chipLabel(")
        XCTAssertTrue(chip.contains(".accessibilityIdentifier(\"post.choice.drafts\")"))
        XCTAssertTrue(parts.contains("CountBadge(count: count)"), "件数が真鍮のバッジでない")
        let upload = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("onDrafts: { openDraftList(tidying: false) })"), "チップから下書きの一覧を開いていない")
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("case .drafts:\n            showPostDrafts = true"), "空の画面の「下書き」で一覧を開いていない")
        // 1件を選ぶと、一覧を閉じてからマイページと同じ道で開く
        let drafts = slice(root, from: ".sheet(isPresented: $showPostDrafts", to: "// 「カメラで撮る」")
        assertInOrder(["onOpen: { entry in", "showPostDrafts = false", "tabRouter.openDraft(entry)"], in: drafts,
                      "下書きの一覧から開く")
        // 一覧が出ている間は、ほかの投稿の画面を重ねない（`openDraftWhenFree` も閉じきるまで待つ）
        XCTAssertTrue(root.contains("showPostCamera, showPostDrafts]"), "下書きの一覧が投稿の画面の旗に入っていない")
    }

    // MARK: - 02 新規投稿

    func testUploadWordingAndFixedSizes() async throws {
        let upload = try source("Features/Upload/UploadView.swift")
        // 2026-11-16（A11）: 帯の下の「色を編集」は無くした（入口は写真の札の「編集」1つ）
        XCTAssertFalse(upload.contains("色を編集"), "帯の下の「色を編集」が戻った")
        XCTAssertFalse(upload.contains("写真を押すと、色や明るさを編集できます"), "帯の下の一言が残っている")
        XCTAssertFalse(upload.contains("L(\"写真を編集\", \"Edit photo\")"), "写真の詳細の「写真を編集」と同じ名前のまま")
        // 帯の札の字と印は caption の段に追従（固定 12・10 をやめた）
        let thumb = slice(upload, from: "private func thumb(", to: "private func openLibrary()")
        XCTAssertFalse(thumb.contains(".font(.system(size: 12, weight: .semibold))"))
        XCTAssertFalse(thumb.contains(".font(.system(size: 10, weight: .bold))"))
        XCTAssertTrue(thumb.contains(".font(JPFont.caption.weight(.semibold))"))
        // 元の写真の小さな写真: 段に無い白 20% の縁をやめ、角 6
        let inspired = slice(upload, from: "private func inspiredThumb(", to: "private var songRow")
        XCTAssertFalse(inspired.contains("Color.white.opacity(0.2)"))
        XCTAssertTrue(inspired.contains("RoundedRectangle(cornerRadius: JPRadius.xs)"))
        // 付ける前の印は構図（camera.viewfinder）と分ける
        XCTAssertNotEqual(UploadDetails.inspiredSymbol, "camera.viewfinder")
        XCTAssertTrue(upload.contains("systemImage: UploadDetails.inspiredSymbol"))
        // 撮影地の位置: 名前は短く、約1km は下の一言
        XCTAssertTrue(UploadDetails.uploadLocationToggleNote(attaches: true).contains("約1km"))
        XCTAssertEqual(UploadDetails.uploadLocationToggleNote(attaches: false),
                       UploadDetails.locationToggleNote(attaches: false))
    }

    /// 詳しい設定は閉じたままでも値を行の右に1行で（入らなければ題の下へ回し、切って隠さない）
    func testDetailsShowValueOnOneLine() async throws {
        let upload = try source("Features/Upload/UploadView.swift")
        let toggle = slice(upload, from: "private var detailsToggle: some View {", to: "private var rowsCard")
        assertInOrder(["ViewThatFits(in: .horizontal) {", "HStack(spacing: 12) {", "Text(detailsSummary)", ".lineLimit(1)",
                       "VStack(alignment: .leading, spacing: 3) {", "Text(detailsSummary)"], in: toggle, "詳しい設定の行")
    }

    /// 写真がまだ無いときは大きな2枚の枠（写真を選ぶ・撮る）と、その下に下書きの行
    func testUploadEmptyStateHasTwoPickers() async throws {
        XCTAssertEqual(UploadStripLayout.emptyTileWidth, 120)
        XCTAssertEqual(UploadStripLayout.emptyTileHeight, 150)
        let upload = try source("Features/Upload/UploadView.swift")
        let block = slice(upload, from: "private var photosBlock: some View {", to: "private func emptyPicker(")
        assertInOrder(["if model.items.isEmpty && !model.isLoadingPicked {", "emptyPickers", "draftsEntryRow",
                       "} else {", "strip"], in: block, "写真が無いときの形")
        let pickers = slice(upload, from: "private var emptyPickers: some View {", to: "private func emptyPicker(")
        XCTAssertTrue(pickers.contains("action: openLibrary"))
        XCTAssertTrue(pickers.contains("if CameraPicker.isAvailable {"), "カメラの無い端末にも「撮る」を出している")
        XCTAssertTrue(pickers.contains(".disabled(model.isWorking || model.isRestoringDraft)"))
    }

    /// 途中で失敗したら、どこから送り直すかを言う（「2枚目からもう一度」）
    func testResendTitleAndStart() async {
        XCTAssertEqual(UploadSummary.resendTitle(from: 2), "2枚目からもう一度")
        XCTAssertEqual(UploadSummary.resendTitle(from: 1), "もう一度送る")
        XCTAssertEqual(UploadSummary.resendStart(queue: ["a", "b", "c"], failed: ["c", "b"]), 2)
        XCTAssertEqual(UploadSummary.resendStart(queue: ["a", "b"], failed: ["a"]), 1)
        XCTAssertNil(UploadSummary.resendStart(queue: ["a", "b"], failed: [String]()))
    }

    /// 失敗・圏外は起きた所（上）に危険の色の一言。トーストにしない・書いた物は残す・下書きにも逃がせる
    func testUploadOfflineAndFailureLines() async throws {
        XCTAssertTrue(UploadSummary.offlineNote.contains("圏外"))
        XCTAssertTrue(UploadSummary.offlineNote.contains("書いた内容は残っています"))
        let upload = try source("Features/Upload/UploadView.swift")
        let block = slice(upload, from: "private var progressAndErrors: some View {", to: "\n}\n")
        assertInOrder(["connectivity.isOffline && !model.items.isEmpty && !model.isWorking",
                       "alertLine(UploadSummary.offlineNote)", "offlineCanSaveDraft",
                       "saveDraftAndClose(update: closeChoice == .update)",
                       "alertLine(error)",
                       "model.resendFrom", "!connectivity.isOffline", "sendInBackground()"], in: block, "知らせの並び")
        XCTAssertFalse(block.contains("toasts.show"), "失敗・圏外をトーストにしている")
        let line = slice(upload, from: "private func alertLine(", to: "private func saveDraftAndClose(")
        XCTAssertTrue(line.contains(".font(JPFont.footnote)"))
        XCTAssertTrue(line.contains(".foregroundStyle(WebTheme.danger)"))
        XCTAssertTrue(line.contains("exclamationmark.circle"))
        // 圏外の「下書きに保存」は閉じる確認と同じ決まり（いっぱいなら出さない）
        let save = slice(upload, from: "private var offlineCanSaveDraft: Bool {", to: "private func alertLine(")
        XCTAssertTrue(save.contains("case .full: return false"))
        XCTAssertTrue(save.contains("closeDialog.canSave"))
        // 送れなかった番号は送り始めるときに下ろし、失敗の回にだけ立てる
        let model = try source("Features/Upload/UploadViewModel.swift")
        let submit = slice(model, from: "func submit() async {", to: "private func makeDraft(")
        assertInOrder(["resendFrom = nil", "failedIds.append(item.id)",
                       "resendFrom = UploadSummary.resendAfterSubmit(queue: queue, failed: failedIds, cancelled: cancelled)"], in: submit,
                      "送れなかった番号")
    }

    // MARK: - 確かめ役の直し（2026-11-12）

    /// 「構図を重ねて撮る」のマスは4列のマスに入る短い名前「構図」、読み上げは長い名前（2026-11-18・案 B1）
    func testCompositionCellNames() async throws {
        XCTAssertEqual(StoryLibraryRules.compositionTitle, "構図を重ねて撮る")
        XCTAssertEqual(StoryLibraryRules.compositionShortTitle, "構図")
        let grid = try source("Features/Common/LibraryGrid.swift")
        let cell = slice(grid, from: "private func compositionCell(", to: "private func tile<")
        XCTAssertTrue(cell.contains("Text(StoryLibraryRules.compositionShortTitle)"))
        XCTAssertTrue(cell.contains(".accessibilityLabel(StoryLibraryRules.compositionTitle)"), "読み上げが短い名前のまま")
        XCTAssertTrue(cell.contains(".accessibilityIdentifier(\"post.choice.composition\")"), "前の入口の道しるべを引き継いでいない")
    }

    /// 撮影地の位置のオンの一言は言い切らない（2026-10-18 の決まり・`PlaceCoordsRule`）
    func testLocationNoteKeepsCaveat() async {
        XCTAssertTrue(UploadDetails.uploadLocationToggleNote(attaches: true).contains("撮影地を書き換えると載せないことがあります"))
    }

    /// 「n枚目からもう一度」は、やめた回は立てない・写真の並びが変わったら下ろす
    func testResendIsDroppedWhenCancelledOrReordered() async throws {
        XCTAssertNil(UploadSummary.resendAfterSubmit(queue: ["a", "b"], failed: ["b"], cancelled: true))
        XCTAssertEqual(UploadSummary.resendAfterSubmit(queue: ["a", "b"], failed: ["b"], cancelled: false), 2)
        XCTAssertTrue(UploadSummary.keepsResend(old: ["b", "c"], new: ["b", "c"]), "題を直しただけで下ろしている")
        XCTAssertFalse(UploadSummary.keepsResend(old: ["b", "c"], new: ["c", "b"]), "並べ替えても残っている")
        XCTAssertFalse(UploadSummary.keepsResend(old: ["b", "c"], new: ["b"]), "外しても残っている")
        XCTAssertFalse(UploadSummary.keepsResend(old: ["b"], new: ["b", "d"]), "足しても残っている")
        let model = try source("Features/Upload/UploadViewModel.swift")
        let items = slice(model, from: "@Published var items: [PendingPhoto] = [] {", to: "let editSources")
        assertInOrder(["if resendFrom != nil,", "UploadSummary.keepsResend(old: oldValue.map(\\.id), new: items.map(\\.id))",
                       "resendFrom = nil"], in: items, "並びが変わったら下ろす")
        XCTAssertTrue(model.contains("resendFrom = UploadSummary.resendAfterSubmit(queue: queue, failed: failedIds, cancelled: cancelled)"))
    }

    /// 下書きの件数は呼び手が開く前に数えて渡す（出てから数え直すと高さが跳ねる）。旅の札の「投稿済み n日」
    func testDraftCountIsPassedAndPostedChip() async throws {
        let root = try source("App/RootView.swift")
        // 2026-11-18（案 B1）: 下の「投稿」は写真の一覧（選ぶシートの高さの跳ねは、シートごと無くなった）
        XCTAssertTrue(root.contains(".fullScreenCover(isPresented: $showPostChoice, onDismiss: createFlowDismissed) {\n                CreateFlowView(flow: createFlow)"))
        let list = try source("Features/Trips/LibraryTripListView.swift")
        let card = slice(list, from: "struct LibraryTripCard: View {", to: "\n}\n")
        assertInOrder(["if postedDays > 0 {", "L(\"投稿済み \\(postedDays)日\"", ".foregroundStyle(WebTheme.foreground)",
                       ".background(Color.black.opacity(0.55), in: Capsule())"], in: card, "投稿済みの札")
    }

    // MARK: - 03 下書きの一覧

    func testDraftsListIsTwoRowsAndGap4() async throws {
        XCTAssertEqual(DraftsView.gridSpacing, 4)
        XCTAssertEqual(DraftsView.gridSpacing, WebTheme.gridSpacing)
        // 帯は1文（「作ってから7日で…」は説明のシート）
        XCTAssertFalse(DraftsText.expiringBand(1).contains("日で消えます"))
        XCTAssertTrue(DraftsText.facts(count: 1, megabytes: 1).contains { $0.headline.contains("日で消えます") },
                      "説明のシートに期限が無い")
        let view = try source("Features/Drafts/DraftsView.swift")
        let list = slice(view, from: "LazyVStack(alignment: .leading, spacing: 0) {", to: ".padding(.bottom, JPSpace.screenEnd)")
        // 帯 → 絞り込みと切り替えの1段 → 格子 → 容量の注記
        assertInOrder(["bands", "viewRow", "grid", "rows", "if !selecting { storageRow }"], in: list, "下書きの一覧の並び")
        XCTAssertFalse(list.contains("chips\n"), "絞り込みが別の段に残っている")
        let row = slice(view, from: "private var viewRow: some View {", to: "private func layoutButton(")
        assertInOrder(["chips", "layoutButton(.grid"], in: row, "絞り込みと切り替えの1段")
        XCTAssertFalse(view.contains("gridHint"), "「長押しで…」の一言が残っている")
        XCTAssertFalse(view.contains("GridItem(.flexible(), spacing: 2)"), "格子の隙間 2 が残っている")
        // 容量は札でなく注記（地なし・12 の text-3）。押すと説明のシート
        let storage = slice(view, from: "private var storageRow: some View {", to: "private var viewRow")
        XCTAssertFalse(storage.contains("WebTheme.card"))
        XCTAssertTrue(storage.contains("showAbout = true"))
    }

    // MARK: - 04 旅の写真からまとめて

    func testLibraryTripCardsAndWording() async throws {
        XCTAssertEqual(LibraryTripCard.height, 120)
        XCTAssertEqual(LibraryTripCard.leadHeight, 150)
        XCTAssertEqual(LibraryTripCard.radius, 14)
        XCTAssertEqual(LibraryTrips.makePostTitle(11), "11枚で投稿をつくる")
        let list = try source("Features/Trips/LibraryTripListView.swift")
        XCTAssertTrue(list.contains("L(\"旅の写真からまとめて\", \"From a trip in your photos\")"), "題が入口とずれている")
        XCTAssertFalse(list.contains("opacity(postedDays > 0 ? 0.45"), "投稿済みの旅を薄くしている")
        XCTAssertFalse(list.contains("ProgressView()"), "探している間が回る印のまま")
        XCTAssertTrue(list.contains(".background(WebTheme.accentSoft"), "一部だけ許可が案内の帯でない")
        // 写真の上は白だけ（札の中に真鍮を置かない）
        let card = slice(list, from: "struct LibraryTripCard: View {", to: "\n}\n")
        XCTAssertFalse(card.contains("WebTheme.accent"))
        XCTAssertTrue(card.contains(".font(JPFont.rowTitle)"))
        // 見つからない: 次の一手（全部許可なら選び足しは出さない）
        let notFound = slice(list, from: "private var notFound: some View {", to: "private var list: some View {")
        assertInOrder(["if model.status == .limited {", "addMore()", "if let onPostSingly {"], in: notFound, "見つからないときの一手")
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("onPostSingly: { postSinglyAfterTripImport = true }"))
        XCTAssertTrue(root.contains("} else if postSinglyAfterTripImport {\n                    showPhotoUpload = true"))
        let pick = try source("Features/Trips/LibraryTripPickView.swift")
        XCTAssertTrue(pick.contains("Text(LibraryTrips.makePostTitle(selected.count))"))
        XCTAssertFalse(pick.contains("旅の記録に入れる\""), "ボタンが「旅の記録に入れる」のまま")
        XCTAssertTrue(pick.contains("GridItem(.flexible(), spacing: WebTheme.gridSpacing), count: 4"))
        // 断られたときは危険の色の一言
        let flow = try source("Features/Trips/LibraryTripFlowView.swift")
        let refused = slice(flow, from: "if refused {", to: ".padding(.horizontal, 20)")
        XCTAssertTrue(refused.contains(".foregroundStyle(WebTheme.danger)"))
    }

    // MARK: - 06 この写真を見て撮影

    func testInspiredPickerStates() async throws {
        // 読めなかった（一覧が読めず、出せる写真も無い）と、まだ無いを分ける
        XCTAssertTrue(InspiredBy.loadFailed(feedLoaded: false, candidates: 0))
        XCTAssertFalse(InspiredBy.loadFailed(feedLoaded: false, candidates: 3), "自分の写真から出せる棚まで失敗にしている")
        XCTAssertFalse(InspiredBy.loadFailed(feedLoaded: true, candidates: 0), "まだ無いを失敗にしている")
        let view = try source("Features/Upload/InspiredPickerView.swift")
        let content = slice(view, from: "private func content(_ shelf: InspiredBy.Shelf) -> some View {", to: "private var skeleton")
        assertInOrder(["if loading || pools == nil {", "skeleton", "InspiredBy.loadFailed(", "failedState",
                       "candidates(shelf).isEmpty"], in: content, "棚の状態")
        XCTAssertFalse(view.contains("ProgressView()"), "読み込み中が回る印のまま")
        XCTAssertFalse(view.contains("cornerRadius: 6"), "格子に角が残っている")
        XCTAssertTrue(view.contains("Rectangle().strokeBorder(Color.white, lineWidth: JPStroke.emphasis)"))
        // 閉じるは左上のシートの「閉じる」（2026-11-13 owner 承認・#187。前は右上の真鍮の字）
        let close = slice(view, from: "ToolbarItem(placement: .cancellationAction) {", to: "inspiredPicker.close")
        XCTAssertTrue(close.contains("SheetCloseButton()"))
        // 下の段で外せる
        let bar = slice(view, from: "private var selectedBar: some View {", to: "private func tile(")
        assertInOrder(["onRemove()", "dismiss()"], in: bar, "下の段の外す")
        let upload = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("onRemove: { model.inspired = nil }"))
    }
}
