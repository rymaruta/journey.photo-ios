import Foundation

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

    init(tokenProvider: TokenProviding = CognitoTokenProvider()) {
        let api = APIClient(tokenProvider: tokenProvider)
        self.api = api
        self.gallery = PublicGalleryService()
        self.photos = PhotoService(api: api)
        self.profiles = ProfileService(api: api)
        self.uploads = UploadService(api: api)
    }
}
