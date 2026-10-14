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
    static func destination(photo: Photo, spot: OfficialSpot?) -> Destination? {
        if let spot, !spot.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .spot(spot)
        }
        let label = (photo.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        let slug = LocationSlug.make(label)
        guard !slug.isEmpty else { return nil }
        return .place(label: label, slug: slug)
    }

    // MARK: - いつ行く（1行）

    /// 「いつ」の1行。**台帳のスポットだけ**（撮影地の文字列には座標の確かさが無い）。
    ///
    /// 1. 座標と時刻帯が引ければ、**次のゴールデンアワー**（今日の朝・夕、無ければ明日の朝・夕のうち、
    ///    まだ終わっていない最初のもの）。時刻はその土地の時計
    /// 2. 引けなければ、索引の「季節の案内がある季節」（撮りどきの季節）
    /// 3. どちらも無ければ nil（行ごと出さない・作り話をしない）
    static func whenLine(spot: OfficialSpot, now: Date, deviceZone: TimeZone = .current) -> String? {
        if let golden = nextGolden(spot: spot, now: now, deviceZone: deviceZone) { return golden }
        return seasonLine(spot)
    }

    /// 次のゴールデンアワー（例「次のゴールデンアワー 今日 16:48–17:20」）。極夜・白夜で無い日は飛ばす
    static func nextGolden(spot: OfficialSpot, now: Date, deviceZone: TimeZone = .current) -> String? {
        guard let coords = spot.coords,
              let zone = SunTimes.timeZone(named: spot.timeZone, country: spot.region?.country) else { return nil }
        for offset in 0...1 {
            guard let ymd = SpotLight.ymd(offset: offset, from: now, in: zone),
                  let times = SunTimes.compute(ymd, lat: coords.lat, lng: coords.lng) else { continue }
            for span in [times.morningGolden, times.eveningGolden] {
                guard let start = span.start, let end = span.end, end > now,
                      let text = SunTimes.span(span, in: zone) else { continue }
                let day = offset == 0 ? L("今日", "today") : L("明日", "tomorrow")
                // 端末と違う時計の土地では「現地」と添える（日本から海外のスポットを見たとき）
                let local = zone.secondsFromGMT(for: start) == deviceZone.secondsFromGMT(for: start)
                    ? "" : L("（現地）", " (local)")
                return L("次のゴールデンアワー \(day) \(text)\(local)",
                         "Next golden hour \(day) \(text)\(local)")
            }
        }
        return nil
    }

    /// 撮りどきの季節（例「撮りどき 春・秋」）。索引の種類だけ（文は詳細）。知らない季節は落とす
    static func seasonLine(_ spot: OfficialSpot) -> String? {
        let kinds = Set(spot.seasonKinds?.value ?? spot.seasonalGuide?.value.map(\.season) ?? [])
        let labels = SpotBodyText.seasonOrder.filter(kinds.contains).compactMap(SpotBodyText.seasonLabel)
        guard !labels.isEmpty else { return nil }
        return L("撮りどき \(labels.joined(separator: "・"))", "Best in \(labels.joined(separator: ", "))")
    }

    /// 「経路」を出すか（座標のある台帳のスポットだけ。撮影地の文字列は場所が確かでない）
    static func offersDirections(_ destination: Destination?) -> Bool {
        destination?.spot?.coords != nil
    }
}
