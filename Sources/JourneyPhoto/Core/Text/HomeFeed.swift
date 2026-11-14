import Foundation

/// ホームの写真の並び（タブの無い1本の並び・札 #595・2026-11-13 owner 決定）。
///
/// 以前は「おすすめ・フォロー中・新着」の3つを切り替えていた。切り替えをやめ、上から:
///
///     1. フォロー中の人の新しい写真 … ログインしていて、フォローがあり、まだ上に出していない新しいものだけ
///                                       （`followingFresh`・数は `followingMax`）
///     2. 選ばれた写真 → いいねの多い順 … 今までの「おすすめ」の中身（`recommended`）。横並び（PICKS）と
///                                       季節の撮影スポットの段もこの部分に残す（画面の側）
///     3. 新しく載った写真 … 今までの「新着」。**2 の間に混ぜる**（`latestEvery` 個ごとに1つ・`arrange`）
///
/// **同じ写真は2回出さない**（投稿の束の鍵 `PhotoGroups.groupKey` と写真の id の両方で落とす）。
///
/// 2026-11-13 判断（3 を「混ぜる」にした理由）: 2 の元は全件（`photos.json` と `GET /photos`）なので、新しい写真も
/// いいねの少ない順の終わりのほうに既に入っている。後ろに続けると、重複を落とした「新着」はほとんど残らず、
/// 載せたばかりの写真は全件の一番下まで送らないと出てこない（＝誰にも届かない）。新着は今までどおり `GET /feed` を
/// 30 枚ずつ（`PublicFeedService.pageSize`）読み、読めた分だけを混ぜる。**読めた新着を使い切った所で並びを切り**、
/// その下の目印が次のページを読む（`truncated`）。こうすると続きを読んでも、もう出ている所の順は動かない
/// （新しく足されるのは切った所より後ろだけ）。
///
/// 推薦の仕組み（口）は無い。並べ方は上の決まりだけで、画面には「おすすめ」の言葉も注釈も出さない
/// （推薦の仕組みがあるように見せない・指示書 5-2）。
enum HomeFeed {

    /// 1. の上限（投稿の束の数）。**5 = 写真の並びのひと回り**（大1→2→2・`EditorialLayout.rows`）。
    /// 2026-11-13 判断: 1画面ぶん（ひと回り）までにして、2 以降（選ばれた写真）が下に沈まないようにする。
    /// 残りの新しい写真も 3 の「新着」から並びに混ざる
    static let followingMax = 5
    /// 1. で1人から出す投稿の上限。1人がまとめて載せた日に、上を1人で埋めない（外した NEW の段と同じ 2）
    static let followingPerPerson = 2
    /// 3. を混ぜる間隔: **4 つめごとに1つ**（選ばれた写真・いいね順 3 つに新着 1 つ）。
    /// 2026-11-13 判断: ひと回り（5）と割り切れない 4 にして、新着が大きい1枚にも小さい2枚にも順に来るようにした。
    /// 1画面目（ひと回り）に新着が1つは入り、1ページ（30 枚）でおよそ 120 個ぶんの並びになる
    static let latestEvery = 4

    /// 季節の段の前に置く写真（束）の数。**大1→2→2 のひと回り**（`EditorialLayout.rows`: 大きい段のあと2枚の段が2つ）。
    /// ひと回りの切れ目で割るので、段の後ろの写真も大きい1枚から始まり、並びのリズムは変わらない
    static let seasonShelfAfter = 5

    /// 写真（束）の並びを、段の前（ひと回り）と後ろに割る
    static func splitForSeasonShelf<T>(_ items: [T]) -> (lead: [T], rest: [T]) {
        let count = min(seasonShelfAfter, items.count)
        return (Array(items.prefix(count)), Array(items.dropFirst(count)))
    }

    /// 2. 選ばれた写真（`featured`）を先に、残りはいいねの多い順（今までの「おすすめ」の並び）
    static func recommended(_ photos: [Photo]) -> [Photo] {
        let sorted = GallerySort.popular.apply(photos)
        return sorted.filter { $0.featured == true } + sorted.filter { $0.featured != true }
    }

    /// 1. フォロー中の人の新しい写真。
    ///
    /// - 未ログイン・フォロー 0 なら空
    /// - フォロー中の人の写真（`GalleryScope.following`・下書きを除く）のうち、自分の写真を除き、
    ///   **投稿日（`createdAt`）が `seen` より新しいもの**。`seen` が nil（まだ1度も上に出していない）なら全部が新しい
    /// - `alwaysNew` の人（この場で新しくフォローした人・「おすすめの人」から）の写真は、覚え（`seen`）に関係なく新しいとする。
    ///   覚えより古い写真しか無い人をフォローして頭へ送っても、上に何も出ない（押して何も起きない）を作らない
    /// - 新しい順。1人 `followingPerPerson` 投稿まで、全体で `followingMax` 投稿まで。投稿の写真はまとめて返す
    /// - ブロック・通報は呼ぶ側が先に落とす
    static func followingFresh(_ photos: [Photo], viewerId: String?, followingIds: Set<String>,
                               seen: String?, alwaysNew: Set<String> = []) -> [Photo] {
        guard let viewerId, !followingIds.isEmpty else { return [] }
        let theirs = GalleryScope.following.photos(photos, viewerId: viewerId, followingIds: followingIds)
            .filter { ($0.userId ?? $0.uploadedBy) != viewerId }
            .filter { photo in
                if let owner = photo.userId ?? photo.uploadedBy, alwaysNew.contains(owner) { return true }
                guard let seen else { return true }
                guard let created = photo.createdAt else { return false }
                return created > seen
            }
        var perPerson: [String: Int] = [:]
        var result: [Photo] = []
        var taken = 0
        for group in PhotoGroups.group(GallerySort.new.apply(theirs)) {
            guard taken < followingMax else { break }
            let owner = group.cover.userId ?? group.cover.uploadedBy ?? ""
            guard perPerson[owner, default: 0] < followingPerPerson else { continue }
            perPerson[owner, default: 0] += 1
            taken += 1
            result += group.photos
        }
        return result
    }

    /// 並べた結果
    struct Arranged: Equatable {
        /// 1. フォロー中の人の新しい写真（束ねる前の写真の並び）
        let following: [Photo]
        /// 2. と 3. を混ぜた並び（1. と `excluding` に出した写真は入らない）
        let main: [Photo]
        /// 読めた新着を使い切ったので、ここで切った（続きのページがある）。下の目印が次を読む
        let truncated: Bool
        /// `main` のうち 3.（新着）から入れた写真の id（UI テストが新着の1枚目を探す・`HomeFeedPageMemo.Rows.firstLatestTile`）
        var fromLatest: Set<String> = []
    }

    /// 1本の並びを作る（純粋な関数・同じ入力なら同じ答え）。
    ///
    /// - Parameters:
    ///   - following: 1.（`followingFresh` の答え）。いちばん上に、そのまま出す
    ///   - recommended: 2.（`recommended` の答え）
    ///   - latest: 3. 読めた新着（新しい順・`GET /feed` のページを足した並び）
    ///   - latestHasMore: 新着に続きのページがあるか
    ///   - excluding: ほかの所（選ばれた写真の横並び）に出した写真の id。並びには入れない
    static func arrange(following: [Photo], recommended: [Photo], latest: [Photo],
                        latestHasMore: Bool, excluding: Set<String> = []) -> Arranged {
        var placedKeys = Set<String>()
        var placedIds = Set<String>()
        var top: [Photo] = []
        for group in PhotoGroups.group(following) {
            top += place(group, keys: &placedKeys, ids: &placedIds)
        }
        // 横並びに出した写真は 2.・3. に入れない（1. が先・横並びの側は 1. の写真を落とす）
        placedIds.formUnion(excluding)

        let recGroups = PhotoGroups.group(recommended)
        let newGroups = PhotoGroups.group(latest)
        var recIndex = 0
        var newIndex = 0
        var main: [Photo] = []
        var slot = 0
        var truncated = false
        var fromLatest = Set<String>()

        /// 次のまだ出していない束を取る（出し済みは飛ばす）
        func next(_ groups: [PhotoGroups.Group], _ index: inout Int) -> [Photo]? {
            while index < groups.count {
                let group = groups[index]
                index += 1
                let fresh = place(group, keys: &placedKeys, ids: &placedIds)
                if !fresh.isEmpty { return fresh }
            }
            return nil
        }

        while true {
            slot += 1
            let wantsLatest = slot % latestEvery == 0
            if wantsLatest {
                if let photos = next(newGroups, &newIndex) {
                    main += photos
                    fromLatest.formUnion(photos.map(\.id))
                    continue
                }
                // 読めた新着を使い切った。続きがあるならここで切る（続きを読んでも上の順が動かない）
                if latestHasMore { truncated = true; break }
            }
            if let photos = next(recGroups, &recIndex) {
                main += photos
                continue
            }
            // 選ばれた写真・いいね順を出し切った後は、新着だけが続く
            if let photos = next(newGroups, &newIndex) {
                main += photos
                fromLatest.formUnion(photos.map(\.id))
                continue
            }
            truncated = latestHasMore
            break
        }
        return Arranged(following: top, main: main, truncated: truncated, fromLatest: fromLatest)
    }

    /// 束を出す。束の鍵か写真の id が出し済みなら、その分を落とす（何も残らなければ空）
    private static func place(_ group: PhotoGroups.Group, keys: inout Set<String>, ids: inout Set<String>) -> [Photo] {
        let key = PhotoGroups.groupKey(of: group.cover)
        guard keys.insert(key).inserted else { return [] }
        return group.photos.filter { ids.insert($0.id).inserted }
    }
}
