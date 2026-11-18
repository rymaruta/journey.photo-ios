import Foundation

/// 共有の絵「写真の色」（2026-11-18 owner 採用・模型は Artifact「共有の絵の新しい形」の「写真の色」）。
///
/// 写真から取った**淡い色を地**に、**濃い色を字**にする。写真は**切らずに**置き、まわりを広く空ける（展示の壁のように）。
/// 写真の下に、撮影地（明朝）と、一つ上の単位（県・国）と日付。写真の上には何も重ねない。
/// ストーリー（`TravelStory.Kind.photoColor`・1080×1920）と投稿（`SignatureShareCardRenderer.Style.photoColor`・4:5・1:1・9:16）の両方で使う。
///
/// 寸法・色の取り方・字はここに1か所（Linux の `swift test` で見張る）。描くのは `PhotoColorCardRenderer`（UIKit）。
/// 仕様のメモ: 模型の `tone()`・`lay()`・`makeTone()` を 1080 幅の画素で写したもの
enum PhotoColorCard {

    // MARK: - 寸法（1080 幅の画素）

    static let width: CGFloat = 1080
    /// 写真の幅の上限（左右 108 の余白）
    static let photoMaxWidth: CGFloat = 864
    /// 字の段の高さと、写真との間
    static let blockHeight: CGFloat = 140
    static let gap: CGFloat = 56
    /// 字の段の幅の下限。**2026-11-18 判断:** 模型は字の幅＝写真の幅だが、とても細い縦長の写真（幅 600 未満）では
    /// 撮影地が入らなくなるので、そのときは 600 を真ん中に置く
    static let textMinWidth: CGFloat = 600

    /// 撮影地（明朝 Bold 56px・字間 0.04em）。段の上端から y −6。入らなければ 36 まで縮める
    static let placeY: CGFloat = -6
    static let placeSize: CGFloat = 56
    static let placeMinimumSize: CGFloat = 36
    static let placeKern: CGFloat = 0.04
    /// 下の段（県と市・日付、34px）。段の上端から y +86
    static let rowY: CGFloat = 86
    static let rowSize: CGFloat = 34
    /// 33px はインスタで 12pt（板の本文の最小）
    static let rowMinimumSize: CGFloat = 33
    static let dateKern: CGFloat = 0.02
    /// 県と市と日付の間に空ける幅
    static let rowGap: CGFloat = 32

    // MARK: - 絵の枠

    /// 絵の高さと、字を置いてよい上下の線。ストーリーと投稿で違うのはここだけ
    struct Frame: Equatable {
        let height: CGFloat
        /// 字の段の上端はこれより下（ストーリーは上 14%、投稿は短い辺の 6%）
        let textTop: CGFloat
        /// 字の段の下端がこれを越えない（ストーリーは下 20% の返信欄の上、投稿は下から短い辺の 6%）
        let textBottom: CGFloat
        /// 写真の上の余白の下限（`photoTopMinimum`・108）
        let photoTop: CGFloat
        /// 写真の上の余白を、左右の余白と同じだけ取るか（ストーリー）。投稿は縦に余りが無いので下限だけ
        var matchesSides = false

        /// ストーリー（1080×1920）
        static let story = Frame(height: 1920, textTop: 1920 * ShareCardSafeArea.storyTopFraction,
                                 textBottom: 1920 * (1 - ShareCardSafeArea.storyBottomFraction),
                                 photoTop: PhotoColorCard.photoTopMinimum, matchesSides: true)

        /// 投稿の比。9:16 はストーリーと同じ線（字の段は 4:5 のフィードの切り取りの内側にも入る・試験で見る）。
        /// 1:1 は模型に無いので 4:5 と同じ決め方（短い辺の 6%・2026-11-18 判断）
        static func post(_ ratio: SignatureShareCardRenderer.Ratio) -> Frame {
            if ratio == .story { return story }
            let height = (PhotoColorCard.width / CGFloat(ratio.rawValue)).rounded()
            let edge = min(PhotoColorCard.width, height) * ShareCardSafeArea.edgeFraction
            return Frame(height: height, textTop: edge, textBottom: height - edge, photoTop: PhotoColorCard.photoTopMinimum)
        }
    }

    /// 写真の枠と字の段
    struct Placement: Equatable {
        let photo: CGRect
        /// 字の段（左右は写真の左端と右端・`textMinWidth` より狭ければ真ん中に 600）
        let text: CGRect
    }

    /// 写真の上の余白の下限。左右の余白の下限（(1080 − 864) ÷ 2）と同じ 108。
    /// **2026-11-18 判断（owner が暦に「写真の上に余白が無くてバランスが悪い」）:** 前は投稿 72（模型の `tm`）、
    /// ストーリー 0 で、ストーリーの縦長 9:16 の写真は絵の上の端に付き、投稿の縦長は上 72・左右 158 だった
    static let photoTopMinimum: CGFloat = 108

    /// 写真の上の余白。ストーリーは左右の余白と同じ（下限 108・展示の壁のように上と左右をそろえる）、投稿は 108
    static func topMargin(photoWidth w: CGFloat, in frame: Frame) -> CGFloat {
        frame.matchesSides ? max(frame.photoTop, (width - w) / 2) : frame.photoTop
    }

    /// 写真（幅 ÷ 高さ = `aspect`）を切らずに置く（模型の `lay`）。
    /// - 幅の上限 864。高さは、上の余白（`topMargin`）＋写真＋間 56＋段 140 が字の下端の線に収まるいちばん大きい値
    ///   （0.5px 刻み。ストーリーの上の余白は写真の幅で変わるので順に見る）。左右の真ん中
    /// - 写真＋間＋段をひとまとまりにして上下の真ん中。段の下端が線を越えるなら上げる（写真の上端は上の余白まで）
    /// - 段の上端が上の線より上なら下げる
    static func place(aspect: CGFloat, in frame: Frame) -> Placement {
        let a = aspect.isFinite && aspect > 0 ? aspect : 1
        var h = photoMaxWidth / a
        while h > 1, topMargin(photoWidth: min(photoMaxWidth, h * a), in: frame) + h + gap + blockHeight
                > frame.textBottom + 0.001 {
            h -= 0.5
        }
        let w = min(photoMaxWidth, h * a)
        let top = topMargin(photoWidth: w, in: frame)
        let group = h + gap + blockHeight
        var y = (frame.height - group) / 2
        if y + group > frame.textBottom { y = frame.textBottom - group }
        if y < top { y = top }
        if y + h + gap < frame.textTop { y = frame.textTop - h - gap }
        let photo = CGRect(x: (width - w) / 2, y: y, width: w, height: h)
        let textWidth = max(w, textMinWidth)
        return Placement(photo: photo,
                         text: CGRect(x: (width - textWidth) / 2, y: photo.maxY + gap, width: textWidth,
                                      height: blockHeight))
    }

    // MARK: - 色（同じ写真なら毎回同じ）

    /// sRGB の 0〜255
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// 整数に丸めた色（描く色と明暗の比を同じにする）
        var rounded: RGB {
            func c(_ v: Double) -> Double { min(255, max(0, v.rounded())) }
            return RGB(c(red), c(green), c(blue))
        }

        var luminance: Double { ShareCardSafeArea.luminance(red: red, green: green, blue: blue) }
    }

    /// 写真を縮める一辺（64×64 の 4096 画素を見る・模型の `pixels`）
    static let sampleSide = 64
    /// まとめる色の数（模型の `palette` の K）
    static let paletteCount = 5
    /// まとめる回数
    static let paletteIterations = 14

    struct Swatch: Equatable {
        let color: RGB
        /// 画素の何割がこの色か（0〜1）
        let share: Double
    }

    /// 写真の画素を5色にまとめる（k-means・模型の `palette`）。
    /// はじめの色は明るさ順に並べた画素の 10・30・50・70・90% の所（乱数を使わないので、同じ写真なら毎回同じ）。
    /// 1% 以下の色は捨てる
    static func palette(_ pixels: [RGB]) -> [Swatch] {
        guard !pixels.isEmpty else { return [] }
        func lum(_ p: RGB) -> Double { 0.2126 * p.red + 0.7152 * p.green + 0.0722 * p.blue }
        let byLum = pixels.sorted { lum($0) < lum($1) }
        let k = paletteCount
        var centers = (0..<k).map { j in byLum[Int((Double(j) + 0.5) / Double(k) * Double(byLum.count))] }
        var labels = [Int](repeating: 0, count: pixels.count)
        for _ in 0..<paletteIterations {
            for (i, p) in pixels.enumerated() {
                var best = 0, bestDistance = Double.infinity
                for (j, q) in centers.enumerated() {
                    let d = (p.red - q.red) * (p.red - q.red) + (p.green - q.green) * (p.green - q.green)
                        + (p.blue - q.blue) * (p.blue - q.blue)
                    if d < bestDistance { bestDistance = d; best = j }
                }
                labels[i] = best
            }
            var sums = [RGB](repeating: RGB(0, 0, 0), count: k)
            var counts = [Int](repeating: 0, count: k)
            for (i, p) in pixels.enumerated() {
                let j = labels[i]
                counts[j] += 1
                sums[j].red += p.red; sums[j].green += p.green; sums[j].blue += p.blue
            }
            centers = centers.indices.map { j in
                counts[j] > 0 ? RGB(sums[j].red / Double(counts[j]), sums[j].green / Double(counts[j]),
                                    sums[j].blue / Double(counts[j])) : centers[j]
            }
        }
        var counts = [Int](repeating: 0, count: k)
        for j in labels { counts[j] += 1 }
        return centers.indices.compactMap { j in
            let share = Double(counts[j]) / Double(pixels.count)
            return share > 0.01 ? Swatch(color: centers[j], share: share) : nil
        }
    }

    /// 地と字の色
    struct Tone: Equatable {
        /// 淡い色（地）
        let ground: RGB
        /// 濃い色（字）
        let ink: RGB
        /// 字と地の明暗の比（WCAG）
        var contrast: Double { ShareCardSafeArea.contrast(ink.luminance, ground.luminance) }
    }

    /// 地の明るさ（HSL の L）と、地の彩度の上限
    static let groundLightness = 0.9
    static let groundMaxSaturation = 0.3
    /// 字の明るさ（はじめ）と彩度の幅
    static let inkLightness = 0.17
    static let inkSaturation: ClosedRange<Double> = 0.25...0.5
    /// 字と地の明暗の比の下限。下回れば字の L を 0.01 ずつ下げる（0.05 まで）
    static let minimumContrast = 7.0
    /// **2026-11-18 判断:** 色の鮮やかさ（クロマ＝RGB の最大−最小、0〜255）がこれ未満の色は無彩色とみなす。
    /// 字の元の色がそうなら字も無彩色、地の元の色がそうなら地も無彩色にする。
    /// 模型の「彩度を 0.25 以上」のままだと、色相 0（赤）の字になり、写真に無い色が出る。
    /// HSL の彩度で見ないのは、暗い色では彩度が大きく出るため（RGB(30,27,25) は彩度 0.09 だがクロマ 5 で、ほぼ黒）
    static let achromaticChroma = 12.0

    /// クロマ（RGB の最大−最小、0〜255）
    static func chroma(_ c: RGB) -> Double { max(c.red, c.green, c.blue) - min(c.red, c.green, c.blue) }

    /// 字の元の色を選ぶ点数「クロマ ×（1 − L）」（暗くて色のある色ほど大きい）。
    /// **2026-11-18 判断:** 模型は「HSL の彩度 ×（1 − L）」だが、暗い影（RGB(35,25,20)・彩度 0.27）が
    /// 空色（RGB(120,140,170)・彩度 0.24）より大きく出て、写真の色ではなく影の茶色が字になる。クロマなら空色が勝つ
    static func inkScore(_ c: RGB) -> Double { chroma(c) / 255 * (1 - hsl(c).l) }

    /// 地と字の色（模型の `makeTone`）。
    /// - 地: いちばん多い色の色相で、彩度を 0.3 まで、L 0.9 の淡い色
    /// - 字: 「クロマ ×（1 − L）」がいちばん大きい色（暗くて色のある色）の色相で、彩度 0.25〜0.5、L 0.17。
    ///   字と地の明暗の比が 7 未満なら L を下げる
    static func tone(_ palette: [Swatch]) -> Tone {
        guard let main = palette.max(by: { $0.share < $1.share }) else {
            return tone([Swatch(color: RGB(128, 128, 128), share: 1)])
        }
        let (h, s, _) = hsl(main.color)
        let groundS = chroma(main.color) < achromaticChroma ? 0 : min(s, groundMaxSaturation)
        let ground = rgb(h: h, s: groundS, l: groundLightness).rounded
        let deep = palette.max(by: { inkScore($0.color) < inkScore($1.color) }) ?? main
        let (h2, s2, _) = hsl(deep.color)
        let inkS = chroma(deep.color) < achromaticChroma
            ? 0 : min(max(s2, inkSaturation.lowerBound), inkSaturation.upperBound)
        return Tone(ground: ground, ink: ink(h: h2, s: inkS, l: inkLightness, on: ground))
    }

    /// 字の色。地との明暗の比が 7 未満なら L を 0.01 ずつ下げる（0.05 まで）。
    /// L 0.17 の字は今の地（L 0.9）ではどの色相・彩度でも 7 を超える（2026-11-18 に色相 0.01 刻みで測った最小 8.0、
    /// 黄の写真で 8.9）が、値を変えたときの守りとして残す（模型の `makeTone` の決まり）
    static func ink(h: Double, s: Double, l start: Double, on ground: RGB) -> RGB {
        var l = start
        var ink = rgb(h: h, s: s, l: l).rounded
        while ShareCardSafeArea.contrast(ink.luminance, ground.luminance) < minimumContrast && l > 0.05 {
            l -= 0.01
            ink = rgb(h: h, s: s, l: l).rounded
        }
        return ink
    }

    /// 画素から地と字の色
    static func tone(pixels: [RGB]) -> Tone { tone(palette(pixels)) }

    /// RGB → HSL（どれも 0〜1）
    static func hsl(_ c: RGB) -> (h: Double, s: Double, l: Double) {
        let r = c.red / 255, g = c.green / 255, b = c.blue / 255
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if mx == r {
            h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
        } else if mx == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h /= 6
        if h < 0 { h += 1 }
        return (h, s, l)
    }

    /// HSL → RGB（0〜255）
    static func rgb(h: Double, s: Double, l: Double) -> RGB {
        let a = s * min(l, 1 - l)
        func f(_ n: Double) -> Double {
            let k = (n + h * 12).truncatingRemainder(dividingBy: 12)
            return (l - a * max(-1, min(k - 3, 9 - k, 1))) * 255
        }
        return RGB(f(0), f(8), f(4))
    }

    // MARK: - 字

    /// 絵に載せる字（無いものは出さない）
    struct Texts: Equatable {
        /// 撮影地（明朝・大きく）。選んだ細かさのいちばん細かい地名
        let place: String?
        /// 下の段の左。撮影地の一つ上の単位（市を出したときの県・海外の国）
        let region: String?
        /// 下の段の右（「2026.10.10」か、ストーリーの「今日」）
        let date: String?

        /// 撮影地が最小の字でも入らないとき: 一つ上の単位を大きく出し、下の段の左は空ける
        var widened: Texts? {
            guard let region else { return nil }
            return Texts(place: region, region: nil, date: date)
        }
    }

    /// **2026-11-18 判断: 撮影地の字は、選んだ細かさのいちばん細かい地名。** 模型は観光スポットの名前（神戸北野異人館街）だが、
    /// 共有の絵は「選んだ細かさより細かい場所を出さない」（`TravelStory.placeText`・`LocationMatch.shareCardDisplay`）ので、
    /// 投稿は共有カードの撮影地の2行（`LocationMatch.shareCardPlace`）の小さい単位を大きく、大きい単位を下の段に出す。
    /// 日付は撮った日（分からない・共有画面の「日付」を切った（`Credit.showsDate`・`ShareCardDateChoice`）なら出さない）
    static func texts(for credit: SignatureShareCardRenderer.Credit) -> Texts {
        let place = credit.place ?? LocationMatch.shareCardPlace(credit.location)
        let small = place?.secondary.flatMap(clean)
        let large = place.flatMap { clean($0.primary) }
        return Texts(place: small ?? large, region: small == nil ? nil : large,
                     date: credit.showsDate ? credit.takenDay.map(dateText) : nil)
    }

    /// 「2026.10.10」（撮った日は UTC 0 時で持つ暦の日なので UTC で書く）
    static func dateText(_ day: Date) -> String {
        let parts = TripBook.utcCalendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
