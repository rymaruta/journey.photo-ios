import Foundation

/// DM の会話から旅行プランの下書きを作る（2026-11-12 判断・資料「SNS をもっと SNS に」2a の段①と段②）。
///
/// - 段①: 会話で送り合った写真の撮影地を集める。写真の札（`DMPhotoQuote`）は撮影地の文字を持つ。
///   公開の写真なら写真の行（`Photo`）から座標を引く。非公開（一覧に無い）は文字だけ（座標なし）
/// - 段②: 吹き出しの文の中の撮影スポットの名前を、撮影スポットの索引で拾う（`spotsInText`）。
///   拾えなければ候補（`candidates`・撮影地の欄の候補 `PlaceSpotSuggestions` と同じ3件）から選ぶ
///
/// **AI は使わない・サーバーに送らない**（会話の中身は端末の中だけで読む）。作るのは自分だけのプランで、
/// 相手と共有する口は出さない（2b の「プランの仲間」は DB の変更が要る）。画面を持たない層なので Linux で試験する
enum DMTripPlaces {

    /// 会話のどこから来た場所か（下書きの行の2行目に出す）
    enum Source: Equatable {
        /// 相手から送られた写真
        case receivedPhoto
        /// 自分が送った写真
        case sentPhoto
        /// 吹き出しの文から拾った
        case text
        /// 候補から選んだ
        case picked
    }

    /// 下書きの1行
    struct Found: Identifiable, Equatable {
        let place: TripDraft.Place
        let source: Source
        var id: String { place.id }

        /// 「撮影スポット · 送られた写真から」「撮影地 · 送った写真から」
        var detail: String {
            let kind = place.isSpot ? L("撮影スポット", "Photo spot") : L("撮影地", "Photo location")
            let from: String
            switch source {
            case .receivedPhoto: from = L("送られた写真から", "from a photo you received")
            case .sentPhoto: from = L("送った写真から", "from a photo you sent")
            case .text: from = L("文から拾った", "from a message")
            case .picked: from = L("候補から選んだ", "picked from suggestions")
            }
            return "\(kind) · \(from)"
        }
    }

    // MARK: - 段①: 写真から

    /// 会話の写真から集めた場所（古い順・同じ場所は1つ・最初に出た写真の向きを残す）。
    ///
    /// - 写真の札が見られる（`live`）で撮影地の文字があるものだけ。見られない・分からない札は数えない
    /// - 撮影地の**頭の語**（「兼六園, 金沢市, 石川県」の「兼六園」）が撮影スポットの名前・別名と**同じ**なら撮影スポット。
    ///   それ以外は撮影地（`DerivedSpot` の slug）。名前の部分一致では撮影スポットにしない（違う場所を入れない）
    /// - `photos`（公開の写真の一覧）に同じ写真があれば、その座標を使う。無ければ座標なし
    /// - ブロックした相手の写真は数えない（札も出していない・`DMPhotoCardState`）
    static func photoPlaces(_ messages: [DMMessage], index: [OfficialSpot], aliases: [String: [String]] = [:],
                            photos: [Photo], blocked: Set<String> = []) -> [Found] {
        photoPlaces(messages, names: NameTable(index, aliases: aliases), photos: photos, blocked: blocked)
    }

    /// 揃えた名前の表を先に作っておく形（会話の画面は打つたびに描き直すので、表は索引を読んだときに1回だけ作る）
    static func photoPlaces(_ messages: [DMMessage], names: NameTable, photos: [Photo],
                            blocked: Set<String> = []) -> [Found] {
        guard messages.contains(where: { $0.photo?.isLive == true }) else { return [] }
        let byId = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var out: [Found] = []
        for message in messages {
            guard let quote = message.photo, quote.isLive else { continue }
            if let owner = quote.ownerId, blocked.contains(owner) { continue }
            let row = byId[quote.id]
            let raw = (row?.location ?? quote.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            let place = place(forLocation: raw, coords: row?.coords, names: names)
            guard seen.insert(place.id).inserted else { continue }
            out.append(Found(place: place, source: message.mine ? .sentPhoto : .receivedPhoto))
        }
        return out
    }

    /// 撮影地の文字 → 下書きの場所（頭の語が撮影スポットの名前と同じなら撮影スポット）
    static func place(forLocation raw: String, coords: Photo.Coords?, index: [OfficialSpot],
                      aliases: [String: [String]] = [:]) -> TripDraft.Place {
        place(forLocation: raw, coords: coords, names: NameTable(index, aliases: aliases))
    }

    private static func place(forLocation raw: String, coords: Photo.Coords?, names: NameTable) -> TripDraft.Place {
        if let head = headWord(raw), let spot = names.spot(named: head) {
            return TripDraft.place(spot: spot)
        }
        let location = DerivedSpot.Place(label: raw, slug: LocationSlug.make(raw), photos: [], broader: [],
                                         categories: [], coords: coords)
        return TripDraft.place(location: location)
    }

    /// 撮影地の頭の語（「,」「、」で区切った最初）
    static func headWord(_ raw: String) -> String? {
        raw.components(separatedBy: CharacterSet(charactersIn: ",、，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// 揃えた名前（名前・英語名・読み・別名）→ 撮影スポット。**公開済みの行だけ**（運営の下書きを入れない）。
    /// 同じ名前が2つあれば索引の先の行
    struct NameTable {
        private var table: [String: OfficialSpot] = [:]

        static let empty = NameTable([], aliases: [:])

        init(_ index: [OfficialSpot], aliases: [String: [String]]) {
            for spot in index where !spot.isDraft {
                for raw in [spot.name, spot.nameEn, spot.reading] + (aliases[spot.slug] ?? []) {
                    let key = OfficialSpotIndex.spotName(raw)
                    if !key.isEmpty, table[key] == nil { table[key] = spot }
                }
            }
        }

        func spot(named raw: String) -> OfficialSpot? {
            table[OfficialSpotIndex.spotName(raw)]
        }
    }

    // MARK: - 段②: 文から

    /// 拾う名前の短さの下限（字）。2字の名前（「海」「城」の組み合わせ）は文の中で外れて当たりやすい
    static let minNameLength = 3

    /// 吹き出しの文の中に**名前がそのまま入っている**撮影スポット（文に出た順）。
    ///
    /// 揃え方は索引の検索と同じ（`OfficialSpotIndex.spotName`: 全角半角・大小・空白と括弧を見ない）。
    /// 名前・英語名・読み・別名のどれかが `minNameLength` 字以上で文に入っていれば拾う。
    /// **短い名前が長い名前の一部として当たったものは捨てる**（「清水寺」と「清水」なら「清水寺」だけ）。
    /// 公開済みの行だけ。座標の無い行も拾う（日へ割るときは地域で束ねる）
    static func spotsInText(_ text: String, index: [OfficialSpot], aliases: [String: [String]] = [:]) -> [OfficialSpot] {
        let haystack = OfficialSpotIndex.spotName(text)
        guard haystack.count >= minNameLength else { return [] }
        struct Hit { let spot: OfficialSpot; let name: String; let position: Int }
        var hits: [Hit] = []
        var seen = Set<String>()
        for spot in index where !spot.isDraft && !seen.contains(spot.spotId) {
            let names = ([spot.name, spot.nameEn, spot.reading] + (aliases[spot.slug] ?? []))
                .map(OfficialSpotIndex.spotName)
                .filter { $0.count >= minNameLength }
                .sorted { $0.count > $1.count }
            for name in names {
                guard let range = haystack.range(of: name) else { continue }
                hits.append(Hit(spot: spot, name: name,
                                position: haystack.distance(from: haystack.startIndex, to: range.lowerBound)))
                seen.insert(spot.spotId)
                break
            }
        }
        let kept = hits.filter { hit in
            !hits.contains { other in other.name.count > hit.name.count && other.name.contains(hit.name) }
        }
        return kept.sorted { $0.position != $1.position ? $0.position < $1.position : $0.spot.slug < $1.spot.slug }
            .map(\.spot)
    }

    /// 文から拾えなかったときの候補（`PlaceSpotSuggestions.limit` 件）。
    ///
    /// 文と名前で**いちばん長く続けて同じ字**（「21世紀美術館も行きたい」と「金沢21世紀美術館」の「21世紀美術館」）が
    /// `minNameLength` 字以上で、名前の 6 割以上を占めるものを、続いた字の長い順に。
    /// 候補は**選ぶまで入れない**（推し量った当たりを黙って下書きに入れない）。
    /// 文は頭の `scanLimit` 字だけ見る（長い文で端末を待たせない）
    static func candidates(for text: String, index: [OfficialSpot], aliases: [String: [String]] = [:]) -> [OfficialSpot] {
        let haystack = Array(OfficialSpotIndex.spotName(text).unicodeScalars.prefix(scanLimit))
        guard haystack.count >= minNameLength else { return [] }
        struct Scored { let spot: OfficialSpot; let run: Int; let ratio: Double }
        var scored: [Scored] = []
        var seen = Set<String>()
        for spot in index where !spot.isDraft && spot.coords != nil && seen.insert(spot.spotId).inserted {
            var best: (run: Int, ratio: Double)?
            for raw in [spot.name, spot.reading] + (aliases[spot.slug] ?? []) {
                let name = Array(OfficialSpotIndex.spotName(raw).unicodeScalars)
                guard name.count >= minNameLength else { continue }
                let run = longestCommonRun(haystack, name)
                let ratio = Double(run) / Double(name.count)
                guard run >= minNameLength, ratio >= minRatio else { continue }
                if best == nil || run > best!.run || (run == best!.run && ratio > best!.ratio) { best = (run, ratio) }
            }
            if let best { scored.append(Scored(spot: spot, run: best.run, ratio: best.ratio)) }
        }
        return scored
            .sorted {
                if $0.run != $1.run { return $0.run > $1.run }
                if $0.ratio != $1.ratio { return $0.ratio > $1.ratio }
                return $0.spot.slug < $1.spot.slug
            }
            .prefix(PlaceSpotSuggestions.limit)
            .map(\.spot)
    }

    /// 候補を探すときに見る文の長さ（字）
    static let scanLimit = 120
    /// 候補にする、名前のうち続けて同じ字の割合の下限
    static let minRatio = 0.6

    /// 2つの並びで、いちばん長く続けて同じ所の長さ
    static func longestCommonRun(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        var current = previous
        var best = 0
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    current[j] = previous[j - 1] + 1
                    if current[j] > best { best = current[j] }
                } else {
                    current[j] = 0
                }
            }
            swap(&previous, &current)
        }
        return best
    }

    // MARK: - まとめ

    /// 写真から集めた場所と、文から入れた場所を1つに（写真が先・同じ場所は先の方）。
    /// 下書きの上限（`TripPicker.pickMax`）で切る
    static func merged(photos: [Found], added: [Found]) -> [Found] {
        var seen = Set<String>()
        return Array((photos + added).filter { seen.insert($0.id).inserted }.prefix(TripPicker.pickMax))
    }

    /// 帯の文（「この会話から旅行プランを作る」）と数（「2 か所」）
    static var bandTitle: String { L("この会話から旅行プランを作る", "Make a trip plan from this chat") }

    static func countLabel(_ n: Int) -> String {
        L("\(n) か所", Plural.count(n, "place"))
    }

    /// 下書きの「2 か所で 日付を選ぶ」
    static func nextTitle(count: Int) -> String {
        guard count > 0 else { return L("日付を選ぶ", "Choose dates") }
        return L("\(count) か所で 日付を選ぶ", count == 1 ? "Choose dates for 1 place" : "Choose dates for \(count) places")
    }
}
