import Foundation

/// iPhone のカメラ・メッセージ・Safari で journey-photo.com のリンクを押したとき、アプリで開く行き先
/// （Universal Links・2026-11-20 札 #661 / #664、札 #545 の段2）。
///
/// **受ける道は、サイトの `/.well-known/apple-app-site-association` の `applinks` と同じにする。**
/// AASA に載っているのにここで受けない道は、アプリが開いて何も出ない（いちばん困る壊れ方）。
/// 足し引きするときは両方（Web は `scripts/__tests__/appSiteAssociation.test.ts` が同じ表を持つ）。
/// - 人の頁 `/users?id=<id>`・`/users/<id>`、更新できる QR `/qr?t=<合図>` は `ProfileQRLink.parse`（アプリの中の
///   QR の読み取りと同じ1か所）で見分ける。iPhone のカメラで人の QR を読んだときもここを通る（札 #664）
/// - 写真の頁 `/photo/<id>`
/// - 観光スポットの頁 `/spots/<slug>`（一覧の頁 `/spots/sakura` などと、`/spots/<地方>/<…>` の下の階層は受けない）
/// - 旅行プラン（`/trips`・`/t?t=`）と共同アルバムの招待（`/j?t=`）は、アプリに受ける口がまだ無いので受けない
///   （2026-11-20 判断: AASA からも外し、Safari で開くままにする）
enum AppLink: Equatable {
    case person(String)
    case pass(String)
    case photo(String)
    case spot(String)

    /// `/spots/` の下にある、観光スポットの頁ではない1段の頁（Web の `app/spots/sakura` など）。
    /// AASA の `exclude` と同じ。2段より深い道（`/spots/area/kanto` など）は段の数で外す
    static let notSpots: Set<String> = ["sakura", "momiji", "snow"]

    static func parse(_ url: URL, base: URL = AppConfig.siteBaseURL) -> AppLink? {
        // 人の頁・QR の合図は、アプリの中の QR の読み取りと同じ所で見分ける（家の確かめもそこ）
        switch ProfileQRLink.parse(url.absoluteString, base: base) {
        case .person(let id)?: return .person(id)
        case .pass(let pass)?: return .pass(pass)
        case nil: break
        }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = parts.host?.lowercased(), ProfileQR.knownHosts(base: base).contains(host)
        else { return nil }
        let segments = parts.path.split(separator: "/").map(String.init)
        guard segments.count == 2, let value = segments[1].removingPercentEncoding, PathID.isSafe(value)
        else { return nil }
        switch segments[0] {
        case "photo": return .photo(value)
        case "spots" where !notSpots.contains(value): return .spot(value)
        default: return nil
        }
    }

    /// ホームに積む画面（`TabRouter.openOnHome`）。自分の人の頁かは、積むとき（ホームが受け取るとき）に見る——
    /// 冷えた起動ではログインの確認が終わる前にリンクが届く
    var homeScreen: HomeScreenRequest {
        switch self {
        case .person(let id): return .person(userId: id)
        case .pass(let pass): return .profilePass(pass)
        case .photo(let id): return .photo(id: id)
        case .spot(let slug): return .officialSpot(slug: slug)
        }
    }
}

/// リンクで開いた写真・合図が引けなかったときの一言（`GalleryView.openRequestedScreen`）
enum AppLinkText {
    static var photoMissing: String {
        L("写真が見つかりませんでした。削除されたか、公開をやめた写真です",
          "Couldn't find this photo. It may have been deleted or made private")
    }
    static var photoCheckFailed: String {
        L("写真を読み込めませんでした。電波のよい所でもう一度開いてください",
          "Couldn't load this photo. Try opening the link again with a better connection")
    }
}

/// リンクで開いた写真を引き当てる（`/photo/<id>`・2026-11-20 札 #661）。写真1枚の公開の口は無いので、
/// 通知を押したとき（`NotificationsViewModel.findPhoto`）と同じく、公開一覧と自分の写真から探す。
/// 控えに無ければ一度だけ取り直す。どちらも取れなければ `failed`（圏外で「見つからない」と言わない）
enum AppLinkPhoto {
    enum Outcome: Equatable {
        case found(Photo, fromPublicFeed: Bool)
        case missing
        case failed
    }

    static func find(_ id: String, mine: [Photo], load: (Bool) async throws -> [Photo]) async -> Outcome {
        var loaded = false
        for force in [false, true] {
            let photos: [Photo]? = try? await load(force)
            if let photos {
                loaded = true
                if let photo = photos.first(where: { $0.id == id }) { return .found(photo, fromPublicFeed: true) }
            }
            // 自分の写真（下書き・範囲を絞った写真は公開一覧に無い）。取り直す前に見る
            let own = force ? nil : mine.first(where: { $0.id == id })
            if let own { return .found(own, fromPublicFeed: false) }
        }
        return loaded ? .missing : .failed
    }
}
