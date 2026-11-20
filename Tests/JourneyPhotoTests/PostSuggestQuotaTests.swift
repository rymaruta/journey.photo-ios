import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿の候補（#622）の回数の上限（札 #658）: 1日20回かつ月300回、端末の中だけで数える、日本時間で区切る
@MainActor
final class PostSuggestQuotaTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: OnDeviceAI.modeKey)
        super.tearDown()
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "PostSuggestQuotaTests.\(UUID().uuidString)")! }

    /// 2026-11-26 23:30（日本時間）
    private let night = Date(timeIntervalSince1970: 1_795_703_400)

    func testDayAndMonthLimitsWithTokyoBoundaries() async {
        let d = defaults()
        var clock = night
        let q = PostSuggestQuota(defaults: d, now: { clock })
        XCTAssertEqual(PostSuggestQuota.day(night), "2026-11-26")
        for _ in 0..<20 { q.count() }
        XCTAssertEqual(q.blocked, .day)
        // 日本時間の0時を過ぎたら今日の分は戻る（UTC ではまだ同じ日）
        clock = night.addingTimeInterval(45 * 60)
        XCTAssertEqual(PostSuggestQuota.day(clock), "2026-11-27")
        XCTAssertNil(q.blocked)
        XCTAssertEqual(q.usedThisMonth, 20)
        // 月 300 回
        for _ in 0..<280 { q.count() }
        XCTAssertEqual(q.blocked, .month, "月の上限は日の上限より先に言う")
        // 翌月の1日（日本時間）に戻る
        clock = night.addingTimeInterval(10 * 86_400 + 45 * 60)
        XCTAssertEqual(PostSuggestQuota.month(clock), "2026-12")
        XCTAssertNil(q.blocked)
        XCTAssertEqual(PostSuggestQuota.line(.day), "今日の候補は使い切りました")
        XCTAssertEqual(PostSuggestQuota.line(.month), "今月の候補は使い切りました")
    }

    private func model() -> UploadViewModel {
        let session = URLSession(configuration: .ephemeral)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        return UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                               photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
    }

    private func pending(_ place: String) -> PendingPhoto {
        var photo = PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data([0xff]), fileName: "photo.jpg", contentType: "image/jpeg", exif: nil, coords: nil, takenOn: nil))
        photo.location = place
        return photo
    }

    /// 上限に達したら AI を呼ばず候補を出さない（1行だけ）。答えなかった回は数えない。投稿の欄はそのまま
    func testBlocksAtLimitAndCountsOnlyShown() async {
        UserDefaults.standard.set("sample", forKey: OnDeviceAI.modeKey)
        let d = defaults()
        let quota = PostSuggestQuota(defaults: d, now: { self.night })
        let model = model()
        model.postSuggestQuota = quota
        model.postSuggestQuotaCountsSample = true
        var answers = 0
        model.runPostSuggest = { _, _ in nil }
        let silent = pending("兼六園")
        model.items = [silent]
        await model.loadPostSuggestion(for: silent.id)
        XCTAssertEqual(quota.usedToday, 0, "AI が答えなかった回を数えた")

        for _ in 0..<19 { quota.count() }
        model.runPostSuggest = { _, _ in PostSuggest.sample }
        let shown = pending("金沢城")
        model.items = [shown]
        await model.loadPostSuggestion(for: shown.id)
        XCTAssertEqual(quota.usedToday, 20, "候補を出した回を数えていない")
        XCTAssertFalse(model.titleSuggestions(for: model.items[0]).isEmpty)

        let calls = QuotaCalls()
        model.runPostSuggest = { _, _ in await calls.bump(); return PostSuggest.sample }
        let next = pending("ひがし茶屋街")
        model.items = [next]
        await model.loadPostSuggestion(for: next.id)
        answers = await calls.value
        XCTAssertEqual(answers, 0, "上限なのに AI を呼んだ")
        XCTAssertEqual(model.titleSuggestions(for: model.items[0]), [])
        XCTAssertEqual(model.postSuggestLimitLine(for: model.items[0]), "今日の候補は使い切りました")
        XCTAssertEqual(model.items[0].title, "", "欄を書き換えた")
    }
}

private actor QuotaCalls {
    private(set) var value = 0
    func bump() { value += 1 }
}
