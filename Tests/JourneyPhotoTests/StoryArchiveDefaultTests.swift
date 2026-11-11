import XCTest
@testable import JourneyPhoto

/// ストーリーの「24時間後も自分用に残す」の既定（2026-11-11 判断・`StoryArchivePreference`）。
///
/// 前は作る画面が毎回オフから始まった。owner「最初からオンでいい」——**初めてはオン、
/// 最後に選んだ値を人ごとに覚える**。
@MainActor
final class StoryArchiveDefaultTests: XCTestCase {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "story-archive-\(UUID().uuidString)")!
    }

    /// 🔴 **覚えが無い人はオンで始まる**（ログインしていないときもオン）
    func testStartsOnForSomeoneWithoutAChoice() async {
        let prefs = StoryArchivePreference(defaults: defaults())
        XCTAssertTrue(StoryArchivePreference.defaultValue, "既定がオフに戻っている")
        XCTAssertTrue(prefs.keepsInArchive(userId: "a"), "初めての人がオフで始まる")
        XCTAssertTrue(prefs.keepsInArchive(userId: nil))
        XCTAssertTrue(prefs.keepsInArchive(userId: ""))
    }

    /// 🔴 **一度オフにした人は次もオフ**（開き直しても同じ値）。オンに戻せばオン
    func testRemembersTheLastChoice() async {
        let store = defaults()
        StoryArchivePreference(defaults: store).set(false, userId: "a")
        let reopened = StoryArchivePreference(defaults: store)
        XCTAssertFalse(reopened.keepsInArchive(userId: "a"), "選んだオフを覚えていない")
        reopened.set(true, userId: "a")
        XCTAssertTrue(StoryArchivePreference(defaults: store).keepsInArchive(userId: "a"))
    }

    /// 🔴 **人ごと。** 前の人のオフを次の人に使わない。持ち主が分からない操作は書かない
    func testChoiceIsPerPerson() async {
        let store = defaults()
        let prefs = StoryArchivePreference(defaults: store)
        prefs.set(false, userId: "a")
        XCTAssertTrue(prefs.keepsInArchive(userId: "b"), "前の人のオフを次の人に使った")

        prefs.set(true, userId: nil)
        XCTAssertNil(store.object(forKey: StoryArchivePreference.baseKey), "持ち主の無い値を書いた")
        XCTAssertFalse(prefs.keepsInArchive(userId: "a"), "持ち主の無い操作が前の人の値を変えた")
    }

    /// 投稿の「撮影地の位置を付ける」と鍵が重ならない（片方を切ってももう片方は変わらない）
    func testDoesNotShareTheLocationChoice() async {
        let store = defaults()
        StoryArchivePreference(defaults: store).set(false, userId: "a")
        XCTAssertTrue(UploadLocationPreference(defaults: store).attachesLocation(userId: "a"))
        UploadLocationPreference(defaults: store).set(false, userId: "b")
        XCTAssertTrue(StoryArchivePreference(defaults: store).keepsInArchive(userId: "b"))
    }

    /// 退会したら消える（`AccountLocalData`）。別の人の値は残る
    func testRemovedWithTheAccount() async {
        let store = defaults()
        let prefs = StoryArchivePreference(defaults: store)
        prefs.set(false, userId: "gone")
        prefs.set(false, userId: "stays")
        let tmp = FileManager.default.temporaryDirectory
        AccountLocalData.remove(userId: "gone", username: nil, defaults: store,
                                draftDirectory: tmp.appendingPathComponent(UUID().uuidString),
                                offlineTripsRoot: tmp.appendingPathComponent(UUID().uuidString),
                                passRoot: tmp.appendingPathComponent(UUID().uuidString))
        XCTAssertNil(store.object(forKey: StoryArchivePreference.key(for: "gone")!))
        XCTAssertFalse(prefs.keepsInArchive(userId: "stays"))
    }

    /// 作る画面のつなぎ（画面は Linux で描けないので、ソースを見る）:
    /// 既定の値で始まり、開いたときにその人の値を読み、「誰に見せる？」で切り替えたときに書く
    func testComposerUsesThePreference() async throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("@State private var keepInArchive = StoryArchivePreference.defaultValue"),
                      "作る画面が既定の値（オン）で始まっていない")
        XCTAssertFalse(source.contains("@State private var keepInArchive = false"), "毎回オフから始まる形に戻っている")
        XCTAssertTrue(source.contains("keepInArchive = StoryArchivePreference().keepsInArchive(userId: userId)"),
                      "開いたときにその人の値を読んでいない")
        XCTAssertTrue(source.contains("StoryArchivePreference().set(value, userId: auth.userId)"),
                      "切り替えた値を覚えていない")
        XCTAssertTrue(source.contains("loadKeepInArchive(for: auth.userId)"))
    }
}
