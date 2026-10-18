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
        XCTAssertEqual(releases.map(\.version), ["1.0.82", "1.0.73", "1.0.67"])
        // 1.0.82: Pro。始まったことを先頭に（入口は設定なので行き先は無い）
        let latest = try XCTUnwrap(releases.first)
        XCTAssertEqual(latest.items.count, 4)
        XCTAssertEqual(latest.items.first?.title.ja, "Journey Photo Pro がはじまりました")
        XCTAssertNil(latest.items.first?.destination)
        XCTAssertEqual(latest.items.compactMap(\.destination), [.map, .mypage])
        // 🔴 版は「Pro が入って出る次の Actions の版」。1.0.79（Pro 無し）に続き、1.0.80・1.0.81 も
        // Pro 無しで TestFlight に出た（タグ testflight/1.0.80・1.0.81）。項目が 1.0.80 のままだと、
        // それらを使った人は「見た版 = 1.0.80 / 1.0.81」で、上げても Pro の知らせが出なかった
        for seen in ["1.0.79", "1.0.80", "1.0.81"] {
            XCTAssertEqual(WhatsNew.pending(releases: releases, seen: seen, current: "1.0.82", usedBefore: true)
                .map(\.version), ["1.0.82"], "見た版 \(seen)")
        }
        // 1.0.73: メダル。期限のある初期ユーザー章を先頭に
        let medals = releases[1]
        XCTAssertEqual(medals.items.count, 4)
        XCTAssertEqual(medals.items.first?.title.ja, "初期ユーザー章を贈ります")
        XCTAssertEqual(medals.items.compactMap(\.destination), [.mypage, .mypage])
        let previous = releases[2]
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
    }

    /// 🔴 **履歴は新しい順・最新は見出し無しで上・2つ目から版ごとに見出し**（JSON の並びに頼らない）
    func testHistorySectionsAreNewestFirstWithHeadings() async {
        let data = Data(#"{"releases":[\#(dated("1.0.67", "2026-10-04")),\#(dated("1.0.82", "2026-10-10")),\#(dated("1.0.73", nil))]}"#.utf8)
        let sections = WhatsNew.sections(WhatsNew.decode(data), mode: .history, now: now)
        XCTAssertEqual(sections.map(\.id), ["1.0.82", "1.0.73", "1.0.67"])
        XCTAssertEqual(sections.map(\.heading), [nil, "1.0.73", "1.0.67 · 10月4日"])
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
        let settings = try source("Sources/JourneyPhoto/Features/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains("\"settings.whatsNew\""))
        XCTAssertTrue(settings.contains("WhatsNewView(releases:"))
    }

    /// 項目からホームへ行く合図は回数で伝える
    func testOpenHomeCounts() async {
        let router = TabRouter()
        router.openHome()
        router.openHome()
        XCTAssertEqual(router.homeRequests, 2)
    }
}
