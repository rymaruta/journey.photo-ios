import XCTest
import SwiftUI
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿の欄が書く写真1枚への窓（`UploadViewModel.photoBinding`・2026-11-15・札 #616）。
///
/// 🔴 題を打ったまま（キーボードが出たまま）「投稿する」を押すと、上がった写真が `items` から外れたあとに
/// 欄が字を確定させ、`ForEach($model.items)` の番号で引く窓が外れた番号を読んでアプリが落ちた
/// （Mac run 1364・1365 の落ちた記録: `PlatformTextFieldCoordinator.textChanged` → `Binding<A>.subscript.getter`
/// → `Array._checkSubscript`）。窓を id で引き、外れた写真は読めても落ちない・書いても何も起きないことを見る
@MainActor
final class UploadPhotoBindingTests: XCTestCase {

    private func pending(title: String = "") -> PendingPhoto {
        var photo = PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data([0xff]), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))
        photo.title = title
        return photo
    }

    private func model() -> UploadViewModel {
        // 通信はしない（窓だけを見る）。背景の転送（`BackgroundTransfer.shared`）に触れないよう、使い捨ての通信を渡す
        let session = URLSession(configuration: .ephemeral)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        return UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                               photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
    }

    /// 投稿して並びから外れた写真の窓を、欄が字の確定で読む・書く（落ちた道そのもの）
    func testRemovedPhotoCanStillBeReadAndWrittenWithoutCrashing() async {
        let model = model()
        let photo = pending(title: "秋の兼六園")
        model.items = [photo]
        let binding = model.photoBinding(photo)
        model.items.removeAll { $0.id == photo.id }   // 上がった写真を外す（`submit` の終わり）

        XCTAssertEqual(binding.wrappedValue.title, "秋の兼六園", "外れた写真は最後に描いた値を返す")
        binding.wrappedValue.title = "秋の兼六園。"     // 欄が字を確定させる
        XCTAssertTrue(model.items.isEmpty, "外れた写真への書き込みで並びに写真を戻さない")
    }

    /// 並びの番号が変わっても（前の写真を外した）、同じ写真を読み書きする
    func testBindingFollowsThePhotoByIdNotIndex() async {
        let model = model()
        let first = pending(title: "1枚目")
        let second = pending(title: "2枚目")
        model.items = [first, second]
        let binding = model.photoBinding(second)
        model.items.removeAll { $0.id == first.id }

        XCTAssertEqual(binding.wrappedValue.title, "2枚目")
        binding.wrappedValue.title = "直した題"
        XCTAssertEqual(model.items.map(\.title), ["直した題"])
    }

    /// 投稿の画面は欄に番号で引く窓（`ForEach($model.items)`）を渡さない
    func testUploadViewDoesNotBindFieldsByIndex() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Upload/UploadView.swift"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("ForEach($model.items)"),
                       "番号で引く窓に戻すと、題を打ったまま投稿したときに落ちる（札 #616）")
        XCTAssertTrue(text.contains("model.photoBinding(item)"))
    }
}
