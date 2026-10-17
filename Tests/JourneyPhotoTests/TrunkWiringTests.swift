import XCTest
@testable import JourneyPhoto

/// 旅のトランクの画面のつなぎ（画面は Linux で動かせないので、書き方を見張る・2026-10-17）
final class TrunkWiringTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func trunkFiles() throws -> [(String, String)] {
        let dir = root.appendingPathComponent("Sources/JourneyPhoto/Features/Trunk")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }.sorted()
        XCTAssertGreaterThanOrEqual(names.count, 8)
        return try names.map { ($0, try source("Features/Trunk/" + $0)) }
    }

    /// 入口はマイページの旅の記録の札（名前の付いた行・画面写真の試験が押す）
    func testEntryFromMyPage() throws {
        let page = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(page.contains("NavigationLink { TrunkView(ownerName: model.profile?.name) }"))
        XCTAssertTrue(page.contains(#".accessibilityIdentifier("trips.trunk")"#))
    }

    /// 投稿が全部上がった所でラベルを渡し、`RootView` がほかの画面が閉じてから出す
    func testArrivalIsPresentedAfterPosting() throws {
        let upload = try source("Features/Upload/UploadViewModel.swift")
        XCTAssertTrue(upload.contains("TrunkArrivals.shared.deliver("), "投稿の成功で届いたラベルを渡していない")
        XCTAssertTrue(upload.contains("outcome.label = saved.label"))
        let rootView = try source("App/RootView.swift")
        XCTAssertTrue(rootView.contains(".fullScreenCover(item: $trunkBatch) { batch in LabelArrivedView(batch: batch) }"))
        XCTAssertTrue(rootView.contains("tabsWithTrunkArrival"), "届いた画面の修飾子が繋がっていない")
        XCTAssertTrue(rootView.contains("toasts.show(notice.text, kind: .info)"), "いっぱいのときの一言が無い")
        XCTAssertTrue(rootView.contains("until: PostModalGate.trunkMayShow"), "届いた画面が順番の決まりを通っていない")
        XCTAssertTrue(rootView.contains("guard PostModalGate.reviewMayAsk(postModalSnapshot())"), "評価のお願いが順番の決まりを通っていない")
    }

    /// 窓口は `TrunkService` 1つで、`AppEnvironment` が組む
    func testServiceIsWired() throws {
        let env = try source("App/AppEnvironment.swift")
        XCTAssertTrue(env.contains("self.trunk = TrunkService(api: api)"))
        for path in ["Features/Trunk/TrunkView.swift", "Features/Trunk/LabelArrivedView.swift"] {
            XCTAssertTrue(try source(path).contains("model.bind(environment.trunk)"), path)
        }
    }

    /// 画面に「捨てる」を出さない（削除）・英語も用意する・系統の赤を行に出さない（危険は `WebTheme.danger`）
    func testWordingAndColors() throws {
        for (name, text) in try trunkFiles() {
            XCTAssertFalse(text.contains("捨て"), "\(name) に「捨てる」がある")
            XCTAssertFalse(text.contains("Color.red"), "\(name) に系統の赤")
            // 日本語の字を `L(` の外で `Text("…")` に直に書いていない（紙のラベルの刷りの字は `spec` から来る）
            for line in text.components(separatedBy: "\n") where line.contains("Text(\"") {
                let inside = line.components(separatedBy: "Text(\"").dropFirst().map { $0.prefix { $0 != "\"" } }
                for literal in inside where literal.unicodeScalars.contains(where: { $0.value >= 0x3000 }) {
                    XCTFail("\(name) に英語の無い字: \(literal)")
                }
            }
        }
        let pocket = try source("Features/Trunk/TrunkPocketView.swift")
        XCTAssertTrue(pocket.contains("kind: .danger"), "削除が危険の字になっていない")
        XCTAssertTrue(pocket.contains(".confirmationDialog("), "削除を確かめていない")
    }

    /// 真鍮は黒い地の上だけ（写真の上に置く画面は無い）・押せるものは 44pt
    func testTapTargets() throws {
        let parts = try source("Features/Trunk/TrunkParts.swift")
        XCTAssertTrue(parts.contains(".frame(minHeight: 52)"), "札の行が 52 でない")
        for path in ["Features/Trunk/TrunkRerollView.swift", "Features/Trunk/LabelArrivedView.swift",
                     "Features/Trunk/TrunkSpinViewer.swift"] {
            XCTAssertTrue(try source(path).contains("WebTheme.minTapTarget"), "\(path) の閉じるが 44pt でない")
        }
    }

    /// 手に取って回す: メダルと同じ仕組みに箱の形を足し、表に胴の絵を貼る
    func testSpinUsesTheMedalViewer() throws {
        let medal = try source("Features/Profile/MedalViewerView.swift")
        XCTAssertTrue(medal.contains("case box(aspect: Double, depth: Double, corner: Double, handle: SpinRGB)"))
        XCTAssertTrue(medal.contains("addHandle(aspect: aspect, depth: depth, color: handle)"))
        let spin = try source("Features/Trunk/TrunkSpinViewer.swift")
        XCTAssertTrue(spin.contains("MedalCoinView(textures: textures"))
        XCTAssertTrue(spin.contains("TrunkBoxView(model: model, posts: posts, stuck: stuck, ownerName: ownerName, bodyOnly: true)"))
        XCTAssertTrue(spin.contains(".accessibilityAction(named: L(\"裏返す\", \"Turn over\"))"))
    }

    /// 4つの状態（読み込み中・空・失敗・圏外）を出し分ける
    func testFourStates() throws {
        let main = try source("Features/Trunk/TrunkView.swift")
        for id in ["trunk.loading", "trunk.failed", "trunk.offline", "trunk.empty"] {
            XCTAssertTrue(main.contains("\"\(id)\""), "\(id) が無い")
        }
        XCTAssertTrue(try source("Features/Trunk/TrunkPocketView.swift").contains("trunk.pocket.empty"))
    }

    /// 画面写真の見本の鍵は Debug だけ（Release では必ず効かない）
    func testPreviewKeysAreDebugOnly() throws {
        let preview = try source("Core/Auth/PreviewSession.swift")
        XCTAssertTrue(preview.contains("static let trunkSampleKey = \"JPPreviewTrunk\""))
        XCTAssertTrue(preview.contains("static let trunkArrivedKey = \"JPPreviewTrunkArrived\""))
        XCTAssertNil(PreviewSession.trunkSample, "テストでは見本が効いていない")
    }

    /// 知らせ: 押して進む画面には重ねず（`RootView` の全体の知らせ）、全画面の届いた画面にだけ置く。
    /// 画面の組みは Linux で描けないので書き方で見る（振る舞いは Mac の画面写真）
    func testToastPlacement() throws {
        for path in ["Features/Trunk/TrunkView.swift", "Features/Trunk/TrunkPocketView.swift"] {
            XCTAssertFalse(try source(path).contains("ToastOverlay()"), "\(path) で知らせが二重に出る")
        }
        XCTAssertTrue(try source("Features/Trunk/LabelArrivedView.swift").contains(".overlay(alignment: .top) { ToastOverlay() }"),
                      "届いた画面の上で知らせが隠れる")
    }
}
