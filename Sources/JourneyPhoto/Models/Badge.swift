import Foundation

// バッジ（メダル）の受け取り方（第1段階・2026-10-09）。
//
// **どれも投げない形で読む。** サーバーは並行して作っている途中で、古いサーバーは
// 項目を返さない。プロフィールの1項目の型違いで画面全体の復号が落ちる
// （`UserProfile` の注記）のを避けるため、読めない項目は「無い」に倒す。

/// 持っているバッジ1つ。`badges` の `{key: {tier, at}}` の1項目
struct EarnedBadge: Equatable, Identifiable {
    /// サーバーの鍵（`first`・`prefectures`・`earlyUser` など）
    let key: String
    /// 段（1 銅・2 銀・3 白金）。段の無いバッジ（初期ユーザー）は 1
    let tier: Int
    /// 受け取った時刻（ISO8601）。古いサーバーは持たないことがある
    let at: String?

    var id: String { key }
}

/// 持っているバッジの一覧（`{key: {tier, at}}`）。
///
/// **1項目が壊れていても残りは読む。** 段が数でない・0以下の項目だけ落とす。
/// 段は数か数の文字列のどちらでも読む（JSON を経由する道で文字にされることがある）
struct BadgeSet: Decodable, Equatable {

    /// 鍵 → 持っているバッジ
    let byKey: [String: EarnedBadge]

    init(_ badges: [EarnedBadge] = []) {
        var map: [String: EarnedBadge] = [:]
        for badge in badges { map[badge.key] = badge }
        byKey = map
    }

    private struct Entry: Decodable {
        let tier: Int?
        let at: String?

        private enum CodingKeys: String, CodingKey { case tier, at }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tier = LenientInt.read(c, .tier)
            at = try? c.decodeIfPresent(String.self, forKey: .at)
        }
    }

    init(from decoder: Decoder) throws {
        let rows = (try? [String: Lenient<Entry>](from: decoder)) ?? [:]
        var map: [String: EarnedBadge] = [:]
        for (key, row) in rows {
            guard !key.isEmpty, let entry = row.value, let tier = entry.tier, tier >= 1 else { continue }
            map[key] = EarnedBadge(key: key, tier: tier, at: entry.at)
        }
        byKey = map
    }

    subscript(key: String) -> EarnedBadge? { byKey[key] }

    var isEmpty: Bool { byKey.isEmpty }
}

/// 次の段までの進み具合（`GET /user/badges` の `progress` の1項目）
struct BadgeProgress: Equatable {
    /// いま数えている数（都道府県の数・朝の写真の枚数など）
    let count: Int
    /// いまの段（0 はまだ持っていない）
    let tier: Int
    /// 次の段に要る数。**nil はもう上の段が無い**（達成）
    let next: Int?
}

/// `GET /user/badges` の答え（`{badges, progress}`）。
///
/// **`badges` が無ければ投げる**——形の違う応答を「何も持っていない」と混ぜない
/// （`TripPlanList` と同じ判断）。`progress` は無くても読む（棚の「あと◯で次」が出ないだけ）
struct BadgeStatus: Decodable, Equatable {
    let badges: BadgeSet
    let progress: [String: BadgeProgress]

    init(badges: BadgeSet, progress: [String: BadgeProgress] = [:]) {
        self.badges = badges
        self.progress = progress
    }

    private enum CodingKeys: String, CodingKey { case badges, progress }

    private struct Row: Decodable {
        let value: BadgeProgress?
        private enum CodingKeys: String, CodingKey { case count, tier, next }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self),
                  let count = LenientInt.read(c, .count) else {
                value = nil
                return
            }
            value = BadgeProgress(count: max(0, count),
                                  tier: max(0, LenientInt.read(c, .tier) ?? 0),
                                  next: LenientInt.read(c, .next))
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        badges = try c.decode(BadgeSet.self, forKey: .badges)
        let rows = (try? c.decodeIfPresent([String: Row].self, forKey: .progress)) ?? [:]
        progress = rows.compactMapValues(\.value)
    }
}

/// Pro マークの形。**既定は絞り羽根**（板 ProMarkOptions・2026-10-09）
enum ProMarkStyle: String, CaseIterable, Identifiable, Equatable {
    case iris, plate

    var id: String { rawValue }

    /// 名前の横の画面の切り替えの札
    var label: String {
        switch self {
        case .iris: return L("絞り羽根", "Aperture")
        case .plate: return "PRO"
        }
    }
}

/// 文字を**投げずに**読む入れ物（`displayBadge`・`proMarkStyle`）。文字でなければ nil、
/// 空の文字も nil（「選んでいない」と同じ）
struct LenientText: Decodable, Equatable {
    let value: String?

    init(_ value: String?) { self.value = value }

    init(from decoder: Decoder) throws {
        let text = try? String(from: decoder)
        value = text.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// 数を**投げずに**読む（数でも数の文字列でも）
enum LenientInt {
    static func read<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let number = try? c.decodeIfPresent(Int.self, forKey: key) { return number }
        if let double = try? c.decodeIfPresent(Double.self, forKey: key), double.isFinite,
           double == double.rounded(), abs(double) < 1e9 {
            return Int(double)
        }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

/// **JSON の null をそのまま送る**ための包み（プロフィールの部分更新の `displayBadge`）。
///
/// `ProfilePatch` は nil を「触らない」として省く（`JSONEncoder` の既定）。
/// バッジを外すには `null` を送る必要があるので、`Clearable(nil)` で「外す」を表す
struct Clearable<Value: Encodable & Equatable>: Encodable, Equatable {
    let value: Value?

    init(_ value: Value?) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let value { try c.encode(value) } else { try c.encodeNil() }
    }
}
