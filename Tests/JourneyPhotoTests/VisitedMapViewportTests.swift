import XCTest
@testable import JourneyPhoto

/// 行った県マップの拡大・移動の計算と、画面の文言（札 #503）。
final class VisitedMapViewportTests: XCTestCase {

    private let content = CGSize(width: 1000, height: 1100)
    private let container = CGSize(width: 360, height: 400)

    func testScreenAndUnitPointsAreInverse() {
        var v = VisitedMapViewport()
        v = v.zoomed(to: 3, around: CGPoint(x: 100, y: 120), content: content, container: container)
        for u in [CGPoint(x: 0, y: 0), CGPoint(x: 500, y: 550), CGPoint(x: 900, y: 80)] {
            let s = v.screenPoint(forUnit: u, content: content, container: container)
            let back = v.unitPoint(forScreen: s, content: content, container: container)
            XCTAssertEqual(back.x, u.x, accuracy: 0.001)
            XCTAssertEqual(back.y, u.y, accuracy: 0.001)
        }
    }

    /// ピンチは指の下の絵の点を動かさない（端に近すぎて収め直されない点で確かめる）
    func testZoomKeepsThePointUnderTheFinger() {
        let start = VisitedMapViewport()
        let focal = CGPoint(x: 180, y: 200)
        let before = start.unitPoint(forScreen: focal, content: content, container: container)
        let zoomed = start.zoomed(to: 2.5, around: focal, content: content, container: container)
        let after = zoomed.unitPoint(forScreen: focal, content: content, container: container)
        XCTAssertEqual(after.x, before.x, accuracy: 0.01)
        XCTAssertEqual(after.y, before.y, accuracy: 0.01)
        XCTAssertEqual(zoomed.zoom, 2.5)
    }

    func testZoomIsClampedAndPanStaysInside() {
        var v = VisitedMapViewport().zoomed(to: 99, around: .zero, content: content, container: container)
        XCTAssertEqual(v.zoom, VisitedMapViewport.maxZoom)
        v = v.zoomed(to: 0.1, around: .zero, content: content, container: container)
        XCTAssertEqual(v.zoom, VisitedMapViewport.minZoom)
        XCTAssertEqual(v.pan, .zero, "1 倍では動かせない")

        let z2 = VisitedMapViewport().zoomed(to: 2, around: CGPoint(x: 180, y: 200), content: content, container: container)
        let far = z2.panned(by: CGSize(width: 9999, height: -9999), content: content, container: container)
        let s = far.scale(content: content, container: container)
        XCTAssertLessThanOrEqual(abs(far.pan.width), (content.width * s - container.width) / 2 + 0.001)
        XCTAssertLessThanOrEqual(abs(far.pan.height), (content.height * s - container.height) / 2 + 0.001)
    }

    func testStepButtons() {
        var v = VisitedMapViewport()
        XCTAssertFalse(v.canZoomOut)
        XCTAssertTrue(v.canZoomIn)
        v = v.stepped(1, content: content, container: container)
        XCTAssertEqual(v.zoom, VisitedMapViewport.step, accuracy: 0.001)
        XCTAssertTrue(v.isZoomed)
        v = v.stepped(-1, content: content, container: container)
        XCTAssertEqual(v.zoom, 1, accuracy: 0.001)
        for _ in 0..<20 { v = v.stepped(1, content: content, container: container) }
        XCTAssertFalse(v.canZoomIn)
    }

    func testToleranceShrinksWhenZoomedIn() {
        let one = VisitedMapViewport()
        let three = VisitedMapViewport().zoomed(to: 3, around: .zero, content: content, container: container)
        XCTAssertGreaterThan(one.tolerance(content: content, container: container),
                             three.tolerance(content: content, container: container))
    }

    // MARK: - 文言

    func testReadAloudForms() {
        XCTAssertEqual(VisitedMapText.prefectureAccessibility("東京都", count: 5, isCandidate: false), "東京都、5 回")
        XCTAssertEqual(VisitedMapText.prefectureAccessibility("東京都", count: 0, isCandidate: false), "東京都、未")
        XCTAssertEqual(VisitedMapText.prefectureAccessibility("東京都", count: 0, isCandidate: true), "東京都、写真の候補")
        XCTAssertEqual(VisitedMapText.changeAnnouncement("東京都", count: 6, visited: 31), "東京都、6 回。行った県 31")
        // 押した県の帯から足し引きしたあと（案 A・2026-11-10）
        XCTAssertEqual(VisitedMapText.quickAdded("東京都", count: 3), "東京都、3 回、1 回足しました")
        XCTAssertEqual(VisitedMapText.quickRemoved("東京都", count: 2), "東京都、2 回、1 回減らしました")
        XCTAssertEqual(VisitedMapText.quickRemoved("東京都", count: 0), "東京都、未、1 回減らしました")
        XCTAssertEqual(VisitedMapText.quickHint, "押す＝1 回足す · 長押し＝見るだけ")
        XCTAssertEqual(VisitedMapText.entryAccessibility(31), "行った県、31 / 47")
        XCTAssertEqual(VisitedMapText.ratio(31), "31/47")
    }

    func testRoundsLine() {
        XCTAssertNil(VisitedMapText.roundsLine(completed: 0, inProgress: (1, 12)))
        XCTAssertEqual(VisitedMapText.roundsLine(completed: 1, inProgress: (2, 0)), "1 周そろった")
        XCTAssertEqual(VisitedMapText.roundsLine(completed: 2, inProgress: (3, 12)), "2 周そろった · 3 周目 12/47")
    }

    /// 禁止語を使わない（全文言を走査する）
    func testNoForbiddenWordsInCopy() throws {
        var all: [String] = [
            VisitedMapText.title, VisitedMapText.breakdownNote,
            VisitedMapText.tapHint, VisitedMapText.quickHint, VisitedMapText.details, VisitedMapText.removeOne,
            VisitedMapText.quickAdded("東京都", count: 3), VisitedMapText.quickRemoved("東京都", count: 2),
            VisitedMapText.quickRemoved("東京都", count: 0),
            VisitedMapText.recentDates, VisitedMapText.noDates, VisitedMapText.addVisit, VisitedMapText.removeVisit,
            VisitedMapText.record, VisitedMapText.candidateNote, VisitedMapText.dismissCandidate,
            VisitedMapText.restoreCandidate, VisitedMapText.undo, VisitedMapText.undoStep,
            VisitedMapText.nearby, VisitedMapText.listTitle, VisitedMapText.legendNone,
            VisitedMapText.legendCandidate, VisitedMapText.loadingPhotos, VisitedMapText.emptyTitle,
            VisitedMapText.emptyBody, VisitedMapText.postPhoto, VisitedMapText.failedPhotos, VisitedMapText.retry,
            VisitedMapText.allVisited47, VisitedMapText.allVisitedConfirmTitle, VisitedMapText.allVisitedConfirmBody,
            VisitedMapText.clearAll, VisitedMapText.clearAllConfirmTitle, VisitedMapText.clearAllConfirmBody,
            VisitedMapText.privateNote, VisitedMapText.mapAccessibility,
            VisitedMapText.openFromBadge,
        ]
        for c in [VisitedPrefectures.Celebration.allVisited, .roundCompleted(2)] {
            all += [VisitedMapText.celebrationEyebrow(c), VisitedMapText.celebrationTitle(c), VisitedMapText.celebrationBody(c)]
        }
        for text in all {
            for word in VisitedMapText.forbiddenWords {
                XCTAssertFalse(text.contains(word), "「\(word)」は使わない: \(text)")
            }
        }
    }

    /// 画面のソースにも禁止語を書かない（画面の文は `VisitedMapText` から出す）
    func testScreenSourcesHaveNoForbiddenWords() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Sources/JourneyPhoto/Features/Profile")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("VisitedMap") }
        for file in files {
            let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                for word in VisitedMapText.forbiddenWords {
                    XCTAssertFalse(line.contains(word), "\(file) に「\(word)」: \(line)")
                }
            }
        }
    }
}
