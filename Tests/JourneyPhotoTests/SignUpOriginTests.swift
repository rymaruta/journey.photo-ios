import XCTest
import Amplify
import AWSCognitoAuthPlugin
@testable import JourneyPhoto

/// 登録の確認に付ける `ClientMetadata`（journey.photo-ios#432・2026-11-04）
final class SignUpOriginTests: XCTestCase {

    /// photo-gallery `api/src/cognitoTrigger.ts` の `SIGNUP_PLATFORMS` / `SIGNUP_FROMS`（2026-11-04 の origin/main）。
    /// 範囲外の値はサーバーが `unknown` に丸めて数えられなくなる。サーバー側が変わったらここも合わせる
    private let serverPlatforms: Set<String> = ["web", "ios"]
    private let serverFroms: Set<String> = ["wish", "other"]

    func testValuesAreInsideWhatTheServerAccepts() {
        let meta = AuthGateway.SignUpOrigin.clientMetadata
        XCTAssertTrue(serverPlatforms.contains(meta["platform"] ?? ""), "platform がサーバーの範囲外")
        XCTAssertTrue(serverFroms.contains(meta["from"] ?? ""), "from がサーバーの範囲外")
        XCTAssertEqual(meta["platform"], "ios")
    }

    /// キーは platform と from の2つだけ。メール・名前・UUID を入れる余地を作らない
    func testOnlyFixedKeysAndNoPersonalValues() {
        let meta = AuthGateway.SignUpOrigin.clientMetadata
        XCTAssertEqual(Set(meta.keys), ["platform", "from"])
        for value in meta.values {
            XCTAssertFalse(value.contains("@"), "メールらしい値が入っている")
            XCTAssertNil(UUID(uuidString: value), "UUID が入っている")
            XCTAssertLessThanOrEqual(value.count, 8, "決まった短い値ではない")
        }
    }

    /// Amplify に渡す options の中身が `AWSAuthConfirmSignUpOptions.metadata` として読める
    /// （本物のプラグインは `pluginOptions as? AWSAuthConfirmSignUpOptions` の `metadata` を ClientMetadata にする）
    func testConfirmOptionsCarryTheMetadata() {
        let options = AuthGateway.confirmSignUpOptions()
        let plugin = options.pluginOptions as? AWSAuthConfirmSignUpOptions
        XCTAssertNotNil(plugin, "pluginOptions が AWSAuthConfirmSignUpOptions ではない")
        XCTAssertEqual(plugin?.metadata, AuthGateway.SignUpOrigin.clientMetadata)
    }
}
