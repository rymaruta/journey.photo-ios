import XCTest
@testable import JourneyPhoto
import UIKit

/// 利用者から黙って失敗に見えた所・重かった所の直し（2026-10-21）。
/// 画面は Linux で描けないので、決まりは型で、配線は文で見る
final class QuietFailuresTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `start` から `end` の手前までを切り出す
    private func slice(_ text: String, from start: String, to end: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let s = text.range(of: start) else {
            XCTFail("「\(start)」が無い", file: file, line: line)
            return ""
        }
        guard let e = text.range(of: end, range: s.upperBound..<text.endIndex) else {
            XCTFail("「\(end)」が無い", file: file, line: line)
            return ""
        }
        return String(text[s.lowerBound..<e.lowerBound])
    }

    private func photo(_ id: String, owner: String = "me", extra: String = "") throws -> Photo {
        try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"\#(id)","src":"/u/\#(id).jpg","userId":"\#(owner)"\#(extra)}"#.utf8))
    }

    // MARK: - 1. コメントの失敗は入力欄のすぐ上

    func testComposerShowsCommentFailureAboveTheField() throws {
        let view = try source("Features/PhotoDetail/PhotoDetailView.swift")
        let composer = slice(view, from: "private var composer: some View {", to: "TextField(L(\"コメントを書く\"")
        XCTAssertTrue(composer.contains("model.commentPostError"), "入力欄の近くに送れなかったことを出していない")
        XCTAssertTrue(composer.contains("WebTheme.danger"), "失敗の色は danger")
        XCTAssertTrue(composer.contains(".font(JPFont.footnote)"), "失敗の字は JPFont の 13pt")
    }

    // MARK: - 2. ストーリー作成の下の並び

    /// 並びの絵は**縮めた `thumb`**（`StripThumb`）。1920px の `preview` を並べない
    func testStoryStripUsesSmallThumbs() throws {
        let view = try source("Features/Stories/StoryComposerView.swift")
        let thumb = slice(view, from: "private func thumb(_ shot: StoryShot, index: Int)", to: "private func move(from: Int, to: Int)")
        XCTAssertTrue(thumb.contains("shot.thumb"))
        XCTAssertFalse(thumb.contains("shot.preview"), "並びに原寸の絵を使っている")
        XCTAssertTrue(view.contains("StripThumb.image(for: prepared)"), "投稿の帯と同じ縮め方を使っていない")
        // 選んだ写真・下書きから戻した写真の両方で作る
        XCTAssertTrue(view.contains("startThumb(for: shot)"))
        XCTAssertTrue(view.contains("shots.forEach(startThumb(for:))"))
    }

    /// 縮める元は一覧用のサムネ（あれば）。作るのは渡した口（投稿の帯と同じ）
    func testStripThumbImageUsesTheSmallSource() async {
        final class Received: @unchecked Sendable { var data: [Data] = [] }
        let received = Received()
        var prepared = ImagePreparer.Prepared(data: Data([1]), fileName: "a.jpg", contentType: "image/jpeg",
                                              exif: nil, coords: nil, takenOn: nil)
        prepared.thumbnail = Data([2, 2])
        let image = await StripThumb.image(for: prepared) { data in
            received.data.append(data)
            return UIImage()
        }
        XCTAssertNotNil(image)
        XCTAssertEqual(received.data, [Data([2, 2])], "1920px の本体から作った")
    }

    // MARK: - 3. 乗車券の写真選び

    /// 🔴 読めなかったら**0枚と言わず、選んだ写真も外さない**
    func testCardPickKeepsSelectionWhenLoadFails() throws {
        let before = [try photo("p1")]
        let failed = PassCardLoad.pick(fetched: nil, me: "me", selected: "p1", current: before)
        XCTAssertTrue(failed.failed, "読めなかったのを0枚と同じに扱っている")
        XCTAssertEqual(failed.selected, "p1", "読めなかったのに選んだ写真を外した")
        XCTAssertEqual(failed.photos.map(\.id), ["p1"])

        // 本当に0枚なら失敗ではない（選んだ写真が公開一覧から消えたら外す）
        let empty = PassCardLoad.pick(fetched: [], me: "me", selected: "p1", current: before)
        XCTAssertFalse(empty.failed)
        XCTAssertNil(empty.selected)
        XCTAssertTrue(empty.photos.isEmpty)

        // 読めたら自分の公開の写真だけ。選んでいなければ先頭
        let loaded = PassCardLoad.pick(fetched: [try photo("x", owner: "other"), try photo("p2"),
                                                 try photo("p3", extra: #","audience":"followers""#)],
                                       me: "me", selected: nil, current: [])
        XCTAssertEqual(loaded.photos.map(\.id), ["p2"])
        XCTAssertEqual(loaded.selected, "p2")
    }

    /// 失敗の時は読み直しのボタン（`ErrorBanner` の retry）を出す
    func testCardPickShowsRetryOnFailure() throws {
        let view = try source("Features/Pass/PassCardPickView.swift")
        let grid = slice(view, from: "private var grid: some View {", to: "private var photoGrid: some View {")
        let failed = slice(grid, from: "} else if loadFailed {", to: "} else if photos.isEmpty {")
        XCTAssertTrue(failed.contains("ErrorBanner("))
        XCTAssertTrue(failed.contains("retryPhotos()"), "読み直しのボタンが無い")
        XCTAssertFalse(failed.contains("全体に公開している写真がありません"))
    }

    // MARK: - 4. すれちがいの設定

    func testSettingsKeepsCardPhotoWhenLoadFails() throws {
        let shown = try photo("p1")
        let failed = PassCardLoad.cardPhoto(id: "p1", fetched: nil, previous: shown)
        XCTAssertEqual(failed.photo?.id, "p1", "読めなかったのに写真を消した")
        XCTAssertTrue(failed.failed)
        // 別の写真を選び直した後に読めなかったら、前の写真は出さない
        XCTAssertNil(PassCardLoad.cardPhoto(id: "p2", fetched: nil, previous: shown).photo)
        // 読めて無かった（非公開にした）なら nil・失敗ではない
        let gone = PassCardLoad.cardPhoto(id: "p1", fetched: [], previous: shown)
        XCTAssertNil(gone.photo)
        XCTAssertFalse(gone.failed)
        XCTAssertFalse(PassCardLoad.cardPhoto(id: nil, fetched: nil, previous: shown).failed)

        let view = try source("Features/Pass/PassSettingsView.swift")
        XCTAssertTrue(view.contains("PassCardLoad.cardPhoto("))
        XCTAssertTrue(view.contains("if cardLoadFailed {"), "読めなかったことを行に出していない")
    }

    // MARK: - 5. ホームの大きい枠

    func testHomeLargeTileIsDownsampled() throws {
        let view = try source("Features/Gallery/HomeMosaic.swift")
        let tile = slice(view, from: "struct HomeFeedTile: View {", to: ".overlay(alignment: .bottomLeading) { caption }")
        XCTAssertTrue(tile.contains("DownsampledRemoteImage(url: photo.detailImageURL, contentMode: .fill"),
                      "大きい枠を原寸で読んでいる")
        XCTAssertTrue(tile.contains("aspectRatio: photo.aspectRatio"), "縦横比を渡さないと縦長の写真がぼやける")
        XCTAssertFalse(tile.contains("RemoteImage(url: large ?"), "大きい枠に AsyncImage が残っている")
    }

    /// 枠を覆う大きさ×倍率で読む（16:9 の枠 390pt・3倍に縦長 3:4 の写真 → 長い辺は 520pt×3 以上）
    func testFillPixelsCoverTheBoxWithoutBlur() throws {
        let box = CGSize(width: 390, height: 390 * 9 / 16)
        let pixels = try XCTUnwrap(DownsampledImageSize.pixels(filling: box, scale: 3, aspectRatio: 0.75))
        XCTAssertGreaterThanOrEqual(pixels, 1560)
    }

    // MARK: - 7. 自分の写真の削除（動きは `ViewModelTests.testPhotoDeleteTwiceSendsOnce`）

    func testPhotoDeleteGoesThroughTheGuard() throws {
        let view = try source("Features/PhotoDetail/PhotoDetailView.swift")
        let delete = slice(view, from: "private func deletePhoto() async {", to: "case .failed(let error):")
        XCTAssertTrue(delete.contains("model.deletePhoto(photoId, photos: environment.photos)"),
                      "守りを通さずに送っている")
        XCTAssertFalse(delete.contains("environment.photos.delete("))
        XCTAssertTrue(view.contains(".disabled(model.deletingPhotoIds.contains(current.id))"))
    }

    // MARK: - 6. アルバム作成のボタン

    /// 作っている間は**どの「アルバムを作る」も押せない**（`create` は黙って断るので）
    func testAlbumCreateButtonsDisableWhileCreating() throws {
        let view = try source("Features/Albums/AlbumsView.swift")
        let button = slice(view, from: "private var createButton: some View {", to: "private var joinCard: some View {")
        XCTAssertTrue(button.contains(".disabled(model.isCreating)"), "主ボタンが送信中も押せる")
        let empty = slice(view, from: "EmptyState(title: L(\"まだアルバムがありません\"", to: ".profileListRow()")
        XCTAssertTrue(empty.contains(".disabled(model.isCreating)"), "空の状態のボタンが送信中も押せる")
        let menu = slice(view, from: "Button(L(\"アルバムを作る\", \"New album\")) { showCreate = true }",
                         to: "Button(L(\"招待リンクから参加\"")
        XCTAssertTrue(menu.contains(".disabled(model.isCreating)"))
    }

    // MARK: - 8. 通知の案内画面

    func testPushPrimerKeepsKnownProWhenProfileFails() throws {
        XCTAssertTrue(PushPrimerPoint.resolvedPro(loaded: nil, known: true), "読めなかったのに Pro でないことにした")
        XCTAssertFalse(PushPrimerPoint.resolvedPro(loaded: nil, known: false), "分からない時は Pro 向けでない文")
        XCTAssertFalse(PushPrimerPoint.resolvedPro(loaded: false, known: true))
        XCTAssertTrue(PushPrimerPoint.resolvedPro(loaded: true, known: false))
        let view = try source("Features/Settings/PushPrimerView.swift")
        XCTAssertTrue(view.contains("PushPrimerPoint.resolvedPro(loaded:"))
        XCTAssertFalse(view.contains("?.isPro ?? false"), "読めないと false に倒している")
    }
}
