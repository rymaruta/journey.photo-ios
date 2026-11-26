import Foundation
// Linux では URLSession が別モジュールに居る（`StoreDemo` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **Apple Weather の印**（WeatherKit の表示の決まり・2026-11-25 審査 5.2.5 の差し戻し・札 #604）。
///
/// 天気はサーバーが WeatherKit の REST で取る（`api-user/src/lightForecast.ts`）。アプリは WeatherKit の部品
/// （`WeatherService`）を持たない——持つには App ID の WeatherKit の能力と権限（entitlement）が要り、署名のプロファイルが
/// 合わないと Archive が落ちる。そこで、REST 用の公開の出典の口 `https://weatherkit.apple.com/attribution/<言語>`
/// （`WeatherService.attribution` と同じ中身: 印の画像・サービス名）を読み、**黒い地に置く白の印**（`logoDark@3x`）を出す。
/// 読めない間・読めないときは、字の印（`textMark`）を出す（印を出さずに天気を出さない）。
///
/// 法的な出典のリンクは、サーバーの応答の `attribution.legalUrl`（`LightForecast.Attribution`）を使う
struct WeatherAttributionMarks: Equatable {
    let serviceName: String
    /// 黒い地に置く白の印（3x・高さ 42px＝14pt）
    let darkMark: URL

    /// 印の高さ（pt）。3x の画像の高さ 42px から（`attribution/ja`・`attribution/en` どちらも 42px）
    static let markHeight: CGFloat = 14
}

enum WeatherAttribution {

    /// 出典の口の置き場（印の画像の相対パスもここから引く）
    static let base = URL(string: "https://weatherkit.apple.com")!

    /// 言語（印の字が言語ごとに違う: 日本語は「天気」、英語は「Weather」）
    static func language(preferred: String) -> String { preferred == "ja" ? "ja" : "en" }

    static func endpoint(language: String) -> URL {
        base.appendingPathComponent("attribution").appendingPathComponent(language)
    }

    /// 読めないときの字の印。2026-11-26 判断（審査 5.2.5）: Apple のロゴの字（U+F8FF）は使わない
    /// （Apple の商標の決まりで、字の中にロゴを置かない）。サービスの名前（出典の口の `serviceName` と同じ）を字で出す
    static var textMark: String { "Apple Weather" }

    /// 出典の口の答えを読む。**印の画像は weatherkit.apple.com の https だけ**受ける（ほかの置き場の画像は出さない）
    static func decode(_ data: Data) -> WeatherAttributionMarks? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = (object["logoDark@3x"] as? String) ?? (object["logoDark@2x"] as? String),
              let url = URL(string: path, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.host == base.host else { return nil }
        let name = (object["serviceName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Apple Weather"
        return WeatherAttributionMarks(serviceName: name, darkMark: url)
    }

    /// 読んだ印（言語ごと・起動の間だけ控える）
    @MainActor private static var cache: [String: WeatherAttributionMarks] = [:]

    /// 印を読む。読めなければ nil（画面は字の印を出す）
    @MainActor
    static func load(language: String = language(preferred: Locale.preferredAppLanguage),
                     session: URLSession = .shared) async -> WeatherAttributionMarks? {
        if let known = cache[language] { return known }
        guard let (data, response) = try? await session.data(from: endpoint(language: language)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let marks = decode(data) else { return nil }
        cache[language] = marks
        return marks
    }
}
