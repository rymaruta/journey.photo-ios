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
    let notifications: NotificationService
    let moderation: ModerationService
    let account: AccountService
    let albums: AlbumService
    let stories: StoryService
    let search: UserSearchService
    let discovery: DiscoveryService

    init(tokenProvider: TokenProviding = CognitoTokenProvider()) {
        let api = APIClient(tokenProvider: tokenProvider)
        self.api = api
        self.gallery = PublicGalleryService()
        self.photos = PhotoService(api: api)
        self.profiles = ProfileService(api: api)
        self.uploads = UploadService(api: api)
        self.social = SocialService(api: api)
        self.notifications = NotificationService(api: api)
        self.moderation = ModerationService(api: api)
        self.account = AccountService(api: api)
        self.albums = AlbumService(api: api)
        self.stories = StoryService(api: api)
        self.search = UserSearchService(api: api)
        self.discovery = DiscoveryService(api: api)
    }
}
