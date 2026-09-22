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
        // **SDK の模型。** Linux には SwiftUI も UIKit も無いので、
        // 使っている口の「形」だけを宣言したモジュールを置き、画面のコードを
        // そこへ向けて型検査する。実機のビルドには**一切入らない**
        // （Xcode は project.yml から作られ、この Package を見ない）。
        //
        // **これが通っても「SwiftUI として正しい」とは言えない。**
        // 修飾子はどれも素通しなので、SwiftUI 側の制約は見ていない。
        // 見えるのは自分たちのコードの誤り——綴り違い・無いプロパティ・
        // 引数ラベルの不一致・型の取り違え。
        .target(name: "Combine", path: "Shims/Combine"),
        .target(name: "SwiftUI", dependencies: ["Combine"], path: "Shims/SwiftUI"),
        .target(name: "UIKit", dependencies: ["SwiftUI"], path: "Shims/UIKit"),
        .target(name: "PhotosUI", dependencies: ["SwiftUI"], path: "Shims/PhotosUI"),
        .target(name: "CoreLocation", path: "Shims/CoreLocation"),
        .target(name: "MapKit", dependencies: ["SwiftUI", "CoreLocation"], path: "Shims/MapKit"),
        .target(name: "AVFoundation", path: "Shims/AVFoundation"),
        .target(name: "AVKit", dependencies: ["SwiftUI", "AVFoundation"], path: "Shims/AVKit"),
        .target(name: "UserNotifications", path: "Shims/UserNotifications"),
        .target(name: "ImageIO", path: "Shims/ImageIO"),
        .target(name: "UniformTypeIdentifiers", path: "Shims/UniformTypeIdentifiers"),
        .target(name: "Amplify", path: "Shims/Amplify"),
        .target(name: "AWSCognitoAuthPlugin", dependencies: ["Amplify"], path: "Shims/AWSCognitoAuthPlugin"),
        .target(name: "AWSPluginsCore", dependencies: ["Amplify"], path: "Shims/AWSPluginsCore"),

        // **アプリ全体**を模型に向けて型検査する。
        //
        // 画面だけを別モジュールにすると、同じモジュール内の型
        // （`APIClient` など internal）が見えない——iOS では1つのモジュール
        // なので、**1つの target に全部入れる**。
        .target(
            name: "JourneyPhoto",
            dependencies: [
                "SwiftUI", "Combine", "UIKit", "PhotosUI", "MapKit", "CoreLocation",
                "AVFoundation", "AVKit", "ImageIO", "UniformTypeIdentifiers", "UserNotifications",
                "Amplify", "AWSCognitoAuthPlugin", "AWSPluginsCore",
            ],
            path: "Sources/JourneyPhoto",
            exclude: ["Resources", "Assets.xcassets"]
        ),
        .testTarget(
            name: "JourneyPhotoTests",
            dependencies: ["JourneyPhoto"],
            path: "Tests/JourneyPhotoTests"
        ),
    ]
)
