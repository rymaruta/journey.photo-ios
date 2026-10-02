import XCTest
@testable import JourneyPhoto

/// 🔴 前の旅の写真を、次の投稿に混ぜない（`TripImportHandoff`）。
/// 読み込みの途中で旅の流れを閉じたあとに写真が届き、次の「写真を投稿」や
/// 今日のテーマの投稿に並んでいた（しかも非公開で始まる）
final class TripImportHandoffTests: XCTestCase {

    private let photos = [Data([1]), Data([2])]

    /// 流れが開いている間に届いた写真は受ける
    func testReceivedWhileOpen() {
        XCTAssertEqual(TripImportHandoff.received(photos, flowOpen: true), photos)
    }

    /// 閉じたあとに届いた写真は捨てる
    func testDroppedAfterClose() {
        XCTAssertEqual(TripImportHandoff.received(photos, flowOpen: false), [], "閉じたあとの写真を控えた")
    }

    /// 投稿画面へ控えを渡すのは旅の流れから開くときだけ
    func testOnlyTheTripFlowPassesPhotos() {
        XCTAssertEqual(TripImportHandoff.photosForUpload(opener: .tripFlow, pending: photos), photos)
        XCTAssertEqual(TripImportHandoff.photosForUpload(opener: .photo, pending: photos), [],
                       "ふつうの写真投稿に前の旅の写真が並ぶ")
        XCTAssertEqual(TripImportHandoff.photosForUpload(opener: .theme, pending: photos), [],
                       "今日のテーマの投稿に前の旅の写真が並ぶ")
    }
}
