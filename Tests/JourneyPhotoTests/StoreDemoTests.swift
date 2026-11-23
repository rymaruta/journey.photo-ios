import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// App Store の画面写真の見本の表示（`StoreDemo`・2026-11-23 札 #604）。
///
/// 守ること: **見本の間は本番の他人の写真が1枚も出ない**（CLAUDE.md「他人の写真は、その人のもの」・絶対）。
/// 画像の入口は見本の置き場の URL しか読まず、通信の答え手は知らない置き場を断り、URLSession を作るところは
/// どれも見本の答え手を通す。見本の答えは本物の読み手（`Photo`・`OfficialSpot`・`SpotBody`）で読める。
/// 見本でなければ何も変えない
final class StoreDemoTests: XCTestCase {

    private let hosts = StoreDemo.Hosts(site: "journey-photo.com", api: "api.example.com",
                                        userAPI: "user.example.com", userAPIPath: "/prod")
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func withDemo(_ on: Bool, _ body: () throws -> Void) rethrows {
        let d = UserDefaults.standard
        let saved = d.object(forKey: StoreDemo.key)
        defer { d.set(saved, forKey: StoreDemo.key) }
        d.set(on, forKey: StoreDemo.key)
        try body()
    }

    // MARK: - 画像の入口の見張り

    func testOffByDefaultAndNothingChanges() {
        XCTAssertFalse(StoreDemo.isOn)
        let url = URL(string: "https://journey-photo.com/photos/a.jpg")!
        XCTAssertTrue(StoreDemo.allowsImage(url), "見本でないのに画像を断る（本番の動きが変わる）")
        XCTAssertEqual(StoreDemo.imageURL(url), url)
        let config = URLSessionConfiguration.ephemeral
        let before = config.protocolClasses?.count ?? 0
        StoreDemo.guarded(config)
        XCTAssertEqual(config.protocolClasses?.count ?? 0, before, "見本でないのに URLSession の設定を変える")
    }

    func testDemoRefusesEveryNetworkImage() {
        for raw in ["https://journey-photo.com/photos/a.jpg", "https://upload.wikimedia.org/x.jpg",
                    "https://d1234.cloudfront.net/u/1/p.jpg", "https://is1-ssl.mzstatic.com/art.jpg",
                    "http://example.com/a.png", "ftp://example.com/a.jpg"] {
            XCTAssertFalse(StoreDemo.allowsImage(URL(string: raw)!, demo: true), "見本の間に読む: \(raw)")
        }
        for raw in ["https://store-demo.invalid/photo/tunnel.jpg", "https://preview-local.invalid/img/k"] {
            XCTAssertTrue(StoreDemo.allowsImage(URL(string: raw)!, demo: true), "見本の画像を断る: \(raw)")
        }
        XCTAssertTrue(StoreDemo.allowsImage(URL(fileURLWithPath: "/tmp/a.jpg"), demo: true))
        withDemo(true) {
            XCTAssertTrue(StoreDemo.isOn)
            XCTAssertNil(StoreDemo.imageURL(URL(string: "https://journey-photo.com/photos/a.jpg")))
        }
    }

    /// 見本の間は、全部の要求を見本の答え手が引き受け（`PreviewBackend.handles`）、設定から作る URLSession にも答え手が入る
    func testDemoTakesEveryRequestAndGuardsSessions() {
        withDemo(true) {
            let request = URLRequest(url: URL(string: "https://upload.wikimedia.org/x.jpg")!)
            XCTAssertTrue(PreviewBackend.handles(request), "見本の間に外への要求を引き受けない")
            XCTAssertTrue(PreviewSession.localBackend, "見本の間に見本の通信にならない")
            XCTAssertEqual(PreviewSession.userId, StoreDemo.userId)
            let config = StoreDemo.guarded(URLSessionConfiguration.ephemeral)
            XCTAssertTrue(config.protocolClasses?.first == PreviewBackendProtocol.self, "URLSession に見本の答え手が入らない")
        }
        // 見本でなければ引き受けない（QR の口の見分けに API の根を読むので、試験の値を入れる）
        let saved = AppConfig.testOverrides
        defer { AppConfig.testOverrides = saved }
        AppConfig.testOverrides = ["JPUserApiBaseURL": "https://user.example.com/prod"]
        XCTAssertFalse(PreviewBackend.handles(URLRequest(url: URL(string: "https://upload.wikimedia.org/x.jpg")!)))
    }

    // MARK: - 答え手

    func testUnknownHostsAreRefused() {
        for raw in ["https://upload.wikimedia.org/x.jpg", "https://commons.wikimedia.org/w/api.php",
                    "https://audio-ssl.itunes.apple.com/a.m4a", "https://www.google.com/"] {
            let reply = StoreDemo.answer(method: "GET", url: URL(string: raw)!, hosts: hosts)
            XCTAssertEqual(reply?.status, 403, "知らない置き場を断らない: \(raw)")
        }
        // 生のいいね数・分けた索引は「無い」
        XCTAssertEqual(StoreDemo.answer(method: "GET", url: URL(string: "https://api.example.com/photos")!, hosts: hosts)?.status, 404)
        XCTAssertEqual(StoreDemo.answer(method: "GET", url: URL(string: "https://journey-photo.com/app/data/spot-feed/index.json")!,
                                        hosts: hosts)?.status, 404)
    }

    func testDemoImagesComeFromTheBundledPhotosOnly() {
        let saved = StoreDemo.loadAsset
        defer { StoreDemo.loadAsset = saved }
        var asked: [String] = []
        StoreDemo.loadAsset = { asked.append($0); return Data([0xFF, 0xD8, 0xFF]) }
        let ok = StoreDemo.answer(method: "GET", url: URL(string: StoreDemo.photoURL("tunnel"))!, hosts: hosts)
        XCTAssertEqual(ok?.status, 200)
        XCTAssertEqual(ok?.contentType, "image/jpeg")
        XCTAssertEqual(asked, ["tunnel"])
        // 見本の一覧に無い名前は返さない（同梱のほかの画像を勝手に出さない）
        XCTAssertEqual(StoreDemo.answer(method: "GET", url: URL(string: StoreDemo.photoURL("iphone"))!, hosts: hosts)?.status, 404)
        XCTAssertEqual(asked, ["tunnel"])
    }

    /// 見本の答えに出る URL は、見本の置き場（画像）と、サイトの頁へのリンクだけ。本番・Commons の画像は1つも無い
    func testEveryURLInDemoDataIsLocal() throws {
        var strings: [String] = []
        func walk(_ value: Any) {
            if let s = value as? String { strings.append(s) }
            if let a = value as? [Any] { a.forEach(walk) }
            if let d = value as? [String: Any] { d.values.forEach(walk) }
        }
        walk(StoreDemo.feed())
        walk(StoreDemo.spotRows())
        for spot in StoreDemo.spots { walk(try XCTUnwrap(StoreDemo.spotBody(spot.slug))) }
        let urls = strings.filter { $0.contains("://") }
        XCTAssertFalse(urls.isEmpty)
        for url in urls {
            XCTAssertTrue(url.hasPrefix("https://\(StoreDemo.host)/"), "見本の置き場でない URL: \(url)")
        }
        XCTAssertTrue(StoreDemo.dmSpotLink.hasPrefix("https://journey-photo.com/spots/"))
    }

    // MARK: - 本物の読み手で読める

    func testFeedSpotsAndBodiesDecodeWithTheRealReaders() throws {
        let site = { (path: String) -> Data in
            let reply = StoreDemo.answer(method: "GET", url: URL(string: "https://journey-photo.com\(path)")!, hosts: self.hosts)
            XCTAssertEqual(reply?.status, 200, path)
            return reply?.body ?? Data()
        }
        let list = try JSONDecoder.api.decode(LenientPhotoList.self, from: site("/app/data/photos.json"))
        XCTAssertEqual(list.dropped, 0)
        XCTAssertEqual(list.photos.count, StoreDemo.photos.count)
        XCTAssertTrue(list.photos.allSatisfy { $0.gridImageURL?.host == StoreDemo.host })
        let spots = try JSONDecoder.api.decode(LenientOfficialSpotList.self, from: site("/app/data/spots.json"))
        XCTAssertEqual(spots.dropped, 0)
        XCTAssertEqual(spots.spots.count, StoreDemo.spots.count)
        XCTAssertTrue(spots.spots.allSatisfy { !$0.isDraft && $0.photo?.url.host == StoreDemo.host })
        for spot in StoreDemo.spots {
            let body = try JSONDecoder.api.decode(SpotBody.self, from: site("/app/data/spots/\(spot.slug).json"))
            XCTAssertEqual(body.slug, spot.slug)
            XCTAssertEqual(body.samples.count, 1, "作例がその場所の写真で出ない: \(spot.slug)")
            XCTAssertEqual(body.samples.first?.src.host, StoreDemo.host)
        }
        // 写真から観光スポットへ（id がつながる）
        let spotIds = Set(StoreDemo.spots.map(\.spotId))
        XCTAssertTrue(StoreDemo.photos.compactMap(\.spotId).allSatisfy(spotIds.contains))
    }

    func testPublicUserRoutesAnswerFromDemoPeopleOnly() throws {
        let feed = StoreDemo.answer(method: "GET", url: URL(string: "https://user.example.com/prod/feed?limit=30")!, hosts: hosts)
        let page = try JSONDecoder.api.decode(FeedPage.self, from: XCTUnwrap(feed?.body))
        XCTAssertEqual(page.items.count, StoreDemo.photos.count)
        let person = StoreDemo.people[0]
        let profile = StoreDemo.answer(method: "GET", url: URL(string: "https://user.example.com/prod/profile/\(person.id)")!, hosts: hosts)
        let decoded = try JSONDecoder.api.decode(UserProfile.self, from: XCTUnwrap(profile?.body))
        XCTAssertEqual(decoded.displayName, person.name)
        // 知らない人は「無い」（本物の人のプロフィールを読みに行かない）
        let unknown = StoreDemo.answer(method: "GET", url: URL(string: "https://user.example.com/prod/profile/someone")!, hosts: hosts)
        XCTAssertEqual(unknown?.status, 404)
        let comments = StoreDemo.answer(method: "GET",
                                        url: URL(string: "https://user.example.com/prod/photos/\(StoreDemo.photoId("rootRectangle"))/comments")!,
                                        hosts: hosts)
        let page2 = try JSONDecoder.api.decode(SocialService.CommentPage.self, from: XCTUnwrap(comments?.body))
        XCTAssertEqual(page2.items.count, 2)
        // 鍵の要る口は見本の通信（`PreviewBackend.reply`）へ回す
        XCTAssertNil(StoreDemo.answer(method: "GET", url: URL(string: "https://user.example.com/prod/stories")!, hosts: hosts))
    }

    // MARK: - 見本の写真と文

    /// 画像はアプリに入っている構図の作例写真だけ。場所の名前は、写真の出典に書かれた実際の場所と合うものだけ
    func testPhotosAreBundledAndPlacesMatchTheirSources() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Tools/composition-examples/photo-sources.json"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sources = try XCTUnwrap(json["photos"] as? [String: [String: Any]])
        for photo in StoreDemo.photos {
            let source = try XCTUnwrap(sources[photo.asset], "出典の無い写真: \(photo.asset)")
            let license = source["license"] as? String ?? ""
            XCTAssertEqual(license, "CC0", "クレジット不要と確かめていない許諾: \(photo.asset) \(license)")
            let imageset = root.appendingPathComponent("Sources/JourneyPhoto/Assets.xcassets/composition-ai-\(photo.asset).imageset")
            XCTAssertTrue(FileManager.default.fileExists(atPath: imageset.path), "同梱されていない: \(photo.asset)")
            if let location = photo.location {
                let subject = source["subject"] as? String ?? ""
                let key = location.replacingOccurrences(of: "・", with: "")
                XCTAssertTrue(subject.replacingOccurrences(of: "・", with: "").contains(key),
                              "写真の出典の場所と合わない場所の名前: \(photo.asset) \(location) / \(subject)")
            }
        }
        for spot in StoreDemo.spots {
            let subject = try XCTUnwrap(sources[spot.asset]?["subject"] as? String)
            XCTAssertTrue(subject.contains(spot.name), "観光スポットの写真が、その場所の写真でない: \(spot.name) / \(subject)")
        }
    }

    /// 言葉の決まり（CLAUDE.md）: 中黒で区切らない、「撮りどき」「捨てる」を使わない。名前は作った名前
    func testDemoWordsFollowTheWordingRules() {
        var texts = StoreDemo.people.map(\.name)
        texts += StoreDemo.photos.flatMap { [$0.title] + $0.tags }
        for spot in StoreDemo.spots {
            texts.append(spot.summary)
            texts.append(spot.description)
            texts.append(contentsOf: spot.highlights)
            texts.append(contentsOf: spot.tips)
            texts.append(contentsOf: spot.seasons.map { $0.1 })
            texts.append(contentsOf: spot.times.map { $0.1 })
        }
        texts += StoreDemo.comments(photoId: StoreDemo.photoId(StoreDemo.photos[0].asset), now: Date()).compactMap { $0["text"] as? String }
        for text in texts {
            XCTAssertFalse(text.contains("撮りどき"), text)
            XCTAssertFalse(text.contains("捨て"), text)
            XCTAssertFalse(text.contains(" · "), text)
        }
        for name in StoreDemo.people.map(\.name) + StoreDemo.photos.map(\.title) {
            XCTAssertFalse(name.contains("・"), "中黒で区切っている: \(name)")
        }
    }

    // MARK: - 仕組みで守る（ソースの見張り）

    /// **URLSession を設定から作るところは、どれも `StoreDemo.guarded` を通す**（`URLProtocol.registerClass` は
    /// `URLSession.shared` にしか効かない）。通さない所は、その上に例外の理由を書く
    func testEverySessionGoesThroughTheGuard() throws {
        let sources = root.appendingPathComponent("Sources/JourneyPhoto")
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: sources.path))
        var checked = 0
        for case let path as String in files where path.hasSuffix(".swift") {
            let lines = try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains("URLSession(configuration:") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                checked += 1
                let above = lines[max(0, i - 3)..<i].joined(separator: "\n")
                XCTAssertTrue(line.contains("StoreDemo.guarded(") || above.contains("見張りの例外"),
                              "見本の答え手を通さない URLSession: \(path):\(i + 1)")
            }
        }
        XCTAssertGreaterThan(checked, 5)
    }

    /// **`AsyncImage(url:)` に渡す URL は、どれも見本の見張りを通す**（`StoreDemo.imageURL`、`RemoteImage` は `allowsImage`）
    func testEveryAsyncImageGoesThroughTheGuard() throws {
        let sources = root.appendingPathComponent("Sources/JourneyPhoto")
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: sources.path))
        var checked = 0
        for case let path as String in files where path.hasSuffix(".swift") {
            let lines = try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains("AsyncImage(url:") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                checked += 1
                let above = lines[max(0, i - 2)..<i].joined(separator: "\n")
                XCTAssertTrue(line.contains("StoreDemo.imageURL(") || above.contains("StoreDemo.allowsImage("),
                              "見本の見張りを通さない画像: \(path):\(i + 1)")
            }
        }
        XCTAssertGreaterThan(checked, 3)
    }
}
