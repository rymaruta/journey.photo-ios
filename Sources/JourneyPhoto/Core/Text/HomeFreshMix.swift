import Foundation

/// **おすすめに新しい投稿を混ぜる**（札 #537 案1・2026-11-11 判断）。
///
/// おすすめは「owner が選んだ写真 → いいねの多い順」（`HomeFeed.arrange`）。本番では選んだ写真が0枚・
/// 52枚中39枚がいいね0なので、**投稿したばかりの写真（いいね0）は1月の写真の後ろ、14〜17番目に沈んでいた**
/// （2026-11-11 に `photos.json` を同じ決まりで並べて数えた）。投稿しても見てもらえず、反応が返らない。
///
/// 決まり（**Web の `lib/utils/homeFeed.ts` の `mixFresh` と同じ。** 試験は同じ入力と答えで両方を縛る）:
/// 1. 並べる単位は**投稿**（`PhotoGroups.groupKey`＝`groupId` と持ち主の組。無ければ写真1枚）。
///    ホームは同じ投稿の写真を1枚の札に束ねるので、枠は札で数える
/// 2. 投稿から 72 時間以内（いちばん新しい写真の `createdAt` で見る）の投稿を「新しい投稿」とし、新しい順に並べる
/// 3. 先頭 10 枠のうち **2・5・8 番目**（`slots`）に、まだ出ていない新しい投稿を入れる。ほかの枠と 11 番目から後ろは
///    今までの並び。新しい投稿が今までの並びで先に来ていれば、そこに出る（枠を使わない）
/// 4. `createdAt` は時刻とゾーンのある ISO 8601 だけ読む（日付だけ・読めない値は「新しい投稿」にしない）
enum HomeFreshMix {

    /// 「新しい投稿」とみなす長さ（72時間）
    static let window: TimeInterval = 72 * 60 * 60
    /// 新しい投稿を入れる枠（0 から数える。画面の 2・5・8 番目）。大1→2→2 のひと回りに1つ以上入る
    static let slots: Set<Int> = [1, 4, 7]
    /// 混ぜる範囲（先頭 10 枠）
    static let span = 10

    /// 72 時間以内に投稿された写真か
    static func isFresh(_ photo: Photo, now: Date) -> Bool {
        guard let created = photo.createdAt, let date = NotificationGroups.parse(created) else { return false }
        return now.timeIntervalSince(date) < window
    }

    /// `ordered`（今までのおすすめの並び）に新しい投稿を混ぜる。写真の数と中身は変えない（並びだけ）
    static func mix(_ ordered: [Photo], now: Date) -> [Photo] {
        // 投稿ごとの写真（今までの並びのまま）と、投稿が最初に出てくる順
        var order: [String] = []
        var members: [String: [Photo]] = [:]
        for photo in ordered {
            let key = PhotoGroups.groupKey(of: photo)
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(photo)
        }
        // 新しい投稿（新しい順。同じ時刻は鍵の昇順）
        let freshKeys: [String] = order.compactMap { key -> (String, Date)? in
            let newest = members[key, default: []]
                .compactMap { isFresh($0, now: now) ? $0.createdAt.flatMap(NotificationGroups.parse) : nil }
                .max()
            return newest.map { (key, $0) }
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        .map(\.0)
        guard !freshKeys.isEmpty else { return ordered }

        var used = Set<String>()
        var result: [String] = []
        var base = order.makeIterator()
        var fresh = freshKeys.makeIterator()
        func next(_ iterator: inout IndexingIterator<[String]>) -> String? {
            while let key = iterator.next() {
                if !used.contains(key) { return key }
            }
            return nil
        }
        while result.count < order.count {
            let index = result.count
            let picked: String?
            if index < span, slots.contains(index), let key = next(&fresh) {
                picked = key
            } else {
                picked = next(&base)
            }
            guard let key = picked else { break }
            used.insert(key)
            result.append(key)
        }
        return result.flatMap { members[$0, default: []] }
    }

    /// **はじめての投稿**の写真の id（札 #537 案1）。持ち主ごとに、公開の写真でいちばん古い投稿が
    /// 72 時間以内なら、その投稿の写真全部。ホームの札に「はじめての投稿」と出し、最初の1枚に反応が返りやすくする。
    ///
    /// 見るのは公開の一覧（`photos.json`）だけ。前に非公開で上げていた人は、公開の1枚目を「はじめて」と数える。
    ///
    /// 🔴 **持ち主の写真に `createdAt` の読めない1枚があれば、その人には印を付けない**（安全側・札 #537 の確かめ役・2026-11-11）。
    /// 読めない写真のほうが古いかもしれず、前から載せている人に「はじめて」と付けてしまう（Web と同じ）
    static func firstPostPhotoIds(_ photos: [Photo], now: Date) -> Set<String> {
        // 持ち主ごとの、いちばん古い投稿の写真（`createdAt` が読めるものだけ）
        var oldest: [String: (date: Date, photo: Photo)] = [:]
        var unreadable = Set<String>()
        for photo in photos {
            guard let owner = photo.userId ?? photo.uploadedBy, !owner.isEmpty else { continue }
            guard let created = photo.createdAt, let date = NotificationGroups.parse(created) else {
                unreadable.insert(owner)
                continue
            }
            if let current = oldest[owner],
               current.date < date || (current.date == date && current.photo.id <= photo.id) { continue }
            oldest[owner] = (date, photo)
        }
        let firstKeys = Set(oldest.filter { !unreadable.contains($0.key) && isFresh($0.value.photo, now: now) }
            .map { PhotoGroups.groupKey(of: $0.value.photo) })
        guard !firstKeys.isEmpty else { return [] }
        return Set(photos.filter { firstKeys.contains(PhotoGroups.groupKey(of: $0)) }.map(\.id))
    }
}
