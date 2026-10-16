import XCTest
@testable import JourneyPhoto

/// すれちがいの画面のつなぎ（読み直し 2026-10-16 の直し）。画面は Linux で動かせないので、書き方を見張る
final class PassWiringTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// 🔴 札が空の間は子が無く `.task` が走らない・時計で 18 時を待つとロック中に越えて古いまま →
    /// 札は中身だけ。写真を引くのも「いま」を入れ直すのもホーム（`LazyVStack` の外）
    func testHomeSlotIsContentOnlyAndGalleryRefreshesNow() throws {
        let slot = try source("Features/Pass/PassHomeSlot.swift")
        XCTAssertFalse(slot.contains(".task"), "札に .task が残っている")
        XCTAssertFalse(slot.contains("Task.sleep"), "時計で 18 時を待っている")
        XCTAssertFalse(slot.contains("@State"), "札が自分で「いま」を持っている")
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertTrue(gallery.contains("await pass.resolve(gallery: environment.gallery, profiles: environment.profiles, now: now)"))
        XCTAssertTrue(gallery.contains("if phase == .active { passNow = Date() }"), "前面に来ても「いま」を入れ直さない")
        XCTAssertTrue(gallery.contains(".onChange(of: pass.openRequests) { _, _ in\n            passNow = Date()"),
                      "知らせを押しても「いま」を入れ直さない")
    }

    /// カードの「…」（通報・ブロック・帳から外す）が束の画面と帳の両方にある（審査 1.2）
    func testCardsHaveReportBlockAndRemove() throws {
        let menu = try source("Features/Pass/PassCardMenu.swift")
        for word in ["通報する", "この人をブロック", "帳から外す"] { XCTAssertTrue(menu.contains(word), word) }
        for path in ["Features/Pass/PassViewerView.swift", "Features/Pass/PassBookView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("PassCardMenu(content:"), "\(path) に「…」が無い")
            XCTAssertTrue(text.contains("ReportSheet(photoId: target.photo.id"), "\(path) から通報できない")
            XCTAssertTrue(text.contains(".blockConfirmation(presenting: $blockTarget)"), "\(path) のブロックに確認が無い")
            XCTAssertTrue(text.contains("pass.remove("), "\(path) から帳から外せない")
        }
        let back = try source("Features/Pass/PassCards.swift")
        XCTAssertTrue(back.contains("Text(PassPrivacyText.noteSource)"), "ひとことが届いた文だと分からない")
        let viewer = try source("Features/Pass/PassViewerView.swift")
        XCTAssertTrue(viewer.contains("Text(PassPrivacyText.thanksNotice)"), "「ありがとう」が名前つきのいいねだと言わない")
    }

    /// 二度目の読み直し: 束の画面にトースト・ひとことの通報は写真の通報と分ける・写真は全面で見られる
    func testViewerShowsToastsAndSeparatesNoteReports() throws {
        let viewer = try source("Features/Pass/PassViewerView.swift")
        XCTAssertTrue(viewer.contains(".overlay(alignment: .top) { ToastOverlay() }"), "束の画面にトーストが出ない")
        XCTAssertTrue(viewer.contains("PassPhotoFullView(photo: photo)"), "写真を全面で見られない")
        XCTAssertTrue(viewer.contains(".allowsHitTesting(!showsBack)"), "裏を見ている間に表の写真が押せる")
        for path in ["Features/Pass/PassViewerView.swift", "Features/Pass/PassBookView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("ReportSheet(photoId: target.photo.id, ownerId: nil, passNote: target.card.note,"),
                          "\(path) のひとことの通報が写真の通報になっている")
            XCTAssertTrue(text.contains("pass.setNoteHidden("), "\(path) でひとことを伏せられない")
        }
        let sheet = try source("Features/Social/ReportSheet.swift")
        XCTAssertTrue(sheet.contains("passNote.map { ModerationService.passNoteReportNote($0, note: note) }"))
        XCTAssertTrue(sheet.contains("if comment == nil && passNote == nil {\n                hidden.markReported"),
                      "ひとことの通報で写真を隠している")
        let menu = try source("Features/Pass/PassCardMenu.swift")
        for word in ["写真を通報する", "ひとことを通報する", "ひとことを伏せる", "ひとことを出す"] {
            XCTAssertTrue(menu.contains(word), word)
        }
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertTrue(pick.contains("PassExchange.noteProblem(note)"), "超えた訳を出さない")
    }

    /// きっぷ（案C）: 表は写真・眉・区間・破線・改札の穴、裏は帯・ご案内・4つの欄
    func testTicketShape() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        for part in ["PassTicketArrow()", "PassTicketDash()", "PassTicketPunch()", "PassTicket.eyebrow(face.kind)",
                     "L(\"ご案内\", \"NOTICE\")", "L(\"発行\", \"Issued by\")", "L(\"有効\", \"Valid\")",
                     "L(\"区間\", \"Distance\")", "L(\"回数\", \"Times\")", "PassTicketEdge(kind: face.kind)"] {
            XCTAssertTrue(cards.contains(part), "きっぷに \(part) が無い")
        }
        XCTAssertTrue(try source("Features/Pass/PassBookView.swift").contains("PassTicketSlot(content: content)"))
    }

    /// 三度目の読み直し: 縁は外側・光は後ろ・見本は縮めない・裏は裏のときだけ押せる・通報の終わりで伏せる
    func testEdgeOutsideAndReportFollowUps() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        let edge = try XCTUnwrap(cards.range(of: "struct PassTicketEdge")).upperBound
        let glow = try XCTUnwrap(cards.range(of: "struct PassTicketGlow")).lowerBound
        let edgeBody = String(cards[edge..<glow])
        XCTAssertTrue(edgeBody.contains(".padding(firstInset)"), "縁を内側に引いている（写真に真鍮がかかる）")
        XCTAssertFalse(edgeBody.contains(".shadow("), "「はじめて」の光を縁に付けている（写真に光が落ちる）")
        XCTAssertEqual(cards.components(separatedBy: ".background { PassTicketGlow(").count - 1, 3)
        XCTAssertEqual(cards.components(separatedBy: ".dynamicTypeSize(...PassCardStyle.typeLimit)").count - 1, 3)
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertFalse(pick.contains("scaleEffect"), "見本を縮めて字が 12pt を割る")
        let viewer = try source("Features/Pass/PassViewerView.swift")
        XCTAssertTrue(viewer.contains(".allowsHitTesting(showsBack)"))
        for path in ["Features/Pass/PassViewerView.swift", "Features/Pass/PassBookView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("onReported: { pass.markNoteReported(target.id) })"), "\(path): 通報したひとことを伏せない")
            XCTAssertTrue(text.contains("carriedPassNote: target.card.noteReported == true ? target.card.note : nil)"),
                          "\(path): 写真の通報でひとことの通報が消える")
        }
        let sheet = try source("Features/Social/ReportSheet.swift")
        XCTAssertTrue(sheet.contains("onReported?()"))
        XCTAssertTrue(sheet.contains("carriedPassNote.map { ModerationService.photoReportWithPassNote(note, passNote: $0) }"))
        XCTAssertTrue(sheet.contains("report.replaceNotice"), "上書きされることを画面で言わない")
    }

    /// 退会・期限切れのログアウトでも電波を止める
    func testRadioStopsOnAccountRemovalAndExpiry() throws {
        // 型の名前を分けて書く（`check-swift-refs.js` が文字列の中の呼び出しを、テストからの呼び出しと読む）
        let store = "Pass" + "Store"
        let local = try source("Core/Storage/AccountLocalData.swift")
        let stop = try XCTUnwrap(local.range(of: store + ".shared.use(userId: nil)"), "退会で電波を止めない")
        let remove = try XCTUnwrap(local.range(of: store + ".removeData(for: userId"))
        XCTAssertLessThan(stop.lowerBound, remove.lowerBound, "帳を消す前に止めていない")
        let app = try source("App/JourneyPhotoApp.swift")
        let task = try XCTUnwrap(app.range(of: store + ".shared.use(userId: auth.userId)"))
        let head = app[app.startIndex..<task.lowerBound]
        let block = try XCTUnwrap(head.range(of: ".task(id: auth.state)", options: .backwards))
        XCTAssertFalse(app[block.upperBound..<task.lowerBound].contains("signedOutByExpiry { return }"),
                       "期限切れのログアウトで電波を止めない")
    }

    /// 写真の上の真鍮の枠には内側に黒の縁・打っている途中で字数で切らない
    func testPickFrameHasInnerBlackEdge() throws {
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertTrue(pick.contains("Rectangle().strokeBorder(Color.black, lineWidth: JPStroke.hairline)"))
        XCTAssertFalse(pick.contains("String(value.prefix(PassExchange.noteLimit))"), "変換中に字数で切っている")
    }
}
