import Foundation
import Combine

/// 保存した写真の控え（端末）。**サーバーが本体**（`SaveService`）。
///
/// 控えを持つ理由は `FavoritesStore` と同じ——**圏外でも一覧が出る**、
/// 押した瞬間に画面が変わる。違うのは中身で、あちらは**いいね**の写し、
/// こちらは**保存**の写し。
///
/// 🔴 **1つの入れ物を2つの意味で使わない。** 使っていたときは、保存を
/// 押すとハートが灯り、マイページの「いいねした写真」に保存しただけの
/// 写真が並んだ。
@MainActor
final class SavedPhotosStore: ObservableObject {

    @Published private(set) var ids: Set<String> = []

    private let defaults: UserDefaults
    private var userId: String?
    /// 手元で押した分（同期の入れ替えで消さないため・`LocalEdits`）
    private var edits = LocalEdits()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// **`FavoritesStore` と別の鍵。** 同じにすると元の混線に戻る
    private static let sharedKey = "journey-photo-saved-photos"

    private func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return Self.sharedKey }
        return "\(Self.sharedKey):\(userId)"
    }

    /// ログイン状態が変わったら呼ぶ。**持ち越さない**
    func use(userId: String?) {
        self.userId = userId
        ids = Set(defaults.stringArray(forKey: key(for: userId)) ?? [])
        edits.reset(owner: userId)
    }

    /// 同期で一覧を取りに行く**前に**取る。`replace(with:since:)` に渡す
    var syncMark: LocalEdits.Mark { edits.mark }

    func contains(_ photoId: String) -> Bool { ids.contains(photoId) }

    /// 押した後の状態を返す（画面の知らせに使う）
    @discardableResult
    func toggle(_ photoId: String) -> Bool {
        let saved = !contains(photoId)
        set(photoId, saved: saved)
        return saved
    }

    func set(_ photoId: String, saved: Bool) {
        guard !photoId.isEmpty else { return }
        if saved { ids.insert(photoId) } else { ids.remove(photoId) }
        edits.note(photoId, on: saved)
        defaults.set(Array(ids), forKey: key(for: userId))
    }

    /// サーバーの一覧に合わせる。**取れた回だけ呼ぶこと**
    /// ——取れなかった回に空で上書きすると、控えごと消える
    ///
    /// - Parameter mark: 取りに行く前の `syncMark`。**その後に押した分は残す**。
    ///   別の人の印なら書かない
    func replace(with photoIds: [String], since mark: LocalEdits.Mark? = nil) {
        var next = Set(photoIds)
        if let mark {
            guard let merged = edits.merged(next, since: mark) else { return }
            next = merged
        }
        ids = next
        defaults.set(Array(ids), forKey: key(for: userId))
    }

    /// 退会した人の控えを消す（読めない鍵付きデータを残さない）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: key(for: userId))
    }
}
