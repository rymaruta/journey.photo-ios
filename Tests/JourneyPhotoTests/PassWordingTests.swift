import XCTest
@testable import JourneyPhoto

/// すれちがい乗車券まわりの呼び名をそろえる（2026-11-14 判断・点検 48 件の直し）。
///
/// - 呼び名は「乗車券」。受け取った物も「カード」と呼ばない。数えるときは「枚」
/// - 保管場所は「すれちがい帳」。「帳」1文字では使わない。「束」も画面の文から外した
/// - 「近くにいたアプリの人」→「近くにいた人」・「字」→「言葉」「区間」・「届きえます」「粒度」は使わない
/// - 「わたしの乗車券」は本人の物だけ。人の乗車券は「〇〇さんの乗車券」（名前が無ければ「乗車券」）
///
/// 画面は Linux で描けないので、`L("…")` の日本語を書いてあるもので見る（`PlaceTermWordingTests` と同じ形）
final class PassWordingTests: XCTestCase {

    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
    }

    /// `L("日本語"` の日本語の部分だけを、ファイル:行 と一緒に返す
    private func japaneseStrings(in file: URL) throws -> [(at: String, text: String)] {
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        let pattern = try NSRegularExpression(pattern: #"L\("((?:[^"\\]|\\.)*)""#)
        var out: [(String, String)] = []
        for (i, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            for match in pattern.matches(in: line, range: range) {
                guard let r = Range(match.range(at: 1), in: line) else { continue }
                out.append(("\(file.lastPathComponent):\(i + 1)", String(line[r])))
            }
        }
        return out
    }

    /// すれちがい乗車券の文があるファイル
    private func passFiles() throws -> [URL] {
        let folder = sourcesRoot.appendingPathComponent("Features/Pass")
        let views = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let text = try FileManager.default.contentsOfDirectory(at: sourcesRoot.appendingPathComponent("Core/Text"),
                                                               includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Pass") && $0.pathExtension == "swift" }
        return views + text + ["Core/Push/PassBundleNotifier.swift", "Core/Text/TrunkInside.swift",
                               "Core/Text/TheirTrunkText.swift", "Features/Trunk/TheirTrunkView.swift"]
            .map { sourcesRoot.appendingPathComponent($0) }
    }

    /// 払う操作と一緒に別の担当が変えている案内（`PassViewerView` の写真の下の一行）。ここが変わったら外す
    private static let leftForSwipeWork = ["写真を押すと全面、"]

    private func passStrings() throws -> [(at: String, text: String)] {
        try passFiles().flatMap { try japaneseStrings(in: $0) }
            .filter { s in !Self.leftForSwipeWork.contains { s.text.hasPrefix($0) } }
    }

    /// 🔴 乗車券を「カード」「束」と呼ばない・「帳」1文字で使わない・使わないと決めた言い方が戻らない
    func testPassTextUsesTicketNames() throws {
        let strings = try passStrings()
        XCTAssertGreaterThan(strings.count, 150, "前提: すれちがい乗車券の `L(` を読めていない")
        let banned = ["カード", "束", "アプリの人", "届きえ", "粒度", "の字", "書く字", "書いた字"]
        let bad = strings.filter { s in banned.contains { s.text.contains($0) } }.map { "\($0.at) \($0.text)" }
        XCTAssertEqual(bad, [], "乗車券の呼び名がそろっていない")
        // 「帳」は「すれちがい帳」の形でだけ使う
        let lone = strings.filter { $0.text.replacingOccurrences(of: "すれちがい帳", with: "").contains("帳") }
            .map { "\($0.at) \($0.text)" }
        XCTAssertEqual(lone, [], "「帳」1文字で使っている（「すれちがい帳」にする）")
    }

    /// 呼び名を直した所が今の言葉になっている（直しを戻すとここで落ちる）
    func testRenamedTexts() {
        XCTAssertEqual(PassBundleNotifier.title(), L("乗車券が届きました", "Tickets have arrived"))
        XCTAssertEqual(PassBundleNotifier.body(count: 3),
                       L("今日すれちがった 3 人から乗車券が届きました", "Tickets have arrived from 3 people you passed today"))
        XCTAssertEqual(PassTicket.sectionTitle, L("区間", "Route"))
        XCTAssertTrue(PassTicket.receivedFootnote.hasPrefix(L("この乗車券は", "This ticket")))
        XCTAssertTrue(PassPrivacyText.introPoints.map(\.text).joined().contains(L("届くことがあります", "may still reach")))
        XCTAssertEqual(PassPrivacyText.thanksNotice, L("相手にあなたの名前でありがとうが届きます",
                                                       "They\u{2019}ll get your thanks, with your name"))
    }

    /// 🔴 人の乗車券に「わたしの乗車券」と出さない（本人の物だけの呼び名）
    func testTheirTicketIsNotCalledMine() throws {
        for path in ["Core/Text/TrunkInside.swift", "Core/Text/TheirTrunkText.swift", "Features/Trunk/TheirTrunkView.swift"] {
            let mine = try japaneseStrings(in: sourcesRoot.appendingPathComponent(path)).filter { $0.text.contains("わたし") }
            XCTAssertEqual(mine.map { "\($0.at) \($0.text)" }, [], "人の乗車券を「わたしの乗車券」と呼んでいる")
        }
        XCTAssertEqual(TheirTrunkText.ticketTitle("丸田"), L("丸田さんの乗車券", "丸田\u{2019}s ticket"))
        XCTAssertEqual(TheirTrunkText.ticketTitle("  "), L("乗車券", "Ticket"), "名前が無いのに「この人さん」と呼んだ")
        XCTAssertEqual(TheirTrunkText.ticketTitle(nil), L("乗車券", "Ticket"))
        // 本人の物は「わたしの乗車券」のまま
        let pick = try String(contentsOf: sourcesRoot.appendingPathComponent("Features/Pass/PassCardPickView.swift"), encoding: .utf8)
        XCTAssertTrue(pick.contains(#".navigationTitle(L("わたしの乗車券", "My ticket"))"#))
        let view = try String(contentsOf: sourcesRoot.appendingPathComponent("Features/Trunk/TheirTrunkView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains(".navigationTitle(TheirTrunkText.ticketTitle(theirs.name))"), "人の乗車券の画面の題")
    }

    /// 通信の失敗の文は「通信できる所で、もう一度お試しください」にそろえる
    func testNetworkFailureWording() throws {
        // 乗車券の文だけ（人のトランクの読み込みの文はこの直しの外）
        let strings = try passStrings().filter { $0.at.hasPrefix("Pass") }
        let old = strings.filter { $0.text.contains("電波のある") || $0.text.contains("つながる所") }.map { "\($0.at) \($0.text)" }
        XCTAssertEqual(old, [], "通信の失敗の言い方がそろっていない")
        XCTAssertTrue(PassTicketFaceStyle.profileUnreadable.contains(L("通信できる所で、もう一度お試しください",
                                                                       "Please try again when you\u{2019}re online")))
    }
}
