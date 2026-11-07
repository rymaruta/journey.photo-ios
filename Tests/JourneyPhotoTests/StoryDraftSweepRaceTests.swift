import XCTest
@testable import JourneyPhoto

/// ストーリーの下書きの掃除(`sweepOrphans`)と裏の保存(`saveInBackground`)の競合(2026-11-07)。
/// 裏の保存は画像を主スレッドの外で書き、書き終えてから記録に載せる。その間に別の入れ物の `use`(=掃除)が走ると、
/// まだ記録に載っていない新しい画像を「どこからも指されていない」と消していた。
@MainActor
final class StoryDraftSweepRaceTests: XCTestCase {

    private let defaults = UserDefaults(suiteName: "StoryDraftSweepRaceTests.\(UUID().uuidString)")!
    nonisolated private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StoryDraftSweepRaceTests-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".jpg") }
    }

    /// 🔴 書き途中の画像は、別の入れ物の掃除で消えない。書き終えて記録に載れば、そのまま残る。
    /// 書き途中の集合(`writing`)を外すと、掃除が消して、保存は成功しても画像が無くなる
    func testSweepDoesNotDeleteImagesBeingWritten() async {
        let store = StoryDraftStore(defaults: defaults, directory: directory, slot: .auto)
        store.use(userId: "a")
        let gate = Gate()
        store.writeFiles = { pairs in
            for (data, url) in pairs { try data.write(to: url, options: .atomic) }
            await gate.wait()
        }
        let saving = Task {
            await store.saveInBackground(
                shots: [StoryDraftStore.ShotInput(imageData: Data([1, 2, 3]), fileName: "a.jpg", contentType: "image/jpeg",
                                                  coords: nil, overlays: [])],
                caption: "", location: "", song: nil, durationSec: 5, archive: false, allowReplies: true,
                basedOn: nil, savedAt: "2026-11-07T00:00:00Z")
        }
        await gate.untilWaiting(1)
        XCTAssertEqual(files().count, 1, "前提: 画像は書けていて、記録にはまだ載っていない")

        // 別の入れ物が人を決める(=掃除が走る)
        let other = StoryDraftStore(defaults: defaults, directory: directory, slot: .auto)
        other.use(userId: "a")
        XCTAssertEqual(files().count, 1, "書き途中の画像を掃除が消した")

        await gate.open()
        let saved = await saving.value
        XCTAssertTrue(saved)
        XCTAssertEqual(files().count, 1)
        let reread = StoryDraftStore(defaults: defaults, directory: directory, slot: .auto)
        reread.use(userId: "a")
        XCTAssertNotNil(reread.draft, "記録に載ったはず")
        XCTAssertEqual(files().count, 1, "載った画像を掃除が消した")
    }

    /// 書き終えた後は守りが外れる(どの記録にも載らなかった画像は、次の掃除で消える)
    func testOrphanIsSweptAfterWritingEnds() async {
        let store = StoryDraftStore(defaults: defaults, directory: directory, slot: .auto)
        store.use(userId: "a")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = StoryDraftStore.imageFileName(forKey: "x", token: "tok", index: 0)
        try? Data([1]).write(to: directory.appendingPathComponent(name))
        XCTAssertFalse(StoryDraftStore.isWriting(name))
        store.use(userId: "a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path),
                       "書き途中でない孤児が掃除されない")
    }
}
