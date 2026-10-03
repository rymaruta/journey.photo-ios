import Foundation

// Linux では URLSession が別モジュールに居る（`DailyQuizService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿済みの写真の色を編集し直す（段階1・2026-10-03）。
/// 写真詳細「…」→「編集」（`EditPhotoView`）→「色を編集」。
///
/// - 元にするのは**公開中の画像**（`Photo.src`・長い辺 1920px・EXIF / GPS はもう無い）。
///   原本は端末にもサーバーにも残っていないので、**投稿した写真の上に重ねて**編集する（画面にそう出す）
/// - 編集画面は投稿のときと同じ `PhotoEditView`。レシピは `.identity` から始める
///   （投稿時のレシピは公開中の画像にもう焼き込まれている）
/// - 「完了」: 無編集なら何も送らない。変えていれば `PhotoRenderer.exportPrepared` で書き出し
///   （EXIF の関所 `encodeStripped` を通る）、`PhotoService.replace` で差し替える。
///   **撮影情報（EXIF・撮影日・座標）は載せない**——公開中の画像には無いので、載せると空で上書きする。
///   サーバーは送られなかった項目を今の値のまま残す（`keepCurrentMetadata`）
///
/// 画面を持たない（Linux で試験する）。画面側は `EditPhotoView.finishRecolor`
enum PhotoRecolor {

    /// 編集画面に出す一言（`PhotoEditView.note`）
    static var note: String {
        L("投稿した写真の上に重ねて編集します", "Your edits are layered on top of the posted photo.")
    }

    /// 書き出しの土台（`PhotoRenderer.exportPrepared` の `base`）。
    /// 公開中の画像から作るので、**撮影情報は持たない**（どのみち送らない・`keepCurrentMetadata`）
    static func base(source: Data) -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: source, fileName: "photo.jpg", contentType: "image/jpeg",
                               exif: nil, coords: nil, takenOn: nil)
    }

    /// 「完了」を押したあとの結末
    enum Finish {
        /// 無編集。何も送らずに閉じる
        case unchanged
        /// 保存・差し替えの最中。何もしない（二重に送らない）
        case busy
        /// 差し替えた。見本は送った本体から作る
        case replaced(ImagePreparer.Prepared)
    }

    /// 「完了」の扱い。
    ///
    /// - 無編集（`isIdentity`）なら**書き出しも送信もしない**
    /// - 保存・差し替えの最中（`isBusy`）なら何もしない。**差し替えの印は画面の `isReplacing` を使い回す**
    ///   ——立てるのは書き出しの前（書き出しの間に2回目が来ても通さない）、下ろすのは終わったとき（失敗でも）
    /// - 書き出し（`export`）と送信（`send`）の失敗はそのまま投げる（画面が知らせに出す）
    @MainActor
    static func finish(recipe: PhotoRecipe,
                       isBusy: () -> Bool,
                       setReplacing: (Bool) -> Void,
                       export: (PhotoRecipe) async throws -> ImagePreparer.Prepared,
                       send: (ImagePreparer.Prepared) async throws -> Void) async throws -> Finish {
        if recipe.isIdentity { return .unchanged }
        if isBusy() { return .busy }
        setReplacing(true)
        defer { setReplacing(false) }
        let prepared = try await export(recipe)
        try await send(prepared)
        return .replaced(prepared)
    }

    /// 読めなかった
    enum LoadError: LocalizedError, Equatable {
        case unreadable

        var errorDescription: String? {
            L("写真を読み込めませんでした。少し時間をおいて、もう一度お試しください",
              "Couldn't load the photo. Please try again in a moment.")
        }
    }

    /// 公開中の画像を読む（編集の元）。**画像でない応答**（Wi-Fi のログイン画面の HTML など）は読めなかった扱い
    static func fetchSource(from url: URL?, session: URLSession = .shared) async throws -> Data {
        guard let url else { throw LoadError.unreadable }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty else { throw LoadError.unreadable }
        if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           !type.isEmpty, !type.hasPrefix("image/"), !type.hasPrefix("application/octet-stream") {
            throw LoadError.unreadable
        }
        return data
    }
}
