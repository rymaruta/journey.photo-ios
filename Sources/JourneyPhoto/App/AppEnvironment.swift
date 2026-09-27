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
    /// 旅行プラン（`/user/trips`・本人だけ）
    let trips: TripPlanService

    /// - Parameter gallery: 公開一覧の出どころ。**テストで差し替えるため**に
    ///   開けてある（既定のままだと本物のサイトを叩きにいくので、
    ///   画面の頭を動かすテストが書けなかった）。
    /// - Parameter spots: 撮影スポットの索引の出どころ。同じ理由で開けてある
    /// - Parameter trips: 旅行プランの口。同じ理由で開けてある（一覧の状態の試験）
    init(tokenProvider: TokenProviding = CognitoTokenProvider(),
         gallery: PublicGalleryService = PublicGalleryService(liveURL: AppConfig.livePhotosURL),
         spots: OfficialSpotService = OfficialSpotService(),
         trips: TripPlanService? = nil) {
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
        self.trips = trips ?? TripPlanService(api: api)
    }

    /// 公開範囲を絞った写真の取り口を、公開一覧へ渡す。
    ///
    /// **ログアウトしたら外す。** 外さないと、次にこの端末を使う人の画面に
    /// 前の人あての「フォロワーのみ」が出る（控えも `setRestrictedLoader`
    /// が捨てる）。未ログインでは口そのものが 401 なので、入れない。
    ///
    /// `JourneyPhotoApp` と、人が替わったら読み直す画面（ホーム・探す）が呼ぶ。
    /// 画面は**差し替えてから読む**を自分で保証したい（`JourneyPhotoApp` の
    /// 差し替えと順番が決まっていないため）。同じ人なら2回目は何もしない。
    func applyRestrictedFeed(userId: String?) async {
        guard let userId else {
            await gallery.setRestrictedLoader(owner: nil, nil)
            return
        }
        let photos = self.photos
        await gallery.setRestrictedLoader(owner: userId) { try await photos.restrictedFeed() }
    }
}
