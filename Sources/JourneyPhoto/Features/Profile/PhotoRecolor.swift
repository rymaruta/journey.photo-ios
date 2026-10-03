import Foundation
// 読んだ応答が画像かどうかは ImageIO で読めるかで決める（`decodable`）
import ImageIO

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

    /// 差し替えに失敗した・止まった回に残す、元の画像と最後の調整内容。
    /// 「もう一度」でこの内容から編集画面を開き直す（調整をやり直させない）
    struct Retry: Equatable {
        let source: Data
        let recipe: PhotoRecipe
    }

    /// 「閉じる」・下へ払うを止めるか。**保存・差し替えの最中だけ。** 色の編集の元を読んでいる間は止めない
    /// ——読み込みは閉じたら取り消すだけで済み、遅い回線で画面に閉じ込めない
    static func blocksClosing(isSaving: Bool, isReplacing: Bool, isLoadingRecolor: Bool) -> Bool {
        isSaving || isReplacing
    }

    /// 「完了」を押したあとの結末
    enum Finish {
        /// 無編集。何も送らずに閉じる
        case unchanged
        /// 保存・差し替えの最中。送らない（二重に送らない）。調整内容は残す
        case busy(Retry)
        /// 差し替えた。見本は送った本体から作る
        case replaced(ImagePreparer.Prepared)
        /// 書き出し・送信に失敗した。知らせの文と、やり直すための調整内容
        case failed(message: String, retry: Retry)
    }

    /// 「完了」の扱い。
    ///
    /// - 無編集（`isIdentity`）なら**書き出しも送信もしない**
    /// - 保存・差し替えの最中（`isBusy`）なら送らない。**差し替えの印は画面の `isReplacing` を使い回す**
    ///   ——立てるのは書き出しの前（書き出しの間に2回目が来ても通さない）、下ろすのは終わったとき（失敗でも）
    /// - 書き出し（`export`）と送信（`send`）の失敗は `.failed`。文はサーバーの文言をそのまま
    ///   （409「元のストーリーが出ている間は…」など・`APIError.errorDescription`）
    @MainActor
    static func finish(recipe: PhotoRecipe,
                       source: Data,
                       isBusy: () -> Bool,
                       setReplacing: (Bool) -> Void,
                       export: (PhotoRecipe) async throws -> ImagePreparer.Prepared,
                       send: (ImagePreparer.Prepared) async throws -> Void) async -> Finish {
        if recipe.isIdentity { return .unchanged }
        let retry = Retry(source: source, recipe: recipe)
        if isBusy() { return .busy(retry) }
        setReplacing(true)
        defer { setReplacing(false) }
        do {
            let prepared = try await export(recipe)
            try await send(prepared)
            return .replaced(prepared)
        } catch {
            return .failed(message: (error as? LocalizedError)?.errorDescription
                               ?? L("差し替えられませんでした", "Couldn't replace it"),
                           retry: retry)
        }
    }

    /// 結末ごとに画面へ出す一言（無編集は何も出さない）。`isError` は知らせを赤で出すか
    static func notice(for finish: Finish) -> (text: String, isError: Bool)? {
        switch finish {
        case .unchanged:
            return nil
        case .busy:
            return (L("保存・差し替えの途中だったので、色の編集はまだ反映していません。終わってから「もう一度」を押してください",
                      "Your color edits weren't applied because a save or replace was in progress. Tap \"Try again\" when it finishes."),
                    true)
        case .replaced:
            return (L("色を編集した写真に差し替えました（反映まで数分かかります）",
                      "Replaced with the recolored photo. It takes a few minutes to appear."), false)
        case .failed(let message, _):
            return (message, true)
        }
    }

    /// 読めなかった
    enum LoadError: LocalizedError, Equatable {
        /// 通信の失敗・200 以外・空の応答
        case unreadable
        /// 画像として読めない応答（Wi-Fi のログイン画面の HTML など）
        case notImage
        /// 上限（`maxSourceBytes`）を超えた
        case tooLarge
        /// 403。署名つき URL の期限切れと見る（写真を取り直して1回だけ読み直す・`loadSource`）
        case forbidden
        /// 取り直しても読めなかった。**開き直すしかない**ことを言う
        case expired

        var errorDescription: String? {
            switch self {
            case .unreadable, .notImage:
                return L("写真を読み込めませんでした。少し時間をおいて、もう一度お試しください",
                         "Couldn't load the photo. Please try again in a moment.")
            case .tooLarge:
                return L("写真が大きすぎて読み込めませんでした",
                         "The photo is too large to load.")
            case .forbidden, .expired:
                return L("写真を読み込めませんでした。この画面を閉じて、写真を開き直してからお試しください",
                         "Couldn't load the photo. Close this screen, reopen the photo, and try again.")
            }
        }
    }

    /// 読み込みの上限（公開中の画像は長い辺 1920px の JPEG で、ふつうは 1MB 前後）
    static let maxSourceBytes = 30 * 1024 * 1024
    /// 読み込みにかける時間の上限（秒・つながってから読み終わるまで全体）
    static let sourceTimeout: TimeInterval = 30

    /// 読み込みに使う通信。**時間の上限は全体で**（`timeoutIntervalForResource`）——
    /// 1つ目の `timeoutIntervalForRequest` は「途切れている間」しか測らず、少しずつ届く回は止まらない
    static let sourceSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = sourceTimeout
        config.timeoutIntervalForResource = sourceTimeout
        return URLSession(configuration: config)
    }()

    /// ImageIO で画像として読めるか（形式は Content-Type ではなく中身で決める）
    static func decodable(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// 公開中の画像を読む（編集の元）。
    /// - 403 は `.forbidden`（期限切れの見込み・呼ぶ側が取り直す）
    /// - 上限を超えたら `.tooLarge`（言われた長さで先に断る。言われなくても読んだ長さで断る）
    /// - **画像として読めない応答**は `.notImage`（`isImage`・既定は ImageIO）
    static func fetchSource(from url: URL?, session: URLSession = sourceSession,
                            maxBytes: Int = maxSourceBytes,
                            isImage: (Data) -> Bool = decodable) async throws -> Data {
        guard let url else { throw LoadError.unreadable }
        let data: Data
        let response: URLResponse
        do {
            try RequestCancellation.throwIfCancelled()
            (data, response) = try await session.data(from: url)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw LoadError.unreadable }
        if http.statusCode == 403 { throw LoadError.forbidden }
        guard (200..<300).contains(http.statusCode), !data.isEmpty else { throw LoadError.unreadable }
        if http.expectedContentLength > Int64(maxBytes) || data.count > maxBytes { throw LoadError.tooLarge }
        guard isImage(data) else { throw LoadError.notImage }
        return data
    }

    /// 編集の元を読む。**403 なら写真を取り直して、新しい URL で1回だけ読み直す**
    /// （公開画像の URL が期限切れになっている回）。取り直せない・それでも 403 なら `.expired`
    static func loadSource(url: URL?,
                           refreshURL: () async throws -> URL?,
                           fetch: (URL?) async throws -> Data) async throws -> Data {
        do {
            return try await fetch(url)
        } catch LoadError.forbidden {
            guard let fresh = try? await refreshURL() else { throw LoadError.expired }
            do {
                return try await fetch(fresh)
            } catch LoadError.forbidden {
                throw LoadError.expired
            }
        }
    }
}
