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
        ]
        // 撮影地の分かる写真が無い旅は「撮影地 0」「0 places」と書かずに載せない（2026-10-09）。
        // 英語は1か所なら単数
        let places = TripBook.placeCount(of: trip.photos)
        if places > 0 {
            stats.append(L("撮影地 \(places)", places == 1 ? "1 place" : "\(places) places"))
        }
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

    // MARK: - 置き方（`TripBookCardRenderer` が使う・ここで試験する）

    /// 左右と下の余白（px）
    static let margin: Double = 72
    /// 題は2行まで。**長い撮影地名で上にはみ出さない**（67ae0a7 のレビュー）
    static let titleMaxLines = 2
    /// 眉ラベルと題・題と期間・期間と数字の間（px）
    static let gaps: [Double] = [20, 22, 18]
    /// 暗くする段の数（多いほど段が見えない）
    static let shadeSteps = 48
    /// 文字の上から、さらにこれだけ上から暗くし始める（px）
    static let shadeLead: Double = 220

    /// 文字のかたまりの上端。下の余白から上へ積む（眉ラベル・題・期間・数字の高さ）
    static func textTop(canvasHeight: Double, heights: [Double]) -> Double {
        let total = heights.reduce(0, +) + gaps.reduce(0, +)
        return max(margin, canvasHeight - margin - total)
    }

    /// 暗くし始める高さ。**文字の上から決める**（題が2行でも眉ラベルが明るい写真の上に乗らない）。
    /// 少なくとも下の4割は暗くする（一冊の画面の表紙と同じ見え方）
    static func shadeTop(textTop: Double, canvasHeight: Double) -> Double {
        max(0, min(canvasHeight * 0.6, textTop - shadeLead))
    }

    /// 段ごとの暗さ（上は薄く、下は 0.85）
    static func shadeAlpha(step: Int) -> Double {
        0.85 * Double(min(max(step, 0), shadeSteps - 1) + 1) / Double(shadeSteps)
    }

    /// 枠を埋めるのに要る大きさ（元より大きくはしない）。縮めて展開するときの目標
    static func fillSize(image: CGSize, canvas: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return image }
        let scale = min(1, max(canvas.width / image.width, canvas.height / image.height))
        // 切り上げは誤差を吸ってから（2025.0000001 を 2026 にしない）
        return CGSize(width: (image.width * scale - 1e-6).rounded(.up), height: (image.height * scale - 1e-6).rounded(.up))
    }

    // MARK: - ファイル

    /// 書き出す場所。**一時置き場の中の専用のフォルダ**——サインアウト・退会でフォルダごと消す
    /// （表紙の写真が、非公開のものも含めて次の人の端末の中に残らないように）。
    /// 画面を閉じたときには消さない（一冊から写真を開いて戻っただけで画像が消え、共有が文に戻った）
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("trip-book-cards", isDirectory: true)
    }

    /// 1枚を書き出す。**書けなければ nil**
    static func write(_ data: Data, for trip: TripBook.Trip, in directory: URL = TripBookCard.directory) -> URL? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(fileName(for: trip))
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    /// 書き出した画像を全部消す（サインアウト・退会）
    static func removeAll(in directory: URL = TripBookCard.directory) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 書き出すファイルの名前。**旅ごとに1つ**（同じ旅を何度共有しても増えない）。
    /// 旅の鍵は日付などの記号を含みうるので、英数字以外は落とす
    static func fileName(for trip: TripBook.Trip) -> String {
        let safe = trip.id.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
        let stem = String(String.UnicodeScalarView(safe)).prefix(40)
        return "trip-book-\(stem.isEmpty ? "card" : String(stem)).jpg"
    }
}
