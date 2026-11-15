import Foundation
#if canImport(Security)
import Security
#endif

/// **鍵束（キーチェーン）がまだ開いていないか**を確かめる（2026-11-15 判断・札 #617）。
///
/// Amplify は自分の控え（ログイン）を `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` で鍵束に置く
/// （amplify-swift 2.63.0 `KeychainItemAttributes.swift`）——端末を入れ直してから**1度も鍵を開けていない**間は読めない。
/// そして `Amplify.configure` は起動のときに1回だけ控えを読み、**読めなかった回は「ログインしていない」で始め、
/// そのプロセスが終わるまで読み直さない**（同 `InitializeAuthConfiguration.swift`: `itemNotFound` 以外の失敗も
/// `credentials = .noCredentials` のまま進む）。だから鍵を開ける前に起こされた起動（すれちがいの電波の復元など、
/// 裏で起こされる起動）で設定すると、あとで利用者が開いたときに**控えは残っているのにログイン画面が出る**。
///
/// ここは**自分の小さな控え**（同じ読める条件で置く）を読んで、鍵束が開いているかだけを見る。Amplify の控えには触らない
enum KeychainProbe {

    static let service = "jp.keychainProbe"
    static let account = "probe"

    /// 鍵束がまだ開いていない（読めない）なら true。分からない回（ほかの失敗）は false——待たずに今までどおり進む
    static func isLocked() -> Bool {
        #if canImport(Security)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecInteractionNotAllowed { return true }
        guard status == errSecItemNotFound else { return false }
        // まだ置いていない（初めての起動）。同じ読める条件で置いてみる——置けなければ開いていない
        query.removeValue(forKey: kSecReturnData as String)
        query.removeValue(forKey: kSecMatchLimit as String)
        query[kSecValueData as String] = Data([1])
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecInteractionNotAllowed
        #else
        return false
        #endif
    }
}
