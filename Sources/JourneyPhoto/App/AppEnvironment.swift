import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine

/// サービス一式の置き場。画面は `@EnvironmentObject` でここから取る。
///
/// シングルトンを各所に散らかさない（テストで差し替えられなくなる）。
@MainActor
final class AppEnvironment: ObservableObject {

    let api: APIClient
    let gallery: PublicGalleryService
    let photos: PhotoService
    let profiles: ProfileService
    let uploads: UploadService
    let social: SocialService
    /// 写真の保存（ブックマーク）。**いいねとは別の入れ物**
    let saves: SaveService
    let notifications: NotificationService
    let moderation: ModerationService
    let account: AccountService
    let albums: AlbumService
    let stories: StoryService
    /// ストーリーハイライト（アーカイブを束ねた輪）
    let highlights: HighlightService
    let search: UserSearchService
    let discovery: DiscoveryService
    /// 撮影スポットの索引（静的サイトの `app/data/spots.json`）。
    /// 写真の一覧と同じく API ではない
    let spots: OfficialSpotService

    /// - Parameter gallery: 公開一覧の出どころ。**テストで差し替えるため**に
    ///   開けてある（既定のままだと本物のサイトを叩きにいくので、
    ///   画面の頭を動かすテストが書けなかった）。
    /// - Parameter spots: 撮影スポットの索引の出どころ。同じ理由で開けてある
    init(tokenProvider: TokenProviding = CognitoTokenProvider(),
         gallery: PublicGalleryService = PublicGalleryService(liveURL: AppConfig.livePhotosURL),
         spots: OfficialSpotService = OfficialSpotService()) {
        let api = APIClient(tokenProvider: tokenProvider)
        self.api = api
        self.gallery = gallery
        self.spots = spots
        self.photos = PhotoService(api: api)
        self.profiles = ProfileService(api: api)
        self.uploads = UploadService(api: api)
        self.social = SocialService(api: api)
        self.saves = SaveService(api: api)
        self.notifications = NotificationService(api: api)
        self.moderation = ModerationService(api: api)
        self.account = AccountService(api: api)
        self.albums = AlbumService(api: api)
        self.stories = StoryService(api: api)
        self.highlights = HighlightService(api: api)
        self.search = UserSearchService(api: api)
        self.discovery = DiscoveryService(api: api)
    }
}
