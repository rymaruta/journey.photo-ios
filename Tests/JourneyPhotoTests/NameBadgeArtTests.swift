import XCTest
@testable import JourneyPhoto

/// 名前の横のバッジの絵（案 C: 大きいメダルの絵をそのまま縮める・2026-10-09 owner「そのままがいい」）
final class NameBadgeArtTests: XCTestCase {

    /// 名前の横に出しうるバッジ（決まった鍵の全段・絵のある季節の章）
    private var everyBadge: [(key: String, tier: Int)] {
        var all: [(String, Int)] = []
        for kind in BadgeCatalog.kinds {
            for tier in 1...kind.maxTier { all.append((kind.key, tier)) }
        }
        for key in ["proSpring2027", "proSummer2027", "proAutumn2026", "proWinter2026"] {
            XCTAssertTrue(BadgeCatalog.isKnown(key), key)
            all.append((key, 1))
        }
        return all
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 🔴 **名前の横は大きい絵**（棚・手に取って回す画面と同じ）。文字の帯を省いた `-s` は使わない
    func testNameSideUsesTheLargeArt() {
        for (key, tier) in everyBadge {
            let name = BadgeCatalog.nameSideImage(key, tier: tier)
            XCTAssertEqual(name, BadgeCatalog.largeImage(key, tier: tier), key)
            XCTAssertFalse(name.hasSuffix("-s"), "\(key) \(tier): \(name)")
        }
        XCTAssertEqual(BadgeCatalog.nameSideImage("prefectures", tier: 2), "medal-prefectures-2")
        XCTAssertEqual(BadgeCatalog.nameSideImage("earlyUser", tier: 1), "medal-earlyUser")
        XCTAssertEqual(BadgeCatalog.nameSideImage("proAutumn2026", tier: 1), "medal-pro-autumn-2026")
        XCTAssertEqual(BadgeCatalog.nameSideImage("supporterYear", tier: 2), "medal-year-2")
        // 選ぶ画面・お知らせの小さい絵は今までどおり
        XCTAssertEqual(BadgeCatalog.smallImage("prefectures", tier: 2), "medal-prefectures-2-s")
    }

    /// 🔴 名前の横の絵がすべて絵の入れ物に在り、**縮める元として十分大きい**（PNG の幅 520px 以上）
    func testEveryNameSideArtExistsAndIsLarge() throws {
        let assets = root.appendingPathComponent("Sources/JourneyPhoto/Assets.xcassets")
        var sets: [String: URL] = [:]
        for case let path as String in FileManager.default.enumerator(atPath: assets.path)?.allObjects ?? []
        where path.hasSuffix(".imageset") {
            sets[((path as NSString).lastPathComponent as NSString).deletingPathExtension] =
                assets.appendingPathComponent(path)
        }
        for (key, tier) in everyBadge {
            let name = BadgeCatalog.nameSideImage(key, tier: tier)
            let folder = try XCTUnwrap(sets[name], "\(key) \(tier): \(name) が無い")
            let data = try Data(contentsOf: folder.appendingPathComponent(name + ".png"))
            // PNG の IHDR: 16〜19 バイト目が幅（ビッグエンディアン）
            XCTAssertGreaterThan(data.count, 24)
            let width = data[16..<20].reduce(0) { $0 << 8 | Int($1) }
            XCTAssertGreaterThanOrEqual(width, 520, "\(name) は \(width)px")
        }
    }

    /// 🔴 **名前の横の描き方（`NameBadgeImage`）は小さい絵を引かない**
    func testNameBadgeImageDoesNotReferenceSmallArt() throws {
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Common/NameMarks.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "struct NameBadgeImage"))
        let end = try XCTUnwrap(source.range(of: "enum MyPageNameLine"))
        let body = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(body.contains("smallImage"))
        XCTAssertFalse(body.contains("\"-s\""))
        XCTAssertTrue(body.contains("nameSideImage"))
    }

    /// 円の割合は大きい絵を測った値に合う（無料 98.2%・Pro 91.2%・初期ユーザー 71.0%。後光はその外）。
    /// 円の部分は今までどおり 22pt、初期ユーザーは後光ごと 30.8pt で置いて 4.4pt を打ち消す
    func testDiscRatiosMatchTheLargeArt() {
        XCTAssertEqual(BadgeCatalog.discRatio("prefectures"), 0.984)
        XCTAssertEqual(BadgeCatalog.discRatio("supporter"), 0.984)
        XCTAssertEqual(BadgeCatalog.discRatio("supporterYear"), 0.984)
        XCTAssertEqual(BadgeCatalog.discRatio("earlyUser"), 0.715)
        XCTAssertEqual(BadgeCatalog.discRatio("proWinter2026"), 0.91)
        for (key, _) in everyBadge {
            let side = BadgeFit.imageSide(key, nameSize: 26)
            XCTAssertEqual(side * BadgeCatalog.discRatio(key), 22, accuracy: 0.1, "\(key): 円は 22pt")
            // 並びの上では円の大きさだけ取る（行の高さを変えない）
            XCTAssertEqual(side - 2 * BadgeFit.overhang(key, nameSize: 26), 22, accuracy: 0.11, key)
        }
        XCTAssertEqual(BadgeFit.imageSide("earlyUser", nameSize: 26), 30.8, accuracy: 0.0001)
        XCTAssertEqual(BadgeFit.overhang("earlyUser", nameSize: 26), 4.4, accuracy: 0.0001)
        XCTAssertEqual(BadgeFit.imageSide("proAutumn2026", nameSize: 26), 24.2, accuracy: 0.0001)
        XCTAssertEqual(BadgeFit.overhang("proAutumn2026", nameSize: 26), 1.1, accuracy: 0.0001)
    }

    /// 縮める先の画素: 画面の倍率ちょうど（3倍の画面で 22.4pt → 67px、初期ユーザー 30.8pt → 92px）
    func testRasterPixelSide() {
        XCTAssertEqual(NameBadgeRaster.pixelSide(points: 22.4, scale: 3), 67)
        XCTAssertEqual(NameBadgeRaster.pixelSide(points: 30.8, scale: 3), 92)
        XCTAssertEqual(NameBadgeRaster.pixelSide(points: 22.4, scale: 2), 45)
        XCTAssertEqual(NameBadgeRaster.pixelSide(points: 400, scale: 3), NameBadgeRaster.maxPixels, "上限で止める")
        XCTAssertNil(NameBadgeRaster.pixelSide(points: 0, scale: 3))
        XCTAssertNil(NameBadgeRaster.pixelSide(points: 22, scale: .nan))
        XCTAssertNil(NameBadgeRaster.pixelSide(points: 0.1, scale: 1))
        XCTAssertEqual(NameBadgeRaster.cacheKey(image: "medal-earlyUser", pixels: 92), "medal-earlyUser@92")
        XCTAssertNotEqual(NameBadgeRaster.cacheKey(image: "medal-night-2", pixels: 67),
                          NameBadgeRaster.cacheKey(image: "medal-night-2", pixels: 45), "倍率ごとに別に覚える")
    }

    /// 案 C の作り方（Lanczos で縮めて半径 0.8px・強さ 0.6 で輪郭を立てる）と同じ値
    func testRasterSharpenMatchesOptionC() {
        XCTAssertEqual(NameBadgeRaster.sharpenRadius, 0.8)
        XCTAssertEqual(NameBadgeRaster.sharpenIntensity, 0.6)
    }

    /// 画面写真の見本（Debug のみ）: `-JPPreviewDisplayBadge` は**入っている本人だけ**、持っている鍵だけ出す
    func testPreviewDisplayBadgeOnlyForThePreviewUser() throws {
        let defaults = UserDefaults.standard
        defaults.set("me", forKey: PreviewSession.defaultsKey)
        defaults.set("earlyUser:1,prefectures:2", forKey: PreviewSession.badgesKey)
        defaults.set("earlyUser", forKey: PreviewSession.displayBadgeKey)
        defer {
            for key in [PreviewSession.defaultsKey, PreviewSession.badgesKey, PreviewSession.displayBadgeKey] {
                defaults.removeObject(forKey: key)
            }
        }
        let me = try JSONDecoder.api.decode(UserProfile.self, from: Data(#"{"userId":"me","displayName":"丸田"}"#.utf8))
        XCTAssertEqual(me.shownBadge?.key, "earlyUser")
        let other = try JSONDecoder.api.decode(UserProfile.self,
                                               from: Data(#"{"userId":"u2","displayName":"他の人"}"#.utf8))
        XCTAssertNil(other.shownBadge, "見本の選択は本人だけ")
        defaults.set("night", forKey: PreviewSession.displayBadgeKey)
        XCTAssertNil(me.shownBadge, "持っていない鍵は出さない")
        defaults.removeObject(forKey: PreviewSession.defaultsKey)
        XCTAssertNil(PreviewSession.displayBadge, "見本の利用者で入っていなければ効かない")
    }
}
