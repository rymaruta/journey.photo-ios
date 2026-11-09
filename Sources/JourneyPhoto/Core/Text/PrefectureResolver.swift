import Foundation

/// 写真から**県の候補**を導く（行った県マップ・札 #503）。サーバーの `badges.ts prefectureOfPhoto` と**同じ順序**:
///
///   ① 写真に結んだ撮影スポットの県（`Photo.spotId`）
///   ② 撮影地の文字に書かれた県（正式名 → 短い名 → 英語。いちばん前に書かれたもの）
///   ③ 座標から、いちばん近い撮影スポットの県（`nearbyLimitKm` 以内）
///
/// 2026-11-08 判断:
/// - **ここで出るのは候補だけ。** 回数に入れるのは本人のタップ（`VisitedPrefectures.add`）。
///   写真の枚数・投稿数では回数を増やさない（分けて投稿する不正を作らない）
/// - 数えてよい写真はサーバーの `isCountablePhoto` と同じ（実体があり、公開で、下書きでない）。
///   ストーリーは `Photo` に持たない（一覧に来ない）
/// - ②は「東京都」の中の「京都」を京都府に当てない（`CamperCounting.prefecture(in:)` は短い名の
///   順序に頼っていて、この除外が無い）。正式名は `RegionList.prefecture(inText:)`、英語の県名の並びは
///   `ShareCardMap.englishPrefectures` を使い回す。英語は長音の記号を落として比べる（"Hyōgo"）——
///   サーバーより広く拾うだけで、候補なので害は無い
/// - 県名の無い写真（座標だけ）は③。日本の外枠（北緯20〜46・東経122〜154）の外は引かない（サーバーと同じ）
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
struct PrefectureResolver: Equatable {

    /// 座標を寄せてよい距離の上限（km）。サーバーの `NEAREST_PREF_MAX_KM`
    static let nearbyLimitKm = 40.0

    struct Anchor: Equatable {
        let coords: Photo.Coords
        let prefecture: String
    }

    /// 撮影スポットの id → 県
    let spotPrefectures: [String: String]
    /// 座標のある撮影スポットの県の手がかり
    let anchors: [Anchor]

    static let empty = PrefectureResolver(spotPrefectures: [:], anchors: [])

    init(spotPrefectures: [String: String], anchors: [Anchor]) {
        self.spotPrefectures = spotPrefectures
        self.anchors = anchors
    }

    /// 台帳の撮影スポットから作る。県が47都道府県の名前と一致する公開済みの行だけ
    /// （フランスの「イヴリーヌ県」を拾わない・`RegionList` と同じ）
    init(spots: [OfficialSpot]) {
        var byId: [String: String] = [:]
        var anchors: [Anchor] = []
        for spot in spots where !spot.isDraft {
            guard let prefecture = spot.region?.prefecture, RegionList.prefectures.contains(prefecture) else { continue }
            byId[spot.spotId] = prefecture
            if let c = spot.coords { anchors.append(Anchor(coords: c, prefecture: prefecture)) }
        }
        self.init(spotPrefectures: byId, anchors: anchors)
    }

    // MARK: - 写真 → 県

    func prefecture(of photo: Photo) -> String? {
        if let id = photo.spotId, let byId = spotPrefectures[id] { return byId }
        if let byText = Self.prefecture(inText: photo.location) { return byText }
        if let c = photo.coords { return nearestPrefecture(to: c) }
        return nil
    }

    /// サーバーの `isCountablePhoto`
    static func isCountable(_ photo: Photo) -> Bool {
        !photo.src.isEmpty && photo.published != false
    }

    /// 自分の写真から導けた県（JIS の順）
    func found(in photos: [Photo]) -> [String] {
        var set = Set<String>()
        for photo in photos where Self.isCountable(photo) {
            if let p = prefecture(of: photo) { set.insert(p) }
        }
        return RegionList.prefectures.filter { set.contains($0) }
    }

    func nearestPrefecture(to c: Photo.Coords) -> String? {
        guard c.lat.isFinite, c.lng.isFinite, abs(c.lat) <= 90, abs(c.lng) <= 180 else { return nil }
        // 日本のおおよその外枠（与那国〜択捉・沖ノ鳥島〜宗谷）。外なら引かない
        guard c.lat >= 20, c.lat <= 46, c.lng >= 122, c.lng <= 154 else { return nil }
        var bestKm = Double.infinity
        var bestPrefecture: String?
        for anchor in anchors {
            // 緯度で1度（約111km）以上離れた点は距離を計るまでもない
            if abs(anchor.coords.lat - c.lat) > 1 { continue }
            let km = TravelDistance.kilometers(from: c, to: anchor.coords)
            if km < bestKm { bestKm = km; bestPrefecture = anchor.prefecture }
        }
        guard let bestPrefecture, bestKm <= Self.nearbyLimitKm else { return nil }
        return bestPrefecture
    }

    // MARK: - 撮影地の文字 → 県

    /// 「京都府」→「京都」。北海道はそのまま
    static func shortName(_ name: String) -> String {
        guard name != "北海道", let last = name.last, "都府県".contains(last) else { return name }
        return String(name.dropLast())
    }

    static func prefecture(inText raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let text = raw.precomposedStringWithCompatibilityMapping
        // ① 正式名（いちばん前）
        if let official = RegionList.prefecture(inText: text) { return official }
        // ② 短い名。「東京都」の中の「京都」は当てない
        let chars = Array(text)
        var shortBest: (offset: Int, name: String)?
        for name in RegionList.prefectures {
            let short = Array(shortName(name))
            guard !short.isEmpty, chars.count >= short.count else { continue }
            var i = 0
            while i + short.count <= chars.count {
                if Array(chars[i..<(i + short.count)]) == short {
                    let insideTokyo = short == Array("京都") && i > 0 && chars[i - 1] == "東"
                    if !insideTokyo {
                        if shortBest == nil || i < shortBest!.offset { shortBest = (i, name) }
                        break
                    }
                }
                i += 1
            }
        }
        if let shortBest { return shortBest.name }
        // ③ 英語（単語として）。"Kyoto"・"Miyagi Prefecture"・"Hyōgo"
        let lower = text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                 locale: Locale(identifier: "en_US_POSIX"))
        let letters = Array(lower)
        var englishBest: (offset: Int, name: String)?
        for (index, en) in ShareCardMap.englishPrefectures.enumerated() {
            let word = Array(en.lowercased())
            var i = 0
            while i + word.count <= letters.count {
                if Array(letters[i..<(i + word.count)]) == word {
                    let beforeOK = i == 0 || !isAsciiLetter(letters[i - 1])
                    let afterOK = i + word.count == letters.count || !isAsciiLetter(letters[i + word.count])
                    if beforeOK && afterOK {
                        if englishBest == nil || i < englishBest!.offset { englishBest = (i, RegionList.prefectures[index]) }
                        break
                    }
                }
                i += 1
            }
        }
        return englishBest?.name
    }

    private static func isAsciiLetter(_ c: Character) -> Bool {
        guard let v = c.asciiValue else { return false }
        return (97...122).contains(v) || (65...90).contains(v)
    }
}
