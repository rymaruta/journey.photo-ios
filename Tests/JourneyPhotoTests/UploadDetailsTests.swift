import XCTest
@testable import JourneyPhoto

/// 投稿画面を軽くする（2026-10-03・計画9）。「詳しい設定」に畳む・撮影地を先に・
/// 作例の一言・写真を選ぶ画面を自動で開く（`UploadDetails`）。
final class UploadDetailsTests: XCTestCase {

    // MARK: - 「詳しい設定」の行の値

    /// **公開範囲は既定でも出す。** 畳んだまま、誰に見えるか分からずに投稿させない
    func testSummaryAlwaysStartsWithTheAudience() {
        let everyone = UploadDetails.summary(published: true, audience: .everyone, songTitle: nil,
                                             albumTitle: nil, category: "")
        XCTAssertEqual(everyone, Audience.everyone.label)
        let close = UploadDetails.summary(published: true, audience: .closeFriends, songTitle: nil,
                                          albumTitle: nil, category: "")
        XCTAssertEqual(close, Audience.closeFriends.label)
    }

    /// 旅の写真から来た回は非公開で始まる。畳んでいても「非公開」と読める
    func testSummarySaysPrivateWhenUnpublished() {
        let s = UploadDetails.summary(published: false, audience: .everyone, songTitle: nil,
                                      albumTitle: nil, category: "")
        XCTAssertEqual(s, L("非公開", "Private"))
        XCTAssertFalse(s.contains(Audience.everyone.label), "非公開なのに全体に公開と読めた")
    }

    /// 付けたものだけ足す（既定の「無し」は並べない）
    func testSummaryListsOnlyWhatWasAdded() {
        let s = UploadDetails.summary(published: true, audience: .everyone, songTitle: "海の声",
                                      albumTitle: "夏の旅", category: "風景")
        XCTAssertTrue(s.hasPrefix(Audience.everyone.label))
        XCTAssertTrue(s.contains(L("曲", "Song")))
        XCTAssertTrue(s.contains(L("アルバム", "Album")))
        XCTAssertTrue(s.contains("風景"))
    }

    /// 1.1.83（資料「SNS をもっと SNS に」①）: 「SNS にも載せる」の行は無くした。まとめにも出さない
    /// （投稿のあとに毎回共有カードが出る・`PostedShareCard`）
    func testSummaryNoLongerMentionsSocial() {
        let s = UploadDetails.summary(published: true, audience: .everyone, songTitle: "海の声",
                                      albumTitle: "夏の旅", category: "風景")
        XCTAssertFalse(s.contains(L("SNS にも載せる", "Share to social")))
    }

    // MARK: - 作例の一言

    /// 撮影地のページ（`DerivedSpot`・Web の `/location/*`）に並ぶのは公開・全体に公開の写真だけ。
    /// **並ばないときに「並ぶ」と言わない**
    func testSampleNoteOnlyWhenThePhotoReallyJoinsThePlacePage() {
        XCTAssertTrue(UploadDetails.showsSampleNote(location: "高屋神社", published: true, audience: .everyone))
        XCTAssertFalse(UploadDetails.showsSampleNote(location: "", published: true, audience: .everyone),
                       "撮影地が空なら並ばない")
        XCTAssertFalse(UploadDetails.showsSampleNote(location: "  \n", published: true, audience: .everyone),
                       "空白だけは空として送られる")
        XCTAssertFalse(UploadDetails.showsSampleNote(location: "高屋神社", published: false, audience: .everyone),
                       "非公開は並ばない")
        XCTAssertFalse(UploadDetails.showsSampleNote(location: "高屋神社", published: true, audience: .followers),
                       "絞った写真は公開一覧に載らない")
        XCTAssertFalse(UploadDetails.showsSampleNote(location: "高屋神社", published: true, audience: .closeFriends))
    }

    /// 撮影地のページは2枚から開く。一言の「2枚から」はその線と同じ数
    func testSampleNoteMatchesThePlacePageThreshold() {
        XCTAssertEqual(DerivedSpot.minPhotosForSpotPage, 2, "線が変わったら一言の「2枚から」も直す")
        XCTAssertTrue(UploadDetails.sampleNote.contains("2"))
    }

    // MARK: - 写真の一覧の段（2026-11-18 案 B1。前は 0.9 秒待って OS の写真選びを自動で開いた）

    func testLibraryStageShowsOnlyWhenEmptyAndSettled() {
        XCTAssertTrue(UploadDetails.showsLibraryStage(hasPhotos: false, restoring: false, preparingCaptures: 0,
                                                      isWorking: false, awaitingInitial: false))
        XCTAssertFalse(UploadDetails.showsLibraryStage(hasPhotos: true, restoring: false, preparingCaptures: 0,
                                                       isWorking: false, awaitingInitial: false),
                       "写真を選んだのに一覧のまま")
        XCTAssertFalse(UploadDetails.showsLibraryStage(hasPhotos: false, restoring: true, preparingCaptures: 0,
                                                       isWorking: false, awaitingInitial: false),
                       "下書きを戻している途中に一覧が一瞬出る")
        XCTAssertFalse(UploadDetails.showsLibraryStage(hasPhotos: false, restoring: false, preparingCaptures: 1,
                                                       isWorking: false, awaitingInitial: false),
                       "撮った1枚を整えている途中に一覧に戻る")
        XCTAssertFalse(UploadDetails.showsLibraryStage(hasPhotos: false, restoring: false, preparingCaptures: 0,
                                                       isWorking: true, awaitingInitial: false))
        XCTAssertFalse(UploadDetails.showsLibraryStage(hasPhotos: false, restoring: false, preparingCaptures: 0,
                                                       isWorking: false, awaitingInitial: true),
                       "旅の写真・撮った1枚を入れる前に一覧が出る")
    }

    // MARK: - 画面の配線（Linux では描けないので文で確かめる）

    private func uploadViewSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Upload/UploadView.swift"), encoding: .utf8)
    }

    /// 曲・公開範囲などの行は「詳しい設定」を開いたときだけ。開け閉めの行はいつも出す
    func testSettingsRowsAreFoldedBehindMoreSettings() throws {
        let source = try uploadViewSource()
        let start = try XCTUnwrap(source.range(of: "private var rowsCard: some View {"))
        let body = String(source[start.upperBound...].prefix(600))
        XCTAssertTrue(body.contains("detailsToggle"), "開け閉めの行が無い")
        XCTAssertTrue(body.contains("if showsDetails {\n                    JPCardDivider()\n                    detailRows"),
                      "設定の行が畳まれていない")
        XCTAssertTrue(source.contains("@State private var showsDetails = false"), "畳んで始める")
        // 公開範囲・親しい友達・曲・カテゴリは中身に残る（機能は消さない）。SNS の行は 1.1.83 で無くした（投稿のあとにカード）
        let rowsStart = try XCTUnwrap(source.range(of: "private var detailRows: some View {"))
        let rows = String(source[rowsStart.upperBound...].prefix(3000))
        for part in ["songRow", "albumRow", "audienceRow", "CloseFriendsView()", "CategoryField("] {
            XCTAssertTrue(rows.contains(part), "\(part) が詳しい設定から消えた")
        }
    }

    /// 撮影地は題・説明より先（いちばん多い道は 写真 → 撮影地 → 投稿）
    func testPlaceComesBeforeTitle() throws {
        let source = try uploadViewSource()
        let start = try XCTUnwrap(source.range(of: "private var detailSection: some View {"))
        let body = source[start.upperBound...]
        let place = try XCTUnwrap(body.range(of: "PlaceSearchField("))
        let title = try XCTUnwrap(body.range(of: "JPField(L(\"題\""))
        XCTAssertLessThan(place.lowerBound, title.lowerBound, "撮影地が題より後ろにある")
        XCTAssertTrue(body.prefix(2500).contains("UploadDetails.showsSampleNote("), "作例の一言が撮影地の下に無い")
    }

    /// 開いたら写真の一覧の段（決まりを通す）。**0.9 秒待って OS の写真選びを開く道は無い**（押す回数が1回減る）
    func testFormStartsWithTheLibraryStage() throws {
        let source = try uploadViewSource()
        XCTAssertTrue(source.contains("UploadDetails.showsLibraryStage("), "一覧の段の決まりを通していない")
        XCTAssertTrue(source.contains("} else if libraryStage {\n                libraryStageView\n            } else {\n                form"),
                      "写真が無い間に欄が出る")
        XCTAssertFalse(source.contains("autoOpenDelay"), "開いてから待って OS の写真選びを開く道が残っている")
        XCTAssertFalse(source.contains("offeredLibrary"), "自動で開いた印が残っている")
        // 「アルバム」「追加」は OS の写真選び（立て直しを通す）
        XCTAssertTrue(source.contains("Button { openLibrary() }"), "「ライブラリから選ぶ」が立て直しを通っていない")
        XCTAssertTrue(source.contains("onAlbums: libraryGridShown ? { openLibrary() } : nil,"))
        // 開いたときの支度（問い・最初から入れる写真）は一覧の段でも走る（画面の外側の onAppear）
        let outer = try XCTUnwrap(source.range(of: ".onChange(of: libraryShownForFlow)"))
        let setup = try XCTUnwrap(source.range(of: "model.applyInitialPhotos(initialPhotos, startPrivate: startPrivate)"))
        let form = try XCTUnwrap(source.range(of: "    private var form: some View {"))
        XCTAssertLessThan(outer.lowerBound, setup.lowerBound)
        XCTAssertLessThan(setup.lowerBound, form.lowerBound, "開いたときの支度が欄にだけ付いている（一覧の段で問いが出ない）")
    }

    /// 🔴 立ったままの印は一度下ろしてから立てる（true に true では開かない）
    func testLibraryReopensWhenTheFlagIsStuck() {
        XCTAssertEqual(UploadDetails.libraryOpenSteps(isPresented: false), [true])
        XCTAssertEqual(UploadDetails.libraryOpenSteps(isPresented: true), [false, true])
    }

    /// 🔴 **公開範囲の説明は畳んでいても出す**（レビュー 2026-10-03）。「ウェブサイトにも載り、検索から…」が
    /// 見えないまま、意図せず公開させない
    func testAudienceNoteShowsEvenWhenFolded() throws {
        let source = try uploadViewSource()
        let start = try XCTUnwrap(source.range(of: "private var rowsCard: some View {"))
        let end = try XCTUnwrap(source.range(of: "private var detailRows: some View {"))
        let body = String(source[start.upperBound..<end.lowerBound])
        let note = try XCTUnwrap(body.range(of: "? model.audience.photoNote"))
        // 説明の直前の数行に `if showsDetails` が無い（畳んでいる間に消えない）
        let before = body[body.startIndex..<note.lowerBound].suffix(260)
        XCTAssertFalse(before.contains("if showsDetails"), "公開範囲の説明が畳んだときに消える")
        XCTAssertTrue(Audience.everyone.photoNote.contains(L("ウェブサイト", "website")))
    }

    // MARK: - 選んだ写真の帯の外す丸

    /// 🔴 **外す丸の押せる範囲が、隣の写真に重ならない。** 板どおり 14 はみ出させると、帯の間（10）を
    /// 越えて隣の写真に 4 重なっていた。見た目（丸の位置・大きさ）は板のまま、押せる範囲は 44 のまま
    func testRemoveButtonHitAreaStaysOutOfTheNextPhoto() {
        XCTAssertLessThanOrEqual(UploadStripLayout.hitOverhangRight, UploadStripLayout.spacing,
                                 "外す丸の押せる範囲が隣の写真に重なっている")
        XCTAssertGreaterThanOrEqual(UploadStripLayout.removeHit, 44)
        // 見た目は板のまま: 丸は写真の右の端から 6 はみ出す（right -14・44 の枠の真ん中に 28）
        XCTAssertEqual(UploadStripLayout.dotOverhangRight, 6)
        XCTAssertEqual(UploadStripLayout.removeDot, 28)
        XCTAssertEqual(UploadStripLayout.removeOffset, 14)
        XCTAssertTrue(UploadStripLayout.dotInsideHit, "ずらした丸が押せる範囲からはみ出している")
    }
}
