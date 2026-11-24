import Foundation

/// UI テストで旅の記録の本棚（札 #714）を決まった中身で撮る（Debug のみ）。`-JPPreviewTripShelf empty|many`。
///
/// - `empty`: 旅が無いとき（投稿の旅も端末の旅も出さない）。旅が無いときの1行と、頭の荷札の列を撮る
/// - `many`: 旅が増えたとき。見本の利用者の写真から、3年に分けた14冊を作る（背の厚さ・高さ・段の折り返しを撮る）
///
/// 入っている見本の利用者のときだけ効く。Release では必ず効かない（中身はそのまま）
extension PreviewSession {

    static let tripShelfKey = "JPPreviewTripShelf"

    static var tripShelfMode: String? {
        #if DEBUG
        guard userId != nil else { return nil }
        return UserDefaults.standard.string(forKey: tripShelfKey)?.lowercased()
        #else
        return nil
        #endif
    }

    /// 端末の旅を棚に出さない（見本の「旅が無いとき」）
    static var hidesDeviceTrips: Bool { tripShelfMode == "empty" }

    /// 棚に並べる旅。見本でなければ渡したまま
    static func tripShelfSample(_ trips: [TripBook.Trip], photos: [Photo]) -> [TripBook.Trip] {
        switch tripShelfMode {
        case "empty": return []
        case "many": return PreviewTripShelf.many(photos: photos)
        default: return trips
        }
    }
}

/// 見本の旅（写真は見本の利用者の写真を順に使い回す。題と日付だけ見本）
enum PreviewTripShelf {

    static let places = ["金沢", "京都", "札幌", "函館", "那覇", "日光", "奈良", "高山",
                         "長崎", "鎌倉", "屋久島", "白川郷", "尾道", "小樽"]

    static func many(photos: [Photo]) -> [TripBook.Trip] {
        guard !photos.isEmpty else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let counts = [24, 12, 41, 9, 63, 15, 8, 35, 22, 51, 14, 27, 6, 18]
        let dayCounts = [3, 2, 3, 2, 4, 2, 1, 5, 3, 2, 4, 1, 2, 3]
        var cursor = 0
        return places.enumerated().map { index, place in
            // 2026 に5冊、2025 に5冊、2024 に4冊。月は新しい順
            let year = index < 5 ? 2026 : (index < 10 ? 2025 : 2024)
            let month = 11 - (index % 5) * 2
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 3 + index % 7))!
            let end = calendar.date(byAdding: .day, value: dayCounts[index] - 1, to: start)!
            // 同じ写真を1冊に2度入れない（開いた一冊の並びが写真の id で決まる）
            let count = min(counts[index], photos.count)
            // **写真の日を旅の日に置き直す**（2026-11-23 判断・1.2.0 の統合・Mac run 1765 と 1769 の
            // `testCapturesTripBookOpened`「左へ払っても1日目の見出しが出ない」）。前は見本の利用者の写真の撮影日のままで、
            // 「金沢 11.03〜11.05」の一冊の日の段が「-23日目（10.10）」「-22日目」「5日目」になり、1日目が無かった
            // （日めくりは効いていて、落ちた時の画面の木では「-23日目」の見出しが上に来ていた）。順に、旅の日数に割って置く
            let picked = (0..<count).map { offset -> Photo in
                let photo = photos[(cursor + offset) % photos.count]
                let day = offset * dayCounts[index] / count
                let at = calendar.date(byAdding: DateComponents(day: day, hour: 12), to: start)!
                return redated(photo, at: at)
            }
            cursor += 3
            return TripBook.Trip(id: "preview-shelf-\(index)", place: place, start: start, end: end,
                                 photos: picked, timeZone: TimeZone(identifier: "UTC")!,
                                 isPrivate: index == 6)
        }
    }

    /// 写真の日を `at` に置き直す（見本の中だけ・Debug のみ。Release では渡したまま）
    private static func redated(_ photo: Photo, at: Date) -> Photo {
        #if DEBUG
        return PreviewSNSLoopSample.remade(photo, createdAt: at, addTag: nil, owner: nil) ?? photo
        #else
        return photo
        #endif
    }
}
