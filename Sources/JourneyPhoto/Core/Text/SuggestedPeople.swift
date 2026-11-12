import Foundation

/// **ホームの「フォロー中」が空のときの「おすすめの人」**（資料「SNS をもっと SNS に」④・1.1.83・2026-11-12）。
///
/// 誰もフォローしていない（またはフォローした人の写真がまだ無い）人に、その場で写真のある人を並べる。
/// 今は「探す」へ移って名前を打たないとフォローできなかった（押す回数 4＋文字 → 1）。
///
/// 2026-11-12 判断: **サーバーの新しい口は作らない。** ホームが既に読んでいる公開の写真（`photos.json` の全件・
/// `GalleryViewModel.allPhotosForTheme`）を持ち主ごとに束ね、**いちばん新しい投稿の順**に並べる。投稿した人は
/// 今は3人なので、選ぶ仕組みは要らない（人が数百に増えたら、人の検索の全表 Scan を替える相談と一緒に考え直す）。
///
/// 並べない人: 自分・もうフォローしている人・ブロックした人（写真は呼ぶ側が `ModerationSnapshot.visible` で落とす）。
/// 公開範囲を絞った写真・非公開は並べない（公開の一覧に載るのは全体に公開だけだが、念のため見る）。
/// 名前の無い人も並べる（`Labels.Common.unnamedUser`・写真がある人は押せば人のページで分かる）。
enum SuggestedPeople {

    /// 並べる人の上限（1画面目に収まる数より少し多く）
    static let limit = 6
    /// 1人に添える写真（名前より先に写真で選べるように・資料の模型の「写真3枚」）
    static let photosPerPerson = 3

    struct Person: Identifiable, Equatable {
        let userId: String
        let name: String
        /// 公開の写真の数（「41 枚」）
        let count: Int
        /// いちばん新しい写真の撮影地（無ければ nil・「最近 金沢」）
        let latestLocation: String?
        /// 新しい順に最大3枚
        let photos: [Photo]
        var id: String { userId }

        static func == (lhs: Person, rhs: Person) -> Bool {
            lhs.userId == rhs.userId && lhs.name == rhs.name && lhs.count == rhs.count
                && lhs.latestLocation == rhs.latestLocation && lhs.photos.map(\.id) == rhs.photos.map(\.id)
        }
    }

    /// 並べる人を決める。
    /// - Parameters:
    ///   - photos: 公開の写真（ブロック・通報は呼ぶ側が落としたもの）
    ///   - viewerId: 見ている人（自分は並べない）
    ///   - following: もうフォローしている人（並べない）
    static func pick(_ photos: [Photo], viewerId: String?, following: Set<String>,
                     limit: Int = limit) -> [Person] {
        var byOwner: [String: [Photo]] = [:]
        var order: [String] = []
        for photo in photos where isPublicToEveryone(photo) {
            guard let owner = (photo.userId ?? photo.uploadedBy)?.trimmingCharacters(in: .whitespaces),
                  !owner.isEmpty, owner != viewerId, !following.contains(owner) else { continue }
            if byOwner[owner] == nil { order.append(owner) }
            byOwner[owner, default: []].append(photo)
        }
        let people: [Person] = order.compactMap { owner in
            guard let owned = byOwner[owner] else { return nil }
            let newest = owned.sorted { postedKey($0) > postedKey($1) }
            let lead = newest.first
            let location = lead?.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = newest.lazy.compactMap { $0.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            return Person(userId: owner,
                          name: name ?? Labels.Common.unnamedUser,
                          count: owned.count,
                          latestLocation: (location?.isEmpty ?? true) ? nil : location,
                          photos: Array(newest.prefix(photosPerPerson)))
        }
        // いちばん新しい投稿の順（同じなら写真の多い順・次に id で決める＝描くたびに並びが揺れない）
        let sorted = people.sorted { a, b in
            let ka = a.photos.first.map(postedKey) ?? "", kb = b.photos.first.map(postedKey) ?? ""
            if ka != kb { return ka > kb }
            if a.count != b.count { return a.count > b.count }
            return a.userId < b.userId
        }
        return Array(sorted.prefix(max(0, limit)))
    }

    /// 新しい順の鍵（投稿日。無ければ撮影日）。ISO 8601 の文字列なので文字の順で比べられる
    static func postedKey(_ photo: Photo) -> String {
        photo.createdAt ?? photo.date ?? ""
    }

    /// 全体に公開の写真か（公開範囲を絞った・非公開は並べない）
    static func isPublicToEveryone(_ photo: Photo) -> Bool {
        guard photo.published != false else { return false }
        let audience = (photo.audience ?? "").trimmingCharacters(in: .whitespaces)
        return audience.isEmpty || audience == "everyone"
    }

    /// 行の2行目（「41 枚 · 最近 金沢」）
    static func detailLine(_ person: Person) -> String {
        let count = L("\(person.count) 枚", "\(person.count) photo\(person.count == 1 ? "" : "s")")
        guard let place = person.latestLocation else { return count }
        return count + " · " + L("最近 \(place)", "Recently \(place)")
    }

    // MARK: 言葉（資料の模型どおり）

    static var title: String { L("まず、写真の好きな人を", "Start with people whose photos you like") }
    static var message: String {
        L("フォローすると、新しい写真がここに並びます。", "Follow them and their new photos will appear here.")
    }
    static var eyebrow: String { L("おすすめの人", "Suggested people") }
    static var follow: String { L("フォロー", "Follow") }
    static var following: String { L("フォロー中", "Following") }
    static var seeFeed: String { L("フォロー中の写真を見る", "See photos from people you follow") }

    /// 「フォロー中の写真を見る」を出すか。**この場で1人でもフォローしたら**出す
    static func showsSeeFeed(followedHere: Set<String>) -> Bool { !followedHere.isEmpty }
}
