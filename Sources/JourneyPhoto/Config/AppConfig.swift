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
        #if DEBUG
        // **Debug ビルドだけ、起動引数で上書きできる。**
        //
        // UI テストは Debug＝staging 設定で走る。staging には写真が
        // **1枚も無い**（本番の写真はコピーしない方針・photo-gallery の
        // CLAUDE.md）ので、撮れる絵は「No photos found.」ばかりで、
        // 人が実際に見る画面の確認にならない。起動引数
        // （`-JPSiteBaseURL https://journey-photo.com`）で**写真の出どころ
        // だけ**を本番に向けられるようにする。
        //
        // **Release には入れない**（`#if DEBUG`）。出荷する側に
        // 「外から向き先を変えられる口」を残さないため。
        if let overridden = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !overridden.isEmpty {
            return overridden
        }
        #endif
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

    /// 管理 API（photo-gallery の `api/`）の `GET /photos`。**未認証で読める、
    /// いまの一覧**。
    ///
    /// **いいねの数だけ**に使う（`LiveLikes`）。一覧そのものの出どころは
    /// 今までどおり静的 JSON——こちらは失敗しても一覧は出る。
    ///
    /// テストで `testOverrides` を入れていて、このキーを持たない回は nil
    /// ＝叩かない（既存の試験が知らない口を叩いて落ちないように）。
    /// 本物のビルドでキーが無いのは設定ミスなので、今までどおり落とす。
    static var livePhotosURL: URL? {
        if let overrides = testOverrides, overrides["JPApiBaseURL"] == nil { return nil }
        return requireURL("JPApiBaseURL").appendingPathComponent("photos")
    }

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

    /// 撮影スポットの**索引**。写真と同じく**静的な JSON**で、API ではない。
    ///
    /// 出どころは DynamoDB ではなく Web の `content/spots.json`（人が持つ台帳）。
    /// Next のルートハンドラ（`app/app/data/spots.json`）が、ビルド時にそこから
    /// アプリ向けの薄い索引（`spotId`・`slug`・名前・読み・地域・座標・
    /// 分類・概要・`stage`・日付）を書き出し、`scripts/deploy-static-site.js` が
    /// 他の静的ファイルと一緒にサイト直下へ配る。**1件ごとの詳細 JSON は
    /// v1 では読まない**（索引だけ）。
    ///
    /// **本番は Web のその変更が `main` に入るまで 404。** そのあいだ
    /// `OfficialSpotService.fetchIndex` は投げ、地図はスポットのピンを
    /// 出さないだけで、写真の機能には触らない。
    ///
    /// **スポットのための API は足していない。**
    static var publicSpotsURL: URL {
        siteBaseURL.appendingPathComponent("app/data/spots.json")
    }
}
