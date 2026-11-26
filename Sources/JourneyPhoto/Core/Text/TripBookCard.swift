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
        /// 題（「蔵王キツネ村の旅」）。**地名の括弧（県・市）は入れない**——下の `region` の行に分ける
        let title: String
        /// 題の下の小さい行（「宮城県白石市」）。撮影地の名前に括弧の地域が無ければ空
        let region: String
        /// 「2026.09.12 — 09.14　3日間」（間は en space）
        let period: String
        /// 「24枚　撮影地 5　移動（直線）312 km」（間は en space）。数えられない距離は載せない
        let stats: String
        /// いちばん下のサイトの名前
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
        let place = splitPlace(LocationMatch.display(trip.place))
        return Lines(eyebrow: "TRIP BOOK",
                     title: place.region.isEmpty ? TripBook.tripTitle(of: trip)
                                                 : L("\(place.name)の旅", "Trip to \(place.name)"),
                     region: place.region,
                     period: "\(TripBook.dateRange(from: trip.start, to: trip.end))\u{2002}\(TripBook.daysLabel(trip.days))",
                     stats: stats.joined(separator: "\u{2002}"),
                     footer: "Journey Photo")
    }

    /// 画面に出す撮影地の形（`LocationMatch.display`）を、名前と、末尾の括弧の中の地域に分ける。
    ///
    /// 🔴 2026-11-26 owner（実機の画面写真）: 題「蔵王キツネ村（宮城県白石市）の旅」が
    /// 「…（宮城県白」「石市）の旅」と**地名の途中で折れた**。1080 幅の明朝 84 では1行に入らず、
    /// UIKit は和文を字の間で折る。題は「蔵王キツネ村の旅」、地域は題の下の小さい行にする
    /// （載せる文字は同じ・足しも作りもしない）。末尾が括弧でない名前はそのまま（地域は空）
    static func splitPlace(_ display: String) -> (name: String, region: String) {
        let text = display.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("（", "）"), (" (", ")")] where text.hasSuffix(close) {
            guard let start = text.range(of: open, options: .backwards) else { continue }
            let name = String(text[..<start.lowerBound]).trimmingCharacters(in: .whitespaces)
            let region = String(text[start.upperBound..<text.index(before: text.endIndex)])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !region.isEmpty else { continue }
            return (name, region)
        }
        return (text, "")
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
    /// 字の大きさ（px・1080 幅の絵の上）。板「TripBookShare」B の表紙カード（216 幅・題は明朝 22）を
    /// 5 倍した釣り合いに寄せ、行が多い（地域・数字・サイト名）ぶん少し詰めた（2026-11-26 判断）
    enum Font {
        /// 題（明朝）。**1行に入る大きさまで縮める**（`titleFit`）
        static let title: Double = 104
        static let titleMinimum: Double = 64
        /// 題の下の地域の行。1行に入るまで縮める
        static let region: Double = 38
        static let regionMinimum: Double = 28
        static let eyebrow: Double = 28
        static let period: Double = 36
        static let stats: Double = 32
        static let footer: Double = 28
    }

    /// 題は2行まで。**長い撮影地名で上にはみ出さない**（67ae0a7 のレビュー）
    static let titleMaxLines = 2

    /// 題の大きさと折った行。**語の途中では折らない**（`ShareCardText.fit`: 折るのは空白・括弧・読点の所だけ）。
    /// 和文の名前は切れ目が無いので1行に入るまで縮め、下限でも入らなければ末尾を「…」で切る
    static func titleFit(_ title: String, width: Double, measure: (String, CGFloat) -> CGFloat) -> ShareCardText.Fitted {
        ShareCardText.fit(title, maxWidth: width, preferredSize: Font.title, minimumSize: Font.titleMinimum,
                          step: 2, maxLines: { _ in titleMaxLines }, measure: measure)
    }

    /// 地域の行（1行・縮めても入らなければ末尾を「…」）
    static func regionFit(_ region: String, width: Double, measure: (String, CGFloat) -> CGFloat) -> ShareCardText.Fitted {
        ShareCardText.fit(region, maxWidth: width, preferredSize: Font.region, minimumSize: Font.regionMinimum,
                          maxLines: { _ in 1 }, measure: measure)
    }

    /// 行の間（px）。眉ラベル→題・題→地域・地域（無ければ題）→期間・期間→数字・数字→サイト名
    static let gapAfterEyebrow: Double = 16
    static let gapAfterTitle: Double = 6
    static let gapBeforePeriod: Double = 26
    static let gapAfterPeriod: Double = 10
    static let gapBeforeFooter: Double = 28

    /// 文字の上から、さらにこれだけ上から暗くし始める（px）
    static let shadeLead: Double = 260

    /// 文字のかたまりの上端。下の余白から上へ積む（行の高さと、その間の合計）
    static func textTop(canvasHeight: Double, heights: [Double], gaps: [Double]) -> Double {
        let total = heights.reduce(0, +) + gaps.reduce(0, +)
        return max(margin, canvasHeight - margin - total)
    }

    /// 暗くし始める高さ。**文字の上から決める**（題が2行でも眉ラベルが明るい写真の上に乗らない）。
    /// 少なくとも下の半分は暗くする（板「TripBookShare」の表紙カードは下 55% を暗くする）
    static func shadeTop(textTop: Double, canvasHeight: Double) -> Double {
        max(0, min(canvasHeight * 0.5, textTop - shadeLead))
    }

    /// いちばん下の暗さ（板の表紙カードは 0.8。白の小さい字が明るい写真の上でも読めるよう少し濃く）
    static let shadeMaxAlpha: Double = 0.85
    /// 文字の上端での暗さ。ここより下に白の字が乗る
    static let shadeAlphaAtText: Double = 0.55

    /// 暗くする**ひと続きのグラデーション**の止め（位置は暗くし始める所から下端までの 0〜1、暗さは黒の濃さ）。
    ///
    /// 🔴 2026-11-26 owner（実機の画面写真）: 下の4割が白→灰→黒の帯になり、**写真が消えていた**（キツネの耳の先しか
    /// 見えない）。前は 48 段の帯を `UIRectFill` で塗っていた。`UIRectFill` は**置き換え（copy）で塗る**ので、
    /// 半透明の黒が写真の画素を「半透明の黒」に置き換え、透明を持つ絵を JPEG にすると白の地に重なった色になった。
    /// いまは写真の上に**重ねて**描く（`TripBookCardRenderer.shade` の `drawLinearGradient`）。
    ///
    /// 形: 上の端は傾き 0 から入り（境目を見せない・smoothstep）、文字の上端で `shadeAlphaAtText`、
    /// そこから下端の `shadeMaxAlpha` まで真っすぐ濃くする
    static func shadeStops(top: Double, textTop: Double, bottom: Double) -> [(location: Double, alpha: Double)] {
        let span = bottom - top
        guard span > 0 else { return [(0, shadeMaxAlpha), (1, shadeMaxAlpha)] }
        let knee = min(max((textTop - top) / span, 0), 1)
        guard knee > 0 else { return [(0, shadeAlphaAtText), (1, shadeMaxAlpha)] }
        let easeSteps = 8
        var stops = (0...easeSteps).map { i -> (location: Double, alpha: Double) in
            let t = Double(i) / Double(easeSteps)
            return (knee * t, shadeAlphaAtText * t * t * (3 - 2 * t))
        }
        if knee < 1 { stops.append((1, shadeMaxAlpha)) }
        return stops
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
