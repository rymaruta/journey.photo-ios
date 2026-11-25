import XCTest
@testable import JourneyPhoto

/// 探すの「人気の撮影地」を作る速さ（2026-11-25 札 #594・Mac run 1786 で探すを開いた時の止まりに
/// `DiscoverySections.stripCountry` が当たっていた）。
///
/// 前の作り方（写真1枚ごとに札の名前を作り、札ごとに全部の写真を `photoIsIn` に通す・欠片ごとに国名の語を作る）を
/// この試験の中に写しておき、**答えが同じ**ことと、**同じ台で測って3倍以上速い**ことを確かめる。
/// 直しを戻すと、速さの比が 1 に近くなって落ちる
final class DiscoverySectionsSpeedTests: XCTestCase {

    private func photo(_ id: String, place: String?, likes: Int) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"",
                      "\"createdAt\":\"2026-01-01\"", "\"category\":\"風景\"", "\"likes\":\(likes)"]
        if let place { fields.append("\"location\":\"\(place)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 本番に出てくる形の撮影地（国名だけ・国名つき・郵便番号・大きい順・英語・空白つき）
    private let places: [String?] = [
        "京都", "京都府 京都市", "パリ, フランス", "フランス", "フランス ヴェルサイユ",
        "ヴェルサイユ, Versailles, イヴリーヌ, 78000, フランス",
        "蔵王キツネ村, 南蔵王七ヶ宿線, 福岡八宮, 白石市, 宮城県, 989-0733, 日本",
        "宮城県, 白石市, 蔵王キツネ村", "Kyoto Japan", "Japan", "Turkey Hill", "日本　富士山",
        "東京都 渋谷区", "渋谷", "金沢", "石川県 金沢市", "Helsinki, Finland", "ヘルシンキ, フィンランド",
        "富士山", "河口湖, 山梨県", nil, "", "  ", "ニューヨーク, アメリカ", "united states",
        "台湾 台北", "台北, 台湾", "ソウル 韓国", "沖縄", "那覇市, 沖縄県",
    ]

    private func library(copies: Int) throws -> [Photo] {
        var photos: [Photo] = []
        for copy in 0..<copies {
            for (index, place) in places.enumerated() {
                photos.append(try photo("p\(copy)-\(index)", place: place, likes: (copy * 7 + index * 3) % 11))
            }
        }
        return photos
    }

    func testSameSpotsAsBefore() throws {
        for copies in [1, 3, 8] {
            let photos = try library(copies: copies)
            for limit in [6, 100] {
                XCTAssertEqual(DiscoverySections.popularSpots(in: photos, limit: limit),
                               Before.popularSpots(in: photos, limit: limit), "copies=\(copies) limit=\(limit)")
            }
        }
        for place in places {
            XCTAssertEqual(DiscoverySections.spotName(place), Before.spotName(place), "\(place ?? "nil")")
        }
    }

    func testFasterThanBefore() throws {
        // 30 種類の撮影地 × 20 枚 = 600 枚（同じ旅の写真は撮影地の文字が同じ）
        let photos = try library(copies: 20)
        func best(_ work: () -> Void) -> TimeInterval {
            var times: [TimeInterval] = []
            for _ in 0..<3 {
                let start = Date()
                work()
                times.append(Date().timeIntervalSince(start))
            }
            return times.min() ?? 0
        }
        let before = best { _ = Before.popularSpots(in: photos, limit: 6) }
        let after = best { _ = DiscoverySections.popularSpots(in: photos, limit: 6) }
        print("measured [popular-spots] photos=\(photos.count) before=\(Int(before * 1000))ms after=\(Int(after * 1000))ms")
        XCTAssertLessThan(after * 3, before, "前の作り方より3倍以上速いこと（before=\(before)s after=\(after)s）")
    }

    /// 直す前（origin/main 528298de8）の作り方の写し
    private enum Before {
        static func popularSpots(in photos: [Photo], limit: Int) -> [DiscoverySections.Spot] {
            var byPlace: [String: (name: String, list: [Photo])] = [:]
            for photo in photos {
                guard let name = spotName(photo.location) else { continue }
                let key = LocationMatch.normalized(name)
                byPlace[key, default: (name: name, list: [])].list.append(photo)
            }
            return byPlace.values
                .compactMap { group -> DiscoverySections.Spot? in
                    guard let cover = GallerySort.popular.apply(group.list).first else { return nil }
                    let counted = PhotoQuery.photos(photos, in: .location(group.name)).count
                    guard counted > 0 else { return nil }
                    return DiscoverySections.Spot(id: group.name, count: counted, cover: cover)
                }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
                .prefix(limit)
                .map { $0 }
        }

        static func spotName(_ raw: String?) -> String? {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ",，、"))
                .map { stripCountry($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.isEmpty && !LocationMatch.isPostalOrNumber($0) }
            guard let first = parts.first, let last = parts.last else { return nil }
            if parts.count >= 2, LocationMatch.isAdministrative(first), !RegionList.prefectures.contains(last) {
                return last
            }
            return first
        }

        static func stripCountry(_ part: String) -> String {
            var text = part
            let table = VisitedCountries.table
            if table.contains(where: { text == $0.ja || text.caseInsensitiveCompare($0.en) == .orderedSame }) { return "" }
            for entry in table where text.hasPrefix(entry.ja + " ") || text.hasPrefix(entry.ja + "　") {
                text = String(text.dropFirst(entry.ja.count + 1)).trimmingCharacters(in: .whitespaces)
            }
            for name in table.flatMap({ [$0.ja, $0.en] }) {
                let lower = text.lowercased()
                if lower.hasSuffix(" " + name) || lower.hasSuffix("　" + name) {
                    text = String(text.dropLast(name.count + 1)).trimmingCharacters(in: .whitespaces)
                }
            }
            return text
        }
    }
}
