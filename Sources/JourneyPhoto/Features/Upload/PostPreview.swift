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

    /// ホームのページに並べるほかの人の札の数（今回の投稿の後ろ）。縮めた1ページに収まる分（大1・2・2）
    static let homeNeighborLimit = 5
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
        switch audience {
        case .everyone:
            return (audience.systemImage, L("全体に公開。ホームと検索にも出ます", "Everyone. Also on Home and in search"))
        case .followers, .closeFriends:
            // 「。」で区切る（中黒で並べない）。但し書きは公開範囲の行と同じ言葉（`Audience.note`）
            return (audience.systemImage, audience.label + L("。", ". ") + audience.note)
        }
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
                       grouped: Bool, category: String, tags: [String], now: Date) -> [Photo] {
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
            guard let data = try? JSONSerialization.data(withJSONObject: row) else { return nil }
            return try? JSONDecoder.api.decode(Photo.self, from: data)
        }
    }

    /// プレビューの写真か（id の頭で見る）
    static func isPreview(_ photo: Photo) -> Bool { photo.id.hasPrefix(idPrefix) }

    /// ホームのページの札（今回の投稿が先頭、後ろにほかの人の札）。
    ///
    /// 2026-11-15 判断（札 #409）: **「それぞれ別の投稿」を選んだときは、選んだ枚数ぶんの札を全部見せる。**
    /// 別の投稿はホームでもそれぞれ1枚の札になる（`PhotoGroups.group` は束の印の無い写真を1枚ずつの束にする）。
    /// 札を1枚に減らして見せると「まとまって出る」と読めてしまい、まとめるかどうかを決めるためのプレビューに
    /// ならない。逆に「1つの投稿にまとめる」は1枚の札（右上に複数枚の印）。どちらも投稿したあとの決まりのまま。
    /// 非公開はホームに出ないので、今回の投稿の札は無い（ページの頭に「ホームには出ません」）
    static func homeGroups(preview: [Photo], published: Bool, neighbors: [Photo], me: String?) -> [PhotoGroups.Group] {
        let mine = showsOnHome(published: published) ? PhotoGroups.group(preview) : []
        let others = PhotoGroups.group(neighbors.filter { !isPreview($0) && ($0.userId ?? $0.uploadedBy) != me })
        return mine + Array(others.prefix(homeNeighborLimit))
    }

    /// マイページのページの格子（今回の投稿が先頭、後ろに自分の写真）。**マイページは1枚ずつ並ぶ**
    /// （束ねない・複数枚の印は格子の部品が `multiPhotoIds` で付ける）
    static func myGrid(preview: [Photo], mine: [Photo]) -> [Photo] {
        Array((preview + mine.filter { !isPreview($0) }).prefix(max(myGridLimit, preview.count)))
    }

    /// 画像の一時ファイルの置き場（開くたびに作り直す・閉じたら消す）
    static func directory(base: URL = FileManager.default.temporaryDirectory) -> URL {
        base.appendingPathComponent("post-preview", isDirectory: true)
    }
}
