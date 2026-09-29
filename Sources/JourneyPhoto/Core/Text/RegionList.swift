import Foundation

/// 地図の「リスト」の札: 撮影スポットと写真を**都道府県ごとのまとまり**にする
/// （owner の提案・2026-09-28。「スポット」の札はそのまま残す）。
///
/// - **起点の県を先頭に**（現在地、無ければ地図の中心から 150km 以内で一番近い撮影スポットの県）。
///   ほかの県は、起点から一番近いもの（スポット・写真）までの距離で近い順。
///   起点が無ければ北から（`prefectures` の並び）
/// - 日本以外は**国ごと**（owner の依頼・2026-09-29）。国の決め方は下。決まらないものは
///   「その他の海外」（国の段が1つも無ければ「海外」）。最後に「場所が分からない写真」
/// - 県の中は、写真（受け取った順）と撮影スポット（`OfficialSpotList.rows` と同じ行・近い順）
///
/// 県の決め方:
/// - 撮影スポット: 台帳の `region.prefecture` が**47都道府県の名前と一致するときだけ**その県。
///   「都道府県で終わるか」では見ない——フランスに「イヴリーヌ県」がある（本番の台帳で確認）
/// - 写真: 撮影地の文字に都道府県の正式名（「東京都」「兵庫県」…）があればその県。
///   無ければ座標を見て、日本の範囲なら**150km 以内で一番近い撮影スポットの県**、範囲外なら海外。
///   どちらも無ければ「場所が分からない」
///
/// 国の決め方（日本の外と決まったものだけ）:
/// - 撮影スポット: 台帳の `region.country`
/// - 写真: 撮影地の文字に国の名前（`countries`・台帳にある国）があればその国。無ければ座標を見て、
///   **150km 以内で一番近い「国の分かったもの」（スポット・写真）の国**。どちらも無ければ「その他の海外」
///   （「バルセロナ」とだけ書いた写真は、近くのサグラダ・ファミリアの国＝スペインに入る）
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
enum RegionList {

    enum Key: Hashable {
        case prefecture(String)
        case country(String)
        case abroad
        case unknown

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
            case .prefecture(let name), .country(let name): return name
            case .abroad: return L("海外", "Outside Japan")
            case .unknown: return L("場所が分からない写真", "Photos without a place")
            }
        }
    }

    struct Section: Identifiable, Equatable {
        let key: Key
        /// 起点のある県（いまいる県）か
        let isCurrent: Bool
        let photos: [Photo]
        let spots: [OfficialSpotList.Row]
        /// 国の段がほかにある「海外」か（見出しを「その他の海外」にする）
        var besideCountries = false

        var id: String { key.id }

        /// 見出し。「場所が分からない」に撮影スポットも入った回は「写真」と言わない
        var title: String {
            if key == .unknown && !spots.isEmpty { return L("場所が分からないもの", "Without a place") }
            if key == .abroad && besideCountries { return L("その他の海外", "Elsewhere abroad") }
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

    /// 撮影地の文字から見分ける国の名前（台帳に無い国の写真のため）。台帳の国はこれに足して見る
    static let countries = [
        "フランス", "スペイン", "イタリア", "ドイツ", "イギリス", "スイス", "オーストリア", "オランダ",
        "ベルギー", "ポルトガル", "ギリシャ", "フィンランド", "スウェーデン", "ノルウェー", "デンマーク",
        "アイスランド", "チェコ", "ハンガリー", "ポーランド", "クロアチア", "トルコ", "アメリカ", "カナダ",
        "メキシコ", "ブラジル", "ペルー", "韓国", "台湾", "中国", "香港", "マカオ", "モンゴル", "タイ",
        "ベトナム", "カンボジア", "シンガポール", "マレーシア", "インドネシア", "フィリピン", "インド",
        "ネパール", "オーストラリア", "ニュージーランド", "エジプト", "モロッコ",
    ]

    /// 撮影地の文字から国。
    ///
    /// 🔴 **カタカナの国名は、語の切れ目で当たったものだけ**——前後がカタカナなら別の語の一部とみる
    /// （「タイル」「タイムズ」のタイ、「インドネシア」のインド）。**中黒「・」は切れ目**
    /// （「フランス・パリ」）。漢字の国名（韓国・台湾…）は前後を見ない——「大韓民国」
    /// 「アメリカ合衆国」「韓国ソウル」を落とさないため（d7e9476 のレビュー）。
    /// 「韓国料理」のような日本の写真は、国の手がかりに使わないので害が無い。
    /// 複数あれば**文字の後ろにある方**（「タイムズスクエア, ニューヨーク, アメリカ」は
    /// アメリカ。住所は国を最後に書く）。d9c5aee のレビュー
    static func country(inText text: String?, known: [String] = countries) -> String? {
        guard let text, !text.isEmpty else { return nil }
        func isKatakana(_ c: Character?) -> Bool {
            guard let s = c?.unicodeScalars.first else { return false }
            // ァ〜ヺ と 長音「ー」。中黒「・」(U+30FB) と「゠」は切れ目として外す
            return (0x30A1...0x30FA).contains(s.value) || s.value == 0x30FC
        }
        var best: (name: String, end: String.Index)?
        // 空の名前は当てない（空文字の検索で先へ進まず回り続けるのを避ける）
        for name in known where !name.isEmpty {
            var searchFrom = text.startIndex
            while let r = text.range(of: name, range: searchFrom..<text.endIndex) {
                let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : nil
                let after = r.upperBound < text.endIndex ? text[r.upperBound] : nil
                let katakanaName = name.unicodeScalars.allSatisfy { (0x30A1...0x30FC).contains($0.value) }
                let bounded = !katakanaName || (!isKatakana(before) && !isKatakana(after))
                if bounded, best.map({ r.upperBound > $0.end }) ?? true {
                    best = (name, r.upperBound)
                }
                searchFrom = r.upperBound
            }
        }
        return best?.name
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
    /// **地図と違って座標の無い写真も残す**（「場所が分からない写真」に入る）。
    /// カテゴリは写真の分類なので、撮影スポットには効かせない（地図のピンと同じ）
    static func filter(photos: [Photo], spots: [OfficialSpot], query: String, category: String?)
        -> (photos: [Photo], spots: [OfficialSpot]) {
        let needle = MapSearch.fold(query)
        let categoryKey = category.map { CategoryChoices.key($0) }
        let shownPhotos = photos.filter { photo in
            if let categoryKey, CategoryChoices.key(photo.category ?? "") != categoryKey { return false }
            return needle.isEmpty || MapSearch.matches(photo, needle: needle)
        }
        let shownSpots = needle.isEmpty ? spots : OfficialSpotIndex.matches(spots, query: query)
        return (shownPhotos, shownSpots)
    }

    /// - `photos` / `spots`: 絞る前の全部。上の欄・カテゴリ（`query` / `category`）はここで効かせる。
    ///   **県を当てる手がかりと「写真 N枚」は絞る前の全部から数える**——絞った後で作ると、
    ///   語がスポット名に当たらないだけで写真の県が分からなくなり、枚数も「スポット」の札と食い違う
    static func sections(photos: [Photo], spots: [OfficialSpot], query: String = "", category: String? = nil,
                         from center: Photo.Coords?) -> [Section] {
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
        let shown = filter(photos: photos, spots: spots, query: query, category: category)
        let shownIds = Set(shown.spots.map(\.spotId))
        let rows = allRows.filter { shownIds.contains($0.spot.spotId) }

        var spotsBy: [Key: [OfficialSpotList.Row]] = [:]
        for row in rows {
            let key: Key
            if let p = row.spot.region?.prefecture, prefectures.contains(p) {
                key = .prefecture(p)
            } else if let c = row.spot.coords, isInJapan(c) {
                key = nearestPrefecture(c).map(Key.prefecture) ?? .unknown
            } else {
                key = .abroad
            }
            spotsBy[key, default: []].append(row)
        }
        var photosBy: [Key: [Photo]] = [:]
        for photo in shown.photos {
            let key: Key
            if let p = prefecture(inText: photo.location) {
                key = .prefecture(p)
            } else if let c = photo.coords {
                if let p = nearestPrefecture(c) {
                    key = .prefecture(p)
                } else if !isInJapan(c) || (!anchors.isEmpty && namesAPlaceOutsideJapan(photo.location)) {
                    // 箱は粗い（釜山・ウラジオストクも入る）。近くにスポットが無く、撮影地の文字が
                    // はっきり日本の外を指していれば海外とみる（"Vladivostok" を「場所が分からない」にしない）。
                    // 台帳が空（404・失敗）の回は近さが測れないので、箱の中は海外にしない
                    key = .abroad
                } else {
                    key = .unknown
                }
            } else {
                key = .unknown
            }
            photosBy[key, default: []].append(photo)
        }

        // 海外を国ごとに分ける。まず国のはっきりしたもの（スポットの国・写真の文字）を手がかりに
        let known = countries + spots.compactMap { $0.region?.country }.filter { !countries.contains($0) }
        let abroadSpots = spotsBy.removeValue(forKey: .abroad) ?? []
        let abroadPhotos = photosBy.removeValue(forKey: .abroad) ?? []
        let spotCountry = { (row: OfficialSpotList.Row) in row.spot.region?.country.flatMap { $0 == "日本" ? nil : $0 } }
        let countryAnchors: [(coords: Photo.Coords, country: String)] =
            allRows.compactMap { row in
                guard let c = row.spot.coords, let country = spotCountry(row) else { return nil }
                return (c, country)
            } + photos.compactMap { photo in
                // 🔴 **日本の範囲の写真は手がかりにしない。** 「利尻 タイムラプス」「志摩スペイン村」の
                // ような日本の写真が、近くの海外扱いの写真を「タイ」「スペイン」へ引き込んでいた
                guard let c = photo.coords, !isInJapan(c), prefecture(inText: photo.location) == nil,
                      let country = country(inText: photo.location, known: known) else { return nil }
                return (c, country)
            }
        func nearestCountry(_ c: Photo.Coords) -> String? {
            let best = countryAnchors
                .map { (km: TravelDistance.kilometers(from: c, to: $0.coords), country: $0.country) }
                .min { $0.km < $1.km }
            guard let best, best.km <= nearbyLimitKm else { return nil }
            return best.country
        }
        for row in abroadSpots {
            let key = (spotCountry(row) ?? row.spot.coords.flatMap(nearestCountry)).map(Key.country) ?? .abroad
            spotsBy[key, default: []].append(row)
        }
        for photo in abroadPhotos {
            let key = (country(inText: photo.location, known: known) ?? photo.coords.flatMap(nearestCountry))
                .map(Key.country) ?? .abroad
            photosBy[key, default: []].append(photo)
        }

        let current = center.flatMap(nearestPrefecture)
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

        // 国は起点から近い順（起点が無ければ名前の順）
        let countryKeys = Set(spotsBy.keys).union(photosBy.keys)
            .compactMap { key -> (key: Key, name: String)? in
                if case .country(let name) = key { return (key, name) } else { return nil }
            }
            .sorted { a, b in
                let (dx, dy) = (distance(a.key), distance(b.key))
                return dx != dy ? dx < dy : a.name < b.name
            }
            .map(\.key)

        return (prefectureKeys + countryKeys + [.abroad, .unknown]).compactMap { key in
            let s = spotsBy[key] ?? []
            let p = photosBy[key] ?? []
            guard !s.isEmpty || !p.isEmpty else { return nil }
            var section = Section(key: key, isCurrent: current.map(Key.prefecture) == key, photos: p, spots: s)
            section.besideCountries = key == .abroad && !countryKeys.isEmpty
            return section
        }
    }
}
