import Foundation

// Linux では URLSession が別モジュールに居る。**iOS では何も起きない**が、
// これがないと Linux 上で `swift build` / `swift test` ができない
// （Xcode の無い環境で型検査できる唯一の層なので、そこを塞がない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// プロフィールの読み書き。
struct ProfileService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// 自分のプロフィール。行が無ければサーバー側が作る
    /// （`createProfileIfMissing`）。
    ///
    /// 🔴 **410 は「退会の途中で止まったアカウント」。** サーバーはデータを消して墓石を
    /// 置いた人に 410 を返す（`userProfile.ts` の `getMyProfile`）。退会の画面で Cognito の
    /// 削除だけが落ちたまま閉じると、その人はログインできるのに何も使えない状態で残っていた
    /// （覚えていたのは退会の画面の `@State` だけ）。知らせを出し、`AuthStore` が
    /// 「退会の手続きが途中です」を出して残りを済ませる（`finishPendingDeletion`）
    func myProfile() async throws -> UserProfile {
        #if DEBUG
        // 鍵を持たない入り方（`PreviewSession`・UI テスト）では、鍵の要る口の代わりに公開プロフィール。
        // プロフィールの編集・バッジの棚を UI テストで開けるようにする（Release には無い）
        if let previewId = PreviewSession.userId {
            return try await publicProfile(userId: previewId)
        }
        #endif
        // `catch … where` の中で await しない（`AuthGateway.idToken` の注記）
        let result: Result<UserProfile, Error>
        do {
            result = .success(try await api.authorized(.get, "/user/profile", as: UserProfile.self))
        } catch {
            result = .failure(error)
        }
        if case .failure(let error) = result, Self.meansAccountDeleted(error) {
            await Self.announceDeletionPending()
        }
        return try result.get()
    }

    /// 自分のプロフィールの取得で、アカウントがもう消されている（410）
    static func meansAccountDeleted(_ error: Error) -> Bool {
        if case .server(status: 410, _)? = error as? APIError { return true }
        return false
    }

    @MainActor
    private static func announceDeletionPending() {
        NotificationCenter.default.post(name: .accountDeletionPending, object: nil)
    }

    /// 他人のプロフィール（認証不要）。
    ///
    /// **退会済みの人は 404 で返る**（`isDeletedProfile` の墓石判定）。
    /// 「取れなかった」と「退会した」を混ぜないよう、呼び出し側は
    /// 404 を専用に扱うこと。
    func publicProfile(userId: String) async throws -> UserProfile {
        // 英数字・`-`・`_` 以外は要求を出さずに失敗にする（`PathID`）
        let encoded = try PathID.segment(userId)
        return try await api.anonymous(.get, "/profile/\(encoded)", as: UserProfile.self)
    }

    /// 更新。**送った項目だけが変わる**（未指定は「触らない」）。
    /// ピン留めの増減。**成功したら、サーバーが持っている一覧を返す。**
    ///
    /// 3枚を超えると 409（「ピン留めは3枚までです」）で、そのときの本体にも
    /// 今の一覧が入っている——画面はそれに揃えないと、断られ続けるだけで
    /// 直せない（`userProfile.ts` の `pinLimitCurrent`）。
    struct PinResult: Decodable { let pinnedPhotoIds: [String]? }

    @discardableResult
    func setPinned(photoId: String, pinned: Bool) async throws -> [String] {
        let patch = ProfilePatch(pinPhotoId: photoId, pin: pinned)
        let result = try await api.authorized(.put, "/user/profile", body: patch, as: PinResult.self)
        return result.pinnedPhotoIds ?? []
    }

    func update(_ patch: ProfilePatch) async throws {
        try await api.authorizedVoid(.put, "/user/profile", body: patch)
    }

    /// 自分のバッジと、次の段までの進み具合（バッジの棚）。
    ///
    /// 持っているバッジは公開プロフィールにも載るが、**進み具合は本人だけ**に返る
    /// （人の棚は持っているメダルだけを出す）
    func myBadges() async throws -> BadgeStatus {
        try await api.authorized(.get, "/user/badges", as: BadgeStatus.self)
    }

    // MARK: - アイコンとカバー

    enum ImageKind: String {
        case avatar
        case cover
    }

    struct AvatarPresign: Decodable {
        let presignedUrl: String
        let publicUrl: String
        /// **PUT で送る Content-Type はこれと一致させること**（署名対象）
        let contentType: String
    }

    /// アイコン（`profiles/<uid>`）かカバー（`profiles/<uid>/cover`）の置き場所をもらう。
    func imagePresign(kind: ImageKind, fileType: String) async throws -> AvatarPresign {
        struct Body: Encodable {
            let fileType: String
            let type: String?
        }
        return try await api.authorized(
            .post, "/profile/avatar/presigned-url",
            // サーバーは `type == "cover"` だけを見る
            body: Body(fileType: fileType, type: kind == .cover ? "cover" : nil),
            as: AvatarPresign.self
        )
    }

    /// アイコン／カバーを差し替える。
    ///
    /// **キーは固定**（`profiles/<uid>`）なので、上書きすると即座に全員へ届く。
    /// だからサーバーもアップロードも `no-store` を付けている——控えると
    /// 変更が永久に届かない。
    func uploadProfileImage(kind: ImageKind, jpeg: Data) async throws {
        let presigned = try await imagePresign(kind: kind, fileType: "image/jpeg")
        guard let url = URL(string: presigned.presignedUrl) else {
            throw APIError.decoding("署名付き URL を読めませんでした")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(presigned.contentType, forHTTPHeaderField: "Content-Type")

        let response: URLResponse
        do {
            try RequestCancellation.throwIfCancelled()
            (_, response) = try await URLSession.shared.upload(for: request, from: jpeg)
        } catch {
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                  message: "画像のアップロードに失敗しました")
        }
    }
}

/// プロフィールの部分更新。nil の項目は JSON に載せない
/// （`JSONEncoder` は nil を省くため、「触らない」がそのまま表せる）。
struct ProfilePatch: Encodable {
    var username: String?
    var displayName: String?
    var bio: String?
    var website: String?
    var instagram: String?
    var statusText: String?
    /// 居住地。空文字は「消す」、`nil` は「触らない」
    var homeLocation: String?
    var themeColor: String?
    /// プロフィールのBGM。**一覧ごと送る**（サーバーは配列を丸ごと受ける）。
    ///
    /// ⚠️ **持っているぶんを全部入れて送ること。** Web 版は最大5曲の
    /// プレイリストを持てるので、アプリが1曲だけ送ると**残りが消える**。
    /// `nil` は「触らない」、`[]` は「全部消す」。
    var songs: [Photo.Song]?
    /// **配列ごと送らない。** サーバーは「1枚単位の増減」で受ける
    /// （`userProfile.ts` の `pinOp`）。配列を送ると、PC のタブを開いたまま
    /// スマホで留めたときに**古い配列で上書き**して、片方の操作が消える。
    var pinnedPhotoIds: [String]?
    /// 留める／外す写真（1枚）。`pin` と対で送る。
    var pinPhotoId: String?
    var pin: Bool?
    /// 名前の横に出すバッジ。**持っている鍵か「外す」（`Clearable(nil)` → JSON の null）**。
    /// `nil` は「触らない」
    var displayBadge: Clearable<String>?
    /// Pro マークの形（`iris` / `plate`）。Pro の人だけが送る
    var proMarkStyle: String?
    /// 光と天気の知らせを受け取るか（Pro・2026-10-09）。**真偽だけ**（サーバーは文字の "false" を 400 で断る）。
    /// `nil` は「触らない」
    var lightAlert: Bool?
}
