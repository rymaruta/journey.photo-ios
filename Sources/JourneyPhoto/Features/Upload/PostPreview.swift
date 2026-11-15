import Foundation

/// 投稿の前のプレビュー（札 #409・案A。2026-11-15 owner「まかせる」で推奨の案Aに決まった）。
///
/// 投稿の画面の下の帯で、主ボタンの左に線の副ボタン「プレビュー」を置く。押すと、投稿したあとの
/// 「詳細」「ホーム」「マイページ」の見え方を左右に払って見られ、そのまま投稿できる（`PostPreviewSheet`）。
/// 案の模型: Artifact「投稿前プレビューの案」（https://claude.ai/artifact/8YHFyLJEHSd91qbuQrPsi3）。
///
/// 🔴 **描き方の写しは作らない。** 3つのページは、投稿したあとに出る部品をそのまま使う
/// （写真の詳細 `PhotoDetailView(postPreview: true)`・ホームの札 `HomeMosaic`・マイページの格子 `MyPageGridCell`）。
/// ここで作るのは、その部品に渡す「投稿したあとの写真の行」（`Photo`）だけ。画像は端末の一時ファイルの
/// `file://` を `src` に入れる（`DownsampledRemoteImage`・`RemoteImage` は `URLSession` で読むので、そのまま出る）。
///
/// 押す回数（案の模型どおり）: 投稿は今と同じ 1 回。見え方を見るのは 1 回（前は無かった）。見てから投稿で 2 回
enum PostPreview {

    /// プレビューの3つのページ（左右に払う順）
    enum Page: String, CaseIterable, PagedTab {
        case detail
        case home
        case myPage

        var tabTitle: String {
            switch self {
            case .detail: return L("詳細", "Detail")
            case .home: return L("ホーム", "Home")
            case .myPage: return L("マイページ", "My page")
            }
        }

        var tabIdentifier: String { "postPreview.tab.\(rawValue)" }
    }

    /// 1枚ぶんの入力（投稿の画面で入力中のもの）。画像は端末の一時ファイル
    struct Item: Equatable {
        var title: String
        var caption: String
        var location: String
        /// 本体（詳細の写真）の `file://`
        var imageURL: URL
        /// 一覧用の小さい画像（ホームの小さい札・マイページの格子）の `file://`。無ければ本体
        var thumbnailURL: URL?
        /// 画素の幅と高さ（縦横比に使う）。分からなければ nil
        var pixelWidth: Double?
        var pixelHeight: Double?
        var takenOn: String?
        var dominantColor: String?
        /// 撮影情報（投稿の画面が送るものと同じ・GPS は含まない）。詳細の「撮影情報」の行に出る
        var exif: ExifFields? = nil
    }

    /// 主ボタンの左の副ボタンの字（目の印と並べる）
    static let buttonTitle = L("プレビュー", "Preview")
    /// 副ボタンの印（SF Symbols）
    static let buttonSymbol = "eye"
    /// シートの題
    static let sheetTitle = L("プレビュー", "Preview")
    /// 今回の投稿に付ける札（写真の上なので白・プレビューの中だけの印）
    static let yoursTag = L("あなたの投稿", "Your post")
    /// 今回の投稿の枠の太さ（白・模型の 2pt）
    static let yoursFrameWidth: Double = 2
    /// 非公開のときにホームのページに出す見出しと本文
    static let homeHiddenTitle = L("ホームには出ません", "Not shown on Home")
    static let homeHiddenBody = L("非公開の写真は、あなたのマイページにだけ並びます。",
                                  "Private photos appear only on your My page.")
    /// 非公開のときのホームのほかの札の濃さ（模型の 50%）
    static let homeHiddenDimOpacity = 0.5

    /// ページの中の画面を縮める倍率（模型の 0.8 倍。行き先の画面だと分かる形にする）
    static let pageScale: Double = 0.8
    /// 縮めたページの角（模型の 24）
    static let pageCorner: Double = 24

    /// ホームのページに並べる札の数の下限。縮めた1ページに収まる分（大1・2・2 とその次の大1）。
    /// 今回の投稿がそれより後ろに入るときは、そこまで並べる
    static let homeTileLimit = 6
    /// マイページの格子に並べる数（今回の投稿を含む）。縮めた1ページで見える 3 列 × 5 段
    static let myGridLimit = 15

    /// プレビューの写真の id の頭。サーバーの id と重ならない
    static let idPrefix = "post-preview-"
    /// 「1つの投稿にまとめる」のときの束の印（`PhotoGroups.groupKey` が持ち主と組で束ねる）
    static let groupId = "post-preview"

    /// 副ボタンを押せるか。**写真を読み込んでいる間・送っている間・写真が無い間は押せない**
    /// （模型「読み込み中」: プレビューも投稿も 32% に薄め、理由は主ボタンの下の1行 `UploadSubmitBar.blockedReason`）
    static func canOpen(hasPhotos: Bool, loading: Bool, working: Bool) -> Bool {
        hasPhotos && !loading && !working
    }

    /// 帯の2つのボタンを縦に積むか。**アクセシビリティの大きさでは積む**（DesignSystem 06「横に並べたボタンを縦に積む」）。
    /// それより小さくても入らないとき（英語の長い字・狭い端末）は `ViewThatFits` が横 → 縦に替える
    static func stacksBar(accessibilitySize: Bool) -> Bool { accessibilitySize }

    /// 公開範囲の1行（シートのタブの下・印と字）。押す前に誰に見えるかが分かるように
    static func audienceLine(published: Bool, audience: Audience) -> (symbol: String, text: String) {
        guard published else {
            return ("lock", L("非公開。あなた以外には見えません", "Private. Only you can see it"))
        }
        // 「。」で区切る（中黒で並べない）。但し書きは写真の公開範囲の言葉（`Audience.photoNote`・2026-11-15 確かめ役の指摘で
        // そろえた。前はストーリーと同じ `note` で、ウェブサイトに載らないことが言えていなかった）
        return (audience.systemImage, audience.label + L("。", ". ") + audience.photoNote)
    }

    /// ホームに出るか。**非公開はホームに出ない**（公開の一覧に載らない）
    static func showsOnHome(published: Bool) -> Bool { published }

    /// 投稿したあとの写真の行。並びは選んだ順（投稿の束の中の順と同じ）。
    ///
    /// - 「1つの投稿にまとめる」なら同じ束の印（`groupId`）を付ける——ホームは1枚の札（右上に複数枚の印）、
    ///   詳細は左右に送れる束、マイページは1枚ずつに複数枚の印。**束ね方は投稿したあとの部品の決まり**
    ///   （`PhotoGroups.group`・`multiPhotoIds`）にそのまま任せる
    /// - 非公開は `published: false`（マイページの「非公開」の札と 55% の沈みは格子の部品が出す）
    static func photos(_ items: [Item], userId: String, displayName: String?, published: Bool, audience: Audience,
                       grouped: Bool, category: String, tags: [String], song: Photo.Song? = nil,
                       now: Date) -> [Photo] {
        let created = ISO8601DateFormatter().string(from: now)
        return items.enumerated().compactMap { index, item in
            var row: [String: Any] = [
                "id": "\(idPrefix)\(index)",
                "src": item.imageURL.absoluteString,
                "userId": userId,
                "published": published,
                // 束の中の順は `createdAt` の古い順（`PhotoGroups.inPostOrder`）。選んだ順に1秒ずつずらす
                "createdAt": ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(index))),
                "updatedAt": created,
                "likes": 0,
            ]
            if let thumb = item.thumbnailURL { row["thumbSrc"] = thumb.absoluteString }
            if let name = displayName, !name.isEmpty { row["displayName"] = name }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { row["title"] = title }
            let caption = item.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !caption.isEmpty { row["description"] = caption }
            let location = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !location.isEmpty { row["location"] = location }
            if published, let wire = audience.wireValue { row["audience"] = wire }
            if grouped, items.count > 1 { row["groupId"] = groupId }
            if !category.isEmpty { row["category"] = category }
            if !tags.isEmpty { row["tags"] = tags }
            if let width = item.pixelWidth, let height = item.pixelHeight { row["width"] = width; row["height"] = height }
            if let date = item.takenOn { row["date"] = date }
            if let color = item.dominantColor { row["dominantColor"] = color }
            // 撮影情報と曲（詳細の行に出る）。送るときと同じ値を、読むときの形に通す
            if let exif = item.exif, !exif.isEmpty, let value = jsonObject(exif) { row["exif"] = value }
            if let song, let value = jsonObject(song) { row["song"] = value }
            guard let data = try? JSONSerialization.data(withJSONObject: row) else { return nil }
            return try? JSONDecoder.api.decode(Photo.self, from: data)
        }
    }

    /// 読み込み中のページの読み上げ
    static let loadingSpoken = L("プレビューを用意しています", "Preparing the preview")

    /// 写真の行が使っている端末の一時ファイルの URL（閉じたら控えから消す）
    static func fileURLs(_ photos: [Photo]) -> [URL] {
        photos.flatMap { [$0.detailImageURL, $0.gridImageURL] }.compactMap { $0 }.filter(\.isFileURL)
    }

    /// プレビューの写真か（id の頭で見る）
    static func isPreview(_ photo: Photo) -> Bool { photo.id.hasPrefix(idPrefix) }

    /// ホームの札の読み上げ。今回の投稿の札は「あなたの投稿」を前に足す（見た目の札と同じことを読む）
    static func spokenTile(yours: Bool, _ readout: String) -> String {
        yours ? yoursTag + L("、", ", ") + readout : readout
    }

    /// 縮めたページのまとめの読み上げ（2026-11-15 確かめ役の指摘）。ページの中は**読み上げから外す**——押す指は止めても、
    /// VoiceOver の操作（保存・送る・いいね）は中の本物の部品に届いてしまうため。代わりに何が見えるかを1つの言葉で言う
    /// - Parameter position: 今回の投稿の札が上から何枚目か（1 から）。ホームに出ないときは nil
    static func pageSummary(_ page: Page, title: String, location: String, published: Bool, position: Int?) -> String {
        switch page {
        case .detail:
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
            var parts = [L("詳細のプレビュー", "Detail preview")]
            parts.append(name.isEmpty ? L("題なし", "No title") : L("題「\(name)」", "Title \(name)"))
            if !place.isEmpty { parts.append(L("撮影地「\(place)」", "Location \(place)")) }
            return parts.joined(separator: L("、", ", "))
        case .home:
            guard showsOnHome(published: published), let position else {
                return L("ホームのプレビュー、", "Home preview, ") + homeHiddenTitle
            }
            return L("ホームのプレビュー、あなたの投稿は上から\(position)枚目", "Home preview, your post is number \(position) from the top")
        case .myPage:
            let at = position ?? 1
            return L("マイページのプレビュー、あなたの投稿は\(at)枚目", "My page preview, your post is number \(at)")
        }
    }

    /// 値を JSON の形（辞書）にする（写真の行に入れるため）
    private static func jsonObject<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// ホームのページの札。**本物のホームと同じ並べ方（`HomeFeed.arrange`）を通す。**
    ///
    /// 2026-11-15 判断（札 #409・確かめ役の指摘）: 模型は今回の投稿を先頭の大きい札に置いていたが、本物と食い違わないことを
    /// 優先した。本物では、自分の写真は「フォロー中の新しい写真」に入らず（`followingFresh` が自分を除く）、いいね 0 なので
    /// 「いいね順」でも下にいく。届くのは「新着」で、新着は4つめごとに混ざる（`HomeFeed.latestEvery`）。投稿した直後は
    /// 新着のいちばん上なので、ふつうは4番目（大1 → 2 → 2 の3段目の左の小さい札）に出る。ここでは今回の投稿を新着の先頭に置き、
    /// 残りの新着は公開の一覧の新しい順で代える（本物は `GET /feed` のページ）。「フォロー中の新しい写真」と、選ばれた写真の
    /// 横並び（PICKS）に出した写真を外す分は入れていない（どちらもその人のフォローと日によって変わる）。
    ///
    /// 「それぞれ別の投稿」を選んだときは、選んだ枚数ぶんの札が新着の並びで1つずつ入る（4番目・8番目…）。札を1枚に減らして
    /// 見せると「まとまって出る」と読めてしまうので減らさない。「1つの投稿にまとめる」は1枚の札（右上に複数枚の印）。
    /// 非公開はホームに出ないので、今回の投稿は入れない（ページの頭に「ホームには出ません」）
    static func homeGroups(preview: [Photo], published: Bool, neighbors: [Photo], viewerId: String?) -> [PhotoGroups.Group] {
        let others = neighbors.filter { !isPreview($0) }
        let recommended = HomeFeed.recommended(GalleryScope.all.photos(others, viewerId: viewerId, followingIds: []))
        let latest = (showsOnHome(published: published) ? preview : []) + GallerySort.new.apply(others)
        let arranged = HomeFeed.arrange(following: [], recommended: recommended, latest: latest, latestHasMore: false)
        let groups = PhotoGroups.group(arranged.main)
        let lastPreview = groups.lastIndex { isPreview($0.cover) } ?? -1
        return Array(groups.prefix(max(homeTileLimit, lastPreview + 1)))
    }

    /// マイページのページの格子。今回の投稿は自分の写真の先頭（投稿したばかりの写真と同じ）で、**ピン留めした写真は
    /// さらにその前**（本物のマイページと同じ `PhotoPinning.pinnedFirst`）。**1枚ずつ並ぶ**（束ねない・複数枚の印は
    /// 格子の部品が `multiPhotoIds` で付ける）
    static func myGrid(preview: [Photo], mine: [Photo], pinned: [String] = []) -> [Photo] {
        let all = PhotoPinning.pinnedFirst(preview + mine.filter { !isPreview($0) }, pinned: pinned)
        let lastPreview = all.lastIndex { isPreview($0) } ?? -1
        return Array(all.prefix(max(myGridLimit, lastPreview + 1)))
    }

    /// 画像の一時ファイルの置き場。**開くたびに別の場所**（`post-preview/<UUID>/`）にする。
    ///
    /// 2026-11-15（確かめ役の指摘）: 前は毎回 `post-preview/0.jpg` と同じ名前で、縮めた絵の控え（`DownsampledRemoteImage.memory`）
    /// が URL の文字列だけを鍵にして持ち続けるため、写真を替えて開き直すとホームとマイページに前の写真が出ていた。
    /// 閉じたら、その場所と、その URL の控えを消す（`PostPreviewSheet.removeFiles`）
    static func directory(id: UUID = UUID(), base: URL = FileManager.default.temporaryDirectory) -> URL {
        root(base: base).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// 置き場の親（開き直すときに前の回の残りもまとめて消す）
    static func root(base: URL = FileManager.default.temporaryDirectory) -> URL {
        base.appendingPathComponent("post-preview", isDirectory: true)
    }
}
