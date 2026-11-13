import Foundation

/// 探すの「撮影スポット」の節に出す行（`SearchView.spotHits`）を**控える**（2026-11-13 判断・札 #590「探すの検索が重い」）。
///
/// Mac の UI テスト（回 1219・シミュレータ）では、1字打つごとに次のようになっていた:
/// - body が 3〜4 回評価される
/// - そのたびに `spotHits` が 9〜12 回呼ばれ、毎回全件（3,899 件）の字をそろえて当てていた。合計 3.8〜7.3 秒、1回で最大 0.8 秒
/// - 画面が最大 2.7〜5.2 秒止まった
///
/// 直し方は次の3つ:
/// 1. **語・絞り込み・索引が同じ間は、1回だけ当てて控える**（body の中で何度呼ばれても、当てるのは1回）
/// 2. 字は、索引（と別名）ごとに1回だけそろえる（`OfficialSpotIndex.Prepared`・`prepare`）
/// 3. 🔴 **そろえるのは主スレッドの外**（2026-11-13 判断）。Linux の Release で約 220ms、シミュレータはその約2倍かかり、
///    索引が届いたとき・別名が届いたときに画面が止まる。画面は `prepare` を `Task.detached` で呼び、
///    できた索引を `hits(index:…)` に渡す。作り直している間は前の索引で当てる（節は消えない）。
///    1字ごとの当てる処理は主スレッドに残す（Linux の Release で1回 数 ms。結果は打った字と同じ描き直しで出したい）
///
/// 画面の `@State` に1つ持ち、body の中から呼ぶ（主スレッドだけ）
final class SearchSpotHits {
    private struct Key: Equatable {
        let query: String
        let filter: ShootingTime.Filter
    }

    private var index: OfficialSpotIndex.Prepared?
    private var key: Key?
    private var result: [OfficialSpot] = []

    /// 当てた（控えが使えなかった）回数（試験で見る）
    private(set) var computeCount = 0

    init() {}

    /// 索引を作り直す鍵（画面の `.task(id:)`）。索引か別名が替わったら作り直す。
    /// 同じ入れ物を渡し直したときは、配列・辞書の `==` が中身を比べずにすぐ返る
    struct Source: Equatable {
        let spots: [OfficialSpot]
        let aliases: [String: [String]]
    }

    /// 探すで当てる相手の索引を作る（重い。**主スレッドの外で呼ぶ**）。
    /// **下書きは出さない**（地図の一覧・ホームと同じ。「撮影地ガイド」と名乗らせない）
    static func prepare(spots: [OfficialSpot], aliases: [String: [String]]) -> OfficialSpotIndex.Prepared {
        OfficialSpotIndex.Prepared(spots.filter { !$0.isDraft }, aliases: aliases)
    }

    /// 語に当たる撮影スポット（名前・読み・英語名・別名・都道府県・市区町村）。地図の検索と同じ当て方に、別名を足したもの。
    /// 季節・時間帯を選んでいるときは、その季節・時間帯の案内を持つ撮影地に絞る（`ShootingTime`）。
    /// **語が無くても出す**——「秋」だけ選べば、秋の案内のある撮影地が並ぶ。
    /// `showsSpots` が false（節を出さない範囲）か、索引がまだ無ければ空
    func hits(index: OfficialSpotIndex.Prepared?, query: String,
              filter: ShootingTime.Filter, showsSpots: Bool) -> [OfficialSpot] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard showsSpots, !q.isEmpty || !filter.isEmpty, let index else { return [] }
        if index !== self.index {
            self.index = index
            key = nil
        }
        let key = Key(query: q, filter: filter)
        if key == self.key { return result }
        computeCount += 1
        let matched = q.isEmpty ? index.spots : index.matches(query: q)
        result = ShootingTime.spots(matched, filter: filter)
        self.key = key
        return result
    }
}
