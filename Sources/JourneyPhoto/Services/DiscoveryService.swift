import Foundation

/// 投稿を書くときの補助——撮影地の候補と、曲の検索。
///
/// **どちらも認証が要る**（`api-user/serverless.yml` の authorizer）。
/// 外の API（Nominatim・iTunes）を叩く口なので、未認証で開けていない。
struct DiscoveryService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - 撮影地

    /// 地名の候補。**座標は約1kmに丸めて返る**（サーバー側で丸め済み）。
    struct Place: Decodable, Identifiable, Equatable {
        let label: String
        let lat: Double
        let lng: Double

        var id: String { "\(label)|\(lat)|\(lng)" }
        var coords: Photo.Coords { Photo.Coords(lat: lat, lng: lng) }
    }

    private struct PlaceList: Decodable { let results: [Place] }

    func searchPlaces(_ query: String) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await api.authorized(
            .get, "/geocode/search", query: ["q": trimmed], as: PlaceList.self
        ).results
    }

    private struct ReverseResult: Decodable { let place: String? }

    /// 座標から地名を引く。写真に座標だけあって地名が無いときに使う。
    func placeName(lat: Double, lng: Double) async throws -> String? {
        try await api.authorized(
            .get, "/geocode/reverse",
            query: ["lat": String(lat), "lng": String(lng), "locale": Locale.preferredAppLanguage],
            as: ReverseResult.self
        ).place
    }

    // MARK: - 曲

    /// 検索結果の1曲。`previewUrl` が無い曲はサーバー側で落としてある。
    struct Song: Decodable, Identifiable, Equatable {
        let id: String
        let title: String
        let artist: String
        let artwork: String
        let previewUrl: String
        let trackUrl: String?

        var artworkURL: URL? { URL(string: artwork) }

        /// 写真に保存する形（`api-user/src/photoUpdate.ts` の `PhotoSong`）。
        var asPhotoSong: Photo.Song {
            Photo.Song(title: title, artist: artist, artwork: artwork,
                       previewUrl: previewUrl, trackUrl: trackUrl)
        }
    }

    private struct SongList: Decodable { let results: [Song] }

    func searchSongs(_ query: String) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await api.authorized(
            .get, "/music/search", query: ["q": trimmed], as: SongList.self
        ).results
    }
}
