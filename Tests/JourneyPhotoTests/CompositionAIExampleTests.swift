import XCTest
@testable import JourneyPhoto

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
            XCTAssertTrue(["individual", "photo"].contains(entry.source), "\(kind) は個別制作でも実写真でもない")
            let file = url.appendingPathComponent("composition-ai-\(kind).jpg")
            let data = try Data(contentsOf: file)
            let size = try XCTUnwrap(Self.jpegSize(data), "\(kind) の寸法が読めない")
            XCTAssertEqual(size.width, entry.width)
            XCTAssertEqual(size.height, entry.height)
            XCTAssertGreaterThanOrEqual(min(size.width, size.height), ledger.minimumShortSide, kind)
            XCTAssertEqual(Double(size.width) / Double(size.height), 0.75, accuracy: 0.01, kind)
        }
        XCTAssertEqual(bundled, Set(ledger.accepted.keys), "台帳と絵の入れ物が食い違っている")
        XCTAssertLessThan(bundled.count, 37, "37種類そろったと数えない。未確認の構図が残っている")
        for kind in ledger.held.keys {
            XCTAssertFalse(bundled.contains(kind), "\(kind) は不採用なのに登録されている")
        }
    }

    /// 実写真の作例（source: photo）は、出典の記録・アプリの札（「作例写真」）と食い違わない。
    /// 表記の要らない許諾（CC0・パブリックドメイン・Unsplash・Pexels）だけを置く
    func testPhotoExamplesHaveSourcesAndAreNotLabeledAI() throws {
        let ledger = try JSONDecoder().decode(ReviewLedger.self,
                                              from: Data(contentsOf: root.appendingPathComponent("docs/composition-ai-review.json")))
        let photoKinds = Set(ledger.accepted.filter { $0.value.source == "photo" }.keys)
        XCTAssertEqual(photoKinds, Set(CompositionExample.photoKinds.map(\.rawValue)),
                       "台帳の実写真とアプリの photoKinds が食い違っている")
        let sourcesURL = root.appendingPathComponent("Tools/composition-examples/photo-sources.json")
        let sources = try JSONDecoder().decode(PhotoSources.self, from: Data(contentsOf: sourcesURL))
        XCTAssertEqual(Set(sources.photos.keys), photoKinds, "出典の記録と台帳の実写真が食い違っている")
        let allowed: Set<String> = ["CC0", "Public domain", "Unsplash License", "Pexels License"]
        for (kind, photo) in sources.photos {
            XCTAssertTrue(allowed.contains(photo.license), "\(kind) の許諾 \(photo.license) は表記なしで使えない")
            XCTAssertTrue(photo.sourceURL.hasPrefix("https://"), kind)
            XCTAssertFalse(photo.checked.isEmpty, kind)
        }
        for kind in CompositionKind.allCases {
            let caption = CompositionExample.bundledCaption(for: kind)
            if CompositionExample.photoKinds.contains(kind) {
                XCTAssertFalse(caption.contains("AI"), "\(kind.rawValue) は写真なのに AI と書いている")
            } else {
                XCTAssertTrue(caption.contains("AI"), "\(kind.rawValue) は AI の絵なのに写真と書いている")
            }
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

    private struct PhotoSources: Decodable {
        let photos: [String: Photo]
    }

    private struct Photo: Decodable {
        let sourceURL: String
        let license: String
        let checked: String
    }

    private struct Entry: Decodable {
        let source: String
        let width: Int
        let height: Int
    }
}
