import Foundation

/// 撮影スポットの台帳の1件——Web の `content/spots.json` から
/// アプリ向けに薄く落とした**索引**（`app/data/spots.json`）の形。
///
/// **台帳そのものではない。** 見どころ・季節・アクセスといった本文は
/// 索引に載らない（v1 のアプリは索引しか読まない）。載っているのは
/// 地図に置く・名前で探す・画面の頭を出すのに要るぶんだけ。
///
/// 🔴 **`stage` が `published` でない行は「運営の下書き」。** 2026-09-25 時点で
/// 台帳の全件（1,417件）が `review`——機械が1日で書いた下書きで、人が
/// 1件も確かめていない。画面では**「公式」と呼ばない**（`SpotScreen.eyebrow` /
/// `reviewNotice`）。Swift の型名に `Official` と付いているのは Web の
/// 「公式撮影地ガイド」の入れ物を指す名前で、**利用者に見える語ではない**。
///
/// 写真との紐づけは `Photo.spotId` だけ（`DerivedSpot` の撮影地の集まりとは
/// 別の軸）。知らない項目は読み飛ばし、壊れた行は `LenientOfficialSpotList` が
/// 1件だけ落とす。
struct OfficialSpot: Decodable, Identifiable, Equatable {
    /// 台帳の鍵（`sp_` + 12桁の16進）。名前から作らない
    let spotId: String
    /// URL に出る綴り（`/spots/<slug>`）。「行きたい」の鍵もこれから作る（`SavedSpotKey`）
    let slug: String
    let name: String
    let nameEn: String?
    /// 読み（ひらがな）。名前で探すときに当てる
    let reading: String?
    let region: Region?
    /// 公開してよい座標（写真と同じ約1km精度）。**無い行は地図に置けない**
    let coords: Photo.Coords?
    let category: String?
    /// 概要。**書かれたものだけ**（自動生成しない）
    let summary: String?
    /// `review`（運営未確認の下書き）か `published`（公開済み＝人が確かめたか、AI 照合）。
    /// **`published` だけで「運営が確かめた」と言わない**——本文の印（`SpotBody.check`）で出し分ける
    let stage: String
    /// 下書きを書いた日（`YYYY-MM-DD`）。**確認日ではない**
    let draftedAt: String?
    /// 人が確かめた日。`published` の行だけが持つ
    let verifiedAt: String?
    /// スポットの写真（Wikimedia Commons・2026-09-26〜）。**owner が写真を確かめた
    /// 公開済みの行だけ**が持つ。壊れていても行ごと落とさない（`LenientSpotImage`）
    let image: LenientSpotImage?
    /// 季節の案内（2026-09-29〜 索引に載る。Web の `spotFeed.ts`）。**公開済みの行だけ**が持つ。
    /// 壊れた1件・知らない季節・空の文は落とし、**行ごとは落とさない**（`LenientSeasonalGuide`）。
    /// `var` で既定 nil なのは、載っていない古い索引・控えも読めるようにするため
    var seasonalGuide: LenientSeasonalGuide? = nil
    /// 時間帯の案内（夜明け・朝・日中・夕方の斜光・日没後・夜）。
    ///
    /// 🔴 **2026-10-03 時点のサーバーの索引には載っていない**（`lib/data/spotFeed.ts` が
    /// 「載せない」に時間帯を挙げている。本文 `/app/data/spots/<slug>.json` にだけある）。
    /// 探すの「時間帯で絞る」が撮影地にも効くよう、**本文・台帳と同じ名前・同じ形**
    /// （`[{time, text}]`）で読む口だけ先に置く——載るまでは常に空で、時間帯で絞ると
    /// 撮影地の節は出ない（`ShootingTime.spots`）。2026-10-03 判断
    var timeOfDayGuide: LenientTimeOfDayGuide? = nil
    /// その場所の時刻帯（IANA 名・例 "America/New_York"）。**台帳に書いた行だけ**サイトが載せる
    /// （`lib/data/spotFeed.ts`・2026-10-07）。光の時刻はこれを国より先に使う（`SunTimes.timeZone(named:country:)`）。
    /// アメリカ・カナダ・オーストラリアのように時刻帯が複数ある国は、これが無いと時計を決められない。
    /// 古い索引には無い。読めない名前は国の表に落とす
    var timeZone: String? = nil

    // MARK: 分けた置き場の索引（`/app/data/spot-feed/index.json`・2026-10-07）

    /// 索引の「季節の案内がある季節」（**種類だけ・文は詳細**）。索引の鍵は `seasons`
    var seasonKinds: LenientStringList? = nil
    /// 索引の「時間帯の案内がある時間帯」（種類だけ）。索引の鍵は `times`
    var timeKinds: LenientStringList? = nil
    /// 索引の「写真が詳細にある」
    var hasImage: LenientFlag? = nil
    /// 索引の別名（`spot-search.json` と同じもの）。古い置き場の行には無い
    var aliases: LenientStringList? = nil
    /// 詳細の区分（`/app/data/spot-feed/<shard>.json`）。**サービスが付ける**（JSON の鍵ではない）
    var shard: String? = nil
    /// **索引だけで読み、まだ詳細を重ねていない行。** 写真・概要・季節/時間帯の文・時刻帯が無い。
    /// 要る画面は `OfficialSpotService.withDetails` で詳細を重ねる（サービスが付ける）
    var isIndexOnly: Bool = false

    private enum CodingKeys: String, CodingKey {
        case spotId, slug, name, nameEn, reading, region, coords, category, summary, stage,
             draftedAt, verifiedAt, image, seasonalGuide, timeOfDayGuide, timeZone, hasImage, aliases
        case seasonKinds = "seasons"
        case timeKinds = "times"
    }

    /// 季節の案内がある季節（台帳の綴り）。**絞り込み・候補選びはこちらを使う**——
    /// 索引だけの行でも答えられる（文は `seasons`、詳細を重ねてから）
    var seasonKeys: [String] {
        isIndexOnly ? (seasonKinds?.value ?? []).filter { SpotBodyText.seasonOrder.contains($0) } : seasons.map(\.season)
    }

    /// 時間帯の案内がある時間帯（台帳の綴り）。`seasonKeys` と同じ理由
    var timeKeys: [String] {
        isIndexOnly ? (timeKinds?.value ?? []).filter { SpotBodyText.timeOrder.contains($0) } : times.map(\.time)
    }

    /// 写真があるか。**候補選びはこちらを使う**（索引だけの行は写真そのものを持たない）
    var hasPhoto: Bool {
        isIndexOnly ? hasImage?.value == true : photo != nil
    }

    /// 索引の行に詳細の行を重ねる。**詳細は同じ `spotId` のときだけ**使い、索引の印（区分・種類・別名）は残す
    func merged(with detail: OfficialSpot) -> OfficialSpot {
        guard detail.spotId == spotId else { return self }
        var row = detail
        row.shard = shard
        row.seasonKinds = seasonKinds
        row.timeKinds = timeKinds
        row.hasImage = hasImage
        row.aliases = aliases ?? detail.aliases
        row.isIndexOnly = false
        return row
    }

    /// 出してよい写真。作者とライセンスが揃っていて、https の画像だけ
    var photo: SpotImage? { image?.value }

    /// 出してよい季節の案内（`SpotBody` の本文と同じ決まりで落としたもの）
    var seasons: [SpotBody.Seasonal] { seasonalGuide?.value ?? [] }

    /// 出してよい時間帯の案内（索引に載っていなければ空・`timeOfDayGuide` の注記）
    var times: [SpotBody.TimeOfDay] { timeOfDayGuide?.value ?? [] }

    struct Region: Decodable, Equatable {
        let prefecture: String?
        let city: String?
        /// 国名（日本語表記・例「フランス」）。**日本の外の行だけ**サイトが載せる
        /// （`lib/data/spotFeed.ts`・2026-09-29）。古い索引には無い
        var country: String? = nil
    }

    var id: String { spotId }

    /// **確かめたと言えるのは `published` だけ。** 知らない値も下書きに倒す
    var isDraft: Bool { stage != "published" }

    /// 「[都道府県] · [市区町村]」。どちらも無ければ nil（空の行を置かない）
    var regionLabel: String? {
        let parts = [region?.prefecture, region?.city]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// スポットの写真。**作者とライセンスは必ず一緒に出す**（CC BY・CC BY-SA の条件）
struct SpotImage: Equatable {
    let url: URL
    let author: String
    let license: String
    /// 出典のページ（Commons のファイルのページ）
    let pageUrl: URL?
    /// ライセンスの文面（Web と同じ欄名 `licenseUrl`）。CC BY・CC BY-SA は
    /// 作者・**ライセンスの URI**・出典の表示が条件。パブリックドメインなどは無い
    var licenseUrl: URL? = nil

    /// 出典の1行の文字（画面は `linkedCredit` でこの文字にリンクを付けて出す）
    var credit: String { "\(creditAuthor) / \(license)" }

    /// 出典の1行の前半（「写真: 作者」）
    var creditAuthor: String { L("写真: \(author)", "Photo: \(author)") }

    /// 出典の1行を、**文字は `credit` と同じまま**、部分にリンクを付けて返す:
    /// 「写真: 作者」→ 出典のページ（`pageUrl`）・「ライセンス」→ 文面（`licenseUrl`）。
    ///
    /// Web（`SpotGuideClient`）は「写真: 作者 / ライセンス（文面へ）/ Wikimedia Commons
    /// （出典のページへ）」で、出典へのリンクは末尾の「Wikimedia Commons」に付く。
    /// アプリは**画面の文字を変えない**ため末尾の語は足さず、出典のページへの
    /// リンクを作者の側に付ける（リンク先の2つは Web と同じ）
    var linkedCredit: AttributedString {
        var head = AttributedString(creditAuthor)
        head.link = pageUrl
        var tail = AttributedString(license)
        tail.link = licenseUrl
        return head + AttributedString(" / ") + tail
    }

    /// 出典の1行から開ける先（並びは文字の並びと同じ: 出典のページ → ライセンスの文面）。
    /// URL の無いものは除く（両方無ければ空＝押せない1行・`CreditLink` の注記）
    var creditLinks: [CreditLink] {
        (pageUrl.map { [CreditLink.commonsPage($0)] } ?? [])
            + (licenseUrl.map { [CreditLink.license(license, url: $0)] } ?? [])
    }
}

/// 写真の欄を**決して投げずに**読む入れ物。写真が壊れていても、スポットの行は
/// 落とさない（写真はおまけで、場所の情報が本体）。条件を満たさなければ `value` は nil:
///   - 画像の URL が https
///   - 作者とライセンスが空でない（表示が使う条件。欠けていれば出さない）
struct LenientSpotImage: Decodable, Equatable {
    let value: SpotImage?

    private struct Raw: Decodable {
        let url: String?
        let author: String?
        let license: String?
        let pageUrl: String?
        let licenseUrl: String?
    }

    init(from decoder: Decoder) throws {
        guard let raw = try? Raw(from: decoder) else { value = nil; return }
        let author = raw.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let license = raw.license?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let s = raw.url, let url = URL(string: s), url.scheme == "https",
              !author.isEmpty, !license.isEmpty else { value = nil; return }
        let page = Self.httpsURL(raw.pageUrl)
        value = SpotImage(url: url, author: author, license: license, pageUrl: page,
                          licenseUrl: Self.httpsURL(raw.licenseUrl))
    }

    /// 出典のページ・ライセンスの文面の URL。**http は https に上げる**（Web の
    /// `spotCoverImage` と同じ扱い。台帳には `http://creativecommons.org/…` が141件ある）。
    /// 空・https/http 以外は nil（押せないリンクを出さない）
    static func httpsURL(_ raw: String?) -> URL? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst("http://".count) }
        guard let url = URL(string: s), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

/// 文字の一覧を**決して投げずに**読む入れ物（索引の季節・時間帯の種類と別名）。
/// 文字でない・空の項目は落とす。行ごとは落とさない（`LenientSpotImage` と同じ理由）
struct LenientStringList: Decodable, Equatable {
    let value: [String]

    init(_ value: [String]) { self.value = value }

    init(from decoder: Decoder) throws {
        let rows = (try? [Lenient<String>](from: decoder)) ?? []
        value = rows.compactMap(\.value)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// 真偽を**決して投げずに**読む入れ物（索引の `hasImage`）。真偽でなければ false
struct LenientFlag: Decodable, Equatable {
    let value: Bool

    init(_ value: Bool) { self.value = value }

    init(from decoder: Decoder) throws {
        value = (try? Bool(from: decoder)) ?? false
    }
}

/// 季節の案内の欄を**決して投げずに**読む入れ物（`LenientSpotImage` と同じ理由）。
/// 本文（`SpotBody.seasonalGuide`）と同じく、知らない季節・空の文の項目は落とす
struct LenientSeasonalGuide: Decodable, Equatable {
    let value: [SpotBody.Seasonal]

    init(_ value: [SpotBody.Seasonal]) { self.value = value }

    init(from decoder: Decoder) throws {
        let rows = (try? [Lenient<SpotBody.Seasonal>](from: decoder)) ?? []
        value = rows.compactMap(\.value).filter {
            SpotBodyText.seasonOrder.contains($0.season)
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// 時間帯の案内の欄を**決して投げずに**読む入れ物（`LenientSeasonalGuide` と同じ理由・同じ形）。
/// 本文（`SpotBody.timeOfDayGuide`）と同じく、知らない時間帯・空の文の項目は落とす
struct LenientTimeOfDayGuide: Decodable, Equatable {
    let value: [SpotBody.TimeOfDay]

    init(_ value: [SpotBody.TimeOfDay]) { self.value = value }

    init(from decoder: Decoder) throws {
        let rows = (try? [Lenient<SpotBody.TimeOfDay>](from: decoder)) ?? []
        value = rows.compactMap(\.value).filter {
            SpotBodyText.timeOrder.contains($0.time)
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// 1件ずつ復号して、**読めなかった行だけを落とす**入れ物
/// （`LenientPhotoList` と同じ理由・同じ形）。
///
/// **同じ `spotId` の2行目以降も落とす（先勝ち）。** 画面は `spotId` を
/// `Identifiable` の鍵に並べる（近くの撮影スポットの `ForEach(id: \.spot.id)`）
/// ので、重なると同じ札が2つ並ぶ。落とした数は `dropped` に入れる。
///
/// 加えて、**鍵になる3つ（`spotId`・`slug`・`name`）が空の行も落とす**。
/// 型は合っていても、空の `slug` は「行きたい」の鍵を `SPOT-` だけにし、
/// 空の名前は札に何も出さない——Web 側の門（`reviewBlockers`）が塞いでいる
/// 形だが、索引を読む側でも受け止める。
struct LenientOfficialSpotList: Decodable {

    let spots: [OfficialSpot]
    /// 落とした行の数。**黙って捨てない**ために数えておく
    let dropped: Int

    init(from decoder: Decoder) throws {
        let rows = try [Row](from: decoder)
        var seen = Set<String>()
        spots = rows.compactMap(\.spot).filter { seen.insert($0.spotId).inserted }
        dropped = rows.count - spots.count
    }

    private struct Row: Decodable {
        let spot: OfficialSpot?
        init(from decoder: Decoder) throws {
            guard let decoded = try? OfficialSpot(from: decoder) else {
                spot = nil
                return
            }
            let keys = [decoded.spotId, decoded.slug, decoded.name]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            spot = keys.allSatisfy { !$0.isEmpty } ? decoded : nil
        }
    }
}
