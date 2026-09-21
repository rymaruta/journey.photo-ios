import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 撮影スポットの台帳を取る。
///
/// **写真と同じ形**（`PublicGalleryService`）——静的サイトに置かれた JSON を
/// 読むだけで、スポットのための API は無い。台帳は写真ほど頻繁に変わらないので
/// 控えは長め（10分）。
actor SpotService {

    private let url: URL
    private let session: URLSession
    private var cached: [Spot]?
    private var cachedAt: Date?
    static let cacheLifetime: TimeInterval = 600

    init(url: URL = AppConfig.publicSpotsURL, session: URLSession? = nil) {
        self.url = url
        self.session = session ?? URLSession(configuration: .default)
    }

    /// 台帳の全件。**取れなければ空**を返す（画面は「まだ無い」と出す）。
    ///
    /// 写真と違い、台帳が取れないことは致命ではない——写真の一覧は
    /// 撮影地の文字列だけで今までどおり動く。だからここで例外を投げて
    /// 画面を止めない。
    func fetchSpots(force: Bool = false) async -> [Spot] {
        if !force, let cached, let cachedAt,
           Date().timeIntervalSince(cachedAt) < Self.cacheLifetime {
            return cached
        }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let spots = try? JSONDecoder.api.decode([Spot].self, from: data) else {
            return cached ?? []
        }
        cached = spots
        cachedAt = Date()
        return spots
    }
}
