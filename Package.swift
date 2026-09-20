// swift-tools-version: 5.9
//
// **Xcode のプロジェクトはこれではない**（`project.yml` から XcodeGen が作る）。
// ここは「画面を持たない層」だけを切り出したパッケージで、目的はひとつ:
//
//     Xcode の無い環境（Linux）でも、この層を**本当に型検査して、
//     テストを走らせる**。
//
//     swift build && swift test
//
// SwiftUI・UIKit・ImageIO・Amplify に触るファイルは入れていない
// （Linux に無いため）。つまり**これが緑でも、画面側は検査されていない**。
// 画面側は `Tools/verify.sh` の構文・参照検査までしか見られない。
import PackageDescription

let package = Package(
    name: "JourneyPhoto",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "JourneyPhoto", targets: ["JourneyPhoto"]),
    ],
    targets: [
        .target(
            name: "JourneyPhoto",
            path: "Sources/JourneyPhoto",
            // 画面・認証・画像処理は SwiftUI / UIKit / ImageIO / Amplify に
            // 触るので Linux では扱えない。**入っていない＝検査されていない**
            exclude: [
                "App",
                "Features",
                "Resources",
                "Assets.xcassets",
                "Core/Auth",
                "Core/Storage/FavoritesStore.swift",
                "Core/Storage/ModerationStore.swift",
                "Services/ImagePreparer.swift",
            ],
            // **足すときはここにも足す。** 入れ忘れたファイルは
            // Linux では一度も型検査されない
            sources: [
                "Config/AppConfig.swift",
                "Core/Networking",
                "Core/Text",
                "Core/Storage/PhotoSnapshotStore.swift",
                "Models",
                "Services/AccountService.swift",
                "Services/AlbumService.swift",
                "Services/ModerationService.swift",
                "Services/NotificationService.swift",
                "Services/PhotoService.swift",
                "Services/ProfileService.swift",
                "Services/PublicGalleryService.swift",
                "Services/SocialService.swift",
                "Services/StoryService.swift",
                "Services/UploadService.swift",
                "Services/UserSearchService.swift",
            ]
        ),
        .testTarget(
            name: "JourneyPhotoTests",
            dependencies: ["JourneyPhoto"],
            path: "Tests/JourneyPhotoTests"
        ),
    ]
)
