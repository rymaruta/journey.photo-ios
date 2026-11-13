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
/// 2. 字は、当てる材料（`sameMaterial`）と別名が替わったときだけそろえ直す（`OfficialSpotIndex.Prepared`・`prepare`）
/// 3. 🔴 **そろえるのは主スレッドの外**（2026-11-13 判断）。Linux の Release で約 220ms、シミュレータはその約2倍かかり、
///    索引が届いたとき・別名が届いたときに画面が止まる。画面は `prepare` を `Task.detached` で呼び、
///    できた索引を `hits(spots:index:…)` に渡す。1字ごとの当てる処理は主スレッドに残す
///    （Linux の Release で1回 数 ms。結果は打った字と同じ描き直しで出したい）
///
/// **行は今の一覧から取る。** 詳細を重ねた（季節の案内が届いた）だけなら当てる材料は同じなので、索引は作り直さず、
/// 当たった位置で今の一覧の行を返す（案内の文が遅れない・2026-11-13 確かめ役の指摘）。
/// 材料が替わって作り直している間は、前の索引の行で当てる（節は消えない）。
///
/// 画面の `@State` に1つ持ち、body の中から呼ぶ（主スレッドだけ）
final class SearchSpotHits {
    /// 節に出す行と、まだ分からない（読み込み中）か
    struct Hits: Equatable {
        var rows: [OfficialSpot] = []
        /// 一覧は届いたが、そろえた索引がまだ（主スレッドの外で作っている）。
        /// **0件と扱わない**——「見つかりませんでした」と言わない（2026-11-13 確かめ役の指摘）
        var pending = false

        /// 0件と言ってよいか（読み込み中ではなく、本当に何も当たっていない）
        var isEmpty: Bool { rows.isEmpty && !pending }
    }

    private struct Key: Equatable {
        let query: String
        let filter: ShootingTime.Filter
    }

    private var spots: [OfficialSpot]?
    /// 下書きを落とした今の行（**下書きは出さない**——地図の一覧・ホームと同じ）
    private var published: [OfficialSpot] = []
    private var index: OfficialSpotIndex.Prepared?
    /// 索引の行と今の行の当てる材料が同じか（索引か一覧が替わったときだけ見直す）
    private var indexMatchesPublished = false
    private var key: Key?
    private var result: [OfficialSpot] = []

    /// 当てた（控えが使えなかった）回数（試験で見る）
    private(set) var computeCount = 0
    /// 今、索引・一覧を握っているか（試験で見る。節を出さない・語も絞り込みも無いときは手放す）
    var holdsIndex: Bool { index != nil || spots != nil }

    init() {}

    /// 索引を作るかの鍵（画面の `.task(id:)`）。`generation` は当てる材料（`sameMaterial`）か別名が替わったときだけ進む
    /// （詳細を重ねただけ・画面に戻っただけでは進まない）。`needed` は語があるか
    struct IndexNeed: Equatable {
        let generation: Int
        let needed: Bool
    }

    /// 索引を作るか（2026-11-13 確かめ役の指摘）。語があり、一覧があり、
    /// 今の世代の索引がまだ無いときだけ（同じ材料なら作り直さない）
    static func shouldBuild(_ need: IndexNeed, builtGeneration: Int?, hasSpots: Bool) -> Bool {
        need.needed && hasSpots && builtGeneration != need.generation
    }

    /// 探すで当てる相手の索引を作る（重い。**主スレッドの外で呼ぶ**）。下書きは落とす
    static func prepare(spots: [OfficialSpot], aliases: [String: [String]]) -> OfficialSpotIndex.Prepared {
        OfficialSpotIndex.Prepared(spots.filter { !$0.isDraft }, aliases: aliases)
    }

    /// 当てる材料（並び・slug・名前・英語名・読み・地域・下書きか）が同じか。
    /// 同じなら、そろえた索引は作り直さなくてよい（詳細を重ねただけ）
    static func sameMaterial(_ a: [OfficialSpot], _ b: [OfficialSpot]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { x, y in
            x.slug == y.slug && x.name == y.name && x.nameEn == y.nameEn && x.reading == y.reading
                && x.region == y.region && x.isDraft == y.isDraft
        }
    }

    /// 語に当たる撮影スポット（名前・読み・英語名・別名・都道府県・市区町村）。地図の検索と同じ当て方に、別名を足したもの。
    /// 季節・時間帯を選んでいるときは、その季節・時間帯の案内を持つ撮影地に絞る（`ShootingTime`）。
    /// **語が無くても出す**——「秋」だけ選べば、秋の案内のある撮影地が並ぶ（語が無いときは索引を使わない）。
    /// `showsSpots` が false（節を出さない範囲）なら空。語があって索引がまだなら `pending`
    func hits(spots: [OfficialSpot], index: OfficialSpotIndex.Prepared?, query: String,
              filter: ShootingTime.Filter, showsSpots: Bool) -> Hits {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard showsSpots, !q.isEmpty || !filter.isEmpty, !spots.isEmpty else {
            // 使わない間は、古い索引・一覧を握り続けない
            release()
            return Hits()
        }
        if self.spots != spots {
            self.spots = spots
            published = spots.filter { !$0.isDraft }
            key = nil
            indexMatchesPublished = self.index.map { Self.sameMaterial($0.spots, published) } ?? false
        }
        if q.isEmpty {
            // 語が無い（季節・時間帯だけ）なら、今の行を絞るだけ（索引は要らない）
            if self.index != nil { self.index = nil; key = nil }
        } else {
            guard let index else {
                self.index = nil
                key = nil
                return Hits(pending: true)
            }
            if index !== self.index {
                self.index = index
                indexMatchesPublished = Self.sameMaterial(index.spots, published)
                key = nil
            }
        }
        let key = Key(query: q, filter: filter)
        if key == self.key { return Hits(rows: result) }
        computeCount += 1
        let matched: [OfficialSpot]
        if let index = self.index {
            // 材料が同じなら今の行（詳細を重ねた後の行）で返す。違えば（作り直している間）索引の行で
            let rows = indexMatchesPublished ? published : index.spots
            matched = index.matchPositions(query: q).map { rows[$0] }
        } else {
            matched = published
        }
        result = ShootingTime.spots(matched, filter: filter)
        self.key = key
        return Hits(rows: result)
    }

    private func release() {
        spots = nil
        published = []
        index = nil
        indexMatchesPublished = false
        key = nil
        result = []
    }
}
