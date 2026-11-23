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

    // MARK: - 答え手の分かれ道（`PreviewBackendProtocol.startLoading` が呼ぶ `PreviewBackend.respond`）

    private func respond(_ raw: String, token: Bool = false, demo: Bool = true) async -> PreviewBackend.Reply {
        var request = URLRequest(url: URL(string: raw)!)
        if token { request.setValue("Bearer \(PreviewBackend.token)", forHTTPHeaderField: "Authorization") }
        return await PreviewBackend.respond(to: request, body: nil, demo: demo, userAPIPath: hosts.userAPIPath,
                                            hosts: demo ? hosts : nil)
    }

    /// 見本の間、知らない置き場への要求は 403 で返る（外へ出ない）。見本の画像・公開の新着は見本から答える
    func testRespondRefusesUnknownHostsAndAnswersFromDemo() async throws {
        let d = UserDefaults.standard
        let saved = (d.object(forKey: StoreDemo.key), d.object(forKey: PreviewSession.storiesKey))
        defer {
            d.set(saved.0, forKey: StoreDemo.key)
            d.set(saved.1, forKey: PreviewSession.storiesKey)
        }
        d.set(true, forKey: StoreDemo.key)
        d.set(true, forKey: PreviewSession.storiesKey)
        let refused = await respond("https://upload.wikimedia.org/x.jpg")
        XCTAssertEqual(refused.status, 403, "見本の間に知らない置き場へ出る")
        let feed = await respond("https://user.example.com/prod/feed?limit=30")
        let page = try JSONDecoder.api.decode(FeedPage.self, from: feed.body)
        XCTAssertEqual(page.items.map(\.id), StoreDemo.photos.map { StoreDemo.photoId($0.asset) }, "公開の新着が見本でない")
        // 鍵の要る口（ストーリー）は見本の通信へ回り、作者は見本の新着の人（本物の新着を読まない）
        let stories = await respond("https://user.example.com/prod/stories", token: true)
        XCTAssertEqual(stories.status, 200)
        let rows = try XCTUnwrap(try JSONSerialization.jsonObject(with: stories.body) as? [[String: Any]])
        let people = Set(StoreDemo.people.map(\.id) + [StoreDemo.userId])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            XCTAssertTrue(people.contains(row["userId"] as? String ?? ""), "見本でない人のストーリー: \(row)")
            XCTAssertEqual(URL(string: row["src"] as? String ?? "")?.host, StoreDemo.host, "見本でない画像のストーリー")
        }
    }

    /// 画像の入口（`DownsampledRemoteImage` の `GridImageInFlight`）は、見本の間は見本の置き場でない URL を読みに行かない
    func testGridImageEntryRefusesNetworkImagesInDemo() async {
        let d = UserDefaults.standard
        let saved = d.object(forKey: StoreDemo.key)
        defer { d.set(saved, forKey: StoreDemo.key) }
        d.set(true, forKey: StoreDemo.key)
        do {
            _ = try await GridImageInFlight.shared.data(for: URL(string: "https://journey-photo.invalid/photos/a.jpg")!)
            XCTFail("見本の間に本番の画像を読みに行く")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badURL, "見本の見張りより先に通信している: \(error)")
        } catch {
            XCTFail("見本の見張りで断っていない: \(error)")
        }
    }

    /// 写真の出典の行は、見本の間は見せない（`CreditLinksMenu`・ホームの上の札が `StoreDemo.showsCredits` を見る）
    func testCreditsAreHiddenOnlyInDemo() throws {
        XCTAssertTrue(StoreDemo.showsCredits(demo: false))
        XCTAssertFalse(StoreDemo.showsCredits(demo: true))
        XCTAssertTrue(StoreDemo.showsCredits, "見本でないのに出典を隠す")
        withDemo(true) { XCTAssertFalse(StoreDemo.showsCredits) }
        let src = root.appendingPathComponent("Sources/JourneyPhoto/Features")
        let menu = try String(contentsOf: src.appendingPathComponent("Spots/OfficialSpotView.swift"), encoding: .utf8)
        let body = try XCTUnwrap(menu.components(separatedBy: "struct CreditLinksMenu").dropFirst().first)
            .components(separatedBy: "private var tapArea").first ?? ""
        XCTAssertTrue(body.contains("if !StoreDemo.showsCredits {") && body.contains(".hidden()"), "CreditLinksMenu が見本の間に出典を隠さない")
        let face = try String(contentsOf: src.appendingPathComponent("Gallery/TopCardFace.swift"), encoding: .utf8)
        XCTAssertTrue(face.contains(".opacity(StoreDemo.showsCredits ? 1 : 0)"), "ホームの上の札が見本の間に出典を隠さない")
    }

    /// 大きい絵の道（`RemoteImage`＝`AsyncImage`。写真の詳細・観光スポットの頁の上の絵・DM の写真）は、見本の答え手を通らない。
    /// 見本の画像は通信せずに同梱の写真から描く（Mac run 1736 で読み込み中のままだった）。見本でない・見本の置き場でない URL は描かない
    func testLargeImagePathDrawsDemoPhotosWithoutNetwork() throws {
        let saved = StoreDemo.loadAsset
        defer { StoreDemo.loadAsset = saved }
        var asked: [String] = []
        StoreDemo.loadAsset = { asked.append($0); return Data([0xFF, 0xD8, 0xFF]) }
        let demoURL = URL(string: StoreDemo.photoURL("tunnel"))!
        XCTAssertNil(StoreDemo.localImageData(for: demoURL), "見本でないのに同梱の写真に替える")
        withDemo(true) {
            XCTAssertNotNil(StoreDemo.localImageData(for: demoURL), "見本の画像を同梱の写真から出さない")
            XCTAssertNil(StoreDemo.localImageData(for: URL(string: "https://journey-photo.com/photos/a.jpg")))
            XCTAssertNil(StoreDemo.localImageData(for: URL(string: StoreDemo.photoURL("iphone"))), "見本の一覧に無い写真を出す")
        }
        XCTAssertEqual(asked, ["tunnel"])
        let remote = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Common/RemoteImage.swift"),
                                encoding: .utf8)
        let local = try XCTUnwrap(remote.range(of: "if let local = StoreDemoImages.image(for: url)"), "RemoteImage が見本の画像を同梱から描かない")
        let async = try XCTUnwrap(remote.range(of: "AsyncImage(url: url"))
        XCTAssertLessThan(local.lowerBound, async.lowerBound, "見本の画像を AsyncImage より先に引いていない")
    }

    /// 見本の曲の名前は場所を言わない（どの写真に付いても食い違わない）
    func testDemoSongTitleNamesNoPlace() {
        XCTAssertNil(StoreDemo.songTitle)
        XCTAssertEqual(PreviewStorySample.song.title, "夜明けの港で聴くバラード")
        withDemo(true) {
            let title = StoreDemo.songTitle ?? ""
            XCTAssertFalse(title.isEmpty)
            for word in ["港", "海", "山", "京都", "富士", "森"] { XCTAssertFalse(title.contains(word), title) }
            XCTAssertEqual(PreviewStorySample.song.title, title)
            XCTAssertEqual(PreviewBackend.previewStorySong(demo: true)["title"] as? String, title)
        }
    }

    // MARK: - 見本の会話・旅行プラン・作者

    /// 作例の作者は `photo-sources.json` の本当の作者（旅のオフラインの頁などに字が出ても正しい名前）
    func testSpotAuthorsAreTheRealAuthors() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Tools/composition-examples/photo-sources.json"))
        let sources = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["photos"] as? [String: [String: Any]])
        for spot in StoreDemo.spots {
            let author = try XCTUnwrap(sources[spot.asset]?["author"] as? String)
            XCTAssertEqual(StoreDemo.spotImage(spot.asset)["author"] as? String, author, spot.name)
            let body = try JSONDecoder.api.decode(SpotBody.self, from: JSONSerialization.data(withJSONObject: XCTUnwrap(StoreDemo.spotBody(spot.slug))))
            XCTAssertEqual(body.samples.first?.author, author, spot.name)
            XCTAssertTrue(body.samples.first?.credit.contains(author) == true, "出典の文に本当の作者が無い: \(spot.name)")
        }
    }

    /// 旅行プランの見本は、見本の観光スポットだけで組む（日程の行が名前を引ける・`TripPlanDetailView.spotFor`）
    func testTripPlanFixtureUsesDemoSpotsInDemo() {
        let ids = Set(StoreDemo.spots.map(\.spotId))
        withDemo(true) {
            let plans = TripPlanFixture.initialPlans(today: Date(), soon: false)
            XCTAssertEqual(plans.map(\.title), [StoreDemo.tripPlanTitle])
            let spotIds = plans.flatMap(\.days).flatMap(\.items).compactMap { item -> String? in
                if case .spot(let id, _) = item { return id }
                return nil
            }
            XCTAssertEqual(Set(spotIds), ids, "見本の4か所で組んでいない")
        }
        // 見本でなければ今までの金沢のプラン
        XCTAssertTrue(TripPlanFixture.initialPlans(today: Date(), soon: false).contains { $0.title == "金沢・福井の旅" })
    }

    /// DM の見本の会話は、見本の写真と場所に合う文（本物の場所の話・夕焼けの話をしない）。見本でなければ今までどおり
    func testDMConversationMatchesDemoPhotos() throws {
        let me = StoreDemo.userId
        let id = DMRules.conversationId(me, PreviewBackend.dmPeers[0].id)
        let sample = StoreDemo.feed().first.map { ["id": $0["id"] ?? "", "state": "live", "src": $0["src"] ?? ""] as [String: Any] }
        func items(demo: Bool) throws -> [[String: Any]] {
            let reply = try XCTUnwrap(PreviewBackend.dmReply(method: "GET", parts: ["dm", id], json: [:], me: me, now: Date(),
                                                             samplePhoto: sample, demo: demo))
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: reply.body) as? [String: Any])
            return object["items"] as? [[String: Any]] ?? []
        }
        func texts(demo: Bool) throws -> [String] { try items(demo: demo).compactMap { $0["text"] as? String } }
        // 「写真を表示できません」（見られなくなった写真）の1通は、見本の表示では出さない。写真の通（見本の写真）は残す
        func goneCount(demo: Bool) throws -> Int {
            try items(demo: demo).filter { (($0["photo"] as? [String: Any])?["state"] as? String) == "gone" }.count
        }
        XCTAssertEqual(try goneCount(demo: true), 0, "見本の表示に「写真を表示できません」の1通が出る")
        XCTAssertEqual(try goneCount(demo: false), 1, "見本でないのに見られなくなった写真の1通が消えた")
        XCTAssertTrue(try items(demo: true).contains { ($0["photo"] as? [String: Any])?["state"] as? String == "live" })
        let demo = try texts(demo: true)
        for word in ["夕焼け", "伊豆", "雪吊り", "kenrokuen"] {
            XCTAssertFalse(demo.contains { $0.contains(word) }, "見本の写真と合わない文: \(word)")
        }
        XCTAssertTrue(demo.contains(StoreDemo.dmSpotLink))
        XCTAssertTrue(demo.contains { $0.contains("伏見稲荷大社") })
        XCTAssertTrue(try texts(demo: false).contains { $0.contains("伊豆") }, "見本でないのに会話の文が変わった")
        let inbox = try XCTUnwrap(PreviewBackend.dmReply(method: "GET", parts: ["dm"], json: [:], me: me, now: Date(), demo: true))
        XCTAssertTrue(String(decoding: inbox.body, as: UTF8.self).contains(StoreDemo.dmFirstExcerpt))
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
