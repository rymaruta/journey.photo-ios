import Foundation

/// 写真を指すサイトの URL。**共有するのは画像ではなくページ。**
///
/// 画像の生 URL を共有すると、受け取った人には題も説明も撮影地も出ない
/// （このサイトが読まれたい中身は全部ページ側にある）。
///
/// **`/photo/<id>` は再ビルドのあとにしか無い。**
/// サイトは静的書き出しで、投稿直後の写真の個別ページはまだ S3 に無い
/// （`lib/routes.ts` の `hasPhotoPage`）。無いものを共有すると 404 になるので、
/// そのときは必ず開ける `/?photo=<id>` に落とす——トップがその写真を
/// 開いた状態で出る。
enum PhotoLink {

    /// - Parameter isPublished: 公開の一覧（`photos.json`）に載っている写真か。
    ///   **載っているなら個別ページも在る**——同じビルドが両方を作るため。
    static func url(photoId: String, isPublished: Bool) -> URL? {
        guard let encoded = photoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !encoded.isEmpty else {
            return nil
        }
        if isPublished {
            return AppConfig.siteBaseURL.appendingPathComponent("photo/\(encoded)")
        }
        var components = URLComponents(url: AppConfig.siteBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "photo", value: photoId)]
        return components?.url
    }

    /// 短縮リンク `/?p=<ID の先頭8文字>`（Threads に載せる文の最後・owner 2026-10-02「短縮リンクは
    /// 載せれる？」）。サイトのトップが一覧と照らして `/?photo=<id>` に置き換える
    /// （`lib/utils/shortPhotoLink.ts`・規則は同じ）。**ID が16進で始まらないときは作らない**
    /// （サイトが短縮と読まず、開けないリンクになる）——呼び手は長い形に落とす
    static func shortURL(photoId: String) -> URL? {
        let short = String(photoId.prefix(8)).lowercased()
        guard short.count == 8, short.allSatisfy({ $0.isHexDigit }) else { return nil }
        var components = URLComponents(url: AppConfig.siteBaseURL, resolvingAgainstBaseURL: false)
        // **末尾の `/` を付ける**（基底 URL は `/` 無し。`https://journey-photo.com?p=…` は正しい URL だが、
        // Threads がそこまでリンクにするかは分からない。1文字で確実な形にする）
        if components?.path.isEmpty ?? false { components?.path = "/" }
        components?.queryItems = [URLQueryItem(name: "p", value: short)]
        return components?.url
    }
}
