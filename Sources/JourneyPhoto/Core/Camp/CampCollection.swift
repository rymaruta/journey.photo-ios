import Foundation

/// キャンプ場に加えた写真 1 枚の記録（端末の中だけ・サーバーには送らない）。
/// 集める条件（写真の枚数・時刻・季節・都道府県・同じ場所・標高・満月・写った物）はこれだけで決まる
struct CampShot: Codable, Equatable, Identifiable, Sendable {
    let id: String
    /// 撮った日時（撮影情報が無ければ加えた日時）
    let takenAt: Date
    /// 撮った所（位置が無ければ nil）
    var latitude: Double?
    var longitude: Double?
    /// 標高（m）
    var altitude: Double?
    /// 都道府県（iOS の地名変換）・市区町村
    var prefecture: String?
    var locality: String?
    /// 写った物（端末の画像分類）
    var subjects: [CampSubject]
    /// 人が写っていた（数えない・切り絵にしない）
    var hasPeople: Bool = false
    /// 切り絵にした（空の色だけに使った写真は false）
    var cutout: Bool = true
}

/// 部品 1 つの集まり具合
struct CampProgress: Equatable, Sendable {
    let current: Int
    let target: Int
    var done: Bool { current >= target }
}

/// 集める決まり（板 CampDex「集める」の付箋）
enum CampCollection {

    /// 高原（m 以上）・山頂（m 以上）。2026-10-18 判断（板に値が無い）
    static let highlandMeters = 1000.0
    static let summitMeters = 2000.0
    /// 同じ場所とみなす升目（緯度・経度 0.01° ≒ 1km）。地名が分かれば市区町村で数える
    static let placeGrid = 0.01

    /// 数える写真（人が写った写真は数えない）
    static func counted(_ shots: [CampShot]) -> [CampShot] { shots.filter { !$0.hasPeople } }

    /// 同じ場所の鍵（都道府県 + 市区町村。無ければ緯度経度の升目。どちらも無ければ nil）
    static func placeKey(_ s: CampShot) -> String? {
        if let pref = s.prefecture, let loc = s.locality { return pref + "/" + loc }
        if let lat = s.latitude, let lon = s.longitude {
            return "g:\(Int((lat / placeGrid).rounded(.down))):\(Int((lon / placeGrid).rounded(.down)))"
        }
        if let pref = s.prefecture { return pref }
        return nil
    }

    /// 1 つの条件の「いま」と「要る数」
    static func progress(_ unlock: CampUnlock, shots all: [CampShot], calendar: Calendar = .current) -> CampProgress {
        let shots = counted(all)
        func count(_ f: (CampShot) -> Bool) -> Int { shots.filter(f).count }
        let current: Int
        switch unlock {
        case .starter: current = 1
        case .server: current = 0
        case .photos: current = shots.count
        case .subject(let s, _): current = count { $0.subjects.contains(s) }
        case .season(let season, _): current = count { CampClock.season(of: $0.takenAt, calendar: calendar) == season }
        case .time(let slot, _): current = count { CampClock.slot(of: $0.takenAt, calendar: calendar) == slot }
        case .subjectAtTime(let s, let slot, _):
            current = count { $0.subjects.contains(s) && CampClock.slot(of: $0.takenAt, calendar: calendar) == slot }
        case .subjectInSeason(let s, let season, _):
            current = count { $0.subjects.contains(s) && CampClock.season(of: $0.takenAt, calendar: calendar) == season }
        case .fullMoonNight:
            current = count { CampMoon.isFull(at: $0.takenAt) && CampClock.slot(of: $0.takenAt, calendar: calendar) == .night }
        case .yearRound: current = longestMonthStreak(shots, calendar: calendar)
        case .samePlace:
            var tally: [String: Int] = [:]
            for s in shots { if let k = placeKey(s) { tally[k, default: 0] += 1 } }
            current = tally.values.max() ?? 0
        case .places: current = Set(shots.compactMap(placeKey)).count
        case .prefectures: current = Set(shots.compactMap(\.prefecture)).count
        case .highland: current = count { ($0.altitude ?? -1) >= highlandMeters }
        case .summit: current = count { ($0.altitude ?? -1) >= summitMeters }
        }
        return CampProgress(current: min(current, unlock.target), target: unlock.target)
    }

    /// 続けて写真を撮った月の数のいちばん長い続き（一年続けて撮る）
    static func longestMonthStreak(_ shots: [CampShot], calendar: Calendar = .current) -> Int {
        let months = Set(shots.map { s -> Int in
            let c = calendar.dateComponents([.year, .month], from: s.takenAt)
            return (c.year ?? 0) * 12 + (c.month ?? 1) - 1
        }).sorted()
        var best = 0, run = 0, last: Int?
        for m in months {
            run = (last.map { m == $0 + 1 } ?? false) ? run + 1 : 1
            best = max(best, run)
            last = m
        }
        return best
    }

    /// 持っている部品（最初からの 23 + 条件を満たしたもの。要サーバーは入らない）
    static func owned(shots: [CampShot], calendar: Calendar = .current) -> Set<String> {
        Set(CampCatalog.allParts.filter { part in
            !part.needsServer && progress(part.unlock, shots: shots, calendar: calendar).done
        }.map(\.id))
    }

    /// 図鑑の数（持っている数 / 端末で集められる数）
    static func tally(owned: Set<String>) -> (owned: Int, total: Int) {
        let collectible = CampCatalog.collectible
        return (collectible.filter { owned.contains($0.id) }.count, collectible.count)
    }
}

/// 図鑑の絞り込み（板: すべて／持っている／まだ／珍しさ／新着）
enum CampDexFilter: Hashable, Sendable {
    case all, owned, missing, rarity(CampRarity), new

    func includes(_ part: CampPart, owned: Set<String>, unseen: Set<String>) -> Bool {
        switch self {
        case .all: return true
        case .owned: return owned.contains(part.id)
        case .missing: return !owned.contains(part.id)
        case .rarity(let r): return part.rarity == r
        case .new: return unseen.contains(part.id)
        }
    }
}

/// 部品の札の状態
enum CampPartState: Equatable, Sendable {
    /// 持っている
    case owned
    /// まだ（端末で集められる）
    case missing
    /// まだ集められない（サーバーの口ができるまで「近日」）
    case comingSoon

    static func of(_ part: CampPart, owned: Set<String>) -> CampPartState {
        if part.needsServer { return .comingSoon }
        return owned.contains(part.id) ? .owned : .missing
    }
}
