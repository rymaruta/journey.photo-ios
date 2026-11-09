import Foundation

/// 撮影スポットの一覧の検索窓が引く、**折りたたみ済みの索引**（2026-11-09・owner「撮影スポットを探す一覧に検索窓がほしい」）。
///
/// 通信しない。端末にある索引（`OfficialSpot`）と別名（`OfficialSpotService.fetchAliases`）だけを使う。
///
/// ## なぜ別の型にしたか
/// `OfficialSpotIndex.matches` は呼ぶたびに全件・全名前を折りたたんでいた（全角半角を揃える NFKC は安くない）。
/// 一覧は描き直しのたびに引くので、**名前・読み・別名・地域の欄を最初に1回だけ折りたたんで持つ**。
/// 索引（`officialSpots`）か別名が替わったときだけ作り直す（`PhotoMapViewModel.spotSearchIndex`）。
///
/// ## 当て方（`OfficialSpotIndex.matches` と同じ。違いは下の2点）
/// 名前・英語名・読み・別名で **完全一致 0 → 前方一致 1 → 部分一致 2**、地域（県・市区町村・国）だけで当たったものは 3。
/// 1. **ひらがな・カタカナの違いを見ない**（`OfficialSpotIndex.spotName`）——「たかや」でも「タカヤ」でも当たる
/// 2. **空白で区切った複数語は AND**——「高屋 香川」は、どの語も名前か地域のどこかに当たるスポット。
///    まず続けた1語（空白なし）として名前に当て、外れたときだけ AND に回す（従来の当たりは変えない）。
///    AND の順位は**いちばん弱い語**の順位（名前の前方一致の語と地域の語なら 3）
struct SpotSearchIndex {

    struct Hit: Equatable {
        let spot: OfficialSpot
        /// 0 完全一致・1 前方一致・2 部分一致・3 地域（または AND の弱い語が地域）
        let rank: Int
    }

    private struct Entry {
        let spot: OfficialSpot
        /// 名前・英語名・読み・別名（`OfficialSpotIndex.spotName` で折りたたみ済み・空は除く）
        let names: [String]
        /// 国・県・市区町村・県＋市・全部（`OfficialSpotIndex.regionFields`）
        let regionFields: [String]
    }

    private let entries: [Entry]

    init(_ spots: [OfficialSpot], aliases: [String: [String]] = [:]) {
        entries = spots.map { spot in
            let raw: [String?] = [spot.name, spot.nameEn, spot.reading] + (aliases[spot.slug] ?? [])
            return Entry(spot: spot,
                         names: raw.map(OfficialSpotIndex.spotName).filter { !$0.isEmpty },
                         regionFields: OfficialSpotIndex.regionFields(of: spot))
        }
    }

    var count: Int { entries.count }

    /// 当たったスポット（順位 → 渡された順）。**空の語は何も当てない**（「絞っていない」）
    func hits(query: String, limit: Int? = nil) -> [Hit] {
        let whole = OfficialSpotIndex.spotName(query)
        guard !whole.isEmpty else { return [] }
        let words = OfficialSpotIndex.queryWords(query)
        var found: [(hit: Hit, index: Int)] = []
        for (i, entry) in entries.enumerated() {
            var rank = OfficialSpotIndex.rank(of: entry.names, needle: whole)
            if rank < 0, OfficialSpotIndex.regionMatches(fields: entry.regionFields, query: query) { rank = 3 }
            if rank < 0, words.count > 1 { rank = andRank(entry, words: words) }
            if rank >= 0 { found.append((Hit(spot: entry.spot, rank: rank), i)) }
        }
        found.sort { $0.hit.rank != $1.hit.rank ? $0.hit.rank < $1.hit.rank : $0.index < $1.index }
        let hits = found.map(\.hit)
        guard let limit else { return hits }
        return Array(hits.prefix(limit))
    }

    /// どの語も名前か地域に当たるときの順位（いちばん弱い語）。1語でも外れたら -1
    private func andRank(_ entry: Entry, words: [String]) -> Int {
        var worst = 0
        for word in words {
            var r = OfficialSpotIndex.rank(of: entry.names, needle: word)
            if r < 0, OfficialSpotIndex.regionHit(fields: entry.regionFields, word: word) { r = 3 }
            if r < 0 { return -1 }
            worst = max(worst, r)
        }
        return worst
    }
}
