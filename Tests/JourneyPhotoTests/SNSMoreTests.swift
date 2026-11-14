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

    /// 札 #595: 「フォロー中」の札が無くなったので、**誰もフォローしていないログイン中の人には、1本の並びの中**
    /// （ひと回りと季節の段の後ろ）に「おすすめの人」を出す（並べる人がいれば）。フォローしたら頭へ送り、上の段にその人の写真
    func testFollowingNobodyShowsSuggestedPeopleInTheFeed() throws {
        let gallery = try source("Sources/JourneyPhoto/Features/Gallery/GalleryView.swift")
        let start = try XCTUnwrap(gallery.range(of: "private func feedSection(_ rows: HomeFeedPageMemo.Rows, featured: [FeaturedGroups.Group]) -> some View {"))
        let body = String(gallery[start.upperBound...].prefix(4000))
        let shelf = try XCTUnwrap(body.range(of: "HomeSpotShelfView("))
        let suggested = try XCTUnwrap(body.range(of: "HomeSuggestedPeopleView("))
        let rest = try XCTUnwrap(body.range(of: "HomeMosaic(groups: rows.rest"))
        XCTAssertLessThan(shelf.lowerBound, suggested.lowerBound, "写真より先におすすめの人を出している")
        XCTAssertLessThan(suggested.lowerBound, rest.lowerBound)
        XCTAssertTrue(body.contains("if !isEmpty, let userId = auth.userId, model.following(for: userId).isEmpty,"),
                      "フォローしている人にもおすすめの人を出している")
        let after = try XCTUnwrap(gallery.range(of: "private func showFollowingAfterSuggested("))
        XCTAssertTrue(String(gallery[after.upperBound...].prefix(800)).contains("scrollToTopRequests &+= 1"),
                      "フォローしても上の段（フォロー中の人の新しい写真）へ送らない")
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
                       L("届いた観光スポット、兼六園、石川県 金沢市", "Spot received, 兼六園, 石川県 金沢市"))
        XCTAssertEqual(DMSpotShare.spoken(name: "兼六園", region: nil, mine: true), L("送った観光スポット、兼六園", "Spot you sent, 兼六園"))
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
        XCTAssertTrue(try source("Sources/JourneyPhoto/Features/Messages/DMSpotCard.swift").contains("HStack(spacing: 6) {\n                Text(DMSpotShare.kindLabel)"))
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
        XCTAssertTrue(dm.contains("DMSpotCard(slug: spotSlug, mine: message.mine,\n                                       fallback: DMSpotShare.link(in: message.text, siteBase: AppConfig.siteBaseURL)"),
                      "届いた頁のリンクは札にする・札が作れなければ拾ったリンクだけを出す")
        let card = try source("Sources/JourneyPhoto/Features/Messages/DMSpotCard.swift")
        XCTAssertTrue(card.contains(".accessibilityAddTraits(.isButton)\n            .accessibilityHint(L(\"観光スポットのページを開きます\""),
                      "札を畳んだあとにボタンの印が無い（読み上げ・UI テストで押せる物と分からない）")
    }

    /// 札が作れなかったときに出すのは、拾ったリンクだけ（文全体を出さない）
    func testSpotLinkIsPickedOutOfTheText() {
        XCTAssertEqual(DMSpotShare.link(in: "雪吊り https://journey-photo.com/spots/kenrokuen 見に行かない？", siteBase: site),
                       "https://journey-photo.com/spots/kenrokuen")
        XCTAssertNil(DMSpotShare.link(in: "ふつうの文", siteBase: site))
    }

    private func thread(_ peer: String, _ state: DMEntryState) -> DMThread {
        DMThread(id: "c-\(peer)", peerId: peer, name: peer, t: "2026-11-12T00:00:00Z", excerpt: "", unread: 0, state: state)
    }

    /// 🔴 観光スポット（リンク）は承認前の会話に届かない。会話が無い・こちらから始めて承認待ちの相手は顔を薄くする。
    /// 受信箱・相手からのリクエスト（返信で承認になる）は薄くしない。受信箱を読めていなければ薄くしない
    func testUnreachablePeersForSpotLinks() {
        let people = ["inbox", "request", "pending", "none"].map { FollowUser(id: $0, name: $0, deleted: nil) }
        let inbox = DMInbox(items: [thread("inbox", .inbox), thread("request", .request), thread("pending", .pending)],
                            unread: 0, requestCount: 1)
        XCTAssertEqual(DMSpotShare.unreachablePeers(people, inbox: inbox, inboxLoaded: true), ["pending", "none"])
        XCTAssertEqual(DMSpotShare.unreachablePeers(people, inbox: inbox, inboxLoaded: false), [])
    }

    /// サーバーが `requestUrl` で断ったら、URL の言葉ではなく観光スポットの言葉を出す
    func testSpotRefusalWording() {
        let refused = DMService.Refused(status: 400, message: "承認されるまではリンクを送れません", code: "requestUrl")
        XCTAssertEqual(DMSpotShare.failureText(refused), DMSpotShare.refusedBeforeAccept)
        XCTAssertFalse(DMSpotShare.failureText(refused).contains("URL"))
        let other = DMService.Refused(status: 400, message: "x", code: "blockedByMe")
        XCTAssertEqual(DMSpotShare.failureText(other), other.errorDescription)
        let view = try? source("Sources/JourneyPhoto/Features/Spots/OfficialSpotView.swift")
        XCTAssertTrue(view?.contains("toasts.show(DMSpotShare.failureText(error), kind: .failure)") ?? false)
        XCTAssertTrue(view?.contains("DMPeopleFacesRow(people: faces,\n                                     dimmed: DMSpotShare.unreachablePeers(") ?? false,
                      "送れない相手の顔を薄くしていない")
    }

    // MARK: - 投稿のたびのカード（閉じるだけが2回続いたら知らせだけ）

    func testPostedCardHabitQuietsAfterTwoClosesAndResetsOnShare() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SNSMoreTests.habit"))
        defaults.removePersistentDomain(forName: "SNSMoreTests.habit")
        XCTAssertTrue(PostedCardHabit.showsCard(defaults: defaults), "はじめはカードを出す")
        PostedCardHabit.noteFinished(shared: false, defaults: defaults)
        XCTAssertTrue(PostedCardHabit.showsCard(defaults: defaults), "1回閉じただけではまだ出す")
        PostedCardHabit.noteFinished(shared: false, defaults: defaults)
        XCTAssertFalse(PostedCardHabit.showsCard(defaults: defaults), "2回続けて閉じたら知らせだけ")
        PostedCardHabit.noteFinished(shared: true, defaults: defaults)
        XCTAssertTrue(PostedCardHabit.showsCard(defaults: defaults), "一度でも共有したら毎回カードに戻す")
        PostedCardHabit.noteFinished(shared: false, defaults: defaults)
        PostedCardHabit.noteFinished(shared: true, defaults: defaults)
        XCTAssertTrue(PostedCardHabit.showsCard(defaults: defaults), "共有で数え直す（続けて閉じた回だけ数える）")
        defaults.removePersistentDomain(forName: "SNSMoreTests.habit")
    }

    /// UI テストで投稿する所は、閉じた回数の鍵を起動の引数で 0 にしている（2026-11-12 確かめ役の指摘）。
    /// 無いと、同じ模擬機で投稿を3回目からカードが出ず知らせだけになり、カードを待つ試験が落ちる。
    /// UI テストの鍵の名前がアプリの鍵（`PostedCardHabit.defaultsKey`）と同じかも見る
    func testUITestsResetPostedCardHabitWhereTheyPost() throws {
        let critical = try source("UITests/JourneyPhotoUITests/CriticalFlowTests.swift")
        XCTAssertTrue(critical.contains("static let postedCardHabitKey = \"\(PostedCardHabit.defaultsKey)\""),
                      "UI テストの鍵の名前がアプリの鍵と違う")
        for file in ["CriticalFlowTests.swift", "ScreenshotTests.swift"] {
            let text = try source("UITests/JourneyPhotoUITests/\(file)")
            // 投稿の「投稿する」を押す試験ごとに、その試験の中で鍵を 0 にしているか
            for chunk in text.components(separatedBy: "    func test").dropFirst()
            where chunk.contains("\"upload.submit\"") {
                let name = chunk.prefix { $0 != "(" }
                let launchesWithReset = chunk.contains("postedCardHabitKey)\", \"0\"]")
                // CriticalFlowTests は共通の `launch` で入れる
                let sharedLaunch = file == "CriticalFlowTests.swift" && chunk.contains("launch(")
                    && critical.contains("app.launchArguments += [\"-\\(Self.postedCardHabitKey)\", \"0\"]")
                XCTAssertTrue(launchesWithReset || sharedLaunch, "\(file) の test\(name) が閉じた回数を 0 にせず投稿している")
            }
        }
    }

    /// 知らせの「カードにする」: 押せる一手を持った知らせ。押せばいちばん外の画面がカードを開く
    @MainActor
    func testQuietCardToastCarriesTheAction() async throws {
        let toasts = ToastCenter()
        var opened = false
        toasts.show(PostedCardHabit.quietText, actionTitle: PostedCardHabit.quietAction) { opened = true }
        XCTAssertEqual(toasts.current?.actionTitle, L("カードにする", "Make a card"))
        toasts.current?.action?()
        XCTAssertTrue(opened)
        toasts.show("x")
        XCTAssertNil(toasts.current?.actionTitle, "一手の無い知らせに一手を残さない")
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("PostedCardOffer.shared.offer(quiet)"))
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains(".sheet(item: $postedCardOffer.presented) { card in\n                PostedShareCardSheet(card: card)"))
        let sheet = try source("Sources/JourneyPhoto/Features/Common/SignatureShareCardSheet.swift")
        XCTAssertTrue(sheet.contains(".onDisappear { posted?.onFinish?(didShare) }"), "閉じたときに共有したかを覚えていない")
    }

    /// 手元にある自分のプロフィールがあれば、カードの画面は通信で待たない
    func testMyProfileCacheIsPerUser() throws {
        let json = #"{"userId":"me-1","displayName":"あや"}"#
        let profile = try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
        MyProfileCache.shared.remember(profile)
        XCTAssertEqual(MyProfileCache.shared.profile(for: "me-1")?.displayName, "あや")
        XCTAssertNil(MyProfileCache.shared.profile(for: "other"), "別の人の控えを使った")
        XCTAssertNil(MyProfileCache.shared.profile(for: nil))
        let sheet = try source("Sources/JourneyPhoto/Features/Upload/PostedShareCard.swift")
        XCTAssertTrue(sheet.contains("if let cached = MyProfileCache.shared.profile(for: auth.userId) {"))
        let service = try source("Sources/JourneyPhoto/Services/ProfileService.swift")
        XCTAssertTrue(service.contains("MyProfileCache.shared.remember(profile)\n        return profile"))
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
