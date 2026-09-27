import Foundation

// Linux では URLSession が別モジュールに居る。**iOS では何も起きない**が、
// これがないと Linux 上で `swift build` / `swift test` ができない
// （Xcode の無い環境で型検査できる唯一の層なので、そこを塞がない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 写真の投稿。3手で済む:
///
///     1. POST /upload/presigned-url  … 置き場所と署名付き URL をもらう
///     2. PUT  <署名付き URL>          … S3 へ本体を置く
///     3. POST /upload/save            … DynamoDB に1行作る
///
/// **2 と 3 の間で落ちたら S3 に迷子のファイルが残る。** ただし 3 の失敗は
/// **その場では片付けない**——保存は通っていて応答だけ失われたのかもしれず、
/// やり直しは同じ鍵で送る（`stage` の注記）。片付けるのは、本人がその写真を
/// 諦めたとき（`DELETE /upload/discard`。`api-user/src/upload.ts` の
/// `discardUpload`。保存済みの写真が使っているキーは消せないようになっている）。
struct UploadService {

    private let api: APIClient
    private let session: URLSession

    /// api-user が弾く上限（`upload.ts`）。手前で同じ数字を出して、
    /// 50MB のアップロードを走らせてから 400 を食う無駄をなくす。
    static let maxFileSize = 50 * 1024 * 1024

    /// api-user が受け付ける画像の MIME（`uploadPolicy.ts` の
    /// `ALLOWED_IMAGE_TYPES`）。**`image/svg+xml` は入っていない**
    /// ——SVG はスクリプトを書ける文書で、同一オリジンで返るため。
    static let allowedImageTypes: Set<String> = [
        "image/jpeg", "image/png", "image/webp",
        "image/avif", "image/gif", "image/heic", "image/heif",
    ]

    init(api: APIClient, session: URLSession? = nil) {
        self.api = api
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            // 本体の転送は API 呼び出しより長くかかる
            config.timeoutIntervalForRequest = 120
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - 1. 置き場所をもらう

    struct PresignResponse: Decodable {
        let presignedUrl: String
        let key: String
        let publicUrl: String
        let photoId: String?
        /// **PUT で送る Content-Type はこれと完全に一致させること。**
        /// presigner が content-type を署名対象に入れているので、
        /// 違う値で送ると SignatureDoesNotMatch で弾かれる
        /// （`uploadPolicy.ts` の長いコメントがその経緯）。
        let contentType: String
    }

    func presign(fileName: String, fileType: String, fileSize: Int) async throws -> PresignResponse {
        struct Body: Encodable {
            let fileName: String
            let fileType: String
            let fileSize: Int
        }
        return try await api.authorized(
            .post, "/upload/presigned-url",
            body: Body(fileName: fileName, fileType: fileType, fileSize: fileSize),
            as: PresignResponse.self
        )
    }

    // MARK: - 2. S3 に置く

    func put(data: Data, to presigned: PresignResponse) async throws {
        guard let url = URL(string: presigned.presignedUrl) else {
            throw APIError.decoding("署名付き URL を読めませんでした")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(presigned.contentType, forHTTPHeaderField: "Content-Type")

        let response: URLResponse
        do {
            (_, response) = try await session.upload(for: request, from: data)
        } catch {
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("HTTP 応答ではありません")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: L("画像のアップロードに失敗しました", "Image upload failed"))
        }
    }

    // MARK: - 3. 1行作る

    struct SaveResponse: Decodable {
        let success: Bool
        let photo: Photo?
    }

    func save(_ draft: PhotoDraft, presigned: PresignResponse) async throws -> Photo? {
        let body = draft.saveBody(key: presigned.key, publicUrl: presigned.publicUrl)
        let result: SaveResponse = try await api.authorized(
            .post, "/upload/save", body: body, as: SaveResponse.self
        )
        return result.photo
    }

    // MARK: - 後始末

    /// 置いたが保存しない本体を片付ける（PUT の失敗・本人が諦めた写真）。失敗しても投げない
    /// ——後始末が転んだことで、利用者に出す本来のエラーを覆い隠さない。
    func discard(key: String) async {
        struct Body: Encodable { let key: String }
        _ = try? await api.authorizedVoid(.delete, "/upload/discard", body: Body(key: key))
    }

    // MARK: - まとめて

    /// 上げてよい大きさと形式か。**投稿と差し替えで同じものを通す**
    /// ——片方だけ緩いと、そちらから上げ切ってから 400 を食う。
    static func checkAcceptable(size: Int, type: String) throws {
        guard size <= maxFileSize else {
            throw APIError.server(status: 400, message: L("ファイルサイズが大きすぎます（最大50MB）", "File is too large (50 MB max)"))
        }
        guard allowedImageTypes.contains(type) else {
            throw APIError.server(status: 400, message: L("対応していない形式です（JPEG・PNG・WebP・AVIF・HEIC）", "Unsupported format (JPEG, PNG, WebP, AVIF, HEIC)"))
        }
    }

    /// 1 と 2（置き場所をもらって本体を置く）。**保存（3）はまだ。**
    ///
    /// 保存を分けてあるのは、🔴 **保存のやり直しを同じ鍵で送るため。**
    /// 保存の応答が失われた（圏外・API Gateway の 29 秒）ときも、サーバーには
    /// 行ができていることがある。以前は1〜3を毎回通していたので、やり直すと
    /// 新しい鍵で2枚目の行ができていた。サーバーは写真の ID を鍵から導き
    /// （`upload.ts` の `idFromUploadKey`）、同じ鍵の再保存を今回の内容で
    /// 書き直して成功を返すので、**同じ鍵で送り直せば二重にならない**。
    ///
    /// PUT で落ちたら S3 の迷子を片付けてから投げ直す（行はまだ無い）。
    func stage(data: Data, fileName: String, fileType: String) async throws -> PresignResponse {
        try Self.checkAcceptable(size: data.count, type: fileType)

        let presigned = try await presign(fileName: fileName, fileType: fileType, fileSize: data.count)
        do {
            try await put(data: data, to: presigned)
        } catch {
            await discard(key: presigned.key)
            throw error
        }
        return presigned
    }
}

/// 投稿の下書き。画面が組み立てて UploadService に渡す。
struct PhotoDraft {
    var title: String = ""
    var description: String = ""
    var location: String = ""
    var category: String?
    var tags: [String] = []
    var published: Bool = true
    /// 撮影日（YYYY-MM-DD）。1990年より前・未来は api-user が弾く
    var date: String?
    var coords: Photo.Coords?
    var albumId: String?
    /// 原本から読み取った撮影情報。**GPS は含まない**
    var exif: ExifFields?
    /// 代表色（`#rrggbb`）。**読み込み中の地の色**。
    /// Web は前から送っていて、アプリだけ送っていなかった
    var dominantColor: String?
    /// 同じ投稿としてまとめる印。**行は1枚ずつのまま**
    var groupId: String?

    /// 公開範囲。**既定は全体に公開**（これまでと同じ）。
    /// 絞ると静的サイトに載らない＝検索から辿り着けなくなる
    /// （`Audience.photoNote` に書いてある）。
    var audience: Audience = .everyone

    /// `POST /upload/save` に送る形。
    ///
    /// **座標は端末側でも丸めてから送る。** サーバーも約1km（小数第2位）に
    /// 丸めるが（`sanitize.ts` の `sanitizeCoords`）、丸める前の値を
    /// 電波に乗せる理由が無い。
    func saveBody(key: String, publicUrl: String) -> SaveBody {
        SaveBody(
            key: key,
            publicUrl: publicUrl,
            title: title.isEmpty ? nil : title,
            description: description.isEmpty ? nil : description,
            location: location.isEmpty ? nil : location,
            category: category,
            tags: tags.isEmpty ? nil : tags,
            published: published,
            date: date,
            coords: coords.map { SaveBody.Coords(lat: ($0.lat * 100).rounded() / 100,
                                                 lng: ($0.lng * 100).rounded() / 100) },
            albumId: albumId,
            exif: exif,
            dominantColor: dominantColor,
            groupId: groupId,
            audience: audience.wireValue
        )
    }

    struct SaveBody: Encodable {
        let key: String
        let publicUrl: String
        let title: String?
        let description: String?
        let location: String?
        let category: String?
        let tags: [String]?
        let published: Bool
        let date: String?
        let coords: Coords?
        let albumId: String?
        let exif: ExifFields?
        let dominantColor: String?
        let groupId: String?
        /// 公開範囲。**全体に公開のときは送らない**（属性を書かない形に揃える）
        let audience: String?

        struct Coords: Encodable {
            let lat: Double
            let lng: Double
        }
    }
}
