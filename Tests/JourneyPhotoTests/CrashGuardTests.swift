import XCTest
import ImageIO
@testable import JourneyPhoto

/// 壊れたデータ・設定ミスで落ちる所と、共有の再生器の止め方
/// （バグ探し 2026-09-27 の L-16・C-1・C-2・C-3）。
final class CrashGuardTests: XCTestCase {

    // MARK: - ピン留めの重複（C-1）

    private func photo(_ id: String) -> Photo {
        let json = #"{"id":"\#(id)","src":"https://x/\#(id).jpg"}"#
        return try! JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    /// 🔴 **同じ id が2回留めてあっても、1枚だけ前へ**（2枚並ぶと格子の id が重なる）
    func testDuplicatePinnedIdsDoNotDuplicatePhotos() {
        let photos = ["a", "b", "c"].map(photo)
        let ordered = PhotoPinning.pinnedFirst(photos, pinned: ["c", "c", "b"])
        XCTAssertEqual(ordered.map(\.id), ["c", "b", "a"], "同じ写真を2枚並べている")
    }

    // MARK: - EXIF の値（C-3）

    /// 🔴 **無限大・桁あふれの露出と焦点距離で落ちない**（出さないだけ）
    func testExtremeExifValuesDoNotTrap() {
        let tiny = ImagePreparer.readExif(from: [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 1e-320,
                kCGImagePropertyExifFocalLength: Double.infinity,
            ] as [CFString: Any],
        ])
        XCTAssertNil(tiny.exposure)
        XCTAssertNil(tiny.focalLength)
        let huge = ImagePreparer.readExif(from: [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifFocalLength: 1e30,
            ] as [CFString: Any],
        ])
        XCTAssertNil(huge.focalLength)
    }

    /// ふつうの値は今までどおり出す
    func testUsualExifValuesStillShow() {
        let fields = ImagePreparer.readExif(from: [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 0.004,
                kCGImagePropertyExifFocalLength: 26.0,
            ] as [CFString: Any],
        ])
        XCTAssertEqual(fields.exposure, "1/250")
        XCTAssertEqual(fields.focalLength, "26mm")
    }

    // MARK: - 曲選びを閉じたとき（L-16）

    /// 🔴 **止めるのは曲選びで鳴らした曲だけ**（前から鳴っていた BGM は止めない）
    func testClosingSongPickerStopsOnlyItsOwnPreview() {
        XCTAssertTrue(SongPickerText.stopsOnClose(playingFrom: .songPicker))
        XCTAssertFalse(SongPickerText.stopsOnClose(playingFrom: .app), "前から鳴っていた曲まで止めている")
        XCTAssertFalse(SongPickerText.stopsOnClose(playingFrom: nil))
    }

    // MARK: - ログインの設定に失敗した起動（C-2）

    /// 🔴 **設定できていなければ Amplify を呼ばない**（未ログイン扱い・ログインは断る）。
    /// Mac の単体テストは宿主のアプリが起動時に `configure()` を済ませるので、
    /// ここで未設定に倒して「設定に失敗した起動」を作る（終わったら戻す）
    func testUnconfiguredGatewayDoesNotCallAmplify() async {
        let wasConfigured = AuthGateway.isConfigured
        AuthGateway.isConfigured = false
        defer { AuthGateway.isConfigured = wasConfigured }
        let signedIn = await AuthGateway.isSignedIn()
        XCTAssertFalse(signedIn)
        let token = try? await AuthGateway.idToken()
        XCTAssertNil(token ?? nil)
        do {
            _ = try await AuthGateway.signIn(email: "a@example.com", password: "x")
            XCTFail("未設定のままログインを通している")
        } catch {
            XCTAssertTrue(error is AuthGateway.NotConfigured, "\(error)")
        }
    }
}
