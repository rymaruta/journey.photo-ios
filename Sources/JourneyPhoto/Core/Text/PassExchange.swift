import Foundation

/// **すれちがい**（板「10 すれちがい」・2026-10-16）の、画面と電波を持たない決まり。
///
/// 旅先で同じ場所に居合わせたアプリの人と、自分が選んだ「名刺の一枚」（自分の公開写真1枚）が
/// カードで交換される。届くのはその日の夕方 18 時に束で1回。受け取ったカードは消えず、
/// すれちがい帳に綴じる。相手の今いる場所は分からない形にする（場所は「〇〇のあたり」・時刻は時の単位・
/// 届くのは夕方）。
///
/// **2026-10-16 判断: サーバーは変えない。** 近くの人は Bluetooth で見つけ（`PassRadio`）、
/// 相手の写真と持ち主は既にある公開写真の一覧（`PublicGalleryService`）と公開プロフィールで引く。
/// 受け取ったカードと設定は端末の中だけ（`PassStore`）。
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる。
enum PassExchange {

    // MARK: - 電波に載せる中身

    /// Bluetooth の特性1つに載せる中身。**連絡先・位置・端末の識別子は載せない。**
    ///
    /// **2026-10-16 判断（指示からの差分・owner に確認）**: 指示は「版番号＋カードの写真の id だけ」だったが、
    /// 板（PassCardPick）が「裏に書くひとこと（20字まで）」と「どこから来た人かを出さない」を持つので、
    /// その2つ（本人が書いて載せると決めたものだけ）を足した。サーバーを変えずに相手へ届ける道が
    /// ほかに無い。外すなら `note` を空・`showsFrom` を false で送れば同じ形のまま読める。
    struct Payload: Equatable {
        /// 名刺の一枚（自分の公開写真の id）
        var photoId: String
        /// 居住地の都道府県をカードに出してよいか（プロフィールの居住地から相手の端末が引く）
        var showsFrom: Bool
        /// 裏に書くひとこと（`noteLimit` 字まで・改行なし）
        var note: String
    }

    /// 中身の版。**知らない版は読まない**（形を変えたら上げる）
    static let version: UInt8 = 1
    /// ひとことの字数（板「20字まで」）
    static let noteLimit = 20
    /// 写真の id の長さの上限（`PathID` と同じ字だけ）
    static let photoIdLimit = 64

    /// 写真の id として受け取ってよいか（英数字・`-`・`_` だけ）。**相手の端末から来た値なので必ず通す**
    static func isValidPhotoId(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= photoIdLimit else { return false }
        return id.unicodeScalars.allSatisfy { s in
            (s.value >= 0x30 && s.value <= 0x39) || (s.value >= 0x41 && s.value <= 0x5A)
                || (s.value >= 0x61 && s.value <= 0x7A) || s == "-" || s == "_"
        }
    }

    /// ひとことのバイト数の上限（UTF-8）。送る側・受ける側とも（`noteLimit` 字の絵文字でも収まる大きさ）
    static let noteByteLimit = 80
    /// 1字に重ねてよい結合文字（Mn・Me）の数。**重ね書きで行を突き破る字**（ザルゴ）を止める
    static let marksPerCharacterLimit = 3
    /// 1字に入ってよいスカラーの数（肌の色つきの家族の絵文字で 11）
    static let scalarsPerCharacterLimit = 16
    /// 中身ごと落とす値（電波で受け取る特性の上限 512 を超えない）
    static let payloadByteLimit = 512

    /// 入力中のひとことが載せられない訳（載せられるなら nil）。名刺選びの欄の下に出す
    static func noteProblem(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count > noteLimit {
            return L("\(noteLimit)字を超えています", "This is longer than \(noteLimit) characters")
        }
        if trimmed.utf8.count > noteByteLimit {
            return L("絵文字が多く、載せられる大きさを超えています", "Too many emoji \u{2014} this is too large to send")
        }
        return nil
    }

    /// 向きを変える制御（文字の並びを逆さに見せる・なりすましに使える）
    private static func isBidiControl(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: return true
        default: return false
        }
    }

    /// 残す書式の字（絵文字をつなぐ ZWJ と、旗のタグ）。ほかの書式の字（ゼロ幅の空白など）は落とす
    private static func isKeptFormat(_ s: Unicode.Scalar) -> Bool {
        s.value == 0x200D || (0xE0020...0xE007F).contains(s.value)
    }

    /// ひとことを整える（2026-10-16 判断・相手の端末から来る値なので受ける側も必ず通す）:
    /// - 改行・制御文字は空白に、向きの制御とゼロ幅の字は落とす。**ZWJ・異体字セレクタ（絵文字）は残す**
    /// - 1字に重ねる結合文字は `marksPerCharacterLimit` まで、スカラーが多すぎる字は落とす
    /// - 前後の空白を落とし、`noteLimit` 字・`noteByteLimit` バイトの短い方で（字の途中で切らずに）切る
    static func cleanNote(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            if isBidiControl(s) { continue }
            if CharacterSet.newlines.contains(s) || s.properties.generalCategory == .control {
                scalars.append(" ")
            } else if s.properties.generalCategory == .format, !isKeptFormat(s) {
                continue
            } else {
                scalars.append(s)
            }
        }
        var out = ""
        var bytes = 0
        for ch in String(scalars).trimmingCharacters(in: .whitespaces) {
            guard out.count < noteLimit else { break }
            var marks = 0
            var kept = String.UnicodeScalarView()
            for s in ch.unicodeScalars {
                let mark = s.properties.generalCategory == .nonspacingMark || s.properties.generalCategory == .enclosingMark
                // 異体字セレクタ（FE00–FE0F）は数えない（絵文字の見た目を選ぶだけ）
                if mark && !(0xFE00...0xFE0F).contains(s.value) {
                    marks += 1
                    if marks > marksPerCharacterLimit { continue }
                }
                kept.append(s)
            }
            // 結合文字を削ってもまだスカラーが多すぎる字は落とす
            guard kept.count <= scalarsPerCharacterLimit else { continue }
            let piece = String(kept)
            let size = piece.utf8.count
            guard bytes + size <= noteByteLimit else { break }
            out += piece
            bytes += size
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// 並び: [版 1][印 1（bit0 = 出身を出す）][id の長さ 1][id][ひとこと（UTF-8・残り全部）]
    static func encode(_ payload: Payload) -> Data? {
        guard isValidPhotoId(payload.photoId) else { return nil }
        let id = Array(payload.photoId.utf8)
        var bytes: [UInt8] = [version, payload.showsFrom ? 1 : 0, UInt8(id.count)]
        bytes += id
        bytes += Array(cleanNote(payload.note).utf8)
        guard bytes.count <= payloadByteLimit else { return nil }
        return Data(bytes)
    }

    /// 読む。**形が崩れていたら nil**（知らない版・長さが合わない・id に使えない字・ひとことが長すぎる）
    static func decode(_ data: Data) -> Payload? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes.count <= payloadByteLimit, bytes[0] == version else { return nil }
        let length = Int(bytes[2])
        guard length > 0, bytes.count >= 3 + length else { return nil }
        guard let id = String(bytes: bytes[3..<(3 + length)], encoding: .utf8), isValidPhotoId(id) else { return nil }
        let rest = bytes[(3 + length)...]
        guard rest.count <= noteByteLimit, let rawNote = String(bytes: rest, encoding: .utf8),
              rawNote.count <= noteLimit else { return nil }
        return Payload(photoId: id, showsFrom: bytes[1] & 1 == 1, note: cleanNote(rawNote))
    }

    /// 名刺の一枚にできる写真か（**全体に公開している写真だけ**）。公開範囲を絞った写真は
    /// 公開一覧（`photos.json`）に載らず、相手の端末で引けない
    static func isPublicCard(_ photo: Photo) -> Bool {
        guard photo.published != false else { return false }
        let audience = photo.audience?.trimmingCharacters(in: .whitespaces) ?? ""
        return audience.isEmpty || audience == "everyone"
    }

    // MARK: - 届く時刻

    /// 束を届ける時（夕方 18 時・板 PassHome「夕方 18 時に、その日すれちがった分をまとめて1回だけ」）
    static let deliveryHour = 18

    /// すれちがった時から、届く時を決める。**18 時より前ならその日の 18 時、18 時を過ぎたら次の日の 18 時。**
    ///
    /// 2026-10-16 判断: 18 時を過ぎた分をすぐ（または 21 時などに）届けると、「いま近くにいる」が
    /// 分かってしまう。次の日の夕方に回す
    static func deliveryDate(for metAt: Date, calendar: Calendar) -> Date {
        let cal = calendar.gregorianKeepingZone
        let start = cal.startOfDay(for: metAt)
        let today = cal.date(bySettingHour: deliveryHour, minute: 0, second: 0, of: start) ?? start
        if metAt < today { return today }
        return cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// 日の鍵（`2026-10-16`）。束・「同じ相手は1日1回」の区切り
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.gregorianKeepingZone.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 時の単位に丸める（分・秒は持たない）
    static func hourStart(_ date: Date, calendar: Calendar) -> Date {
        let cal = calendar.gregorianKeepingZone
        let c = cal.dateComponents([.year, .month, .day, .hour], from: date)
        return cal.date(from: c) ?? date
    }

    /// 裏の時刻（板「2026.10.16 · 15 時ごろ」）。**分は出さない**
    static func timeLabel(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.gregorianKeepingZone.dateComponents([.year, .month, .day, .hour], from: date)
        let y = c.year ?? 0, m = c.month ?? 0, d = c.day ?? 0, h = c.hour ?? 0
        let day = String(format: "%04d.%02d.%02d", y, m, d)
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return L("\(day) · \(h) 時ごろ", "\(day) · around \(hour12) \(h < 12 ? "AM" : "PM")")
    }

    /// 帳の日の見出し（板「2026.10.16 · 京都」）
    static func dayLabel(_ date: Date, place: String?, calendar: Calendar) -> String {
        let c = calendar.gregorianKeepingZone.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d.%02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        guard let place, !place.isEmpty else { return day }
        return "\(day) · \(place)"
    }

    // MARK: - 場所

    /// 記録する場所の粗さ（緯度・経度を 0.1 度・およそ 11km に丸める）。**番地は持たない**
    static let coordinateStep = 0.1

    static func coarse(_ coords: Photo.Coords) -> Photo.Coords {
        Photo.Coords(lat: (coords.lat / coordinateStep).rounded() * coordinateStep,
                     lng: (coords.lng / coordinateStep).rounded() * coordinateStep)
    }

    /// 位置を使ってよい新しさ（これより古い位置は「取れなかった」とみなす）
    static let placeFreshness: TimeInterval = 30 * 60

    /// 「〇〇のあたり」（取れたときだけ・市区町村の名前）
    static func placeLabel(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return L("\(name)のあたり", "around \(name)")
    }

    /// 地名の部品から、記録する名前を選ぶ。**市区町村（`locality`）、無ければ都道府県**
    static func placeName(locality: String?, administrativeArea: String?) -> String? {
        for raw in [locality, administrativeArea] {
            if let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        }
        return nil
    }

    // MARK: - どこから来た人か・距離

    /// 居住地（自由入力）から都道府県だけを取り出す。正式名か「福岡」のような県名だけの入力
    static func homePrefecture(_ homeLocation: String?) -> String? {
        guard let text = homeLocation?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return RegionList.prefecture(inText: text) ?? RegionList.prefecture(named: text)
    }

    /// カードの表の「〇〇から」
    static func fromLabel(_ prefecture: String) -> String {
        L("\(prefecture)から", "from \(prefecture)")
    }

    /// 都道府県庁のおおよその位置（距離の起点・都道府県の粒度より細かくしない）
    static let prefectureOffices: [String: Photo.Coords] = {
        let raw: [(String, Double, Double)] = [
            ("北海道", 43.064, 141.347), ("青森県", 40.824, 140.740), ("岩手県", 39.704, 141.153),
            ("宮城県", 38.269, 140.872), ("秋田県", 39.719, 140.102), ("山形県", 38.240, 140.364),
            ("福島県", 37.750, 140.468), ("茨城県", 36.342, 140.447), ("栃木県", 36.566, 139.884),
            ("群馬県", 36.391, 139.061), ("埼玉県", 35.857, 139.649), ("千葉県", 35.605, 140.123),
            ("東京都", 35.690, 139.692), ("神奈川県", 35.448, 139.642), ("新潟県", 37.902, 139.023),
            ("富山県", 36.695, 137.211), ("石川県", 36.594, 136.626), ("福井県", 36.065, 136.222),
            ("山梨県", 35.664, 138.568), ("長野県", 36.651, 138.181), ("岐阜県", 35.391, 136.722),
            ("静岡県", 34.977, 138.383), ("愛知県", 35.180, 136.907), ("三重県", 34.730, 136.509),
            ("滋賀県", 35.004, 135.868), ("京都府", 35.021, 135.756), ("大阪府", 34.686, 135.520),
            ("兵庫県", 34.691, 135.183), ("奈良県", 34.685, 135.833), ("和歌山県", 34.226, 135.168),
            ("鳥取県", 35.504, 134.238), ("島根県", 35.472, 133.051), ("岡山県", 34.662, 133.935),
            ("広島県", 34.396, 132.459), ("山口県", 34.186, 131.471), ("徳島県", 34.066, 134.559),
            ("香川県", 34.340, 134.043), ("愛媛県", 33.842, 132.766), ("高知県", 33.560, 133.531),
            ("福岡県", 33.607, 130.418), ("佐賀県", 33.249, 130.299), ("長崎県", 32.745, 129.874),
            ("熊本県", 32.790, 130.742), ("大分県", 33.238, 131.613), ("宮崎県", 31.911, 131.424),
            ("鹿児島県", 31.560, 130.558), ("沖縄県", 26.212, 127.681),
        ]
        return Dictionary(uniqueKeysWithValues: raw.map { ($0.0, Photo.Coords(lat: $0.1, lng: $0.2)) })
    }()

    /// 相手の都道府県（庁のあたり）から、すれちがった場所までの距離（km・整数）。どちらか無ければ nil
    static func travelKm(fromPrefecture prefecture: String?, to place: Photo.Coords?) -> Int? {
        guard let prefecture, let start = prefectureOffices[prefecture], let place else { return nil }
        return Int(TravelDistance.kilometers(from: start, to: place).rounded())
    }

    /// 裏の下の一行（板「札幌 → 京都 1,047km」）。距離が 1km 未満なら出さない
    static func routeLabel(fromPrefecture prefecture: String, placeName: String?, km: Int) -> String? {
        guard km >= 1 else { return nil }
        let to = placeName ?? L("ここ", "here")
        return "\(prefecture) → \(to) \(kmText(km))"
    }

    /// 「1,047km」（桁区切り・単位は詰める）
    static func kmText(_ km: Int) -> String { grouped(km) + "km" }

    /// 桁区切りの数（「1,284」）。端末の言語に関わらず「,」で区切る（板の書き方）
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return value < 0 ? "-" + out : out
    }

    // MARK: - いつ交換するか

    /// 「いつ」の3つ（板 PassSettings のセグメント）
    enum Mode: String, Codable, CaseIterable, Identifiable {
        /// いつでも
        case always
        /// 旅のあいだ（家から `travelThresholdKm` 以上離れた日だけ）
        case traveling
        /// アプリを開いている間だけ
        case foreground

        var id: String { rawValue }

        var label: String {
            switch self {
            case .always: return L("いつでも", "Always")
            case .traveling: return L("旅のあいだ", "While traveling")
            case .foreground: return L("開いている間", "While open")
            }
        }
    }

    /// 「旅のあいだ」の線（板「家から 50km 以上離れた日だけ」）
    static let travelThresholdKm = 50.0

    /// いまの位置が家（居住地の都道府県庁のあたり）から離れているか。どちらかが分からなければ nil
    static func isAway(current: Photo.Coords?, homePrefecture: String?) -> Bool? {
        guard let current, let prefecture = homePrefecture, let home = prefectureOffices[prefecture] else { return nil }
        return TravelDistance.kilometers(from: home, to: current) >= travelThresholdKm
    }

    /// いま交換してよいか。**分からないときは交換しない**（「旅のあいだ」で家からの距離が分からない日）
    static func allowsExchange(mode: Mode, isForeground: Bool, awayFromHome: Bool?) -> Bool {
        switch mode {
        case .always: return true
        case .foreground: return isForeground
        case .traveling: return awayFromHome == true
        }
    }

    // MARK: - 数え方

    /// 1日に受け取るカードの上限（人の多い所で帳が溢れない・電波を使いすぎない）
    static let dailyLimit = 30

    /// カードの番号（板「No.0087」）。帳に綴じた順
    static func numberLabel(_ number: Int) -> String {
        String(format: "No.%04d", max(0, number))
    }

    /// 帳の格子の番号（板「0087」）
    static func shortNumber(_ number: Int) -> String {
        String(format: "%04d", max(0, number))
    }

    /// 同じ人と何回目か（板「はじめてのすれちがい」）
    static func meetingLabel(_ count: Int) -> String {
        count <= 1 ? L("はじめてのすれちがい", "Your first pass")
            : L("\(count) 回目のすれちがい", "Pass no. \(count)")
    }
}
