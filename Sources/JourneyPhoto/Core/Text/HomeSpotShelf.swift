import Foundation

/// ホームの「いまの季節のスポット」の段（2026-10-03・戦略ドキュメント「初回起動のあと、写真の少ない
/// ホームに着き『人がいない』印象になる」への直し。板 Main の「THIS SEASON · いまの季節のスポット」）。
///
/// 2026-10-03 判断: **場所の図鑑を主役にする。** 投稿が少ない時期でも、撮影スポットの索引と
/// 作例（Wikimedia Commons・`SpotSample`）で上の段が埋まる。押すと撮影スポットの画面
/// （`OfficialSpotView`）。
///
/// ## 何を出すか
///
/// - 候補は季節の札と同じ（`HomeTopCard.seasonGuides`: 公開済み・いまの季節の案内を持つ）。
///   **写真の有無では絞らない**——作例は本文にしか無く、取る前には分からない
/// - **週替わり**（owner・2026-09-30「ホームのスポットは週替わり」）。`spotId` の順に並べ、
///   週ごとに `count` 件ずつ先へ進める。**除く前に回す**——上の札が替わっても、残りの並びがずれない
/// - **都道府県で散らす**（板の注記「都道府県で散らす」）。1周目は同じ県（国外は国）を飛ばし、
///   足りなければ飛ばした行で埋める
/// - **上の札に出ているスポットと、今日の一問の選択肢（4つ）は除く**（`excluded`）。答えが
///   名前と写真つきで横に並ぶと答えが見える（`HomeTopCard.cards` と同じ理由）。外れの選択肢も
///   写真が並ぶと消去法の手がかりになるので、4つとも除く
///
/// ## 通信を抑える
///
/// 作例は**スポットごとの本文**（`/app/data/spots/<slug>.json`）にしか無い。索引（1,400件）の分を
/// 取りに行かず、**段に出す `count` 件だけ**本文を取る（`OfficialSpotService.fetchBody`・
/// サービスの控えあり）。画面が生きている間は取り直さない（画面の側）。写真は Commons の
/// **小さい縮小版**（`SpotSample.thumbnail(maxWidth:)`・500px）。本文が取れない・作例の無い場所は、
/// 索引に載っている代表写真（`OfficialSpot.photo`・通信は増えない）を使い、それも無ければ真鍮のピンだけ
/// （板の注記「写真の無い行は真鍮のピンだけ」）。
///
/// 🔴 **作例は利用者の投稿ではない。** 段の注記で「撮影者はこのアプリの利用者ではない」と言い
/// （docs/spot-samples-commons.md の決まり）、1枚ごとに題・作者・ライセンス・出典を写真のすぐ下に出す。
/// 切り抜かない（縦横比のまま）。人数・投稿数のような数は出さない
enum HomeSpotShelf {

    /// 段に出す数＝本文を取りに行く数の上限
    static let count = 5
    /// 札の写真に使う縮小版の幅（px）。札の写真は幅 240pt
    static let thumbnailWidth = 500

    struct Entry: Identifiable, Equatable {
        let spot: OfficialSpot
        /// いまの季節の案内（台帳の文のまま）
        let guide: String
        var id: String { spot.spotId }

        /// 札の右上の地域（県・国外は国）。板は「岡山」のように短く出す
        var regionLabel: String? {
            let value = (spot.region?.prefecture ?? spot.region?.country)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty ?? true) ? nil : value
        }
    }

    struct Shelf: Equatable {
        /// `spring`〜`winter`
        let season: String
        let entries: [Entry]
    }

    /// 今週の段。候補が無ければ nil（**空き地を作らない**——段ごと出さない）
    static func shelf(today: Date, spots: [OfficialSpot], excluding: Set<String> = [],
                      limit: Int = count) -> Shelf? {
        let guides = HomeTopCard.seasonGuides(today: today, spots: spots)
        let rows = guides.rows
        guard !rows.isEmpty, limit > 0 else { return nil }
        // 週ごとに `limit` 件ずつ先へ（除く前に回す）
        let week = HomeTopCard.weekNumber(today)
        let start = (((week * limit) % rows.count) + rows.count) % rows.count
        let rotated = (rows[start...] + rows[..<start]).filter { !excluding.contains($0.spot.spotId) }
        var picked: [(spot: OfficialSpot, guide: String)] = []
        var skipped: [(spot: OfficialSpot, guide: String)] = []
        var regions = Set<String>()
        for row in rotated where picked.count < limit {
            let key = Entry(spot: row.spot, guide: row.guide).regionLabel
            // 地域の分からない行は散らす対象にしない（どれとも重ならない）
            if let key, !regions.insert(key).inserted {
                skipped.append(row)
            } else {
                picked.append(row)
            }
        }
        picked += skipped.prefix(max(limit - picked.count, 0))
        guard !picked.isEmpty else { return nil }
        return Shelf(season: guides.season, entries: picked.map { Entry(spot: $0.spot, guide: $0.guide) })
    }

    /// 段から除くスポット: 上の札（季節・行きたい場所）に出ているものと、今日の一問の選択肢
    static func excluded(by choices: [HomeTopCard.Choice], quizSpots: [String]) -> Set<String> {
        var ids = Set<String>()
        for choice in choices {
            switch choice {
            case .inSeason(let spot, _, _), .wishlistSeason(let spot, _, _): ids.insert(spot.spotId)
            default: break
            }
        }
        ids.formUnion(quizSpots.filter { !$0.isEmpty })
        return ids
    }

    // MARK: - 札の写真

    /// 札に出す写真と、その出典
    enum Picture: Equatable {
        /// 本文の作例（Wikimedia Commons）
        case sample(SpotSample)
        /// 索引の代表写真
        case cover(SpotImage)

        /// 表示に使う URL（作例は小さい縮小版）
        var url: URL {
            switch self {
            case .sample(let sample): return sample.thumbnail(maxWidth: HomeSpotShelf.thumbnailWidth)
            case .cover(let image): return image.url
            }
        }

        /// 写真のすぐ下の出典の1行（作例は「題 / 写真: 作者 / ライセンス / Wikimedia Commons」）
        var credit: String {
            switch self {
            case .sample(let sample): return sample.credit
            case .cover(let image): return image.credit
            }
        }

        var linkedCredit: AttributedString {
            switch self {
            case .sample(let sample): return sample.linkedCredit
            case .cover(let image): return image.linkedCredit
            }
        }

        var creditLinks: [CreditLink] {
            switch self {
            case .sample(let sample): return sample.creditLinks
            case .cover(let image): return image.creditLinks
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .sample(let sample): return sample.accessibilityLabel
            case .cover(let image): return L("撮影スポットの写真（撮影: \(image.author)）", "Spot photo by \(image.author)")
            }
        }
    }

    /// 札の写真。**作例が先**（その場所で撮られた写真）、無ければ索引の代表写真、どちらも無ければ nil。
    /// `broken` は読み込めなかった写真の URL（その1枚を出典ごと隠し、次の候補へ）
    static func picture(for spot: OfficialSpot, body: SpotBody?, broken: Set<URL> = []) -> Picture? {
        if let body {
            for sample in body.samples {
                let picture = Picture.sample(sample)
                if !broken.contains(picture.url) { return picture }
            }
        }
        if let cover = spot.photo, !broken.contains(cover.url) { return .cover(cover) }
        return nil
    }

    // MARK: - 言葉

    /// 眉ラベル（「THIS SEASON · 秋」）。知らない季節は季節を付けない
    static func eyebrow(_ season: String) -> String {
        guard let label = SpotBodyText.seasonLabel(season) else { return "THIS SEASON" }
        return "THIS SEASON · \(label)"
    }

    /// 眉ラベルの読み上げ（英字の眉は日本語で読ませる）
    static func eyebrowSpoken(_ season: String) -> String {
        guard let label = SpotBodyText.seasonLabel(season) else { return L("いまの季節", "This season") }
        return L("いまの季節・\(label)", "This season · \(label)")
    }

    static var heading: String { L("いまの季節のスポット", "Spots for this season") }

    /// 段の注記。**作例の撮影者はこのアプリの利用者ではない**と添える（docs/spot-samples-commons.md）
    static var note: String {
        L("写真は Wikimedia Commons の作例です。撮影者はこのアプリの利用者ではありません。",
          "Photos are examples from Wikimedia Commons. The photographers are not members of this app.")
    }
}
