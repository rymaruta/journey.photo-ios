import XCTest
@testable import JourneyPhoto

/// 板 15 の1行（文言・まとめ・経過時間・未読）。
final class NotificationTextTests: XCTestCase {

    /// **鍵はサーバーと同じ `type`**（`kind` と書くと種類が nil になり、
    /// 何も確かめないテストになる）
    private func row(_ type: String, by: String? = "u1", name: String? = "Aki",
                     photo: String? = "p1", t: String = "2026-09-21T10:00:00.000Z",
                     deleted: Bool = false) throws -> AppNotification {
        var fields = ["\"type\":\"\(type)\"", "\"t\":\"\(t)\""]
        if let by { fields.append("\"byId\":\"\(by)\"") }
        if let name { fields.append("\"byName\":\"\(name)\"") }
        if let photo { fields.append("\"photoId\":\"\(photo)\"") }
        if deleted { fields.append("\"deleted\":true") }
        return try JSONDecoder.api.decode(AppNotification.self,
                                          from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var now: Date { NotificationGroups.parse("2026-09-21T12:00:00.000Z")! }

    private func single(_ notification: AppNotification) -> NotificationText.Entry {
        NotificationText.Entry(lead: notification, others: 0, unread: false)
    }

    // MARK: 文言（板の言い方）

    func testWordingFollowsTheBoard() throws {
        XCTAssertEqual(NotificationText.line(for: single(try row("like")))?.plain,
                       L("Aki があなたの写真にいいねしました", "Aki liked your photo"))
        XCTAssertEqual(NotificationText.line(for: single(try row("follow", photo: nil)))?.plain,
                       L("Aki があなたをフォローしました", "Aki followed you"))
        XCTAssertEqual(NotificationText.line(for: single(try row("comment")))?.plain,
                       L("Aki がコメントしました", "Aki commented on your photo"))
        XCTAssertEqual(NotificationText.line(for: single(try row("storyreply")))?.plain,
                       L("Aki がストーリーに返信しました", "Aki replied to your story"))
    }

    /// 名前だけ太くするので、名前と残りを分けて返す
    func testNameIsSeparated() throws {
        let line = try XCTUnwrap(NotificationText.line(for: single(try row("like"))))
        XCTAssertEqual(line.who, "Aki")
        XCTAssertFalse(line.rest.contains("Aki"))
    }

    func testGroupedLikeWording() throws {
        let entry = NotificationText.Entry(lead: try row("like"), others: 3, unread: false)
        XCTAssertEqual(NotificationText.line(for: entry)?.plain,
                       L("Aki ほか 3人 がいいねしました", "Aki and 3 others liked your photo"))
    }

    /// アイコンの読み上げ。名前の無い通知でも「だれか」で補う（行の文言と同じ）
    func testOpenProfileLabelFillsMissingName() throws {
        XCTAssertEqual(NotificationText.openProfileLabel(try row("follow", name: nil, photo: nil)),
                       L("だれか のプロフィールを開く", "Open Someone's profile"))
        XCTAssertEqual(NotificationText.openProfileLabel(try row("follow", photo: nil)),
                       L("Aki のプロフィールを開く", "Open Aki's profile"))
    }

    func testUnknownKindAndDeletedUser() throws {
        XCTAssertNil(NotificationText.line(for: single(try row("inspired"))))
        XCTAssertEqual(NotificationText.line(for: single(try row("like", deleted: true)))?.who,
                       Labels.Common.deletedUser)
    }

    // MARK: まとめ

    func testLikesOnTheSamePhotoCollapse() throws {
        let rows = [
            try row("like", by: "a", photo: "p1", t: "2026-09-21T11:00:00.000Z"),
            try row("comment", by: "b", photo: "p1", t: "2026-09-21T10:30:00.000Z"),
            try row("like", by: "b", photo: "p1", t: "2026-09-21T10:00:00.000Z"),
            try row("like", by: "c", photo: "p2", t: "2026-09-21T09:30:00.000Z"),
            try row("like", by: "d", photo: "p1", t: "2026-09-21T09:00:00.000Z"),
        ]
        let entries = NotificationText.collapse(rows)
        // 並びは先頭の位置のまま。コメントはまとめない
        XCTAssertEqual(entries.map(\.lead.byId), ["a", "b", "c"])
        XCTAssertEqual(entries.map(\.lead.kind), [.like, .comment, .like])
        XCTAssertEqual(entries.map(\.others), [2, 0, 0])
    }

    /// 同じ人が押し直した（外して、また押した）ぶんは「ほか」に数えない
    func testSamePersonIsCountedOnce() throws {
        let rows = [
            try row("like", by: "a", t: "2026-09-21T11:00:00.000Z"),
            try row("like", by: "a", t: "2026-09-21T10:00:00.000Z"),
        ]
        let entries = NotificationText.collapse(rows)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.others, 0)
    }

    /// 写真の id が無いいいね・フォローはまとめない
    func testRowsWithoutPhotoAreNotCollapsed() throws {
        let rows = [
            try row("follow", by: "a", photo: nil),
            try row("follow", by: "b", photo: nil),
            try row("like", by: "c", photo: ""),
            try row("like", by: "d", photo: ""),
        ]
        XCTAssertEqual(NotificationText.collapse(rows).count, 4)
    }

    // MARK: 未読

    /// サーバーの未読は「先頭から何件」
    func testUnreadIsTheHeadOfTheList() throws {
        let rows = [
            try row("like", by: "a", photo: "p1", t: "2026-09-21T11:00:00.000Z"),
            try row("follow", by: "b", photo: nil, t: "2026-09-21T10:00:00.000Z"),
            try row("like", by: "c", photo: "p2", t: "2026-09-21T09:00:00.000Z"),
        ]
        let ids = NotificationText.unreadIds(rows, unread: 2)
        XCTAssertEqual(NotificationText.collapse(rows, unreadIds: ids).map(\.unread), [true, true, false])
        XCTAssertTrue(NotificationText.unreadIds(rows, unread: 0).isEmpty)
        XCTAssertEqual(NotificationText.unreadIds(rows, unread: 99).count, 3)
    }

    /// まとめた中に未読があれば、その行は未読
    func testCollapsedEntryIsUnreadIfAnyMemberIs() throws {
        let rows = [
            try row("like", by: "a", photo: "p1", t: "2026-09-21T11:00:00.000Z"),
            try row("follow", by: "b", photo: nil, t: "2026-09-21T10:00:00.000Z"),
            try row("like", by: "c", photo: "p1", t: "2026-09-21T09:00:00.000Z"),
        ]
        let ids: Set<String> = [rows[2].id]
        XCTAssertEqual(NotificationText.collapse(rows, unreadIds: ids).map(\.unread), [true, false])
    }

    // MARK: 経過時間

    func testAgo() {
        func ago(_ t: String?) -> String? { NotificationText.ago(t, now: now, calendar: calendar) }
        XCTAssertEqual(ago("2026-09-21T10:00:00.000Z"), L("2時間前", "2h ago"))
        XCTAssertEqual(ago("2026-09-21T11:55:00Z"), L("5分前", "5m ago"))
        XCTAssertEqual(ago("2026-09-20T23:00:00.000Z"), L("昨日", "Yesterday"))
        XCTAssertEqual(ago("2026-09-18T20:00:00.000Z"), L("3日前", "3d ago"))
        XCTAssertNil(ago(nil))
        XCTAssertNil(ago("壊れた値"))
        XCTAssertNil(ago("2026-09-22T10:00:00.000Z"))   // 未来
    }
}

/// 未読の点が「読み直すまで」残るか（ビューモデル）。
///
/// 開いた回の最後に既読にするので、**行を押して戻っただけ**で `.task` が
/// 走り直すと、サーバーは `unread=0` を返す。それで点が消えてはいけない。
@MainActor
final class NotificationsUnreadKeepTests: XCTestCase {

    private func page(_ ids: [String], unread: Int) throws -> NotificationService.Page {
        let items = ids.map {
            "{\"type\":\"like\",\"byId\":\"\($0)\",\"photoId\":\"p-\($0)\",\"t\":\"2026-09-21T10:00:00.000Z\"}"
        }.joined(separator: ",")
        return try JSONDecoder.api.decode(NotificationService.Page.self,
                                          from: Data("{\"items\":[\(items)],\"unread\":\(unread)}".utf8))
    }

    func testDotsSurviveAReloadAfterMarkingRead() async throws {
        let model = NotificationsViewModel()
        let first = try page(["a", "b", "c"], unread: 2)
        model.apply(first, refreshing: false)
        XCTAssertEqual(model.unreadIds, Set(first.items.prefix(2).map(\.id)))
        // 戻ってきて読み直した回（既読化のあと）
        model.apply(try page(["a", "b", "c"], unread: 0), refreshing: false)
        XCTAssertEqual(model.unreadIds, Set(first.items.prefix(2).map(\.id)))
    }

    /// 同じ画面にいる間に届いたぶんは足す
    func testNewArrivalsAreAdded() async throws {
        let model = NotificationsViewModel()
        model.apply(try page(["a", "b"], unread: 1), refreshing: false)
        let next = try page(["n", "a", "b"], unread: 1)
        model.apply(next, refreshing: false)
        XCTAssertEqual(model.unreadIds, Set([next.items[0].id, next.items[1].id]))
    }

    /// **遅れて返った古い読み込みで点が戻らない。**
    /// `.task`（古い）が既読化の前に読んだ `unread` を抱えたまま、読み直しで点を
    /// 消したあとに返ってくると、和で点が戻っていた
    func testStaleLoadDoesNotBringDotsBack() async throws {
        let model = NotificationsViewModel()
        let task = model.beginLoad()                      // `.task` が始まる（返りが遅い）
        let pull1 = model.beginLoad()
        XCTAssertTrue(model.apply(try page(["a", "b"], unread: 2), refreshing: true, generation: pull1))
        let pull2 = model.beginLoad()                     // 既読化のあとの読み直し
        XCTAssertTrue(model.apply(try page(["a", "b"], unread: 0), refreshing: true, generation: pull2))
        XCTAssertTrue(model.unreadIds.isEmpty)
        // 既読化の前に読んだ `.task` の結果がいま返る
        model.apply(try page(["a", "b"], unread: 2), refreshing: false, generation: task)
        XCTAssertTrue(model.unreadIds.isEmpty, "古い読み込みで未読の点が戻った")
    }

    /// **新しい回が失敗しても、先に成功した古い回は画面に移す。**
    /// 「新しい回が始まった」だけで捨てると、圏外で読み直した瞬間に
    /// 行も既読化も飛び、エラーだけが残っていた
    func testOlderLoadAppliesWhenNewerNeverApplied() async throws {
        let model = NotificationsViewModel()
        let task = model.beginLoad()
        _ = model.beginLoad()                             // 読み直し（このあと失敗して何も移さない）
        XCTAssertTrue(model.apply(try page(["a"], unread: 1), refreshing: false, generation: task),
                      "新しい回が移していないのに古い回を捨てた")
        XCTAssertEqual(model.rows.count, 1)
    }

    /// **より新しい回が書いた手元の一覧を、遅れた古い回で上書きしない**
    func testStaleLoadDoesNotOverwritePools() async {
        let model = NotificationsViewModel()
        let old = model.beginLoad()
        let new = model.beginLoad()
        XCTAssertTrue(model.claimPools(new))
        XCTAssertFalse(model.claimPools(old), "古い回が一覧を上書きできる")
        XCTAssertTrue(model.claimPools(new), "同じ回の2つ目（自分の写真）は書ける")
    }

    /// 引っぱって読み直したときは入れ替える（点が消える）
    func testPullToRefreshReplaces() async throws {
        let model = NotificationsViewModel()
        model.apply(try page(["a", "b"], unread: 2), refreshing: false)
        model.apply(try page(["a", "b"], unread: 0), refreshing: true)
        XCTAssertTrue(model.unreadIds.isEmpty)
    }
}

/// プッシュ通知の文面（`Localizable.strings`）が一覧の文言と同じか。
/// **サーバーは鍵だけ送る**ので、文面はここにしか無い
final class NotificationPushStringsTests: XCTestCase {

    private func strings(_ lang: String) throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Resources/\(lang).lproj/Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            if parts.count >= 4, parts[1].hasPrefix("NOTIF_") { out[String(parts[1])] = String(parts[3]) }
        }
        return out
    }

    func testJapaneseMatchesTheList() throws {
        let ja = try strings("ja")
        XCTAssertEqual(ja["NOTIF_LIKE"], "%@ があなたの写真にいいねしました")
        XCTAssertEqual(ja["NOTIF_COMMENT"], "%@ がコメントしました")
        XCTAssertEqual(ja["NOTIF_FOLLOW"], "%@ があなたをフォローしました")
        XCTAssertEqual(ja["NOTIF_STORY_REPLY"], "%@ がストーリーに返信しました")
    }

    func testEnglishMatchesTheList() throws {
        let en = try strings("en")
        XCTAssertEqual(en["NOTIF_LIKE"], "%@ liked your photo")
        XCTAssertEqual(en["NOTIF_COMMENT"], "%@ commented on your photo")
        XCTAssertEqual(en["NOTIF_FOLLOW"], "%@ followed you")
        XCTAssertEqual(en["NOTIF_STORY_REPLY"], "%@ replied to your story")
    }
}

/// 行を `NavigationLink` で包まなくなったので、行き先は id で持つ。
/// 開くときに引き直せるか（公開一覧 → 自分の写真の順）
@MainActor
final class NotificationRouteTests: XCTestCase {

    private func photo(_ id: String) throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"\#(id)","src":"https://x/\#(id).jpg"}"#.utf8))
    }

    private func notification(_ json: String) throws -> AppNotification {
        try JSONDecoder.api.decode(AppNotification.self, from: Data(json.utf8))
    }

    func testRoutesResolveBackToTheScreen() async throws {
        let model = NotificationsViewModel()
        model.setFeedForTesting([try photo("pub")])
        model.setMineForTesting([try photo("draft")])
        let like = try notification(#"{"type":"like","photoId":"draft","byId":"u"}"#)
        XCTAssertEqual(model.route(for: like), .photo(try photo("draft"), fromPublicFeed: false))
        let pub = try notification(#"{"type":"like","photoId":"pub","byId":"u"}"#)
        XCTAssertEqual(model.route(for: pub), .photo(try photo("pub"), fromPublicFeed: true))
        let follow = try notification(#"{"type":"follow","byId":"u","targetUserId":"u"}"#)
        XCTAssertEqual(model.route(for: follow), .user("u"))
        let reply = try notification(#"{"type":"storyreply","photoId":"s","byId":"u"}"#)
        XCTAssertNil(model.route(for: reply))
    }

    /// **押したあとで手元の一覧が空になっても、行き先の写真は残る。**
    /// 遷移で一覧の `.task` が取り消される・読み直しが失敗する等で一覧が空に
    /// なると、id から引き直す作りでは詳細が白紙になっていた
    func testRouteKeepsThePhotoAfterTheListEmpties() async throws {
        let model = NotificationsViewModel()
        model.setMineForTesting([try photo("draft")])
        let like = try notification(#"{"type":"like","photoId":"draft","byId":"u"}"#)
        let route = try XCTUnwrap(model.route(for: like))
        model.setMineForTesting([])
        model.setFeedForTesting([])
        guard case .photo(let held, false) = route else { return XCTFail("行き先が写真でない") }
        XCTAssertEqual(held.src, "https://x/draft.jpg")
    }

    /// 取り消された回は手元の一覧を空で上書きしない（取り消し以外の失敗は空にする）
    func testCancelledFetchKeepsThePreviousList() async throws {
        let before = [try photo("a")]
        XCTAssertEqual(NotificationsViewModel.kept(nil, previous: before, cancelled: true).map(\.id), ["a"])
        XCTAssertTrue(NotificationsViewModel.kept(nil, previous: before, cancelled: false).isEmpty)
        XCTAssertEqual(NotificationsViewModel.kept([try photo("b")], previous: before, cancelled: true).map(\.id), ["b"])
    }
}
