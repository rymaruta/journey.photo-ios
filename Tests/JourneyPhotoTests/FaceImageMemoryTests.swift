import XCTest
import SwiftUI
import UIKit
@testable import JourneyPhoto

/// 人の顔を、アプリを開いている間だけ URL ごとにメモリに覚える直し（2026-11-28・札 #594 の2回目）の試験。
/// 前は `RemoteImage`（`AsyncImage`）で、顔の画像が `no-store` なので顔が出るたびに通信し直していた
@MainActor
final class FaceImageMemoryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FaceImage.memory.removeAll()
    }

    override func tearDown() {
        FaceImage.memory.removeAll()
        super.tearDown()
    }

    private func url(_ name: String) throws -> URL {
        try XCTUnwrap(URL(string: "https://journey-photo.com/profile/\(name).jpg"))
    }

    /// 🔴 顔は写真の格子と同じ読み込みの部品で、顔の控えを使う（`AsyncImage` に戻すと落ちる）
    func testFaceUsesTheSharedLoaderWithTheFaceMemory() throws {
        let face = FaceImage(url: try url("a"))
        let image = try XCTUnwrap(face.body as Any as? DownsampledRemoteImage, "顔が控えのある読み込みの部品ではない")
        XCTAssertTrue(image.imageMemory === FaceImage.memory, "顔が顔の控えを使っていない")
        XCTAssertFalse(image.imageMemory === DownsampledRemoteImage.memory, "顔が写真の控えを食う")
        XCTAssertEqual(image.placeholderSymbol, RemoteImage.personSymbol, "顔の無い人に人の影が出ない")
        XCTAssertEqual(image.contentMode, .fill)
        XCTAssertEqual(image.url, try url("a"))
        // 写真の部品の既定は今までどおり
        XCTAssertEqual(DownsampledRemoteImage(url: nil).placeholderSymbol, "photo")
        XCTAssertTrue(DownsampledRemoteImage(url: nil).imageMemory === DownsampledRemoteImage.memory)
    }

    /// 🔴 同じ URL は覚えた顔を返す。URL が替われば（相手が顔を替えた）覚えていない＝取りに行く
    func testSameURLIsRememberedAndANewURLIsFetched() throws {
        let old = try url("u1-v1"), new = try url("u1-v2")
        FaceImage.memory.store(UIImage(), pixels: 256, for: old, cost: 256 * 256 * 4)
        XCTAssertNotNil(FaceImage.memory.entry(for: old, atLeast: 256), "同じ URL の顔をもう一度取りに行く")
        XCTAssertNil(FaceImage.memory.entry(for: new, atLeast: 256), "替わった URL に前の顔を出す")
    }

    /// 🔴 控えは件数で切る（上限の数を持つ）。上限を超えて入れても上限より多くは持たない
    func testMemoryHasACountLimit() throws {
        XCTAssertEqual(FaceImage.memoryCountLimit, 200)
        let small = DecodedImageMemory<UIImage>(costLimit: 1024 * 1024, countLimit: 2)
        let urls = try (0..<5).map { try url("count-\($0)") }
        for item in urls { small.store(UIImage(), pixels: 256, for: item, cost: 1) }
        let kept = urls.filter { small.entry(for: $0) != nil }.count
        XCTAssertLessThanOrEqual(kept, 2, "件数の上限を超えて持っている")
        XCTAssertGreaterThan(kept, 0)
    }

    /// 🔴 ログアウトで顔の控えも空にする（次の人に残さない）
    func testSignOutClearsTheFaceMemory() throws {
        let face = try url("signed-out")
        FaceImage.memory.store(UIImage(), pixels: 256, for: face, cost: 1)
        XCTAssertNotNil(FaceImage.memory.entry(for: face), "下ごしらえ: 控えに入る")
        AuthStore().settleSignedOut()
        XCTAssertNil(FaceImage.memory.entry(for: face), "ログアウトしても顔の控えが残っている")
    }
}
