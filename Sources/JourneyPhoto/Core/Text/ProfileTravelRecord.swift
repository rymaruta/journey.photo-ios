import Foundation

/// プロフィールの「旅の記録」の中身。**マイページと人のページで同じ作り方**（2026-10-16 owner
/// 「他人のプロフィールを見たときも、旅の記録などの表示を見られるようにしたい」）。
///
/// 数え方は `TravelDistance`・`TravelRoute`・`TripBook.shelfTrips` のまま。ここは
/// **どの写真から作るか**だけを決める:
///
/// - **マイページ**: 自分の写真すべて（`myPhotos()`・下書きも入る）。今までどおり
/// - **人のページ**: 2026-10-16 判断——**その人の公開写真だけ**（`PhotoTrip.isPublic`:
///   下書きでなく、公開範囲を絞っていない）。人のページの写真は公開一覧（`gallery.fetchPhotos`）から
///   選り分けたもので、見ている人がフォロワーならフォロワー限定・親しい友達の写真も混ざる
///   （`RestrictedFeed.merge`）。それを数に入れると、写真の格子に出ている限定の写真の撮影地が
///   「旅の記録」という**その人の公の実績**に入り、見る人によって数が変わる。Web の人のページ
///   （`UserProfileClient.tsx` の `footprint`）も公開の写真（静的 JSON）だけで数えている。
///   **ブロックの関係なら何も作らない**。自分専用の口（`/user/photos`・`/user/badges` の進み具合・
///   `/user/spots`）と、その人の端末にしか無いもの（すれちがい帳など）は使わない
enum ProfileTravelRecord {

    /// 旅の記録の数（`TravelRecordView` に渡すもの）
    struct Summary: Equatable {
        /// 写真をつないだ距離（km）
        let kilometers: Double
        /// 訪れた国・地域（初めて訪れた順）
        let countries: [String]
        /// 線の点（距離と同じ写真・同じ順）
        let coordinates: [Photo.Coords]
        /// 一番古い写真の年
        let firstYear: Int?

        init(photos: [Photo]) {
            kilometers = TravelDistance.total(of: photos)
            countries = TravelRoute.countriesInOrder(photos)
            coordinates = TravelRoute.coordinates(of: photos)
            firstYear = TravelRoute.firstYear(of: photos)
        }

        /// **0 のものは出さない**（マイページの決まり）。国も距離も無ければ節ごと出さない
        /// （板 UserProfile F33「無ければ節ごと出さず、灰色の空き地も置かない」）
        var isEmpty: Bool { countries.isEmpty && !(kilometers > 0) }
    }

    /// 人のページで旅の記録を作ってよい写真（2026-10-16 判断・上の注記）。
    /// - Parameter blocked: 見ている人がこの人をブロックしている。**何も返さない**
    static func othersPhotos(_ photos: [Photo], blocked: Bool) -> [Photo] {
        guard !blocked else { return [] }
        return photos.filter(PhotoTrip.isPublic)
    }

    /// 人のページの旅の記録の数
    static func othersSummary(_ photos: [Photo], blocked: Bool) -> Summary {
        Summary(photos: othersPhotos(photos, blocked: blocked))
    }

    /// 人のページの旅の一冊（公開写真だけを、マイページの棚と同じ規則で束ねる）
    static func othersTrips(_ photos: [Photo], blocked: Bool,
                            timeZone: TimeZone = .current) -> [TripBook.Trip] {
        TripBook.shelfTrips(from: othersPhotos(photos, blocked: blocked), timeZone: timeZone)
    }

    // MARK: - 数え方の説明（押すと出る）

    /// 国・地域の数え方。**本人の文は今までのまま**（撮影地に国名を足す手立てまで言う）。
    /// 人のページは公開写真だけを数えると言い、本人にしかできない手立ては言わない
    static func countriesNote(isMine: Bool) -> String {
        if isMine {
            return L("撮影地に国・地域の名前が書かれている写真だけを数えています。地名から国を推測はしません。撮影地に国名を足すと、この数もサイトの地名ページも増えます。",
                     "Counts only photos whose location text names a country or region. We don't guess a country from a place name. Adding the country to your location text raises this number.")
        }
        return L("公開されている写真のうち、撮影地に国・地域の名前が書かれている写真だけを数えています。地名から国を推測はしません。",
                 "Counts only public photos whose location text names a country or region. We don't guess a country from a place name.")
    }

    /// 距離の数え方。**「旅した距離」とだけ書かない**——実際に歩いた・乗った距離だと読まれる（指示書 8-3）
    static func distanceNote(isMine: Bool) -> String {
        if isMine {
            return L("撮影地の分かる写真を、古い順に直線で結んだ合計です。実際に歩いた・乗った距離ではありません（道のりではなく直線で、撮っていない区間は飛び、座標は約1kmに丸めてあります）。",
                     "The straight-line total between photos that have coordinates, oldest first. Not the distance you actually travelled.")
        }
        return L("撮影地の分かる公開写真を、古い順に直線で結んだ合計です。実際に歩いた・乗った距離ではありません（道のりではなく直線で、撮っていない区間は飛び、座標は約1kmに丸めてあります）。",
                 "The straight-line total between public photos that have coordinates, oldest first. Not the distance actually travelled.")
    }
}
