import Foundation

/// **写真から、次の旅へ**（2026-10-14 owner「写真から、次の旅が始まるSNS」）。
///
/// 人の写真を見た人が、そこから 行き先（撮影スポット）→ 行きたい → いつ・どう行く → 同じ場所で撮る、
/// へ進めるようにする。写真の詳細（`PhotoDetailView`）の「行き先」の段が使う決まりをここに集める
/// （画面の部品は Linux で動かせないので、判断は値で試せる形にする）。
///
/// **通信しない。** 台帳の索引は画面が既存の口（`OfficialSpotService.fetchIndexRows`）で読んで渡す。
/// 光の時刻は座標と日付から端末で計算する（`SunTimes`）。
enum PhotoTrip {

    /// 写真の行き先
    enum Destination: Equatable {
        /// 台帳の撮影スポット（`Photo.spotId` で紐づいた行）
        case spot(OfficialSpot)
        /// 撮影地の文字列（スラッグが作れたもの）。台帳の行が無い・引けない写真
        case place(label: String, slug: String)

        /// 「行きたい」の鍵。**スポットの頁・撮影地の頁と同じ決まり**（`SavedSpotKey`）——
        /// 同じ鍵なので、どこで押しても状態がそろう
        var wishKey: String {
            switch self {
            case .spot(let spot): return SavedSpotKey.official(spot.slug)
            case .place(_, let slug): return slug
            }
        }

        /// 読み上げ・知らせに使う名前
        var name: String {
            switch self {
            case .spot(let spot): return spot.name
            case .place(let label, _): return LocationMatch.display(label)
            }
        }

        var spot: OfficialSpot? {
            if case .spot(let spot) = self { return spot }
            return nil
        }
    }

    /// 写真に紐づいた台帳の行。**`spotId` だけで引く**（撮影地の文字列では当てない・`OfficialSpot` の注記）。
    /// `spotId` が無い・索引が読めない・見つからないときは nil（何も出さない）
    static func spot(for photo: Photo, in index: [OfficialSpot]?) -> OfficialSpot? {
        guard let id = photo.spotId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              let index else { return nil }
        return index.first { $0.spotId == id }
    }

    /// 写真の行き先。台帳の行があればそれ、無ければ撮影地（スラッグが空になる撮影地は無し）。
    ///
    /// 🔴 **スラッグの空な撮影地（「---」など）には出さない**——押しても `WishlistStore` は
    /// 何も残さない（`SpotDetailView` の「行きたい」と同じ理由）。台帳の行のスラッグが空でも同じ
    ///
    /// 🔴 **撮影地の「行きたい」は公開の写真だけ**（`isPublic`・2026-10-14 のレビュー）。下書き・
    /// フォロワーのみ・親しい友達の写真の撮影地は、その人が広く見せていない場所——行きたいの一覧
    /// （ログイン中は Web にも出る）へ広げない。台帳のスポットは公開の台帳なのでこの限りではない
    static func destination(photo: Photo, spot: OfficialSpot?) -> Destination? {
        if let spot, !spot.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .spot(spot)
        }
        guard isPublic(photo) else { return nil }
        let label = (photo.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        let slug = LocationSlug.make(label)
        guard !slug.isEmpty else { return nil }
        return .place(label: label, slug: slug)
    }

    /// 公開（下書きでない・全員に見せる）写真か。`published` の無い写真は公開の一覧から来たもの
    /// （`PhotoDetailRules.acceptsReactions` と同じ読み）。公開範囲は空か `everyone` だけ
    static func isPublic(_ photo: Photo) -> Bool {
        guard photo.published != false else { return false }
        let raw = (photo.audience ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty || raw == Audience.everyone.rawValue
    }

    // MARK: - この近くの撮影スポット（`spotId` の無い写真・撮影地の頁）

    /// 「この近くの撮影スポット」と呼んでよい距離（km）。**2026-10-16 判断: 2km。**
    ///
    /// 写真の座標も台帳の座標も**約1kmに丸めてある**（小数2桁・斜めのずれは最大 約0.7km ずつ）。
    /// 同じ場所でも丸めだけで 約1.4km 離れて見えるので、それを包む 2km にした。
    /// これより広げると、隣の町の別の名所を「この近く」と呼ぶ（地図の「近くの撮影スポット」の
    /// `OfficialSpotIndex.nearbyMaxKm` = 50km は「足を延ばせる所」の距離で、ここの用途とは違う）
    static let nearbySpotMaxKm: Double = 2

    /// 座標からいちばん近い台帳の撮影スポット（`nearbySpotMaxKm` 以内・座標とスラッグのある行だけ）。
    /// 🔴 **運営の下書き（`isDraft`）の行は出さない**——まだ確かめていない行を「この近く」と勧めない
    /// 選び方は地図で押した地点の拾い直しと同じ（`PlaceLookup.nearestIndex`）。無ければ nil（行ごと出さない）
    static func nearbySpot(to coords: Photo.Coords?, in index: [OfficialSpot],
                           maxKm: Double = nearbySpotMaxKm) -> OfficialSpot? {
        guard let coords else { return nil }
        let usable = index.filter {
            !$0.isDraft && $0.coords != nil && !$0.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let i = PlaceLookup.nearestIndex(of: usable.compactMap(\.coords), to: coords, withinKm: maxKm) else {
            return nil
        }
        return usable[i]
    }

    /// 行の呼び名（写真の詳細・撮影地の頁で同じ語）
    static var nearbySpotTitle: String { L("この近くの撮影スポット", "Photo spot nearby") }

    /// 写真の詳細で「この近くの撮影スポット」を探しに行く鍵。**`spotId` の無い写真で、座標のあるときだけ**
    /// （`spotId` のある写真は「撮影スポット」の行がもう台帳の頁へ行く）。写真と座標で変わる
    /// （写真を送った直後・座標を直した直後に前の写真の行を出さない・`Loaded.spotId` に入れて比べる）
    static func nearbySpotKey(photo: Photo) -> String? {
        guard normalizedSpotId(photo.spotId) == nil, let c = photo.coords else { return nil }
        return "near|\(photo.id)|\(c.lat),\(c.lng)"
    }

    // MARK: - 読み込み（写真ごと）

    /// 読み終えた台帳の行。**どの `spotId` で読んだか**を持つ（写真を送った直後に前の写真の
    /// スポット・行きたい・経路・時刻を出さないため・2026-10-14 のレビュー）
    struct Loaded {
        /// 読んだときの写真の `spotId`（前後の空白を落としたもの）
        let spotId: String
        /// 引けた台帳の行（索引が読めない・見つからないなら nil）
        let spot: OfficialSpot?
        /// スポットの頁に渡す索引（読めなければ空）
        let index: [OfficialSpot]
        /// スポットの頁に渡す公開写真（読めなければ nil＝「まだありません」を言わない）
        let photos: [Photo]?

        /// 写真を後から足す（索引を読んだ時点で段を出し、一覧の取り直しを待たない）
        func withPhotos(_ photos: [Photo]) -> Loaded {
            Loaded(spotId: spotId, spot: spot, index: index, photos: photos)
        }
    }

    /// 今の写真に対する読み込みの段階
    enum Stage {
        /// `spotId` の無い写真（読みに行かない）
        case none
        /// `spotId` はあるが、まだこの写真の分を読み終えていない（前の写真の分しか無いときも）
        case loading
        /// この写真の `spotId` で読み終えた
        case ready(Loaded)

        /// 使ってよい読み込み結果（この写真の分だけ）
        var loaded: Loaded? {
            if case .ready(let l) = self { return l }
            return nil
        }
    }

    static func normalizedSpotId(_ raw: String?) -> String? {
        let id = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    /// 写真の `spotId` と、手元の読み込み結果から段階を決める。**読んだ `spotId` が違えば使わない**
    static func stage(photoSpotId: String?, loaded: Loaded?) -> Stage {
        guard let id = normalizedSpotId(photoSpotId) else { return .none }
        guard let loaded, loaded.spotId == id else { return .loading }
        return .ready(loaded)
    }

    /// 段に出す行き先。**読み込み中は出さない**——読み終わると鍵が撮影地のスラッグから `SPOT-…` に
    /// 変わるので、その前に押した「行きたい」が別の鍵に入る（2026-10-14 のレビュー）
    static func sectionDestination(photo: Photo, stage: Stage) -> Destination? {
        switch stage {
        case .loading: return nil
        case .none: return destination(photo: photo, spot: nil)
        case .ready(let l): return destination(photo: photo, spot: l.spot)
        }
    }

    // MARK: - いつ行く（1行）

    /// 「いつ」の1行。**台帳のスポットだけ**（撮影地の文字列には座標の確かさが無い）。
    ///
    /// 1. 座標と時刻帯が引ければ、**次のゴールデンアワー**（今日の朝・夕、無ければ明日の朝・夕のうち、
    ///    まだ終わっていない最初のもの）。時刻はその土地の時計
    /// 2. 引けなければ、索引の「季節の案内がある季節」（おすすめの季節）
    /// 3. どちらも無ければ nil（行ごと出さない・作り話をしない）
    static func whenLine(spot: OfficialSpot, now: Date, deviceZone: TimeZone = .current) -> String? {
        if let golden = nextGolden(spot: spot, now: now, deviceZone: deviceZone) { return golden }
        return seasonLine(spot)
    }

    /// 次のゴールデンアワー（例「次のゴールデンアワー 今日 16:48–17:20」）。極夜・白夜で無い日は飛ばす。
    ///
    /// 🔴 **「今日・明日」は、始まる時刻をその土地の暦で見て決める**（2026-10-14・日付変更線のテスト）。
    /// `SunTimes.compute` の日付は経度で決まる太陽の日なので、トンガ（西経175°・UTC+13）のように経度と
    /// 時刻帯が日付変更線をまたぐ土地では、その土地の「今日」の日付で計算した朝が翌朝になる。
    /// 前後の日も計算して、まだ終わっていないうち最も早いものを選び、その土地の暦で日を言う
    static func nextGolden(spot: OfficialSpot, now: Date, deviceZone: TimeZone = .current) -> String? {
        guard let coords = spot.coords,
              let zone = SunTimes.timeZone(named: spot.timeZone, country: spot.region?.country),
              let today = SpotLight.ymd(offset: 0, from: now, in: zone),
              let tomorrow = SpotLight.ymd(offset: 1, from: now, in: zone) else { return nil }
        var spans: [(start: Date, span: SunTimes.Span)] = []
        for offset in -1...2 {
            guard let ymd = SpotLight.ymd(offset: offset, from: now, in: zone),
                  let times = SunTimes.compute(ymd, lat: coords.lat, lng: coords.lng) else { continue }
            for span in [times.morningGolden, times.eveningGolden] {
                guard let start = span.start, let end = span.end, end > now else { continue }
                spans.append((start, span))
            }
        }
        guard let next = spans.min(by: { $0.start < $1.start }),
              let text = SunTimes.span(next.span, in: zone),
              let startDay = SpotLight.ymd(offset: 0, from: next.start, in: zone) else { return nil }
        let day: String
        if startDay <= today {
            // 始まっていて、まだ終わっていない（今まさにゴールデンアワー）も「今日」
            day = L("今日", "today")
        } else if startDay == tomorrow {
            day = L("明日", "tomorrow")
        } else {
            return nil
        }
        // 端末と違う時計の土地では「現地」と添える（日本から海外のスポットを見たとき）
        let local = zone.secondsFromGMT(for: next.start) == deviceZone.secondsFromGMT(for: next.start)
            ? "" : L("（現地）", " (local)")
        return L("次のゴールデンアワー \(day) \(text)\(local)",
                 "Next golden hour \(day) \(text)\(local)")
    }

    /// おすすめの季節（例「おすすめの季節 春・秋」）。2026-10-22 判断: owner の好みで「撮りどき」は画面の文に使わない。索引の種類だけ（文は詳細）。知らない季節は落とす
    static func seasonLine(_ spot: OfficialSpot) -> String? {
        let kinds = Set(spot.seasonKinds?.value ?? spot.seasonalGuide?.value.map(\.season) ?? [])
        let labels = SpotBodyText.seasonOrder.filter(kinds.contains).compactMap(SpotBodyText.seasonLabel)
        guard !labels.isEmpty else { return nil }
        return L("おすすめの季節 \(labels.joined(separator: "・"))", "Best in \(labels.joined(separator: ", "))")
    }

    /// 「経路」を出すか（座標のある台帳のスポットだけ。撮影地の文字列は場所が確かでない）
    static func offersDirections(_ destination: Destination?) -> Bool {
        destination?.spot?.coords != nil
    }
}
