import XCTest
@testable import JourneyPhoto

/// 投稿の前のプレビュー（札 #409・案A・`PostPreview`）。投稿したあとの写真の行を作り、
/// ホーム・マイページの部品へ渡す並びを決める
final class PostPreviewTests: XCTestCase {

    private let me = "me-1"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ n: Int, title: String = "", location: String = "") -> PostPreview.Item {
        PostPreview.Item(title: title, caption: "朝の霧", location: location,
                         imageURL: URL(fileURLWithPath: "/tmp/post-preview/\(n).jpg"),
                         thumbnailURL: URL(fileURLWithPath: "/tmp/post-preview/\(n)_thumb.jpg"),
                         pixelWidth: 4000, pixelHeight: 3000, takenOn: "2026-11-15", dominantColor: "#334455")
    }

    private func photos(count: Int, published: Bool = true, audience: Audience = .everyone,
                        grouped: Bool = true) -> [Photo] {
        PostPreview.photos((0..<count).map { item($0, title: "題\($0)", location: "上高地") },
                           userId: me, displayName: "旅人ハル", published: published, audience: audience,
                           grouped: grouped, category: "", tags: [], now: now)
    }

    private func other(_ id: String, owner: String = "someone", group: String? = nil, likes: Int = 0) -> Photo {
        var row: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg", "userId": owner, "likes": likes,
                                  "published": true, "createdAt": "2026-01-01T00:00:00Z"]
        if let group { row["groupId"] = group }
        let data = try! JSONSerialization.data(withJSONObject: row)
        return try! JSONDecoder.api.decode(Photo.self, from: data)
    }

    // MARK: - 写真の行

    /// 入力中の題・説明・撮影地・画像（`file://`）・持ち主・公開範囲が、投稿したあとの行の形で入る
    func testRowCarriesWhatIsBeingTyped() {
        let rows = PostPreview.photos([item(0, title: " 朝霧の河童橋 ", location: "上高地")], userId: me,
                                      displayName: "旅人ハル", published: true, audience: .followers,
                                      grouped: true, category: "landscape", tags: ["霧"], now: now)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.displayTitle, "朝霧の河童橋", "題の前後の空白を落としていない")
        XCTAssertEqual(row.location, "上高地")
        XCTAssertEqual(row.paragraphs, ["朝の霧"])
        XCTAssertEqual(row.detailImageURL?.isFileURL, true, "詳細の画像が端末の一時ファイルでない")
        XCTAssertEqual(row.gridImageURL?.lastPathComponent, "0_thumb.jpg", "格子が小さい画像を使わない")
        XCTAssertEqual(row.userId, me)
        XCTAssertEqual(row.displayName, "旅人ハル")
        XCTAssertEqual(row.published, true)
        XCTAssertEqual(row.audience, "followers")
        XCTAssertEqual(row.category, "landscape")
        XCTAssertEqual(row.tags, ["霧"])
        XCTAssertEqual(row.aspectRatio ?? 0, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertTrue(PostPreview.isPreview(row))
        XCTAssertNil(row.groupId, "1枚だけなのに束の印を付けた")
    }

    /// 撮影情報と曲も詳細に出る形で入る（2026-11-15 確かめ役の指摘）
    func testRowCarriesExifAndSong() {
        var source = item(0)
        source.exif = ExifFields(camera: "X-T5", lens: nil, aperture: "f/8", exposure: nil, iso: 200,
                                 focalLength: nil, dateTimeOriginal: nil)
        let song = Photo.Song(title: "朝", artist: "誰か", artwork: nil, previewUrl: "https://example.com/a.m4a",
                              trackUrl: nil)
        let row = PostPreview.photos([source], userId: me, displayName: nil, published: true, audience: .everyone,
                                     grouped: false, category: "", tags: [], song: song, now: now)[0]
        XCTAssertEqual(row.exif?.camera, "X-T5")
        XCTAssertEqual(row.exif?.iso, 200)
        XCTAssertEqual(row.song, song)
        let empty = PostPreview.photos([item(0)], userId: me, displayName: nil, published: true, audience: .everyone,
                                       grouped: false, category: "", tags: [], now: now)[0]
        XCTAssertNil(empty.exif)
        XCTAssertNil(empty.song)
    }

    /// 空の題・撮影地は付けない（ホームの札は撮影地が空なら字が出ない＝投稿したあとと同じ）
    func testEmptyFieldsStayEmpty() {
        let row = PostPreview.photos([item(0)], userId: me, displayName: nil, published: true, audience: .everyone,
                                     grouped: false, category: "", tags: [], now: now)[0]
        XCTAssertEqual(row.displayTitle, "")
        XCTAssertNil(row.location)
        XCTAssertNil(row.audience, "全体に公開なのに公開範囲の印を付けた")
        XCTAssertNil(row.displayName)
    }

    /// 非公開は `published: false`（マイページの「非公開」の札と沈みは格子の部品が出す）。公開範囲の印は付けない
    func testPrivateRowIsUnpublished() {
        let rows = photos(count: 2, published: false, audience: .followers)
        XCTAssertTrue(rows.allSatisfy { $0.published == false })
        XCTAssertTrue(rows.allSatisfy { $0.audience == nil })
    }

    /// まとめる・別々で束の印が変わり、束の中は選んだ順
    func testGroupingFollowsTheChoice() {
        let grouped = photos(count: 3, grouped: true)
        XCTAssertEqual(Set(grouped.map(\.groupId)), [PostPreview.groupId])
        XCTAssertEqual(PhotoGroups.group(grouped).count, 1)
        XCTAssertEqual(PhotoGroups.group(grouped)[0].photos.map(\.id), grouped.map(\.id), "束の中の順が選んだ順でない")
        let separate = photos(count: 3, grouped: false)
        XCTAssertTrue(separate.allSatisfy { $0.groupId == nil })
        XCTAssertEqual(PhotoGroups.group(separate).count, 3)
    }

    // MARK: - ホーム

    /// 本物のホームと同じ並べ方（`HomeFeed.arrange`）。今回の投稿は新着の先頭なので、いいね順 3 つの後の4番目に出る
    /// （先頭の大きい札ではない・2026-11-15 確かめ役の指摘）。まとめた投稿は1枚の札
    func testHomeUsesTheRealArrangement() {
        let neighbors = (0..<10).map { other("n\($0)", likes: 10 - $0) }
        let groups = PostPreview.homeGroups(preview: photos(count: 3, grouped: true), published: true,
                                            neighbors: neighbors, viewerId: me)
        let index = groups.firstIndex { PostPreview.isPreview($0.cover) }
        XCTAssertEqual(index, HomeFeed.latestEvery - 1, "今回の投稿が本物の新着の位置（4番目）に無い")
        XCTAssertEqual(groups[index ?? 0].count, 3, "まとめた投稿が1枚の札（3枚の束）になっていない")
        XCTAssertEqual(groups.prefix(3).map(\.id), ["n0", "n1", "n2"], "前の3つがいいね順でない")
        XCTAssertEqual(groups.filter { PostPreview.isPreview($0.cover) }.count, 1)
        XCTAssertGreaterThanOrEqual(groups.count, PostPreview.homeTileLimit)
    }

    /// 「それぞれ別の投稿」は選んだ枚数ぶんの札で、新着の並びで1つずつ入る（4番目・8番目…）。札は全部見せる
    func testSeparatePostsEachGetALatestSlot() {
        let neighbors = (0..<20).map { other("n\($0)", likes: 30 - $0) }
        let groups = PostPreview.homeGroups(preview: photos(count: 3, grouped: false), published: true,
                                            neighbors: neighbors, viewerId: me)
        let slots = groups.indices.filter { PostPreview.isPreview(groups[$0].cover) }
        XCTAssertEqual(slots, [3, 7, 11], "別々の投稿が新着の位置に1つずつ入っていない")
        XCTAssertTrue(slots.allSatisfy { groups[$0].count == 1 })
        XCTAssertEqual(groups.count, 12, "最後の投稿の札まで並べていない")
    }

    /// 非公開はホームに出ない（今回の投稿の札は無く、ほかの人の札だけ）
    func testPrivatePostIsNotOnHome() {
        XCTAssertFalse(PostPreview.showsOnHome(published: false))
        XCTAssertTrue(PostPreview.showsOnHome(published: true))
        let groups = PostPreview.homeGroups(preview: photos(count: 2, published: false), published: false,
                                            neighbors: [other("n0")], viewerId: me)
        XCTAssertEqual(groups.map(\.id), ["n0"])
    }

    // MARK: - マイページ

    /// マイページは1枚ずつ（束ねない）で今回の投稿が自分の写真の先頭。まとめた投稿には複数枚の印が付く
    func testMyPageListsEachPhotoFirst() {
        let preview = photos(count: 3, grouped: true)
        let mine = (0..<20).map { other("m\($0)", owner: me) }
        let grid = PostPreview.myGrid(preview: preview, mine: mine)
        XCTAssertEqual(Array(grid.prefix(3).map(\.id)), preview.map(\.id))
        XCTAssertEqual(grid.count, PostPreview.myGridLimit)
        XCTAssertEqual(PhotoGroups.multiPhotoIds(grid), Set(preview.map(\.id)))
        let separate = photos(count: 3, grouped: false)
        XCTAssertTrue(PhotoGroups.multiPhotoIds(PostPreview.myGrid(preview: separate, mine: [])).isEmpty)
    }

    /// ピン留めした写真は今回の投稿より前（本物のマイページと同じ `PhotoPinning.pinnedFirst`）
    func testMyPageKeepsPinnedFirst() {
        let preview = photos(count: 1)
        let mine = (0..<5).map { other("m\($0)", owner: me) }
        let grid = PostPreview.myGrid(preview: preview, mine: mine, pinned: ["m3"])
        XCTAssertEqual(grid.prefix(2).map(\.id), ["m3", preview[0].id])
    }

    // MARK: - 一時ファイルと読み上げ

    /// 開くたびに別の置き場（同じ名前だと、縮めた絵の控えが前の写真を出す）
    func testEachOpenUsesItsOwnDirectory() {
        let base = URL(fileURLWithPath: "/tmp")
        let first = PostPreview.directory(base: base), second = PostPreview.directory(base: base)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent(), PostPreview.root(base: base))
        let rows = photos(count: 2)
        XCTAssertEqual(Set(PostPreview.fileURLs(rows).map(\.lastPathComponent)),
                       ["0.jpg", "0_thumb.jpg", "1.jpg", "1_thumb.jpg"])
        XCTAssertTrue(PostPreview.fileURLs([other("web")]).isEmpty, "サーバーの写真の控えまで捨てる")
    }

    /// 縮めた絵の控えから、その URL の分だけ捨てられる
    func testDecodedMemoryRemovesOneURL() {
        let memory = DecodedImageMemory<String>()
        let a = URL(fileURLWithPath: "/tmp/post-preview/x/0.jpg"), b = URL(fileURLWithPath: "/tmp/b.jpg")
        memory.store("A", pixels: 100, for: a, cost: 1)
        memory.store("B", pixels: 100, for: b, cost: 1)
        memory.remove(a)
        XCTAssertNil(memory.entry(for: a))
        XCTAssertEqual(memory.entry(for: b)?.image, "B")
    }

    /// 縮めたページのまとめの読み上げ・今回の投稿の札の読み上げ（中黒で区切らない）
    func testSpokenSummaries() {
        let detail = PostPreview.pageSummary(.detail, title: "朝霧", location: "上高地", published: true, position: nil)
        XCTAssertTrue(detail.contains("朝霧") && detail.contains("上高地"))
        XCTAssertTrue(PostPreview.pageSummary(.home, title: "", location: "", published: true, position: 4).contains("4"))
        XCTAssertTrue(PostPreview.pageSummary(.home, title: "", location: "", published: false, position: nil)
            .contains(PostPreview.homeHiddenTitle))
        XCTAssertTrue(PostPreview.spokenTile(yours: true, "上高地").hasPrefix(PostPreview.yoursTag))
        XCTAssertEqual(PostPreview.spokenTile(yours: false, "上高地"), "上高地")
        for text in [detail, PostPreview.pageSummary(.myPage, title: "", location: "", published: true, position: 1)] {
            XCTAssertFalse(text.contains("・") || text.contains("·"))
        }
    }

    // MARK: - 帯と1行

    /// 読み込み中・送っている間・写真が無い間は押せない
    func testPreviewButtonWaitsLikeTheSubmitButton() {
        XCTAssertTrue(PostPreview.canOpen(hasPhotos: true, loading: false, working: false))
        XCTAssertFalse(PostPreview.canOpen(hasPhotos: true, loading: true, working: false))
        XCTAssertFalse(PostPreview.canOpen(hasPhotos: true, loading: false, working: true))
        XCTAssertFalse(PostPreview.canOpen(hasPhotos: false, loading: false, working: false))
    }

    /// アクセシビリティの大きさでは帯を縦に積む
    func testBarStacksAtAccessibilitySizes() {
        XCTAssertTrue(PostPreview.stacksBar(accessibilitySize: true))
        XCTAssertFalse(PostPreview.stacksBar(accessibilitySize: false))
    }

    /// 公開範囲の1行。中黒で区切らない
    func testAudienceLine() {
        XCTAssertEqual(PostPreview.audienceLine(published: false, audience: .everyone).symbol, "lock")
        XCTAssertEqual(PostPreview.audienceLine(published: true, audience: .everyone).symbol, "globe")
        XCTAssertTrue(PostPreview.audienceLine(published: true, audience: .followers).text
            .hasSuffix(Audience.followers.photoNote), "写真の公開範囲の言葉（ウェブサイトに載らない）でない")
        for audience in Audience.allCases {
            for published in [true, false] {
                let text = PostPreview.audienceLine(published: published, audience: audience).text
                XCTAssertFalse(text.contains("・") || text.contains("·"), "中黒で区切った: \(text)")
            }
        }
    }

    /// 画面の言葉に「捨てる」「撮りどき」を使わない。帯に「プレビュー」、切り替えの下の説明の1行は消した
    func testWordingAndWiring() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let sheet = try source("Sources/JourneyPhoto/Features/Upload/PostPreviewSheet.swift")
        let rules = try source("Sources/JourneyPhoto/Features/Upload/PostPreview.swift")
        for text in [sheet, rules] {
            XCTAssertFalse(text.contains("捨て"))
            XCTAssertFalse(text.contains("撮りどき"))
        }
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("accessibilityIdentifier(\"upload.preview\")"), "帯に「プレビュー」が無い")
        XCTAssertTrue(upload.contains("PostPreviewSheet(model: model)"))
        XCTAssertFalse(upload.contains("一覧では1枚のカードにまとまり、左右に送れます（"), "切り替えの下の説明の1行が残っている")
        XCTAssertFalse(upload.contains("それぞれ別の投稿として並びます"), "切り替えの下の説明の1行が残っている")
        // 描き方の写しを作らない: 投稿したあとの部品をそのまま使う
        XCTAssertTrue(sheet.contains("PhotoDetailView(photo: first, fromPublicFeed: false, context: photos, postPreview: true)"))
        XCTAssertTrue(sheet.contains("HomeMosaic(groups: groups"))
        XCTAssertTrue(sheet.contains("MyPageGridCell(photo: photo"))
        // 左右の払いは祖先の縦の送りにパンを足す作り（`ProfileSwipePanHost.attach`）。送りの外に置くと払っても替わらない
        // （Mac run 1341）
        XCTAssertTrue(sheet.contains("ScrollView {\n                        ProfileTabPager(tabs: PostPreview.Page.allCases"),
                      "ページの入れ物が縦の送りの中に無い（払っても札が替わらない）")
        XCTAssertTrue(sheet.contains(".scrollDisabled(true)"))
        // VoiceOver の操作を中の本物の部品に届かせない（中は読み上げから外し、まとめの言葉で言う）
        XCTAssertTrue(sheet.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(sheet.contains(".accessibilityLabel(summary(option))"))
        // 閉じたら、その URL の控えと一時ファイルを捨てる。書いている間に閉じた回も書き終えた所で消す
        XCTAssertTrue(sheet.contains("DownsampledRemoteImage.memory.remove(url)"))
        XCTAssertTrue(sheet.contains("guard !Task.isCancelled else { removeFiles(); return }"))
        XCTAssertTrue(sheet.contains("pinned: pinned.contains(photo.id)"), "マイページの格子にピン留めを渡していない")
        let myPage = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        XCTAssertTrue(myPage.contains("MyPageGridCell(photo: photo, multiple: multiple, pinned: model.isPinned(photo.id))"),
                      "マイページがプレビューと同じ格子の部品を使っていない")
    }
}
