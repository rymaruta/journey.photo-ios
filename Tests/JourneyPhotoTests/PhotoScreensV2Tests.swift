import XCTest
@testable import JourneyPhoto

/// v2 の第3段（写真の詳細・全画面・写真の編集・通報。Artifact「v2」の PhotoDetail・PhotoViewer・EditPhoto・Report・
/// 2026-10-14）の見た目の決まりを見張る。
///
/// - **写真の上は白と白の透過だけ**（`muted2`・`faint`）。不透明の灰（`text2`・`text3`）と真鍮は置かない
/// - **真鍮は黒地の上だけ**（行き先の段の印・撮影日の暦・通報の選んだ丸・保存の字）
/// - **押せるものは 44pt 以上**
///
/// 画面は Linux では描けないので、値は数で、作りは元のファイルを読んで見張る（`DesignFoundationTests` と同じ）。
/// 切り出しは宣言の範囲に絞る——ほかの部品の同じ字に当たらないように
final class PhotoScreensV2Tests: XCTestCase {

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

    /// `marker` の行から、同じ深さ（4 字下げ）の次の宣言・注記までを切り出す
    private func member(_ marker: String, in text: String,
                        file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = text.range(of: marker) else {
            XCTFail("「\(marker)」が無い", file: file, line: line)
            return ""
        }
        let rest = text[start.upperBound...]
        let ends = ["\n    private ", "\n    ///", "\n    @ViewBuilder", "\n    static ", "\n    nonisolated ",
                    "\n    var ", "\n    func ", "\n}\n"]
            .compactMap { rest.range(of: $0)?.lowerBound }
        return String(rest[..<(ends.min() ?? rest.endIndex)])
    }

    /// 写真の上に置いてはいけない色（不透明の灰・真鍮）
    private func assertWhiteOnly(_ part: String, _ what: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(part.isEmpty, "\(what) が切り出せない", file: file, line: line)
        for banned in ["WebTheme.text2", "WebTheme.text3", "WebTheme.accent)", "WebTheme.accent,",
                       "WebTheme.accent ", "WebTheme.accentFill", "WebTheme.accentStrong"] {
            XCTAssertFalse(part.contains(banned), "\(what) が写真の上に \(banned) を置いている", file: file, line: line)
        }
    }

    // MARK: - 写真の詳細

    /// 写真の裾（撮影地・撮影スポットの行・ページの点）は白だけ。字は影つき
    func testPhotoFootIsWhiteOnly() throws {
        let view = try source("Features/PhotoDetail/PhotoDetailView.swift")
        for name in ["private var photoFoot", "private var pageDots", "private var placeRow",
                     "private var spotGuideRow", "private func placeLabel"] {
            assertWhiteOnly(member(name, in: view), name)
        }
        let place = member("private func placeLabel", in: view)
        XCTAssertTrue(place.contains(".foregroundStyle(WebTheme.foreground)"))
        XCTAssertTrue(place.contains(".foregroundStyle(WebTheme.muted2)"), "添え書きの灰が写真の上の透過でない")
        XCTAssertTrue(place.contains(".jpPhotoTextShadow()"))
        XCTAssertTrue(member("private var spotGuideRow", in: view).contains(".jpPhotoTextShadow()"))
        // 点は白と白 40%
        XCTAssertTrue(member("private var pageDots", in: view)
            .contains("Color.white.opacity(index == page ? 1 : Self.inactiveDotOpacity)"))
        XCTAssertEqual(PhotoDetailView.inactiveDotOpacity, 0.4)
        // 写真の裾は黒 72% まで（題を重ねないので黒まで溶かさない）・写真は 520
        XCTAssertEqual(PhotoDetailView.heroHeight, 520)
        XCTAssertEqual(PhotoDetailView.heroFootShade.height, 150)
        XCTAssertEqual(PhotoDetailView.heroFootShade.opacity, 0.72)
        // 撮影地・撮影スポットの行は写真の裾に（題のかたまりには無い）
        let image = member("private var imageButton", in: view)
        XCTAssertTrue(image.contains("photoFoot"), "撮影地の行が写真の裾に無い")
        let heading = member("private var heading", in: view)
        XCTAssertFalse(heading.contains("placeRow"), "撮影地の行が題のかたまりに残っている")
    }

    /// 題・日時は写真の下の黒地: 題は明朝 26（Title 1）、日時は不透明の text-3。影は付けない
    func testHeadingSitsOnBlack() throws {
        let view = try source("Features/PhotoDetail/PhotoDetailView.swift")
        let heading = member("private var heading", in: view)
        XCTAssertTrue(heading.contains(".font(JPFont.screenTitle)"))
        XCTAssertTrue(heading.contains(".foregroundStyle(WebTheme.text3)"))
        XCTAssertFalse(heading.contains("jpPhotoTextShadow"), "黒地の題に写真の上の影が残っている")
        XCTAssertFalse(heading.contains("WebTheme.faint"), "黒地の日時が写真の上の透過の灰のまま")
        // 題を写真に重ねる負の余白は無い（v2 は写真の下）
        XCTAssertFalse(view.contains("heroOverlap"))
        XCTAssertTrue(view.contains("details(proxy)\n                                .padding(.top, JPSpace.l)"))
        // 説明は本文 15 の text-2
        let paragraphs = member("private var paragraphs", in: view)
        XCTAssertTrue(paragraphs.contains(".font(JPFont.body)"))
        XCTAssertTrue(paragraphs.contains(".foregroundStyle(WebTheme.text2)"))
    }

    /// いいね・コメント・保存・共有は白の細い線。**ハートは白のまま**（owner の決まり）。当たりは 44
    func testSocialBarStaysWhiteAndTappable() throws {
        let view = try source("Features/PhotoDetail/PhotoDetailView.swift")
        let label = member("private func actionLabel", in: view)
        XCTAssertTrue(label.contains(".foregroundStyle(Color.white)"))
        XCTAssertTrue(label.contains(".webTappable()"), "操作の当たりが 44pt でない")
        XCTAssertTrue(label.contains(".font(.title2.weight(.light))"))
        let bar = member("private func socialBar", in: view)
        XCTAssertFalse(bar.contains("WebTheme.accent"), "いいね・保存の段に真鍮がある（ハートは白・CLAUDE.md）")
        // 左に いいね・コメント、右に 保存・共有（間に1つだけ伸びる空き）
        XCTAssertEqual(bar.components(separatedBy: "Spacer(minLength: 0)").count - 1, 1)
        XCTAssertTrue(bar.contains(".fill(WebTheme.hairline)"), "段の下の区切り線が無い")
    }

    /// コメントの送信は白い丸に墨（写真の上を流れる帯なので真鍮を置かない）。44pt
    func testCommentSendIsWhiteCircle() throws {
        let view = try source("Features/PhotoDetail/PhotoDetailView.swift")
        let composer = member("private var composer", in: view)
        XCTAssertTrue(composer.contains(".background(WebTheme.accentBackground, in: Circle())"))
        XCTAssertTrue(composer.contains(".foregroundStyle(WebTheme.accentText)"))
        XCTAssertTrue(composer.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"))
        assertWhiteOnly(composer, "コメントの欄")
        XCTAssertTrue(composer.contains(".disabled(!canSend)"))
    }

    /// 写真の下の黒地の部品は不透明の灰（作者の @・撮影情報・コメント）。数字は等幅
    func testBelowPhotoUsesOpaqueGrays() throws {
        let view = try source("Features/PhotoDetail/PhotoDetailView.swift")
        let author = member("private var authorRow", in: view)
        XCTAssertTrue(author.contains(".foregroundStyle(WebTheme.text3)"))
        XCTAssertTrue(author.contains("NameMarks(profile: model.owner, nameSize: JPTypeScale.body, relativeTo: .subheadline)"),
                      "名前の横の印が名前の字（15）に合っていない")
        XCTAssertTrue(author.contains(".frame(minHeight: WebTheme.minTapTarget)"))
        XCTAssertEqual(PhotoDetailView.authorAvatarSize, 40)
        let exif = try XCTUnwrap(view.components(separatedBy: "private struct ExifRow: View {").dropFirst().first?
            .components(separatedBy: "struct FlowLayout").first)
        XCTAssertTrue(exif.contains("PhotoMetaLine.settingsLine(exif)"), "閉じた撮影情報に要約が無い")
        XCTAssertTrue(exif.contains("PhotoMetaLine.settingsCells(exif)"))
        XCTAssertTrue(exif.contains(".frame(minHeight: WebTheme.minTapTarget)"), "開け閉めの当たりが 44pt でない")
        XCTAssertTrue(exif.contains(".frame(minHeight: JPHeight.field)"), "機材の行が 48 でない")
        XCTAssertFalse(exif.contains("WebTheme.faint"))
        XCTAssertFalse(exif.contains("Color.white.opacity(0.5)"))
        XCTAssertFalse(exif.contains("WebTheme.accent"), "撮影情報に真鍮（合図ではない）")
        let comments = member("private var commentSection", in: view)
        XCTAssertTrue(comments.contains("CommentsHeading.age(comment.t, now: Date())"))
        XCTAssertTrue(comments.contains(".foregroundStyle(WebTheme.text2)"))
        XCTAssertEqual(PhotoDetailView.commentAvatarSize, 32)
        XCTAssertEqual(PhotoDetailView.nearbyColumns, 4)
    }

    /// 行き先の段: 眉ラベル（真鍮・黒地）と、幅を分け合う 48 の札。印は真鍮、字は白
    func testTripSectionBrassOnBlackAndTall() throws {
        let section = try source("Features/PhotoDetail/PhotoTripSection.swift")
        XCTAssertTrue(section.contains("JPEyebrowLine(L(\"NEXT TRIP · 次の旅へ\""))
        XCTAssertTrue(section.contains(".foregroundStyle(WebTheme.accent)"))
        XCTAssertTrue(section.contains("selected ? WebTheme.accent : WebTheme.line"), "選んだ状態を縁で伝えていない")
        XCTAssertTrue(section.contains(".frame(maxWidth: .infinity, minHeight: Self.goHeight)"))
        XCTAssertFalse(section.contains("WebTheme.muted2"), "黒地の「いつ」が写真の上の灰のまま")
        XCTAssertGreaterThanOrEqual(PhotoTripSection.goHeight, WebTheme.minTapTarget)
        XCTAssertEqual(PhotoTripSection.goHeight, 48)
        XCTAssertEqual(PhotoTripSection.goRadius, 14)
    }

    // MARK: - 全画面

    /// 全画面は全部が写真の上: 白と白の透過だけ。閉じる・共有はガラスの丸 44、ハートは白で 44
    func testViewerIsWhiteOnlyOnPhoto() throws {
        let viewer = try source("Features/PhotoDetail/PhotoViewerView.swift")
        assertWhiteOnly(viewer, "全画面")
        let top = member("private var topBar", in: viewer)
        XCTAssertEqual(top.components(separatedBy: ".jpGlass(in: Circle())").count - 1, 2, "閉じる・共有がガラスの丸でない")
        XCTAssertEqual(top.components(separatedBy: ".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)").count - 1, 3)
        XCTAssertTrue(top.contains("PhotoMetaLine.viewerPositionSpoken(index, of: photos.count)"), "「1 / 3」の読み上げが数字だけ")
        let caption = member("private var caption", in: viewer)
        XCTAssertTrue(caption.contains("PhotoMetaLine.gearLine(photo.exif)"))
        XCTAssertTrue(caption.contains("PhotoMetaLine.settingsLine(photo.exif)"))
        XCTAssertTrue(caption.contains(".foregroundStyle(WebTheme.muted2)"))
        XCTAssertTrue(caption.contains("heart.fill"))
        XCTAssertTrue(caption.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"))
        XCTAssertEqual(PhotoViewerView.heartSize, 26)
    }

    // MARK: - 通報

    /// 理由は左の丸・選ぶと真鍮の太い輪・行は 48。主ボタンは写真の無い画面の決まり（真鍮の塗り）
    func testReportReasonsAndButton() throws {
        let sheet = try source("Features/Social/ReportSheet.swift")
        let row = try XCTUnwrap(sheet.components(separatedBy: "private struct ReportReasonRow: View {").dropFirst().first)
        XCTAssertTrue(row.contains("selected ? WebTheme.accent : Color.white.opacity(0.35)"))
        XCTAssertTrue(row.contains("lineWidth: selected ? Self.selectedRingWidth : 1.5"), "選んだことを太さ（形）でも伝えていない")
        XCTAssertTrue(row.contains("static let height: CGFloat = JPHeight.field"))
        XCTAssertTrue(row.contains(".frame(minHeight: Self.height)"))
        XCTAssertTrue(row.contains(".accessibilityAddTraits(selected ? .isSelected : [])"))
        XCTAssertGreaterThanOrEqual(JPHeight.field, WebTheme.minTapTarget)
        XCTAssertFalse(sheet.contains("JPRadioRow("), "通報の理由が共通の右の白い丸のまま")
        XCTAssertTrue(sheet.contains(".jpPillButton(JPPillStyle.main(onPhoto: false))"))
        // 閉じるはガラスの丸 44
        let header = member("private var header", in: sheet)
        XCTAssertTrue(header.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"))
        // 通報する写真の札は写真の詳細から渡す
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("ReportSheet(photoId: current.id, ownerId: ownerId, subject: reportSubject)"))
        XCTAssertEqual(ReportSheet.subjectThumb, 44)
    }

    // MARK: - 写真を編集

    /// 写真の段は白の線のボタン2つ（44）。保存は真鍮の字（黒地のナビ）、閉じるは text-2、撮影日は真鍮の暦
    func testEditPhotoButtons() throws {
        let edit = try source("Features/Profile/EditPhotoView.swift")
        let header = member("private var photoHeader", in: edit)
        XCTAssertEqual(header.components(separatedBy: ".jpPillButton(.outline)").count - 1, 2)
        XCTAssertTrue(header.contains(".accessibilityIdentifier(\"editPhoto.recolor\")"))
        XCTAssertFalse(header.contains("WebTheme.accent"), "写真のある画面の欄に真鍮のボタン")
        XCTAssertEqual(JPPillStyle.outline.height, WebTheme.minTapTarget)
        XCTAssertEqual(EditPhotoView.thumbSize, CGSize(width: 112, height: 140))
        let save = member("private var saveButton", in: edit)
        XCTAssertTrue(save.contains("isBusy ? WebTheme.faint : WebTheme.accent"))
        XCTAssertTrue(save.contains(".accessibilityIdentifier(\"editPhoto.save\")"))
        XCTAssertTrue(edit.contains("Text(Labels.Common.close)\n                        .font(.body)\n                        .foregroundStyle(WebTheme.text2)"))
        let date = member("private var dateField", in: edit)
        XCTAssertTrue(date.contains("Image(systemName: \"calendar\")"))
        XCTAssertTrue(date.contains(".foregroundStyle(WebTheme.accent)"))
        XCTAssertTrue(date.contains(".webTappable()"), "撮影日を消す × が 44pt でない")
        XCTAssertTrue(edit.contains("JPToggleRow(title: L(\"公開する\", \"Public\")"), "公開のトグルの軌道が真鍮の行でない")
    }

    // MARK: - コメントの時刻

    func testCommentAge() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func iso(_ ago: TimeInterval) -> String {
            let f = ISO8601DateFormatter()
            return f.string(from: now.addingTimeInterval(-ago))
        }
        XCTAssertEqual(CommentsHeading.age(iso(10), now: now), L("たった今", "Just now"))
        XCTAssertEqual(CommentsHeading.age(iso(5 * 60), now: now), L("5分前", "5m ago"))
        XCTAssertEqual(CommentsHeading.age(iso(2 * 3600), now: now), L("2時間前", "2h ago"))
        XCTAssertEqual(CommentsHeading.age(iso(30 * 3600), now: now), L("昨日", "Yesterday"))
        XCTAssertEqual(CommentsHeading.age(iso(3 * 86_400), now: now), L("3日前", "3d ago"))
        XCTAssertEqual(CommentsHeading.age(iso(30 * 86_400), now: now)?.count, 10)  // 2026.xx.xx
        XCTAssertEqual(CommentsHeading.age("2026-01-02T03:04:05.678Z", now: now)?.count, 10)
        // 読めない・未来の時刻は出さない
        XCTAssertNil(CommentsHeading.age(nil, now: now))
        XCTAssertNil(CommentsHeading.age("きのう", now: now))
        XCTAssertNil(CommentsHeading.age(iso(-3600), now: now))
    }
}
