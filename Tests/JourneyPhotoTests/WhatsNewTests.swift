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
        XCTAssertEqual(releases.map(\.version), ["1.0.79", "1.0.73", "1.0.67"])
        // 1.0.79: Pro。始まったことを先頭に（入口は設定なので行き先は無い）
        let latest = try XCTUnwrap(releases.first)
        XCTAssertEqual(latest.items.count, 4)
        XCTAssertEqual(latest.items.first?.title.ja, "Journey Photo Pro がはじまりました")
        XCTAssertNil(latest.items.first?.destination)
        XCTAssertEqual(latest.items.compactMap(\.destination), [.map, .mypage])
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
