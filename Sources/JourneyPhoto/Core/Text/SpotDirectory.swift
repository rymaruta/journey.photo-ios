import Foundation

/// 撮影スポット台帳の引き当て。**Web の `lib/utils/spots.ts` と同じ規則**
/// （どちらかだけ直すと、アプリとサイトで違う場所が出る）。
enum SpotDirectory {

    /// 名前の突き合わせ用の正規化。**判定にしか使わない**（表示は生の名前）
    static func normalize(_ value: String?) -> String {
        guard let value else { return "" }
        let folded = value.folding(options: [.widthInsensitive, .caseInsensitive], locale: nil)
        return folded.unicodeScalars
            .filter { scalar in
                !CharacterSet.whitespacesAndNewlines.contains(scalar)
                    && !"()（）「」『』,、，".unicodeScalars.contains(scalar)
            }
            .map(String.init)
            .joined()
    }

    static func spot(id: String?, in spots: [Spot]) -> Spot? {
        guard let id, !id.isEmpty else { return nil }
        return spots.first { $0.spotId == id }
    }

    static func spot(slug: String?, in spots: [Spot]) -> Spot? {
        guard let slug, !slug.isEmpty else { return nil }
        return spots.first { $0.slug == slug }
    }

    /// 名前で探す。**完全一致 → 前方一致 → 部分一致**の順。別名も見る
    static func search(_ query: String, in spots: [Spot], limit: Int = 20) -> [Spot] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }
        var scored: [(spot: Spot, rank: Int)] = []
        for spot in spots {
            let names = ([spot.name] + (spot.aliases ?? [])).map(normalize)
            var rank = -1
            for name in names {
                if name == q { rank = 0; break }
                if name.hasPrefix(q) { rank = rank < 0 ? 1 : min(rank, 1); continue }
                if name.contains(q), rank < 0 { rank = 2 }
            }
            if rank >= 0 { scored.append((spot, rank)) }
        }
        return scored
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.spot.name < $1.spot.name }
            .prefix(limit)
            .map(\.spot)
    }

    /// 近くのスポット（近い順）。**座標は約1km に丸めてある**ので、
    /// 半径を1km以下にしても答えは細かくならない
    static func nearby(_ point: Photo.Coords, in spots: [Spot],
                       radiusKm: Double = 5, limit: Int = 20) -> [Spot] {
        spots
            .compactMap { spot -> (Spot, Double)? in
                guard let coords = spot.coords else { return nil }
                return (spot, TravelDistance.kilometers(from: point, to: coords))
            }
            .filter { $0.1 <= radiusKm }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// そのスポットの公開写真（新しい順）。
    ///
    /// **`spotId` でしか数えない。** 撮影地の文字列が似ているだけの写真を
    /// 混ぜると、画面の枚数が「本当に紐づけた数」より多く見える
    /// ——数えていない数を出さない、という約束（指示書 15）に反する。
    static func photos(of spot: Spot, in photos: [Photo]) -> [Photo] {
        GallerySort.new.apply(photos.filter { $0.spotId == spot.spotId && $0.published != false })
    }

    /// 代表写真。台帳の指定を優先し、無ければ**紐づいた写真の中でいちばん人気**。
    /// どちらも無ければ nil（**でっち上げない**）
    static func cover(of spot: Spot, in photos: [Photo]) -> Photo? {
        let linked = self.photos(of: spot, in: photos)
        if let id = spot.coverPhotoId, let picked = linked.first(where: { $0.id == id }) { return picked }
        return GallerySort.popular.apply(linked).first
    }
}
