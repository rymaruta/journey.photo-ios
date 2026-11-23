import Foundation

/// **写真の色に、日本の色の名前**（札 #710 の案10・2026-11-23 owner 承認）。
///
/// 写真の代表色（`Photo.dominantColor`・投稿のときに端末で計算している）に、端末に同梱した日本の伝統色の表から
/// いちばん近い1色の名前を付ける。近さは人の目に近い色の差（CIELAB の距離 ΔE76）で測る。
///
/// 2026-11-23 判断:
/// - 表は約100色。名前・読み・ローマ字・色の値・由来の1行（日本語と英語）。**色の名前と値は事実**として使い、
///   由来の文は辞典から写さず自分たちで書いた
/// - 出さないとき: 代表色が無い・灰色に近い（彩りが `minChroma` より少ない）・表のどの色からも遠い（`maxDistance` より遠い）。
///   外れた名前を出すより出さない方を選ぶ
/// - 名前は保存しない（表から毎回引く）。サーバー・DB は変えない。AI は使わない
/// - 英語の画面では名前をローマ字にし、由来は英語の1行
enum JapaneseColors {

    struct Color: Identifiable, Equatable {
        let name: String
        let reading: String
        let romaji: String
        /// `0xRRGGBB`
        let hex: Int
        let origin: String
        let originEn: String
        /// Lab の値。**作るときに1回だけ計算して持つ**（2026-11-23 確かめ役の指摘: 計算型だと比べるたびに pow を計算し直していた）
        let lab: Lab

        init(name: String, reading: String, romaji: String, hex: Int, origin: String, originEn: String) {
            self.name = name
            self.reading = reading
            self.romaji = romaji
            self.hex = hex
            self.origin = origin
            self.originEn = originEn
            self.lab = JapaneseColors.lab(hex: hex)
        }

        var id: String { romaji }
        /// 画面に出す名前（英語の画面はローマ字）
        var shownName: String { L(name, romaji) }
        /// 名前の横の小さな字（日本語は読み。英語の画面は出さない）
        var shownReading: String? { L(reading, "").isEmpty ? nil : L(reading, "") }
        /// 由来の1行
        var shownOrigin: String { L(origin, originEn) }
        /// `#rrggbb`
        var hexString: String { String(format: "#%06x", hex) }
    }

    /// 灰色に近いとみなす彩り（Lab の a・b の長さ）。これより少ない写真には名前を出さない
    static let minChroma = 12.0
    /// 表の色からこれより遠い写真には名前を出さない（ΔE76）
    static let maxDistance = 22.0

    /// いちばん近い色。出さないときは nil
    static func name(forHex raw: String?) -> Color? {
        guard let rgb = ColorFamilies.rgb(raw) else { return nil }
        let lab = lab(r: rgb.r, g: rgb.g, b: rgb.b)
        guard lab.chroma >= minChroma else { return nil }
        guard let best = all.min(by: { $0.lab.distance(to: lab) < $1.lab.distance(to: lab) }),
              best.lab.distance(to: lab) <= maxDistance else { return nil }
        return best
    }

    /// 表の中で近い色（自分を除く・近い順）
    static func neighbors(of color: Color, limit: Int = 3) -> [Color] {
        all.filter { $0 != color }
            .sorted { $0.lab.distance(to: color.lab) < $1.lab.distance(to: color.lab) }
            .prefix(limit).map { $0 }
    }

    /// 「この色の写真」に並べる写真。同じ名前になる写真。**少ない（`fewPhotos` 未満）ときは近い色の写真も混ぜる**
    static func photos(for color: Color, in photos: [Photo]) -> [Photo] {
        self.photos(for: color, in: photos, names: names(of: photos))
    }

    /// 写真の id → 色の id（`Color.id`）。名前の付かない写真は入れない。
    /// 画面は写真を読んだときに1回だけ作って控える（body のたびに全部の写真の名前を引かない・2026-11-23 判断）
    static func names(of photos: [Photo]) -> [String: String] {
        var out: [String: String] = [:]
        for photo in photos {
            if let color = name(forHex: photo.dominantColor) { out[photo.id] = color.id }
        }
        return out
    }

    /// 控えた名前（`names(of:)`）で選ぶ形
    static func photos(for color: Color, in photos: [Photo], names: [String: String]) -> [Photo] {
        let same = photos.filter { names[$0.id] == color.id }
        guard same.count < fewPhotos else { return same }
        let near = Set(neighbors(of: color).map(\.id))
        let more = photos.filter { photo in
            guard let other = names[photo.id] else { return false }
            return near.contains(other)
        }
        return same + more
    }

    /// これより少ないと近い色も混ぜる
    static let fewPhotos = 6

    // MARK: - 色の計算（sRGB → CIELAB・D65）

    struct Lab: Equatable {
        let l: Double
        let a: Double
        let b: Double

        var chroma: Double { (a * a + b * b).squareRoot() }

        func distance(to other: Lab) -> Double {
            let dl = l - other.l, da = a - other.a, db = b - other.b
            return (dl * dl + da * da + db * db).squareRoot()
        }
    }

    static func lab(hex: Int) -> Lab {
        lab(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    /// 0〜1 の sRGB から Lab
    static func lab(r: Double, g: Double, b: Double) -> Lab {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (lr, lg, lb) = (linear(r), linear(g), linear(b))
        let x = (lr * 0.4124 + lg * 0.3576 + lb * 0.1805) / 0.95047
        let y = (lr * 0.2126 + lg * 0.7152 + lb * 0.0722) / 1.0
        let z = (lr * 0.0193 + lg * 0.1192 + lb * 0.9505) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0) }
        let (fx, fy, fz) = (f(x), f(y), f(z))
        return Lab(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    // MARK: - 表（約100色）

    private static func c(_ name: String, _ reading: String, _ romaji: String, _ hex: Int,
                          _ origin: String, _ originEn: String) -> Color {
        Color(name: name, reading: reading, romaji: romaji, hex: hex, origin: origin, originEn: originEn)
    }

    static let all: [Color] = [
        // 赤・紅
        c("紅", "べに", "Beni", 0xD7003A, "紅花で染めた、あざやかな赤", "A vivid red dyed with safflower"),
        c("紅緋", "べにひ", "Benihi", 0xE83929, "紅に黄を重ねて染めた、明るい赤", "A bright red, safflower over yellow"),
        c("茜色", "あかねいろ", "Akane-iro", 0xB7282E, "茜の根で染めた、夕焼けのような赤", "A sunset red from madder root"),
        c("緋色", "ひいろ", "Hiiro", 0xD3381C, "火の色にたとえられた、黄みの強い赤", "A strong yellowish red, like flame"),
        c("朱色", "しゅいろ", "Shu-iro", 0xEB6101, "鳥居に塗られる、黄みの赤", "The orange-red of shrine gates"),
        c("臙脂", "えんじ", "Enji", 0xB94047, "深く落ち着いた赤", "A deep, calm red"),
        c("蘇芳", "すおう", "Suou", 0x9E3D3F, "蘇芳の木の芯で染めた、紫みの赤", "A purplish red from sappanwood"),
        c("小豆色", "あずきいろ", "Azuki-iro", 0x96514D, "小豆の実のような、くすんだ赤", "A muted red like azuki beans"),
        c("韓紅", "からくれない", "Karakurenai", 0xE9546B, "紅を濃く染め重ねた、あざやかな赤", "A vivid red, dyed deep and many times"),
        c("弁柄色", "べんがらいろ", "Bengara-iro", 0x8F2E14, "古い町家の格子に残る、土の赤", "The earthy red of old townhouse lattices"),
        c("煉瓦色", "れんがいろ", "Renga-iro", 0xB55233, "焼いた煉瓦のような、黄みの赤茶", "A reddish brown like fired brick"),
        c("赤銅色", "しゃくどういろ", "Shakudou-iro", 0x752100, "日に焼けた肌にたとえる、赤みの深い茶", "A deep copper brown, like sunburnt skin"),
        // 桃・桜
        c("桜色", "さくらいろ", "Sakura-iro", 0xFEF4F4, "桜の花びらのような、ほんのり赤い白", "A white faintly blushed, like cherry petals"),
        c("薄紅", "うすべに", "Usubeni", 0xF0908D, "紅を淡くした、やさしい赤", "A soft, pale red"),
        c("桃色", "ももいろ", "Momo-iro", 0xF09199, "桃の花のような、明るい紅", "A bright pink like peach blossoms"),
        c("撫子色", "なでしこいろ", "Nadeshiko-iro", 0xEEBBCB, "撫子の花のような、紫みの淡い紅", "A pale purplish pink like a pink carnation"),
        c("躑躅色", "つつじいろ", "Tsutsuji-iro", 0xE95295, "つつじの花のような、あざやかな紅", "A vivid pink like azaleas"),
        c("牡丹色", "ぼたんいろ", "Botan-iro", 0xE7609E, "牡丹の花のような、紫みの紅", "A purplish pink like peonies"),
        c("珊瑚色", "さんごいろ", "Sango-iro", 0xF5B1AA, "桃色の珊瑚のような、黄みの淡い紅", "A soft coral pink"),
        c("鴇色", "ときいろ", "Toki-iro", 0xF4B3C2, "トキの風切羽のような、淡い紅", "The pale pink of a crested ibis's wings"),
        c("紅梅色", "こうばいいろ", "Koubai-iro", 0xF2A0A1, "早春に咲く紅梅のような、淡い紅", "The soft pink of early plum blossoms"),
        c("東雲色", "しののめいろ", "Shinonome-iro", 0xF19072, "夜明けの東の空のような、黄みの紅", "The orange-pink of the eastern sky at dawn"),
        // 橙・茶
        c("柿色", "かきいろ", "Kaki-iro", 0xED6D3D, "熟した柿の実のような、黄みのある赤", "An orange-red like ripe persimmons"),
        c("橙色", "だいだいいろ", "Daidai-iro", 0xEE7800, "橙の実のような、あざやかな黄赤", "A vivid orange like bitter orange fruit"),
        c("蜜柑色", "みかんいろ", "Mikan-iro", 0xF08300, "冬のこたつの蜜柑のような、明るい橙", "A bright orange like winter mandarins"),
        c("黄丹", "おうに", "Ouni", 0xEE7948, "昔、皇太子の装束に使われた、明るい黄赤", "A bright orange once worn by crown princes"),
        c("杏色", "あんずいろ", "Anzu-iro", 0xF7B977, "熟した杏の実のような、やわらかな橙", "A soft orange like ripe apricots"),
        c("柑子色", "こうじいろ", "Kouji-iro", 0xF6AD49, "柑子みかんの皮のような、明るい黄橙", "A bright yellow-orange like citrus peel"),
        c("枇杷色", "びわいろ", "Biwa-iro", 0xEBB471, "枇杷の実のような、くすんだ黄橙", "A muted yellow-orange like loquats"),
        c("琥珀色", "こはくいろ", "Kohaku-iro", 0xBF783A, "琥珀のような、透きとおった黄みの茶", "A clear yellowish brown like amber"),
        c("黄土色", "おうどいろ", "Oudo-iro", 0xC39143, "黄色い土のような、にぶい黄茶", "A dull yellow-brown like ochre earth"),
        c("小麦色", "こむぎいろ", "Komugi-iro", 0xE4AD6D, "実った小麦のような、明るい黄茶", "A light tan like ripe wheat"),
        c("狐色", "きつねいろ", "Kitsune-iro", 0xC38743, "狐の毛のような、こんがりした茶", "A toasty brown like a fox's coat"),
        c("丁子色", "ちょうじいろ", "Chouji-iro", 0xEFCD9A, "丁子のつぼみで染めた、淡い黄茶", "A pale tan dyed with clove buds"),
        c("亜麻色", "あまいろ", "Ama-iro", 0xD6C6AF, "亜麻の糸のような、灰みの薄い茶", "A light grayish tan like flax yarn"),
        c("朽葉色", "くちばいろ", "Kuchiba-iro", 0x917347, "落ち葉のような、くすんだ黄みの茶", "A dull yellow-brown like fallen leaves"),
        c("胡桃色", "くるみいろ", "Kurumi-iro", 0xA86F4C, "胡桃の皮で染めた、やわらかな茶", "A soft brown dyed with walnut husks"),
        c("茶色", "ちゃいろ", "Cha-iro", 0x965042, "茶の煮汁で染めた、赤みの茶", "A reddish brown, once dyed with tea"),
        c("栗色", "くりいろ", "Kuri-iro", 0x762F07, "栗の実の皮のような、深い赤茶", "A deep reddish brown like chestnut shells"),
        c("檜皮色", "ひわだいろ", "Hiwada-iro", 0x6C3524, "檜の皮で葺いた屋根のような、黒みの赤茶", "A dark red-brown like cypress-bark roofs"),
        c("焦茶", "こげちゃ", "Kogecha", 0x6F4B3E, "焦げたような、黒みの茶", "A dark, scorched brown"),
        // 黄
        c("山吹色", "やまぶきいろ", "Yamabuki-iro", 0xF8B500, "山吹の花のような、赤みの黄", "A warm yellow like yamabuki flowers"),
        c("黄色", "きいろ", "Ki-iro", 0xFFD900, "明るくすんだ黄", "A clear, bright yellow"),
        c("鬱金色", "うこんいろ", "Ukon-iro", 0xFABF14, "鬱金の根で染めた、あざやかな黄", "A vivid yellow dyed with turmeric"),
        c("黄金色", "こがねいろ", "Kogane-iro", 0xE6B422, "実った稲穂のような、金色の黄", "A golden yellow like ripened rice"),
        c("刈安色", "かりやすいろ", "Kariyasu-iro", 0xF5E56B, "刈安の草で染めた、緑みの黄", "A greenish yellow dyed with kariyasu grass"),
        c("菜の花色", "なのはないろ", "Nanohana-iro", 0xFFEC47, "春の菜の花畑のような、明るい黄", "The bright yellow of spring rapeseed fields"),
        c("卵色", "たまごいろ", "Tamago-iro", 0xFCD575, "卵の黄身のような、やわらかな黄", "A soft yellow like egg yolk"),
        c("鳥の子色", "とりのこいろ", "Torinoko-iro", 0xFFF1CF, "卵の殻のような、ごく淡い黄", "A very pale yellow like an eggshell"),
        c("芥子色", "からしいろ", "Karashi-iro", 0xD0AF4C, "からしのような、にぶい黄", "A dull yellow like mustard"),
        c("菜種油色", "なたねゆいろ", "Natane-yu-iro", 0xA69425, "菜種の油のような、緑みの暗い黄", "A dark greenish yellow like rapeseed oil"),
        c("鶸色", "ひわいろ", "Hiwa-iro", 0xD7CF3A, "鶸の羽のような、あざやかな黄緑", "A vivid yellow-green like a siskin's feathers"),
        // 緑
        c("萌黄", "もえぎ", "Moegi", 0xAACF53, "春に芽吹く若葉のような、明るい黄緑", "A bright yellow-green like spring sprouts"),
        c("若草色", "わかくさいろ", "Wakakusa-iro", 0xC3D825, "春の若い草のような、あざやかな黄緑", "A vivid yellow-green like young grass"),
        c("鶯色", "うぐいすいろ", "Uguisu-iro", 0x928C36, "鶯の背のような、くすんだ緑みの黄", "A dull olive like a bush warbler's back"),
        c("抹茶色", "まっちゃいろ", "Maccha-iro", 0xC5C56A, "点てた抹茶のような、やわらかな黄緑", "A soft yellow-green like whisked matcha"),
        c("苗色", "なえいろ", "Nae-iro", 0xB0CA71, "田植えの苗のような、明るい黄緑", "A light yellow-green like rice seedlings"),
        c("柳色", "やなぎいろ", "Yanagi-iro", 0xA8C97F, "柳の葉のような、やわらかな黄緑", "A soft green like willow leaves"),
        c("若緑", "わかみどり", "Wakamidori", 0x98D98E, "松の若葉のような、明るい緑", "A light green like young pine needles"),
        c("白緑", "びゃくろく", "Byakuroku", 0xD6E9CA, "岩絵の具の緑を白く砕いた、ごく淡い緑", "A very pale green from finely ground pigment"),
        c("苔色", "こけいろ", "Koke-iro", 0x69821B, "庭の苔のような、深い黄緑", "A deep yellow-green like garden moss"),
        c("松葉色", "まつばいろ", "Matsuba-iro", 0x839B5C, "松の葉のような、くすんだ緑", "A muted green like pine needles"),
        c("海松色", "みるいろ", "Miru-iro", 0x726D40, "海藻の海松のような、黒みの黄緑", "A dark olive like miru seaweed"),
        c("緑", "みどり", "Midori", 0x3EB370, "新緑の木々のような、明るい緑", "A fresh green like new leaves"),
        c("若竹色", "わかたけいろ", "Wakatake-iro", 0x68BE8D, "その年に伸びた竹のような、明るい青緑", "A light blue-green like this year's bamboo"),
        c("翡翠色", "ひすいいろ", "Hisui-iro", 0x38B48B, "翡翠の玉のような、あざやかな青緑", "A vivid blue-green like jade"),
        c("青磁色", "せいじいろ", "Seiji-iro", 0x7EBEA5, "青磁の器のような、やわらかな青緑", "A soft blue-green like celadon ware"),
        c("木賊色", "とくさいろ", "Tokusa-iro", 0x3B7960, "木賊の茎のような、深い青緑", "A deep blue-green like horsetail stems"),
        c("常磐色", "ときわいろ", "Tokiwa-iro", 0x007B43, "一年中変わらない常緑樹のような、深い緑", "A deep evergreen"),
        c("千歳緑", "ちとせみどり", "Chitose-midori", 0x316745, "長く栄える松にたとえた、暗い緑", "A dark green, named for long-lived pines"),
        c("深緑", "ふかみどり", "Fukamidori", 0x00552E, "夏の森の奥のような、濃い緑", "A dark green like the depths of a summer forest"),
        c("利休鼠", "りきゅうねずみ", "Rikyu-nezumi", 0x888E7E, "茶人の名を冠した、緑みの灰", "A greenish gray named after a tea master"),
        // 青
        c("浅葱色", "あさぎいろ", "Asagi-iro", 0x00A3AF, "葱の若い芽のような、あざやかな青緑", "A vivid teal like young scallion shoots"),
        c("水浅葱", "みずあさぎ", "Mizu-asagi", 0x80ABA9, "浅葱を淡くした、やわらかな青緑", "A soft, pale teal"),
        c("新橋色", "しんばしいろ", "Shinbashi-iro", 0x59B9C6, "明治の新橋の芸者に好まれた、明るい青緑", "A bright turquoise loved in Meiji-era Shinbashi"),
        c("青碧", "せいへき", "Seiheki", 0x478384, "青い玉のような、くすんだ青緑", "A muted blue-green like a blue gemstone"),
        c("白藍", "しらあい", "Shira-ai", 0xC1E4E9, "藍をごく薄く染めた、白に近い青", "A whitish blue, the faintest indigo"),
        c("甕覗", "かめのぞき", "Kamenozoki", 0xA2D7DD, "藍の甕を少しのぞいた程度に染めた、淡い青", "A pale blue, as if dipped once in an indigo vat"),
        c("秘色", "ひそく", "Hisoku", 0xABCED8, "秘蔵の青磁にたとえた、灰みの淡い青", "A grayish pale blue, after treasured celadon"),
        c("水色", "みずいろ", "Mizu-iro", 0xBCE2E8, "澄んだ水のような、淡い青", "A pale blue like clear water"),
        c("空色", "そらいろ", "Sora-iro", 0xA0D8EF, "晴れた日の空のような、明るい青", "A light blue like a clear sky"),
        c("勿忘草色", "わすれなぐさいろ", "Wasurenagusa-iro", 0x89C3EB, "勿忘草の花のような、明るい青", "A bright blue like forget-me-nots"),
        c("浅縹", "あさはなだ", "Asa-hanada", 0x84B9CB, "縹を淡くした、灰みの青", "A light grayish blue"),
        c("露草色", "つゆくさいろ", "Tsuyukusa-iro", 0x38A1DB, "露草の花のような、あざやかな青", "A vivid blue like dayflowers"),
        c("青", "あお", "Ao", 0x0095D9, "晴れた空や海のような、すんだ青", "A clear blue like sky and sea"),
        c("紺碧", "こんぺき", "Konpeki", 0x007BBB, "深い海や空のような、濃い青", "A deep azure like open sea and sky"),
        c("縹色", "はなだいろ", "Hanada-iro", 0x2792C3, "藍で染めた、明るい青", "A bright blue dyed with indigo"),
        c("群青色", "ぐんじょういろ", "Gunjou-iro", 0x4C6CB3, "岩絵の具の群青のような、紫みの青", "A purplish blue like mineral ultramarine"),
        c("瑠璃色", "るりいろ", "Ruri-iro", 0x1E50A2, "宝石の瑠璃のような、深い青", "A deep blue like lapis lazuli"),
        c("藍色", "あいいろ", "Ai-iro", 0x165E83, "藍の葉で染めた、深い青", "A deep blue dyed with indigo leaves"),
        c("紺色", "こんいろ", "Kon-iro", 0x223A70, "藍を濃く重ねた、黒みの青", "A dark navy, indigo dyed many times"),
        c("鉄紺", "てつこん", "Tetsukon", 0x17184B, "鉄のような、ごく暗い紺", "A very dark navy, like iron"),
        c("褐色", "かちいろ", "Kachi-iro", 0x181B39, "藍を何度も染めた、黒に近い紺", "An indigo so deep it looks black"),
        // 紫
        c("藤色", "ふじいろ", "Fuji-iro", 0xBBBCDE, "藤の花のような、淡い青紫", "A pale lavender like wisteria"),
        c("藤紫", "ふじむらさき", "Fuji-murasaki", 0xA59ACA, "藤の花房の濃い所のような、明るい紫", "A light purple like the depth of wisteria clusters"),
        c("紅藤", "べにふじ", "Benifuji", 0xCCA6BF, "藤色に紅を足した、淡い赤紫", "A pale pinkish lavender"),
        c("菖蒲色", "あやめいろ", "Ayame-iro", 0xCC7EB1, "菖蒲の花のような、明るい赤紫", "A bright magenta-purple like iris"),
        c("桔梗色", "ききょういろ", "Kikyou-iro", 0x5654A2, "秋の桔梗の花のような、青紫", "A blue-violet like bellflowers"),
        c("菫色", "すみれいろ", "Sumire-iro", 0x7058A3, "菫の花のような、深い青紫", "A deep violet like violets"),
        c("江戸紫", "えどむらさき", "Edo-murasaki", 0x745399, "江戸で好まれた、青みの紫", "A bluish purple loved in Edo"),
        c("紫", "むらさき", "Murasaki", 0x884898, "紫草の根で染めた、高貴な紫", "A noble purple dyed with gromwell root"),
        c("古代紫", "こだいむらさき", "Kodai-murasaki", 0x895B8A, "昔の紫草染めのような、くすんだ紫", "A muted purple like old gromwell dye"),
        c("茄子紺", "なすこん", "Nasukon", 0x824880, "茄子の皮のような、赤みの紫", "A reddish purple like eggplant skin"),
        c("葡萄色", "えびいろ", "Ebi-iro", 0x640125, "山葡萄の実のような、深い赤紫", "A deep wine purple like wild grapes"),
    ]
}
