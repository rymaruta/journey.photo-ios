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

    /// カメラの2つの入口を1段に並べて、行を5本から4本に（シートの高さも1行ぶん詰まる）
    func testPostSheetPutsBothCamerasInOneRow() async throws {
        let sheet = try source("Features/Upload/PostSheet.swift")
        let body = slice(sheet, from: "var body: some View {", to: ".padding(.horizontal, JPSpace.l)")
        // 行は 写真を投稿 → カメラの段 → ストーリー → 旅 の順。カメラの段はカメラのある端末だけ
        assertInOrder(["kind: .photo", "if CameraPicker.isAvailable {", "cameraSplit", "kind: .story", "kind: .trip"],
                      in: body, "投稿シートの並び")
        XCTAssertEqual(body.components(separatedBy: "choice(").count - 1, 3, "大きな行が3本でない（カメラの段と合わせて4本）")
        let split = slice(sheet, from: "private var cameraSplit: some View {", to: "private func cameraTile(")
        assertInOrder(["kind: .camera, accentIcon: false", "kind: .composition, accentIcon: true"], in: split,
                      "カメラの段（カメラ → 構図）")
        // 前の5本の高さ（572）より詰まる。カメラの無い端末は段ごと、下書きの無い人は下書きの行ぶん詰める
        let four = PostSheet.sheetHeight(hasCamera: true, hasDrafts: false)
        XCTAssertLessThan(four, 572)
        XCTAssertLessThan(PostSheet.sheetHeight(hasCamera: false, hasDrafts: false), four)
        XCTAssertGreaterThan(PostSheet.sheetHeight(hasCamera: true, hasDrafts: true), four)
        // 札は板の 56 以上（押せる 44 を満たす）・地は一段浮かせた面（surface-3）
        XCTAssertGreaterThanOrEqual(PostSheet.cameraTileHeight, WebTheme.minTapTarget)
        XCTAssertTrue(sheet.contains(".background(Self.tileFill, in: RoundedRectangle(cornerRadius: Self.tileRadius))"))
    }

    /// 下書きがあれば、シートの下から直に一覧へ（投稿 → 下書き → 1件 の3回）
    func testPostSheetOpensDraftsDirectly() async throws {
        let sheet = try source("Features/Upload/PostSheet.swift")
        XCTAssertTrue(sheet.contains("if drafts > 0 {\n                draftsLine\n            }"), "下書きの行が件数のあるときだけでない")
        let line = slice(sheet, from: "private var draftsLine: some View {", to: "@MainActor static func iconColor")
        XCTAssertTrue(line.contains("onSelect(.drafts)"))
        XCTAssertTrue(line.contains("CountBadge(count: drafts)"), "件数が真鍮のバッジでない")
        XCTAssertTrue(line.contains(".accessibilityIdentifier(\"post.choice.drafts\")"))
        // 行の右の件数バッジは外した（下の行に1つにまとめた）
        XCTAssertFalse(sheet.contains("drafts: postDrafts"))
        XCTAssertFalse(sheet.contains("drafts: storyDrafts"))
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains("case .drafts:\n            showPostDrafts = true"), "シートの「下書き」で一覧を開いていない")
        // 1件を選ぶと、一覧を閉じてからマイページと同じ道で開く
        let drafts = slice(root, from: ".sheet(isPresented: $showPostDrafts", to: "// 「カメラで撮る」")
        assertInOrder(["onOpen: { entry in", "showPostDrafts = false", "tabRouter.openDraft(entry)"], in: drafts,
                      "下書きの一覧から開く")
        // 一覧が出ている間は、ほかの投稿の画面を重ねない（`openDraftWhenFree` も閉じきるまで待つ）
        XCTAssertTrue(root.contains("showPostCamera, showPostDrafts]"), "下書きの一覧が投稿の画面の旗に入っていない")
    }

    // MARK: - 02 新規投稿

    func testUploadWordingAndFixedSizes() async throws {
        XCTAssertEqual(UploadEditEntry.buttonTitle, "色を編集")
        let upload = try source("Features/Upload/UploadView.swift")
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
        XCTAssertFalse(UploadDetails.uploadLocationToggleTitle.contains("1km"))
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
                       "model.resendFrom", "!connectivity.isOffline", "await model.submit()"], in: block, "知らせの並び")
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
                       "resendFrom = UploadSummary.resendStart(queue: queue, failed: failedIds)"], in: submit,
                      "送れなかった番号")
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
        // 閉じるは黒地の上の文字ボタン＝真鍮
        let close = slice(view, from: "ToolbarItem(placement: .topBarTrailing) {", to: "inspiredPicker.close")
        XCTAssertTrue(close.contains(".foregroundStyle(WebTheme.accent)"))
        // 下の段で外せる
        let bar = slice(view, from: "private var selectedBar: some View {", to: "private func tile(")
        assertInOrder(["onRemove()", "dismiss()"], in: bar, "下の段の外す")
        let upload = try source("Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("onRemove: { model.inspired = nil }"))
    }
}
