import Foundation

/// 同じ投稿としてまとめて出す束（モック6 の「1/10」・モック8 の「1〜10枚」）。
///
/// **サーバーの行は1枚ずつのまま。** 束ねるのは見せ方だけで、
/// 個別ページもサイトマップも変わらない——写真1枚＝1ページが
/// このサイトの検索での面積（`photo-gallery/CLAUDE.md`）なので、
/// 1行にまとめると**出せるページが減る**。
///
/// だから `groupId` は「同じときに出した写真」の印にすぎない。
enum PhotoGroups {

    /// 1つのカードに出す束。**1枚でも束**（呼ぶ側で場合分けしない）
    struct Group: Identifiable, Equatable {
        /// 先頭の写真の id（`groupId` が無い写真も1枚の束になるので、
        /// 束の id は写真の id から採る——同じ束が2つ並ばない）
        let id: String
        let photos: [Photo]

        var cover: Photo { photos[0] }
        var count: Int { photos.count }
        var isMultiple: Bool { photos.count > 1 }
    }

    /// 一覧を束に畳む。
    ///
    /// **並びは壊さない。** 束は「その束の先頭が出てきた場所」に置く
    /// ——新しい順に並んだ一覧を畳んだとき、束が急に先頭へ飛ばない。
    ///
    /// **束の中は選んだ順（`createdAt` の古い順）。** 一覧の並び（人気順など）の
    /// ままだと、10枚の投稿の表紙と「1/10」の順が並べ替えのたびに変わった。
    ///
    /// **持ち主の違う写真は同じ束にしない。** `groupId` は画面が作る値なので、
    /// 別の人が同じ値を送れば他人の写真が自分の投稿に混ざりうる。
    static func group(_ photos: [Photo]) -> [Group] {
        var order: [String] = []
        var buckets: [String: [Photo]] = [:]
        for photo in photos {
            let key = groupKey(of: photo)
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(photo)
        }
        return order.compactMap { key in
            guard let items = buckets[key].map(inPostOrder), let first = items.first else { return nil }
            return Group(id: first.id, photos: items)
        }
    }

    /// 束ねる鍵。**`groupId` と持ち主の組**。
    /// どちらかが無ければ、その写真だけの束にする
    /// **1つの投稿に2枚以上入っている写真の id**（モック2-7 の格子の印）。
    ///
    /// 印は「束ねた印を持っている」だけでは出せない——**兄弟が同じ並びに
    /// 居るときだけ**。1枚しか見えていないのに「複数枚」と出すと、
    /// 押しても1枚しか出てこない。
    static func multiPhotoIds(_ photos: [Photo]) -> Set<String> {
        var byKey: [String: [String]] = [:]
        for photo in photos {
            let key = groupKey(of: photo)
            // 束ねていない写真の鍵は写真ごとに違うので、ここには積まれない
            byKey[key, default: []].append(photo.id)
        }
        return Set(byKey.values.filter { $0.count > 1 }.flatMap { $0 })
    }

    static func groupKey(of photo: Photo) -> String {
        guard let groupId = photo.groupId?.trimmingCharacters(in: .whitespaces),
              !groupId.isEmpty,
              let owner = photo.userId ?? photo.uploadedBy, !owner.isEmpty else {
            return "single#\(photo.id)"
        }
        return "group#\(owner)#\(groupId)"
    }

    /// その写真と同じ束の写真（選んだ順・`inPostOrder`）。
    /// **1枚しか無ければその1枚だけ**
    static func siblings(of photo: Photo, in photos: [Photo]) -> [Photo] {
        let key = groupKey(of: photo)
        let found = inPostOrder(photos.filter { groupKey(of: $0) == key })
        return found.isEmpty ? [photo] : found
    }

    /// 一覧の並びはそのまま、**束の写真どうしだけ選んだ順に入れ替える**。
    /// 束の写真が居た場所（何番目か）は変えない——束ねていない写真は動かない。
    /// 詳細の上の束（`siblings`）と大きく見る画面で、送る向きをそろえるため
    static func inPostOrderWithinGroups(_ photos: [Photo]) -> [Photo] {
        var slots: [String: [Int]] = [:]
        for (i, photo) in photos.enumerated() {
            slots[groupKey(of: photo), default: []].append(i)
        }
        var result = photos
        for indices in slots.values where indices.count > 1 {
            for (slot, photo) in zip(indices, inPostOrder(indices.map { photos[$0] })) {
                result[slot] = photo
            }
        }
        return result
    }

    /// 束の中の並び。**`createdAt` の古い順**（投稿は選んだ順に1枚ずつ保存される）。
    /// 同じ時刻・時刻の無い写真は元の並びのまま（時刻の無いものは後ろ）
    static func inPostOrder(_ photos: [Photo]) -> [Photo] {
        photos.enumerated().sorted { a, b in
            switch (a.element.createdAt, b.element.createdAt) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }
}
