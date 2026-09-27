import Foundation

/// この端末で最近選んだ曲（「曲を選ぶ」の欄が空のときに出す）。
///
/// **鍵はアカウントごとに分ける**（`FavoritesStore` と同じ理由——同じ端末の
/// 別の人に前の人の選曲が並ばないように）。
///
/// 画面が開くたびに読み、選んだときに書くだけなので `ObservableObject` に
/// しない（配る `EnvironmentObject` を増やさない）。
struct RecentSongsStore {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let sharedKey = "journey-photo-recent-songs"

    private func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return Self.sharedKey }
        return "\(Self.sharedKey):\(userId)"
    }

    /// 読めない・壊れているときは空（**曲をでっち上げない**）
    func songs(userId: String?) -> [Photo.Song] {
        guard let data = defaults.data(forKey: key(for: userId)),
              let songs = try? JSONDecoder().decode([Photo.Song].self, from: data)
        else { return [] }
        return SongPickerText.unique(songs)
    }

    /// 退会した人の控えを消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: key(for: userId))
    }

    /// 選んだ曲を覚える。戻り値は覚えたあとの並び
    @discardableResult
    func remember(_ song: Photo.Song, userId: String?) -> [Photo.Song] {
        let next = SongPickerText.remembering(song, in: songs(userId: userId))
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: key(for: userId))
        }
        return next
    }
}
