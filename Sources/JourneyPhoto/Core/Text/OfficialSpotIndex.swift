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
        // 空の語は、索引をそろえる前に返す（そろえる手間を払わない）
        guard !spotName(query).isEmpty else { return [] }
        return Prepared(spots, aliases: aliases).matches(query: query, limit: limit)
    }

    /// **字をそろえ終えた索引**（2026-11-13 判断・札 #590「探すの検索が重い」）。
    ///
    /// Mac の UI テスト（回 1219）で、探すの1字ごとに `matches` が 9〜12 回・1回 475〜812ms かかっていた。
    /// Linux の Release（本番 3,899 件）での内訳は次のとおりで、**語に関わらず毎回、全件の字をそろえ直していた**:
    /// - 名前・読み・英語名・別名をそろえる（`spotName`）のに約 160ms
    /// - 地域をそろえて当てる（`regionMatches`）のに約 175ms
    ///
    /// そこで次のようにする:
    /// - 各行の名前・別名・地域のそろえた字を、ここで**1回だけ**作って控える。当てるときはそろえ直さない
    ///   （語のほうは1回の当てに1回だけそろえる）
    /// - 部分一致（`contains`）と地域の名前の当て方（`LocationMatch.nameIn`）は、字（Character）単位で比べるので重い
    ///   （そろえ終えた後でも 1回 約 13〜19ms と 12〜18ms）。そこで先に **UTF-8 のバイト列で含まれるか**を見て、
    ///   含まれない行は字単位の比べ方を飛ばす。どちらも語が中に字として入っていることが前提で、
    ///   バイト列は両方とも字をそろえた（NFC）形なので、字として入っていればバイト列でも入っている。
    ///   **結果は変わらない**（バイト列で入っていた行は、今までの比べ方で決める）
    ///
    /// Linux の Release では、1回の当てが約 265ms から約 5ms 前後になり、そろえるのは索引ごとに約 220ms。
    /// 当て方・並びは `matches` と同じ（`matches` もこれを通るので、当て方は1か所）。
    /// 作り終えたら変えない（参照の型。同じ索引かは `===` で見る）
    final class Prepared: @unchecked Sendable {
        /// そろえた字と、その UTF-8 のバイト列（含まれるかの下調べ用）
        fileprivate struct Text {
            let value: String
            let bytes: [UInt8]

            init(_ value: String) {
                self.value = value
                bytes = Array(value.precomposedStringWithCanonicalMapping.utf8)
            }
        }

        fileprivate struct Row {
            /// 名前・英語名・読み・別名をそろえた字（空は落とす）
            let names: [Text]
            /// 国（日本は除く）・県・市区町村・県＋市・全部をつないだ字をそろえたもの（空は落とす）
            let regionFields: [Text]
        }

        fileprivate let rows: [Row]
        /// 渡された行（順はそのまま）
        let spots: [OfficialSpot]

        /// そろえた行の数
        var count: Int { rows.count }

        init(_ spots: [OfficialSpot], aliases: [String: [String]] = [:]) {
            self.spots = spots
            rows = spots.map { spot in
                Row(names: ([spot.name, spot.nameEn, spot.reading] + (aliases[spot.slug] ?? []))
                        .map(OfficialSpotIndex.spotName).filter { !$0.isEmpty }.map(Text.init),
                    regionFields: OfficialSpotIndex.regionFields(spot).map(Text.init))
            }
        }

        /// `OfficialSpotIndex.matches` と同じ当て方・並び（そろえた字を使う）
        func matches(query: String, limit: Int? = nil) -> [OfficialSpot] {
            let positions = matchPositions(query: query)
            return (limit.map { Array(positions.prefix($0)) } ?? positions).map { spots[$0] }
        }

        /// 当たった行の位置（`spots` の添字）を `matches` と同じ順で。
        /// 探すは、当てる材料が同じ今の一覧（詳細を重ねた後）の行をこの位置で取る（`SearchSpotHits`）
        func matchPositions(query: String) -> [Int] {
            // 当てる1回の区間（`PerfSignpost.spotMatch`・2026-11-13 札 #590）。**UI テストのときだけ**（Debug・`-JPPreviewPerfProbe`）
            let signpost = PerfRecorder.shared.isEnabled ? PerfSignpost.begin(.spotMatch) : nil
            defer { if let signpost { PerfSignpost.end(signpost) } }
            let needle = OfficialSpotIndex.spotName(query)
            guard !needle.isEmpty else { return [] }
            let needleText = Text(needle)
            let region = RegionQuery(query)
            return rows.enumerated()
                .compactMap { i, row -> (Int, Int)? in
                    var rank = OfficialSpotIndex.rankByNames(row.names, needleText)
                    if rank < 0, region.hits(row.regionFields) { rank = 3 }
                    return rank < 0 ? nil : (rank, i)
                }
                .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
                .map(\.1)
        }
    }

    /// `hay` の中に `needle` のバイト列が入っているか（字単位で比べる前の下調べ）
    fileprivate static func bytesContain(_ hay: [UInt8], _ needle: [UInt8]) -> Bool {
        let n = needle.count
        guard n > 0 else { return true }
        guard n <= hay.count else { return false }
        let first = needle[0]
        return hay.withUnsafeBufferPointer { h in
            needle.withUnsafeBufferPointer { l in
                var i = 0
                let last = h.count - n
                while i <= last {
                    if h[i] == first {
                        var j = 1
                        while j < n, h[i + j] == l[j] { j += 1 }
                        if j == n { return true }
                    }
                    i += 1
                }
                return false
            }
        }
    }

    /// Web の `normalizeSpotName`（`lib/utils/spots.ts`）と同じ。**判定にしか使わない**。
    /// 写真の撮影地の当て方（`MapSearch.matches`）には使わない
    static func spotName(_ value: String?) -> String {
        (value ?? "").precomposedStringWithCompatibilityMapping
            .lowercased()
            .filter { !$0.isWhitespace && !"()（）「」『』,、，".contains($0) }
    }

    /// Web の `rankByNames`。完全一致 0・前方一致 1・部分一致 2・外れ -1。
    /// `names` は**そろえ終えた**字（空は落としてある・`Prepared`）。部分一致はバイト列で下調べしてから字で比べる
    fileprivate static func rankByNames(_ names: [Prepared.Text], _ needle: Prepared.Text) -> Int {
        var rank = -1
        for name in names {
            if name.value == needle.value { return 0 }
            if name.value.hasPrefix(needle.value) { rank = 1; continue }
            if rank < 0, bytesContain(name.bytes, needle.bytes), name.value.contains(needle.value) { rank = 2 }
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
        RegionQuery(query).hits(regionFields(spot).map(Prepared.Text.init))
    }

    /// 地域の欄をそろえた字（国（日本は除く）・県・市区町村・県＋市・全部をつないだ字。空は落とす）。
    /// 索引をそろえるとき（`Prepared`）に1回だけ作る
    fileprivate static func regionFields(_ spot: OfficialSpot) -> [String] {
        guard let r = spot.region else { return [] }
        let country = r.country == "日本" ? nil : r.country
        let pair: String = [r.prefecture, r.city].compactMap { $0 }.joined()
        let whole: String = [country, r.prefecture, r.city].compactMap { $0 }.joined()
        return [country, r.prefecture, r.city, pair, whole].map(spotName).filter { !$0.isEmpty }
    }

    /// 語を地域に当てる形にそろえたもの（1回の当てで1回だけ作る。以前は行ごとにそろえ直していた）
    fileprivate struct RegionQuery {
        /// 空白・読点で区切ってそろえた語（空は落とす）
        let words: [Prepared.Text]
        /// 区切らずにそろえた語全体
        let whole: Prepared.Text

        init(_ query: String) {
            words = query.components(separatedBy: CharacterSet(charactersIn: "、,，").union(.whitespacesAndNewlines))
                .map(OfficialSpotIndex.spotName).filter { !$0.isEmpty }.map(Prepared.Text.init)
            whole = Prepared.Text(OfficialSpotIndex.spotName(query))
        }

        func hits(_ fields: [Prepared.Text]) -> Bool {
            guard !fields.isEmpty else { return false }
            func hit(_ word: Prepared.Text) -> Bool {
                // `nameIn` は語が字として中に入っているときだけ当たる。バイト列で入っていなければ飛ばす
                !word.value.isEmpty && fields.contains {
                    $0.value.hasPrefix(word.value)
                        || (OfficialSpotIndex.bytesContain($0.bytes, word.bytes)
                            && LocationMatch.nameIn($0.value, word.value, boundaries: OfficialSpotIndex.regionMarks))
                }
            }
            if words.count > 1, words.allSatisfy(hit) { return true }
            return hit(whole)
        }
    }

    /// 海外の地域名の切れ目（「アンダルシア州」「ブルターニュ地方」）
    fileprivate static let regionMarks = ["州", "地方"]

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
