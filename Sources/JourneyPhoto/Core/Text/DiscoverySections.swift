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
    /// 選択肢（`TagChoices.all`）の中の季節の語だけを使う。
    static func seasonalTags(now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let month = calendar.component(.month, from: now)
        switch month {
        case 3...5: return ["春", "桜", "花"]
        case 6...8: return ["夏", "海", "空"]
        case 9...11: return ["秋", "紅葉", "森"]
        default: return ["冬", "雪", "夜"]
        }
    }

    /// その季節のタグを持つ写真（多い順ではなく**新しい順**——
    /// 季節は「いま」の話なので、古い写真を先に出しても嬉しくない）。
    static func seasonal(in photos: [Photo], now: Date = Date(),
                         calendar: Calendar = .current, limit: Int = 6) -> [Photo] {
        let wanted = Set(seasonalTags(now: now, calendar: calendar).map { TagChoices.key($0) })
        let matched = photos.filter { photo in
            let have = Set((photo.tags ?? []).map { TagChoices.key($0) })
            return !wanted.isDisjoint(with: have)
        }
        return Array(GallerySort.new.apply(matched).prefix(limit))
    }
}
