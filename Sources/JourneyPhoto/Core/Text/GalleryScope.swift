import Foundation

/// トップに出す範囲。Web の `?scope=`（`lib/hooks/useGallery.ts`）と対。
///
/// owner の指示（2026-09-19）:「この画面は、タブで切り替えて、自分の写真か
/// フォロー中の人の写真みれるようにしたい」「デフォルトは自分のみがいい」。
enum GalleryScope: String, CaseIterable, Identifiable {
    case mine, following, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mine: return L("自分", "Mine")
        case .following: return L("フォロー中", "Following")
        case .all: return L("すべて", "All")
        }
    }

    /// その範囲の写真。
    ///
    /// - `mine` … 自分の写真だけ。**ログインしていなければ絞らない**
    ///   （絞れないので絞らない——Web の `useGallery` と同じ）
    /// - `following` … **フォローしている人の写真だけ**。自分のは入らない
    ///   （自分はフォローできないので集合に自分の id は無い。
    ///   自分の投稿はマイページが持ち場——`lib/utils/timeline.ts`）
    /// - `all` … 未ログインと同じ
    ///
    /// 公開されているものだけを出す（`published != false`）。
    func photos(_ photos: [Photo], viewerId: String?, followingIds: Set<String>) -> [Photo] {
        let visible = photos.filter { $0.published != false }
        switch self {
        case .all:
            return visible
        case .mine:
            guard let viewerId else { return visible }
            return visible.filter { ($0.userId ?? $0.uploadedBy) == viewerId }
        case .following:
            guard viewerId != nil else { return visible }
            return visible.filter { photo in
                guard let owner = photo.userId ?? photo.uploadedBy else { return false }
                return followingIds.contains(owner)
            }
        }
    }
}
