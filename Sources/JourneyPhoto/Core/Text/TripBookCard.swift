import Foundation

/// 旅の一冊を**1枚の画像**にして配る（2026-09-30・owner の判断「次」の段）。
///
/// 今の共有は題と期間の文だけで、受け取った人には旅の姿が見えなかった。表紙の写真の上に
/// 題・期間・数字を載せた縦長の1枚（4:5・SNS の縦の枠にそのまま入る）を作る。
///
/// **載せるのは一冊の画面に出ている文字と数だけ**（作り話をしない）。距離は画面と同じく
/// 「直線」と書く（道のりではない・`TravelDistance`）。URL は載せない（一冊にはサイトの
/// ページが無い・`TripBook.shareText`）。載せるのはサイトの名前だけ。
///
/// 描くのは `TripBookCardRenderer`（UIKit）。ここは文字と切り抜きの計算だけで、Linux で試験する。
enum TripBookCard {

    /// 画像の大きさ（px）。4:5 の縦長
    static let size = CGSize(width: 1080, height: 1350)

    struct Lines: Equatable {
        /// 眉ラベル（写真の上なので白で描く）
        let eyebrow: String
        let title: String
        /// 「2026.09.12 — 09.14 · 3日間」
        let period: String
        /// 「24枚 · 撮影地 5 · 移動（直線）312 km」。数えられない距離は載せない
        let stats: String
        /// 右下の名前
        let footer: String
    }

    static func lines(of trip: TripBook.Trip, distance: Double?) -> Lines {
        var stats = [
            L("\(trip.photos.count)枚", trip.photos.count == 1 ? "1 photo" : "\(trip.photos.count) photos"),
            L("撮影地 \(TripBook.placeCount(of: trip.photos))", "\(TripBook.placeCount(of: trip.photos)) places"),
        ]
        // 「—」は画面の枠の中なら読めるが、1行の文では何のことか分からない。数えられなければ載せない
        if let distance {
            stats.append(L("移動（直線）\(TripBook.distanceText(distance)) km",
                           "\(TripBook.distanceText(distance)) km (straight line)"))
        }
        return Lines(eyebrow: "TRIP BOOK",
                     title: TripBook.title(of: trip),
                     period: "\(TripBook.dateRange(from: trip.start, to: trip.end)) · \(TripBook.daysLabel(trip.days))",
                     stats: stats.joined(separator: " · "),
                     footer: "Journey Photo")
    }

    /// 表紙の写真を枠いっぱいに切り抜いて置く位置（はみ出しは切る）。
    ///
    /// **持ち主が選んだ中心（`Photo.focalPoint`・0〜1）を残す**——一覧の切り抜きと同じ考え。
    /// 中心が端に寄っていても、写真の外（黒い隙間）は見せない
    static func coverRect(image: CGSize, in canvas: CGSize, focal: Photo.FocalPoint?) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: canvas) }
        let scale = max(canvas.width / image.width, canvas.height / image.height)
        let drawn = CGSize(width: image.width * scale, height: image.height * scale)
        let fx = min(max(focal?.x ?? 0.5, 0), 1)
        let fy = min(max(focal?.y ?? 0.5, 0), 1)
        let x = min(0, max(canvas.width - drawn.width, canvas.width / 2 - fx * drawn.width))
        let y = min(0, max(canvas.height - drawn.height, canvas.height / 2 - fy * drawn.height))
        return CGRect(x: x, y: y, width: drawn.width, height: drawn.height)
    }

    /// 書き出すファイルの名前。**旅ごとに1つ**（同じ旅を何度共有しても増えない）。
    /// 旅の鍵は日付などの記号を含みうるので、英数字以外は落とす
    static func fileName(for trip: TripBook.Trip) -> String {
        let safe = trip.id.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
        let stem = String(String.UnicodeScalarView(safe)).prefix(40)
        return "trip-book-\(stem.isEmpty ? "card" : String(stem)).jpg"
    }
}
