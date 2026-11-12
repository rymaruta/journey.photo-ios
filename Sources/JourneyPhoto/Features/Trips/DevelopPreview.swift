import SwiftUI
import UIKit

/// 画面写真の試験だけ: 端末の写真の代わりに、同梱の見本の絵で旅を作る（`PreviewSession.develop`・Debug のみ）。
/// ①現像の札と画面・②「1年前」の輪と閲覧を撮るのに使う。Release では旅を作らない（`trips` は空）
enum DevelopPreview {

    static let idPrefix = "preview-develop:"

    /// 見本の絵（構図の見本）
    private static let assets = [
        "composition-ai-goldenSpiral", "composition-ai-horizon", "composition-ai-diagonals",
        "composition-ai-frameWithin", "composition-ai-negativeSpace", "composition-ai-radial",
        "composition-ai-lShape", "composition-ai-halves", "composition-ai-cCurve", "composition-ai-armature",
        "composition-ai-hinomaru", "composition-ai-grid4",
    ]

    static func isSample(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    /// 見本の1枚の絵
    static func image(for id: String) -> UIImage? {
        guard isSample(id) else { return nil }
        return UIImage(named: String(id.dropFirst(idPrefix.count)))
    }

    /// 見本の旅（帰ってきたばかりの3日の旅と、1年前の今日の旅）。見本でなければ空
    static func trips(now: Date = Date()) -> [LibraryTrip] {
        guard PreviewSession.develop else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: now)
        // 帰ってきた旅: 3日前に始まり2日前に終わった（金沢のあたり）
        let recent = make(start: calendar.date(byAdding: .day, value: -4, to: today) ?? today, days: 3,
                          perDay: 4, lat: 36.56, lng: 136.65, offset: 0, calendar: calendar)
        // 1年前の今日を含む旅（2日目が今日の1年前）
        let yearAgoDay = calendar.date(byAdding: .year, value: -1, to: today) ?? today
        let old = make(start: calendar.date(byAdding: .day, value: -1, to: yearAgoDay) ?? yearAgoDay, days: 3,
                       perDay: 3, lat: 24.33, lng: 124.09, offset: 4, calendar: calendar)
        return [recent, old]
    }

    /// 見本の地名（旅の id → 地名）
    static func names(now: Date = Date()) -> [String: String] {
        let made = trips(now: now)
        guard made.count == 2 else { return [:] }
        return [made[0].id: "金沢市", made[1].id: "竹富町"]
    }

    private static func make(start: Date, days: Int, perDay: Int, lat: Double, lng: Double, offset: Int,
                             calendar: Calendar) -> LibraryTrip {
        var shots: [LibraryShot] = []
        for d in 0..<days {
            for k in 0..<perDay {
                let date = start.addingTimeInterval(Double(d) * 86_400 + 9 * 3600 + Double(k) * 2 * 3600)
                let asset = assets[(offset + d * perDay + k) % assets.count]
                shots.append(LibraryShot(id: "\(idPrefix)\(asset)", date: date,
                                         lat: lat + Double(d) * 0.05, lng: lng + Double(k) * 0.01))
            }
        }
        // 見本の id は絵の名前なので、同じ絵が2つの旅に出ても重ならないよう日時で決める旅の id を付ける
        let found = LibraryTrips.find(shots, home: (lat: 35.68, lng: 139.76), timeZone: calendar.timeZone)
        return found.first ?? LibraryTrip(id: "preview", shots: shots, start: start, end: start, days: [],
                                          center: nil, timeZone: calendar.timeZone)
    }
}

/// 端末の写真の1枚（①現像のコマ・②の閲覧）。**読めなかったら `onFailed`**（章: 読めない写真は飛ばす）。
/// 読み込み中は読み込み中の地（surface-4）。見本の id は同梱の絵（`DevelopPreview`）
struct LibraryShotImage: View {

    let id: String
    /// 読む縮小の一辺（pt）
    let side: CGFloat
    var onFailed: () -> Void = {}

    @State private var image: UIImage?

    var body: some View {
        WebTheme.surface4
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .task(id: id) {
                image = nil
                if let sample = DevelopPreview.image(for: id) {
                    image = sample
                    return
                }
                let loaded = await LibraryThumbnails.shared.image(for: id, pixels: side * 3)
                if Task.isCancelled { return }
                if let loaded { image = loaded } else { onFailed() }
            }
    }
}
