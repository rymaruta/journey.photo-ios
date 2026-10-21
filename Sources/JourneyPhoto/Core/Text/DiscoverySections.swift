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
    /// 🔴 2026-10-21 判断（全画面の点検 11-探す）: **市・名所の細かさの名前でまとめる**（`spotName`）。
    /// 以前は撮影地の文字列そのままで分けていて（「ゆるく畳まない」）、本番の写真では
    /// 「フランス」（国名だけ・5枚）と「フランス ヴェルサイユ」（2枚）が並び、
    /// **「フランス」の札が2枚**に見えた。「パリ」と「パリ, フランス」も別の札だった。
    ///  - 国名・郵便番号の欠片は落とす（「パリ, フランス」→「パリ」・「フランス ヴェルサイユ」→「ヴェルサイユ」・
    ///    「ヴェルサイユ, Versailles, …, 78000, フランス」→「ヴェルサイユ」）
    ///  - **国名しか無い撮影地は出さない**（国は「撮影地」として広すぎ、近くの地名で補うと当て推量になる）
    ///  - 同じ名前（空白・大小を無視）は1枚の札にまとめる
    static func popularSpots(in photos: [Photo], limit: Int = 6) -> [Spot] {
        var byPlace: [String: (name: String, list: [Photo])] = [:]
        for photo in photos {
            guard let name = spotName(photo.location) else { continue }
            let key = LocationMatch.normalized(name)
            byPlace[key, default: (name: name, list: [])].list.append(photo)
        }
        return byPlace.values
            .compactMap { group -> Spot? in
                let place = group.name
                let list = group.list
                guard let cover = GallerySort.popular.apply(list).first else { return nil }
                // 🔴 **数えるのは行き先と同じ関数で。** 完全一致で数えていたので、
                // 札に「2枚の写真」と書いて開くと3枚出ていた（run 55 の実機の絵）。
                // Web は同じ食い違いを `collectEntries` で直してある——
                // 「見出しの（N枚）と実際に並ぶ枚数が食い違う」と名指しで書いてある
                //
                // **表紙はここを変えない。** 表紙の元（`list`）は札の名前で
                // 分けた束なので**互いに重ならない**＝2枚の札が同じ表紙になることは
                // 無い。run 56 の絵を見て「フランス」と「フランス ヴェルサイユ」が
                // 同じ絵に見えたので重複よけを書いたが、**変異を当てたら1件も
                // 落ちなかった**——よく見ると別の写真（柱頭と列柱）で、
                // 直す対象が最初から無かった。消した
                let counted = PhotoQuery.photos(photos, in: .location(place)).count
                // 1字の名前は行き先の突き合わせ（`photoIsIn`）が当てない。0枚の札は出さない
                guard counted > 0 else { return nil }
                return Spot(id: place, count: counted, cover: cover)
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
            .prefix(limit)
            .map { $0 }
    }

    /// 人気の撮影地の札の名前（市・名所の細かさ）。**国名しか無ければ nil**（2026-10-21 判断）。
    ///
    ///     「パリ, フランス」→「パリ」          「フランス ヴェルサイユ」→「ヴェルサイユ」
    ///     「蔵王キツネ村, …, 白石市, 宮城県, 989-0733, 日本」→「蔵王キツネ村」
    ///     「宮城県, 白石市, 蔵王キツネ村」（大きい順に打った）→「蔵王キツネ村」
    ///     「フランス」「France」「日本」→ nil
    ///
    /// 名前は**元の撮影地の中にそのまま在る語**だけ——行き先（`PhotoQuery` の `.location`）が
    /// 同じ写真を拾えるように、作った名前・訳した名前にはしない
    static func spotName(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ",，、"))
            .map { stripCountry($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty && !LocationMatch.isPostalOrNumber($0) }
        guard let first = parts.first, let last = parts.last else { return nil }
        // 大きい順に打った撮影地（先頭が県・市・最後が県ではない）は、いちばん細かい最後の欠片。
        // 場所の検索の答え（小さい順・最後が県）の「蔵王キツネ村」は先頭が「村」で終わるが、名前なので先頭
        if parts.count >= 2, LocationMatch.isAdministrative(first), !RegionList.prefectures.contains(last) {
            return last
        }
        return first
    }

    /// 欠片から国名を落とす。欠片そのものが国名なら空、空白で区切った頭か尾の国名
    /// （「フランス ヴェルサイユ」「Kyoto Japan」）は外す。語の途中の国名（「フランス・メトロポリテーヌ」）は触らない。
    /// 英語の国名は**尾だけ**見る（頭で外すと「Turkey Hill」のような地名が欠ける）
    private static func stripCountry(_ part: String) -> String {
        var text = part
        let table = VisitedCountries.table
        if table.contains(where: { text == $0.ja || text.caseInsensitiveCompare($0.en) == .orderedSame }) { return "" }
        for entry in table where text.hasPrefix(entry.ja + " ") || text.hasPrefix(entry.ja + "　") {
            text = String(text.dropFirst(entry.ja.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        for name in table.flatMap({ [$0.ja, $0.en] }) {
            let lower = text.lowercased()
            if lower.hasSuffix(" " + name) || lower.hasSuffix("　" + name) {
                text = String(text.dropLast(name.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return text
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

    /// 「いまの季節の写真」の先の小さい字（どう集めたかを隠さない）。英語表示では英語の語で。
    /// 月の範囲は書かない——南半球で撮った写真は半年ずらして見るので、「9〜11月に撮った」とは限らない
    static func seasonalNote(now: Date = Date(), calendar: Calendar = .current) -> String {
        let list = words(for: currentSeason(now: now, calendar: calendar))
        return L(list.map { "#\($0.ja)" }.joined(separator: " ")
                 + "（ほかの季節に撮った写真・料理・分類の無い写真は入れない）",
                 "Tagged " + list.map(\.en).joined(separator: " or ")
                 + " (excluding photos taken in another season, food and uncategorized photos)")
    }
}
