import Foundation

/// 撮影スポットの索引（`OfficialSpot`）を**手元で引く**。通信しない。
///
/// 名前で探す（地図の検索窓）と、近くのスポット（画面の末尾）の2つ。
/// どちらも画面を持たない層に置いて、Linux の `swift test` で動かす。
enum OfficialSpotIndex {

    /// 名前・読み・英語名・別名・国・都道府県・市区町村のどれかに当たるもの。
    /// **空の語は何も当てない**（「絞っていない」）。2026-11-09 から当て方は Web の一覧の検索の正本
    /// （`SpotSearchIndex`・`docs/spot-list-search.md`）: ひらがな・カタカナ・全角半角・大小・空白・中黒・括弧・
    /// ピリオドを見ない、空白区切りの複数語は AND（最大 6 語）、県の読み・英語名でも県が引ける。
    ///
    /// 並び: 名前・英語名・読み・別名で**完全一致 → 前方一致 →
    /// 部分一致**、地域だけで当たったものはその後ろ。別名は名前と同じ扱い。
    /// 同じ段の中は渡された順（索引の順）。`limit` が nil なら全部
    /// （地図は枠で並べ直してから切るので、ここでは切らない）。
    /// `aliases` は slug → 別名（`OfficialSpotService.fetchAliases`・無ければ空）
    static func matches(_ spots: [OfficialSpot], query: String, limit: Int? = nil,
                        aliases: [String: [String]] = [:]) -> [OfficialSpot] {
        // 空の語は索引を作らずに返す（1回きりの呼び出しで全件を折りたたまない）
        guard !SpotSearchIndex.terms(query).isEmpty else { return [] }
        return SpotSearchIndex(spots, aliases: aliases).hits(query: query, limit: limit).map(\.spot)
    }

    /// Web の `normalizeSpotName`（`lib/utils/spots.ts`）と同じ揃え方。判定にしか使わない。
    /// 写真の撮影地の当て方（`MapSearch.matches`）には使わない。
    /// 🔴 **検索窓の折りたたみは別**（`SpotSearchIndex.fold`・かな・中黒・ピリオドも見ない）。これは変えない
    static func spotName(_ value: String?) -> String {
        (value ?? "").precomposedStringWithCompatibilityMapping
            .lowercased()
            .filter { !$0.isWhitespace && !"()（）「」『』,、，".contains($0) }
    }

    /// 地域（国・都道府県・市区町村）で当たるか。国は日本の外の行だけに載る——
    /// 「日本」は当てない（索引に載ると「本」で国内のほぼ全部が当たる）。
    ///
    /// 🔴 2026-10-07 判断: 以前は Web の `regionLabel` のように「国 県 市」をつないだ字に
    /// 部分一致していて、「京都」で東京都のスポットが22件混ざった（「東**京都**千代田区」）。
    /// いまは国・県・市区町村（と県＋市をつないだ字）を**別々に**見て、次のどれかなら当てる:
    ///  - その欄が語で**始まる**（「神奈」→ 神奈川県・「トスカーナ」→ トスカーナ州）
    ///  - 語が欄の中に**名前として**入っている（`LocationMatch.nameIn`。前後が端・行政区分の字・
    ///    海外の「州」「地方」）——「箱根」→ 足柄下郡箱根町、「東山」→ 京都市東山区
    ///
    /// 空白で区切った語（「神奈川 箱根」）は**どの語もどれかの欄に**当たること。
    /// 区切らずに続けた「東京都千代田区」は県＋市をつないだ字に当てる
    static func regionMatches(_ spot: OfficialSpot, query: String) -> Bool {
        SpotSearchIndex.regionMatches(fields: SpotSearchIndex.regionFields(of: spot), query: query)
    }

    /// 写真の場所の候補（`PlaceSpotSuggestions`）が使う別名の当て方（`MapSearch.fold` の揃え方のまま）
    static func aliasMatches(_ aliases: [String]?, needle: String) -> Bool {
        (aliases ?? []).contains { MapSearch.fold($0).contains(needle) }
    }

    /// 「近く」と呼んでよい距離（km）。写真から作る撮影地（`DerivedSpot.nearbyMaxKm`）と同じ
    static let nearbyMaxKm: Double = 50

    /// 近くの撮影スポット。**座標を持っているものだけ**、自分を除いて近い順。
    /// 距離は写真と同じ式（`TravelDistance.kilometers`）。同じ距離は slug 順。
    /// **同じ `spotId` は1つだけ（先勝ち）**——画面は `spotId` で並べるので、
    /// 重なると同じ札が2つ出る（索引を読む側 `LenientOfficialSpotList` でも落とす）
    ///
    /// 🔴 **`nearbyMaxKm` より遠い場所は出さない。** 以前は上限が無く、近くに
    /// 索引の行が少ない場所では数百km先まで「近く」と名乗っていた。
    /// 足りなくても遠い場所で埋めない（0件なら節ごと出ない）
    static func nearby(_ spot: OfficialSpot, in spots: [OfficialSpot],
                       limit: Int = 6, maxKm: Double = nearbyMaxKm) -> [(spot: OfficialSpot, km: Double)] {
        guard let here = spot.coords else { return [] }
        var seen: Set<String> = [spot.spotId]
        return spots
            .filter { seen.insert($0.spotId).inserted }
            .compactMap { other -> (spot: OfficialSpot, km: Double)? in
                guard let there = other.coords else { return nil }
                let km = TravelDistance.kilometers(from: here, to: there)
                return km <= maxKm ? (other, km) : nil
            }
            .sorted { $0.km != $1.km ? $0.km < $1.km : $0.spot.slug < $1.spot.slug }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 経路の行き先

    /// 経路の行き先を名前の検索結果から拾い直すときの距離（km）。
    ///
    /// 🔴 **索引の座標は約1km に丸めてある**（小数2桁。台帳 `content/spots.json`
    /// の時点で丸めてあり、丸める前の値はどこにも無い）。丸めのずれは最大で
    /// 緯度 0.005°≒0.56km・経度 0.005°≒0.45km、斜めで約0.7km。そのまま
    /// 経路に渡すと、山や滝では**入口と違う道の上**に案内する。
    /// 地図で押した地点の拾い直し（`PlaceLookup.sameSpotKm` = 0.3km）より
    /// 広く取るのはこのずれのぶん
    static let directionsMatchKm: Double = 1.5

    /// 名前で探した候補のうち、丸めた座標から `directionsMatchKm` 以内で
    /// いちばん近いものの位置。無ければ nil（丸めた座標に名前を付けて渡す）
    static func directionsTargetIndex(of candidates: [Photo.Coords], near rounded: Photo.Coords) -> Int? {
        PlaceLookup.nearestIndex(of: candidates, to: rounded, withinKm: directionsMatchKm)
    }

    /// 経路の検索を待つ秒数。過ぎたら丸めた座標にスポット名を付けて開く
    static let directionsTimeout: Double = 3
}
