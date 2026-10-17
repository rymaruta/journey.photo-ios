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
            XCTAssertEqual(entry.source, "photo", "\(kind) は実写真ではない")
            let file = url.appendingPathComponent("composition-ai-\(kind).jpg")
            let data = try Data(contentsOf: file)
            let size = try XCTUnwrap(Self.jpegSize(data), "\(kind) の寸法が読めない")
            XCTAssertEqual(size.width, entry.width)
            XCTAssertEqual(size.height, entry.height)
            XCTAssertGreaterThanOrEqual(min(size.width, size.height), ledger.minimumShortSide, kind)
            XCTAssertEqual(Double(size.width) / Double(size.height), 0.75, accuracy: 0.01, kind)
        }
        XCTAssertEqual(bundled, Set(ledger.accepted.keys), "台帳と絵の入れ物が食い違っている")
        for kind in ledger.held.keys {
            XCTAssertFalse(bundled.contains(kind), "\(kind) は不採用なのに登録されている")
        }
    }

    /// 作例が無くてよい構図と、その理由。**空が正しい**（2026-10-16 に37種類そろった）。
    /// 合う写真が見つからない構図を残すときだけ、理由を書いてここに足す（台帳の `held` にも同じ構図を書く）
    static let allowedMissing: [CompositionKind: String] = [:]

    /// 2026-10-16 owner「黄金螺旋など、まだ作例の写真が無い構図がある」: **全37種類（向きのある構図も
    /// 1枚で全部の向きを兼ねる）に作例の写真がある**か、理由つきで許した一覧に載っている。
    /// 足した4枚（goldenSpiral・thirdsDiagonals・dynamicSymmetry・triangle）を外すとここで落ちる
    func testEveryCompositionHasAnExamplePhotoOrAReason() throws {
        let ledger = try JSONDecoder().decode(ReviewLedger.self,
                                              from: Data(contentsOf: root.appendingPathComponent("docs/composition-ai-review.json")))
        let assets = root.appendingPathComponent("Sources/JourneyPhoto/Assets.xcassets")
        for kind in CompositionKind.allCases {
            let file = assets.appendingPathComponent("composition-ai-\(kind.rawValue).imageset/composition-ai-\(kind.rawValue).jpg")
            let hasPhoto = FileManager.default.fileExists(atPath: file.path)
            if let reason = Self.allowedMissing[kind] {
                XCTAssertFalse(hasPhoto, "\(kind) は作例があるのに、無い一覧に残っている")
                XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty, "\(kind) の無い理由が空")
            } else {
                XCTAssertTrue(hasPhoto, "\(kind) に作例の写真が無い（無いままにするなら allowedMissing に理由を書く）")
                XCTAssertNotNil(ledger.accepted[kind.rawValue], "\(kind) が確認台帳に無い")
            }
        }
        XCTAssertEqual(Set(ledger.held.keys), Set(Self.allowedMissing.keys.map(\.rawValue)),
                       "台帳の held（不採用）と、作例の無い構図の一覧が食い違っている")
    }

    /// 作例は**すべて実写真**（source: photo）で、出典の記録と食い違わない。アプリの札に「AI」と書かない。
    /// 表記の要らない許諾（CC0・パブリックドメイン・Unsplash・Pexels）だけを置く。
    ///
    /// 2026-10-15: 残りの21枚も写真にしたので、AI の絵（source: individual）を戻すとここで落ちる
    func testAllExamplesArePhotosWithSourcesAndAreNotLabeledAI() throws {
        let ledger = try JSONDecoder().decode(ReviewLedger.self,
                                              from: Data(contentsOf: root.appendingPathComponent("docs/composition-ai-review.json")))
        for (kind, entry) in ledger.accepted {
            XCTAssertEqual(entry.source, "photo", "\(kind) が実写真ではない（AI の絵は入れない）")
        }
        let photoKinds = Set(ledger.accepted.keys)
        let sourcesURL = root.appendingPathComponent("Tools/composition-examples/photo-sources.json")
        let sources = try JSONDecoder().decode(PhotoSources.self, from: Data(contentsOf: sourcesURL))
        XCTAssertEqual(Set(sources.photos.keys), photoKinds, "出典の記録と台帳の実写真が食い違っている")
        let allowed: Set<String> = ["CC0", "Public domain", "Unsplash License", "Pexels License"]
        for (kind, photo) in sources.photos {
            XCTAssertTrue(allowed.contains(photo.license), "\(kind) の許諾 \(photo.license) は表記なしで使えない")
            XCTAssertTrue(photo.sourceURL.hasPrefix("https://"), kind)
            XCTAssertFalse(photo.checked.isEmpty, kind)
            // 出典・作者・許諾の根拠・元の写真の URL（Unsplash から Commons に移った写真）を記録する（2026-10-16）
            XCTAssertFalse(photo.author.trimmingCharacters(in: .whitespaces).isEmpty, "\(kind) の作者が無い")
            XCTAssertFalse(photo.licenseEvidence.isEmpty, "\(kind) の許諾の根拠が無い")
            XCTAssertFalse(photo.subject.isEmpty, "\(kind) の写真の説明が無い")
            if photo.sourceURL.contains("(Unsplash)") {
                XCTAssertTrue(photo.originalURL?.hasPrefix("https://unsplash.com/photos/") ?? false, "\(kind) の元の URL が無い")
            }
        }
        XCTAssertFalse(CompositionExample.bundledCaption.contains("AI"), "写真の作例を AI と書いている")
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
        let subject: String
        let sourceURL: String
        let originalURL: String?
        let author: String
        let license: String
        let licenseEvidence: String
        let checked: String
    }

    private struct Entry: Decodable {
        let source: String
        let width: Int
        let height: Int
    }
}
