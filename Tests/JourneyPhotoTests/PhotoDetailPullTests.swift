import XCTest
@testable import JourneyPhoto

/// 写真の詳細で写真を下に引いて前の画面へ戻る（2026-11-13 owner 決定・札 #592・`PhotoDetailPull`）
final class PhotoDetailPullTests: XCTestCase {

    /// 上に居て、下向きで、縦が横より大きいときだけ始める
    func testStartsOnlyWhenAtTopAndPullingDown() {
        XCTAssertTrue(PhotoDetailPull.starts(dx: 0, dy: 12, atTop: true))
        XCTAssertTrue(PhotoDetailPull.starts(dx: 10, dy: 10, atTop: true), "斜め 45° までは引く側")
        XCTAssertFalse(PhotoDetailPull.starts(dx: 0, dy: -12, atTop: true), "上へ払う指を奪った（説明・コメントへ流れない）")
        XCTAssertFalse(PhotoDetailPull.starts(dx: 0, dy: 12, atTop: false), "下まで読んでいる途中で上へ戻す指を奪った")
        XCTAssertFalse(PhotoDetailPull.starts(dx: 30, dy: 12, atTop: true), "横の払い（束の写真の送り・端からの戻る）を奪った")
        XCTAssertFalse(PhotoDetailPull.starts(dx: -30, dy: 12, atTop: true), "左向きの横の払いを奪った")
        XCTAssertFalse(PhotoDetailPull.starts(dx: 0, dy: 0, atTop: true))
    }

    /// 上に居るか（送りの止まり際の端数は上とみなす）
    func testIsAtTop() {
        XCTAssertTrue(PhotoDetailPull.isAtTop(offsetY: 0, insetTop: 0))
        XCTAssertTrue(PhotoDetailPull.isAtTop(offsetY: 0.6, insetTop: 0), "端数で上に居ないことにした")
        XCTAssertTrue(PhotoDetailPull.isAtTop(offsetY: -59, insetTop: 59), "上の余白のある送りで上と見なかった")
        XCTAssertFalse(PhotoDetailPull.isAtTop(offsetY: 4, insetTop: 0))
        XCTAssertFalse(PhotoDetailPull.isAtTop(offsetY: -50, insetTop: 59))
    }

    /// 引いた量（と勢い）が 120pt に届けば戻る。足りなければ元に戻る
    func testClosesByDistanceOrFlick() {
        XCTAssertEqual(PhotoDetailPull.closeDistance, StoryReel.closeDistance, "人のストーリーの下へ払う距離とそろえる")
        XCTAssertTrue(PhotoDetailPull.closes(dy: 130, velocityY: 0))
        XCTAssertTrue(PhotoDetailPull.closes(dy: 120, velocityY: 0))
        XCTAssertFalse(PhotoDetailPull.closes(dy: 80, velocityY: 0), "足りない量で戻った")
        XCTAssertTrue(PhotoDetailPull.closes(dy: 40, velocityY: 400), "短く素早く払って戻れない（40 + 400 × 0.499 ≒ 240）")
        XCTAssertFalse(PhotoDetailPull.closes(dy: 40, velocityY: 100), "ゆっくり少し引いただけで戻った")
        XCTAssertFalse(PhotoDetailPull.closes(dy: 200, velocityY: -600), "引いてから上へ払い戻したのに戻った")
        XCTAssertEqual(PhotoDetailPull.projectionSeconds, 0.499, accuracy: 0.0005)
    }

    /// 🔴 **止めてから離した指は速さ 0**（Mac の回 1232: 80pt 引いて 1.5 秒止めて離した指に、UIKit は 172pt/秒を返し、
    /// 80 ＋ 172 × 0.499 ≒ 166 で閉じた）。最後に量が変わってから 100ms を越えて止めていたら勢いを足さない
    func testStillFingerReleasesWithoutVelocity() {
        let velocity = PhotoDetailPull.releaseVelocity(reportedY: 172, sinceLastMoveMs: 1478)
        XCTAssertEqual(velocity, 0, "止めてから離した指に、動いていた頃の速さを使った")
        XCTAssertFalse(PhotoDetailPull.closes(dy: 80, velocityY: velocity), "回 1232 の値（80pt・止めて離す）で閉じた")
        // 動きながら離した（払った）指は速さを使う
        XCTAssertEqual(PhotoDetailPull.releaseVelocity(reportedY: 400, sinceLastMoveMs: 12), 400)
        XCTAssertTrue(PhotoDetailPull.closes(dy: 40, velocityY: PhotoDetailPull.releaseVelocity(reportedY: 400, sinceLastMoveMs: 12)),
                      "短く素早く払って戻れない")
        XCTAssertEqual(PhotoDetailPull.releaseVelocity(reportedY: 300, sinceLastMoveMs: 100), 300, "境目（100ms ちょうど）はまだ動いている")
        XCTAssertEqual(PhotoDetailPull.releaseVelocity(reportedY: 300, sinceLastMoveMs: 101), 0)
        // 止めて離しても、引いた量が 120pt 以上なら戻る
        XCTAssertTrue(PhotoDetailPull.closes(dy: 130, velocityY: PhotoDetailPull.releaseVelocity(reportedY: 50, sinceLastMoveMs: 900)))
    }

    /// 引くほど縮む（下限 0.75）。「視差効果を減らす」では縮めない
    func testScaleShrinksWithPullUnlessReduceMotion() {
        XCTAssertEqual(PhotoDetailPull.scale(dy: 0, reduceMotion: false), 1)
        XCTAssertEqual(PhotoDetailPull.scale(dy: 200, reduceMotion: false), 0.875, accuracy: 0.0001)
        XCTAssertEqual(PhotoDetailPull.scale(dy: 400, reduceMotion: false), 0.75, accuracy: 0.0001)
        XCTAssertEqual(PhotoDetailPull.scale(dy: 900, reduceMotion: false), 0.75, accuracy: 0.0001, "下限より縮んだ")
        XCTAssertEqual(PhotoDetailPull.scale(dy: -50, reduceMotion: false), 1, "上へ戻した指で大きくなった")
        XCTAssertEqual(PhotoDetailPull.scale(dy: 300, reduceMotion: true), 1, "視差効果を減らすでも縮んだ")
    }

    /// 写真は指に付いて動く（縦は下向きだけ）。下の説明は薄れる。角は引いている間だけ丸める
    func testOffsetFadeAndCorners() {
        let shift = PhotoDetailPull.offset(dx: -24, dy: 90)
        XCTAssertEqual(shift.x, -24)
        XCTAssertEqual(shift.y, 90)
        XCTAssertEqual(PhotoDetailPull.offset(dx: 0, dy: -30).y, 0, "指を上へ戻すと写真が元の位置より上へ出た")

        XCTAssertEqual(PhotoDetailPull.restOpacity(dy: 0), 1)
        XCTAssertEqual(PhotoDetailPull.restOpacity(dy: 100), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PhotoDetailPull.restOpacity(dy: 300), 0)
        XCTAssertEqual(PhotoDetailPull.restOpacity(dy: -40), 1)

        XCTAssertFalse(PhotoDetailPull.rounds(dy: 0))
        XCTAssertTrue(PhotoDetailPull.rounds(dy: 1))
    }

    /// 🔴 **引く量の箱は画面が出たときに1回だけ作る**（2026-11-13 確かめ役）。`@State` の初期値に書くと、格子のマスが
    /// 行き先の `PhotoDetailView` を作るたびに箱が割り当てられていた。入れ物は `@StateObject`、入れ物自身は知らせない
    func testPullBoxIsMadeOnceAndHolderNeverPublishes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift"), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(view.contains("@StateObject private var pullHolder = PhotoDetailPullHolder()"),
                      "引く量の箱の入れ物が @StateObject に無い")
        XCTAssertFalse(view.contains("= PhotoDetailPullDrag()"), "画面を作るたびに引く量の箱を割り当てている")

        // 入れ物は知らせない（`@Published` を持つと、引いている間に写真の詳細の body ぜんぶが描き直される）。
        // Linux の模型の Combine は知らせを流さないので、持ち物の型で見る
        let kinds = Mirror(reflecting: PhotoDetailPullHolder()).children.map { String(describing: type(of: $0.value)) }
        XCTAssertEqual(kinds, ["PhotoDetailPullDrag"], "入れ物が箱のほかに持ち物を持った（知らせる値なら body が描き直される）")
    }

    // MARK: - 写真を大きく見る画面（2026-11-14 判断・人間工学の点検）

    /// 大きく見る画面で引き始めるのは、**拡大していない・つまんでいない・下向きで縦が横より大きい**ときだけ
    func testViewerStartsOnlyWhenNotZoomedAndPullingDown() {
        let flat = ZoomPan()
        XCTAssertTrue(PhotoDetailPull.viewerStarts(dx: 0, dy: 12, zoom: flat, pinch: 1))
        XCTAssertTrue(PhotoDetailPull.viewerStarts(dx: 10, dy: 10, zoom: flat, pinch: 1), "斜め 45° までは引く側（写真の詳細と同じ）")
        XCTAssertFalse(PhotoDetailPull.viewerStarts(dx: 30, dy: 12, zoom: flat, pinch: 1), "横に払う指（写真を送る）を奪った")
        XCTAssertFalse(PhotoDetailPull.viewerStarts(dx: -30, dy: 12, zoom: flat, pinch: 1), "左向きの送りを奪った")
        XCTAssertFalse(PhotoDetailPull.viewerStarts(dx: 0, dy: -12, zoom: flat, pinch: 1), "上へ払う指で始めた")
        XCTAssertFalse(PhotoDetailPull.viewerStarts(dx: 0, dy: 0, zoom: flat, pinch: 1))
        XCTAssertTrue(PhotoDetailPull.viewerAccepts(zoom: flat, pinch: 1))
    }

    /// 🔴 **拡大中・つまんでいる最中は始めない**（拡大中の1本指は写真を動かす指・つまむ指は倍率を変える指）。
    /// 倍率を戻したらまた引ける
    func testViewerNeverStartsWhileZoomedOrPinching() {
        let screen = CGSize(width: 440, height: 956), photo = CGSize(width: 440, height: 293)
        var zoomed = ZoomPan()
        zoomed.endPinch(2, container: screen, content: photo)
        XCTAssertTrue(zoomed.isZoomed, "前提: 2倍に拡大している")
        XCTAssertFalse(PhotoDetailPull.viewerStarts(dx: 0, dy: 40, zoom: zoomed, pinch: 1), "拡大中に下へ動かす指で閉じ始めた")
        XCTAssertFalse(PhotoDetailPull.viewerAccepts(zoom: zoomed, pinch: 1), "拡大中に引く指を受けた")
        XCTAssertFalse(PhotoDetailPull.viewerStarts(dx: 0, dy: 40, zoom: ZoomPan(), pinch: 1.3), "等倍からつまんでいる最中に始めた")
        XCTAssertFalse(PhotoDetailPull.viewerStarts(dx: 0, dy: 40, zoom: ZoomPan(), pinch: 0.8), "縮めてつまんでいる最中に始めた")
        XCTAssertFalse(PhotoDetailPull.viewerAccepts(zoom: ZoomPan(), pinch: 1.3))
        zoomed.reset()
        XCTAssertTrue(PhotoDetailPull.viewerStarts(dx: 0, dy: 40, zoom: zoomed, pinch: 1), "倍率を戻しても引けない")
    }

    /// 離したときの決め方は1つ（写真の詳細と大きく見る画面の両方が `PhotoDetailPullDrag.release` を使う）。
    /// 届けば閉じている最中にし、届かなければ 0 へ戻す
    func testReleaseClosesOrResets() {
        let drag = PhotoDetailPullDrag()
        drag.translation = CGSize(width: 0, height: 80)
        XCTAssertFalse(drag.release(dy: 80, velocityY: 0, reduceMotion: false), "足りない量で閉じた")
        XCTAssertFalse(drag.closing)
        XCTAssertEqual(drag.translation, .zero, "届かなかった写真が元の位置へ戻らない")

        drag.translation = CGSize(width: 0, height: 130)
        XCTAssertTrue(drag.release(dy: 130, velocityY: 0, reduceMotion: true))
        XCTAssertTrue(drag.closing, "閉じると決めたのに、閉じる動きの間にもう一度つかめる")
        XCTAssertEqual(drag.translation.height, 130, "閉じる写真を戻してから閉じている（一瞬跳ねる）")
        drag.reset(reduceMotion: true)
        XCTAssertFalse(drag.closing)
        XCTAssertEqual(drag.translation, .zero)
    }

    /// 🔴 大きく見る画面は**写真の詳細と同じ部品と計算を使う**（写しを作らない）。拡大中は始めない決まりを通し、
    /// パンは見ている頁にだけ置く。引く部品には頁いっぱいの枠で渡す（写真の枠のままだと拡大した写真が切り抜かれる）
    func testViewerUsesTheSharedPull() throws {
        let viewer = try viewSource("PhotoViewerView.swift")
        XCTAssertTrue(viewer.contains("@StateObject private var pullHolder = PhotoDetailPullHolder()"), "引く量の箱の入れ物が @StateObject に無い")
        XCTAssertFalse(viewer.contains("= PhotoDetailPullDrag()"), "画面を作るたびに引く量の箱を割り当てている")
        let catcher = member("private var pullCatcher", in: viewer)
        XCTAssertTrue(catcher.contains("DetailPullCatcher("), "下へ引く指を受けていない")
        XCTAssertTrue(catcher.contains("isEnabled: PhotoDetailPull.viewerAccepts(zoom: zoom, pinch: pinch)"), "拡大中も引く指を受ける")
        XCTAssertTrue(catcher.contains("PhotoDetailPull.viewerStarts(dx: dx, dy: dy, zoom: zoom, pinch: pinch)"), "始める条件が共通の決まりでない")
        XCTAssertTrue(catcher.contains("pull.release(dy: dy, velocityY: velocityY, reduceMotion: reduceMotion)"), "離したときの決め方を写している")
        XCTAssertTrue(catcher.contains("dismiss()"))
        XCTAssertFalse(catcher.contains("120"), "閾値を画面に写している（`PhotoDetailPull.closeDistance`）")
        XCTAssertTrue(viewer.contains(".background { if shown { pullCatcher } }"), "パンを見ている頁にだけ置いていない")
        XCTAssertTrue(viewer.contains("DetailPullFollow(drag: shown ? pull : stillHolder.drag, part: .photo"), "見ている写真が指に付いて動かない")
        XCTAssertTrue(viewer.contains(".offset(x: shown ? Double(liveOffset.width) : 0, y: shown ? Double(liveOffset.height) : 0)\n"
            + "                        .frame(maxWidth: .infinity, maxHeight: .infinity))"), "拡大した写真が写真の枠で切り抜かれる")
        // 写真の詳細も同じ決め方を使う
        let detail = try viewSource("PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("pull.release(dy: dy, velocityY: velocityY, reduceMotion: reduceMotion)"))
    }

    private func viewSource(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/PhotoDetail/" + name),
                          encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `head` で始まる宣言の中身（次の `{` から閉じる `}` まで）
    private func member(_ head: String, in text: String) -> String {
        guard let start = text.range(of: head) else { return "" }
        var depth = 0, began = false, out = ""
        for ch in text[start.lowerBound...] {
            out.append(ch)
            if ch == "{" { depth += 1; began = true }
            if ch == "}" { depth -= 1; if began && depth == 0 { break } }
        }
        return out
    }
}
