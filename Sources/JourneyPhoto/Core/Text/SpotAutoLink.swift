import Foundation

/// **写真を撮影スポットに自動で結ぶ**（2026-10-31 判断・owner 承認・journey.photo-ios#425）。
///
/// 決まりの本体は Web の `lib/utils/spotAutoLink.ts`。Web は静的な生成で結び、結果を小さな表
/// （写真 id → 撮影スポット id・`/app/data/spot-photo-links.json`）にして配る。iOS は**その表を読む**
/// （`SpotPhotoLinks`）——表示のときに写真を結ぶ決まりは Swift に写さない。
///
/// 写真から撮影スポットを引く順（Web と同じ）:
///   1. 写真の `spotId`（本人が選んだ紐づけ）
///   2. 無ければ表
///   3. ただし写真の `spotAuto` が `"off"`（本人が外した）なら、表にあっても結ばない
///
/// 投稿画面の候補（まだサーバーに無い写真）だけは表に載らないので、Web が配る索引
/// （`/app/data/spot-match.json`）と同じ突き合わせ（`SpotMatcher`）で選ぶ。写すのは**突き合わせだけ**
/// （約100行）で、索引を作る決まり（地名だけの別名・同名異所・公開済みだけ）は Web の索引に任せる。
/// 2026-10-31 判断: 写さずに済む作り（端末で JavaScript を動かす・サーバーに口を足す）は、
/// JavaScript の同梱と実行の口が要る・サーバーは触らない約束、のどちらかで取れなかった。
/// 写しが Web と同じ答えを出すことは、Web の決まりで作った答えの表（`Tests/Fixtures/spot-auto-link.json`・
/// 本番48枚と結ばない例の全部）で縛る（`SpotAutoLinkTests`）
enum SpotAutoLink {
    /// 本人が「違う場所なので外す」を押した印（写真の行の `spotAuto`）。Web の `SPOT_AUTO_OFF`
    static let off = "off"
    /// 写真と撮影スポットの位置の差の上限（km）。Web の `SPOT_AUTO_KM`
    static let maxKm = 5.0
    /// 写真の位置が地名から補ったもの（`geoApprox`）のときの上限（km）。Web の `SPOT_AUTO_APPROX_KM`
    static let approxMaxKm = 50.0

    /// 撮影スポットの頁の写真の節の注記（自動で結んだ写真を含むときだけ・Web の `SpotGuideClient` と同じ言葉）
    static var spotPageNote: String {
        L("撮影地の名前と位置から自動で結んだ写真を含みます。",
          "Includes photos linked automatically by place name and location.")
    }

    /// 本人が選んだ `spotId`（前後の空白を落とした・空なら nil）
    static func explicitSpotId(_ photo: Photo) -> String? {
        let id = (photo.spotId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }
}

// MARK: - 表（`/app/data/spot-photo-links.json`）

/// 自動で結んだ表と、この端末で本人が外した・戻した写真（サイトの作り直しまでの数分を埋める）。
struct SpotPhotoLinks: Equatable, Sendable {

    /// この端末で本人が変えた結び（`OfficialSpotService.noteSpotAuto`）。**サイトの作り直しで表と
    /// 写真の `spotAuto` が追いつくまで**、外した写真を出さない・戻した写真を出す
    enum Override: Equatable, Sendable {
        case off(spotId: String)
        case on(spotId: String)

        var spotId: String {
            switch self {
            case .off(let id), .on(let id): return id
            }
        }
    }

    /// 写真 id → 撮影スポット id（自動の結びだけ。`spotId` を持つ・外した・非公開の写真は入らない）
    let links: [String: String]
    var overrides: [String: Override] = [:]

    static let empty = SpotPhotoLinks(links: [:])

    /// 表の版。知らない版は読まない（使わない側に倒す＝`spotId` だけで引く）
    static let version = 1

    /// `{"v":1,"links":{"<写真 id>":"<撮影スポット id>"}}`。形が違えば nil。
    /// **読めない行だけを落とす**（1行の崩れで表ごと捨てない）
    static func decode(_ data: Data) -> SpotPhotoLinks? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["v"] as? NSNumber)?.intValue == version,
              let raw = object["links"] as? [String: Any] else { return nil }
        var links: [String: String] = [:]
        for (photoId, value) in raw {
            guard let spotId = value as? String, !photoId.isEmpty, !spotId.isEmpty else { continue }
            links[photoId] = spotId
        }
        return SpotPhotoLinks(links: links)
    }

    /// 本人が外したか（この端末で変えた分が先・無ければ写真の `spotAuto`）
    func isOff(_ photo: Photo) -> Bool {
        switch overrides[photo.id] {
        case .off: return true
        case .on: return false
        case nil: return photo.spotAutoMark == SpotAutoLink.off
        }
    }

    /// 写真の撮影スポット。**本人が選んだ `spotId` → 無ければ表**（外した写真は表を見ない）
    func spotId(for photo: Photo) -> String? {
        if let explicit = SpotAutoLink.explicitSpotId(photo) { return explicit }
        return autoSpotId(for: photo)
    }

    /// 自動で結んだ撮影スポット（`spotId` を持つ写真・外した写真は nil）
    func autoSpotId(for photo: Photo) -> String? {
        guard SpotAutoLink.explicitSpotId(photo) == nil, !isOff(photo) else { return nil }
        if case .on(let id) = overrides[photo.id] { return id }
        return links[photo.id]
    }

    /// 本人に「外す」「元に戻す」を出す先（外していても）。`rule` は表に無いとき（外した写真は
    /// 表に載らない）に決まりで求めた先（`SpotMatcher`）。`spotId` を持つ写真・非公開の写真は nil
    /// （Web の `page.tsx` の `rule` と同じ守り）
    func candidate(for photo: Photo, rule: String? = nil) -> String? {
        guard SpotAutoLink.explicitSpotId(photo) == nil, photo.published != false else { return nil }
        return overrides[photo.id]?.spotId ?? links[photo.id] ?? rule
    }

    /// 外した写真で、表にも、この端末で変えた分にも先が無い（決まりで求め直さないと名前が出せない）
    func needsRule(for photo: Photo) -> Bool {
        SpotAutoLink.explicitSpotId(photo) == nil && photo.published != false
            && overrides[photo.id] == nil && links[photo.id] == nil && photo.spotAutoMark == SpotAutoLink.off
    }

    /// 撮影スポットの写真（Web の `photosLinkedTo`）。並びは渡された順。何を渡すか（公開の一覧か）は
    /// 呼ぶ側のまま（今までの `spotId` の絞りと同じ）——表は公開の写真しか持たない
    static func photos(_ photos: [Photo], linkedTo spotId: String, links: SpotPhotoLinks) -> [Photo] {
        photos.filter { links.spotId(for: $0) == spotId }
    }

    func with(_ overrides: [String: Override]) -> SpotPhotoLinks {
        var copy = self
        copy.overrides = overrides
        return copy
    }
}

// MARK: - 索引（`/app/data/spot-match.json`）

/// 突き合わせに使う索引（Web の `SpotMatchIndex`）。公開済みの撮影スポットの、正規化した名前・使える別名・
/// 位置・県だけ。作るのは Web（`buildSpotMatchIndex`）で、地名だけの別名・同名異所はもう外してある
struct SpotMatchIndex: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        /// spotId
        let id: String
        /// 画面に出す正式名
        let name: String
        /// 正規化した正式名（3字未満・台帳で2件以上に当たる名前は空）
        let key: String
        /// 使える別名（正規化済み）
        let aliases: [String]
        let coords: Photo.Coords?
        /// 都道府県（日本の行だけ）
        let prefecture: String?
    }

    let rows: [Row]

    static let version = 1

    /// 形が違えば nil（自動では選ばない側に倒す）。`i`・`d`・`n` が文字でない行だけを落とす
    /// （Web の `parseSpotMatchIndex` と同じ）
    static func decode(_ data: Data) -> SpotMatchIndex? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["v"] as? NSNumber)?.intValue == version,
              let spots = object["spots"] as? [Any] else { return nil }
        let rows: [Row] = spots.compactMap { raw in
            guard let r = raw as? [String: Any], let id = r["i"] as? String, let name = r["d"] as? String,
                  let key = r["n"] as? String else { return nil }
            let aliases = (r["a"] as? [Any])?.compactMap { $0 as? String } ?? []
            var coords: Photo.Coords?
            if let c = r["c"] as? [Any], c.count == 2,
               let lat = (c[0] as? NSNumber)?.doubleValue, let lng = (c[1] as? NSNumber)?.doubleValue,
               lat.isFinite, lng.isFinite {
                coords = Photo.Coords(lat: lat, lng: lng)
            }
            return Row(id: id, name: name, key: key, aliases: aliases, coords: coords, prefecture: r["p"] as? String)
        }
        return SpotMatchIndex(rows: rows)
    }

    /// spotId → 画面に出す名前
    func name(of spotId: String) -> String? {
        rows.first { $0.id == spotId }?.name
    }
}

// MARK: - 突き合わせ（Web の `spotMatcher` の写し）

/// 撮影地・題・説明・位置から撮影スポットを1つ選ぶ。**Web の `spotMatcher(index).match` と同じ答えを出す。**
///
/// 文字は JavaScript と同じく **UTF-16 の単位**で扱う（`normalize("NFKC").toLowerCase()`・`indexOf`・
/// 前後の1字・`[\s]` の範囲まで）。`Character`（書記素）で数えると、絵文字や結合文字の前後で
/// 「語の切れ目」の判定が Web と割れる
struct SpotMatcher: Sendable {

    private struct Key: Sendable {
        let units: [UInt16]
        /// 撮影地の1項目と丸ごと同じときだけ当てる（短いカタカナ・短い英字）
        let itemOnly: Bool
        let latin: Bool
        let kataStart: Bool
        let kataEnd: Bool

        init?(_ text: String) {
            let units = Array(text.utf16)
            guard !units.isEmpty else { return nil }
            self.units = units
            itemOnly = Self.isShortKatakana(units) || Self.isShortLatin(units)
            latin = units.contains(where: SpotMatcher.isLatin)
            kataStart = SpotMatcher.isKatakana(units[0])
            kataEnd = SpotMatcher.isKatakana(units[units.count - 1])
        }

        /// Web の `SHORT_KATAKANA`（`/^[゠-ヿ]{1,4}$/`）
        static func isShortKatakana(_ u: [UInt16]) -> Bool {
            (1...4).contains(u.count) && u.allSatisfy { (0x30A0...0x30FF).contains($0) }
        }

        /// Web の `SHORT_LATIN`（`/^[a-z]{1,5}$/`）
        static func isShortLatin(_ u: [UInt16]) -> Bool {
            (1...5).contains(u.count) && u.allSatisfy { (0x61...0x7A).contains($0) }
        }
    }

    private struct Row: Sendable {
        let id: String
        let key: Key?
        let aliases: [Key]
        let coords: Photo.Coords?
        let prefecture: String?
    }

    private let rows: [Row]

    init(index: SpotMatchIndex) {
        rows = index.rows.map { row in
            Row(id: row.id, key: Key(row.key), aliases: row.aliases.compactMap(Key.init),
                coords: row.coords, prefecture: row.prefecture)
        }
    }

    /// 写真（題・説明は言語ごとの値をすべて見る）
    func match(_ photo: Photo) -> String? {
        match(location: photo.location, texts: Self.texts(photo), coords: photo.coords,
              geoApprox: photo.isGeoApprox)
    }

    /// - Parameters:
    ///   - texts: 題・説明（Web の `texts(title)`・`texts(description)` をつないだもの）
    ///   - geoApprox: 位置が地名から補ったもの（地域の代表点）
    func match(location: String?, texts: [String], coords: Photo.Coords?, geoApprox: Bool = false) -> String? {
        let location = location ?? ""
        let loc = Located(location)
        let all = Located(([location] + texts).joined(separator: "\n"))
        guard !all.norm.isEmpty else { return nil }
        let items = Self.locationItems(location)
        let prefs = Self.prefectures(in: location)
        let c = coords.flatMap { $0.lat.isFinite && $0.lng.isFinite ? $0 : nil }
        let limitKm = geoApprox ? SpotAutoLink.approxMaxKm : SpotAutoLink.maxKm
        func nameHit(_ k: Key) -> Bool { k.itemOnly ? items.contains(k.units) : all.hasWord(k) }
        func inLocation(_ k: Key) -> Bool { k.itemOnly ? items.contains(k.units) : loc.hasWord(k) }
        var found: String?
        for row in rows {
            let fromLocation = !loc.norm.isEmpty
                && ((row.key.map(inLocation) ?? false) || row.aliases.contains(where: inLocation))
            let hit = fromLocation || (row.key.map(nameHit) ?? false)
            guard hit else { continue }
            // 補った位置で、題・説明にだけ名前がある写真は 5km まで（Web の「最後の見直し」）
            let km = geoApprox && !fromLocation ? SpotAutoLink.maxKm : limitKm
            if let c, let rc = row.coords, TravelDistance.kilometers(from: c, to: rc) > km { continue }
            if c == nil || geoApprox, !prefs.isEmpty, !(row.prefecture.map(prefs.contains) ?? false) { continue }
            if let found, found != row.id { return nil } // 2つ以上は結ばない
            found = row.id
        }
        return found
    }

    // MARK: 文字

    /// 正規化した文字列と、その1単位ずつが正規化の前の何単位目か（Web の `locate`）
    private struct Located {
        let norm: [UInt16]
        let soft: [UInt16]
        let at: [Int]

        init(_ text: String) {
            let soft = SpotMatcher.soft(text)
            var norm: [UInt16] = []
            var at: [Int] = []
            norm.reserveCapacity(soft.count)
            for (i, u) in soft.enumerated() where !SpotMatcher.isDropped(u) {
                norm.append(u)
                at.append(i)
            }
            self.norm = norm
            self.soft = soft
            self.at = at
        }

        /// 鍵が文中に**語として**あるか（Web の `hasWord`）
        func hasWord(_ key: Key) -> Bool {
            let k = key.units
            guard !k.isEmpty, norm.count >= k.count else { return false }
            var i = 0
            while i <= norm.count - k.count {
                if norm[i] == k[0], Array(norm[i..<(i + k.count)]) == k {
                    let beforeAt = at[i] - 1
                    let afterAt = at[i + k.count - 1] + 1
                    let before: UInt16? = beforeAt >= 0 ? soft[beforeAt] : nil
                    let after: UInt16? = afterAt < soft.count ? soft[afterAt] : nil
                    let latinClash = key.latin && (before.map(SpotMatcher.isLatin) == true || after.map(SpotMatcher.isLatin) == true)
                    let kataStartClash = key.kataStart && before.map(SpotMatcher.isKatakana) == true
                    let kataEndClash = key.kataEnd && after.map(SpotMatcher.isKatakana) == true
                    if !latinClash && !kataStartClash && !kataEndClash { return true }
                }
                i += 1
            }
            return false
        }
    }

    /// `text.normalize("NFKC").toLowerCase()` の UTF-16
    private static func soft(_ text: String) -> [UInt16] {
        Array(text.precomposedStringWithCompatibilityMapping.lowercased().utf16)
    }

    /// Web の `normalizeSpotName`（判定にしか使わない）
    static func normalize(_ text: String) -> String {
        String(decoding: soft(text).filter { !isDropped($0) }, as: UTF16.self)
    }

    /// 正規化で落とす字（JavaScript の `\s` と、括弧・読点）
    private static func isDropped(_ u: UInt16) -> Bool {
        isJSWhitespace(u) || dropped.contains(u)
    }

    private static let dropped: Set<UInt16> = Set("()（）「」『』,、，".utf16)

    /// JavaScript の正規表現の `\s`（ES2015 の WhiteSpace と LineTerminator）
    private static func isJSWhitespace(_ u: UInt16) -> Bool {
        switch u {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// Web の `LATIN_CHAR`（`/[a-z0-9]/`）
    fileprivate static func isLatin(_ u: UInt16) -> Bool {
        (0x61...0x7A).contains(u) || (0x30...0x39).contains(u)
    }

    /// Web の `KATAKANA_CHAR`（`/[ァ-ヺー]/`。中黒「・」は区切り・長音「ー」は語の続き）
    fileprivate static func isKatakana(_ u: UInt16) -> Bool {
        (0x30A1...0x30FA).contains(u) || u == 0x30FC
    }

    /// 撮影地を「,」「、」「，」で区切った項目（正規化済み）。Web の `locationItems`
    private static func locationItems(_ location: String) -> Set<[UInt16]> {
        let nfkc = Array(location.precomposedStringWithCompatibilityMapping.utf16)
        var items = Set<[UInt16]>()
        var part: [UInt16] = []
        func flush() {
            let key = Array(normalize(String(decoding: part, as: UTF16.self)).utf16)
            if !key.isEmpty { items.insert(key) }
            part = []
        }
        let separators: Set<UInt16> = Set(",、，".utf16)
        for u in nfkc {
            if separators.contains(u) { flush() } else { part.append(u) }
        }
        flush()
        return items
    }

    /// 撮影地に書かれた都道府県（正式な綴りだけ）。Web の `prefecturesIn`
    private static func prefectures(in location: String) -> [String] {
        let s = location.precomposedStringWithCompatibilityMapping
        return RegionList.prefectures.filter { s.contains($0) }
    }

    /// 題・説明の文字（Web の `texts`）。言語ごとの値は ja・en・ほかの順に並べる。
    ///
    /// ⚠️ **既知の差（2026-10-31 確かめの指摘）**: Web は JSON に書かれた順（`Object.values`）につなぐが、
    /// `JSONDecoder` の辞書は並びを持たないので、ここでは ja・en・ほかの順に決めて並べる。答えが割れるのは、
    /// 名前が**2つの言語の値の境目をまたいで**当たるとき（題 `{ja: "東京", en: "タワー"}` のように、
    /// つないで初めて名前になる・正規化で改行が落ちる）だけで、JSON が ja より先に en を書いた写真に限る。
    /// api-user は ja → en の順で書く（`sanitize.ts` の `sanitizeTitle`・`sanitizeDescription`）。ただし DynamoDB と
    /// 静的な生成を通ったあとの並びは確かめていない。ja → en の境目をまたぐ例は
    /// 答えの表に入れてある（`SpotAutoLinkTests.testSwiftAnswersMatchWebFromPhotoRows`）
    static func texts(_ photo: Photo) -> [String] {
        func ordered<V>(_ map: [String: V]) -> [V] {
            let keys = map.keys.sorted { a, b in
                let rank = { (k: String) in k == "ja" ? 0 : k == "en" ? 1 : 2 }
                return rank(a) != rank(b) ? rank(a) < rank(b) : a < b
            }
            return keys.compactMap { map[$0] }
        }
        var out: [String] = []
        switch photo.title {
        case .plain(let text)?: out.append(text)
        case .byLocale(let map)?: out += ordered(map)
        case nil: break
        }
        switch photo.description {
        case .plain(let text)?: out.append(text)
        case .byLocale(let map)?: out += ordered(map).flatMap { $0 }
        case nil: break
        }
        return out
    }
}

// MARK: - 写真の詳細の知らせ（本人だけ）

/// 写真の詳細の「外す」の札の言葉（Web の `SpotAutoNotice.tsx` と同じ）
enum SpotAutoNoticeText {
    static var eyebrow: String { L("あなたにだけ表示", "Only you can see this") }

    static func title(spotName: String, off: Bool) -> String {
        off ? L("「\(spotName)」への自動の結びつけを外しています", "Automatic link to “\(spotName)” removed")
            : L("撮影スポット「\(spotName)」に結びました", "Linked to the photo spot “\(spotName)”")
    }

    static func body(off: Bool) -> String {
        off ? L("撮影スポットの頁には並びません。同じ場所なら元に戻せます。",
                "It won’t appear on the spot page. Restore it if this is the same place.")
            : L("撮影地の名前と写真の位置から、自動で結んでいます。違う場所なら外してください。",
                "Linked automatically by place name and location. Remove it if this is a different place.")
    }

    static func button(off: Bool) -> String {
        off ? L("元に戻す", "Restore") : L("違う場所なので外す", "Different place — remove")
    }

    /// 保存できたときの知らせ（`nowOff` は保存したあとの状態）
    static func saved(nowOff: Bool) -> String {
        nowOff ? L("外しました。撮影スポットの頁から外れるのは、サイトの更新が終わってからです",
                   "Removed. The spot page updates after the site is rebuilt.")
               : L("元に戻しました。サイトの更新が終わると、撮影スポットの頁に並びます",
                   "Restored. It will appear on the spot page after the site is rebuilt.")
    }

    static var failed: String {
        L("保存できませんでした。通信を確かめて、もう一度お試しください",
          "Couldn't save. Check your connection and try again.")
    }
}

/// 写真の詳細で、本人の「外す」「元に戻す」を出すかと、その中身（値で試せる形）
enum SpotAutoNotice {
    struct State: Equatable {
        let spotId: String
        let off: Bool
    }

    /// - Parameters:
    ///   - isMine: 撮った本人か
    ///   - links: 読み終えた表（読み終える前は nil＝出さない）
    ///   - rule: 外した写真で表に無いときに決まりで求めた先（`SpotMatcher`）
    ///   - pendingOff: いま送っている向き（先に見せる。失敗したら nil に戻す＝元の表示）
    static func state(photo: Photo, isMine: Bool, links: SpotPhotoLinks?, rule: String?,
                      pendingOff: Bool?) -> State? {
        guard isMine, let links, let spotId = links.candidate(for: photo, rule: rule) else { return nil }
        return State(spotId: spotId, off: pendingOff ?? links.isOff(photo))
    }

    /// 写真の詳細の「撮影スポット · ◯◯」の札（チップ）に出す撮影スポット。送っている間は送った向きで先に見せる。
    /// 表を読み終える前は `spotId` だけ
    static func chipSpotId(photo: Photo, links: SpotPhotoLinks?, pendingOff: Bool?, candidate: String?) -> String? {
        if let explicit = SpotAutoLink.explicitSpotId(photo) { return explicit }
        guard let links else { return nil }
        switch pendingOff {
        case true?: return nil
        case false?: return candidate
        case nil: return links.autoSpotId(for: photo)
        }
    }
}

// MARK: - 投稿画面の切り替え（Web の `spotUploadAuto.ts`）

/// 投稿画面で撮影スポットを自動で選ぶ（2026-10-31 判断・journey.photo-ios#425）。
///
/// 🔴 **自動の候補は投稿で `spotId` にしない。** 結ぶのは Web の静的な生成に任せ、決まりを1か所に保つ。
/// 書くのは本人が切り替えを切ったときの `spotAuto: "off"` だけ。**本人が触っていない写真には何も書かない**
/// （複数枚の投稿で、見ていない写真まで固い結びや外した印にしない）。撮影スポットの画面から来た投稿の
/// 明示の `spotId` は今までどおり（`UploadSpotTarget.spotIdToSend`）
enum SpotUploadAuto {

    static func title(spotName: String) -> String {
        L("撮影スポット「\(spotName)」に結ぶ", "Link to “\(spotName)”")
    }

    static func note(on: Bool) -> String {
        on ? L("撮影地の名前と写真の位置から、自動で選んであります。投稿のあと、撮影スポットの頁に並びます。ここで撮っていなければ外してください。",
               "Chosen automatically from the place name and photo location. It will appear on the spot page. Turn off if you didn’t take it here.")
           : L("撮影スポットには結ばずに投稿します。", "This photo won’t be linked to the spot.")
    }

    /// 投稿する写真の候補（撮影地・題・説明・写真の位置。Web の `autoUploadSpot` と同じく、位置は撮影時のもの）
    static func candidate(matcher: SpotMatcher?, location: String, title: String, caption: String,
                          coords: Photo.Coords?) -> String? {
        guard let matcher else { return nil }
        return matcher.match(location: location, texts: [title, caption], coords: coords)
    }

    /// 本人の決め（切り替え・撮影スポットの帯の「外す」）。**どの撮影スポットについて決めたか**も持つ
    struct Decision: Equatable, Sendable {
        /// 切り（結ばない）
        let off: Bool
        /// 決めたときの撮影スポット。nil は「どの候補にも効く」（形だけの受け口・ふだんは入っている）
        let spotId: String?
    }

    /// その写真の「切り」（Web の `autoOffFor`）。本人が決めた撮影スポットと今の候補が同じときだけ効く——
    /// 撮影地・題・位置が変わって**別の撮影スポットが候補になった写真には何も書かない**（`"off"` も書かない。
    /// 本人がその撮影スポットを見ていない・2026-10-31 確かめの指摘）。決めていない写真も nil
    static func offFor(_ decision: Decision?, candidate: String?) -> Bool? {
        guard let decision else { return nil }
        if let spotId = decision.spotId, spotId != candidate { return nil }
        return decision.off
    }

    /// 保存で送る外した印（Web の `uploadSpotFields`）。明示の `spotId` を送る写真・候補の無い写真・
    /// 本人が切っていない写真は nil（書かない）
    static func spotAutoToSend(explicitSpotId: String?, candidate: String?, off: Bool?) -> String? {
        guard explicitSpotId == nil, candidate != nil, off == true else { return nil }
        return SpotAutoLink.off
    }
}
