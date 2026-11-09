import Foundation

/// 撮影スポットの索引（`OfficialSpot`）を**手元で引く**。通信しない。
///
/// 名前で探す（地図の検索窓）と、近くのスポット（画面の末尾）の2つ。
/// どちらも画面を持たない層に置いて、Linux の `swift test` で動かす。
enum OfficialSpotIndex {

    /// 名前・読み・英語名・別名・国・都道府県・市区町村のどれかに当たるもの。
    /// **空の語は何も当てない**（「絞っていない」）。揃え方は Web の `normalizeSpotName`
    /// （`spotName`）: 全角半角・大小に加えて、空白と括弧・読点も見ない
    /// （「嵐山渡月橋」で「嵐山 渡月橋」に当たる）。
    ///
    /// 並びは Web の `searchSpotRows` と同じ: 名前・英語名・読み・別名で**完全一致 → 前方一致 →
    /// 部分一致**、地域だけで当たったものはその後ろ。別名は名前と同じ扱い。
    /// 同じ段の中は渡された順（索引の順）。`limit` が nil なら全部
    /// （地図は枠で並べ直してから切るので、ここでは切らない）。
    /// `aliases` は slug → 別名（`OfficialSpotService.fetchAliases`・無ければ空）
    static func matches(_ spots: [OfficialSpot], query: String, limit: Int? = nil,
                        aliases: [String: [String]] = [:]) -> [OfficialSpot] {
        // 空の語は索引を作らずに返す（1回きりの呼び出しで全件を折りたたまない）
        guard !spotName(query).isEmpty else { return [] }
        return SpotSearchIndex(spots, aliases: aliases).hits(query: query, limit: limit).map(\.spot)
    }

    /// Web の `normalizeSpotName`（`lib/utils/spots.ts`）と同じ揃え方に、**ひらがな・カタカナの違いを見ない**
    /// （2026-11-09・owner 要望）を足したもの。判定にしか使わない。
    /// 写真の撮影地の当て方（`MapSearch.matches`）には使わない
    static func spotName(_ value: String?) -> String {
        foldKana((value ?? "").precomposedStringWithCompatibilityMapping.lowercased())
            .filter { !$0.isWhitespace && !"()（）「」『』,、，".contains($0) }
    }

    /// カタカナ（ァ〜ヶ）をひらがなに寄せる。長音「ー」・中黒「・」はそのまま。
    /// 半角カタカナは `spotName` が先に NFKC で全角にしている
    static func foldKana(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for u in text.unicodeScalars {
            if (0x30A1...0x30F6).contains(u.value), let h = Unicode.Scalar(u.value - 0x60) {
                out.append(h)
            } else {
                out.append(u)
            }
        }
        return String(out)
    }

    /// 打った語を空白・読点で区切った語（折りたたみ済み・空は除く）
    static func queryWords(_ query: String) -> [String] {
        query.components(separatedBy: CharacterSet(charactersIn: "、,，").union(.whitespacesAndNewlines))
            .map(spotName).filter { !$0.isEmpty }
    }

    /// Web の `rankByNames`。完全一致 0・前方一致 1・部分一致 2・外れ -1。
    /// `names` は `spotName` で折りたたみ済みの名前（`SpotSearchIndex` が1回だけ作る）
    static func rank(of names: [String], needle: String) -> Int {
        var rank = -1
        for name in names {
            if name == needle { return 0 }
            if name.hasPrefix(needle) { rank = 1; continue }
            if name.contains(needle), rank < 0 { rank = 2 }
        }
        return rank
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
        regionMatches(fields: regionFields(of: spot), query: query)
    }

    /// 国（日本以外）・県・市区町村・県＋市・全部をつないだ字（折りたたみ済み・空は除く）。地域の無い行は空
    static func regionFields(of spot: OfficialSpot) -> [String] {
        guard let r = spot.region else { return [] }
        let country = r.country == "日本" ? nil : r.country
        let pair: String = [r.prefecture, r.city].compactMap { $0 }.joined()
        let whole: String = [country, r.prefecture, r.city].compactMap { $0 }.joined()
        return [country, r.prefecture, r.city, pair, whole].map(spotName).filter { !$0.isEmpty }
    }

    /// 1語（折りたたみ済み）が地域の欄のどれかに当たるか
    static func regionHit(fields: [String], word: String) -> Bool {
        !word.isEmpty && fields.contains { $0.hasPrefix(word) || LocationMatch.nameIn($0, word, boundaries: regionMarks) }
    }

    static func regionMatches(fields: [String], query: String) -> Bool {
        guard !fields.isEmpty else { return false }
        let words = queryWords(query)
        if words.count > 1, words.allSatisfy({ regionHit(fields: fields, word: $0) }) { return true }
        return regionHit(fields: fields, word: spotName(query))
    }

    /// 海外の地域名の切れ目（「アンダルシア州」「ブルターニュ地方」）
    private static let regionMarks = ["州", "地方"]

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
