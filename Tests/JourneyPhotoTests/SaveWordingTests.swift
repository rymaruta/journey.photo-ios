import XCTest
@testable import JourneyPhoto

/// 写真を残す言葉は「保存」の1語にそろえる（資料「説明なしで分かるアプリ」項目3・1.1.85 束H・2026-11-12 判断）。
///
/// それまでは「とっておく」「しおり」「保存した旅」が並び、どれが同じ物か説明文で探させていた。
/// - 写真を残す: 「保存」（とっておく → 保存、しおり → 保存の印）
/// - 端末に入れる旅: 「圏外で開ける旅」（写真の保存と取り違えない）
/// - 場所は「行きたい場所」のまま（ここでは触らない）
///
/// 画面は Linux で描けないので、`L("…")` の日本語に古い言葉が残っていないことを書いてあるもので見る
/// （`NoDiscardWordingTests` と同じ形）。識別子・注記・サーバーの欄は見ない
final class SaveWordingTests: XCTestCase {

    private func uiStrings(matching pattern: String) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var bad: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated()
            where line.range(of: #"L\("[^"]*("# + pattern + ")", options: .regularExpression) != nil {
                bad.append("\(file.lastPathComponent):\(i + 1)")
            }
        }
        return bad.sorted()
    }

    func testPhotoSaveIsCalledSave() throws {
        XCTAssertEqual(try uiStrings(matching: "とっておく|とっておき|しおり"), [],
                       "写真を残す言葉に「とっておく」「しおり」が残っている（「保存」にそろえる）")
    }

    func testOfflineTripsAreNotCalledSavedTrips() throws {
        XCTAssertEqual(try uiStrings(matching: "保存した旅"), [],
                       "端末に入れる旅を「保存した旅」と呼んでいる（写真の保存と紛れる。「圏外で開ける旅」）")
    }

    func testLiftDoneMessageSaysSaved() {
        XCTAssertEqual(PhotoLift.doneMessage(.save, faceName: nil), "保存しました")
    }
}
