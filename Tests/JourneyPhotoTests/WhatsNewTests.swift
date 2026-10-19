import XCTest
@testable import JourneyPhoto

/// 「新しくなったこと」（2026-10-04）。新しいインストールには出さない・更新して初めての起動で1回だけ・
/// 2回目は出さない・同梱の JSON が読める。
@MainActor
final class WhatsNewTests: XCTestCase {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "whatsnew-\(UUID().uuidString)")!
    }

    private func release(_ version: String) -> WhatsNew.Release {
        WhatsNew.Release(version: version, items: [
            WhatsNew.Item(symbol: "star", title: .init(ja: "題 \(version)", en: "Title"),
                          detail: .init(ja: "説明", en: "Detail"), destination: nil),
        ])
    }

    // MARK: - 出すかどうか

    /// 🔴 **新しくインストールした人には出さない**（見た版も規約の同意も無い）
    func testFreshInstallDoesNotShow() async {
        let d = defaults()
        let gate = WhatsNewGate(defaults: d, current: "1.0.67", releases: [release("1.0.67")])
        XCTAssertFalse(gate.shouldPresent)
        // いまの版を覚える（次の更新で「前から使っていた人」として出せるように）
        XCTAssertEqual(d.string(forKey: WhatsNewGate.seenKey), "1.0.67")
    }

    /// 新しいインストールの次の起動（規約に同意した後）でも出さない
    func testFreshInstallSecondLaunchDoesNotShow() async {
        let d = defaults()
        _ = WhatsNewGate(defaults: d, current: "1.0.67", releases: [release("1.0.67")])
        d.set(1, forKey: WhatsNewGate.consentKey)
        XCTAssertFalse(WhatsNewGate(defaults: d, current: "1.0.67", releases: [release("1.0.67")]).shouldPresent)
    }

    /// 🔴 **この仕組みより前の版から更新した人には出す**（見た版は無いが、規約に同意済み）
    func testUpdateFromBeforeThisFeatureShowsOnce() async {
        let d = defaults()
        d.set(1, forKey: WhatsNewGate.consentKey)
        let gate = WhatsNewGate(defaults: d, current: "1.0.67", releases: [release("1.0.67"), release("1.0.50")])
        XCTAssertTrue(gate.shouldPresent)
        // 何版前から来たか分からないので、一番新しい版だけ
        XCTAssertEqual(gate.pending.map(\.version), ["1.0.67"])
        gate.markSeen()
        XCTAssertFalse(gate.shouldPresent)
        XCTAssertEqual(d.string(forKey: WhatsNewGate.seenKey), "1.0.67")
    }

    /// 🔴 **2回目は出さない**（出した版を覚えている）
    func testSecondLaunchAfterSeeingDoesNotShow() async {
        let d = defaults()
        d.set(1, forKey: WhatsNewGate.consentKey)
        WhatsNewGate(defaults: d, current: "1.0.67", releases: [release("1.0.67")]).markSeen()
        XCTAssertFalse(WhatsNewGate(defaults: d, current: "1.0.67", releases: [release("1.0.67")]).shouldPresent)
    }

    /// 前に見た版より後の分だけ出す。飛ばして更新した人には、飛ばした版の分も新しい順に
    func testUpdateShowsReleasesAfterSeenVersion() async {
        let d = defaults()
        d.set("1.0.9", forKey: WhatsNewGate.seenKey)
        let gate = WhatsNewGate(defaults: d, current: "1.0.12",
                                releases: WhatsNew.decode(json(["1.0.9", "1.0.10", "1.0.12"])))
        // 数の比較（文字で比べると "1.0.10" < "1.0.9" になる）
        XCTAssertEqual(gate.pending.map(\.version), ["1.0.12", "1.0.10"])
    }

    /// 版が変わっても新しい項目が無ければ出さない（覚えて終わり）
    func testUpdateWithoutNewItemsDoesNotShow() async {
        let d = defaults()
        d.set("1.0.67", forKey: WhatsNewGate.seenKey)
        let gate = WhatsNewGate(defaults: d, current: "1.0.68", releases: [release("1.0.67")])
        XCTAssertFalse(gate.shouldPresent)
        XCTAssertEqual(d.string(forKey: WhatsNewGate.seenKey), "1.0.68")
    }

    func testVersionComparisonIsNumeric() async {
        XCTAssertTrue(WhatsNew.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertTrue(WhatsNew.isNewer("1.1", than: "1.0.99"))
        XCTAssertFalse(WhatsNew.isNewer("1.0.0", than: "1.0"))
        XCTAssertFalse(WhatsNew.isNewer("1.0.5", than: "1.0.5"))
    }

    // MARK: - JSON

    private func json(_ versions: [String]) -> Data {
        let releases = versions.map {
            #"{"version":"\#($0)","items":[{"symbol":"star","title":{"ja":"a","en":"b"},"detail":{"ja":"c","en":"d"}}]}"#
        }
        return Data(#"{"releases":[\#(releases.joined(separator: ","))]}"#.utf8)
    }

    /// 知らない行き先は説明だけにする（古いアプリが新しい JSON を読んでも落ちない）・空の版は捨てる
    func testDecodeIsLenient() async {
        let data = Data(#"""
        {"releases":[
          {"version":"2.0.0","items":[]},
          {"version":"1.0.1","items":[
            {"symbol":"map","title":{"ja":"地図","en":"Map"},"detail":{"ja":"説明","en":"Detail"},"destination":"map"},
            {"symbol":"star","title":{"ja":"星","en":"Star"},"detail":{"ja":"説明","en":"Detail"},"destination":"somewhere-new"}
          ]}
        ]}
        """#.utf8)
        let releases = WhatsNew.decode(data)
        XCTAssertEqual(releases.map(\.version), ["1.0.1"])
        XCTAssertEqual(releases.first?.items.map(\.destination), [.map, nil])
        XCTAssertEqual(WhatsNew.decode(Data("not json".utf8)), [])
    }

    /// 🔴 **同梱の `WhatsNew.json` が読めて、版ごとの項目がそろっている**（壊れると黙って何も出なくなる）
    func testBundledJSONDecodes() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/WhatsNew.json"))
        let releases = WhatsNew.decode(data)
        XCTAssertEqual(releases.map(\.version), ["1.1.18", "1.1.16", "1.1.15", "1.1.14", "1.0.82", "1.0.73", "1.0.67"])
        // 版に重複が無い（履歴の区切りと「見た版」の比べ方が版で1つに決まる前提）
        let versions = releases.map(\.version)
        XCTAssertEqual(Set(versions).count, versions.count, "WhatsNew.json の版が重複している")
        // 1.1.18（2026-10-19）: 写真で作るキャンプ場・写真で作るキャンピングカー・アイコンとカバー（後の2つは 1.1.17 で入ったが知らせが無かった）
        let camp = try XCTUnwrap(releases.first)
        XCTAssertEqual(camp.items.map(\.title.ja), ["写真で作るキャンプ場", "写真で作るキャンピングカー", "アイコンとカバーを選びやすく"])
        XCTAssertEqual(camp.items.map(\.symbol), ["tent", "bus", "person.crop.circle"])
        XCTAssertEqual(camp.items.compactMap(\.destination), [.mypage, .mypage, .mypage])
        XCTAssertEqual(camp.date, WhatsNew.Day(year: 2026, month: 10, day: 19))
        XCTAssertTrue(camp.items[1].detail.ja.contains("とおまわり号"), "キャンピングカーの名前を言っていない")
        // 1.1.16（2026-10-18・札 #305 #306）: トランクの部品の付き方・特別な券面の裏・呼び名「すれちがい乗車券」
        let upcoming = releases[1]
        XCTAssertEqual(upcoming.items.map(\.title.ja), ["トランクの部品がきれいに付く", "特別な券面は裏まで", "すれちがい乗車券"])
        XCTAssertEqual(upcoming.items.map(\.symbol), ["suitcase", "sparkles", "ticket"])
        XCTAssertEqual(upcoming.items.compactMap(\.destination), [.mypage])
        XCTAssertEqual(upcoming.date, WhatsNew.Day(year: 2026, month: 10, day: 18))
        XCTAssertTrue(upcoming.items[2].detail.ja.contains("設定の「すれちがい乗車券」"), "設定の場所を言っていない")
        // 1.1.15（2026-10-18）: トランクを回す面・ふたを開ける・人のトランク・見せる設定・自分の旅の手荷物タグ
        let next = releases[2]
        XCTAssertEqual(next.items.map(\.title.ja),
                       ["トランクを回すと裏も横も見える", "トランクを開けて中を見る", "人のトランクを見る",
                        "トランクを見せるか選べる", "手荷物タグに自分の旅"])
        XCTAssertEqual(next.items.map(\.symbol), ["rotate.3d", "archivebox", "person.2", "eye", "tag"])
        XCTAssertEqual(next.items.compactMap(\.destination), [.mypage, .mypage])
        XCTAssertEqual(next.date, WhatsNew.Day(year: 2026, month: 10, day: 18))
        for item in next.items {
            XCTAssertFalse(item.detail.ja.contains("捨て"), item.title.ja)
        }
        // 1.1.14（2026-10-18）: 乗車券・Pro の券面・重ねて撮るが無料・旅のトランク・構図の作例写真・
        // 横長の作例の向き（#289）・撮影地の位置の切り替え（#290）・季節のスポットの日替わり・お知らせの履歴
        let shipped = releases[3]
        XCTAssertEqual(shipped.items.map(\.title.ja),
                       ["わたしの乗車券", "Pro の特別な券面", "重ねて撮るが無料に", "旅のトランク", "構図に作例写真",
                        "横長の作例は横向きに重ねる", "撮影地の位置を付けるか選べる", "季節の撮影スポットが日替わりに",
                        "お知らせの履歴"])
        XCTAssertEqual(shipped.items.compactMap(\.destination), [.map, .mypage, .map, .home])
        // 1.0.82: Pro。始まったことを先頭に（入口は設定なので行き先は無い）
        let latest = releases[4]
        XCTAssertEqual(latest.items.count, 4)
        XCTAssertEqual(latest.items.first?.title.ja, "Journey Photo Pro がはじまりました")
        XCTAssertNil(latest.items.first?.destination)
        XCTAssertEqual(latest.items.compactMap(\.destination), [.map, .mypage])
        // 🔴 版は「Pro が入って出る次の Actions の版」。1.0.79（Pro 無し）に続き、1.0.80・1.0.81 も
        // Pro 無しで TestFlight に出た（タグ testflight/1.0.80・1.0.81）。項目が 1.0.80 のままだと、
        // それらを使った人は「見た版 = 1.0.80 / 1.0.81」で、上げても Pro の知らせが出なかった
        // （1.0.82 の版に入っていた中身＝1.0.82 までの項目で見る。`pending` は今の版を上限にしないので、
        // 後の版の項目を足した今の JSON をそのまま渡すと 1.1.14 も混ざる——実際の 1.0.82 には入っていない）
        let bundledIn1082 = releases.filter { !WhatsNew.isNewer($0.version, than: "1.0.82") }
        for seen in ["1.0.79", "1.0.80", "1.0.81"] {
            XCTAssertEqual(WhatsNew.pending(releases: bundledIn1082, seen: seen, current: "1.0.82", usedBefore: true)
                .map(\.version), ["1.0.82"], "見た版 \(seen)")
        }
        // 1.0.73: メダル。期限のある初期ユーザー章を先頭に
        let medals = releases[5]
        XCTAssertEqual(medals.items.count, 4)
        XCTAssertEqual(medals.items.first?.title.ja, "初期ユーザー章を贈ります")
        XCTAssertEqual(medals.items.compactMap(\.destination), [.mypage, .mypage])
        let previous = releases[6]
        XCTAssertEqual(previous.items.count, 8)
        XCTAssertEqual(previous.items.first?.title.ja, "撮影スポットに作例写真")
        XCTAssertEqual(previous.items.compactMap(\.destination), [.map, .search, .home, .mypage, .mypage])
        for item in releases.flatMap(\.items) {
            XCTAssertFalse(item.title.en.isEmpty || item.detail.en.isEmpty || item.detail.ja.isEmpty, item.title.ja)
            XCTAssertFalse(item.symbol.isEmpty, item.title.ja)
        }
    }

    // MARK: - 日付と履歴（2026-10-18 owner「過去の履歴を見れるようにしたい」）

    private func dated(_ version: String, _ date: String?) -> String {
        let field = date.map { #","date":"\#($0)""# } ?? ""
        return #"{"version":"\#(version)"\#(field),"items":[{"symbol":"star","title":{"ja":"a","en":"b"},"detail":{"ja":"c","en":"d"}}]}"#
    }

    /// 🔴 **日付は任意。** ある・無い・壊れた値のどれでも版は捨てない（壊れた日付だけ無視）
    func testReleaseDateIsOptionalAndLenient() async throws {
        let data = Data(#"""
        {"releases":[
          \#(dated("1.0.9", "2026-10-10")),
          \#(dated("1.0.8", nil)),
          \#(dated("1.0.7", "2026-02-30")),
          \#(dated("1.0.6", "10/04/2026")),
          \#(dated("1.0.5", "2026-1-4")),
          {"version":"1.0.4","date":20261004,"items":[{"symbol":"star","title":{"ja":"a","en":"b"},"detail":{"ja":"c","en":"d"}}]},
          {"version":"1.0.3","date":null,"items":[{"symbol":"star","title":{"ja":"a","en":"b"},"detail":{"ja":"c","en":"d"}}]}
        ]}
        """#.utf8)
        let releases = WhatsNew.decode(data)
        XCTAssertEqual(releases.map(\.version), ["1.0.9", "1.0.8", "1.0.7", "1.0.6", "1.0.5", "1.0.4", "1.0.3"])
        XCTAssertEqual(releases.first?.date, WhatsNew.Day(year: 2026, month: 10, day: 10))
        XCTAssertEqual(releases.dropFirst().map(\.date), Array(repeating: nil, count: 6))
        XCTAssertNil(WhatsNew.Day("２０２６-10-10"))
        XCTAssertNil(WhatsNew.Day("2026-13-01"))
        XCTAssertEqual(WhatsNew.Day("2024-02-29"), WhatsNew.Day(year: 2024, month: 2, day: 29))
        XCTAssertNil(WhatsNew.Day("2025-02-29"))
        // 🔴 数で作る口も暦に無い日を作らない（月の表を範囲の外で引いて落ちていた）
        XCTAssertNil(WhatsNew.Day(year: 2026, month: 0, day: 1))
        XCTAssertNil(WhatsNew.Day(year: 2026, month: 13, day: 1))
        XCTAssertNil(WhatsNew.Day(year: 2026, month: 2, day: 30))
        XCTAssertNil(WhatsNew.Day(year: 2026, month: 1, day: 0))
    }

    private let now = Date(timeIntervalSince1970: 1_792_300_000) // 2026-10 の半ば

    /// 区切りの見出し: 「1.0.82 · 10月10日」・"1.0.82 · Oct 10"・日付が無ければ版だけ・今年でなければ年も
    func testReleaseHeading() async {
        let r = WhatsNew.Release(version: "1.0.82", items: [], date: WhatsNew.Day(year: 2026, month: 10, day: 10))
        XCTAssertEqual(WhatsNew.heading(for: r, now: now, english: false), "1.0.82 · 10月10日")
        XCTAssertEqual(WhatsNew.heading(for: r, now: now, english: true), "1.0.82 · Oct 10")
        XCTAssertEqual(WhatsNew.heading(for: release("1.0.67"), now: now, english: false), "1.0.67")
        let old = WhatsNew.Release(version: "0.9.0", items: [], date: WhatsNew.Day(year: 2025, month: 12, day: 1))
        XCTAssertEqual(WhatsNew.heading(for: old, now: now, english: false), "0.9.0 · 2025年12月1日")
        XCTAssertEqual(WhatsNew.heading(for: old, now: now, english: true), "0.9.0 · Dec 1, 2025")
        // 読み上げは「·」や略した月を読ませない
        XCTAssertEqual(WhatsNew.spokenHeading(for: r, now: now, english: false), "バージョン 1.0.82、10月10日")
        XCTAssertEqual(WhatsNew.spokenHeading(for: r, now: now, english: true), "Version 1.0.82, October 10")
        XCTAssertEqual(WhatsNew.spokenHeading(for: release("1.0.67"), now: now, english: false), "バージョン 1.0.67")
        XCTAssertEqual(WhatsNew.spokenHeading(for: old, now: now, english: true), "Version 0.9.0, December 1, 2025")
    }

    /// 🔴 **履歴は新しい順・最新は見出し無しで上・2つ目から版ごとに見出し**（JSON の並びに頼らない）
    func testHistorySectionsAreNewestFirstWithHeadings() async {
        let data = Data(#"{"releases":[\#(dated("1.0.67", "2026-10-04")),\#(dated("1.0.82", "2026-10-10")),\#(dated("1.0.73", nil))]}"#.utf8)
        let sections = WhatsNew.sections(WhatsNew.decode(data), mode: .history, now: now)
        XCTAssertEqual(sections.map(\.id), ["1.0.82", "1.0.73", "1.0.67"])
        XCTAssertEqual(sections.map(\.heading), [nil, "1.0.73", "1.0.67 · 10月4日"])
        XCTAssertEqual(sections.map(\.spokenHeading), [nil, "バージョン 1.0.73", "バージョン 1.0.67、10月4日"])
        XCTAssertEqual(sections.map(\.items.count), [1, 1, 1])
        XCTAssertEqual(WhatsNew.sections([], mode: .history), [])
    }

    /// 🔴 **起動時のシートは変えない**: 何版またいでも見出し無しの1かたまりに、項目を新しい順に平らに
    func testLaunchSheetStaysFlat() async {
        let releases = [release("1.0.12"), release("1.0.10")]
        let sections = WhatsNew.sections(releases, mode: .launch, now: now)
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections.first?.heading)
        XCTAssertEqual(sections.first?.items, releases.flatMap(\.items))
        XCTAssertEqual(WhatsNew.sections([], mode: .launch), [])
    }

    /// 🔴 **1.1.18 の項目は、次に Actions で出す版（testflight/1.1.17 の次 = 1.1.18）で出る**（2026-10-19）。
    /// 1.1.17（キャンピングカー・アイコンとカバー）には項目が無かったので、その2つも 1.1.18 で知らせる。
    /// 比べ方は数（`isNewer`）。1.1.17・1.1.16 を見た人には 1.1.18 の分だけ、1.1.15 を見た人には 1.1.16 とまとめて出す。
    /// 1.1.18 を見た人・その次の版（項目の無い 1.1.19）では出さない
    func testNextReleaseShowsOnlyOnTheNextVersion() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/WhatsNew.json"))
        let releases = WhatsNew.decode(data)
        XCTAssertEqual(releases.first?.version, "1.1.18")
        XCTAssertEqual(releases.first?.items.count, 3)
        XCTAssertEqual(releases[1].items.count, 3)
        XCTAssertEqual(releases[2].items.count, 5)
        // 1.1.17・1.1.16 を見た人: 1.1.18 の分だけ
        for seen in ["1.1.17", "1.1.16"] {
            XCTAssertEqual(WhatsNew.pending(releases: releases, seen: seen, current: "1.1.18", usedBefore: true)
                .map(\.version), ["1.1.18"], "見た版 \(seen)")
        }
        // 1.1.15 を見た人: 見ていない 1.1.16 と 1.1.18 をまとめて
        XCTAssertEqual(WhatsNew.pending(releases: releases, seen: "1.1.15", current: "1.1.18", usedBefore: true)
            .map(\.version), ["1.1.18", "1.1.16"])
        // 文字の比較なら "1.1.18" < "1.1.9" で出なかった（数で比べる）
        XCTAssertTrue(WhatsNew.isNewer("1.1.18", than: "1.1.9"))
        XCTAssertTrue(WhatsNew.isNewer("1.1.18", than: "1.1.17"))
        // 2回目（同じ版）・その次の版では出さない
        XCTAssertTrue(WhatsNew.pending(releases: releases, seen: "1.1.18", current: "1.1.18", usedBefore: true).isEmpty)
        XCTAssertTrue(WhatsNew.pending(releases: releases, seen: "1.1.18", current: "1.1.19", usedBefore: true).isEmpty)
        // 新しいインストールには出さない
        XCTAssertTrue(WhatsNew.pending(releases: releases, seen: nil, current: "1.1.18", usedBefore: false).isEmpty)

        // 出した 1.1.17 の中身（1.1.16 までの項目）での出方は前のまま: 1.1.16 を見た人には何も出さない
        let bundledIn1117 = releases.filter { !WhatsNew.isNewer($0.version, than: "1.1.17") }
        XCTAssertTrue(WhatsNew.pending(releases: bundledIn1117, seen: "1.1.16", current: "1.1.17", usedBefore: true).isEmpty)
        XCTAssertEqual(WhatsNew.pending(releases: bundledIn1117, seen: "1.1.15", current: "1.1.17", usedBefore: true)
            .map(\.version), ["1.1.16"])

        // 版の決め方: project.yml の版より、出した印（testflight/1.1.17）の +1 が新しい（`next-marketing-version.sh`）
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        let marketing = try XCTUnwrap(project.components(separatedBy: "\n")
            .first { $0.contains("MARKETING_VERSION:") }?
            .components(separatedBy: "\"").dropFirst().first)
        XCTAssertFalse(WhatsNew.isNewer(marketing, than: "1.1.17"),
                       "project.yml の版（\(marketing)）が 1.1.17 より新しい——次の版が 1.1.18 にならない。項目の版を見直す")
    }

    // MARK: - 配線（Linux では描けないので文で確かめる）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 起動で出す口と、設定から開き直す口がある
    func testScreensAreWired() async throws {
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains("@StateObject private var whatsNew = WhatsNewGate()"))
        XCTAssertTrue(root.contains("whatsNew.markSeen()"))
        XCTAssertTrue(root.contains("WhatsNewView(releases: whatsNewReleases)"))
        // 起動時は履歴の形にしない（`mode` の既定 `.launch` のまま）
        XCTAssertFalse(root.contains(".history"))
        let view = try source("Sources/JourneyPhoto/Features/Settings/WhatsNewView.swift")
        XCTAssertTrue(view.contains("var mode: WhatsNew.Mode = .launch"))
        XCTAssertTrue(view.contains("WhatsNew.sections(releases, mode: mode)"))
        // 見出しは読み上げを持ち、区切り線は札の行の間の線と同じ部品
        XCTAssertTrue(view.contains(".accessibilityLabel(spoken)"))
        XCTAssertTrue(view.contains("JPCardDivider()"))
        let settings = try source("Sources/JourneyPhoto/Features/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains("\"settings.whatsNew\""))
        // 設定からは全部の版を履歴の形で（最新の版だけに切らない・2026-10-18）
        XCTAssertTrue(settings.contains("WhatsNewView(releases: WhatsNew.bundled(), mode: .history, primaryTitle: Labels.Common.close)"),
                      "設定から開いた「新しくなったこと」が履歴になっていない")
        XCTAssertFalse(settings.contains("WhatsNew.bundled().prefix(1)"))
    }

    /// 出した版には日付を入れる（履歴の区切りの見出し「1.0.82 · 10月10日」）。版の重複が無い
    func testBundledReleasesCarryDates() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let releases = WhatsNew.decode(try Data(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/WhatsNew.json")))
        let dates = Dictionary(uniqueKeysWithValues: releases.map { ($0.version, $0.date) })
        XCTAssertEqual(dates["1.1.16"] ?? nil, WhatsNew.Day(year: 2026, month: 10, day: 18))
        XCTAssertEqual(dates["1.1.15"] ?? nil, WhatsNew.Day(year: 2026, month: 10, day: 18))
        XCTAssertEqual(dates["1.1.14"] ?? nil, WhatsNew.Day(year: 2026, month: 10, day: 18))
        XCTAssertEqual(dates["1.0.82"] ?? nil, WhatsNew.Day(year: 2026, month: 10, day: 10))
        XCTAssertEqual(dates["1.0.73"] ?? nil, WhatsNew.Day(year: 2026, month: 10, day: 9))
        XCTAssertEqual(dates["1.0.67"] ?? nil, WhatsNew.Day(year: 2026, month: 10, day: 4))
        XCTAssertEqual(Set(releases.map(\.version)).count, releases.count, "版が重複している")
    }

    /// 項目からホームへ行く合図は回数で伝える
    func testOpenHomeCounts() async {
        let router = TabRouter()
        router.openHome()
        router.openHome()
        XCTAssertEqual(router.homeRequests, 2)
    }
}
