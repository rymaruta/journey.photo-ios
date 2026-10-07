import Foundation

/// 「さがす」に出す塊（モック2 の「人気スポット」「季節のおすすめ」）。
///
/// **スポットの台帳は無い。** モックの「富士山 12,421件」は場所そのものの
/// 記録があって初めて出せる数だが、いまあるのは**写真に書かれた撮影地の
/// 文字列**だけ（`api-user` に場所のマスタは無い）。
///
/// だから**写真から数える**。同じ場所の写真が何枚あるかは正確に出せるし、
/// 押せば `/location/*` の集約（`TagPhotosView`）へ行ける。
/// **「12,421件」のような他所から持ってきた数は出さない。**
enum DiscoverySections {

    /// 1つの塊に出す枚数
    static let perSection = 6

    struct Spot: Identifiable, Equatable {
        /// 撮影地の文字列（集約ページの鍵にもなる）
        let id: String
        let count: Int
        /// 表紙にする写真
        let cover: Photo
    }

    /// 写真の多い撮影地。**同数なら名前順**（毎回同じ並びにする）。
    ///
    /// **ゆるく畳まない。** 「パリ」と「パリ, フランス」は別の札として出す
    /// ——集約ページ側（`PhotoQuery.photos(_, in: .location)`）は
    /// ゆるく一致させるので、どちらを押しても同じ写真が出る。
    /// ここで畳むと、どちらの綴りを見せるかを決める根拠が無い。
    static func popularSpots(in photos: [Photo], limit: Int = 6) -> [Spot] {
        var byPlace: [String: [Photo]] = [:]
        for photo in photos {
            let place = (photo.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !place.isEmpty else { continue }
            byPlace[place, default: []].append(photo)
        }
        return byPlace
            .compactMap { place, list -> Spot? in
                guard let cover = GallerySort.popular.apply(list).first else { return nil }
                // 🔴 **数えるのは行き先と同じ関数で。** 完全一致で数えていたので、
                // 札に「2枚の写真」と書いて開くと3枚出ていた（run 55 の実機の絵）。
                // Web は同じ食い違いを `collectEntries` で直してある——
                // 「見出しの（N枚）と実際に並ぶ枚数が食い違う」と名指しで書いてある
                //
                // **表紙はここを変えない。** 表紙の元（`list`）は撮影地の文字列で
                // 分けた束なので**互いに重ならない**＝2枚の札が同じ表紙になることは
                // 無い。run 56 の絵を見て「フランス」と「フランス ヴェルサイユ」が
                // 同じ絵に見えたので重複よけを書いたが、**変異を当てたら1件も
                // 落ちなかった**——よく見ると別の写真（柱頭と列柱）で、
                // 直す対象が最初から無かった。消した
                let counted = PhotoQuery.photos(photos, in: .location(place)).count
                return Spot(id: place, count: counted, cover: cover)
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
            .prefix(limit)
            .map { $0 }
    }

    /// 季節のおすすめ。**いまの季節のタグ**を先に出す。
    ///
    /// モックの「春の桜 / 夏の絶景 / 秋の紅葉」にあたる。決まった
    /// 選択肢（`TagChoices.all`）の中の**季節そのものを言う語**だけを使う。
    ///
    /// 🔴 2026-10-07 判断: 以前は「森」「海」「空」「夜」「花」も季節の語に入れていて、
    /// 冬の雪景色（タグ forest）が秋に並んでいた。森・海・空・夜・花は一年中あるので外す
    static func seasonalTags(now: Date = Date(), calendar: Calendar = .current) -> [String] {
        words(for: currentSeason(now: now, calendar: calendar)).map(\.ja)
    }

    /// いまの季節（西暦の月で決める——イスラム暦などの月は季節と合わない）
    static func currentSeason(now: Date = Date(), calendar: Calendar = .current) -> ShootingTime.Season {
        let month = calendar.gregorianKeepingZone.component(.month, from: now)
        return ShootingTime.Season(rawValue: SpotBodyText.season(ofMonth: month)) ?? .winter
    }

    /// その季節を言うタグ（日本語の選択肢と、注記に出す英語）
    private static func words(for season: ShootingTime.Season) -> [(ja: String, en: String)] {
        switch season {
        case .spring: return [("春", "spring"), ("桜", "cherry blossoms")]
        case .summer: return [("夏", "summer")]
        case .autumn: return [("秋", "autumn"), ("紅葉", "autumn leaves")]
        case .winter: return [("冬", "winter"), ("雪", "snow")]
        }
    }

    private static func keys(for season: ShootingTime.Season) -> Set<String> {
        Set(words(for: season).map { TagChoices.key($0.ja) })
    }

    /// 季節の写真に入れてよい分類か（2026-10-07 判断）。
    /// **料理は入れない**——タグ「秋」の付いたご飯🍚が「いまの季節の写真」に並んでいた。
    /// **分類の無い写真も入れない**（何が写っているか分からない。色から探す #176 と同じ考え）。
    /// 色から探すの `ColorFamilies.allows` は札ごとの景色の約束なので使わず、ここは料理だけを外す
    static func seasonAllows(_ photo: Photo) -> Bool {
        guard let raw = photo.category?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return false }
        return CategoryChoices.key(raw) != "food"
    }

    /// その季節のタグを持つ写真（多い順ではなく**新しい順**——
    /// 季節は「いま」の話なので、古い写真を先に出しても嬉しくない）。
    ///
    /// 2026-10-07 判断: タグだけでは足りないので次も見る。
    ///  - **ほかの季節の語を持つ写真は外す**（「秋」と「winter」の両方が付いた写真は季節が決められない）
    ///  - **撮影日の分かる写真は、撮った季節**（`ShootingTime.season`・南半球は半年ずらす）も合わせる
    ///  - 料理・分類の無い写真は外す（`seasonAllows`）
    static func seasonal(in photos: [Photo], now: Date = Date(),
                         calendar: Calendar = .current, limit: Int = 6) -> [Photo] {
        let season = currentSeason(now: now, calendar: calendar)
        let wanted = keys(for: season)
        let others = Set(ShootingTime.Season.allCases.filter { $0 != season }.flatMap { keys(for: $0) })
        let matched = photos.filter { photo in
            guard seasonAllows(photo) else { return false }
            let have = Set((photo.tags ?? []).map { TagChoices.key($0) })
            guard !wanted.isDisjoint(with: have), others.isDisjoint(with: have) else { return false }
            if let taken = ShootingTime.season(of: photo), taken != season { return false }
            return true
        }
        return Array(GallerySort.new.apply(matched).prefix(limit))
    }

    /// 「いまの季節の写真」の先の小さい字（どう集めたかを隠さない）。英語表示では英語の語で
    static func seasonalNote(now: Date = Date(), calendar: Calendar = .current) -> String {
        let season = currentSeason(now: now, calendar: calendar)
        let list = words(for: season)
        let months: (ja: String, en: String) = {
            switch season {
            case .spring: return ("3〜5月", "Mar–May")
            case .summer: return ("6〜8月", "Jun–Aug")
            case .autumn: return ("9〜11月", "Sep–Nov")
            case .winter: return ("12〜2月", "Dec–Feb")
            }
        }()
        return L(list.map { "#\($0.ja)" }.joined(separator: " ")
                 + "（撮影日の分かる写真は\(months.ja)に撮ったもの。料理の写真は入れない）",
                 "Tagged " + list.map(\.en).joined(separator: " or ")
                 + " (photos with a known date were taken \(months.en); food photos are left out)")
    }
}
