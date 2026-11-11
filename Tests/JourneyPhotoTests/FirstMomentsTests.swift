import XCTest
@testable import JourneyPhoto

/// 楽しさの案 A・B（2026-11-08・札 #502）: 「はじめて」を静かに祝う・季節の家具の条件。
/// 判定はすべて端末の中。**確かめられないときは祝わない**（取りこぼしは「無い」方へ倒す）
@MainActor
final class FirstMomentsTests: XCTestCase {

    // MARK: 道具

    private func suite() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    private let now = NotificationGroups.parse("2026-11-08T12:00:00.000Z")!

    private func iso(hoursAgo: Double) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: now.addingTimeInterval(-hoursAgo * 3600))
    }

    private func row(_ type: String, by: String = "u1", photo: String = "p1", t: String, deleted: Bool = false) throws -> AppNotification {
        let extra = deleted ? ",\"deleted\":true" : ""
        let json = "{\"type\":\"\(type)\",\"t\":\"\(t)\",\"byId\":\"\(by)\",\"byName\":\"Aki\",\"photoId\":\"\(photo)\"\(extra)}"
        return try JSONDecoder.api.decode(AppNotification.self, from: Data(json.utf8))
    }

    private func photo(_ id: String, location: String?, published: Bool = true) throws -> Photo {
        var json: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg", "published": published]
        if let location { json["location"] = location }
        return try JSONDecoder().decode(Photo.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func label(kind: TrunkLabel.Kind = .place, name: String = "京都", milestone: TrunkLabel.Milestone? = nil,
                       country: String? = nil, foil: Bool = false, photoId: String = "ph1") -> TrunkLabel {
        TrunkLabel(id: photoId, photoId: photoId, kind: kind,
                   place: .init(name: name, latin: nil, country: country), milestone: milestone, seed: 1,
                   at: "2026-11-08T00:00:00Z", foil: foil)
    }

    // MARK: 初めての反応（案 A）

    /// 新しい人の最初のいいね（直近）は印が付き、端末に控える。次に開いても同じ行のまま
    func testFirstLikeIsMarkedOnceAndKept() async throws {
        let defaults = suite()
        let first = try row("like", by: "a", t: iso(hoursAgo: 2))
        let marks = FirstReaction.resolve(rows: [first], userId: "me", now: now, defaults: defaults)
        XCTAssertEqual(marks, [first.id: .like])
        // 新しいいいねが先頭に増えても、印は最初の行のまま（一度だけ）
        let later = try row("like", by: "b", photo: "p2", t: iso(hoursAgo: 1))
        let again = FirstReaction.resolve(rows: [later, first], userId: "me", now: now, defaults: defaults)
        XCTAssertEqual(again, [first.id: .like], "控えがあるのに、別の行を「初めて」にした")
    }

    /// いいねとコメントは別々に一度ずつ
    func testLikeAndCommentAreSeparate() async throws {
        let defaults = suite()
        let like = try row("like", t: iso(hoursAgo: 5))
        let comment = try row("comment", by: "b", t: iso(hoursAgo: 3))
        let marks = FirstReaction.resolve(rows: [comment, like], userId: "me", now: now, defaults: defaults)
        XCTAssertEqual(marks[like.id], .like)
        XCTAssertEqual(marks[comment.id], .comment)
    }

    /// 一覧のいちばん古いものを「初めて」にする（新しい順の一覧の最後）
    func testOldestOfKindIsTheFirst() async throws {
        let defaults = suite()
        let newer = try row("like", by: "b", photo: "p2", t: iso(hoursAgo: 1))
        let older = try row("like", by: "a", t: iso(hoursAgo: 30))
        let marks = FirstReaction.resolve(rows: [newer, older], userId: "me", now: now, defaults: defaults)
        XCTAssertEqual(marks, [older.id: .like])
    }

    /// 7 日より前のいいねを今さら祝わない。印だけ付け、あとで新しいのが来ても祝わない（初めてではない）
    func testStaleFirstIsNotCelebratedAndNeverLater() async throws {
        let defaults = suite()
        let old = try row("like", t: iso(hoursAgo: 24 * 8))
        XCTAssertEqual(FirstReaction.resolve(rows: [old], userId: "me", now: now, defaults: defaults), [:])
        let fresh = try row("like", by: "b", photo: "p2", t: iso(hoursAgo: 1))
        XCTAssertEqual(FirstReaction.resolve(rows: [fresh, old], userId: "me", now: now, defaults: defaults), [:],
                       "初めてでないいいねを祝った")
    }

    /// サーバーは 50 件に切る。50 件の一覧は古い側が切れているかもしれないので決めない（控えも書かない）
    func testTruncatedListDoesNotDecide() async throws {
        let defaults = suite()
        var rows: [AppNotification] = []
        for i in 0..<FirstReaction.listLimit {
            rows.append(try row("like", by: "u\(i)", photo: "p\(i)", t: iso(hoursAgo: Double(i) + 1)))
        }
        XCTAssertEqual(FirstReaction.resolve(rows: rows, userId: "me", now: now, defaults: defaults), [:])
        XCTAssertNil(defaults.string(forKey: FirstReaction.key("me", .like)), "決めていないのに控えを書いた")
        // 49 件なら切れていない
        XCTAssertFalse(FirstReaction.resolve(rows: Array(rows.dropLast()), userId: "me", now: now, defaults: defaults).isEmpty)
    }

    /// 退会した人・時刻が読めない行は祝わない
    func testDeletedAndUndatedAreNotCelebrated() async throws {
        let gone = try row("like", t: iso(hoursAgo: 2), deleted: true)
        XCTAssertEqual(FirstReaction.resolve(rows: [gone], userId: "me", now: now, defaults: suite()), [:])
        let undated = try row("comment", t: "いつか")
        XCTAssertEqual(FirstReaction.resolve(rows: [undated], userId: "me", now: now, defaults: suite()), [:])
    }

    /// 入っていない・人ごとに別・退会で消える
    func testPerPersonAndRemoved() async throws {
        let defaults = suite()
        let like = try row("like", t: iso(hoursAgo: 2))
        XCTAssertEqual(FirstReaction.resolve(rows: [like], userId: nil, now: now, defaults: defaults), [:])
        XCTAssertEqual(FirstReaction.resolve(rows: [like], userId: "a", now: now, defaults: defaults), [like.id: .like])
        XCTAssertEqual(FirstReaction.resolve(rows: [like], userId: "b", now: now, defaults: defaults), [like.id: .like],
                       "別の人の控えを引き継いだ")
        AccountLocalData.remove(userId: "a", username: nil, defaults: defaults)
        XCTAssertNil(defaults.string(forKey: FirstReaction.key("a", .like)), "退会しても控えが残っている")
        XCTAssertNotNil(defaults.string(forKey: FirstReaction.key("b", .like)), "別の人の控えまで消した")
    }

    /// 同じ写真へのいいねをまとめた行に、初めての印が引き継がれる
    func testCollapsedEntryCarriesTheFirstMark() async throws {
        let older = try row("like", by: "a", t: iso(hoursAgo: 30))
        let newer = try row("like", by: "b", t: iso(hoursAgo: 1))
        let entries = NotificationText.collapse([newer, older], firstReactions: [older.id: .like])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].firstReaction, .like)
        XCTAssertNil(NotificationText.collapse([newer, older]).first?.firstReaction)
    }

    /// 言葉: 事実だけ。数・順位・連続・促す文を言わない。禁止語を使わない
    func testWordingStaysFactual() async {
        for kind in FirstReaction.Kind.allCases {
            for text in [kind.eyebrow, kind.note] {
                XCTAssertFalse(text.isEmpty)
                for banned in ["あと", "連続", "位", "撮りどき", "捨て", "共有して", "シェアして", "!", "！"] {
                    XCTAssertFalse(text.contains(banned), "「\(text)」に「\(banned)」")
                }
            }
        }
    }

    // MARK: 投稿を終えたときの一文（案 A）

    func testMilestoneFirstStatesTheFact() async {
        XCTAssertEqual(ArrivalFact.sentence(label: label(kind: .milestone, name: "京都", milestone: .first), photos: nil),
                       L("京都、はじめての1枚です", "京都 \u{2014} your very first photo"))
        XCTAssertEqual(ArrivalFact.sentence(label: label(kind: .milestone, name: "", milestone: .first), photos: nil),
                       L("はじめての1枚です", "Your very first photo"))
        XCTAssertEqual(ArrivalFact.sentence(label: label(kind: .milestone, name: "パリ", milestone: .firstCountry, country: "フランス"),
                                            photos: nil),
                       L("フランス、はじめての国です", "フランス \u{2014} your first country"))
        // 10 枚目などは数の節目なので、事実の一文は言わない（数を稼ぐ文にしない）
        XCTAssertNil(ArrivalFact.sentence(label: label(kind: .milestone, name: "京都", milestone: .posts10), photos: nil))
    }

    func testFirstInPrefectureOnlyWhenSure() async throws {
        let mine = try photo("ph1", location: "京都府 京都市")
        let osaka = try photo("o1", location: "大阪府 大阪市")
        let kyoto = label()
        let expected = L("京都、はじめての1枚です", "京都 \u{2014} your first photo here")
        XCTAssertEqual(ArrivalFact.sentence(label: kyoto, photos: [mine, osaka]), expected)
        // 同じ県のほかの写真が在れば言わない
        XCTAssertNil(ArrivalFact.sentence(label: kyoto, photos: [mine, try photo("k0", location: "京都府 宇治市")]))
        // 下書き（公開していない）は数えない
        XCTAssertEqual(ArrivalFact.sentence(label: kyoto, photos: [mine, try photo("k0", location: "京都府", published: false)]), expected)
        // 一覧が読めていない・今の写真が一覧に無い（一覧が古い）・県が読めない は言わない
        XCTAssertNil(ArrivalFact.sentence(label: kyoto, photos: nil))
        XCTAssertNil(ArrivalFact.sentence(label: kyoto, photos: [osaka]))
        XCTAssertNil(ArrivalFact.sentence(label: label(name: "どこか"), photos: [try photo("ph1", location: "どこか")]))
        // 今の写真の県はラベルの名前からも読む（撮影地が空でも、ほかに読めない写真が無ければ言える）
        XCTAssertEqual(ArrivalFact.sentence(label: kyoto, photos: [try photo("ph1", location: nil)]), expected)
        // **県が読めない公開の写真が1枚でも混じるなら言わない**（撮影地が空・英語・座標だけの写真が、実は京都かもしれない）
        XCTAssertNil(ArrivalFact.sentence(label: kyoto, photos: [mine, try photo("x", location: nil)]))
        XCTAssertNil(ArrivalFact.sentence(label: kyoto, photos: [mine, try photo("y", location: "Kyoto, Japan")]))
        XCTAssertNil(ArrivalFact.sentence(label: kyoto, photos: [mine, osaka, try photo("z", location: "35.0116, 135.7681")]))
        // 読めない写真が下書きなら数えない
        XCTAssertEqual(ArrivalFact.sentence(label: kyoto, photos: [mine, try photo("w", location: nil, published: false)]), expected)
    }

    func testSpecialLabelsGetStrongerGlow() async {
        XCTAssertTrue(ArrivalFact.isSpecial(label(kind: .milestone, milestone: .posts10)))
        XCTAssertTrue(ArrivalFact.isSpecial(label(foil: true)))
        XCTAssertFalse(ArrivalFact.isSpecial(label()))
        XCTAssertGreaterThan(TrunkStyle.glowStrongCenter, 0.22)
        XCTAssertGreaterThan(TrunkStyle.glowStrongEdge, 0.05)
    }

    /// 動きを減らす設定では待たずに全部を出す。通常は 写真 → ラベル → 一文 の順
    func testSequenceOrderAndReduceMotion() async {
        XCTAssertEqual(ArrivalSequence.firstStep(reduceMotion: true), .sentence)
        XCTAssertEqual(ArrivalSequence.firstStep(reduceMotion: false), .start)
        XCTAssertTrue(ArrivalSequence.delays(reduceMotion: true).isEmpty)
        let steps = ArrivalSequence.delays(reduceMotion: false)
        XCTAssertEqual(steps.map { $0.0 }, [.photo, .label, .sentence])
        XCTAssertEqual(steps.reduce(0) { $0 + $1.1 }, ArrivalSequence.sentenceAt, accuracy: 0.0001)
        XCTAssertLessThan(ArrivalSequence.sentenceAt, 2, "祝いが長すぎる（閉じるまで待たせない）")
        // 画面が使う判定: 動きを減らす設定では、進みが始まりのままでも全部見せる
        XCTAssertTrue(ArrivalSequence.isShown(.sentence, current: .start, reduceMotion: true))
        XCTAssertFalse(ArrivalSequence.isShown(.photo, current: .start, reduceMotion: false))
        XCTAssertTrue(ArrivalSequence.isShown(.photo, current: .label, reduceMotion: false))
        XCTAssertFalse(ArrivalSequence.isShown(.sentence, current: .label, reduceMotion: false))
    }

    /// 一覧の読み込みが呼ぶ `noteFirstReactions`: 印を model に載せ、控えで一度だけ、退会者・ログアウトでは載せない
    func testViewModelNotesFirstReactionsOnce() async throws {
        let defaults = suite()
        let model = NotificationsViewModel()
        let first = try row("like", by: "a", t: iso(hoursAgo: 2))
        model.noteFirstReactions([first], viewerId: "me", now: now, defaults: defaults)
        XCTAssertEqual(model.firstReactions, [first.id: .like])
        // 新しい行が増えても、印は最初の行のまま
        let later = try row("like", by: "b", photo: "p2", t: iso(hoursAgo: 1))
        model.noteFirstReactions([later, first], viewerId: "me", now: now, defaults: defaults)
        XCTAssertEqual(model.firstReactions, [first.id: .like])
        // 別の人（別の端末の控え）は別に決まる。ログインしていなければ載せない
        let other = NotificationsViewModel()
        other.noteFirstReactions([first], viewerId: nil, now: now, defaults: defaults)
        XCTAssertTrue(other.firstReactions.isEmpty)
        // 一覧が50件に届いていれば決めない
        let many = try (0..<FirstReaction.listLimit).map { try row("like", by: "u\($0)", t: iso(hoursAgo: Double($0) + 1)) }
        let full = NotificationsViewModel()
        full.noteFirstReactions(many, viewerId: "someone", now: now, defaults: defaults)
        XCTAssertTrue(full.firstReactions.isEmpty)
    }

    /// 読み上げの文: 印が付く行は印の言葉が先に来る。未読の言葉も残る
    func testSpokenLabelCarriesFirstMark() async {
        XCTAssertEqual(NotificationText.spokenLabel("Aki liked", unread: false, first: nil), "Aki liked")
        XCTAssertEqual(NotificationText.spokenLabel("Aki liked", unread: true, first: nil), L("未読、", "Unread, ") + "Aki liked")
        let spoken = NotificationText.spokenLabel("Aki liked", unread: true, first: .like)
        XCTAssertTrue(spoken.hasPrefix(FirstReaction.Kind.like.eyebrow + "。" + FirstReaction.Kind.like.note))
        XCTAssertTrue(spoken.hasSuffix(L("未読、", "Unread, ") + "Aki liked"))
    }

    // MARK: 画面のつなぎ（消したら落ちる）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    func testScreensAreWired() async throws {
        let arrived = try source("Features/Trunk/LabelArrivedView.swift")
        XCTAssertTrue(arrived.contains("@Environment(\\.accessibilityReduceMotion)"), "動きを減らす設定を見ていない")
        XCTAssertTrue(arrived.contains(".sensoryFeedback(.impact(weight: .light), trigger: landed)"), "触覚が無い")
        XCTAssertTrue(arrived.contains("ArrivalFact.sentence("), "事実の一文につながっていない")
        XCTAssertTrue(arrived.contains("ArrivalSequence.isShown("), "動きの順序（ArrivalSequence）を画面が使っていない")
        XCTAssertTrue(arrived.contains("ArrivalSequence.delays("), "動きの待ち（ArrivalSequence）を画面が使っていない")
        XCTAssertTrue(arrived.contains("@State private var sentence"), "一文を1回だけ決めて持っていない")
        XCTAssertTrue(arrived.contains("TrunkStyle.glow(width: 340, height: 250, strong: special)"), "節目・箔押しの光が強くならない")
        XCTAssertTrue(arrived.contains("ShareLink"), "共有の副ボタンが無い")
        XCTAssertTrue(arrived.contains("arrival.shareable"), "公開でない投稿にも共有が出る")
        XCTAssertTrue(arrived.contains("minHeight: WebTheme.minTapTarget"), "共有の当たりが 44pt でない")
        let list = try source("Features/Notifications/NotificationsView.swift")
        XCTAssertTrue(list.contains("firstReactions: model.firstReactions"), "一覧が初めての印を受けていない")
        XCTAssertTrue(list.contains("FirstReaction.resolve("), "初めての判定につながっていない")
        XCTAssertTrue(list.contains("noteFirstReactions(page.items, viewerId: viewerId)"), "読み込みが初めての判定を呼んでいない")
        XCTAssertTrue(list.contains("entry.firstReaction"), "行に初めての印が出ない")
        let upload = try source("Features/Upload/UploadViewModel.swift")
        XCTAssertTrue(upload.contains("photoURL: $0.photoURL, shareable: $0.shareable"), "投稿の写真・共有可が届いた画面に渡らない")
        XCTAssertTrue(try source("Core/Storage/AccountLocalData.swift").contains("FirstReaction.removeData("), "退会で控えを消していない")
    }

    // MARK: 季節の家具（案 B）

    func testRoomCountsAutumnAndSeasons() async throws {
        func p(_ id: String, _ date: String?) throws -> Photo {
            var json: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg"]
            if let date { json["date"] = date }
            return try JSONDecoder().decode(Photo.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let r = CamperRoomCounting.stats([try p("a", "2025:10:02 10:00:00"), try p("b", "2025:11:30 10:00:00"),
                                          try p("c", "2025:04:02 10:00:00"), try p("d", nil), try p("e", "2025:12:25 10:00:00")])
        XCTAssertEqual(r.autumnShots, 2)
        XCTAssertEqual(r.springShots, 1)
        XCTAssertEqual(r.seasonsShot, 3, "春・秋・冬。日付の無い写真は季節に数えない")
        let none = CamperRoomCounting.stats([try p("x", nil)])
        XCTAssertEqual(none.seasonsShot, 0)
        XCTAssertEqual(none.autumnShots, 0)
        let s = CamperStats()
        XCTAssertEqual(CamperRoomUnlock.autumn(2).progress(s, r).have, 2)
        XCTAssertTrue(CamperRoomUnlock.autumn(2).isMet(s, r))
        XCTAssertFalse(CamperRoomUnlock.autumn(3).isMet(s, r))
        XCTAssertTrue(CamperRoomUnlock.seasons(3).isMet(s, r))
        XCTAssertFalse(CamperRoomUnlock.seasons(4).isMet(s, r))
        XCTAssertEqual(CamperRoomUnlock.seasons(3).fraction(s, r), 1)
        XCTAssertFalse(CamperRoomUnlock.autumn(4).condition.isEmpty)
        XCTAssertFalse(CamperRoomUnlock.seasons(4).condition.isEmpty)
    }

    /// 家具の図鑑に、秋と季節をまたぐ条件が「もう一つの道」として入っている。同じ日に撮る条件は、どれも残っている。
    /// 2026-11-11: 組み合わせの家具を消したので、板の三枚続きの額・盆栽・ケーキ台に付け直した
    func testVarietyUsesTheNewSeasonalUnlocks() async {
        let unlocks = CamperRoomCatalog.all.map(\.unlock)
        func either(_ u: CamperRoomUnlock, _ f: (CamperRoomUnlock) -> Bool) -> Bool {
            if case let .either(a, b) = u { return f(a) || f(b) }
            return false
        }
        XCTAssertTrue(unlocks.contains { either($0) { if case .autumn = $0 { return true } else { return false } } }, "秋の条件の家具が無い")
        XCTAssertTrue(unlocks.contains { either($0) { if case .seasons = $0 { return true } else { return false } } }, "季節をまたぐ条件の家具が無い")
        func sameDay(_ u: CamperRoomUnlock) -> Bool {
            if case .sameDay = u { return true }
            if case let .either(a, _) = u, case .sameDay = a { return true }
            return false
        }
        XCTAssertTrue(unlocks.contains(where: sameDay), "同じ日の条件が全部消えた")
        XCTAssertTrue(CamperRoomUnlock.autumn(4).isAvailable)
        XCTAssertTrue(CamperRoomUnlock.seasons(3).isAvailable)
    }

    /// **互換**: 前の条件（同じ日に n 枚）だけを満たす人は、どの家具も持ち続ける。新しい道は足すだけ
    func testOldSameDayUnlockStillHoldsAndNewPathAdds() async {
        let s = CamperStats()
        var oldOnly = CamperRoomStats()
        oldOnly.sameDayMax = 100
        var newOnly = CamperRoomStats()
        newOnly.autumnShots = 100
        newOnly.seasonsShot = 4
        var checked = 0
        // 前の条件（2026-11-11 に道を足す前の、板の条件）。`.either` の先に、そのまま残っていること
        let before: [String: CamperRoomUnlock] = [
            "photo_frame.triptych": .sameDay(30),
            "plant_pot.bonsai": .topic(.temple, 4),
            "tea.cake_stand": .spring(15),
        ]
        // 前の条件だけを満たす人（同じ日 100 枚・寺 100 枚・春 100 枚。秋と季節は 0）
        oldOnly.springShots = 100
        oldOnly.topics[.temple] = 100
        for f in CamperRoomCatalog.all {
            guard case let .either(old, new) = f.unlock else { continue }
            checked += 1
            guard let was = before[f.id] else { XCTFail("\(f.id): 前の条件が分からない道が足されている"); continue }
            XCTAssertEqual(old, was, "\(f.id): 前の条件が先に残っていない")
            XCTAssertTrue(f.unlock.isMet(s, oldOnly), "\(f.id): 前の条件だけ満たす人が持てなくなる")
            XCTAssertTrue(f.unlock.isMet(s, newOnly), "\(f.id): 新しい道で持てない（\(new)）")
            XCTAssertFalse(f.unlock.isMet(s, CamperRoomStats()), "\(f.id): 何も満たさないのに持てる")
            XCTAssertEqual(f.unlock.fraction(s, oldOnly), 1)
        }
        XCTAssertEqual(checked, before.count, "新しい道を足した家具が足りない")
        // 同じ日の条件は、満たし方が増えただけで残っている（三枚続きの額）
        let sameDayStill = CamperRoomCatalog.all.filter { f in
            if case .sameDay = f.unlock { return true }
            if case let .either(a, _) = f.unlock, case .sameDay = a { return true }
            return false
        }.count
        XCTAssertGreaterThan(sameDayStill, 0)
        // 満たしていない間は、進みの大きい方を見せる
        var part = CamperRoomStats()
        part.sameDayMax = 3
        part.autumnShots = 2
        let u = CamperRoomUnlock.either(.sameDay(6), .autumn(4))
        XCTAssertEqual(u.fraction(s, part), 0.5, accuracy: 0.0001)
        XCTAssertFalse(u.isMet(s, part))
        XCTAssertFalse(u.condition.isEmpty)
    }
}
