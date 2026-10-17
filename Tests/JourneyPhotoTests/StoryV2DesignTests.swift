import XCTest
@testable import JourneyPhoto

/// v2 の板（デザインシステム v2・2026-10-14）の第6・7段——**投稿とストーリー**の見た目の決まり。
///
/// 画面の部品は Linux では描けないので、`DesignFoundationTests` と同じく**値は数で**、**部品の作りは
/// 元のファイルを読んで**見張る。字があるかだけでなく、型の範囲と呼び出しの順まで見る。
///
/// 守っている CLAUDE.md の owner の好み: 未見の輪は真鍮・ストーリーの反応のハートは真鍮・親しい友達の ★ は真鍮・
/// 「写真を追加」は真鍮・写真の上は白（灰は白の透過）・本文 12pt 以上・押せるもの 44pt・危険の色は `WebTheme.danger`。
final class StoryV2DesignTests: XCTestCase {

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

    /// `func <name>` / `var <name>` から次の `func`・`var` の宣言までを切り出す（ほかの関数の同じ字に当たらないように）
    private func member(_ name: String, in text: String,
                        file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = text.range(of: name) else {
            XCTFail("\(name) が無い", file: file, line: line)
            return ""
        }
        let rest = text[start.upperBound...]
        let ends = ["\n    private func ", "\n    private var ", "\n    func ", "\n    var ",
                    "\n    static ", "\n    @MainActor static ", "\n    private static ", "\n}"]
            .compactMap { rest.range(of: $0)?.lowerBound }
        return String(rest[..<(ends.min() ?? rest.endIndex)])
    }

    /// `parts` がこの順に `text` に現れる（並びの入れ替え・呼び出しの削除で落ちる）
    private func assertInOrder(_ parts: [String], in text: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: cursor..<text.endIndex) else {
                XCTFail("\(what): 「\(part)」が無いか、順が違う", file: file, line: line)
                return
            }
            cursor = found.upperBound
        }
    }

    // MARK: - ストーリーの輪（v2 StoryRings）

    /// 外径 64・線 2・黒いすき間 3・写真 54。見た輪は白 22%、輪と輪の間は 14
    func testRingMetrics() {
        XCTAssertEqual(StoryRingMetrics.size, 64)
        XCTAssertEqual(StoryRingMetrics.stroke, JPStroke.emphasis)
        XCTAssertEqual(StoryRingMetrics.gap, JPStroke.ringGap)
        XCTAssertEqual(StoryRingMetrics.photo, 54)
        XCTAssertEqual(StoryRingMetrics.seenOpacity, 0.22)
        XCTAssertEqual(StoryRingMetrics.spacing, 14)
        XCTAssertEqual(StoryRingMetrics.metalStartDegrees, 210)
    }

    /// 🔴 **未見の輪は真鍮の金属の光**（owner の好み「未見の輪は真鍮」・v2 の brass-lo → hi → 真鍮 → lo）。
    /// 見た輪は白 22% の一色
    func testUnseenRingIsMetalBrass() throws {
        let ring = try source("Features/Stories/StoryRing.swift")
        let style = member("static func style(unseen: Bool)", in: ring)
        assertInOrder(["if unseen {", "WebTheme.accentMetal",
                       "AngularGradient(colors: [metal[2], metal[0], metal[1], metal[2]]",
                       "Color.white.opacity(StoryRingMetrics.seenOpacity)"], in: style, "輪の塗り")
        XCTAssertTrue(ring.contains(".stroke(Self.style(unseen: unseen)"), "輪の線が塗りの決まりを通っていない")
        XCTAssertTrue(ring.contains("StoryPlayback.ringSegments(count: count)"), "本数の切れ目を描いていない")
    }

    /// ホームの輪の並びは共通の輪を使う（行の中に一色の輪を書き直さない）。名前は未読が白・既読が灰
    func testStoriesRowUsesTheSharedRing() throws {
        let row = try source("Features/Stories/StoriesRow.swift")
        XCTAssertTrue(row.contains("StoryRing(count: count, unseen: unseen)"), "人の輪が共通の輪を通っていない")
        XCTAssertTrue(row.contains("StoryRing(count: 1, unseen: false) { myFace }"), "自分の入口が白 22% の輪でない")
        XCTAssertFalse(row.contains("Color.white.opacity(0.18)"), "v1 の既読の輪（白 18%）が残っている")
        XCTAssertTrue(row.contains("unseen ? WebTheme.text : WebTheme.text3"), "名前の色が未読・既読で分かれていない")
        XCTAssertTrue(row.contains("HStack(alignment: .top, spacing: StoryRingMetrics.spacing)"))
        // 送っている間の輪: 地は白 16%、写真は 60%
        let upload = member("private func uploadRing(", in: row)
        assertInOrder(["StoryRingMetrics.uploadTrackOpacity", "failed ? WebTheme.danger : WebTheme.accent",
                       ".opacity(StoryRingMetrics.uploadPhotoOpacity)"], in: upload, "送っている間の輪")
        XCTAssertTrue(row.contains("accessibilityIdentifier(\"stories.uploading\")"), "画面写真の道しるべが消えた")
    }

    /// フォロー中の輪が無いときは、入口の行と「探す」への道（真鍮・黒地の上）。**読み終える前には出さない**
    func testEmptyRingRow() throws {
        let row = try source("Features/Stories/StoriesRow.swift")
        XCTAssertTrue(row.contains("ordered.mine == nil && ordered.others.isEmpty && model.loaded"),
                      "読み込み前に「輪が無い」の行を出している")
        let empty = member("private var emptyRow: some View", in: row)
        assertInOrder(["showComposer = true", "TabRouter.shared.openSearch()", ".foregroundStyle(WebTheme.accent)"],
                      in: empty, "輪が無いときの行")
        XCTAssertLessThanOrEqual(StoryRingMetrics.emptyRowWidth, 320 - 2 * JPSpace.gutter, "いちばん狭い iPhone に収まらない")
    }

    // MARK: - 見る画面（v2 StoryViewer・Paused・Menu・Reply・Mine・DeleteConfirm）

    func testViewerMetrics() {
        XCTAssertEqual(StoryViewerMetrics.progressHeight, 2.5)
        XCTAssertEqual(StoryViewerMetrics.progressGap, 3)
        XCTAssertEqual(StoryViewerMetrics.progressTrack, 0.32)
        XCTAssertLessThan(StoryViewerMetrics.pausedTrack, StoryViewerMetrics.progressTrack, "止めた線が沈んでいない")
        XCTAssertLessThan(StoryViewerMetrics.pausedScale, 1)
        XCTAssertEqual(StoryViewerMetrics.menuDim, 0.5)
        XCTAssertEqual(StoryViewerMetrics.replyDim, 0.55)
        XCTAssertEqual(StoryViewerMetrics.deleteDim, 0.6)
        XCTAssertEqual(StoryViewerMetrics.menuRowHeight, 56)
        XCTAssertEqual(StoryViewerMetrics.confirmWidth, 290)
        XCTAssertEqual(StoryViewerMetrics.confirmButtonHeight, 50)
        // 押せるもの 44 以上
        for size in [StoryViewerMetrics.menuRowHeight, StoryViewerMetrics.confirmButtonHeight,
                     StoryViewerMetrics.replyFieldHeight, StoryViewerMetrics.sendSize, StoryViewerMetrics.ownCircle] {
            XCTAssertGreaterThanOrEqual(size, WebTheme.minTapTarget)
        }
        XCTAssertGreaterThanOrEqual(StoryViewerMetrics.ownCountSize, Double(WebTheme.minBodyText))
    }

    /// 画面が板の値を通っている（進み線・止めた形・暗幕・シートの行）
    func testViewerUsesTheMetrics() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains(".frame(height: StoryViewerMetrics.progressHeight)"))
        XCTAssertTrue(viewer.contains("HStack(spacing: StoryViewerMetrics.progressGap)"))
        let segment = member("private func segment(fill: Double?, isCurrent: Bool)", in: viewer)
        assertInOrder(["chrome.showsPill", "StoryViewerMetrics.pausedTrack", "StoryViewerMetrics.progressTrack",
                       "StoryViewerMetrics.pausedFill"], in: segment, "止めている間の進み線")
        XCTAssertTrue(viewer.contains(".scaleEffect(chrome.showsPill ? StoryViewerMetrics.pausedScale : 1)"),
                      "止めている間に写真を縮めていない")
        // 「…」・削除の確認は画面全体、返信を書いている間は写真の上（2026-10-16・`StoryViewerV2FixTests`）
        let dim = member("private var overlayDimOpacity: Double", in: viewer)
        assertInOrder(["StoryViewerMetrics.deleteDim", "StoryViewerMetrics.menuDim"], in: dim, "暗幕")
        XCTAssertTrue(member("private var photoDimOpacity: Double", in: viewer).contains("StoryViewerMetrics.replyDim"))
        let row = member("private func menuRow(", in: viewer)
        XCTAssertTrue(row.contains(".frame(minHeight: StoryViewerMetrics.menuRowHeight)"))
        XCTAssertTrue(row.contains("danger ? Self.storyDanger : WebTheme.text"), "ブロック・通報が危険の色でない")
        XCTAssertTrue(viewer.contains("private static let storyDanger = WebTheme.danger"))
    }

    /// 「…」のシートは誰のストーリーかを先に出す（v2 StoryViewerMenu）
    func testMenuStartsWithWhose() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        let menu = member("private func menuSheet(for story: Story)", in: viewer)
        assertInOrder(["menuHeader(for: story)", "if items.contains(.pause)", "if items.contains(.block)"],
                      in: menu, "「…」のシート")
        let header = member("private func menuHeader(for story: Story)", in: viewer)
        assertInOrder(["menuTitle(for: story)", "開いている間は止まっています"], in: header, "シートの先頭")
    }

    /// 🔴 **ストーリーの反応のハートは、送る前から真鍮**（owner の好み・v2 StoryViewer）。送ったかは塗りで分ける
    func testReactionHeartIsBrass() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("private static let heartColor = WebTheme.accent"))
        assertInOrder(["Image(systemName: reacted ? \"heart.fill\" : \"heart\")", ".foregroundStyle(Self.heartColor)"],
                      in: viewer, "反応のハート")
        XCTAssertFalse(viewer.contains("reacted ? WebTheme.accent : Color.white"), "送る前のハートが白に戻っている")
    }

    /// 返信欄（v2: ふだんは白 30% の線だけ・書いている間は暗い地）と、白い送信の丸 44
    func testReplyFieldIsOutlined() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        assertInOrder([".frame(minHeight: StoryViewerMetrics.replyFieldHeight)",
                       ".background(replyFocused ? Self.replyFocusedFill : Color.clear, in: Capsule())",
                       "StoryViewerMetrics.replyFieldFocusedBorder", "StoryViewerMetrics.replyFieldBorder"],
                      in: viewer, "返信欄")
        XCTAssertTrue(viewer.contains(".frame(width: StoryViewerMetrics.sendSize, height: StoryViewerMetrics.sendSize)"))
        XCTAssertFalse(viewer.contains("jpGlass(in: Capsule(), border: replyFocused ? 0.6 : 0.35)"), "v1 のガラスの欄が残っている")
    }

    /// 自分のストーリー: 返信の件数は共通の件数バッジ（真鍮＋墨・12pt）。v1 の 10pt の字を使わない
    func testOwnFooterUsesTheCountBadge() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("CountBadge(count: badge, maximum: 99)"))
        XCTAssertFalse(viewer.contains("JPFont.mono(10"), "本文の最小 12 を割る 10pt の数字が残っている")
        let circle = member("private func ownCircle(symbol: String)", in: viewer)
        assertInOrder([".background(WebTheme.sheet, in: Circle())", "StoryViewerMetrics.ownCircleBorder"],
                      in: circle, "足元の丸")
        // 「見た人 12　いいね 4」を1行に（数は白・名札は白の透過の灰）
        let count = member("private func ownCount(", in: viewer)
        assertInOrder(["WebTheme.muted2", "JPFont.number(StoryViewerMetrics.ownCountSize, weight: .semibold",
                       "WebTheme.text"], in: count, "見た人・いいねの数")
    }

    func testCountBadgeCap() {
        XCTAssertEqual(CountBadge.text(count: 120, maximum: 99), "99+")
        XCTAssertEqual(CountBadge.text(count: 99, maximum: 99), "99")
        XCTAssertEqual(CountBadge.text(count: 3, maximum: nil), "3")
        XCTAssertEqual(CountBadge.text(count: 120, maximum: nil), "120", "上限なしの呼び出し（地図のピン）が変わった")
    }

    /// 削除の確認: 何を消すかの写真を入れ、キャンセル｜削除 の2つ並び（削除は右・危険の色）
    func testDeleteConfirmShowsTheStory() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        let confirm = member("private func deleteConfirm(for story: Story)", in: viewer)
        assertInOrder(["StoryPoster(story: story)", "このストーリーを削除しますか？", "HStack(spacing: 0) {",
                       "confirmButton(Labels.Common.cancel", "confirmButton(L(\"削除\", \"Delete\"), color: Self.storyDanger"],
                      in: confirm, "削除の確認")
        XCTAssertTrue(confirm.contains(".frame(width: StoryViewerMetrics.confirmWidth)"))
    }

    /// 🔴 返信の一覧は札の地（surface-1）の別のファイル。閲覧画面（写真の上の字を持つ）に不透明の灰・札の地を戻さない
    func testRepliesSheetIsSeparate() throws {
        let sheet = try source("Features/Stories/StoryRepliesSheet.swift")
        XCTAssertTrue(sheet.contains(".background(WebTheme.card)"))
        XCTAssertTrue(sheet.contains("JPFont.cardTitle"), "見出しが明朝 22 でない")
        XCTAssertTrue(sheet.contains("UnevenRoundedRectangle(topLeadingRadius: 4"), "吹き出しの形でない")
        XCTAssertTrue(sheet.contains("ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }"))
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("StoryRepliesSheet(items: replies.textReplies, loaded: repliesLoaded"))
        for opaque in ["WebTheme.text2", "WebTheme.text3", "WebTheme.card"] {
            XCTAssertFalse(viewer.contains(opaque), "閲覧画面が \(opaque) を使っている")
        }
    }

    /// ハイライト: 表紙の丸の縁は白 50%、「編集」は鉛筆の印つき。**明朝は 18 未満に使わない**（板の 16 は使わない）
    func testHighlightHeader() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        let label = member("private func highlightLabel(", in: viewer)
        XCTAssertTrue(label.contains("StoryViewerMetrics.highlightCoverRing"))
        XCTAssertFalse(label.contains("JPFont.display("), "ハイライトの題に 18 未満の明朝を使っている")
        let footer = member("private func highlightFooter(", in: viewer)
        assertInOrder(["Image(systemName: \"pencil\")", "編集", "StoryViewerMetrics.highlightEditHeight",
                       ".frame(minHeight: WebTheme.minTapTarget)"], in: footer, "ハイライトの編集")
    }

    // MARK: - 反応の画面（v2 StoryInsights）

    func testInsightsTabsAndCounts() throws {
        let insights = try source("Features/Stories/StoryInsightsView.swift")
        XCTAssertTrue(insights.contains("selected ? WebTheme.accent : WebTheme.text3"), "選んだタブが真鍮でない")
        let tabs = member("private var tabs: some View", in: insights)
        assertInOrder(["Self.tabColor(selected: selected)", "selected ? WebTheme.accent : Color.clear",
                       "JPStroke.emphasis"], in: tabs, "下線のタブ")
        let cell = member("private func countCell(", in: insights)
        XCTAssertTrue(cell.contains(".font(JPFont.figureLarge)"), "数が細い大きい数字でない")
        XCTAssertTrue(cell.contains("?? \"—\""), "読めていない数を 0 と書いている")
        XCTAssertTrue(insights.contains(".background(WebTheme.card)"))
        XCTAssertEqual(StoryInsightsView.rowHeight, 60)
        XCTAssertGreaterThanOrEqual(StoryInsightsView.rowHeight, WebTheme.minTapTarget)
    }

    // MARK: - 親しい友達（v2 CloseFriends）

    /// 🔴 **選んだ人は真鍮の丸に墨の ★**（owner の好み「親しい友達の選んだ ★ は真鍮」）。色だけでなく形でも
    func testCloseFriendsPickMark() throws {
        XCTAssertEqual(CloseFriendsView.pickMarkSize, 28)
        let view = try source("Features/Social/CloseFriendsView.swift")
        let mark = member("private func pickMark(_ picked: Bool)", in: view)
        assertInOrder(["if picked {", "Circle().fill(WebTheme.accent)", "Image(systemName: \"star.fill\")",
                       ".foregroundStyle(WebTheme.accentText)", "} else {",
                       "Color.white.opacity(Self.unpickedRing)"], in: mark, "選んだ印")
        XCTAssertTrue(view.contains("JPEyebrowLine(L(\"選んだ人 \\(chosen.count)\""), "件数が眉ラベルでない")
        XCTAssertTrue(view.contains(".frame(minHeight: JPHeight.tallRow)"))
        XCTAssertTrue(view.contains(".background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))"))
        XCTAssertTrue(view.contains(".accessibilityAddTraits(picked ? .isSelected : [])"), "読み上げの「選択中」が消えた")
    }

    // MARK: - 投稿の2択（v2 PostSheet）

    func testPostSheetRows() throws {
        XCTAssertEqual(PostSheet.tileSize, 52)
        XCTAssertEqual(PostSheet.tileRadius, JPRadius.l)
        let sheet = try source("Features/Upload/PostSheet.swift")
        XCTAssertTrue(sheet.contains(".font(JPFont.screenTitle)"), "見出しが明朝 26 でない")
        XCTAssertTrue(sheet.contains(".font(JPFont.rowTitle)"), "行の題が明朝 18 でない")
        XCTAssertTrue(sheet.contains(".presentationBackground(WebTheme.sheet)"))
        // 画面写真の道しるべ（40 系）
        XCTAssertTrue(sheet.contains(".accessibilityIdentifier(\"post.choice.\\(Self.identifier(kind))\")"))
        for kind in ["photo", "story", "trip", "composition"] {
            XCTAssertTrue(sheet.contains("case .\(kind): return \"\(kind)\""))
        }
        // owner の決まり: 札に敷くのは自分の写真（v2 の板の印だけの札より優先）
        XCTAssertTrue(sheet.contains("PostSheetThumbs.pick(fromMine: mine, count: 4)"))
        // PRO は真鍮の縁と字（黒地の上）
        assertInOrder(["Text(badge)", ".foregroundStyle(WebTheme.accent)",
                       "Capsule().strokeBorder(WebTheme.accent.opacity(0.6)"], in: sheet, "PRO の合図")
    }

    // MARK: - 曲を選ぶ（v2 SongPicker）

    func testSongPickerRow() throws {
        XCTAssertEqual(SongPickerView.rowHeight, 68)
        XCTAssertEqual(SongPickerView.artworkSize, 48)
        XCTAssertGreaterThanOrEqual(SongPickerView.artworkSize, WebTheme.minTapTarget, "試し聴きの口が 44 より小さい")
        let picker = try source("Features/Upload/SongPickerView.swift")
        let row = member("private func row(_ song: Photo.Song)", in: picker)
        assertInOrder(["player.toggle(song.previewURL, song: song, origin: .songPicker)",
                       "playing ? \"stop.fill\" : \"play.fill\"",
                       "onSelect(song)",
                       "playing ? WebTheme.accentBackground : Color.clear",
                       ".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)"],
                      in: row, "曲の行")
        let bar = try source("Features/Common/MiniPlayerBar.swift")
        XCTAssertTrue(bar.contains("inSongPicker ? Self.pickerBarHeight : nil"), "曲選びの中の帯が v2 の形でない")
    }

    // MARK: - 投稿の画面（v2 Upload）

    func testUploadStrip() throws {
        XCTAssertEqual(UploadStripLayout.thumbWidth, 84)
        XCTAssertEqual(UploadStripLayout.thumbHeight, 104)
        XCTAssertEqual(UploadStripLayout.spacing, 8)
        XCTAssertGreaterThanOrEqual(UploadStripLayout.numberSize, 22)
        let upload = try source("Features/Upload/UploadView.swift")
        // 🔴 「写真を追加」は真鍮の点線と字（黒地の上・owner の好み）
        let add = member("private var addTile: some View", in: upload)
        assertInOrder([".foregroundStyle(WebTheme.accent)",
                       "WebTheme.accent.opacity(UploadStripLayout.addBorderOpacity)"], in: add, "「追加」の枠")
        XCTAssertTrue(add.contains("accessibilityIdentifier(\"upload.add\")"), "画面写真の道しるべが消えた")
        // 黒地の画面なので灰は v2 の不透明の灰（白の透過の灰は写真の上だけ）
        XCTAssertFalse(upload.contains("WebTheme.faint"))
        XCTAssertFalse(upload.contains("WebTheme.muted2"))
        // まとめ方のセグメント: 選んだ側は一段明るい面に白（白の塗りは主ボタンだけ）
        let segment = member("private func segment(", in: upload)
        XCTAssertTrue(segment.contains("selected ? Self.segmentSelectedFill : Color.clear"))
        XCTAssertFalse(segment.contains("WebTheme.accentBackground"))
        for id in ["upload.thumb.\\(index)", "upload.editButton", "upload.details", "upload.inspired"] {
            XCTAssertTrue(upload.contains("accessibilityIdentifier(\"\(id)\")"), "\(id) が消えた")
        }
    }

    // MARK: - 構図を重ねて撮る（v2 ComposeGuide）

    func testComposeGuideControls() throws {
        XCTAssertEqual(ComposeGuideView.shutterSize, 76)
        XCTAssertGreaterThanOrEqual(ComposeGuideView.segmentInner + 6, WebTheme.minTapTarget)
        let view = try source("Features/Spots/ComposeGuideView.swift")
        let post = member("private var postButton: some View", in: view)
        assertInOrder(["lastShotThumb", ".foregroundStyle(WebTheme.accent)", ".frame(minHeight: WebTheme.minTapTarget)",
                       "Capsule().strokeBorder(WebTheme.accent, lineWidth: 1.5)", "composeGuide.post"],
                      in: post, "撮った後の「投稿」")
        // シャッターを真ん中に保つ3つ割り
        let controls = member("private var controls: some View", in: view)
        assertInOrder([".frame(maxWidth: .infinity, alignment: .leading)", "shutter",
                       ".frame(maxWidth: .infinity, alignment: .trailing)"], in: controls, "下の3つ割り")
        for id in ["composeGuide.close", "composeGuide.shutter", "composeGuide.switch", "composeGuide.composition",
                   "composeGuide.counter", "composeGuide.thumb"] {
            XCTAssertTrue(view.contains("accessibilityIdentifier(\"\(id)\")"), "\(id) が消えた")
        }
    }

    /// 構図のシートは1行ずつの札。選んだ札は真鍮の縁 2＋チェック（owner の決定 2026-10-10）
    func testCompositionSheetRows() throws {
        XCTAssertEqual(CompositionPicker.rowHeight, 60)
        let picker = try source("Features/Spots/CompositionPicker.swift")
        let card = member("private func card(_ kind: CompositionKind?)", in: picker)
        assertInOrder(["Image(systemName: \"checkmark\")", "WebTheme.accent",
                       "isSelected ? WebTheme.accent : WebTheme.hairline",
                       "isSelected ? JPStroke.emphasis : JPStroke.hairline",
                       "accessibilityIdentifier(\"composition.card."], in: card, "構図の札")
        XCTAssertFalse(picker.contains("LazyVGrid"), "v1 の3列の格子が残っている")
        XCTAssertTrue(picker.contains("accessibilityIdentifier(\"composition.chip.\\(section.id)\")"))
    }

    // MARK: - ストーリーを作る（v2 StoryComposer・StoryComposerText）

    /// 🔴 ひとことは作る画面と見る画面で同じ 30（v1 は 32 と 30 でずれていた）
    func testComposerCaptionMatchesViewer() throws {
        XCTAssertEqual(StoryComposerView.captionSize, 30)
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertEqual(StoryViewerMetrics.captionSize, StoryComposerView.captionSize)
        XCTAssertTrue(viewer.contains("JPFont.display(highlight == nil ? StoryViewerMetrics.captionSize"))
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("JPFont.display(Self.captionSize, relativeTo: .largeTitle)"))
        XCTAssertFalse(composer.contains("JPFont.display(32"))
    }

    /// 主ボタンは写真のある画面の決まり（白・50）、並ぶ線のボタンも 50（跳ねない）
    func testComposerButtons() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertEqual(composer.components(separatedBy: ".jpPillButton(.main(onPhoto: true))").count - 1, 2,
                       "「次へ」「シェアする」が主ボタンの決まりを通っていない")
        XCTAssertTrue(composer.contains(".jpPillButton(.outline, height: JPHeight.primaryButton)"))
        XCTAssertFalse(composer.contains("minHeight: 52"), "v1 の 52 が残っている")
        XCTAssertEqual(StoryComposerView.chipHeight, 30)
    }

    /// 「誰に見せる？」は共通の札と入切の行（写しを作らない）。主ボタンは写真の無い画面の真鍮
    func testAudienceSheetUsesSharedParts() throws {
        let sheet = try source("Features/Stories/StoryAudienceSheet.swift")
        assertInOrder(["JPCard {", "JPToggleRow(title: L(\"返信を受け取る\"", "JPCardDivider()",
                       "JPToggleRow(title: L(\"24時間後も自分用に残す\""], in: sheet, "入切の札")
        XCTAssertTrue(sheet.contains(".jpPillButton(.main(onPhoto: false))"))
        XCTAssertFalse(sheet.contains("private func toggleRow("), "入切の行の写しが残っている")
    }

    func testTextTypingSwatches() throws {
        XCTAssertEqual(StoryTextTypingView.swatchSize, 30)
        XCTAssertEqual(StoryTextTypingView.chipHeight, 32)
        let typing = try source("Features/Stories/StoryTextTypingView.swift")
        XCTAssertTrue(typing.contains(".background(Color.white.opacity(Self.chipFill), in: Capsule())"))
        // 消すは危険の色（系統の赤にしない）
        XCTAssertTrue(typing.contains(".foregroundStyle(WebTheme.danger)"))
        XCTAssertFalse(typing.contains("Color.red"))
    }

    /// 板 v2 `StoryComposerText` の上の段: 「キャンセル／文字と札／完了」（17pt・白）。揃えはキャンセルの右に残す
    func testTextTypingTopBar() throws {
        let typing = try source("Features/Stories/StoryTextTypingView.swift")
        let bar = member("private var topBar: some View", in: typing)
        assertInOrder(["L(\"文字と札\", \"Text & stickers\")",
                       "barButton(L(\"キャンセル\", \"Cancel\"), weight: .regular, action: onCancel)",
                       "StoryTextEditing.nextAlign(overlay)",
                       "barButton(L(\"完了\", \"Done\"), weight: .bold, action: onDone)"], in: bar, "上の段")
        XCTAssertEqual(StoryTextTypingView.barFontSize, 17)
        // 写真の上の白い帯のボタン（v1 の「完了」）は残さない
        XCTAssertFalse(bar.contains("accentBackground"), "完了が白い帯のまま")
        // 呼ぶ側がキャンセルを通す（打つ前に戻す）
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("onCancel: { cancelTyping() }"))
        let cancel = member("private func cancelTyping()", in: composer)
        assertInOrder(["StoryTextEditing.cancel(shots[i].overlays, id: id, original: typingOriginal)",
                       "finishTyping(showsHint: false)"], in: cancel, "キャンセル")
        // 新しく足した札は打つ前が無い（nil）＝キャンセルで消える
        XCTAssertEqual(composer.components(separatedBy: "startTyping(overlay.id, isNew: true)").count - 1, 2,
                       "「Aa」とトレイの札が新しい札として打ち始めていない")
        XCTAssertTrue(composer.contains("typingOriginal = isNew ? nil : overlays.wrappedValue.first { $0.id == id }"))
    }

    /// 大きさのつまみは右に、上に「大」・下に「小」（12pt）
    func testTextTypingSizeSliderOnTheRight() throws {
        let typing = try source("Features/Stories/StoryTextTypingView.swift")
        assertInOrder(["sizeSlider", ".frame(maxWidth: .infinity, alignment: .trailing)"], in: typing, "右のつまみ")
        XCTAssertFalse(typing.contains("sizeSlider\n                        .frame(maxWidth: .infinity, alignment: .leading)"))
        let slider = member("private var sizeSlider: some View", in: typing)
        assertInOrder(["sizeMark(L(\"大\", \"L\"))", "Slider(", ".rotationEffect(.degrees(-90))",
                       "sizeMark(L(\"小\", \"S\"))"], in: slider, "大・つまみ・小")
        XCTAssertTrue(member("private func sizeMark(", in: typing).contains(".font(.system(size: 12"))
        XCTAssertEqual(StoryTextTypingView.sliderLength, 200)
    }

    /// 置いた直後の案内: 置いたときだけ・端末に1回（印を付けてから出す）・押せば消える・12pt 以上
    func testPlaceHintInComposer() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        let finish = member("private func finishTyping(", in: composer)
        assertInOrder(["let placed = shots[i].overlays.contains { $0.id == id }",
                       "if showsHint, StoryTextEditing.shouldShowPlaceHint(placed: placed) {",
                       "StoryTextEditing.markPlaceHintShown()", "showPlaceHint = true"], in: finish, "案内")
        let hint = member("private var placeHint: some View", in: composer)
        assertInOrder(["Button { showPlaceHint = false }", "Text(StoryTextEditing.placeHint)",
                       ".font(.footnote"], in: hint, "案内の札")
        XCTAssertTrue(composer.contains("if showPlaceHint && typingId == nil && !draggingOverlay {"))
    }

    // MARK: - 共通

    /// 一段浮かせた面（#1A1A1C）は1つの値（画面ごとに書かない）
    func testRaisedTileIsShared() throws {
        XCTAssertEqual(RaisedTile.hex, 0x1A1A1C)
        for path in ["Features/Upload/PostSheet.swift", "Features/Common/MiniPlayerBar.swift",
                     "Features/Stories/StoryRepliesSheet.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("RaisedTile.fill"), "\(path) が共通の面を使っていない")
            XCTAssertFalse(text.contains("0x1A / 255.0, green: 0x1A / 255.0, blue: 0x1C"), "\(path) に同じ色の写しがある")
        }
    }

    /// 触った画面に系統の赤を置かない（危険の色は `WebTheme.danger`）
    func testNoSystemRed() throws {
        for path in ["Features/Stories/StoriesRow.swift", "Features/Stories/StoryViewerView.swift",
                     "Features/Stories/StoryRepliesSheet.swift", "Features/Stories/StoryInsightsView.swift",
                     "Features/Stories/StoryComposerView.swift", "Features/Upload/PostSheet.swift",
                     "Features/Upload/UploadView.swift", "Features/Upload/SongPickerView.swift",
                     "Features/Spots/ComposeGuideView.swift", "Features/Spots/CompositionPicker.swift",
                     "Features/Social/CloseFriendsView.swift"] {
            let text = try source(path)
            XCTAssertFalse(text.contains("Color.red") || text.contains(".foregroundStyle(.red)"), "\(path) に系統の赤")
        }
    }
}
