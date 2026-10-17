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
        XCTAssertTrue(try source("Features/Pass/PassSpinCard.swift").contains(".allowsHitTesting(!back)"),
                      "裏を見ている間に表の写真が押せる")
        for path in ["Features/Pass/PassViewerView.swift", "Features/Pass/PassBookView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("ReportSheet(photoId: target.photo.id, ownerId: nil, passNote: target.card.writtenText,"),
                          "\(path) のひとことの通報が写真の通報になっている")
            XCTAssertTrue(text.contains("pass.setNoteHidden("), "\(path) でひとことを伏せられない")
        }
        let sheet = try source("Features/Social/ReportSheet.swift")
        XCTAssertTrue(sheet.contains("passNote.map { ModerationService.passNoteReportNote($0, note: note) }"))
        XCTAssertTrue(sheet.contains("if comment == nil && passNote == nil {\n                hidden.markReported"),
                      "ひとことの通報で写真を隠している")
        let menu = try source("Features/Pass/PassCardMenu.swift")
        for word in ["写真を通報する", "書かれた字を通報する", "ひとことを伏せる", "ひとことを出す"] {
            XCTAssertTrue(menu.contains(word), word)
        }
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertTrue(pick.contains("PassExchange.noteProblem(note)"), "超えた訳を出さない")
        XCTAssertTrue(pick.contains("foregroundStyle(PassExchange.noteProblem(note) == nil ? WebTheme.text3 : WebTheme.danger)"),
                      "ひとことの字数が、発・着のエラーで赤くなる")
        XCTAssertFalse(pick.contains("foregroundStyle(noteTooLong"), "ひとことの字数が別の欄のエラーを見ている")
    }

    /// きっぷ（案C）: 表は写真・眉・区間・破線・改札の穴、裏は帯・ご案内・4つの欄
    func testTicketShape() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        // 2026-10-17 マルス券: 表の改札の穴はやめ（破線は裏へ）、種類の名は「乗車券」の位置（`face.headline`）
        for part in ["PassTicketArrow()", "PassTicketDash(shine: shine)", "PassTicketHead(text: face.headline)",
                     "PassTicketHead(text: L(\"ご案内\", \"NOTICE\"))", "face.fields", "PassTicketEdge(kind: face.kind, shine: shine)"] {
            XCTAssertTrue(cards.contains(part), "きっぷに \(part) が無い")
        }
        let ticket = try source("Core/Text/PassTicket.swift")
        for part in ["L(\"発行\", \"Issued by\")", "L(\"有効\", \"Valid\")", "L(\"区間\", \"Distance\")",
                     "L(\"回数\", \"Times\")", "L(\"日付\", \"Date\")"] {
            XCTAssertTrue(ticket.contains(part), "きっぷの欄に \(part) が無い")
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
        // 2026-10-17 判断: 表と裏は固定の字（文字を大きくする設定では変わらない・読み上げで全部読める）なので
        // `.dynamicTypeSize` を付けない。設定に合わせて大きくなる字（`JPFont`）を使うのは帳の小さな札だけで、上限はそこに1つ
        XCTAssertEqual(cards.components(separatedBy: ".dynamicTypeSize(...PassCardStyle.typeLimit)").count - 1, 1)
        let slot = try XCTUnwrap(cards.range(of: "struct PassTicketSlot"))
        let mini = try XCTUnwrap(cards.range(of: "struct PassMiniStack"))
        XCTAssertTrue(cards[slot.upperBound..<mini.lowerBound].contains(".dynamicTypeSize(...PassCardStyle.typeLimit)"),
                      "帳の小さな札に文字の大きさの上限が無い")
        let front = try XCTUnwrap(cards.range(of: "struct PassCardFront")).lowerBound
        XCTAssertFalse(cards[front..<slot.lowerBound].contains(".font(JPFont."),
                       "表と裏に設定で大きくなる字が入った（固定の字の判断が崩れる・札からはみ出す）")
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertFalse(pick.contains("scaleEffect"), "見本を縮めて字が 12pt を割る")
        XCTAssertTrue(try source("Features/Pass/PassSpinCard.swift").contains(".allowsHitTesting(back)"))
        for path in ["Features/Pass/PassViewerView.swift", "Features/Pass/PassBookView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("onReported: { pass.markNoteReported(target.id) })"), "\(path): 通報したひとことを伏せない")
            XCTAssertTrue(text.contains("carriedPassNote: target.card.noteReported == true ? target.card.writtenText : nil)"),
                          "\(path): 写真の通報でひとことの通報が消える")
        }
        let sheet = try source("Features/Social/ReportSheet.swift")
        XCTAssertTrue(sheet.contains("onReported?()"))
        XCTAssertTrue(sheet.contains("carriedPassNote.map { ModerationService.photoReportWithPassNote(note, passNote: $0) }"))
        XCTAssertTrue(sheet.contains("report.replaceNotice"), "上書きされることを画面で言わない")
    }

    /// 発・着: 乗車券選びに区間の欄・見本にその場で出る・「…」に区間の字を伏せる・通報は書かれた字ぜんぶ
    func testTicketLabelsWiring() throws {
        let pick = try source("Features/Pass/PassCardPickView.swift")
        for part in ["routeSection", "PassTicket.previewOrigin(originChoice", "PassTicket.previewDestination(custom: destinationCustom",
                     "settings.setOrigin(originChoice, text: originText)", "PassExchange.labelProblem("] {
            XCTAssertTrue(pick.contains(part), part)
        }
        let menu = try source("Features/Pass/PassCardMenu.swift")
        XCTAssertTrue(menu.contains("区間の字を伏せる"))
        XCTAssertTrue(menu.contains("書かれた字を通報する"))
        for path in ["Features/Pass/PassViewerView.swift", "Features/Pass/PassBookView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("passNote: target.card.writtenText"), "\(path): 通報に発・着の字が入らない")
            XCTAssertTrue(text.contains("pass.setLabelsHidden("), "\(path): 区間の字を伏せられない")
        }
        let radio = try source("Services/PassRadio.swift")
        XCTAssertTrue(radio.contains("legacy: PassExchange.encodeV1(payload)"), "前のアプリ向けの版 1 を出していない")
    }

    /// 回す: メダルと同じ決め方（`SpinMotion`）を両方が使う・減らす設定では回さない・読み上げの操作は残す
    func testSpinWiring() throws {
        let medal = try source("Features/Profile/MedalViewerView.swift")
        XCTAssertTrue(medal.contains("SpinMotion.yawDelta("), "メダルが同じ決め方を使っていない（写しになる）")
        XCTAssertTrue(medal.contains("SpinMotion.flipTarget(from:"))
        let viewer = try source("Features/Pass/PassViewerView.swift")
        for part in ["PassSpinTicket(yaw: yaw", "spin.liveYaw(", "PassSpinGesture.classify(",
                     "SpinMotion.snapTarget(",
                     "accessibilityAction(named: L(\"次のカード\"", "accessibilityAction(named: L(\"写真を全面で見る\""] {
            XCTAssertTrue(viewer.contains(part), part)
        }
        // 回す描き方・手つきは共有の部品（自分のカードの見本も使う・`PassOwnCardSpinTests`）
        let spin = try source("Features/Pass/PassSpinCard.swift")
        for part in ["PassSpinGesture.liveYaw(", ".rotation3DEffect(.radians(reduceMotion ? 0 : yaw)",
                     "let shine: Double? = reduceMotion ? nil : SpinMotion.shine(yaw)"] {
            XCTAssertTrue(spin.contains(part), part)
        }
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

    /// 呼び名は「わたしの乗車券」（2026-10-17 判断: owner が「名刺の一枚」から替えた）。
    /// 画面に出る字（Sources の文字列リテラル＝`L("…", "…")` の中・InfoPlist.strings）に「名刺」を残さない。
    /// 注記（`//`）の「旧: 名刺の一枚」は数えない。識別子・保存のキーは変えていない
    func testNoOldCardNameOnScreen() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
        let literal = try NSRegularExpression(pattern: #""(?:[^"\\\n]|\\.)*""#)
        var checked = 0
        var found: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        for url in files where url.pathExtension == "swift" || url.pathExtension == "strings" {
            let text = try String(contentsOf: url, encoding: .utf8)
            checked += 1
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                let range = NSRange(line.startIndex..., in: line)
                for match in literal.matches(in: line, range: range) {
                    guard let r = Range(match.range, in: line), line[r].contains("名刺") else { continue }
                    found.append("\(url.lastPathComponent):\(index + 1) \(line[r])")
                }
            }
        }
        XCTAssertGreaterThan(checked, 100, "Sources を読めていない")
        XCTAssertTrue(found.isEmpty, "画面の字に「名刺」が残っている（「乗車券」に）: \(found)")
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertTrue(pick.contains(#".navigationTitle(L("わたしの乗車券", "My ticket"))"#), "選ぶ画面の題が「わたしの乗車券」でない")
        let settings = try source("Features/Pass/PassSettingsView.swift")
        XCTAssertTrue(settings.contains(#"Text(L("わたしの乗車券", "My ticket"))"#), "設定の行が「わたしの乗車券」でない")
    }
}
