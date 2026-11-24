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

    /// 友達の行きたい場所の札の鍵（写真、フォロー、行きたい場所の鍵、日。索引と印は書き換えの番号）。
    /// 2026-11-23 判断（札 #710 の確かめ役の指摘）: body のたびに UserDefaults の JSON を読み、全部の写真を突き合わせていた。
    /// 日で控えるので、7日を過ぎた写真が札から外れるのは翌日の描き直しから（1日に1枚の決まりと同じ区切り）
    struct FriendWishKey: Equatable {
        let photos: [Photo]
        let following: Set<String>
        let me: String
        let keys: Set<String>
        let day: String
        let spotsRevision: Int
        /// 印（「この知らせは出さない」）を書き換えた番号
        let revision: Int
    }

    /// 自分の写真から決まる2枚の鍵（2026-11-24・札 #594）。写真・開いた印・今日（端末の暦日）と時刻帯
    struct PhotoCardsKey: Equatable {
        let myPhotos: [Photo]
        let openedBookDays: Set<String>
        let today: Date?
        let timeZone: TimeZone
    }

    private let pool = DerivedMemo<Int, SpotSwipe.CoverPool>()
    private let photo = DerivedMemo<PhotoCardsKey, HomeTopCard.PhotoCards?>()
    private let posted = DerivedMemo<[Photo], [LibraryTrips.PostedShot]>()
    private let friendWish = DerivedMemo<FriendWishKey, FriendWish.Hit?>()
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

    /// 友達の行きたい場所の今日の1枚（鍵が変わったときだけ計算する）
    func friendWishHit(_ key: FriendWishKey, _ make: () -> FriendWish.Hit?) -> FriendWish.Hit? {
        friendWish.value(for: key, make)
    }

    /// 自分の写真から決まる2枚（一冊ができた・1年前）。写真・開いた印・今日が変わったときだけ計算する（2026-11-24・札 #594）。
    /// 今日が決まらない（暦が作れない）回は nil（`HomeTopCard.cards` が自分で作る）
    func photoCards(_ key: PhotoCardsKey) -> HomeTopCard.PhotoCards? {
        photo.value(for: key) {
            key.today.map { HomeTopCard.photoCards(today: $0, myPhotos: key.myPhotos, openedBookDays: key.openedBookDays,
                                                   timeZone: key.timeZone) }
        }
    }

    /// 投稿した写真の日と位置（現像前の旅の札の材料・`LibraryTrips.postedShots`）。写真が変わったときだけ作る（2026-11-24・札 #594）。
    /// 写真ごとに日を読み `String(format:)` で整えるので、body のたびに全部の写真で作り直していた
    func postedShots(_ myPhotos: [Photo]) -> [LibraryTrips.PostedShot] {
        posted.value(for: myPhotos) { LibraryTrips.postedShots(of: myPhotos) }
    }

    /// 計算した回数（テスト用）
    var photoCardsComputes: Int { photo.computeCount }
    var postedShotsComputes: Int { posted.computeCount }
    var poolBuilds: Int { pool.computeCount }
    var friendWishComputes: Int { friendWish.computeCount }
    var shelfComputes: Int { shelf.computeCount }
}
