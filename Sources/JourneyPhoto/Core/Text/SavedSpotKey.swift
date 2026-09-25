import Foundation

/// 「行きたい」（`WishlistStore`）に入れる鍵の形。
///
/// **Web の `lib/utils/savedSpotKey.ts` と同じ約束。** 入れ物は文字列の
/// 一覧で、これまで入っていたのは**撮影地のスラッグ**（`パリ` /
/// `yamanakako`）だけだった。ここに台帳の撮影スポットを足すが、
/// **混ぜてはいけない**——撮影地のスラッグは写真の自由入力から作るので、
/// 同じ綴りが偶然できうる。同じ文字列というだけで別物を1件に見せない。
///
/// 接頭辞が `SPOT-` なのは、撮影地のスラッグ（`LocationSlug.make`＝Web の
/// `slugify`）が**小文字にする**ため——出力に大文字は現れず、撮影地の名前が
/// 偶然この形になることは原理的に無い。記号を含まないので URL のパス片にも
/// そのまま置ける（サーバーの `DELETE /user/spots/{slug}` に乗せる日のため）。
///
/// **鍵は端末の中だけ**（`WishlistStore`）。サーバーの `/user/spots` へ寄せる
/// かは owner の判断待ちで、今回は鍵の形だけ Web と揃えておく。
enum SavedSpotKey {

    /// 撮影スポットの鍵に付ける頭。**`LocationSlug.make` の出力には現れない**
    static let officialPrefix = "SPOT-"

    /// 撮影スポット（`/spots/<slug>`）を保存するときの鍵。二重には付けない
    static func official(_ slug: String) -> String {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(officialPrefix) { return trimmed }
        return officialPrefix + trimmed
    }

    /// 撮影スポットの鍵か。**頭の無いものは今までどおり撮影地**
    /// （知らない形を捨てると、既存の保存が消えたように見える）
    static func isOfficial(_ key: String) -> Bool {
        key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(officialPrefix)
    }

    /// 鍵からスラッグを取り出す。撮影地の鍵なら nil。
    /// **`SPOT-`（スラッグが空）も落とさない**——落とすと画面に出ないのに
    /// 保存には残り、本人が外す手段を失う
    static func slug(fromOfficial key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(officialPrefix) else { return nil }
        return String(trimmed.dropFirst(officialPrefix.count))
    }
}
