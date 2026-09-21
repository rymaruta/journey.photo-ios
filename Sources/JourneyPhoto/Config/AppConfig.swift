import Foundation

/// 実行時の環境値。すべて Info.plist 経由で xcconfig から入る。
///
/// **既定値（本番値へのフォールバック）を置かない。** Web 側の
/// `lib/aws/env.ts` / `api-user/src/env.ts` と同じ方針で、値が欠けていたら
/// 落とす。フォールバックがあると「staging ビルドのつもりで本番の
/// DynamoDB を触っていた」という事故が静かに起きる。
enum AppConfig {

    enum Environment: String {
        case production
        case staging
    }

    /// **テストから差し替えるための口。本番では必ず nil。**
    ///
    /// Info.plist を持たない環境（Linux 上の `swift test`）で
    /// `AppConfig` を触る型を検査するために要る。
    /// **本番値のフォールバックではない**——nil のままなら今までどおり、
    /// 値が欠けていれば落ちる。
    /// （`nonisolated(unsafe)` は付けない——構文解析器がまだ読めず、
    /// Swift 5 モードでは付けなくても通る。Swift 6 モードへ上げるときに足す）
    static var testOverrides: [String: String]?

    /// Info.plist から必須の文字列を読む。無ければ設定ミスなので即座に落とす。
    private static func require(_ key: String) -> String {
        if let value = testOverrides?[key] { return value }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            fatalError("Info.plist に \(key) がありません。Config/*.xcconfig を確認してください。")
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            fatalError("Info.plist の \(key) が空です。Config/*.xcconfig を確認してください。")
        }
        return value
    }

    private static func requireURL(_ key: String) -> URL {
        let value = require(key)
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
            fatalError("Info.plist の \(key) が https の URL ではありません: \(value)")
        }
        return url
    }

    static var environment: Environment {
        let raw = require("JPEnvironmentName")
        guard let env = Environment(rawValue: raw) else {
            fatalError("JPEnvironmentName が production / staging のどちらでもありません: \(raw)")
        }
        return env
    }

    /// ユーザー API（api-user）の根。末尾にスラッシュは付けない。
    static var userAPIBaseURL: URL { requireURL("JPUserApiBaseURL") }

    /// 静的サイトの根。公開写真の一覧 JSON をここから取る。
    static var siteBaseURL: URL { requireURL("JPSiteBaseURL") }

    static var cognitoUserPoolId: String { require("JPCognitoUserPoolId") }
    static var cognitoClientId: String { require("JPCognitoClientId") }
    static var cognitoRegion: String { require("JPCognitoRegion") }

    /// 公開写真の一覧。`scripts/deploy-static-site.js` が
    /// `app/data/photos.json` としてサイト直下に置いている（非公開の
    /// フィールドは `lib/server/photos.ts` の `PRIVATE_FIELDS` で落とし済み）。
    ///
    /// **これはビルド時に固まったスナップショットで、API ではない。**
    /// 反映は投稿時の `repository_dispatch` によるサイト再ビルド待ちになる。
    static var publicPhotosURL: URL {
        siteBaseURL.appendingPathComponent("app/data/photos.json")
    }
}
