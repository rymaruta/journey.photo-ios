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

    private func other(_ id: String, owner: String = "someone", group: String? = nil) -> Photo {
        var row: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg", "userId": owner]
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

    /// 「1つの投稿にまとめる」はホームで1枚の札、「それぞれ別の投稿」は選んだ枚数ぶんの札（2026-11-15 判断）。
    /// 今回の投稿が先頭で、後ろにほかの人の札
    func testHomeShowsOneCardWhenGroupedAndEveryCardWhenSeparate() {
        let neighbors = (0..<10).map { other("n\($0)") }
        let grouped = PostPreview.homeGroups(preview: photos(count: 3, grouped: true), published: true,
                                             neighbors: neighbors, me: me)
        XCTAssertEqual(grouped.first?.count, 3, "まとめた投稿が1枚の札（3枚の束）になっていない")
        XCTAssertTrue(PostPreview.isPreview(grouped[0].cover))
        XCTAssertFalse(PostPreview.isPreview(grouped[1].cover))
        XCTAssertEqual(grouped.count, 1 + PostPreview.homeNeighborLimit)

        let separate = PostPreview.homeGroups(preview: photos(count: 3, grouped: false), published: true,
                                              neighbors: neighbors, me: me)
        XCTAssertEqual(separate.prefix(3).map { PostPreview.isPreview($0.cover) }, [true, true, true],
                       "別々の投稿なのに札の数が選んだ枚数と違う")
        XCTAssertTrue(separate.prefix(3).allSatisfy { $0.count == 1 })
        XCTAssertEqual(separate.count, 3 + PostPreview.homeNeighborLimit)
    }

    /// 非公開はホームに出ない（今回の投稿の札は無く、ほかの人の札だけ）
    func testPrivatePostIsNotOnHome() {
        XCTAssertFalse(PostPreview.showsOnHome(published: false))
        XCTAssertTrue(PostPreview.showsOnHome(published: true))
        let groups = PostPreview.homeGroups(preview: photos(count: 2, published: false), published: false,
                                            neighbors: [other("n0")], me: me)
        XCTAssertEqual(groups.map(\.id), ["n0"])
    }

    /// ほかの人の札に、自分の写真（もう投稿した分）を混ぜない。ほかの人の束は束のまま
    func testHomeNeighborsSkipMyOwnPhotos() {
        let neighbors = [other("mine", owner: me), other("a", group: "g"), other("b", group: "g"), other("c")]
        let groups = PostPreview.homeGroups(preview: photos(count: 1), published: true, neighbors: neighbors, me: me)
        XCTAssertEqual(groups.dropFirst().map(\.id), ["a", "c"])
        XCTAssertEqual(groups[1].count, 2)
    }

    // MARK: - マイページ

    /// マイページは1枚ずつ（束ねない）で今回の投稿が先頭。まとめた投稿には複数枚の印が付く
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
        let myPage = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        XCTAssertTrue(myPage.contains("MyPageGridCell(photo: photo, multiple: multiple, pinned: model.isPinned(photo.id))"),
                      "マイページがプレビューと同じ格子の部品を使っていない")
    }
}
