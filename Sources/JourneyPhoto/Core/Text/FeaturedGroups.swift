import Foundation

/// owner が手で選んだ「おすすめ」を、カテゴリごとにまとめる。
///
/// **Web の `lib/utils/featured.ts` の写し。** あちらは owner の要望
/// （「写真いちらんもいいけど、カテゴリごとのおすすめとかもほしい」）で
/// 入ったもので、トップの一覧の上に出る。アプリには**丸ごと無かった**
/// ——`featured` の印を読んでもいなかったので、owner が選んでも
/// アプリでは何も変わらなかった。
enum FeaturedGroups {

    /// 1つのカテゴリに出す最大枚数。多すぎるとトップが一覧の焼き直しになる
    static let perCategory = 6
    /// 出すカテゴリの最大数。トップが縦に伸びすぎないように
    static let groupsMax = 4

    struct Group: Identifiable, Equatable {
        /// カテゴリの値（集約ページの鍵）
        let id: String
        /// 画面に出す名前
        let label: String
        let photos: [Photo]
    }

    /// - **公開ぶんだけ。** 印が付いていても非公開なら出さない
    /// - **カテゴリを持たない写真は出さない**（「その他」の塊を作らない）
    /// - 並びは新しい順。**塊は多い順**、同数なら名前順で毎回同じ並びにする
    static func groups(from photos: [Photo]) -> [Group] {
        var byCategory: [String: [Photo]] = [:]
        var order: [String] = []
        for photo in photos {
            guard photo.featured == true, photo.published != false else { continue }
            guard let category = photo.category?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !category.isEmpty else { continue }
            let key = category.lowercased()
            if byCategory[key] == nil { order.append(key) }
            byCategory[key, default: []].append(photo)
        }

        return byCategory
            .map { key, list in
                Group(id: list.first?.category ?? key,
                      label: Labels.Category.name(list.first?.category ?? key),
                      photos: Array(GallerySort.new.apply(list).prefix(perCategory)))
            }
            .sorted {
                if $0.photos.count != $1.photos.count { return $0.photos.count > $1.photos.count }
                return $0.id < $1.id
            }
            .prefix(groupsMax)
            .map { $0 }
    }
}
