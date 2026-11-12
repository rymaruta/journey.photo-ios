import XCTest
@testable import JourneyPhoto

/// 資料「SNS をもっと SNS に」（1.1.83・2026-11-12）の ①投稿したら共有カード・④ホームの「おすすめの人」・
/// ⑤撮影スポットを DM で送る。
final class SNSMoreTests: XCTestCase {

    private func photo(id: String, user: String, name: String? = nil, location: String? = nil,
                       createdAt: String, audience: String? = nil, published: Bool? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"\(user)\"",
                      "\"createdAt\":\"\(createdAt)\""]
        if let name { fields.append("\"displayName\":\"\(name)\"") }
        if let location { fields.append("\"location\":\"\(location)\"") }
        if let audience { fields.append("\"audience\":\"\(audience)\"") }
        if let published { fields.append("\"published\":\(published)") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - ④ おすすめの人

    /// 持ち主ごとに束ね、いちばん新しい投稿の順。写真は新しい順に3枚・数は全部・撮影地はいちばん新しい写真の
    func testSuggestedPeopleGroupsByOwnerNewestFirst() throws {
        let photos = [
            try photo(id: "a1", user: "A", name: "あや", location: "京都", createdAt: "2026-11-01T00:00:00Z"),
            try photo(id: "a2", user: "A", name: "あや", location: "金沢", createdAt: "2026-11-05T00:00:00Z"),
            try photo(id: "a3", user: "A", name: "あや", createdAt: "2026-10-01T00:00:00Z"),
            try photo(id: "a4", user: "A", name: "あや", createdAt: "2026-09-01T00:00:00Z"),
            try photo(id: "b1", user: "B", name: "ぶん", location: "札幌", createdAt: "2026-11-09T00:00:00Z"),
        ]
        let people = SuggestedPeople.pick(photos, viewerId: "me", following: [])
        XCTAssertEqual(people.map(\.userId), ["B", "A"], "いちばん新しい投稿の順")
        let a = try XCTUnwrap(people.last)
        XCTAssertEqual(a.count, 4)
        XCTAssertEqual(a.photos.map(\.id), ["a2", "a1", "a3"], "新しい順に3枚")
        XCTAssertEqual(a.latestLocation, "金沢")
        XCTAssertEqual(a.name, "あや")
        XCTAssertEqual(SuggestedPeople.countLine(a), L("4 枚", "4 photos"))
        XCTAssertEqual(SuggestedPeople.recentLine(a), L("最近 金沢", "Recently 金沢"))
        XCTAssertEqual(SuggestedPeople.spoken(a), L("あや、4 枚、最近 金沢", "あや、4 photos、Recently 金沢"), "読み上げの区切りは「、」")
    }

    /// 自分・フォロー中の人・公開範囲を絞った写真は並べない。上限で切る
    func testSuggestedPeopleSkipsSelfFollowedAndRestricted() throws {
        let photos = [
            try photo(id: "m", user: "me", createdAt: "2026-11-10T00:00:00Z"),
            try photo(id: "f", user: "F", createdAt: "2026-11-10T00:00:00Z"),
            try photo(id: "r", user: "R", createdAt: "2026-11-10T00:00:00Z", audience: "followers"),
            try photo(id: "p", user: "P", createdAt: "2026-11-10T00:00:00Z", published: false),
            try photo(id: "o", user: "O", createdAt: "2026-11-01T00:00:00Z"),
        ]
        XCTAssertEqual(SuggestedPeople.pick(photos, viewerId: "me", following: ["F"]).map(\.userId), ["O"])
        let many = try (0..<10).map { try photo(id: "x\($0)", user: "U\($0)", createdAt: "2026-11-0\($0 % 9 + 1)T00:00:00Z") }
        XCTAssertEqual(SuggestedPeople.pick(many, viewerId: nil, following: []).count, SuggestedPeople.limit)
        XCTAssertNil(SuggestedPeople.recentLine(SuggestedPeople.pick(photos, viewerId: "me", following: ["F"])[0]),
                     "撮影地の無い人は数だけ")
    }

    /// 「フォロー中の写真を見る」は、この場で1人でもフォローしたら出す
    func testSeeFeedButtonAppearsAfterAFollow() {
        XCTAssertFalse(SuggestedPeople.showsSeeFeed(followedHere: []))
        XCTAssertTrue(SuggestedPeople.showsSeeFeed(followedHere: ["A"]))
    }

    /// ホームの「フォロー中」が空のとき、「写真や人を探す」の前に「おすすめの人」を出す（並べる人がいれば）
    func testFollowingEmptyShowsSuggestedPeople() throws {
        let gallery = try source("Sources/JourneyPhoto/Features/Gallery/GalleryView.swift")
        let start = try XCTUnwrap(gallery.range(of: "private func feedEmptyState(_ page: HomeFeed) -> some View {"))
        let body = String(gallery[start.upperBound...].prefix(1800))
        let suggested = try XCTUnwrap(body.range(of: "HomeSuggestedPeopleView("))
        let search = try XCTUnwrap(body.range(of: "L(\"写真や人を探す\""))
        XCTAssertLessThan(suggested.lowerBound, search.lowerBound, "おすすめの人が先")
        XCTAssertTrue(body.contains("page == .following, let userId = auth.userId, !suggestedPeople(userId).isEmpty"))
    }

    /// UI テストの見本の通信: `-JPPreviewFollowNone` で誰もフォローしていないことにし、フォローは受けたことにする
    func testPreviewFollowNoneAnswersAnEmptyFollowingList() async throws {
        let list = await PreviewBackend.reply(method: "GET", route: ["user", "following"], body: nil, userId: "me",
                                              followNone: true, publicLikes: { _ in nil })
        let ids = try XCTUnwrap(JSONSerialization.jsonObject(with: list.body) as? [String: Any])["userIds"] as? [String]
        XCTAssertEqual(ids, [])
        let follow = await PreviewBackend.reply(method: "POST", route: ["users", "U1", "follow"], body: nil, userId: "me",
                                                followNone: true, publicLikes: { _ in nil })
        XCTAssertEqual(follow.status, 200)
        XCTAssertEqual(try XCTUnwrap(JSONSerialization.jsonObject(with: follow.body) as? [String: Any])["following"] as? Bool,
                       true)
        let off = await PreviewBackend.reply(method: "GET", route: ["user", "following"], body: nil, userId: "me",
                                             publicLikes: { _ in nil })
        XCTAssertNotEqual(off.status, 200, "旗が無ければ今までどおり答えない")
    }

    // MARK: - ⑤ 撮影スポットを DM で送る

    private let site = URL(string: "https://journey-photo.com")!

    func testSpotSlugIsReadOnlyFromThisSitesSpotPages() {
        XCTAssertEqual(DMSpotShare.slug(in: "https://journey-photo.com/spots/kenrokuen", siteBase: site), "kenrokuen")
        XCTAssertEqual(DMSpotShare.slug(in: "雪吊り https://www.journey-photo.com/spots/kenrokuen 見に行かない？",
                                        siteBase: site), "kenrokuen")
        XCTAssertNil(DMSpotShare.slug(in: "https://example.com/spots/kenrokuen", siteBase: site), "ほかのサイト")
        XCTAssertNil(DMSpotShare.slug(in: "https://journey-photo.com/location/kanazawa", siteBase: site), "撮影地の頁")
        XCTAssertNil(DMSpotShare.slug(in: "https://journey-photo.com/spots", siteBase: site), "スラッグが無い")
        XCTAssertNil(DMSpotShare.slug(in: "https://journey-photo.com/spots/a/b", siteBase: site))
        XCTAssertNil(DMSpotShare.slug(in: "spots/kenrokuen", siteBase: site))
    }

    func testSpotMessageIsTheLinkAndTheBubbleKeepsTheRest() {
        let url = URL(string: "https://journey-photo.com/spots/kenrokuen")!
        let text = DMSpotShare.message(pageURL: url)
        XCTAssertEqual(text, url.absoluteString, "送るのは頁のリンクだけ（サーバーの口は変えない）")
        XCTAssertNil(DMSpotShare.remainder(text, siteBase: site), "リンクだけの通は札だけ")
        XCTAssertEqual(DMSpotShare.remainder("雪吊り、見に行かない？ \(text)", siteBase: site), "雪吊り、見に行かない？")
        XCTAssertEqual(DMSpotShare.remainder("ふつうの文", siteBase: site), "ふつうの文")
    }

    /// 種類は「観光スポット」（2026-11-12 owner 承認）。「見頃」は言わない。読み上げの区切りは「、」
    func testSpotCardWordsUseSightseeingSpotAndNoPeak() {
        XCTAssertEqual(DMSpotShare.kindLabel, L("観光スポット", "Sightseeing spot"))
        XCTAssertEqual(DMSpotShare.spoken(name: "兼六園", region: "石川県 金沢市", mine: false),
                       L("届いた観光スポット、兼六園、石川県 金沢市", "Spot received、兼六園、石川県 金沢市"))
        XCTAssertEqual(DMSpotShare.spoken(name: "兼六園", region: nil, mine: true), L("送った観光スポット、兼六園", "Spot you sent、兼六園"))
    }

    /// 🔴 この枝で足した画面の文に中黒の区切り（「・」「·」）を使わない（2026-11-12 の決まり）。
    /// 新しく足した文に「撮影スポット」を使わない（呼び名は「観光スポット」）
    func testNewWordsHaveNoMiddleDotsAndUseTheNewSpotName() throws {
        let files = ["Sources/JourneyPhoto/Core/Text/SuggestedPeople.swift",
                     "Sources/JourneyPhoto/Core/Text/DMSpotShare.swift",
                     "Sources/JourneyPhoto/Features/Gallery/HomeSuggestedPeopleView.swift",
                     "Sources/JourneyPhoto/Features/Messages/DMSpotCard.swift",
                     "Sources/JourneyPhoto/Features/Upload/PostedShareCard.swift"]
        for file in files {
            let text = try source(file)
            for line in text.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                // 画面の文（L("…") と、文をつなぐ "…" の字）だけを見る
                let code = line.components(separatedBy: "//").first ?? line
                guard code.contains("\"") else { continue }
                XCTAssertFalse(code.contains("·") || code.contains("・"), "\(file): 中黒の区切り: \(line)")
                XCTAssertFalse(code.contains("L(\"撮影スポット") || code.contains("撮影スポットを") || code.contains("撮影スポットの頁"),
                               "\(file): 新しい文は「観光スポット」: \(line)")
            }
        }
        XCTAssertTrue(try source("Sources/JourneyPhoto/Features/Messages/DMSpotCard.swift").contains("HStack(spacing: 6) {\n                            Text(DMSpotShare.kindLabel)"))
        XCTAssertTrue(try source("Sources/JourneyPhoto/Features/Gallery/HomeSuggestedPeopleView.swift").contains("HStack(spacing: 8) {\n                                Text(SuggestedPeople.countLine(person))"))
    }

    /// 撮影スポットの「送る」シートの行動: リンクをコピー（頁）とほかのアプリ（今までの ↑ と同じ文）。ストーリーは無し
    func testSpotSendSheetActions() {
        let url = URL(string: "https://journey-photo.com/spots/kenrokuen")!
        let actions = SendSheetLayout.spotActions(pageURL: url, shareText: "兼六園\n石川")
        XCTAssertEqual(actions.map(\.id), ["copy", "other"])
        guard case .copyLink(let copied) = actions[0], case .otherAppsText(let text) = actions[1] else {
            return XCTFail("並びが違う")
        }
        XCTAssertEqual(copied, url)
        XCTAssertEqual(text, "兼六園\n石川")
    }

    /// 撮影スポットの頁の右上は、頁のある撮影スポットなら「送る」シート、下書きは今までの共有だけ（入口は増やさない）
    func testSpotPageShareOpensTheSendSheet() throws {
        let view = try source("Sources/JourneyPhoto/Features/Spots/OfficialSpotView.swift")
        XCTAssertTrue(view.contains("if spotPageURL != nil {\n                        Button { Task { await openSendSheet() } }"))
        XCTAssertTrue(view.contains("DMSpotShare.send(service: environment.dm"))
        XCTAssertTrue(view.contains(".sheet(isPresented: $showSendSheet) { sendSheet }"))
        let dm = try source("Sources/JourneyPhoto/Features/Messages/DMConversationView.swift")
        XCTAssertTrue(dm.contains("DMSpotCard(slug: spotSlug, mine: message.mine, fallback: message.text)"),
                      "届いた頁のリンクは札にする")
        let card = try source("Sources/JourneyPhoto/Features/Messages/DMSpotCard.swift")
        XCTAssertTrue(card.contains(".accessibilityAddTraits(.isButton)\n            .accessibilityHint(L(\"観光スポットの頁を開きます\""),
                      "札を畳んだあとにボタンの印が無い（読み上げ・UI テストで押せる物と分からない）")
    }

    // MARK: - ① 投稿したら共有カード

    /// 投稿画面の「SNS にも載せる」の行は無くし、投稿のあとにカードの画面を出す
    func testUploadShowsTheCardInsteadOfTheToggle() throws {
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertFalse(upload.contains("threadsRow"), "切り替えの行は無くした")
        XCTAssertFalse(upload.contains("L(\"SNS にも載せる\""), "切り替えの言葉も残さない")
        XCTAssertTrue(upload.contains(".sheet(item: $model.postedCard, onDismiss: { dismiss() }) { card in\n            PostedShareCardSheet(card: card)"))
        XCTAssertTrue(upload.contains("if model.postedCard == nil { dismiss() }"))
    }

    /// カードに焼き込む名前と情報。プロフィールが読めなくても写真の名前で作る・位置は約50kmに丸める
    func testPostedCardCreditWithoutProfile() throws {
        let json = """
        {"id":"p1","src":"https://x/p1.jpg","displayName":"あや","location":"石川県金沢市 兼六園",
         "coords":{"lat":36.5621,"lng":136.6625},"exif":{"camera":"X100V","iso":200}}
        """
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
        let credit = PostedShareCardCredit.make(photo: photo, me: nil)
        XCTAssertEqual(credit.name, "あや")
        XCTAssertNil(credit.username)
        XCTAssertEqual(credit.camera, "X100V")
        XCTAssertEqual(credit.iso, 200)
        XCTAssertEqual(credit.coords?.latitude, 36.5)
        XCTAssertEqual(credit.coords?.longitude, 136.5)
        XCTAssertFalse(credit.verified)
    }

    /// 投稿の完了のカードの画面: 頭に「投稿しました」、主ボタンは「カードを共有」、下に「ストーリーに載せる」「リンクをコピー」「閉じる」
    func testPostedCardSheetWording() throws {
        XCTAssertEqual(PostedShareCardText.eyebrow, L("投稿しました", "Posted"))
        XCTAssertEqual(PostedShareCardText.title, L("カードにして、ほかの SNS にも", "Turn it into a card for other social apps"))
        let sheet = try source("Sources/JourneyPhoto/Features/Common/SignatureShareCardSheet.swift")
        XCTAssertTrue(sheet.contains("posted == nil ? L(\"この画像を共有\", \"Share this image\") : L(\"カードを共有\", \"Share card\")"))
        for id in ["postedCard.story", "postedCard.copyLink", "postedCard.close", "postedCard.header"] {
            XCTAssertTrue(sheet.contains("\"\(id)\""), id)
        }
    }
}
