import XCTest

/// 構図解説の写真は、1枚ずつ確認した台帳に載ったものだけを本番の絵の入れ物へ置く。
/// 一覧からの切り抜きや、短い辺が 800px に届かない仮素材は置けない。
final class CompositionAIExampleTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testOnlyReviewedIndividualPhotosAreBundled() throws {
        let ledgerURL = root.appendingPathComponent("docs/composition-ai-review.json")
        let ledger = try JSONDecoder().decode(ReviewLedger.self, from: Data(contentsOf: ledgerURL))
        XCTAssertGreaterThanOrEqual(ledger.minimumShortSide, 800)
        let assets = root.appendingPathComponent("Sources/JourneyPhoto/Assets.xcassets")
        var bundled: Set<String> = []
        let enumerator = FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("composition-ai-")
            && url.pathExtension == "imageset" {
            let kind = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "composition-ai-", with: "")
            bundled.insert(kind)
            let entry = try XCTUnwrap(ledger.accepted[kind], "\(kind) は確認台帳に無い")
            XCTAssertEqual(entry.source, "individual", "\(kind) は個別制作ではない")
            let file = url.appendingPathComponent("composition-ai-\(kind).jpg")
            let data = try Data(contentsOf: file)
            let size = try XCTUnwrap(Self.jpegSize(data), "\(kind) の寸法が読めない")
            XCTAssertEqual(size.width, entry.width)
            XCTAssertEqual(size.height, entry.height)
            XCTAssertGreaterThanOrEqual(min(size.width, size.height), ledger.minimumShortSide, kind)
            XCTAssertEqual(Double(size.width) / Double(size.height), 0.75, accuracy: 0.01, kind)
        }
        XCTAssertEqual(bundled, Set(ledger.accepted.keys), "台帳と絵の入れ物が食い違っている")
        XCTAssertEqual(bundled.count, 37, "確認済みの37種類がそろっていない")
        XCTAssertTrue(ledger.held.isEmpty, "不採用の構図が残っている")
        for kind in ledger.held.keys {
            XCTAssertFalse(bundled.contains(kind), "\(kind) は不採用なのに登録されている")
        }
    }

    /// JPEG の SOF から幅と高さ。引き伸ばした PNG を別形式で紛らわせない。
    static func jpegSize(_ data: Data) -> (width: Int, height: Int)? {
        guard data.count > 4, data[0] == 0xFF, data[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < data.count {
            if data[i] != 0xFF {
                i += 1
                continue
            }
            let marker = data[i + 1]
            if marker == 0xC0 || marker == 0xC1 || marker == 0xC2 {
                let height = Int(data[i + 5]) << 8 | Int(data[i + 6])
                let width = Int(data[i + 7]) << 8 | Int(data[i + 8])
                return (width, height)
            }
            let length = Int(data[i + 2]) << 8 | Int(data[i + 3])
            guard length >= 2 else { return nil }
            i += 2 + length
        }
        return nil
    }

    private struct ReviewLedger: Decodable {
        let minimumShortSide: Int
        let accepted: [String: Entry]
        let held: [String: String]
    }

    private struct Entry: Decodable {
        let source: String
        let width: Int
        let height: Int
    }
}
