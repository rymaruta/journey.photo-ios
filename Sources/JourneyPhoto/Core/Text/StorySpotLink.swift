import Foundation

/// ストーリーの撮影地から、**撮影スポットのガイド**（`OfficialSpotView`）へつなぐ
/// （2026-09-30・owner「iOS のストーリー機能大好きだからもっと作り込みたい」）。
///
/// 友達の旅先のストーリーから「ここに行きたい」へ一直線につなぐ——インスタに無い、
/// 写真の旅のアプリならではの作り込み。サーバーは変えない（撮影地の文字と約1kmの座標は
/// ストーリーが既に持ち、索引は端末にある）。
///
/// 🔴 **取り違えるくらいなら結ばない。** 結ぶのは次の全部を満たすときだけ:
///  - ストーリーに**座標がある**（座標の無い回は結ばない——「飛島村」が山形の飛島、
///    「月山富田城」が山形の月山に当たった。部分一致の「索引の中で1件だけ」は、世の中で
///    一意という意味ではない）
///  - 撮影地の文字に**スポットの名前がそのまま入っている**、または撮影地の最初の区切り
///    （「高屋神社, 観音寺市, …」の「高屋神社」）が**日本語名の最初の語と同じ**（4文字以上。
///    実データの名前は「高屋神社 本宮（天空の鳥居）」のように後ろが長い）。空白は無視する
///  - スポットが **`maxKm` 以内**。いちばん近いもの
///  - 下書き（運営未確認）でない
///
/// 🔴 **括弧の中は名前として当てない**（「旧・」で始まる旧称だけ当てる）。実データで括弧つきの
/// 名前は48件あり、中身はほとんど**地名**（パリ・プラハ・尾道・屋久島・奈良公園…）だった。
/// 当てると「パリ, フランス」だけの撮影地がノートルダム大聖堂に結ばれた（9952462 のレビュー）
enum StorySpotLink {

    /// 名前が当たっても、これより離れていれば別の場所とみなす（座標はどちらも約1kmに丸めてある）
    static let maxKm: Double = 5

    /// 名前として当てる最短の文字数（短い名前が地名の一部に当たらないように）
    static let minNameLength = 2

    /// 撮影地の最初の区切りを「名前の最初の語」として当てる最短の文字数
    static let minPrefixLength = 4

    /// 日本語名の**空白の前の最初の語**（「高屋神社 本宮（天空の鳥居）」→「高屋神社」）。
    /// 空白の無い名前は nil（名前そのものは `names` の含み当てで拾う）。
    ///
    /// 🔴 **英語名には使わない・頭の一致（前方一致）にしない。** 英語名の頭で当てると「Kyoto」が
    /// 京都駅ビル、「Helsinki」がヘルシンキ中央駅に、前方一致だと「明治神宮」が明治神宮外苑に
    /// 結ばれた（eb10587 のレビュー）
    static func firstWord(of spot: OfficialSpot) -> String? {
        let outer = splitParentheses(spot.name).outer
        let words = outer.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 2, let first = words.first else { return nil }
        return squash(String(first))
    }

    static func spot(for story: Story, in spots: [OfficialSpot]) -> OfficialSpot? {
        spot(location: story.location, coords: story.coords, in: spots)
    }

    /// 撮影地の文字と座標から結ぶ。作る画面の候補（`StorySpotSuggestion`）が、
    /// **見る画面で本当に結ばれるか**を投稿の前に確かめるのにも使う（同じ1本で判定する）
    static func spot(location: String?, coords: Photo.Coords?, in spots: [OfficialSpot]) -> OfficialSpot? {
        guard let raw = location, let here = coords else { return nil }
        // **市区町村・都道府県・国だけの区切りは落とす**（索引が知っている地名）。
        // 「姫島村, 大分県」が姫島に、「十和田市」が十和田市現代美術館に結ばれていた
        let areas = areaNames(in: spots)
        let segments = segments(of: raw).filter { !areas.contains($0) }
        guard let head = segments.first else { return nil }
        let place = segments.joined()
        return spots
            .compactMap { spot -> (spot: OfficialSpot, km: Double, length: Int)? in
                guard !spot.isDraft, let there = spot.coords else { return nil }
                let names = names(of: spot)
                // 当たった名前の長さ（**長く当たった方を先に**——「明治神宮外苑」の撮影地が、
                // 近い方の「明治神宮」に取られていた）
                var length = names.filter { place.contains($0) }.map(\.count).max() ?? 0
                if head.count >= minPrefixLength, firstWord(of: spot) == head { length = max(length, head.count) }
                guard length > 0 else { return nil }
                let km = TravelDistance.kilometers(from: here, to: there)
                return km <= maxKm ? (spot, km, length) : nil
            }
            .min { a, b in
                if a.length != b.length { return a.length > b.length }
                if a.km != b.km { return a.km < b.km }
                return a.spot.slug < b.spot.slug
            }?
            .spot
    }

    /// 当てる名前: 名前・括弧を除いた名前・「旧・」で始まる括弧の中（旧称）・英語名
    static func names(of spot: OfficialSpot) -> [String] {
        var out: [String] = []
        func add(_ s: String?) {
            guard let s else { return }
            // **名前の中の読点・カンマも落とす**——撮影地は区切りで切ってつなぐので、英語名
            // 「Lake Onuma, Mount Akagi」のようなカンマ入りの名前が本人に当たらなかった
            let folded = squash(s).filter { $0 != "," && $0 != "、" && $0 != "，" }
            if folded.count >= minNameLength { out.append(folded) }
        }
        add(spot.name)
        let (outer, inner) = splitParentheses(spot.name)
        add(outer)
        inner.filter { $0.hasPrefix("旧・") }.forEach { add(String($0.dropFirst("旧・".count))) }
        add(spot.nameEn)
        return out
    }

    /// 全角半角・大小を畳み、**空白を落とす**（「高屋神社 本宮」と「高屋神社本宮」を同じに）
    static func squash(_ s: String) -> String {
        MapSearch.fold(s).filter { !$0.isWhitespace }
    }

    /// 撮影地を読点・カンマで切り、畳む（空は落とす）。「高屋神社, 観音寺市, 香川県」→ 3つ
    static func segments(of s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == "、" || $0 == "，" })
            .map { squash(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// 索引が知っている地名（市区町村・都道府県。索引に国があれば国も）と「日本」。畳んだ形。
    /// **「市・町・村・区・郡・県・都・府」を外した形も入れる**（「近江八幡市」→「近江八幡」。
    /// 撮影地に「近江八幡」とだけ書くと、名前の最初の語が同じ八幡堀に結ばれた）。
    /// 2文字未満になるもの・**スポットの名前そのものになるもの**（「姫島村」→「姫島」＝島のスポット）は入れない
    static func areaNames(in spots: [OfficialSpot]) -> Set<String> {
        var out: Set<String> = ["日本", "japan"]
        let suffixes: Set<Character> = ["市", "町", "村", "区", "郡", "県", "都", "府"]
        let spotNames = Set(spots.flatMap { [squash($0.name), squash(splitParentheses($0.name).outer)] })
        for spot in spots {
            for name in [spot.region?.prefecture, spot.region?.city, spot.region?.country].compactMap({ $0 }) {
                let folded = squash(name)
                guard !folded.isEmpty else { continue }
                // 「南都留郡山中湖村」は「山中湖村」とも書かれる（郡を外した形も地名）
                var forms = [folded]
                // 「〜郡〜町／村」の形のときだけ（「郡上市」「蒲郡市」の郡では切らない）
                if let gun = folded.lastIndex(of: "郡"), folded.index(after: gun) < folded.endIndex,
                   let last = folded.last, last == "町" || last == "村" {
                    forms.append(String(folded[folded.index(after: gun)...]))
                }
                for form in forms {
                    out.insert(form)
                    if let last = form.last, suffixes.contains(last), form.count >= 3 {
                        let bare = String(form.dropLast())
                        if !spotNames.contains(bare) { out.insert(bare) }
                    }
                }
            }
        }
        return out
    }

    /// 「A（B）」→ ("A", ["B"])。全角・半角の括弧の両方
    static func splitParentheses(_ name: String) -> (outer: String, inner: [String]) {
        var outer = ""
        var inner: [String] = []
        var current = ""
        var depth = 0
        for ch in name {
            if ch == "（" || ch == "(" {
                depth += 1
                if depth == 1 { current = ""; continue }
            } else if ch == "）" || ch == ")" {
                if depth == 1 { inner.append(current.trimmingCharacters(in: .whitespaces)) }
                depth = max(0, depth - 1)
                continue
            }
            if depth == 0 { outer.append(ch) } else { current.append(ch) }
        }
        return (outer.trimmingCharacters(in: .whitespaces), inner.filter { !$0.isEmpty })
    }

    /// 押せる撮影地の行に出す文字の上限（これを超えたら詰めて「…」）
    static let maxShownLength = 20

    /// 押せる行は文字の幅だけ当たり判定を持つので、**長い撮影地は文字の側で詰める**
    static func shortened(_ place: String) -> String {
        place.count > maxShownLength ? String(place.prefix(maxShownLength - 1)) + "…" : place
    }
}

