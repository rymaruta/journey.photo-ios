import XCTest
@testable import JourneyPhoto

/// **ストーリーを見る画面の型の入れ子の深さ**（札 #596・2026-11-14）。
///
/// 実機（TestFlight 1.1.87）でストーリーを開くと落ちた。落ちた記録の段は、`StoryViewerView.content(for:)` の
/// 具体的な型のメタデータを作る所から上の 141 段がすべて型の名前の解読の再帰で、メインスレッドのスタックを
/// 使い切っていた（`EXC_BAD_ACCESS`・スタックの見張りの領域）。解読の再帰の深さは、型の名前の入れ子の深さで決まる。
///
/// 直しは、大きい塊を型の境目（`storyTypeBoundary`・`AnyView`）で切ったこと。ここでは境目で切った塊ごとの
/// 具体的な型の名前（`StoryViewerView.typeSegments`）の入れ子の深さを測り、上限を超えたら落とす。
/// 測った数は `measured storyTypeDepth` の行に出す（Mac の成果物 `build-logs` の `xcodebuild-full.log`）。
///
/// 型の名前は本物の SwiftUI でないと意味が無い（Linux の模型の修飾子は素通し）ので、深さの上限は iOS（Mac の模擬機）
/// だけで見る。Linux では数え方そのものを確かめる
@MainActor
final class StoryViewTypeDepthTests: XCTestCase {

    /// 数え方: `<`・`(` の入れ子の最大。関数の型の `->` の `>` は閉じに数えない
    func testDepthCounting() async {
        XCTAssertEqual(ViewTypeDepth.depth(of: "Swift.Int"), 0)
        XCTAssertEqual(ViewTypeDepth.depth(of: "A<B<C>, D>"), 2)
        XCTAssertEqual(ViewTypeDepth.depth(of: "T<(A<B>, C)>"), 3)
        XCTAssertEqual(ViewTypeDepth.depth(of: "F<(Swift.Int) -> ()>, G<H<I<J>>>"), 3)
    }

    /// 境目で切った塊を全部並べている（名前が重ならない・型の名前が取れる）
    func testSegmentsAreListed() async {
        let segments = StoryViewerView.typeSegments()
        XCTAssertGreaterThan(segments.count, 30)
        XCTAssertEqual(Set(segments.map(\.name)).count, segments.count)
        for segment in segments { XCTAssertFalse(segment.type.isEmpty, segment.name) }
    }

    #if os(iOS)
    /// 1つの型の深さの上限（札 #596）。直す前と直した後の数は、上の注記と `docs` ではなくここに書く:
    /// 直す前（main deb4dda69）と直した後の数は Mac の回で測って書き足す
    static let depthLimit = 24

    /// **どの塊も上限以下**。超えたら、その塊の中に境目（`storyTypeBoundary`）を足す
    func testStoryViewerSegmentsStayShallow() async {
        var worst: (name: String, depth: Int) = ("", 0)
        for segment in StoryViewerView.typeSegments() {
            let depth = ViewTypeDepth.depth(of: segment.type)
            print("measured storyTypeDepth view=StoryViewerView part=\(segment.name) depth=\(depth) length=\(segment.type.count)")
            if depth > worst.depth { worst = (segment.name, depth) }
            XCTAssertLessThanOrEqual(depth, Self.depthLimit, "\(segment.name): \(segment.type)")
        }
        print("measured storyTypeDepth view=StoryViewerView worst=\(worst.name) depth=\(worst.depth) limit=\(Self.depthLimit)")
    }

    /// ほかのストーリーの画面と、比べるための画面（実機で落ちていない）の `body` の深さを記録する。
    /// 上限は付けない（`body` の型の名前は、中の `struct` の画面の名前で止まる。その画面の中身は別に数える）
    func testRecordOtherScreens() async {
        let screens: [(String, String)] = [
            ("StoryReelView", ViewTypeDepth.bodyTypeName(StoryReelView.self)),
            ("HighlightPlayerView", ViewTypeDepth.bodyTypeName(HighlightPlayerView.self)),
            ("StoryComposerView", ViewTypeDepth.bodyTypeName(StoryComposerView.self)),
            ("StoryCameraView", ViewTypeDepth.bodyTypeName(StoryCameraView.self)),
            ("StoryCameraContent", ViewTypeDepth.bodyTypeName(StoryCameraContent.self)),
            ("StoryInsightsView", ViewTypeDepth.bodyTypeName(StoryInsightsView.self)),
            ("StoryRepliesSheet", ViewTypeDepth.bodyTypeName(StoryRepliesSheet.self)),
            ("PhotoDetailView", ViewTypeDepth.bodyTypeName(PhotoDetailView.self)),
            ("EditPhotoView", ViewTypeDepth.bodyTypeName(EditPhotoView.self)),
            ("MyPageView", ViewTypeDepth.bodyTypeName(MyPageView.self)),
            ("UserProfileView", ViewTypeDepth.bodyTypeName(UserProfileView.self)),
            ("OfficialSpotView", ViewTypeDepth.bodyTypeName(OfficialSpotView.self)),
            ("DMConversationView", ViewTypeDepth.bodyTypeName(DMConversationView.self)),
            ("RootView", ViewTypeDepth.bodyTypeName(RootView.self)),
        ]
        for (name, type) in screens {
            print("measured storyTypeDepth view=\(name) part=body depth=\(ViewTypeDepth.depth(of: type)) length=\(type.count)")
            XCTAssertFalse(type.isEmpty)
        }
    }
    #endif
}
