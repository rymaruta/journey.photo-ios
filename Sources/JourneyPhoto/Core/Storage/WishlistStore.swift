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

    func use(userId: String?) {
        self.userId = userId
        spotIds = Set(defaults.stringArray(forKey: key(for: userId)) ?? [])
    }

    func contains(_ spotId: String) -> Bool { spotIds.contains(spotId) }

    /// 押すたびに入れ替える。**押した後の状態**を返す（画面の知らせに使う）
    @discardableResult
    func toggle(_ spotId: String) -> Bool {
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

}
