import XCTest
@testable import JourneyPhoto

/// 探すの「人」の検索（`SearchViewModel.search`）。**返事の届く順を操って**確かめる。
///
/// 通信の代わりに、呼ばれたら止まって待つ引き先を渡す
/// （`release` で好きな順に返事を返す）。
@MainActor
final class SearchPeopleTests: XCTestCase {

    /// 呼ばれた語ごとに止まって待つ引き先
    /// **本体と同じ MainActor に置く。** 置かないと、止まって待つ側（別スレッド）と
    /// テスト本体の `isWaiting` が同じ辞書を同時に読み書きする（ThreadSanitizer で検出）
    @MainActor
    private final class PendingFetch {
        private var waiting: [String: CheckedContinuation<[UserProfile], Never>] = [:]
        private(set) var called: [String] = []

        func fetch(_ query: String) async -> [UserProfile] {
            called.append(query)
            return await withCheckedContinuation { waiting[query] = $0 }
        }

        func isWaiting(_ query: String) -> Bool { waiting[query] != nil }

        func release(_ query: String, with users: [UserProfile]) {
            waiting.removeValue(forKey: query)?.resume(returning: users)
        }
    }

    private func user(_ id: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self,
                                   from: Data(#"{"userId":"\#(id)","displayName":"\#(id)"}"#.utf8))
    }

    /// 条件が立つまで少しずつ待つ（最長2秒）。**決め打ちの時間では待たない**
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("待っても立たなかった", file: file, line: line)
    }

    /// 返事が届くまでの間を少し回す（反映されるなら、ここで反映される）
    private func settle() async {
        for _ in 0..<20 { try? await Task.sleep(for: .milliseconds(1)) }
    }

    /// **打鍵のあとの待ちの間も「探している」。** 待ちの間だけ
    /// `isSearching` が偽だと、人の種類で「見つかりませんでした」がちらつく
    func testWaitingBeforeTheRequestCountsAsSearching() async {
        let model = SearchViewModel()
        let pending = PendingFetch()
        await model.search("ab", debounce: .seconds(60)) { await pending.fetch($0) }
        XCTAssertTrue(model.isSearching, "待ちの間に「探していない」になっている")
        XCTAssertTrue(pending.called.isEmpty, "待たずに引いている")
    }

    /// **空にした直後に、前の語の返事が届いても人を並べない。**
    func testClearedQueryIgnoresTheOldReply() async throws {
        let model = SearchViewModel()
        let pending = PendingFetch()
        await model.search("ab", debounce: .zero) { await pending.fetch($0) }
        await waitUntil { pending.isWaiting("ab") }

        await model.search("", debounce: .zero) { await pending.fetch($0) }
        pending.release("ab", with: [try user("old")])
        await settle()

        XCTAssertTrue(model.users.isEmpty, "空にしたのに前の語の人が並んでいる")
        XCTAssertFalse(model.isSearching)
    }

    /// **古い回の返事で、新しい回の結果と「探しています…」を壊さない。**
    func testStaleReplyDoesNotOverwriteTheNewSearch() async throws {
        let model = SearchViewModel()
        let pending = PendingFetch()
        await model.search("a", debounce: .zero) { await pending.fetch($0) }
        await waitUntil { pending.isWaiting("a") }
        await model.search("ab", debounce: .zero) { await pending.fetch($0) }
        await waitUntil { pending.isWaiting("ab") }

        // 古い回の返事が、新しい回の途中で届く
        pending.release("a", with: [try user("old")])
        await settle()
        XCTAssertTrue(model.users.isEmpty, "取り消した回の返事で上書きしている")
        XCTAssertTrue(model.isSearching, "新しい回の途中で「探しています…」を消している")

        pending.release("ab", with: [try user("new")])
        await waitUntil { !model.isSearching }
        XCTAssertEqual(model.users.map(\.userId), ["new"])
    }
}
