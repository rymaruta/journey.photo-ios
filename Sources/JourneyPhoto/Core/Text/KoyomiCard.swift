import Foundation

/// 共有の絵「暦（差し色）」（2026-11-18 owner「暦 差し色採用」・模型は Artifact「共有の絵の新しい形」の「暦　差し色」）。
///
/// 写真から取った一色（`ShareCardMap.MatColor`・額装と同じ暗い色）を全面に塗り、写真を**切らずに**置き、
/// その下に字の段（二十四節気の名前・英字・細い線・日付と撮影地と節気の番号の3列・意味の一文）。写真の上には何も重ねない。
/// ストーリー（`TravelStory.Kind.koyomi`・1080×1920）と投稿（`SignatureShareCardRenderer.Style.koyomi`・4:5・1:1・9:16）の両方で使う。
/// 違うのは字の下端の線と上の線だけ（`Frame`）。
///
/// 寸法と字はここに1か所（Linux の `swift test` で見張る）。描くのは `KoyomiCardRenderer`（UIKit）
enum KoyomiCard {

    // MARK: - 寸法（1080 幅の画素）

    static let width: CGFloat = 1080
    /// 字の段の高さと、写真との間
    static let blockHeight: CGFloat = 340
    static let gap: CGFloat = 64
    /// 字の段の左端と幅（左右 72 の格子）
    static let left: CGFloat = 72
    static let contentWidth: CGFloat = 936
    static var right: CGFloat { left + contentWidth }

    /// 節気の名前（明朝 Bold 132px・行の高さ 1.1）。段の上端から y −14。
    /// **2026-11-18 判断: 左は 65。** 模型は 64 だが、安全域（短い辺の 6% = 64.8）の 0.8 外になるので、内側の 65 にした
    static let headingX: CGFloat = 65
    static let headingY: CGFloat = -14
    static let headingSize: CGFloat = 132
    static let headingMinimumSize: CGFloat = 60
    /// 英字（SF 500 30px・字間 0.4em・白 72%）。右端 1008 にそろえる
    static let latinY: CGFloat = 52
    static let latinSize: CGFloat = 30
    static let latinKern: CGFloat = 0.4
    /// 名前と英字の間に空ける幅（長い撮影地を名前の所に出すとき）
    static let headingLatinGap: CGFloat = 32
    /// 細い線（1px・白 35%）
    static let ruleY: CGFloat = 150
    /// 3列（各幅 300・左端 72、384、696）
    static let columnX: [CGFloat] = [72, 384, 696]
    static let columnWidth: CGFloat = 300
    static let eyebrowY: CGFloat = 180
    static let eyebrowSize: CGFloat = 30
    static let eyebrowKern: CGFloat = 0.24
    static let valueY: CGFloat = 226
    static let valueSize: CGFloat = 36
    /// 撮影地（明朝）が長いときの最小（入らなければ末尾を切り詰める）
    static let valueMinimumSize: CGFloat = 30
    /// 意味の一文（SF 400 34px・白 75%）
    static let meaningY: CGFloat = 292
    static let meaningSize: CGFloat = 34

    /// 字の白の濃さ（地の色の上）
    enum Ink {
        static let latin: Double = 0.72
        static let rule: Double = 0.35
        static let eyebrow: Double = 0.65
        static let meaning: Double = 0.75
    }

    // MARK: - 絵の枠

    /// 絵の高さと、字を置いてよい上下の線。ストーリーと投稿で違うのはここだけ
    struct Frame: Equatable {
        let height: CGFloat
        /// 字の段の下端がこれを越えない（ストーリーは下 20% の返信欄の上、投稿は下から短い辺の 6%）
        let textBottom: CGFloat
        /// 字の段の上端はこれより下（ストーリーは上 14%、投稿は短い辺の 6%）
        let textTop: CGFloat

        /// ストーリー（1080×1920）
        static let story = Frame(height: 1920, textBottom: 1920 * (1 - ShareCardSafeArea.storyBottomFraction),
                                 textTop: 1920 * ShareCardSafeArea.storyTopFraction)

        /// 投稿の比。9:16 はストーリーと同じ線（字の段は 4:5 のフィードの切り取りの内側にも入る・試験で見る）
        static func post(_ ratio: SignatureShareCardRenderer.Ratio) -> Frame {
            if ratio == .story { return story }
            let height = (KoyomiCard.width / CGFloat(ratio.rawValue)).rounded()
            let edge = min(KoyomiCard.width, height) * ShareCardSafeArea.edgeFraction
            return Frame(height: height, textBottom: height - edge, textTop: edge)
        }
    }

    /// 写真の枠と字の段の上端
    struct Placement: Equatable {
        let photo: CGRect
        let blockTop: CGFloat
    }

    /// 写真（幅 ÷ 高さ = `aspect`）を切らずに置く。
    /// - 幅の上限 1080、高さの上限は「字の下端の線 − 段 340 − 間 64」。超えるなら高さを上限にして幅を縮め、左右の真ん中
    /// - 写真＋間＋段をひとまとまりにして上下の真ん中。段の下端が線を越えるなら上げる（写真の上端は 0 まで）
    /// - 段の上端が上の線より上なら下げる
    static func place(aspect: CGFloat, in frame: Frame) -> Placement {
        let a = aspect.isFinite && aspect > 0 ? aspect : 1
        var w = width, h = width / a
        let maxH = max(1, frame.textBottom - blockHeight - gap)
        if h > maxH {
            h = maxH
            w = h * a
        }
        let group = h + gap + blockHeight
        var y = (frame.height - group) / 2
        if y + group > frame.textBottom { y = frame.textBottom - group }
        if y < 0 { y = 0 }
        if y + h + gap < frame.textTop { y = frame.textTop - h - gap }
        return Placement(photo: CGRect(x: (width - w) / 2, y: y, width: w, height: h), blockTop: y + h + gap)
    }

    // MARK: - 字

    struct Column: Equatable {
        let key: String
        let value: String
        /// 撮影地は明朝、ほかは SF の等幅数字
        let serif: Bool
    }

    struct Texts: Equatable {
        /// 大きな明朝（節気の名前。節気を出さないときは撮影地）
        let heading: String
        /// 名前が節気か（意味の一文と SOLAR TERM の列がある）
        let isSolarTerm: Bool
        /// 右の英字（節気の読み・南半球では国名）
        let latin: String?
        /// 3列（無い値の列は詰める）
        let columns: [Column]
        /// 節気の意味の一文
        let meaning: String?
    }

    /// 絵に載せる字。
    /// - `takenDay`: 撮った日（UTC 0 時で持つ暦の日）。無い・日付を出さない（`showsDate == false`）なら節気も出さない
    ///   （節気は日付の手がかりなので、日付を伏せた人の絵に出さない）
    /// - 南半球（緯度が 0 より小さい、座標が無ければ撮影地の国が南半球の国）なら節気を出さない。
    ///   名前の所に撮影地、英字は国名、3列目は COUNTRY
    /// - `place`: 列に出す撮影地（呼ぶ側が細かさを決める）。`country`: 絵に出す撮影地の国（海外のとき）。
    ///   `hemisphereCountry`: 南半球かを見分ける国（絵には出さない・既定は `country`）
    static func texts(takenDay: Date?, showsDate: Bool, latitude: Double?, place: String?,
                      country: String?, hemisphereCountry: String?? = nil) -> Texts {
        let date = showsDate ? takenDay.map(dateText) : nil
        let south = isSouthern(latitude: latitude, country: hemisphereCountry ?? country)
        let placeValue = place.flatMap(clean)
        if let takenDay, showsDate, !south {
            let term = SolarTerm.term(onDay: takenDay)
            var columns: [Column] = []
            if let date { columns.append(Column(key: "DATE", value: date, serif: false)) }
            if let placeValue { columns.append(Column(key: "PLACE", value: placeValue, serif: true)) }
            columns.append(Column(key: "SOLAR TERM", value: "\(term.number) / 24", serif: false))
            return Texts(heading: term.name, isSolarTerm: true, latin: term.latin, columns: columns,
                         meaning: term.meaning)
        }
        let countryValue = country.flatMap(clean)
        var columns: [Column] = []
        if let date { columns.append(Column(key: "DATE", value: date, serif: false)) }
        if let placeValue { columns.append(Column(key: "PLACE", value: placeValue, serif: true)) }
        // 撮影地が国そのもの（「オーストラリア」だけ）なら、同じ字を2列に並べない
        if let countryValue, countryValue != placeValue {
            columns.append(Column(key: "COUNTRY", value: countryValue, serif: true))
        }
        return Texts(heading: placeValue ?? countryValue ?? TravelStory.onTheRoad, isSolarTerm: false,
                     latin: countryValue.flatMap(countryLatin), columns: columns, meaning: nil)
    }

    /// 投稿の共有カード（`SignatureShareCardRenderer.Credit`）の字。撮影地の列は小さい単位（市区町村・海外の地名）、
    /// 無ければ大きい単位。緯度は約 50km に丸めた概略（`approximateShareCoordinate`）で、南半球かの見分けには足りる
    static func texts(for credit: SignatureShareCardRenderer.Credit) -> Texts {
        let place = credit.place ?? LocationMatch.shareCardPlace(credit.location)
        return texts(takenDay: credit.takenDay, showsDate: true, latitude: credit.coords?.latitude,
                     place: place?.secondary ?? place?.primary, country: country(of: credit.location))
    }

    /// 「2026.10.10」（撮った日は UTC 0 時で持つ暦の日なので UTC で書く）
    static func dateText(_ day: Date) -> String {
        let parts = TripBook.utcCalendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 前後の空白を落とし、空なら nil
    private static func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - 南半球

    /// 南半球の国（和名・英名）。座標の無い写真で、撮影地の国から南半球かを決める。
    /// 赤道をまたぐ国（ブラジル・インドネシア・エクアドル・ケニアなど）は、人の多い側で決めた
    /// （ブラジル・インドネシアは南、エクアドル・ケニア・コロンビアは入れない）。座標があれば座標が先
    static let southernCountries: [(ja: String, en: String)] = [
        ("オーストラリア", "Australia"), ("ニュージーランド", "New Zealand"), ("アルゼンチン", "Argentina"),
        ("チリ", "Chile"), ("南アフリカ", "South Africa"), ("ブラジル", "Brazil"), ("ペルー", "Peru"),
        ("ボリビア", "Bolivia"), ("パラグアイ", "Paraguay"), ("ウルグアイ", "Uruguay"), ("インドネシア", "Indonesia"),
        ("フィジー", "Fiji"), ("マダガスカル", "Madagascar"), ("モーリシャス", "Mauritius"), ("ナミビア", "Namibia"),
        ("ボツワナ", "Botswana"), ("ジンバブエ", "Zimbabwe"), ("ザンビア", "Zambia"), ("モザンビーク", "Mozambique"),
        ("タンザニア", "Tanzania"), ("アンゴラ", "Angola"), ("マラウイ", "Malawi"), ("レソト", "Lesotho"),
        ("エスワティニ", "Eswatini"), ("パプアニューギニア", "Papua New Guinea"), ("サモア", "Samoa"),
        ("トンガ", "Tonga"), ("バヌアツ", "Vanuatu"), ("ニューカレドニア", "New Caledonia"),
        ("フランス領ポリネシア", "French Polynesia"), ("東ティモール", "Timor-Leste"),
    ]

    /// 南半球の国の表の行（和名の頭が合う「南アフリカ共和国」、英名の大文字小文字を問わない）
    static func southernCountry(_ country: String?) -> (ja: String, en: String)? {
        guard let name = country.flatMap(clean) else { return nil }
        return southernCountries.first { row in
            name.hasPrefix(row.ja) || name.caseInsensitiveCompare(row.en) == .orderedSame
                || name.lowercased().hasPrefix(row.en.lowercased() + " ")
        }
    }

    /// 南半球か。座標があれば緯度（0 より小さい）、無ければ国
    static func isSouthern(latitude: Double?, country: String?) -> Bool {
        if let latitude, latitude.isFinite { return latitude < 0 }
        return southernCountry(country) != nil
    }

    /// 国名の英字（大文字）。南半球の国の表にあれば英名、ラテン文字の国名ならそのまま
    static func countryLatin(_ country: String) -> String? {
        if let row = southernCountry(country) { return row.en.uppercased() }
        return country.unicodeScalars.allSatisfy(\.isASCII) ? country.uppercased() : nil
    }

    /// 撮影地の文字から国（海外のとき・最後の欠片）。日本・都道府県なら nil
    static func country(of location: String?) -> String? {
        let parts = (location ?? "").components(separatedBy: CharacterSet(charactersIn: ",，、"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !LocationMatch.isPostalOrNumber($0) }
        guard let last = parts.last, !LocationMatch.isJapan(last),
              ShareCardMap.prefectureName(in: location) == nil else { return nil }
        // 1つの欠片は国とは限らない（「山中湖」）。南半球の国の表にあるものだけ国とみなす
        if parts.count == 1 { return southernCountry(last).map { _ in last } }
        return last
    }

    // MARK: - 字の明暗（地の色の上の白の濃さ）

    /// 地の色（sRGB 0〜255）の上に、白を `alpha` で重ねた色の明暗の比
    static func contrast(ground: (red: Double, green: Double, blue: Double), whiteAlpha alpha: Double) -> Double {
        func blend(_ c: Double) -> Double { c * (1 - alpha) + 255 * alpha }
        let text = ShareCardSafeArea.luminance(red: blend(ground.red), green: blend(ground.green), blue: blend(ground.blue))
        let back = ShareCardSafeArea.luminance(red: ground.red, green: ground.green, blue: ground.blue)
        return ShareCardSafeArea.contrast(text, back)
    }
}
