import XCTest
@testable import JourneyPhoto

/// 保存（ブックマーク）の控え。**いいねとは別の入れ物**。
@MainActor
final class SavedPhotosStoreTests: XCTestCase {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    /// 🔴 **いいねと混ざらない。** 混ざっていたときは、保存を押すと
    /// ハートが灯り、「いいねした写真」に保存しただけの写真が並んだ
    func testSavingDoesNotTouchLikes() async {
        let store = defaults()
        let likes = FavoritesStore(defaults: store)
        let saves = SavedPhotosStore(defaults: store)
        likes.use(userId: "u1")
        saves.use(userId: "u1")

        saves.toggle("p1")
        likes.set("p2", favorite: true)

        // **読み直してから見る。** それぞれ自前の集合を持っているので、
        // 押した直後を見ても混線は見つからない——漏れるのは
        // 「次に開いたとき（同じ鍵を読み直したとき）」。
        // この読み直しを省いた最初の書き方では、鍵を同じにする変異で
        // **テストが緑のまま**だった
        likes.use(userId: "u1")
        saves.use(userId: "u1")

        XCTAssertTrue(saves.contains("p1"))
        XCTAssertTrue(likes.contains("p2"))
        XCTAssertFalse(likes.contains("p1"), "保存がいいねに漏れている")
        XCTAssertFalse(saves.contains("p2"), "いいねが保存に漏れている")
    }

    /// 同じ端末で人が変わったら持ち越さない
    func testDoesNotLeakBetweenAccounts() async {
        let store = defaults()
        let saves = SavedPhotosStore(defaults: store)
        saves.use(userId: "a")
        saves.toggle("p1")
        saves.use(userId: "b")
        XCTAssertFalse(saves.contains("p1"))
        saves.use(userId: "a")
        XCTAssertTrue(saves.contains("p1"), "同じ人に戻ったら出る")
    }

    /// サーバーの一覧に合わせる（取れた回だけ呼ぶ約束）
    func testReplaceMatchesTheServer() async {
        let saves = SavedPhotosStore(defaults: defaults())
        saves.use(userId: "u1")
        saves.toggle("old")
        saves.replace(with: ["a", "b"], for: "u1")
        XCTAssertEqual(saves.ids, ["a", "b"])
    }

    /// 空の id は入れない（空の行を作らない）
    func testIgnoresEmptyId() async {
        let saves = SavedPhotosStore(defaults: defaults())
        saves.use(userId: "u1")
        saves.set("", saved: true)
        XCTAssertTrue(saves.ids.isEmpty)
    }
}

/// いいねの控えを、サーバーの一覧に合わせるところ。
@MainActor
final class FavoritesSyncTests: XCTestCase {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    /// 🔴 **足すのではなく入れ替える。** 保存といいねが同じ入れ物だった頃の
    /// 端末には、**保存しただけの写真の id が残っている**——足すだけだと、
    /// その古い混ざりものが「いいねした写真」に出続ける
    func testSyncReplacesInsteadOfMerging() async {
        let likes = FavoritesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        likes.use(userId: "u1")
        likes.set("保存しただけの古い写真", favorite: true)
        likes.replace(with: ["本当にいいねした写真"], for: "u1")
        XCTAssertEqual(likes.ids, ["本当にいいねした写真"])
    }

    // MARK: - 「いいねした写真」に並べる ID（`FavoritesStore.listedIds`）

    /// 🔴 **外した直後に古い一覧が返っても出さない。** サーバーの一覧の読み取りは
    /// 強い整合でないので、詳細でハートを外して戻ると、外した写真を含む一覧が
    /// 返ることがある
    func testRemovedHereStaysHiddenEvenIfTheServerListIsStale() async {
        let likes = FavoritesStore(defaults: defaults())
        likes.use(userId: "u1")
        likes.set("a", favorite: true)
        likes.set("a", favorite: false)
        XCTAssertFalse(likes.listedIds(server: ["a", "b"]).contains("a"),
                       "外したいいねが古い一覧で戻ってきた")
    }

    /// 別の端末で押したぶん（サーバーの一覧にだけある）は足す
    func testServerOnlyIdsAreAdded() async {
        let likes = FavoritesStore(defaults: defaults())
        likes.use(userId: "u1")
        likes.set("here", favorite: true)
        XCTAssertEqual(likes.listedIds(server: ["other"]), ["here", "other"])
        // 聞けなかった回は控えだけ
        XCTAssertEqual(likes.listedIds(server: nil), Set(["here"]))
    }

    /// 押し直したら（外して、また付けた）出す。人が替わったら外した印は捨てる
    func testRelikingOrSwitchingUserClearsTheRemovedMark() async {
        let likes = FavoritesStore(defaults: defaults())
        likes.use(userId: "u1")
        likes.set("a", favorite: false)
        likes.set("a", favorite: true)
        XCTAssertTrue(likes.listedIds(server: ["a"]).contains("a"))

        likes.set("b", favorite: false)
        likes.use(userId: "u2")
        XCTAssertTrue(likes.listedIds(server: ["b"]).contains("b"),
                      "前の人が外した印が次の人に残っている")
    }
}
