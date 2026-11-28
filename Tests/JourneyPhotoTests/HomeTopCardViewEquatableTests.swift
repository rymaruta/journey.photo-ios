import XCTest
import SwiftUI
@testable import JourneyPhoto

/// ホームの上の札を、ホーム（`GalleryView`）が描き直されただけでは描き直さない直し（2026-11-28・Mac run 1870 の
/// 写真の詳細の往復で `home.topCard.body` 18 回・理由はすべて `chg.HomeTopCardView.@self`）の試験。
/// 札そのものは Linux の模型では描けないので、比べた結果と配線を見る
@MainActor
final class HomeTopCardViewEquatableTests: XCTestCase {

    private func photo(_ id: String, location: String = "京都") throws -> Photo {
        let json = "{\"id\":\"\(id)\",\"src\":\"https://journey-photo.com/images/\(id).jpg\",\"title\":\"t\(id)\",\"location\":\"\(location)\"}"
        return try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// ホームが渡すのと同じ形で作る。並びは毎回 `map` で新しい配列にする（ホームの `filter`・`dropped.visible` と同じ）
    private func card(theme: [Photo], mine: [Photo] = [], known: Bool = true, token: Int = 0,
                      friends: [Photo]? = nil, following: Set<String> = ["u1"], away: Bool = false,
                      shelf: Binding<HomeSeasonShelfSlot?> = .constant(nil)) -> HomeTopCardView {
        HomeTopCardView(themePhotos: theme.map { $0 }, myPhotos: mine.map { $0 }, myPhotosKnown: known,
                        reloadToken: token, seasonShelf: shelf, friendPhotos: (friends ?? theme).map { $0 },
                        followingIds: following, scrolledAway: away)
    }

    /// 🔴 中身の同じ並びを新しく作り直しただけの札は同じ。描く値が1つでも違えば違う
    func testCardsCompareOnlyWhatTheyDraw() throws {
        let a = try photo("a"), b = try photo("b")
        let base = card(theme: [a, b], mine: [a])
        XCTAssertTrue(base == card(theme: [a, b], mine: [a]), "並びを作り直しただけで描き直す")
        // 書くだけの口（季節の段）は比べない——書き先はホームの同じ `@State`
        var other: HomeSeasonShelfSlot?
        let elsewhere = Binding<HomeSeasonShelfSlot?>(get: { other }, set: { other = $0 })
        XCTAssertTrue(base == card(theme: [a, b], mine: [a], shelf: elsewhere), "書くだけの口で描き直す")

        XCTAssertFalse(base == card(theme: [a], mine: [a]), "お題の写真が替わったのに描き直さない")
        XCTAssertFalse(base == card(theme: [a, try photo("b", location: "大阪")], mine: [a]), "写真の中身が替わったのに描き直さない")
        XCTAssertFalse(base == card(theme: [a, b], mine: []), "自分の写真が替わったのに描き直さない")
        XCTAssertFalse(base == card(theme: [a, b], mine: [a], known: false))
        XCTAssertFalse(base == card(theme: [a, b], mine: [a], token: 1), "読み直しの合図で描き直さない")
        XCTAssertFalse(base == card(theme: [a, b], mine: [a], friends: [b]), "友達の写真が替わったのに描き直さない")
        XCTAssertFalse(base == card(theme: [a, b], mine: [a], following: ["u2"]))
        XCTAssertFalse(base == card(theme: [a, b], mine: [a], away: true), "流れ出たのに知らない")
    }

    /// 🔴 ホームが札を `.equatable()` で包む。札が親から受け取る値が増えたら、比べる値も見直す
    func testHomeWrapsTheCardsAndInputsAreComplete() throws {
        let gallery = try source("Sources/JourneyPhoto/Features/Gallery/GalleryView.swift")
        guard let range = gallery.range(of: "HomeTopCardView(themePhotos:") else { return XCTFail("ホームに上の札が無い") }
        let call = gallery[range.upperBound...].prefix(1200)
        guard let end = call.range(of: "scrolledAway: topCardsAway)") else { return XCTFail("札を作る所が読めない") }
        XCTAssertTrue(call[end.upperBound...].prefix(200).contains(".equatable()"), "ホームが上の札を .equatable() で包んでいない")

        let file = try source("Sources/JourneyPhoto/Features/Gallery/HomeTopCardView.swift")
        guard let head = file.range(of: "struct HomeTopCardView: View {") else { return XCTFail("HomeTopCardView が無い") }
        let body = file[head.upperBound...].components(separatedBy: "\n}\n").first ?? ""
        let passed = body.components(separatedBy: "\n")
            .filter { $0.hasPrefix("    let ") || $0.hasPrefix("    var ") || $0.hasPrefix("    @Binding var ") }
            .filter { !$0.hasSuffix("{") }
            .map { $0.trimmingCharacters(in: .whitespaces).components(separatedBy: ":").first ?? "" }
        XCTAssertEqual(passed, ["let themePhotos", "let myPhotos", "var myPhotosKnown = false", "var reloadToken",
                                "@Binding var seasonShelf", "var friendPhotos", "var followingIds", "var scrolledAway"],
                       "HomeTopCardView が親から受け取る値が変わった。HomeTopCardViewInputs も見直す")
    }
}
