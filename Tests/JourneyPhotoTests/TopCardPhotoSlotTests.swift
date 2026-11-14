import XCTest
@testable import JourneyPhoto
#if os(iOS)
import SwiftUI
import UIKit
#endif

/// **ホームの上の札の背は、左の写真の縦横比で変わらない**（`TopCardPhotoSlot`・2026-11-14）。
///
/// Mac run 1321 で `testCapturesSpotSwipe` が「札の背が 116 から変わった: 149.3」で落ちた。同じアプリ（c75310a →
/// 1eecd08 は UI テストだけの差）で、1304・1317 は 116。違いは季節の札の写真だけで、花の窟神社の写真は
/// 960×1280（3:4）→ 幅 112 に合わせた背が 112×1280/960 = 149.3。並びは高さを決めずに測って背を揃えるので
/// （`HomeTopCardView` の `fixedSize(horizontal: false, vertical: true)`）、写真の背が並びの3枚の背になっていた。
/// 横長の谷川岳 一ノ倉沢（960×720）なら 84 で、最小の 116 のまま通っていた
final class TopCardPhotoSlotTests: XCTestCase {

    /// 札の面は写真を枠（`TopCardPhotoSlot`）に入れる。**写真に直に `.frame(maxHeight: .infinity)` を付ける形に戻すと落ちる**
    func testCardFacePutsPhotosInTheSlot() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let face = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Gallery/TopCardFace.swift"),
                              encoding: .utf8)
        guard let start = face.range(of: "private func cardPhoto("),
              let end = face.range(of: "private func cardFilm(", range: start.upperBound..<face.endIndex) else {
            return XCTFail("札の面に写真の段（cardPhoto）が無い")
        }
        let photo = String(face[start.lowerBound..<end.lowerBound])
        XCTAssertEqual(photo.components(separatedBy: "TopCardPhotoSlot {").count - 1, 2,
                       "写真（Photo・URL の2通り）を枠に入れていない")
        XCTAssertFalse(photo.contains(".frame(maxHeight: .infinity)"),
                       "写真に直に高さいっぱいを付けている（縦長の写真で札の背が伸びる）")
    }

    #if os(iOS)
    /// 縦横比のある写真（ピクセルの大きさ＝点の大きさ）
    private func photo(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// 高さを決めずに測ったときの大きさ（並びが背を揃えるときと同じ測り方）
    @MainActor
    private func idealSize<V: View>(_ view: V) -> CGSize {
        let host = UIHostingController(rootView: view.fixedSize(horizontal: false, vertical: true))
        return host.sizeThatFits(in: CGSize(width: 392, height: CGFloat.greatestFiniteMagnitude))
    }

    /// `RemoteImage` が読めた写真を敷く形（`resizable().aspectRatio(contentMode: .fill)`）
    private func filled(_ image: UIImage) -> some View {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
    }

    /// 枠は写真の背を返さない。縦長（3:4・花の窟神社と同じ 960×1280）でも横長でも、札の最小の背を越えない
    @MainActor
    func testSlotIdealHeightDoesNotFollowThePhoto() {
        let portrait = photo(width: 960, height: 1280)
        let landscape = photo(width: 960, height: 720)
        let tall = idealSize(TopCardPhotoSlot { filled(portrait) })
        let wide = idealSize(TopCardPhotoSlot { filled(landscape) })
        let empty = idealSize(TopCardPhotoSlot { Color.clear })
        print("topCardPhotoSlot portrait=\(tall) landscape=\(wide) empty=\(empty)")
        XCTAssertEqual(tall.width, HomeTopCardView.photoWidth, accuracy: 0.5)
        XCTAssertEqual(tall.height, empty.height, accuracy: 0.5, "縦長の写真で枠の背が変わった")
        XCTAssertEqual(wide.height, empty.height, accuracy: 0.5, "横長の写真で枠の背が変わった")
        XCTAssertLessThan(tall.height, HomeTopCardView.cardHeight)

        // 前の形（写真に直に幅と高さいっぱい）は、縦長の写真で 112×4/3 = 149.3 を返す（run 1321 の値）。
        // ここが崩れたら、この試験は直しを見分けられていない
        let before = idealSize(filled(portrait)
            .frame(width: HomeTopCardView.photoWidth)
            .frame(maxHeight: .infinity)
            .clipped())
        XCTAssertEqual(before.height, HomeTopCardView.photoWidth * 1280 / 960, accuracy: 0.5)
    }

    /// 札の背（左に縦長の写真の枠・右に字）を、高さを決めずに測っても 116 のまま
    @MainActor
    func testCardWithPortraitPhotoKeepsTheBoardHeight() {
        let portrait = photo(width: 960, height: 1280)
        let card = HStack(spacing: 0) {
            TopCardPhotoSlot { filled(portrait) }
            Text("行きたい場所を探す").frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: HomeTopCardView.cardHeight, maxHeight: .infinity, alignment: .leading)
        XCTAssertEqual(idealSize(card).height, HomeTopCardView.cardHeight, accuracy: 0.5)
        // 背を渡されたら、枠はその背いっぱいに写真を敷く
        let host = UIHostingController(rootView: TopCardPhotoSlot { filled(portrait) })
        XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 392, height: 116)).height, 116, accuracy: 0.5)
    }
    #endif
}
