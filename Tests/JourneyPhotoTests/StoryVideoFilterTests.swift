import XCTest
@testable import JourneyPhoto

/// ストーリーの動画にフィルターをかける書き出し（2026-11-09・段 2b）。
/// **重ねの焼き込みとコマごとのフィルターを同じ合成に載せない**（併用できるか確かめていない）ので、
/// 「フィルターだけの1回目 → 今までどおりの2回目」に分けた。ここは1回目の決まり（大きさ・倍率・向きの見張り・
/// 2回目の元）と、配線（2回目の道・重ねの焼き込みに手を入れていないこと）を縛る。
/// 書き出しの時間・メモリ・向きの本物は Mac の CI と実機で確かめる。
final class StoryVideoFilterTests: XCTestCase {

    // MARK: - 1回目の大きさと倍率

    /// 最上段（長い辺 1920）に収める。4K を 4K のまま符号化しない。小さい動画は拡大しない。画素は偶数
    func testPassRenderSizeFitsTheTopStep() {
        XCTAssertEqual(StoryVideoFilterPlan.passRenderSize(oriented: CGSize(width: 2160, height: 3840)),
                       CGSize(width: 1080, height: 1920))
        XCTAssertEqual(StoryVideoFilterPlan.passRenderSize(oriented: CGSize(width: 3840, height: 2160)),
                       CGSize(width: 1920, height: 1080))
        XCTAssertEqual(StoryVideoFilterPlan.passRenderSize(oriented: CGSize(width: 540, height: 960)),
                       CGSize(width: 540, height: 960), "小さい動画を拡大している")
        let odd = StoryVideoFilterPlan.passRenderSize(oriented: CGSize(width: 1001, height: 1779))
        XCTAssertEqual(Int(odd.width) % 2, 0)
        XCTAssertEqual(Int(odd.height) % 2, 0)
    }

    func testScaleFitsTheFrameToTheTarget() {
        let same = StoryVideoFilterPlan.scale(from: CGSize(width: 1080, height: 1920), to: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(same.x, 1)
        XCTAssertEqual(same.y, 1)
        let half = StoryVideoFilterPlan.scale(from: CGSize(width: 2160, height: 3840), to: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(half.x, 0.5)
        XCTAssertEqual(half.y, 0.5)
        // 値が壊れていても 1（倍率 0 や無限大で1コマを消さない）
        let broken = StoryVideoFilterPlan.scale(from: .zero, to: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(broken.x, 1)
        XCTAssertEqual(broken.y, 1)
        let none = StoryVideoFilterPlan.scale(from: CGSize(width: 100, height: 100), to: .zero)
        XCTAssertEqual(none.x, 1)
    }

    // MARK: - 向きの見張り

    /// ハンドラの1コマの向きが想定と違った（横向きの動画になった）ときは見つけて失敗にする
    func testOrientationGuard() {
        let portrait = CGSize(width: 1080, height: 1920)
        XCTAssertTrue(StoryVideoFilterPlan.orientationMatches(expected: portrait, actual: CGSize(width: 1080, height: 1920)))
        XCTAssertTrue(StoryVideoFilterPlan.orientationMatches(expected: portrait, actual: CGSize(width: 1088, height: 1920)),
                      "符号化の丸めの差で失敗にしている")
        XCTAssertFalse(StoryVideoFilterPlan.orientationMatches(expected: portrait, actual: CGSize(width: 1920, height: 1080)),
                       "横向きになった動画を通している")
        XCTAssertFalse(StoryVideoFilterPlan.orientationMatches(expected: CGSize(width: 1920, height: 1080),
                                                               actual: portrait))
        XCTAssertTrue(StoryVideoFilterPlan.orientationMatches(expected: CGSize(width: 1080, height: 1080),
                                                              actual: CGSize(width: 1080, height: 1080)))
        XCTAssertFalse(StoryVideoFilterPlan.orientationMatches(expected: portrait, actual: .zero))
        XCTAssertFalse(StoryVideoFilterPlan.orientationMatches(expected: .zero, actual: portrait))
    }

    // MARK: - 2回目の元

    /// 切り取りは1回目で済んでいる: 2回目の元は範囲が全部・長さは残した長さ（段の選びも残した長さ）
    func testSecondPassClipIsAlreadyTrimmed() {
        let url = URL(fileURLWithPath: "/tmp/original.mov")
        var clip = StoryVideoClip(url: url, durationSec: 3 * 3600, size: CGSize(width: 2160, height: 3840), bytes: 9)
        clip.trim.setEnd(120)
        clip.trim.setStart(100)
        XCTAssertEqual(clip.outputSeconds, 20, accuracy: 0.0001)
        let middle = URL(fileURLWithPath: "/tmp/filtered.mov")
        let second = StoryVideoFilterPlan.secondPassClip(from: clip, intermediate: middle,
                                                         size: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(second.url, middle)
        XCTAssertEqual(second.durationSec, 20, accuracy: 0.0001)
        XCTAssertFalse(second.isTrimmed, "2回目でもう一度切っている（始点がずれる）")
        XCTAssertEqual(second.outputSeconds, 20, accuracy: 0.0001)
        XCTAssertEqual(second.size, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(StoryVideoRules.ladder(durationSec: second.outputSeconds).first?.preset,
                       "AVAssetExportPreset1920x1080")
    }

    /// 実際の動画の長さに収めた範囲（丸めで保存した長さとわずかに違っても、範囲が動画の外へ出ない）
    func testSourceRangeStaysInsideTheAsset() {
        let trim = StoryVideoTrim(total: 125, start: 10, end: 70)
        let exact = trim.sourceRange(assetDuration: 125)
        XCTAssertEqual(exact.start, 10)
        XCTAssertEqual(exact.length, 60)
        var tail = StoryVideoTrim(total: 60)
        tail.setStart(10)
        let shorter = tail.sourceRange(assetDuration: 59.9)
        XCTAssertEqual(shorter.start, 10, accuracy: 1e-9)
        XCTAssertEqual(shorter.length, 49.9, accuracy: 1e-9, "動画の終わりを越えている")
        // 読めない長さのときは範囲のまま
        let unknown = trim.sourceRange(assetDuration: .nan)
        XCTAssertEqual(unknown.start, 10)
        XCTAssertEqual(unknown.length, 60)
        // 始点が動画の外なら、最短を残して寄せる
        let outside = StoryVideoTrim(total: 125, start: 100, end: 110).sourceRange(assetDuration: 50)
        XCTAssertEqual(outside.start, 49, accuracy: 1e-9)
        XCTAssertEqual(outside.length, 1, accuracy: 1e-9)
    }

    // MARK: - 配線（ソース）

    private func repo(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 1回目はフィルターだけ（重ねの焼き込みを載せない）。2回目は今までの道。「なし」は1回目を通らない
    func testPipelineKeepsTheOverlayPathAndFiltersInATwoPassExport() throws {
        let pipeline = try repo("Sources/JourneyPhoto/Services/StoryVideoPipeline.swift")
        let first = try XCTUnwrap(pipeline.components(separatedBy: "private static func filteredIntermediate(").dropFirst().first?
            .components(separatedBy: "/// 切り取りの帯のサムネイル").first)
        XCTAssertTrue(first.contains("applyingCIFiltersWithHandler"))
        XCTAssertTrue(first.contains("renderer.apply(recipe, to: fitted)"), "写真と同じレシピの当て方を通していない")
        XCTAssertTrue(first.contains("context: renderer.context"), "写真と同じ作業色空間の CIContext を使っていない")
        XCTAssertTrue(first.contains("session.timeRange = "), "1回目で切り取りの範囲を切っていない")
        XCTAssertTrue(first.contains("StoryVideoFilterPlan.orientationMatches(expected: target, actual: madeSize)"),
                      "向きの見張りが無い")
        XCTAssertTrue(first.contains("session.metadataItemFilter = AVMetadataItemFilter.forSharing()"))
        XCTAssertFalse(first.contains("AVVideoCompositionCoreAnimationTool"), "1回目に重ねの焼き込みを載せている")
        XCTAssertFalse(first.contains("overlays"), "1回目に重ねを持ち込んでいる")
        // 2回目: 重ねの焼き込みは前のまま・「なし」は1回目を通らない・中間の動画は必ず消す
        XCTAssertTrue(pipeline.contains("videoComposition.animationTool = AVVideoCompositionCoreAnimationTool("))
        XCTAssertTrue(pipeline.contains("if filter.isNone {\n            clip = original\n        } else {"))
        XCTAssertTrue(pipeline.contains("defer { if let intermediate { try? FileManager.default.removeItem(at: intermediate) } }"),
                      "中間の動画が残る")
        XCTAssertTrue(pipeline.contains("StoryVideoFilterPlan.secondPassClip(from: original, intermediate: made.url, size: made.size)"))
        // 位置情報の除去・50MB の段下げは2回目の最終出力に対して今のまま
        XCTAssertTrue(pipeline.contains("if await hasLocationMetadata(out)"))
        XCTAssertTrue(pipeline.contains("StoryVideoRules.ladder(durationSec: clip.outputSeconds)"))
        XCTAssertTrue(pipeline.contains("session.metadata = []"))
    }

    /// 画面: 動画にもフィルターを出す・書き出しに渡す・かけ直したら書き出し直す・表紙もそろえる・時間の延びを言う
    func testComposerCarriesTheFilterIntoTheVideoExport() throws {
        let composer = try repo("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("for (id, clip, overlays, filter, drawing) in targets {"))
        XCTAssertTrue(composer.contains("filter: filter, drawing: drawing)"), "書き出しにフィルターを渡していない")
        XCTAssertTrue(composer.contains("done.filters[id] = filter"))
        XCTAssertTrue(composer.contains("&& done.filters[$0.id] == $0.filter"), "かけ直しても書き出し直さない")
        XCTAssertTrue(composer.contains("StoryFilterRenderer.coverData(shot.prepared.data, filter: shot.filter)"), "動画の表紙がフィルターと食い違う")
        XCTAssertTrue(composer.contains("if !shots[index].filter.isNone { renderFilteredPreview(shot: id) }"),
                      "切り取りで表紙が替わってもフィルターの絵が古いまま")
        XCTAssertTrue(composer.contains("フィルターをかけています。少し時間がかかります"), "書き出しが延びることを言わない")
        XCTAssertFalse(composer.contains("guard shots.indices.contains(current), shots[current].video == nil, typingId == nil"),
                       "動画でフィルターを開けない")
    }
}
