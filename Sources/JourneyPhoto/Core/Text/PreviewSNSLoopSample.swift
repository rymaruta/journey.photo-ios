import Foundation

/// おすすめの新しい投稿・はじめての投稿・今週のお題の参加の**見本**（UI テストだけ・`PreviewSession.snsLoopSample`・札 #537）。
///
/// 公開一覧のいちばん新しい3枚を、端末の中だけで次のように書き替える（サーバーには何も送らない）:
/// 1. 6 時間前・今週のお題のタグ・見本の持ち主（この人の公開の写真はこれだけ）→ **はじめての投稿**・新しい投稿・参加
/// 2. 30 時間前・今週のお題のタグ → 新しい投稿・参加
/// 3. 50 時間前 → 新しい投稿
/// 投稿日は今週の月曜0時より前にしない（月曜に撮ると先週になり、参加の行が出ない）。
/// 写真は読んだ欄から作り直す（`Photo` は読むだけの型なので、見本に要る欄だけを JSON から読み直す）
enum PreviewSNSLoopSample {

    /// 見本の持ち主（はじめての投稿の人）
    static let firstPosterId = "preview-first-poster"

    static func stamp(_ photos: [Photo], now: Date = Date(), calendar: Calendar = .current) -> [Photo] {
        #if DEBUG
        let newest = Array(GallerySort.new.apply(photos).prefix(3))
        guard !newest.isEmpty else { return photos }
        let theme = WeeklyTheme.current(now, calendar: calendar)
        let weekStart = WeeklyTheme.weekRange(now, calendar: calendar)?.lowerBound ?? now
        let plans: [(hours: Double, joins: Bool, owner: String?)] = [(6, true, firstPosterId), (30, true, nil), (50, false, nil)]
        var replaced: [String: Photo] = [:]
        for (photo, plan) in zip(newest, plans) {
            let at = max(now.addingTimeInterval(-plan.hours * 3_600), weekStart.addingTimeInterval(60))
            if let made = remade(photo, createdAt: at, addTag: plan.joins ? theme.tag : nil, owner: plan.owner) {
                replaced[photo.id] = made
            }
        }
        return photos.map { replaced[$0.id] ?? $0 }
        #else
        return photos
        #endif
    }

    #if DEBUG
    private static func remade(_ photo: Photo, createdAt: Date, addTag: String?, owner: String?) -> Photo? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var fields: [String: Any] = ["id": photo.id, "src": photo.src, "createdAt": formatter.string(from: createdAt)]
        let optional: [String: Any?] = [
            "thumbSrc": photo.thumbSrc, "src256": photo.src256, "thumbAvif": photo.thumbAvif, "thumbSm": photo.thumbSm,
            "thumbSmAvif": photo.thumbSmAvif, "srcAvif": photo.srcAvif, "dominantColor": photo.dominantColor,
            "category": photo.category, "location": photo.location, "published": photo.published, "likes": photo.likes,
            "displayName": photo.displayName, "width": photo.width, "height": photo.height,
            "userId": owner ?? photo.userId, "uploadedBy": owner == nil ? photo.uploadedBy : nil,
            "tags": (photo.tags ?? []) + [addTag].compactMap { $0 },
        ]
        for (key, value) in optional { if let value { fields[key] = value } }
        guard JSONSerialization.isValidJSONObject(fields),
              let data = try? JSONSerialization.data(withJSONObject: fields) else { return nil }
        return try? JSONDecoder.api.decode(Photo.self, from: data)
    }
    #endif
}
