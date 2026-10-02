import Foundation

/// API のパスに入れる ID・トークンを確かめる。
///
/// 🔴 **パスに入れる値は、英数字・`-`・`_` だけを通す。** 以前は口ごとに
/// `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)` を掛けていたが、
/// `.urlPathAllowed` は `/` と `.` を通す——`../user/account` のような値が来ると、
/// 写真の削除が**別の口**（`DELETE /user/account`）に化けうる。符号化を
/// 掛けていない口（親しい友達）もあった。
///
/// サーバーが実際に配る ID はどれもこの形に収まる（pg-dev の api-user で確かめた）:
/// - 写真・コメント: `uuidv4()`（`upload.ts`・`comments.ts`）
/// - アルバム・ハイライト・旅行プラン: `randomUUID()`（`albums.ts`・`highlights.ts`・`tripPlans.ts`）
/// - ストーリー: `story-<UUID>`（`stories.ts`）
/// - 招待トークン: 24 バイトの base64url（`invite.ts`——`A-Z a-z 0-9 - _`）
/// - 利用者: Cognito の sub（UUID）
/// - スポット: `sp_<16進>`
///
/// **使わない口:** 行きたい場所（`/user/spots/{slug}`）の鍵は日本語の地名を含むので
/// ここを通さない（`SavedSpotService.unsave` の注記）。
///
/// 合わない値は**要求を出さずに**失敗にする（`APIError.invalidIdentifier`）。
/// 符号化は要らない（通す文字はどれもパスにそのまま書ける）。
enum PathID {

    /// 長さの上限。いちばん長い `story-<UUID>` でも 42 文字。余裕を見て決める
    static let maxLength = 128

    static func isSafe(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maxLength else { return false }
        return value.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39)      // 0-9
                || (byte >= 0x41 && byte <= 0x5A) // A-Z
                || (byte >= 0x61 && byte <= 0x7A) // a-z
                || byte == 0x2D || byte == 0x5F   // - _
        }
    }

    /// パスに入れてよい値ならそのまま返す。合わなければ投げる
    static func segment(_ value: String) throws -> String {
        guard isSafe(value) else { throw APIError.invalidIdentifier }
        return value
    }
}
