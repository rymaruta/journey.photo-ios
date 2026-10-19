import Foundation

/// 島の空の時刻（板の 朝・昼・夕・夜）。撮った時刻の段（`CampSlot`）の夜明け前は「朝」の空で描く
enum CampTime: String, CaseIterable, Codable, Sendable {
    case morning, day, evening, night

    var name: String {
        switch self {
        case .morning: return L("朝", "Morning")
        case .day: return L("昼", "Day")
        case .evening: return L("夕", "Evening")
        case .night: return L("夜", "Night")
        }
    }

    init(slot: CampSlot) {
        switch slot {
        case .predawn, .morning: self = .morning
        case .day: self = .day
        case .evening: self = .evening
        case .night: self = .night
        }
    }
}

/// 時刻と季節の決まり（日本の暮らしの感覚で区切る・2026-10-18 判断）
enum CampClock {

    /// 撮った時刻の段。夜明け前 3〜5 時・朝 5〜10 時・昼 10〜16 時・夕 16〜19 時・夜 19〜3 時
    static func slot(hour: Int) -> CampSlot {
        switch hour {
        case 3..<5: return .predawn
        case 5..<10: return .morning
        case 10..<16: return .day
        case 16..<19: return .evening
        default: return .night
        }
    }

    /// 季節。春 3〜5 月・夏 6〜8 月・秋 9〜11 月・冬 12〜2 月
    static func season(month: Int) -> CampSeason {
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    static func slot(of date: Date, calendar: Calendar = .current) -> CampSlot {
        slot(hour: calendar.component(.hour, from: date))
    }

    static func season(of date: Date, calendar: Calendar = .current) -> CampSeason {
        season(month: calendar.component(.month, from: date))
    }
}

/// 月齢（満月の夜の部品 `lantern.candle_brass`）。日付から計算するので端末だけで決まる
enum CampMoon {
    /// 朔望月（日）
    static let synodicMonth = 29.530588853
    /// 基準の新月（2000-01-06 18:14 UTC）
    static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    /// 月齢（0〜29.53。0 が新月、約 14.77 が満月）
    static func age(at date: Date) -> Double {
        let days = date.timeIntervalSince(referenceNewMoon) / 86_400
        let age = days.truncatingRemainder(dividingBy: synodicMonth)
        return age < 0 ? age + synodicMonth : age
    }

    /// 満月の前後 1 日（月がほぼ丸く見える間）
    static func isFull(at date: Date) -> Bool {
        abs(age(at: date) - synodicMonth / 2) <= 1.0
    }
}

/// 島の育ち（板 CampGrow: 焚き火 → テント場 → キャンプ場）。立てた切り絵の数で育つ
enum CampStage: String, CaseIterable, Codable, Sendable {
    case fire, tent, camp

    var name: String {
        switch self {
        case .fire: return L("焚き火", "Campfire")
        case .tent: return L("テント場", "Tent site")
        case .camp: return L("キャンプ場", "Campsite")
        }
    }

    /// 島の大きさの倍率（板の寸法の付箋: 焚き火 0.62・テント場 0.86・キャンプ場 1）
    var scale: Double {
        switch self {
        case .fire: return 0.62
        case .tent: return 0.86
        case .camp: return 1
        }
    }

    /// この段になる切り絵の数（2026-10-18 判断: 1 枚目でテントが立ち、6 枚でキャンプ場）
    var threshold: Int {
        switch self {
        case .fire: return 0
        case .tent: return 1
        case .camp: return 6
        }
    }

    static func stage(cutouts: Int) -> CampStage {
        allCases.last { cutouts >= $0.threshold } ?? .fire
    }

    /// 次の段まであと何枚（最後の段なら nil）
    static func remaining(cutouts: Int) -> Int? {
        let now = stage(cutouts: cutouts)
        guard let next = allCases.first(where: { $0.threshold > now.threshold }) else { return nil }
        return max(0, next.threshold - cutouts)
    }
}

/// 時刻・季節ごとの光（板 Camp の値・実装の指定「灯りと光の強さ」「影と地面」の付箋）。
/// 向きは**板の座標**（x 右・y 下・z 手前）。SceneKit へは y を返して渡す（`CampOrbit.toScene`）
struct CampLighting: Equatable, Sendable {
    /// 太陽（夜は月）の光が来る向き（光の進む向きの逆ではなく、板と同じ「L」）
    let sun: CampVec3
    /// 環境光（0〜1）
    let ambient: Double
    /// 拡散光（0〜1）
    let diffuse: Double
    /// 影の色（16 進）
    let shadow: UInt32
    /// 落ち影の濃さ（冬は薄い・夜は出さない）
    let shadowOpacity: Double
    /// 太陽の色の足し（板の `sun`・0〜255）
    let sunTint: [Double]
    /// 空の 3 色（上・中・下）
    let sky: [UInt32]
    /// 太陽（月）の芯と光の輪
    let sunCore: UInt32
    let sunHalo: UInt32
    /// 島の下の霧の色
    let mist: UInt32
    /// 焚き火の強さと届く距離
    let fireIntensity: Double
    let fireRange: Double
    /// 芝の上の焚き火の明かりの輪（半径 x・z）。無ければ nil
    let fireGlow: (Double, Double)?
    /// テントの布が内から光る（夜）
    let tentGlows: Bool
    /// 星を出す
    let stars: Bool

    static func == (a: CampLighting, b: CampLighting) -> Bool {
        a.sun == b.sun && a.ambient == b.ambient && a.diffuse == b.diffuse && a.shadow == b.shadow
            && a.shadowOpacity == b.shadowOpacity && a.sky == b.sky && a.fireIntensity == b.fireIntensity
            && a.fireRange == b.fireRange && a.fireGlow?.0 == b.fireGlow?.0 && a.fireGlow?.1 == b.fireGlow?.1
            && a.tentGlows == b.tentGlows && a.stars == b.stars && a.mist == b.mist
    }

    /// 焚き火の位置（板の付箋: (38, −6, 34)）
    static let firePosition = CampVec3(38, -6, 34)
    /// 焚き火の色（255, 146, 64）
    static let fireColor: UInt32 = 0xFF9240
    /// ランタン（キャンプ場・夜）: (−88, −46, 10) 色 (255,196,120)。
    /// 2026-10-19 owner「夜の光り方がおかしい」: 強さ 1.1→0.4・距離 40→55（芯の白い丸を避け、なだらかな溜まりに）
    static let lanternPosition = CampVec3(-88, -46, 10)
    static let lanternColor: UInt32 = 0xFFC478
    static let lanternIntensity = 0.4
    static let lanternRange = 55.0

    static func of(time: CampTime, season: CampSeason) -> CampLighting {
        let winter = season == .winter
        let night = time == .night
        var sun: CampVec3, ambient: Double, diffuse: Double, shadow: UInt32, tint: [Double]
        var sky: [UInt32], core: UInt32, halo: UInt32
        switch time {
        case .morning:
            sun = CampVec3(-0.74, -0.42, -0.52); ambient = 0.36; diffuse = 0.62; shadow = 0x2A3A5A; tint = [36, 26, 8]
            sky = [0x6D8AA8, 0xD8C9AE, 0xEFD9B4]; core = 0xFFF4DC; halo = 0xFFD9A0
        case .day:
            sun = CampVec3(-0.22, -0.92, 0.32); ambient = 0.42; diffuse = 0.6; shadow = 0x26364C; tint = [16, 16, 10]
            sky = [0x3F6C96, 0x8FB2CC, 0xD4E2EA]; core = 0xFFFBEA; halo = 0xFFF3CF
        case .evening:
            sun = CampVec3(0.8, -0.3, -0.52); ambient = 0.30; diffuse = 0.62; shadow = 0x3A2440; tint = [92, 38, 0]
            sky = [0x253150, 0xB4694A, 0xEAA868]; core = 0xFFE2B0; halo = 0xFF9A50
        case .night:
            // 月の指向光はごく弱く（0.3→0.05）。残すと島全体が昼のように均一に明るく、焚き火の溜まりが消える
            // （2026-10-19 owner・とおまわり号の中と同じ判断）
            sun = CampVec3(0.36, -0.8, -0.46); ambient = 0.14; diffuse = 0.05; shadow = 0x08122A; tint = [0, 0, 0]
            sky = [0x03060D, 0x0B1424, 0x16223A]; core = 0xE9EEF8; halo = 0x9FB4D8
        }
        // 冬は空が白み、環境光 +0.14、影は青み（夜は除く）
        if winter && !night {
            sky = [sky[0], 0xB9C6D2, 0xE8EEF3]
            ambient += 0.14
            shadow = 0x3A5068
            tint = [0, 0, 0]
        }
        let mist: UInt32 = night ? 0x1A2638 : (time == .evening ? 0xF0B07A : 0xF4F1EA)
        // 夜の焚き火: 2.4→0.85・届く 58→50（外の車の夜と同じく、硬く白い芯と遠くまで飛ぶのを止める）
        let fireIntensity = night ? 0.85 : (time == .evening ? 0.9 : 0.35)
        let fireRange = night ? 50.0 : 34.0
        let glow: (Double, Double)? = night ? (60, 52) : (time == .evening ? (46, 40) : nil)
        return CampLighting(sun: sun.normalized, ambient: ambient, diffuse: diffuse, shadow: shadow,
                            shadowOpacity: night ? 0 : (winter ? 0.32 : 0.42), sunTint: tint, sky: sky,
                            sunCore: core, sunHalo: halo, mist: mist, fireIntensity: fireIntensity,
                            fireRange: fireRange, fireGlow: glow, tentGlows: night, stars: night)
    }
}
