import Foundation
import Combine

/// 「行きたい場所」（モック5・モック2）。
///
/// 🔴 **鍵は `/location/<スラッグ>` のスラッグ**（`LocationSlug`）。
/// サーバーの「行きたい場所」（`spots#<uid>`）に入っているのと**同じ文字列**で、
/// Web の一覧とも突き合わさる。
///
/// **台帳の撮影スポットは `SPOT-<slug>`**（`SavedSpotKey`・Web の
/// `savedSpotKey.ts` と同じ）。同じ入れ物に入るが、頭で見分けるので
/// 撮影地の鍵とは混ざらない。マイページの一覧は両方を並べる
/// （スポットの側は `OfficialWishlist.rows` が索引と突き合わせる）。
///
/// **端末に残る。サーバーには無い。** api-user に「行きたい」の口は
/// （いいね・保存・フォローはあるが）無いので、押した事実はこの端末にしか
/// 残らない。だから画面でもそう書く——**他人の「行きたい」数は出さない**
/// （数えていないものを数字にしない）。
///
/// 鍵はアカウントごとに分ける（`FavoritesStore` と同じ理由——同じ端末で
/// 人が変わったときに前の人の印を吸い込まないため）。
@MainActor
final class WishlistStore: ObservableObject {

    @Published private(set) var spotIds: Set<String> = []

    private let defaults: UserDefaults
    private var userId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let sharedKey = "journey-photo-wishlist"

    private func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return Self.sharedKey }
        return "\(Self.sharedKey):\(userId)"
    }

    /// 使う人を切り替える。
    ///
    /// 🔴 **ログインしていない間に押したぶんは、ログインした人へ引き継ぐ。**
    /// 未ログインの印は共有の鍵（`sharedKey`）に入るので、以前はログインした瞬間に
    /// その人の鍵へ切り替わるだけで、**押したばかりの「行きたい」が消えて見えた**。
    /// 未ログイン→ログインの回だけ、共有の鍵のぶんをその人の鍵へ足して共有の鍵を消す
    /// （消さないと、次にログインした別の人にも同じぶんが入る）。
    ///
    /// 🔴 **ログイン中の人から別の人へ替わる回は混ぜない**（`FavoritesStore` と同じ
    /// 理由——同じ端末で人が変わったときに前の人の印を吸い込まない）
    func use(userId: String?) {
        let wasSignedOut = self.userId?.isEmpty ?? true
        self.userId = userId
        var ids = Set(defaults.stringArray(forKey: key(for: userId)) ?? [])
        if wasSignedOut, let userId, !userId.isEmpty {
            let anonymous = Set(defaults.stringArray(forKey: Self.sharedKey) ?? [])
            if !anonymous.isEmpty {
                ids.formUnion(anonymous)
                defaults.set(Array(ids), forKey: key(for: userId))
                defaults.removeObject(forKey: Self.sharedKey)
            }
        }
        spotIds = ids
    }

    func contains(_ spotId: String) -> Bool { spotIds.contains(spotId) }

    /// 押すたびに入れ替える。**押した後の状態**を返す（画面の知らせに使う）
    ///
    /// 🔴 **空の鍵は何もせず false。** `set` は空の鍵を捨てるのに、ここが
    /// 「入った」と返していたので、画面は「追加しました」と知らせて何も残らなかった
    @discardableResult
    func toggle(_ spotId: String) -> Bool {
        guard !spotId.isEmpty else { return false }
        let wanted = !contains(spotId)
        set(spotId, wanted: wanted)
        return wanted
    }

    func set(_ spotId: String, wanted: Bool) {
        guard !spotId.isEmpty else { return }
        if wanted {
            spotIds.insert(spotId)
        } else {
            spotIds.remove(spotId)
        }
        defaults.set(Array(spotIds), forKey: key(for: userId))
    }

    /// 退会した人の控えを消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: key(for: userId))
    }
}
