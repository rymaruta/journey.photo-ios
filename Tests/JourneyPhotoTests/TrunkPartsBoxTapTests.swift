import XCTest
@testable import JourneyPhoto

/// 部品箱: 押すとその場で付く・もう一度押すと外す・「元に戻す」を 3 秒（札 #711・2026-11-23 owner 承認）
final class TrunkPartsBoxTapTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 押して付け、「元に戻す」で前の付け方へ戻る。もう一度押すと外れる（見本で・サーバーに送らない）
    @MainActor
    func testTapPutsOnAndUndoRestores() async throws {
        let model = TrunkViewModel(preview: .sample, previewPro: false)
        await model.load(offline: false)
        let state = try XCTUnwrap(model.state)
        let before = state.equipped
        // 持っていて、まだ付けていない持ち手を1つ
        let part = try XCTUnwrap(TrunkPartCatalog.parts(of: .handle).first {
            state.ownedParts.contains($0.id) && !before.ids(.handle).contains($0.id)
        })
        let next = TrunkEquipText.toggling(part, on: before)
        XCTAssertFalse(next.full)
        let ok = await model.equip(next.equipped)
        XCTAssertTrue(ok)
        XCTAssertTrue(model.state?.equipped.ids(.handle).contains(part.id) ?? false, "押しても付かない")

        let toasts = ToastCenter()
        toasts.show(TrunkPartsBoxText.equippedNotice(part, on: true), seconds: TrunkPartsBoxText.undoSeconds,
                    undo: ToastCenter.Undo(title: TrunkPartsBoxText.undoTitle) { [model] in await model.equip(before) })
        XCTAssertEqual(toasts.current?.text, "「\(part.name)」を付けました")
        XCTAssertEqual(toasts.undo?.title, "元に戻す")
        await toasts.performUndo()
        XCTAssertEqual(model.state?.equipped, before, "「元に戻す」で前の付け方に戻らない")
        XCTAssertNil(toasts.current, "戻せたのに知らせが残る")

        // 付けている部品をもう一度押すと外れる
        let again = TrunkEquipText.toggling(part, on: TrunkEquipText.toggling(part, on: before).equipped)
        XCTAssertFalse(again.equipped.ids(.handle).contains(part.id), "もう一度押しても外れない")
    }

    /// 出している時間を決めた知らせは、時間が過ぎると消える（3 秒の「元に戻す」）
    @MainActor
    func testUndoToastHidesAfterGivenSeconds() async throws {
        let toasts = ToastCenter()
        toasts.show("付けました", seconds: 1, undo: ToastCenter.Undo(title: "元に戻す") { true })
        XCTAssertNotNil(toasts.undo)
        try await Task.sleep(nanoseconds: 1_400_000_000)
        XCTAssertNil(toasts.current, "決めた時間を過ぎても消えない")
        XCTAssertNil(toasts.undo)
    }

    func testWording() {
        let part = TrunkPartCatalog.parts(of: .lock)[0]
        XCTAssertEqual(TrunkPartsBoxText.equippedNotice(part, on: false), "「\(part.name)」を外しました")
        XCTAssertEqual(TrunkPartsBoxText.missingTitle, "まだ持っていない部品です")
        XCTAssertEqual(TrunkPartsBoxText.missingNote(fragments: 3),
                       "カプセルを回すと出ることがあります。かけらがあと2つたまると、好きな部品と交換できます。")
        XCTAssertEqual(TrunkPartsBoxText.missingNote(fragments: 5),
                       "カプセルを回すと出ることがあります。かけらが5つあるので、この部品と交換できます。")
        XCTAssertEqual(TrunkPartsBoxText.collectedCaption(owned: 9, total: 108), "9 / 108 集めました")
        XCTAssertEqual(TrunkPartsBoxText.coinsTitle(3), "硬貨 3 枚")
        XCTAssertEqual(TrunkPartsBoxText.tapHint, "押すと付けます。もう一度押すと外します。")
        for word in [TrunkPartsBoxText.missingNote(fragments: 0), TrunkPartsBoxText.exchangeTitle, TrunkPartsBoxText.tapHint] {
            XCTAssertFalse(word.contains("・") || word.contains("·"), word)
        }
    }

    /// 「付け替える」の画面と入口は、どこにも残さない
    func testEquipScreenIsGone() throws {
        let dir = root.appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(atPath: dir.path)?.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") } ?? []
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("TrunkEquipView("), "\(file) に付け替えの画面が残っている")
            XCTAssertFalse(text.contains("\"trunk.parts.equip\""), "\(file) に付け替えの入口が残っている")
        }
    }
}
