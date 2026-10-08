import Foundation

/// 探すの「**季節・時間帯で絞る**」（2026-10-03・戦略の計画6）。「秋の京都」「夕方の海」のように、
/// 写真と撮影地を撮った季節・時間帯で絞る。
///
/// ## 写真
///
///  - **季節は撮影日の月**（春3〜5月・夏6〜8月・秋9〜11月・冬12〜2月。台帳と同じ区切り
///    `SpotBodyText.season(ofMonth:)`）。撮影日は `date`、無ければ EXIF の `dateTimeOriginal` の日付
///  - **南半球（緯度が負）の写真は季節を半年ずらす**——「秋の写真」はその土地の秋。座標が無ければ北半球として扱う
///  - **時間帯はカメラが書いた撮影時刻（EXIF）の時だけ**。`date` に付いている時刻は撮った時刻とは
///    限らない（`TakenDay` の注記）ので使わない。EXIF の日付が `date` と食い違う写真も使わない
///    （持ち主が撮影日を直した写真に別の日の時刻を当てない。`PhotoMetaLine.stamp` と同じ決まり）
///  - **分からない写真は入れない。** 撮影日の無い写真はどの季節にも、撮影時刻の無い写真はどの
///    時間帯にも入れない（「分からない」を「その季節」として数えない。色から探すと同じ考え）
///
/// ## 時間帯の区切り（2026-10-03 判断）
///
/// 撮影時刻の時（0〜23）で4つに分ける: 朝 5〜9時・日中 10〜15時・夕 16〜18時・夜 19〜4時。
/// **季節・緯度で日の入りは動く**（東京の日の入りは冬 16:30 頃・夏 19:00 頃）が、写真の時刻は
/// 時刻帯を持たない（EXIF の `dateTimeOriginal` は現地の時計の生の値）ので、太陽の高さからは
/// 決めない。分け方は画面に出す（`DayPart.hours`）——なぜこの写真が並ぶのかを隠さない
///
/// ## 撮影地（台帳）
///
///  - 季節: 季節の案内（`OfficialSpot.seasons`）にその季節の文がある公開済みのスポット
///  - 時間帯: 時間帯の案内（`OfficialSpot.times`）に当たる時間帯の文があるスポット。
///    台帳の6つを4つに寄せる: 夜明け・朝 → 朝、日中 → 日中、夕方の斜光・日没後 → 夕、夜 → 夜。
///    索引は時間帯の案内を載せている（2026-10-07 の実データで公開済み 1079件中 315件）。
///    案内の無い撮影地は時間帯で絞ると出ない
///  - 見出しは「冬の**案内がある**撮影スポット」（`Filter.spotsHeading`）——案内が「冬季は通行止め」
///    のこともあるので、「冬に撮れる」とは言わない
enum ShootingTime {

    // MARK: - 季節

    enum Season: String, CaseIterable, Identifiable {
        /// 生の値は台帳と同じ（`SpotBodyText.seasonOrder`）
        case spring, summer, autumn, winter

        var id: String { rawValue }

        /// 札の字（「秋」）
        var label: String { SpotBodyText.seasonLabel(rawValue) ?? rawValue }

        /// 半年先（南半球の読み替え）
        var opposite: Season {
            switch self {
            case .spring: return .autumn
            case .summer: return .winter
            case .autumn: return .spring
            case .winter: return .summer
            }
        }
    }

    // MARK: - 時間帯

    enum DayPart: String, CaseIterable, Identifiable {
        case morning, day, evening, night

        var id: String { rawValue }

        /// 札の字（板 11 の札は短く）
        var label: String {
            switch self {
            case .morning: return L("朝", "Morning")
            case .day: return L("日中", "Daytime")
            case .evening: return L("夕", "Evening")
            case .night: return L("夜", "Night")
            }
        }

        /// 「秋の夕方」のように語をつなぐときの言い方
        var phrase: String {
            switch self {
            case .morning: return L("朝", "morning")
            case .day: return L("日中", "daytime")
            case .evening: return L("夕方", "evening")
            case .night: return L("夜", "night")
            }
        }

        /// 区切り（撮影時刻の時）。**分け方を隠さない**ため画面の注記にも出す
        var hours: String {
            switch self {
            case .morning: return L("5〜9時", "5–9")
            case .day: return L("10〜15時", "10–15")
            case .evening: return L("16〜18時", "16–18")
            case .night: return L("19〜4時", "19–4")
            }
        }

        /// 台帳の時間帯（`SpotBodyText.timeOrder`）のうち、この札に寄せるもの
        var ledgerTimes: [String] {
            switch self {
            case .morning: return ["dawn", "morning"]
            case .day: return ["day"]
            case .evening: return ["goldenHour", "dusk"]
            case .night: return ["night"]
            }
        }

        /// 時（0〜23）から。範囲外は nil
        static func of(hour: Int) -> DayPart? {
            switch hour {
            case 5...9: return .morning
            case 10...15: return .day
            case 16...18: return .evening
            case 0...4, 19...23: return .night
            default: return nil
            }
        }
    }

    // MARK: - 写真から読む

    /// 撮った季節。撮影日が読めなければ nil
    static func season(of photo: Photo) -> Season? {
        let month = TakenDay.ymd(photo.date)?.1 ?? PhotoMetaLine.parts(photo.exif?.dateTimeOriginal)?.m
        guard let month, let season = Season(rawValue: SpotBodyText.season(ofMonth: month)) else { return nil }
        if let lat = photo.coords?.lat, lat < 0 { return season.opposite }
        return season
    }

    /// 撮った時間帯。**EXIF の撮影時刻だけ**から。`date` と日付が食い違えば nil
    static func dayPart(of photo: Photo) -> DayPart? {
        guard let exif = PhotoMetaLine.parts(photo.exif?.dateTimeOriginal), let hour = exif.hh else { return nil }
        if let (y, m, d) = TakenDay.ymd(photo.date), (y, m, d) != (exif.y, exif.m, exif.d) { return nil }
        return DayPart.of(hour: hour)
    }

    // MARK: - 絞り込み

    /// いま選んでいる季節と時間帯。**どちらも無ければ絞らない**
    struct Filter: Equatable, Hashable {
        var season: Season?
        var dayPart: DayPart?

        var isEmpty: Bool { season == nil && dayPart == nil }

        /// 写真が当たるか（選んでいない軸は問わない）
        func matches(_ photo: Photo) -> Bool {
            if let season, ShootingTime.season(of: photo) != season { return false }
            if let dayPart, ShootingTime.dayPart(of: photo) != dayPart { return false }
            return true
        }

        /// 撮影地が当たるか（季節は季節の案内、時間帯は時間帯の案内に文があるか）。
        /// **種類で見る**——索引だけの行（分けた置き場・文は詳細）でも絞れる（`OfficialSpot.seasonKeys`）
        func matches(_ spot: OfficialSpot) -> Bool {
            if let season, !spot.seasonKeys.contains(season.rawValue) { return false }
            if let dayPart, !spot.timeKeys.contains(where: { dayPart.ledgerTimes.contains($0) }) { return false }
            return true
        }

        /// 「秋の」「夕方の」「秋・夕方の」（節の見出しの頭）。絞っていなければ空。
        /// 英語は後ろに小文字の語が続く前提で、頭だけ大文字（"Autumn evening " + "shooting spots"）
        var prefix: String {
            let parts = [season?.label, dayPart?.phrase].compactMap { $0 }
            guard !parts.isEmpty else { return "" }
            let english = parts.map { $0.lowercased() }.joined(separator: " ")
            return L(parts.joined(separator: "・") + "の", english.prefix(1).uppercased() + english.dropFirst() + " ")
        }

        /// 撮影スポットの節の見出し（「冬の案内がある撮影スポット（3か所）」）。
        ///
        /// 2026-10-07 判断: 以前は「冬の撮影スポット」で、冬の案内が「冬季は通行止め」
        /// 「冬は休業」のようなスポット（実データで 192件中少なくとも5件）も並び、
        /// 冬に撮りに行ける所と読めた。絞っているのは**その季節・時間帯の案内があるか**なので、
        /// 見出しもそう言う（いちばん小さい直し。案内の中身は読み分けない）
        func spotsHeading(count: Int) -> String {
            let parts = [season?.label, dayPart?.phrase].compactMap { $0 }
            guard !parts.isEmpty else { return L("撮影スポット（\(count)か所）", "Shooting spots (\(count))") }
            let english = parts.map { $0.lowercased() }.joined(separator: " ")
            return L("\(prefix)案内がある撮影スポット（\(count)か所）",
                     "Shooting spots with \(english) notes (\(count))")
        }

        /// 絞り方の注記（どう分けたかを隠さない）。絞っていなければ nil
        var note: String? {
            var lines: [String] = []
            if season != nil {
                lines.append(L("季節は撮影日（春3〜5月・夏6〜8月・秋9〜11月・冬12〜2月。南半球で撮った写真は半年ずらす）",
                               "Season by date taken (spring Mar–May, summer Jun–Aug, autumn Sep–Nov, winter Dec–Feb; shifted by six months for photos taken in the Southern Hemisphere)"))
            }
            if let dayPart {
                lines.append(L("時間帯はカメラの撮影時刻（\(dayPart.label) \(dayPart.hours)）",
                               "Time of day by the camera's capture time (\(dayPart.label.lowercased()) \(dayPart.hours))"))
            }
            guard !lines.isEmpty else { return nil }
            return lines.joined(separator: L("、", "; "))
                + L("で絞っています。日時の分からない写真は入りません", ". Photos without a known date or time are not included.")
        }
    }

    static func photos(_ photos: [Photo], filter: Filter) -> [Photo] {
        filter.isEmpty ? photos : photos.filter(filter.matches)
    }

    /// 撮影地を絞る。**並びはそのまま**（語で探した順・索引の順を崩さない）
    static func spots(_ spots: [OfficialSpot], filter: Filter) -> [OfficialSpot] {
        filter.isEmpty ? spots : spots.filter(filter.matches)
    }

    /// 撮影地の行に添える案内の文（選んだ季節の文 → 選んだ時間帯の文の順で先に見つかったもの）。
    /// 絞っていない・文が無ければ nil
    static func guide(for spot: OfficialSpot, filter: Filter) -> String? {
        if let season = filter.season, let hit = spot.seasons.first(where: { $0.season == season.rawValue }) {
            return hit.text
        }
        if let dayPart = filter.dayPart,
           let hit = SpotBodyText.orderedTimes(spot.times).first(where: { dayPart.ledgerTimes.contains($0.time) }) {
            return hit.text
        }
        return nil
    }

    /// 当たるものがある時間帯（写真はカメラの撮影時刻、撮影地は時間帯の案内）。
    /// **0件の札は薄く出して押せなくする**——押しても空の結果しか出ない札を置かない
    static func dayParts(photos: [Photo], spots: [OfficialSpot]) -> Set<DayPart> {
        var found = Set(photos.compactMap { dayPart(of: $0) })
        for spot in spots where !spot.isDraft {
            for part in DayPart.allCases where spot.timeKeys.contains(where: { part.ledgerTimes.contains($0) }) {
                found.insert(part)
            }
        }
        return found
    }

    /// 発見の段（「季節・時間帯から探す」）を出すか。**押しても空になる段を置かない**
    /// ——季節か時間帯の分かる写真が1枚でもあるか、季節・時間帯の案内を持つ公開済みの撮影地があるとき
    static func hasAnything(photos: [Photo], spots: [OfficialSpot]) -> Bool {
        photos.contains { season(of: $0) != nil || dayPart(of: $0) != nil }
            || spots.contains { !$0.isDraft && (!$0.seasonKeys.isEmpty || !$0.timeKeys.isEmpty) }
    }
}
