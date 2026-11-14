import Foundation

/// ホームの上の札（`HomeTopCardView`）の重い計算の控え（2026-11-14 判断・札 #594「アプリ全体を軽くする」）。
///
/// **数（Mac run 1238・`testUsageSurveyProbe`）**: 札の body は、ホームを送る・タブを替える・別のタブにいる間にも
/// 評価し直され（`chg.HomeTopCardView.@self`・8 段で計 70 回）、そのたびに
/// - 札の並び（`home.topCard.choices`）70 回・合計 8,324ms（うち撮影スポットの索引の並べ替え `SpotSwipe.cover`）
/// - 季節の段（`home.topCard.visibleShelf`）77 回・合計 830ms
/// - 詳細を取りに行く場所（`home.topCard.detailNeeds`）77 回・合計 1,074ms
///
/// を主スレッドで計算していた。材料が同じなら答えも同じなので、**材料が変わったときだけ計算し直す**:
/// - 写真の候補の並び: 索引の書き換え（`spotsRevision`）が変わったとき
/// - 季節の段と、詳細を取りに行く場所: 今日・索引の書き換え・札の並び・今日の一問・一問の決着が変わったとき
///
/// 札の並びそのもの（旅行プラン・写真・行きたい場所などで決まる）は控えない（材料が多く、取り違えると札が古いまま残る）。
/// 重かった並べ替えは写真の候補の並びの控えで消える
final class HomeTopCardMemo {

    /// 季節の段と詳細の鍵（`HomeSpotShelf.visibleShelf` の材料。索引そのものの代わりに書き換えの番号）
    struct ShelfKey: Equatable {
        let today: Date?
        let spotsRevision: Int
        let choices: [HomeTopCard.Choice]
        let quiz: DailyQuiz?
        let quizSettled: Bool
    }

    private let pool = DerivedMemo<Int, SpotSwipe.CoverPool>()
    private let shelf = DerivedMemo<ShelfKey, HomeSpotShelf.Shelf?>()
    private let needs = DerivedMemo<ShelfKey, [OfficialSpot]>()

    init() {}

    /// 写真の候補の並び（索引の書き換えの番号が変わったときだけ作る）
    func coverPool(spots: [OfficialSpot], revision: Int) -> SpotSwipe.CoverPool {
        pool.value(for: revision) { SpotSwipe.CoverPool(spots: spots) }
    }

    /// 季節の段（鍵が変わったときだけ計算する）
    func visibleShelf(_ key: ShelfKey, _ make: () -> HomeSpotShelf.Shelf?) -> HomeSpotShelf.Shelf? {
        shelf.value(for: key, make)
    }

    /// 詳細を取りに行く場所（鍵が変わったときだけ計算する）
    func detailNeeds(_ key: ShelfKey, _ make: () -> [OfficialSpot]) -> [OfficialSpot] {
        needs.value(for: key, make)
    }

    /// 計算した回数（テスト用）
    var poolBuilds: Int { pool.computeCount }
    var shelfComputes: Int { shelf.computeCount }
    var needsComputes: Int { needs.computeCount }
}
