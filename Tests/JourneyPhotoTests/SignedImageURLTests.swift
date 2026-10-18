import XCTest
@testable import JourneyPhoto

/// 2026-10-18（札 #294）: 絞った写真の画像は期限つきの署名 URL。期限を過ぎると CloudFront が
/// 403 で断るので、割れたら一覧を取り直して新しい URL をもらう。
final class SignedImageURLTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_760_788_800)

    private func signed(_ expires: TimeInterval) -> URL {
        URL(string: "https://cdn.example.com/private/u/p.jpg?Expires=\(Int(expires))&Signature=abc~_-&Key-Pair-Id=K2")!
    }

    func testReadsExpiryOnlyFromSignedURLs() {
        XCTAssertEqual(SignedImageURL.expiry(of: signed(123)), Date(timeIntervalSince1970: 123))
        XCTAssertNil(SignedImageURL.expiry(of: URL(string: "https://cdn.example.com/uploads/u/p.jpg")!))
        XCTAssertNil(SignedImageURL.expiry(of: URL(string: "https://cdn.example.com/p.jpg?Expires=1")!),
                     "署名の無い Expires は期限として読まない")
    }

    func testExpiredIncludesSkew() {
        let t = now.timeIntervalSince1970
        XCTAssertTrue(SignedImageURL.isExpired(signed(t - 60), now: now))
        XCTAssertTrue(SignedImageURL.isExpired(signed(t + 10), now: now), "30秒手前から切れた扱い")
        XCTAssertFalse(SignedImageURL.isExpired(signed(t + 600), now: now))
        XCTAssertFalse(SignedImageURL.isExpired(URL(string: "https://cdn.example.com/uploads/u/p.jpg")!, now: now))
    }

    func testGateRefetchesOnlyForExpiredSignedFailures() {
        let t = now.timeIntervalSince1970
        var gate = SignedImageRefetchGate()
        XCTAssertFalse(gate.shouldRefetch(after: signed(t + 600), now: now), "期限内の失敗は取り直しても直らない")
        XCTAssertFalse(gate.shouldRefetch(after: URL(string: "https://cdn.example.com/uploads/u/p.jpg"), now: now))
        XCTAssertFalse(gate.shouldRefetch(after: nil, now: now))
        XCTAssertTrue(gate.shouldRefetch(after: signed(t - 60), now: now))
    }

    func testGateThrottlesBurstsFromAGrid() {
        let t = now.timeIntervalSince1970
        var gate = SignedImageRefetchGate(minInterval: 15)
        XCTAssertTrue(gate.shouldRefetch(after: signed(t - 60), now: now))
        XCTAssertFalse(gate.shouldRefetch(after: signed(t - 60), now: now.addingTimeInterval(1)),
                       "格子で何枚割れても、続けては取り直さない")
        XCTAssertTrue(gate.shouldRefetch(after: signed(t - 60), now: now.addingTimeInterval(16)))
    }

    func testReportPostsOnlyExpiredSignedURLsWithTheURL() {
        let center = NotificationCenter()
        let got = Box<[URL]>([])
        let token = center.addObserver(forName: .signedImagesExpired, object: nil, queue: nil) { note in
            if let url = note.userInfo?[SignedImageExpiry.urlKey] as? URL { got.mutate { $0.append(url) } }
        }
        defer { center.removeObserver(token) }
        let t = now.timeIntervalSince1970
        SignedImageExpiry.report(signed(t + 600), now: now, center: center)
        SignedImageExpiry.report(URL(string: "https://cdn.example.com/uploads/u/p.jpg"), now: now, center: center)
        SignedImageExpiry.report(nil, now: now, center: center)
        XCTAssertEqual(got.value, [])
        SignedImageExpiry.report(signed(t - 60), now: now, center: center)
        XCTAssertEqual(got.value, [signed(t - 60)], "どの画像が割れたかを載せる（受ける画面が自分の写真か確かめる）")
    }

    func testSignalsStreamDeliversTheFailedURL() async {
        let center = NotificationCenter()
        let stream = SignedImageExpiry.signals(center: center)
        let received = Task { () -> URL? in
            for await url in stream { return url }
            return nil
        }
        // 受け口が付くまで少し待ってから流す
        try? await Task.sleep(nanoseconds: 50_000_000)
        let url = signed(now.timeIntervalSince1970 - 60)
        center.post(name: .signedImagesExpired, object: nil, userInfo: [SignedImageExpiry.urlKey: url])
        let got = await received.value
        XCTAssertEqual(got, url)
    }

    func testPhotoKnowsItsImageURLs() throws {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data("""
        {"id":"p","src":"https://x/p.jpg","thumbSrc":"https://x/p_t.webp","thumbSmAvif":"https://x/p_s.avif",
         "createdAt":"2026-01-02T00:00:00Z"}
        """.utf8))
        XCTAssertTrue(photo.usesImageURL(URL(string: "https://x/p_t.webp")!))
        XCTAssertTrue(photo.usesImageURL(URL(string: "https://x/p_s.avif")!))
        XCTAssertFalse(photo.usesImageURL(URL(string: "https://x/other.jpg")!))
        XCTAssertTrue([photo].containsImageURL(URL(string: "https://x/p.jpg")!))
        XCTAssertFalse([Photo]().containsImageURL(URL(string: "https://x/p.jpg")!))
    }
}

/// 受け口（別のスレッドから呼ばれうる）で値を持つ箱
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ change: (inout T) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}
