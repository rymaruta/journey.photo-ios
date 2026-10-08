import Foundation

/// 地図の「リスト」の札: 撮影スポットと写真を**都道府県ごとのまとまり**にする
/// （owner の提案・2026-09-28。「スポット」の札はそのまま残す）。
///
/// - **起点の県を先頭に**（現在地、無ければ地図の中心から 150km 以内で一番近い撮影スポットの県）。
///   ほかの県は、起点から一番近いもの（スポット・写真）までの距離で近い順。
///   起点が無ければ北から（`prefectures` の並び）
/// - 日本の外は**国ごとの段**（owner の要求変更・2026-09-29。以前は「海外」に1つだった）。
///   県の段のあとに、起点から近い順（起点が無ければ国名の順）。撮影スポットは台帳の国
///   （`region.country`）、写真は**150km 以内で一番近い海外の撮影スポットの国**。
///   国が分からない海外は最後の「海外（その他）」に。最後に「県・国に分けられない写真」
/// - 県の中は、写真（受け取った順）と撮影スポット（`OfficialSpotList.rows` と同じ行・近い順）。
///   カテゴリで絞っている間は撮影スポットの行を出さない（`filter`）
///
/// 県の決め方:
/// - 撮影スポット: 台帳の `region.prefecture` が**47都道府県の名前と一致するときだけ**その県。
///   「都道府県で終わるか」では見ない——フランスに「イヴリーヌ県」がある（本番の台帳で確認）
/// - 写真: 撮影地の文字に都道府県の正式名（「東京都」「兵庫県」…）があればその県。
///   無ければ座標を見て、日本の範囲なら**150km 以内で一番近い撮影スポットの県**、範囲外なら海外。
///   どちらも無ければ「場所が分からない」
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
enum RegionList {

    enum Key: Hashable {
        case prefecture(String)
        /// 日本の外の国（台帳の日本語表記）
        case country(String)
        /// 日本の外だが国が分からない
        case abroad
        case unknown

        /// 国の段か（見出しの「いまいる国」の言い分け）
        var isCountry: Bool {
            if case .country = self { return true }
            return false
        }

        /// 開閉の状態を覚える鍵（`@State` の集合に入れる）
        var id: String {
            switch self {
            case .prefecture(let name): return "pref:\(name)"
            case .country(let name): return "country:\(name)"
            case .abroad: return "abroad"
            case .unknown: return "unknown"
            }
        }

        var title: String {
            switch self {
            case .prefecture(let name): return name
            case .country(let name): return name
            case .abroad: return L("海外（その他）", "Elsewhere outside Japan")
            // 2026-10-07 判断: 以前は「場所が分からない写真」で、撮影地に「福岡」「土谷棚田」と
            // 書いてある写真（県名の正式名も座標も無い）まで「場所が分からない」と言っていた。
            // ここに入るのは**県・国を決められなかった**写真なので、そう言う。
            // 「地図に置けない写真」にしないのは、座標があって近くに撮影スポットが無い写真
            // （地図には置ける）もここに入るため。板 MapList の注記の字（「場所が分からない写真」）とは違う
            case .unknown: return L("県・国に分けられない写真", "Photos not sorted by prefecture or country")
            }
        }
    }

    struct Section: Identifiable, Equatable {
        let key: Key
        /// 起点のある県（いまいる県）か
        let isCurrent: Bool
        let photos: [Photo]
        let spots: [OfficialSpotList.Row]

        var id: String { key.id }

        /// 見出し。「県・国に分けられない」段に撮影スポットも入った回は「写真」と言わない
        var title: String {
            if key == .unknown && !spots.isEmpty {
                return L("県・国に分けられないもの", "Not sorted by prefecture or country")
            }
            return key.title
        }
        var count: Int { photos.count + spots.count }
    }

    /// 見出しの右の件数。スポットは「件」、写真は「写真 N枚」
    static func countLabel(_ section: Section) -> String {
        let spots = section.spots.count, photos = section.photos.count
        let english = photos == 1 ? "1 photo" : "\(photos) photos"
        let spotsEnglish = spots == 1 ? "1 spot" : "\(spots) spots"
        let photoText = L("写真 \(photos)枚", english)
        switch (spots, photos) {
        case (_, 0): return L("\(spots)件", spotsEnglish)
        case (0, _): return photoText
        default: return L("\(spots)件 · 写真 \(photos)枚", "\(spotsEnglish) · \(english)")
        }
    }

    /// 47都道府県（北から・JIS の順）
    static let prefectures = [
        "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
        "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
        "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
        "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
        "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
        "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
        "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県",
    ]

    /// 打った語が都道府県の名前か（「福岡」「福岡県」→「福岡県」）。違えば nil
    static func prefecture(named query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return nil }
        return prefectures.first { $0 == q || ($0.count == q.count + 1 && $0.hasPrefix(q)) }
    }

    /// 撮影地の文字から都道府県。**正式名だけ**を見る（「京都」だけでは東京都と区別できない）。
    /// 複数あれば文字の先に出てくる方
    static func prefecture(inText text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return prefectures
            .compactMap { name in text.range(of: name).map { (name, $0.lowerBound) } }
            .min { $0.1 < $1.1 }?.0
    }

    /// 日本のおおよその範囲か（箱3つ: 本州・四国・九州・北海道／南西諸島／小笠原）。
    /// 箱は粗い——朝鮮半島の南岸やウラジオストクも入る。そこで県を当てるときは
    /// **近くに撮影スポットがあること**も求める（`nearbyLimitKm`）
    static func isInJapan(_ c: Photo.Coords) -> Bool {
        (c.lat >= 30 && c.lat <= 46 && c.lng >= 128.5 && c.lng <= 146)
            || (c.lat >= 24 && c.lat < 30 && c.lng >= 122 && c.lng <= 132)
            || (c.lat >= 20 && c.lat < 28 && c.lng >= 136 && c.lng <= 154)
    }

    /// 撮影地の文字が**はっきり日本の外を指しているか**。かな・漢字を1字でも含めば
    /// 日本とみなして false（「山中湖」「父島」のような短い地名は県名も「日本」も持たない）。
    /// ローマ字だけで "Japan" も無いときだけ true（"Vladivostok"）。
    /// 近くに撮影スポットが無い写真を「海外」と「場所が分からない」に分けるのにだけ使う
    static func namesAPlaceOutsideJapan(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return false }
        let hasJapaneseScript = text.unicodeScalars.contains { s in
            (0x3040...0x30FF).contains(s.value) || (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
        }
        return !hasJapaneseScript && text.range(of: "japan", options: .caseInsensitive) == nil
    }

    /// 座標から県を当てるとき、一番近い撮影スポットがこれより遠ければ当てない（「場所が分からない」）。
    /// 県の境・スポットの無い地域で、何百kmも離れた県に入れないため
    static let nearbyLimitKm = 150.0

    /// 上の欄（撮影地・スポット名）とカテゴリで絞る。地図の絞り込みと同じ当て方
    /// （写真は `MapSearch.matches`、スポットは `OfficialSpotIndex.matches`）。
    /// **地図と違って座標の無い写真も残す**（「県・国に分けられない写真」に入る）。
    /// **カテゴリで絞っている間は撮影スポットの行を出さない**（2026-10-08・owner 承認）。
    /// カテゴリは写真の分類で、撮影スポットには分類が無い——残すと「このカテゴリのスポット」と読める。
    /// 地図のピン（`PhotoMapViewModel.refreshOfficialPins`・PR #179）・Web の `filterMapSpots` と同じ。
    /// 以前（2026-09-29 の決め）はリストだけ行を残していて、地図と食い違っていた。
    /// 隠している理由は画面に1行で言う（`categoryHidesSpotsNote`）
    /// `aliases` は slug → 別名（`OfficialSpotService.fetchAliases`）。「さがす」と同じく別名にも当てる
    static func filter(photos: [Photo], spots: [OfficialSpot], query: String, category: String?,
                       aliases: [String: [String]] = [:])
        -> (photos: [Photo], spots: [OfficialSpot]) {
        let needle = MapSearch.fold(query)
        let categoryKey = category.map { CategoryChoices.key($0) }
        let shownPhotos = photos.filter { photo in
            if let categoryKey, CategoryChoices.key(photo.category ?? "") != categoryKey { return false }
            return needle.isEmpty || MapSearch.matches(photo, needle: needle)
        }
        let shownSpots = categoryKey != nil ? []
            : needle.isEmpty ? spots : OfficialSpotIndex.matches(spots, query: query, aliases: aliases)
        return (shownPhotos, shownSpots)
    }

    /// カテゴリで絞っている間、撮影スポットの行が無い理由（リストの上に淡い1行で出す）。
    /// 字は Web の `MapSpotList` と同じ。iOS のチップも「すべて」/ "All"（`Labels.Category.all`）
    static var categoryHidesSpotsNote: String {
        L("カテゴリは写真の分類なので、絞っている間は撮影スポットを出していません。「すべて」に戻すと出ます。",
          "Categories filter photos only, so spots are hidden. Choose “All” to see spots.")
    }

    /// - `photos` / `spots`: 絞る前の全部。上の欄・カテゴリ（`query` / `category`）はここで効かせる。
    ///   **県を当てる手がかりと「写真 N枚」は絞る前の全部から数える**——絞った後で作ると、
    ///   語がスポット名に当たらないだけで写真の県が分からなくなり、枚数も「スポット」の札と食い違う
    static func sections(photos: [Photo], spots: [OfficialSpot], query: String = "", category: String? = nil,
                         aliases: [String: [String]] = [:], from center: Photo.Coords?) -> [Section] {
        let allRows = OfficialSpotList.rows(spots, photos: photos, from: center)
        let anchors: [(coords: Photo.Coords, prefecture: String)] = allRows.compactMap { row in
            guard let c = row.spot.coords, let p = row.spot.region?.prefecture, prefectures.contains(p) else { return nil }
            return (c, p)
        }
        /// 日本の範囲で、近くに撮影スポットがあればその県。無ければ nil
        func nearestPrefecture(_ c: Photo.Coords) -> String? {
            guard isInJapan(c) else { return nil }
            let best = anchors
                .map { (km: TravelDistance.kilometers(from: c, to: $0.coords), prefecture: $0.prefecture) }
                .min { $0.km < $1.km }
            guard let best, best.km <= nearbyLimitKm else { return nil }
            return best.prefecture
        }
        /// 海外の撮影スポットの国の手がかり（写真の国を当てる）
        let countryAnchors: [(coords: Photo.Coords, country: String)] = allRows.compactMap { row in
            guard let c = row.spot.coords, let country = row.spot.region?.country, !country.isEmpty,
                  country != "日本" else { return nil }
            return (c, country)
        }
        /// 近く（`nearbyLimitKm` 以内）に国の分かる海外の撮影スポットがあればその国
        func nearestCountry(_ c: Photo.Coords) -> String? {
            let best = countryAnchors
                .map { (km: TravelDistance.kilometers(from: c, to: $0.coords), country: $0.country) }
                .min { $0.km < $1.km }
            guard let best, best.km <= nearbyLimitKm else { return nil }
            return best.country
        }
        /// 座標から段（県か国）。**県と国の一番近い手がかりを距離で比べる**——日本の箱は粗く
        /// 釜山も入るので、県を先に見ると対馬の県に吸われる。どちらも 150km より遠ければ nil
        func nearestPlace(_ c: Photo.Coords) -> Key? {
            let pref: (km: Double, key: Key)? = isInJapan(c) ? anchors
                .map { (km: TravelDistance.kilometers(from: c, to: $0.coords), key: Key.prefecture($0.prefecture)) }
                .min { $0.km < $1.km } : nil
            let country = countryAnchors
                .map { (km: TravelDistance.kilometers(from: c, to: $0.coords), key: Key.country($0.country)) }
                .min { $0.km < $1.km }
            let best = [pref, country].compactMap { $0 }.filter { $0.km <= nearbyLimitKm }.min { $0.km < $1.km }
            return best?.key
        }
        /// 日本の外の行・写真の段
        func abroadKey(country: String?, coords: Photo.Coords?) -> Key {
            if let country, !country.isEmpty, country != "日本" { return .country(country) }
            return coords.flatMap(nearestCountry).map(Key.country) ?? .abroad
        }
        let shown = filter(photos: photos, spots: spots, query: query, category: category, aliases: aliases)
        let shownIds = Set(shown.spots.map(\.spotId))
        let rows = allRows.filter { shownIds.contains($0.spot.spotId) }

        var spotsBy: [Key: [OfficialSpotList.Row]] = [:]
        for row in rows {
            let key: Key
            if let p = row.spot.region?.prefecture, prefectures.contains(p) {
                key = .prefecture(p)
            } else if let country = row.spot.region?.country, !country.isEmpty, country != "日本" {
                // **国を箱より先に見る。** 日本の箱は粗く釜山・対馬海峡の向こうも入る——
                // 国が載っている行を近くの県に入れない
                key = .country(country)
            } else if let c = row.spot.coords, isInJapan(c) {
                key = nearestPrefecture(c).map(Key.prefecture) ?? .unknown
            } else {
                key = abroadKey(country: row.spot.region?.country, coords: row.spot.coords)
            }
            spotsBy[key, default: []].append(row)
        }
        var photosBy: [Key: [Photo]] = [:]
        for photo in shown.photos {
            let key: Key
            if let p = prefecture(inText: photo.location) {
                key = .prefecture(p)
            } else if let c = photo.coords {
                if let near = nearestPlace(c) {
                    key = near
                } else if !isInJapan(c) || (!anchors.isEmpty && namesAPlaceOutsideJapan(photo.location)) {
                    // 箱は粗い（釜山・ウラジオストクも入る）。近くにスポットが無く、撮影地の文字が
                    // はっきり日本の外を指していれば海外とみる（"Vladivostok" を「場所が分からない」にしない）。
                    // 台帳が空（404・失敗）の回は近さが測れないので、箱の中は海外にしない
                    key = abroadKey(country: nil, coords: c)
                } else {
                    key = .unknown
                }
            } else {
                key = .unknown
            }
            photosBy[key, default: []].append(photo)
        }

        // 起点のある段。近くの県か国の近い方（どちらも 150km 以内）
        let currentKey: Key? = center.flatMap(nearestPlace)
        let current = currentKey.flatMap { key -> String? in
            if case .prefecture(let p) = key { return p }
            return nil
        }
        func distance(_ key: Key) -> Double {
            guard let center else { return .infinity }
            let fromSpots = (spotsBy[key] ?? []).compactMap(\.km)
            let fromPhotos = (photosBy[key] ?? []).compactMap { $0.coords.map { TravelDistance.kilometers(from: center, to: $0) } }
            return (fromSpots + fromPhotos).min() ?? .infinity
        }
        let prefectureKeys = prefectures.map(Key.prefecture)
            .filter { spotsBy[$0] != nil || photosBy[$0] != nil }
            .enumerated()
            .sorted { a, b in
                let (x, y) = (a.element, b.element)
                if (x == current.map(Key.prefecture)) != (y == current.map(Key.prefecture)) {
                    return x == current.map(Key.prefecture)
                }
                let (dx, dy) = (distance(x), distance(y))
                return dx != dy ? dx < dy : a.offset < b.offset
            }
            .map(\.element)

        // 国の段: 起点から近い順、起点が無い・同じ近さなら国名の順
        let countryKeys = Set(spotsBy.keys).union(photosBy.keys)
            .compactMap { key -> (Key, String)? in
                if case .country(let name) = key { return (key, name) }
                return nil
            }
            .sorted { a, b in
                let (dx, dy) = (distance(a.0), distance(b.0))
                return dx != dy ? dx < dy : a.1 < b.1
            }
            .map(\.0)

        return (prefectureKeys + countryKeys + [.abroad, .unknown]).compactMap { key in
            let s = spotsBy[key] ?? []
            let p = photosBy[key] ?? []
            guard !s.isEmpty || !p.isEmpty else { return nil }
            return Section(key: key, isCurrent: currentKey == key, photos: p, spots: s)
        }
    }
}
