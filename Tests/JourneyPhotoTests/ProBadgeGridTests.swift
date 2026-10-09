import XCTest
@testable import JourneyPhoto

/// 名前の横の画面の格子・棚・お知らせのメダルの絵、Pro の人の「PRO 限定」の段、
/// 人のページのフォロー一覧の丸（2026-10-09）
final class ProBadgeGridTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func day(_ y: Int, _ m: Int, _ d: Int = 15) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tokyo
        return cal.date(from: c)!
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// `start` から `end` までの文字（1つの関数・型の中だけを見る）
    private func slice(_ text: String, from start: String, to end: String) throws -> String {
        let a = try XCTUnwrap(text.range(of: start), start)
        let b = try XCTUnwrap(text.range(of: end, range: a.upperBound..<text.endIndex), end)
        return String(text[a.lowerBound..<b.lowerBound])
    }

    // MARK: - 1. 格子は大きい絵を縮めて出す

    /// 🔴 名前の横の画面の2つの格子・棚の「名前の横に飾る」・お知らせのメダルは `-s` を引かず、
    /// 大きい絵を `RasterBadgeArt`（名前の横と同じ縮め方）で出す
    func testGridsUseLargeArtThroughTheRaster() throws {
        let nameSide = try source("Features/Profile/NameSideBadgeView.swift")
        let owned = try slice(nameSide, from: "private func badgeCell", to: "private var noneCell")
        XCTAssertFalse(owned.contains("smallImage"))
        XCTAssertTrue(owned.contains("RasterBadgeArt(image: BadgeCatalog.largeImage("))
        let locked = try slice(nameSide, from: "private func lockedCell", to: "private var shelfLink")
        XCTAssertFalse(locked.contains("smallImage"))
        XCTAssertTrue(locked.contains("RasterBadgeArt(image: item.image"))

        let shelf = try source("Features/Profile/BadgeShelfView.swift")
        let decorate = try slice(shelf, from: "private func decorateSection", to: "Text(L(\"変える\"")
        XCTAssertFalse(decorate.contains("smallImage"))
        XCTAssertTrue(decorate.contains("RasterBadgeArt(image: BadgeCatalog.largeImage(badge.key, tier: badge.tier), side: 40)"))

        let notes = try source("Features/Notifications/NotificationsView.swift")
        let avatar = try slice(notes, from: "private var avatar", to: "private var personAvatar")
        XCTAssertFalse(avatar.contains("smallImage"))
        XCTAssertTrue(avatar.contains("RasterBadgeArt(image: BadgeCatalog.largeImage(key, tier: notification.tier ?? 1), side: 44)"))
    }

    /// 名前の横（`NameBadgeImage`）も同じ部品を通す（写しを作らない）
    func testNameBadgeImageSharesTheRasterView() throws {
        let marks = try source("Features/Common/NameMarks.swift")
        let image = try slice(marks, from: "struct NameBadgeImage", to: "struct RasterBadgeArt")
        XCTAssertTrue(image.contains("RasterBadgeArt(image: BadgeCatalog.nameSideImage("))
        let code = image.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        XCTAssertFalse(code.contains { $0.contains("NameBadgeRaster") || $0.contains(".task") },
                       "縮める仕組みは RasterBadgeArt の1か所だけ")
        XCTAssertEqual(marks.components(separatedBy: "NameBadgeRaster.shared(named:").count - 1, 1)
    }

    // MARK: - 作り直しの合図・鍵の一致・できるまで透明・同じ鍵をまとめる（確かめ役の指摘 2026-10-09）

    /// 作り直しの合図は絵の名前と画素の数を両方含む（倍率・文字の大きさ・絵が替われば作り直す）
    func testTaskIDCarriesImageAndPixels() {
        let a = RasterBadgeArt.taskID(image: "medal-night-2", pixels: 168)
        XCTAssertEqual(a, "medal-night-2@168")
        XCTAssertNotEqual(a, RasterBadgeArt.taskID(image: "medal-night-2", pixels: 112), "倍率が替われば作り直す")
        XCTAssertNotEqual(a, RasterBadgeArt.taskID(image: "medal-night-3", pixels: 168), "絵が替われば作り直す")
        XCTAssertEqual(RasterBadgeArt.taskID(image: "medal-night-2", pixels: nil), "medal-night-2")
        XCTAssertTrue(RasterBadgeArt.matches(renderedKey: a, key: a))
        XCTAssertFalse(RasterBadgeArt.matches(renderedKey: "medal-night-2@112", key: a), "前の倍率の絵は使わない")
        XCTAssertFalse(RasterBadgeArt.matches(renderedKey: nil, key: a))
    }

    /// 🔴 `RasterBadgeArt` の作り直しと鍵の確かめ・できるまで透明を縛る
    func testRasterBadgeArtRebuildsByKeyAndStaysClearUntilReady() throws {
        let marks = try source("Features/Common/NameMarks.swift")
        let view = try slice(marks, from: "struct RasterBadgeArt", to: "/// マイページの名前の行の読み上げ")
        XCTAssertTrue(view.contains("let key = Self.taskID(image: name, pixels: pixels)"))
        XCTAssertTrue(view.contains(".task(id: key) {"), "鍵が替われば作り直す（`.task` だけだと前の絵のまま）")
        let taskLines = view.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(".task") }
        XCTAssertEqual(taskLines.map { $0.trimmingCharacters(in: .whitespaces) }, [".task(id: key) {"])
        XCTAssertTrue(view.contains("guard let pixels, !Self.matches(renderedKey: rendered?.key, key: key)"))
        XCTAssertTrue(view.contains("if let rendered, Self.matches(renderedKey: rendered.key, key: key)"),
                      "前の鍵で作った絵を出さない")
        XCTAssertFalse(view.contains("if let rendered {"))
        // できるまでは大きい絵を描かない（透明の枠だけ）
        XCTAssertFalse(view.contains("Image(name)"), "大きい絵を画面の処理で開かない")
        XCTAssertTrue(view.contains("Color.clear\n            .frame(width: side, height: side)"))
        XCTAssertTrue(view.contains("return nil"))
        XCTAssertTrue(view.contains("await NameBadgeRaster.shared(named: name, pixels: pixels)"))
    }

    /// 同じ鍵を同時に頼んでも1回だけ作る。違う鍵は別に作る。終わったら忘れる
    func testInflightTasksCoalesceSameKey() async {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func bump() { lock.lock(); n += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return n }
        }
        let tasks = InflightTasks<Int>()
        let made = Counter()
        let make: @Sendable () -> Int = {
            made.bump()
            Thread.sleep(forTimeInterval: 0.2)
            return 7
        }
        async let a = tasks.value(for: "medal@168", make: make)
        async let b = tasks.value(for: "medal@168", make: make)
        async let c = tasks.value(for: "medal@168", make: make)
        let values = await [a, b, c]
        XCTAssertEqual(values, [7, 7, 7])
        XCTAssertEqual(made.value, 1, "同じ鍵は1回だけ作る")
        let runningAfter = await tasks.runningCount
        XCTAssertEqual(runningAfter, 0, "終わったら忘れる")
        _ = await tasks.value(for: "medal@112", make: make)
        XCTAssertEqual(made.value, 2, "違う鍵は別に作る")
    }

    /// `NameBadgeRaster.shared` は作る仕事をまとめる口を通す
    func testRasterSharedGoesThroughInflight() throws {
        let raster = try source("Features/Profile/NameBadgeRaster.swift")
        let shared = try slice(raster, from: "static func shared(named", to: "private static let inflight")
        XCTAssertTrue(shared.contains("await inflight.value(for: cacheKey(image: name, pixels: pixels))"))
    }

    /// 🔴 「PRO 限定」の絵: サポーター・季節の章は大きい絵、機能の章（大きい絵が無い）は `-s`
    func testLockedItemsUseLargeArtExceptFeatures() {
        let items = ProChapters.lockedItems(owned: BadgeSet(), now: day(2026, 10))
        XCTAssertEqual(items.map(\.image), [
            "medal-supporter",
            "medal-pro-spring-2027", "medal-pro-summer-2027", "medal-pro-autumn-2026", "medal-pro-winter-2026",
            "medal-pro-dawn-s", "medal-pro-compose-s", "medal-pro-summit-s",
        ])
        for item in items {
            if case .feature = item.kind {
                XCTAssertTrue(item.image.hasSuffix("-s"), item.id)
            } else {
                XCTAssertFalse(item.image.hasSuffix("-s"), item.id)
            }
        }
    }

    /// 縮める先の画素: いちばん大きい 56pt × 3倍 = 168px が上限（256px）に収まる。
    /// 元の大きい絵（520px 以上）より小さいので、縮めるだけで引き伸ばさない
    func testRasterFitsTheLargestGrid() {
        XCTAssertEqual(NameSideChoice.ownedArtSide, 56, "板: 持っているバッジは 56pt（行の並びを変えない）")
        XCTAssertEqual(NameSideChoice.lockedArtSide, 48, "板: PRO 限定は 48pt")
        XCTAssertEqual(NameBadgeRaster.pixelSide(points: NameSideChoice.ownedArtSide, scale: 3), 168)
        XCTAssertEqual(NameBadgeRaster.pixelSide(points: NameSideChoice.lockedArtSide, scale: 3), 144)
        XCTAssertEqual(NameBadgeRaster.pixelSide(points: 44, scale: 3), 132)
        XCTAssertEqual(NameBadgeRaster.pixelSide(points: 40, scale: 3), 120)
        XCTAssertGreaterThanOrEqual(NameBadgeRaster.maxPixels, 168)
        XCTAssertLessThan(168, 520)
    }

    /// 円の割合は大きい絵と小さい絵で同じ（測った値）——絵を替えても円の大きさは変わらない
    func testDiscRatioUnchangedBySwitchingArt() {
        XCTAssertEqual(BadgeCatalog.discRatio("prefectures"), 0.984)
        XCTAssertEqual(BadgeCatalog.discRatio("supporter"), 0.984)
        XCTAssertEqual(BadgeCatalog.discRatio("earlyUser"), 0.715)
        XCTAssertEqual(BadgeCatalog.discRatio("proAutumn2026"), 0.91)
    }

    // MARK: - 2. Pro の人の「PRO 限定」の一行

    func testProWaitingNote() throws {
        XCTAssertEqual(NameSideChoice.proWaitingNote,
                       "Pro の間に、季節ごとに届きます。届いたら上の「持っているバッジ」から選べます")
        let nameSide = try source("Features/Profile/NameSideBadgeView.swift")
        let section = try slice(nameSide, from: "private var proSection", to: "private func lockedCell")
        // Pro の人にだけ出す。Pro でない人の「Pro で集める」はそのまま
        XCTAssertTrue(section.contains("if profile.isPro {\n                // Pro の人には"))
        XCTAssertTrue(section.contains("Text(NameSideChoice.proWaitingNote)"))
        XCTAssertTrue(section.contains(".font(.caption)"), "本文系の最小 12pt")
        XCTAssertTrue(section.contains("if !profile.isPro {"))
        XCTAssertTrue(section.contains("nameSide.proCollect"))
    }

    // MARK: - 3. 押したら届く時期

    /// 🔴 Pro の人が押すと届く時期の知らせ（以前は `.disabled` で無反応）。読み上げも同じ文
    func testLockedCellTellsWhenItArrives() throws {
        let nameSide = try source("Features/Profile/NameSideBadgeView.swift")
        let cell = try slice(nameSide, from: "private func lockedCell", to: "private var shelfLink")
        XCTAssertFalse(cell.contains(".disabled(!locked)"), "Pro の人にも押せる")
        XCTAssertTrue(cell.contains("let note = ProChapters.arrivalNote(item)"))
        XCTAssertTrue(cell.contains("toasts.show(note, kind: .info)"))
        XCTAssertTrue(cell.contains("UIAccessibility.post(notification: .announcement, argument: note)"))
        XCTAssertTrue(cell.contains(": note)"), "読み上げのヒントも同じ文")
        // Pro でない人は今までどおり Pro の案内
        XCTAssertTrue(cell.contains("if locked {\n                openPaywall()"))
        // シートの上でも知らせが見える
        XCTAssertTrue(nameSide.contains("ToastOverlay().padding(.bottom, 110)"))
    }

    /// 季節の章は日本時間の始まりの月（冬は12月の年）。始まっていれば「まもなく」
    func testArrivalNoteForSeasons() {
        let items = ProChapters.lockedItems(owned: BadgeSet(), now: day(2026, 10))
        func note(_ id: String, _ now: Date) -> String? {
            items.first { $0.id == id }.map { ProChapters.arrivalNote($0, now: now, timeZone: tokyo) }
        }
        XCTAssertEqual(note("proWinter2026", day(2026, 10)), "2026年12月から届きます")
        XCTAssertEqual(note("proSpring2027", day(2026, 10)), "2027年3月から届きます")
        XCTAssertEqual(note("proSummer2027", day(2026, 10)), "2027年6月から届きます")
        XCTAssertEqual(note("proAutumn2026", day(2026, 10)), "いまの季節の章です。まもなく届きます")
        // 冬 2026 は 2027年1月も「いまの季節」（12月の年の鍵）
        XCTAssertEqual(note("proWinter2026", day(2027, 1)), "いまの季節の章です。まもなく届きます")
        XCTAssertEqual(note("proWinter2026", day(2026, 11, 30)), "2026年12月から届きます")
        // 日本時間で見る: 世界時の 11/30 15:00 は日本の 12/1 0:00
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let edge = utc.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 15))!
        XCTAssertEqual(note("proWinter2026", edge), "いまの季節の章です。まもなく届きます")
        XCTAssertEqual(ProChapters.startMonth(.spring), 3)
        XCTAssertEqual(ProChapters.startMonth(.summer), 6)
        XCTAssertEqual(ProChapters.startMonth(.autumn), 9)
        XCTAssertEqual(ProChapters.startMonth(.winter), 12)
    }

    func testArrivalNoteForSupporterAndFeatures() {
        let items = ProChapters.lockedItems(owned: BadgeSet(), now: day(2026, 10))
        for item in items {
            let text = ProChapters.arrivalNote(item, now: day(2026, 10), timeZone: tokyo)
            switch item.kind {
            case .supporter: XCTAssertEqual(text, "まもなく届きます", "Pro の人にしか出ない一言なので「Pro になると」は言わない")
            case .feature: XCTAssertEqual(text, "これから配ります", item.id)
            case .season: XCTAssertFalse(text.isEmpty)
            }
        }
    }

    /// 知らせの印: 案内には ✓ も △ も付けない
    func testInfoToastSymbol() {
        XCTAssertEqual(ToastOverlay.symbol(.info), "info.circle.fill")
        XCTAssertEqual(ToastOverlay.symbol(.success), "checkmark.circle.fill")
        XCTAssertEqual(ToastOverlay.symbol(.failure), "exclamationmark.triangle.fill")
    }

    // MARK: - 4. 人のページのフォロー一覧の丸を消した

    /// 🔴 見出しの丸（人と＋の印）は出さない。一覧へは数の札から開く
    func testUserProfileHasNoFollowListCircle() throws {
        let profile = try source("Features/Profile/UserProfileView.swift")
        XCTAssertFalse(profile.contains("followListButton"))
        XCTAssertFalse(profile.contains("person.badge.plus"))
        let countLink = try slice(profile, from: "private func countLink", to: "private func countText")
        XCTAssertTrue(countLink.contains("FollowListView(userId: userId, kind: kind)"), "数の札の口は残す")
        XCTAssertEqual(profile.components(separatedBy: "FollowListView(").count - 1, 1, "一覧への口は数の札だけ")
    }

    // MARK: - 見本の Pro（Debug のみ）

    func testPreviewProOnlyForThePreviewUser() throws {
        let defaults = UserDefaults.standard
        defaults.set("me", forKey: PreviewSession.defaultsKey)
        defaults.set(true, forKey: PreviewSession.proKey)
        defer {
            defaults.removeObject(forKey: PreviewSession.defaultsKey)
            defaults.removeObject(forKey: PreviewSession.proKey)
        }
        let me = try JSONDecoder.api.decode(UserProfile.self, from: Data(#"{"userId":"me","displayName":"丸田"}"#.utf8))
        XCTAssertTrue(me.isPro)
        let other = try JSONDecoder.api.decode(UserProfile.self,
                                               from: Data(#"{"userId":"u2","displayName":"他の人"}"#.utf8))
        XCTAssertFalse(other.isPro, "見本の Pro は本人だけ")
        defaults.removeObject(forKey: PreviewSession.proKey)
        XCTAssertFalse(me.isPro)
    }
}
