import Foundation

/// APNs の端末トークンの扱い。
///
/// **`@MainActor` の型に置かない**（テストから呼べなくなる。5回目の轍）。
enum PushToken {

    /// `Data` を16進の文字列にする。
    ///
    /// **`description` を使わない。** iOS 15 までは `<a1b2 c3d4>` のような
    /// 文字列が返り、それ以降は `32 bytes` に変わった——どちらもサーバーに
    /// 送ると弾かれる（APNs のトークンは16進の文字列）。
    static func hex(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// 送ってよい形か。**サーバーと同じ判定**（`api-user/src/devices.ts` の
    /// `isDeviceToken`）——ここで弾けば、通らない要求を出さずに済む。
    static func isValid(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (32...200).contains(trimmed.count) else { return false }
        return trimmed.allSatisfy { $0.isHexDigit }
    }
}
