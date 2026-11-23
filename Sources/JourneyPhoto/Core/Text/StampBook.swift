import Foundation

/// 旅のスタンプ帳（札 #712・とおまわり号の代わり・2026-11-23 owner「スタンプ帳は推奨でおっけ」）。
/// 案の頁（模型。実際の画面ではない）: https://claude.ai/artifact/NiauLwroDym5vSNkgYYMqT
///
/// **観光スポットに結ばれた自分の写真があれば、その場所のスタンプが押される。** 置く・並べるは無い。
/// 画面を持たない層（Linux の `swift test` で確かめられる）。
///
/// 2026-11-23 判断（札 #712 の本文とコメント）:
/// - **端末が自分の写真から毎回作る。どこにも保存しない。** サーバー・DB・新しい欄は使わない。写真を消すと、そのスタンプも消える
/// - **本人だけが見る**（owner「他人に見せて比較するようなものじゃない」）。人のページに行を足さない・共有の道も作らない
/// - 使うのは**自分の写真だけ**（公開も非公開も。帳面は本人にしか出ないので、自分だけの写真も数える）。他人の写真は入れない
/// - 結び方は今のアプリと同じ順（`SpotAutoLink`）: 写真の `spotId`（本人が選んだ）→ サイトが配る結びの表 →
///   端末の突き合わせ（`SpotMatcher`・撮影地の名前と位置）。本人が「違う場所なので外す」を押した写真は押さない
///   （表は公開の写真しか持たないので、自分だけの写真は突き合わせで結ぶ）
/// - ズル（行っていない所の写真に観光スポットを付ける）は照らさない。スタンプは硬貨・部品・Pro・順位・メダルに結ばない
/// - 行った県マップ（`VisitedPrefectures`）とは別の物。県マップの回数を増やさない
/// - 図柄は型から組む（枠4種 × 地方の色8色 + 県の形 + 名前 + 日付）。AI なし・費用0円。実在の御朱印や駅スタンプを真似ない
struct StampBook: Equatable {

    /// 1つの観光スポットのスタンプ。同じ所で何度撮っても1つ（写真が並ぶだけ）
    struct Stamp: Equatable, Identifiable {
        let spotId: String
        let name: String
        /// 日本の県（`RegionList.prefectures` の綴り）。海外は nil
        let prefecture: String?
        /// 海外の国名。日本は nil
        let country: String?
        let frame: StampFrame
        /// はじめて撮った日（`YYYY-MM-DD`）。撮影日 → 無ければ投稿した日。どちらも読めなければ nil
        let firstDay: String?
        /// そこで撮った自分の写真（新しい順）
        let photos: [Photo]

        var id: String { spotId }

        /// スタンプの上に出す地名（県か国）
        var placeName: String { prefecture ?? country ?? "" }
    }

    /// 押したスタンプ（はじめて撮った日の新しい順。日の無いものは後ろ）
    let stamps: [Stamp]
    /// 県 → その県の観光スポットの数（公開済みだけ）。県のページの「3 / 68」の分母
    let totals: [String: Int]

    static let empty = StampBook(stamps: [], totals: [:])

    var isEmpty: Bool { stamps.isEmpty }

    /// スタンプのある県（北から・`RegionList.prefectures` の並び）
    var prefectures: [String] {
        let have = Set(stamps.compactMap(\.prefecture))
        return RegionList.prefectures.filter { have.contains($0) }
    }

    /// その県のスタンプ（はじめて撮った日の古い順＝押された順）
    func stamps(in prefecture: String) -> [Stamp] {
        stamps.filter { $0.prefecture == prefecture }.sorted(by: Self.olderFirst)
    }

    /// 海外のスタンプ（国の名前の順、同じ国は古い順）
    var abroad: [Stamp] {
        stamps.filter { $0.prefecture == nil }.sorted {
            ($0.country ?? "") != ($1.country ?? "") ? ($0.country ?? "") < ($1.country ?? "") : Self.olderFirst($0, $1)
        }
    }

    /// 海外の国の数
    var countryCount: Int { Set(abroad.compactMap(\.country)).count }

    /// その県のまだの観光スポットの数（分母が分からなければ nil）
    func remaining(in prefecture: String) -> Int? {
        guard let total = totals[prefecture] else { return nil }
        return max(0, total - stamps(in: prefecture).count)
    }

    /// 最近押された3つ（入口の行の飾り・新しい順）
    var recent: [Stamp] { Array(stamps.prefix(3)) }

    private static func olderFirst(_ a: Stamp, _ b: Stamp) -> Bool {
        switch (a.firstDay, b.firstDay) {
        case let (l?, r?) where l != r: return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.spotId < b.spotId
        }
    }

    // MARK: - 作る

    /// 自分の写真から帳面を作る。
    /// - Parameters:
    ///   - photos: 自分の写真（`myPhotos()`。公開も非公開も）
    ///   - me: 自分の id。`PhotoOwnership.isMine` で持ち主を確かめ、自分の写真だけを使う（持ち主の分からない写真も落とす）
    ///   - spots: 観光スポットの索引（`OfficialSpotService.fetchIndex`）。公開済みの行だけ使う
    ///   - links: サイトが配る結びの表（本人が外した印を含む）
    ///   - matcher: 端末の突き合わせ（無ければ `spotId` と表だけで結ぶ）
    static func build(me: String?, photos: [Photo], spots: [OfficialSpot], links: SpotPhotoLinks,
                      matcher: SpotMatcher?) -> StampBook {
        (try? make(me: me, photos: photos, spots: spots, links: links, matcher: matcher, checksCancel: false)) ?? .empty
    }

    /// `build` と同じ。ただし途中で、止める合図（`Task.checkCancellation()`）を見る。
    /// 画面を閉じたら作りかけを捨てる（`StampBookModel` が画面の外の処理で呼ぶ）
    static func buildCancellable(me: String?, photos: [Photo], spots: [OfficialSpot], links: SpotPhotoLinks,
                                 matcher: SpotMatcher?) throws -> StampBook {
        try make(me: me, photos: photos, spots: spots, links: links, matcher: matcher, checksCancel: true)
    }

    /// 止める合図を見る間隔（写真の枚数）。突き合わせは1枚で索引の全行（約 4,640）を見るので、細かめに見る
    static let cancelStride = 64

    private static func make(me: String?, photos: [Photo], spots: [OfficialSpot], links: SpotPhotoLinks,
                             matcher: SpotMatcher?, checksCancel: Bool) throws -> StampBook {
        var byId: [String: OfficialSpot] = [:]
        var totals: [String: Int] = [:]
        let known = Set(RegionList.prefectures)
        for spot in spots where !spot.isDraft {
            byId[spot.spotId] = spot
            if let prefecture = japanesePrefecture(spot, known: known) { totals[prefecture, default: 0] += 1 }
        }
        // 写真ごとの日（並べ替えの中で何度も読まない）
        var grouped: [String: [(photo: Photo, day: String?)]] = [:]
        var order: [String] = []
        // 他人の写真は入れない（CLAUDE.md「他人の写真は、その人のもの」）。持ち主の確かめは1か所（`PhotoOwnership`）
        for (index, photo) in PhotoOwnership.mine(photos, me: me).enumerated() {
            if checksCancel, index % cancelStride == 0 { try Task.checkCancellation() }
            guard let spotId = spotId(for: photo, links: links, matcher: matcher), byId[spotId] != nil else { continue }
            if grouped[spotId] == nil { order.append(spotId) }
            grouped[spotId, default: []].append((photo, day(of: photo)))
        }
        if checksCancel { try Task.checkCancellation() }
        var stamps: [Stamp] = []
        for spotId in order {
            guard let spot = byId[spotId], let shots = grouped[spotId] else { continue }
            let prefecture = japanesePrefecture(spot, known: known)
            let country = prefecture == nil ? (spot.region?.country.flatMap { $0.isEmpty ? nil : $0 } ?? L("海外", "Abroad")) : nil
            let sortedShots = shots.sorted { ($0.day ?? "") > ($1.day ?? "") }.map(\.photo)
            stamps.append(Stamp(spotId: spotId, name: spot.name, prefecture: prefecture, country: country,
                                frame: StampFrame.of(category: spot.category, abroad: prefecture == nil),
                                firstDay: shots.compactMap(\.day).min(), photos: sortedShots))
        }
        stamps.sort { a, b in
            switch (a.firstDay, b.firstDay) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.spotId < b.spotId
            }
        }
        return StampBook(stamps: stamps, totals: totals)
    }

    /// 材料の目印（2026-11-23 判断・確かめ役の指摘）。**前回と同じ材料なら作り直さない**ための値。
    /// 見るのは、自分の id、写真ごとの id、`spotId`、外した印（`spotAuto`）、撮影地、題と説明の要約、位置、日、
    /// それと結びの表と観光スポットの索引と突き合わせの索引の件数。`Hasher` の値は起動ごとに変わるので、
    /// 同じ起動の間の覚え（`StampBookModel`）にだけ使い、端末には書かない
    static func fingerprint(me: String?, photos: [Photo], spots: [OfficialSpot], links: SpotPhotoLinks,
                            matchRows: Int?) -> Int {
        var h = Hasher()
        h.combine(me)
        h.combine(photos.count)
        for photo in photos {
            h.combine(photo.id)
            h.combine(PhotoOwnership.ownerId(of: photo))
            h.combine(photo.spotId)
            h.combine(photo.spotAutoMark)
            h.combine(photo.location)
            h.combine(SpotMatcher.texts(photo))
            h.combine(photo.coords?.lat)
            h.combine(photo.coords?.lng)
            h.combine(photo.date)
            h.combine(photo.createdAt)
        }
        h.combine(links.links.count)
        // この端末で本人が外した、戻した結びは件数が同じでも中身で変わる（数は少ないので中身を見る）
        for (photoId, override) in links.overrides.sorted(by: { $0.key < $1.key }) {
            h.combine(photoId)
            h.combine(override.spotId)
            if case .off = override { h.combine(0) } else { h.combine(1) }
        }
        h.combine(spots.count)
        h.combine(spots.filter(\.isDraft).count)
        h.combine(matchRows)
        return h.finalize()
    }

    /// 写真の観光スポット。**本人が選んだ `spotId` → 結びの表 → 端末の突き合わせ**。本人が外した写真は自動では結ばない
    static func spotId(for photo: Photo, links: SpotPhotoLinks, matcher: SpotMatcher?) -> String? {
        if let id = links.spotId(for: photo) { return id }
        guard !links.isOff(photo) else { return nil }
        return matcher?.match(photo)
    }

    /// 日本の県（国の欄が無く、県の綴りが47の中にある行だけ）。海外の行も州や地方を `prefecture` に持つ
    static func japanesePrefecture(_ spot: OfficialSpot, known: Set<String> = Set(RegionList.prefectures)) -> String? {
        if let country = spot.region?.country, !country.isEmpty { return nil }
        guard let prefecture = spot.region?.prefecture, known.contains(prefecture) else { return nil }
        return prefecture
    }

    /// その写真の日（`YYYY-MM-DD`）。撮影日 → 無ければ投稿した日（`createdAt` の頭）
    static func day(of photo: Photo) -> String? {
        if let taken = GallerySort.takenDay(photo) {
            return String(format: "%04d-%02d-%02d", taken / 10_000, (taken / 100) % 100, taken % 100)
        }
        guard let (y, m, d) = TakenDay.ymd(photo.createdAt) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

// MARK: - 図柄の型

/// 枠の形（観光スポットの種類で4つ）。2026-11-23 判断（案の頁「図柄の型」）:
/// 自然＝丸、歴史（寺社・城・史跡など）＝八角、町と建物＝角の丸い四角、海外＝二重の楕円と国名
enum StampFrame: String, Equatable, Sendable, CaseIterable {
    case nature
    case history
    case town
    case abroad

    /// 歴史の種類（索引の `category` の綴り・2026-11-23 に索引 4,640 件の種類を数えて振り分けた）
    static let historyKinds: Set<String> = ["寺社", "寺院", "神社", "史跡", "城", "城跡", "遺跡", "教会", "宮殿",
                                            "産業遺産", "仏像"]
    /// 町と建物の種類
    static let townKinds: Set<String> = ["町並み", "街並み", "街", "建築", "橋", "運河", "展望台", "博物館", "美術館",
                                         "水族館", "動物園", "鉄道", "駅", "灯台", "劇場", "広場", "市場", "ダム", "道路",
                                         "アート", "温泉街"]

    /// 種類から枠を決める。知らない種類・種類の無い行は自然（丸）
    static func of(category: String?, abroad: Bool) -> StampFrame {
        if abroad { return .abroad }
        guard let category else { return .nature }
        if historyKinds.contains(category) { return .history }
        if townKinds.contains(category) { return .town }
        return .nature
    }
}

/// 朱肉の色（地方で8色＋海外）。0xRRGGBB。紙（`paper`）の上に置く色で、黒い地の上には置かない
enum StampInk {
    /// 地方ごとの色（`PrefectureRegions.all` と同じ並び: 北海道、東北、関東、中部、近畿、中国、四国、九州と沖縄）。案の頁の模型と同じ値
    static let byRegion: [UInt32] = [0x2F4E8C, 0x2D6E62, 0x5A3F85, 0x86562A, 0xB8342C, 0x8C2A48, 0x1E6C87, 0xBF5418]
    static let abroad: UInt32 = 0x34302B

    /// 紙の色（帳面の地）・紙の二段目（スタンプの無い県）・紙の線（点線の丸）・墨（紙の上の字）
    static let paper: UInt32 = 0xECE5D5
    static let paperShade: UInt32 = 0xDDD3BE
    static let paperLine: UInt32 = 0xCFC4AC
    static let sumi: UInt32 = 0x2B2723
    static let sumiSoft: UInt32 = 0x6B6255

    static func color(prefecture: String?) -> UInt32 {
        guard let prefecture, let region = PrefectureRegions.region(of: prefecture),
              let index = PrefectureRegions.all.firstIndex(of: region), index < byRegion.count else { return abroad }
        return byRegion[index]
    }
}

/// 1つのスタンプの組み方（100×100 の箱の中の数。画面はこれを拡大して描く）
enum StampLayout {
    /// 箱の大きさ
    static let box: Double = 100
    /// 県の形を収める四角の一辺と中心
    static let silhouetteBox: Double = 40
    static let silhouetteCenter = (x: 50.0, y: 52.0)
    /// 県の形の塗りの濃さ
    static let silhouetteOpacity = 0.16

    /// 傾き（度）。観光スポットの鍵から決める（-7〜7）。同じ場所はいつも同じ見た目、場所ごとに少しずつ違う
    static func tilt(_ spotId: String) -> Double {
        Double(Int(hash(spotId) % 15) - 7)
    }

    /// FNV-1a（32bit・文字の符号位置ごと）。案の頁の模型と同じ
    static func hash(_ text: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for scalar in text.unicodeScalars {
            h ^= scalar.value
            h = h &* 16_777_619
        }
        return h
    }

    /// 名前を2行までに分ける: 空白で → 「（」の前で → 7字以上は半分で
    static func nameLines(_ name: String) -> [String] {
        var parts = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if parts.count == 1, let open = name.firstIndex(of: "（"), open != name.startIndex {
            parts = [String(name[..<open]), String(name[open...])]
        }
        if parts.count == 1, name.count > 6 {
            let half = (name.count + 1) / 2
            parts = [String(name.prefix(half)), String(name.dropFirst(half))]
        }
        return Array(parts.prefix(2))
    }

    /// 名前の字の大きさ（箱 100 の中。長い名前ほど小さく、最大 15）
    static func nameSize(_ lines: [String]) -> Double {
        let longest = max(lines.map(\.count).max() ?? 1, 1)
        return min(15, (62.0 / Double(longest)).rounded(.down))
    }

    /// 地名（県・国）の字の大きさ
    static func placeSize(_ stamp: StampBook.Stamp) -> Double {
        stamp.prefecture != nil ? 8.5 : (stamp.placeName.count > 6 ? 6.5 : 8)
    }

    /// 名前の行の高さ（箱 100 の中の y）
    static func nameBaselines(count: Int, size: Double) -> [Double] {
        count <= 1 ? [56] : [48, 48 + size * 1.15]
    }

    /// 地名と日付の高さ（枠の形で少し変える）
    static func placeY(_ frame: StampFrame) -> Double {
        switch frame {
        case .abroad: return 27
        case .town: return 22
        default: return 24
        }
    }

    static func dateY(_ frame: StampFrame) -> Double {
        switch frame {
        case .abroad: return 79
        case .town: return 83
        default: return 80
        }
    }

    /// 八角の頂点（箱 100 の中・半径 r）
    static func octagon(radius r: Double) -> [(x: Double, y: Double)] {
        (0..<8).map { i in
            let a = Double.pi / 8 + Double(i) * Double.pi / 4
            return (50 + r * cos(a), 50 + r * sin(a))
        }
    }

    /// 県の形を箱に収める拡大と移動（形の外接の四角 → 箱 100 の中）
    static func silhouetteFit(bounds: CGRect) -> (scale: Double, dx: Double, dy: Double)? {
        let side = max(Double(bounds.width), Double(bounds.height))
        guard side > 0, side.isFinite else { return nil }
        let scale = silhouetteBox / side
        let dx = silhouetteCenter.x - (Double(bounds.midX)) * scale
        let dy = silhouetteCenter.y - (Double(bounds.midY)) * scale
        return (scale, dx, dy)
    }
}

// MARK: - 言葉

/// スタンプ帳の言葉（中黒で区切らない・2026-11-12 owner）
enum StampBookText {
    static var title: String { L("旅のスタンプ帳", "Travel stamp book") }
    /// 入口の行の説明
    static var entryDetail: String {
        L("観光スポットで撮って投稿すると押される", "Post a photo taken at a sightseeing spot to get its stamp")
    }
    static var japan: String { L("日本", "Japan") }
    static var abroad: String { L("海外", "Abroad") }

    /// 表紙の数「10 個」（数と単位は画面で字の大きさを分ける）
    static func stampUnit(_ count: Int) -> String { L("個", count == 1 ? "stamp" : "stamps") }
    static func prefectureUnit(_ count: Int) -> String { L("県", count == 1 ? "prefecture" : "prefectures") }
    /// 海外の行の右「2 か国」
    static func countries(_ count: Int) -> String { L("\(count) か国", count == 1 ? "1 country" : "\(count) countries") }
    /// 県の行の右「3 / 68」
    static func ratio(_ have: Int, _ total: Int?) -> String {
        total.map { "\(have) / \($0)" } ?? "\(have)"
    }

    static var howTo: String {
        L("観光スポットで撮った写真を投稿すると押されます", "Post a photo taken at a sightseeing spot to get a stamp")
    }
    static var emptyTitle: String {
        L("観光スポットで撮った写真を\n投稿すると、スタンプが押されます",
          "Post a photo taken at a sightseeing spot\nand its stamp goes here")
    }
    static var emptySlot: String { L("ここに\n押されます", "Your stamp\ngoes here") }
    static var nextSlot: String { L("つぎの\nひとつ", "Your\nnext one") }
    static var browseSpots: String { L("観光スポットを見る", "Browse sightseeing spots") }
    static var remainingTitle: String { L("まだの観光スポット", "Spots still to visit") }
    static func remainingNote(_ prefecture: String) -> String {
        L("\(prefecture)で撮れる所を見る", "See places to visit in \(prefecture)")
    }
    static var firstDayLabel: String { L("はじめて撮った日", "First photo") }
    static var photosHere: String { L("ここで撮った写真", "Your photos here") }
    static func photoCount(_ count: Int) -> String { L("\(count) 枚", count == 1 ? "1 photo" : "\(count) photos") }
    static var openSpot: String { L("観光スポットを見る", "Open the spot") }
    static var close: String { L("閉じる", "Close") }
    static var loadFailed: String {
        L("旅のスタンプ帳を読めませんでした。通信を確かめて、もう一度お試しください",
          "Couldn't load your stamp book. Check your connection and try again.")
    }
    static var onlyYou: String { L("旅のスタンプ帳はあなたにだけ見えます", "Only you can see your stamp book") }
    /// 圏外で、同じ起動の間に読めた帳面を出しているとき
    static var offlineSaved: String {
        L("電波が無いので、前に読んだ帳面です", "No connection. Showing the stamp book you loaded earlier")
    }
    /// 押される瞬間の見出し「鹿苑寺（金閣寺）の\nスタンプが押されました」
    static func pressedTitle(_ name: String) -> String {
        L("\(name)の\nスタンプが押されました", "You got a stamp for\n\(name)")
    }
    /// 押される瞬間の事実の一文「京都府で3つめのスタンプです」
    static func pressedFact(place: String, ordinal: Int) -> String {
        L("\(place)で\(ordinal)つめのスタンプです", ordinal == 1 ? "Your first stamp in \(place)" : "Stamp no. \(ordinal) in \(place)")
    }
    static var openBook: String { L("旅のスタンプ帳を見る", "Open your stamp book") }
    /// 押される瞬間の画面の下の一行（同じ投稿でトランクのラベルも届いたとき）
    static var labelAlsoArrived: String {
        L("旅のラベルも1枚、手持ちに入りました", "A travel label was also added to your collection")
    }
    /// 入口の行の右の最近の3つの読み上げ
    static func recentAccessibility(_ names: [String]) -> String {
        L("最近のスタンプ、\(names.joined(separator: "、"))", "Recent stamps: \(names.joined(separator: ", "))")
    }

    /// 日付「2026.11.23」（スタンプの中の字）
    static func stampDate(_ day: String?) -> String {
        guard let (y, m, d) = TakenDay.ymd(day) else { return "" }
        return String(format: "%04d.%02d.%02d", y, m, d)
    }

    /// 読み上げ「鹿苑寺（金閣寺）、京都府、2026年11月23日」
    static func accessibility(_ stamp: StampBook.Stamp) -> String {
        var parts = [stamp.name, stamp.placeName].filter { !$0.isEmpty }
        if let day = TakenDay.label(stamp.firstDay) { parts.append(day) }
        return parts.joined(separator: L("、", ", "))
    }

    /// 地図の読み上げ
    static func mapAccessibility(_ prefectures: [String]) -> String {
        prefectures.isEmpty
            ? L("日本地図。まだスタンプのある県はありません", "Map of Japan. No prefectures with stamps yet")
            : L("日本地図。スタンプのある県: \(prefectures.joined(separator: "、"))",
                "Map of Japan. Prefectures with stamps: \(prefectures.joined(separator: ", "))")
    }

    /// 表紙の数の読み上げ
    static func countsAccessibility(stamps: Int, prefectures: Int) -> String {
        L("スタンプ \(stamps) 個、\(prefectures) 県", "\(stamps) stamps in \(prefectures) prefectures")
    }

    /// 県の行の読み上げ「京都府、スタンプ 3 個、観光スポット 68 か所のうち」
    static func rowAccessibility(prefecture: String, have: Int, total: Int?) -> String {
        if let total {
            return L("\(prefecture)、観光スポット \(total) か所のうち \(have) 個", "\(prefecture), \(have) of \(total) spots")
        }
        return L("\(prefecture)、スタンプ \(have) 個", "\(prefecture), \(have) stamps")
    }
}

// MARK: - 投稿の直後に押される瞬間

/// 投稿の直後に「スタンプが押されました」を出すかの判定（案の頁の1・2026-11-23 owner「推奨でおっけ」）。
///
/// **出すのは、その観光スポットで初めてのときだけ。** 2回目からは何も出さない（帳面の中で写真が増えるだけ）。
/// 帳面をまだ作っていない（前の帳面が分からない）ときも出さない（初めてか分からないのに祝わない）。
/// 事実の一文は「京都府で3つめのスタンプです」だけ。連続日数や順位は出さない。
///
/// 投稿の直後は、自動の候補がまだ写真の `spotId` に書かれていない（サイトの表に載るまで時間がかかる）。
/// だから渡すのは投稿の画面が持っている観光スポット（本人が選んだもの → `UploadViewModel.autoSpotCandidate`）。
///
/// **つなぐ所（まとめるときに呼ぶ1行・札 #712）**: 投稿が終わってラベルが届く所（`RootView` の
/// `LabelArrivedView` を出す所。release-1.2.0 で形が変わっている #706・#710・#711）で
/// `StampMoment.pressed(spotIds: <投稿した写真の観光スポット>, before: StampBookModel.shared.knownBook(userId:), spots: <索引>, today: <今日>)`
/// が値を返したら、ラベルの画面の代わりに `StampPressedView(pressed:labelAlsoArrived:onOpenBook:)` を出す
/// （ラベルは手持ちに入れ、画面の下に一行で知らせる。投稿のあとの画面は1枚）
enum StampMoment {

    struct Pressed: Equatable, Identifiable {
        let stamp: StampBook.Stamp
        /// その県（海外は国）で何番目のスタンプか（1から）
        let ordinal: Int

        var id: String { stamp.spotId }
    }

    /// - Parameters:
    ///   - spotIds: 投稿した写真の観光スポット（投稿した順。重なりや空は気にしない）
    ///   - before: 投稿の前の帳面。nil（まだ作っていない）なら出さない
    ///   - spots: 観光スポットの索引（公開済みの行だけ使う）
    ///   - today: 今日（`YYYY-MM-DD`）。スタンプの日付になる
    static func pressed(spotIds: [String], before: StampBook?, spots: [OfficialSpot], today: String) -> Pressed? {
        guard let before else { return nil }
        let have = Set(before.stamps.map(\.spotId))
        let known = Set(RegionList.prefectures)
        for spotId in spotIds where !spotId.isEmpty && !have.contains(spotId) {
            guard let spot = spots.first(where: { $0.spotId == spotId && !$0.isDraft }) else { continue }
            let prefecture = StampBook.japanesePrefecture(spot, known: known)
            let country = prefecture == nil ? (spot.region?.country.flatMap { $0.isEmpty ? nil : $0 } ?? L("海外", "Abroad")) : nil
            let stamp = StampBook.Stamp(spotId: spotId, name: spot.name, prefecture: prefecture, country: country,
                                        frame: StampFrame.of(category: spot.category, abroad: prefecture == nil),
                                        firstDay: today, photos: [])
            let ordinal = prefecture.map { before.stamps(in: $0).count + 1 }
                ?? (before.abroad.filter { $0.country == country }.count + 1)
            return Pressed(stamp: stamp, ordinal: ordinal)
        }
        return nil
    }

    /// 押されて止まるまでの時間（秒・案の頁の 0.62 秒）
    static let landDuration = 0.62
    /// 止まった瞬間に紙が沈む深さ（pt）
    static let paperSink: CGFloat = 2
    /// 落ち始めの高さ（pt・上から）と大きさ
    static let dropFrom: CGFloat = -120
    static let dropScale: CGFloat = 1.18
}

// MARK: - 画面写真の試験の見本

/// UI テストの見本の帳面（`PreviewSession.stampBookSample`・Debug のときだけ使う）。
/// 名前と種類と県は観光スポットの索引にある実在の行（2026-11-23 に索引で確かめた）。日付は例。写真は持たない
enum StampBookSamples {
    private struct Row {
        let id: String
        let name: String
        let prefecture: String?
        let country: String?
        let category: String
        let day: String
    }

    private static let rows: [Row] = [
        Row(id: "sp_31047ba6ec8d", name: "鹿苑寺（金閣寺）", prefecture: "京都府", country: nil, category: "寺院", day: "2026-11-23"),
        Row(id: "sp_d41c6b8e7025", name: "伏見稲荷大社", prefecture: "京都府", country: nil, category: "神社", day: "2026-11-22"),
        Row(id: "sp_37ea9b06c154", name: "嵐山 竹林の小径", prefecture: "京都府", country: nil, category: "並木道", day: "2026-04-03"),
        Row(id: "sp_0b9137ea54cd", name: "小樽運河", prefecture: "北海道", country: nil, category: "運河", day: "2025-08-12"),
        Row(id: "sp_764e0a13c8bf", name: "函館山 山頂展望台", prefecture: "北海道", country: nil, category: "展望台", day: "2025-08-14"),
        Row(id: "sp_e817b40cf295", name: "摩周湖 第一展望台", prefecture: "北海道", country: nil, category: "湖", day: "2025-08-15"),
        Row(id: "sp_e4903b7c168d", name: "古宇利大橋", prefecture: "沖縄県", country: nil, category: "橋", day: "2026-06-02"),
        Row(id: "sp_90ac47e1f638", name: "万座毛", prefecture: "沖縄県", country: nil, category: "海岸", day: "2026-06-03"),
        Row(id: "sp_94b07fe3c218", name: "浅草寺", prefecture: "東京都", country: nil, category: "寺院", day: "2026-01-02"),
        Row(id: "sp_9df6c9e074ac", name: "六義園", prefecture: "東京都", country: nil, category: "庭園", day: "2025-11-30"),
        Row(id: "sp_e4a73d503368", name: "東京タワー", prefecture: "東京都", country: nil, category: "建築", day: "2025-12-24"),
        Row(id: "sp_2f43278876a7", name: "横浜赤レンガ倉庫", prefecture: "神奈川県", country: nil, category: "建築", day: "2025-10-11"),
        Row(id: "sp_de81570c34b9", name: "日光東照宮", prefecture: "栃木県", country: nil, category: "神社", day: "2025-10-25"),
        Row(id: "sp_7d49f02b856e", name: "松本城", prefecture: "長野県", country: nil, category: "城", day: "2025-07-20"),
        Row(id: "sp_8e945530e928", name: "黒部ダム", prefecture: "富山県", country: nil, category: "建築", day: "2025-07-22"),
        Row(id: "sp_31f0b7a9dc52", name: "兼六園", prefecture: "石川県", country: nil, category: "庭園", day: "2025-07-23"),
        Row(id: "sp_c5a1407fe6d8", name: "姫路城", prefecture: "兵庫県", country: nil, category: "城", day: "2025-05-04"),
        Row(id: "sp_92dc681b0f47", name: "銀山温泉", prefecture: "山形県", country: nil, category: "温泉街", day: "2026-02-10"),
        Row(id: "sp_35d8b1740fce", name: "角館 武家屋敷通り", prefecture: "秋田県", country: nil, category: "街並み", day: "2026-04-28"),
        Row(id: "sp_51e8b0374cad", name: "道後温泉本館", prefecture: "愛媛県", country: nil, category: "温泉", day: "2025-03-15"),
        Row(id: "sp_4b6e18f9c530", name: "高千穂峡", prefecture: "宮崎県", country: nil, category: "峡谷", day: "2025-03-18"),
        Row(id: "sp_4a56afb646fa", name: "ハルシュタット", prefecture: nil, country: "オーストリア", category: "町並み", day: "2024-09-18"),
        Row(id: "sp_07b160155909", name: "エッフェル塔", prefecture: nil, country: "フランス", category: "建築", day: "2024-05-02"),
    ]

    /// 県 → 観光スポットの数（2026-11-23 の索引の数）
    private static let totals: [String: Int] = [
        "京都府": 68, "北海道": 58, "沖縄県": 61, "東京都": 67, "神奈川県": 63, "栃木県": 59, "長野県": 59, "富山県": 52,
        "石川県": 50, "兵庫県": 62, "山形県": 72, "秋田県": 60, "愛媛県": 65, "宮崎県": 84,
    ]

    /// `empty`（まだ1つも無い）、`few`（3つ）、`many`（23）。知らない値は nil
    static func book(_ kind: String) -> StampBook? {
        let picked: [Row]
        switch kind {
        case "empty": picked = []
        // 3つは別々の県（京都、北海道、沖縄）にして、地方の色と枠の形の違いが見えるようにする
        case "few": picked = [rows[0], rows[3], rows[7]]
        case "many": picked = rows
        default: return nil
        }
        let stamps = picked.map { row in
            StampBook.Stamp(spotId: row.id, name: row.name, prefecture: row.prefecture, country: row.country,
                            frame: StampFrame.of(category: row.category, abroad: row.prefecture == nil),
                            firstDay: row.day, photos: [])
        }
        let sorted = stamps.sorted { ($0.firstDay ?? "") > ($1.firstDay ?? "") }
        return StampBook(stamps: sorted, totals: totals)
    }
}
