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

    /// 出してよい写真。作者とライセンスが揃っていて、https の画像だけ
    var photo: SpotImage? { image?.value }

    struct Region: Decodable, Equatable {
        let prefecture: String?
        let city: String?
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
