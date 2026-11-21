import XCTest
import SwiftUI
@testable import JourneyPhoto

/// **自前の消すボタンは赤の塗りに白の太字**（2026-11-21 owner「一般的な削除するの色にしたい」「水平展開お願い」・札 #679）。
///
/// 前は危険の線（赤の字・赤 40% の線）と、確かめの「削除する」（白の字・赤 16% の地・赤 50% の線）に割れていた。
/// 消す形は `JPOutlineTone.danger` 1つにまとめ、削除の確かめの札は `JPDeleteConfirm` 1つを通す。
/// 新しく足した消すボタンが線の形に戻らないよう、ここで見張る。
/// 系統の部品（確認のダイアログ・メニュー・スワイプ・`role: .destructive`）はこの試験の外（もう iOS のふつうの赤）
final class DestructiveButtonFillTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
    }

    /// 注記（`//`・`///`）の行を除いたソース
    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: sourceRoot.appendingPathComponent(path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func allSources() throws -> [(path: String, text: String)] {
        guard let walker = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) else {
            XCTFail("Sources が読めない")
            return []
        }
        var out: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let rel = url.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
            out.append((rel, try source(rel)))
        }
        XCTAssertGreaterThan(out.count, 100, "Sources のファイルを見つけられていない")
        return out
    }

    // MARK: - 色

    /// 白の字と赤の塗りの字の線: 塗りは `dangerFill`（#C8323A）で白 5.29:1。15pt の副ボタン（大きな字ではない）でも 4.5:1 に届く。
    /// 危険の字の色 #F0565A の塗りは白 3.39:1 で、17pt の太字（大きな字・3:1）には届くが 15pt には届かない
    func testFillContrast() {
        XCTAssertEqual(BrandPalette.dangerFill, 0xC8323A)
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(0xFFFFFF, BrandPalette.dangerFill), 4.5,
                                    "白の字と赤の塗りが 4.5:1 に届かない")
        XCTAssertLessThan(BrandPalette.contrast(0xFFFFFF, BrandPalette.danger), 4.5,
                          "（前提）字の赤 #F0565A の塗りは 15pt の白の字に足りない。塗りは dangerFill を使う")
        // 塗りの面が地（surface #0E0E0F）から見分けられる（部品の 3:1）
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(BrandPalette.dangerFill, BrandPalette.surface), 3)
    }

    /// 消す形は赤の塗り・白の字・縁なし（線の形に戻らない）
    @MainActor
    func testDangerToneIsFilled() {
        XCTAssertEqual(JPOutlineTone.danger.fill, WebTheme.dangerFill, "消すボタンが赤の塗りでない")
        XCTAssertEqual(JPOutlineTone.danger.text, WebTheme.foreground, "消すボタンの字が白でない")
        XCTAssertEqual(JPOutlineTone.danger.border, Color.clear, "消すボタンに線が残っている")
        XCTAssertEqual(JPOutlineTone.plain.fill, Color.clear)
        XCTAssertEqual(JPPillStyle.danger.fill, WebTheme.dangerFill, "退会の最後のボタンと同じ赤でない")
        XCTAssertEqual(TrunkButtonFace.fill(.danger), WebTheme.dangerFill, "トランクの削除が赤の塗りでない")
        XCTAssertEqual(TrunkButtonFace.fill(.secondary), Color.clear)
    }

    /// 確かめの札のボタンは 50・字は折り返す（大きな文字で「キャンセル」が切れない）
    func testConfirmSize() {
        XCTAssertEqual(JPOutlineSize.confirm.height, 50)
        XCTAssertGreaterThanOrEqual(JPOutlineSize.confirm.height, WebTheme.minTapTarget)
        XCTAssertTrue(JPOutlineSize.confirm.wraps)
        XCTAssertFalse(JPOutlineSize.regular.wraps)
    }

    // MARK: - 部品

    /// 確かめの札: 問いは headline（17 semibold）の白、ボタンは「キャンセル｜削除する」、横に入らなければ縦に積んで消す側が上
    func testDeleteConfirmComponent() throws {
        let parts = try source("Core/Design/FormParts.swift")
        guard let start = parts.range(of: "struct JPDeleteConfirm: View {") else { return XCTFail("JPDeleteConfirm が無い") }
        let body = String(parts[start.upperBound...].prefix(4000))
        XCTAssertTrue(body.contains(".font(JPFont.headline)"), "問いの字が 17pt でない")
        XCTAssertTrue(body.contains(".foregroundStyle(WebTheme.text)"), "問いの字が白でない")
        XCTAssertTrue(body.contains("ViewThatFits(in: .horizontal)"), "大きな文字で縦に積まない")
        let order = ["HStack(spacing: JPSpace.xs) {", "cancelButton", "confirmButton", "VStack(spacing: JPSpace.xs) {",
                     "confirmButton", "cancelButton"]
        var cursor = body.startIndex
        for part in order {
            guard let found = body.range(of: part, range: cursor..<body.endIndex) else {
                return XCTFail("並びが違う: 「\(part)」")
            }
            cursor = found.upperBound
        }
        XCTAssertTrue(body.contains(".jpOutlineButton(.confirm, tone: .danger, fullWidth: true)"), "「削除する」が赤の塗りでない")
        XCTAssertTrue(body.contains(".jpOutlineButton(.confirm, tone: .plain, fullWidth: true)"), "キャンセルが線のボタンでない")
        XCTAssertTrue(body.contains(".padding(JPSpace.l)"), "札の内側が 20 でない")
    }

    /// 消す形の古い作り（赤 16% の地・赤 50% の線・赤 40% の線）が戻っていない
    func testNoOutlinedDestructiveButtons() throws {
        for (path, text) in try allSources() {
            XCTAssertFalse(text.contains("tone: .strong"), "\(path): 確かめの古い形（赤 16% の地）")
            XCTAssertFalse(text.contains("strong: true, fill: true"), "\(path): 確かめの札を画面に書いている（JPDeleteConfirm を使う）")
            XCTAssertFalse(text.contains("strongFillOpacity") || text.contains("strongLineOpacity") || text.contains("dangerLineOpacity"),
                           "\(path): 赤の線の濃さが残っている")
        }
    }

    /// 旅行プランの3つの確かめが共通の札を通る。消す入口のボタン（DM・グループ・トランク）は消す形
    func testConfirmsAndEntriesUseSharedParts() throws {
        let detail = try source("Features/Trips/TripPlanDetailView.swift")
        XCTAssertEqual(detail.components(separatedBy: "JPDeleteConfirm(").count - 1, 2, "日の削除とプランの削除")
        let offline = try source("Features/Trips/OfflineTripCard.swift")
        XCTAssertTrue(offline.contains("JPDeleteConfirm(question:"), "端末から削除の確かめ")
        XCTAssertTrue(offline.contains("carded: false"), "電波なしの札の中に二重の札を開いている")
        XCTAssertTrue(try source("Features/Messages/DMConversationView.swift")
            .contains("Text(L(\"会話を削除\", \"Delete conversation\")).jpOutlineButton(.regular, tone: .danger"))
        XCTAssertTrue(try source("Features/Messages/GroupConversationView.swift")
            .contains("Text(L(\"受信箱から消す\", \"Remove from inbox\")).jpOutlineButton(.regular, tone: .danger"))
        XCTAssertTrue(try source("Features/Trunk/TrunkPocketView.swift")
            .contains("TrunkButtonFace(title: Labels.Common.delete, kind: .danger)"))
    }
}
