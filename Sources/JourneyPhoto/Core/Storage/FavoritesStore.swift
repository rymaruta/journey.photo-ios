import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine

/// お気に入り（端末に残るハート）。
///
/// **鍵はアカウントごとに分ける。** Web 版は共有キー1本だった頃、
/// A のハート一覧が同じ端末の B にそのまま見え、いいね判定の
/// フォールバックを通じて B の初回押下が取り消しに化けていた
/// （`lib/hooks/useFavorites.ts` の経緯）。同じ轍を踏まない。
///
/// サーバーのいいねが本体で、これはその写し。**圏外でも一覧が出る**ように
/// 端末にも持つ。
@MainActor
final class FavoritesStore: ObservableObject {

    @Published private(set) var ids: Set<String> = []

    private let defaults: UserDefaults
    private var userId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let sharedKey = "photo-gallery-favorites"

    private func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return Self.sharedKey }
        return "\(Self.sharedKey):\(userId)"
    }

    /// ログイン状態が変わったら呼ぶ。**持ち越さない**
    /// （別の人のハートを吸い込む事故は Web で実際に起きた）。
    func use(userId: String?) {
        self.userId = userId
        ids = Set(defaults.stringArray(forKey: key(for: userId)) ?? [])
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func set(_ id: String, favorite: Bool) {
        if favorite {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        defaults.set(Array(ids), forKey: key(for: userId))
    }
}
