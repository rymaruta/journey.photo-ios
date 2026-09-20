import Foundation

/// 年表の束ね方。**SwiftUI に依存させない**——画面を持たない層に置くことで、
/// Linux 上の `swift test` で本当に型検査とテストができる（Xcode が無い
/// 環境で唯一まともに検証できる層）。
enum PhotoTimeline {

    struct Section: Identifiable {
        let id: String
        let title: String
        let photos: [Photo]
    }

    /// 保存されている文字列から年月を取り出す。
    ///
    /// **`Date` に変換しない。** 撮影日は `"2024-10-12"` という日付だけの
    /// 形で保存されていて、UTC 0時として読んだうえで端末のゾーンに直すと
    /// **西側の利用者には1日前に見える**（Web 側 `lib/utils/photoDate.ts` が
    /// 同じ穴を踏んで、変換をやめた）。書かれている通りに切る。
    static func yearMonth(of photo: Photo) -> (year: Int, month: Int)? {
        for candidate in [photo.date, photo.exif?.dateTimeOriginal, photo.createdAt] {
            guard let text = candidate?.trimmingCharacters(in: .whitespaces), text.count >= 7 else { continue }
            // "2026-09-13..." と、EXIF の "2026:09:13 ..." の両方を受ける
            let digits = text.prefix(7)
            let separator = digits[digits.index(digits.startIndex, offsetBy: 4)]
            guard separator == "-" || separator == ":" else { continue }
            let year = Int(digits.prefix(4))
            let month = Int(digits.suffix(2))
            if let year, let month, (1...12).contains(month) { return (year, month) }
        }
        return nil
    }

    /// 新しい月から順に。**年月が読めない写真は最後にまとめる**
    /// ——落とすと「一覧には在るのに年表に出ない」写真ができる。
    static func group(_ photos: [Photo]) -> [Section] {
        var buckets: [String: [Photo]] = [:]
        var unknown: [Photo] = []
        for photo in photos {
            guard let (year, month) = yearMonth(of: photo) else {
                unknown.append(photo)
                continue
            }
            buckets[String(format: "%04d-%02d", year, month), default: []].append(photo)
        }
        var sections = buckets.keys.sorted(by: >).map { key -> Section in
            let year = key.prefix(4)
            let month = Int(key.suffix(2)) ?? 0
            return Section(id: key, title: "\(year)年 \(month)月", photos: buckets[key] ?? [])
        }
        if !unknown.isEmpty {
            sections.append(Section(id: "unknown", title: "日付なし", photos: unknown))
        }
        return sections
    }
}
