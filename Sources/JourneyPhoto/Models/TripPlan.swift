import Foundation

/// 旅行プラン（`GET/POST/PUT/DELETE /user/trips`）。
///
/// **Web の `lib/hooks/useTripPlans.ts` と同じ形。** 行きたい場所を
/// 「いつ・どの順で回るか」に並べるだけのもので、移動時間・費用・経路・
/// AI・予約は**作らない**（Web の計画書 §12。計算していない数字を出さない）。
///
/// 読むときは**読めた分だけ採る**（Web の `usableTripPlan` と同じ判断）。
/// 1件の壊れた項目のせいで、プランごと・一覧ごと見えなくならないように。
struct TripPlan: Decodable, Identifiable, Equatable {
    let planId: String
    let title: String
    /// `YYYY-MM-DD`。**無ければ nil**（作り話をしない）
    let startDate: String?
    let endDate: String?
    let days: [TripDay]
    let createdAt: String?
    let updatedAt: String?
    /// 仲間と共有したプラン（2026-11-12・サーバーの `trip#<planId>`）。**共有していなければ nil**
    let share: TripShare?
    /// 場所を足した人（`TripShareText.itemKey` → 利用者 ID）。共有したプランで、ほかの仲間が足した項目だけ持つ。
    /// `TripItem` には持たせない（日程の直しは今までどおり項目だけを送り、足した人はサーバーが前の日程から決める）
    let addedBy: [String: String]

    var id: String { planId }

    /// 何か所ぶん置いてあるか（日をまたいで数える）。**数えた値**
    var itemCount: Int { days.reduce(0) { $0 + $1.items.count } }

    init(planId: String, title: String, startDate: String? = nil, endDate: String? = nil,
         days: [TripDay] = [], createdAt: String? = nil, updatedAt: String? = nil,
         share: TripShare? = nil, addedBy: [String: String] = [:]) {
        self.planId = planId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.days = days
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.share = share
        self.addedBy = addedBy
    }

    private enum CodingKeys: String, CodingKey {
        case planId, title, startDate, endDate, days, createdAt, updatedAt, shared, ownerId, memberIds, rev
    }

    /// 足した人だけを読む軽い形（項目の `by`）
    private struct ByDay: Decodable { let items: [Lenient<ByItem>]? }
    private struct ByItem: Decodable { let kind: String; let spotId: String?; let slug: String?; let by: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // **ID の無い行は読まない**（開いても直せない・消せない）
        let planId = try c.decode(String.self, forKey: .planId)
        guard !planId.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .planId, in: c, debugDescription: "planId が空")
        }
        self.planId = planId
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.startDate = try? c.decode(String.self, forKey: .startDate)
        self.endDate = try? c.decode(String.self, forKey: .endDate)
        // **読めない日は空の日として残す**（Web の `usableTripPlan` と同じ）。落とすと
        // 3日目以降の「N 日目」がずれ、次の保存で空の日がサーバーから消える
        self.days = (try? c.decode([Lenient<TripDay>].self, forKey: .days))?.map { $0.value ?? TripDay() } ?? []
        self.createdAt = try? c.decode(String.self, forKey: .createdAt)
        self.updatedAt = try? c.decode(String.self, forKey: .updatedAt)
        // 共有したプラン。**形が揃わなければ本人だけのプランとして読む**（古いサーバー・壊れた行で開けなくしない）
        if (try? c.decode(Bool.self, forKey: .shared)) == true,
           let owner = try? c.decode(String.self, forKey: .ownerId),
           let rev = try? c.decode(Int.self, forKey: .rev) {
            let members = (try? c.decode([String].self, forKey: .memberIds)) ?? [owner]
            self.share = TripShare(ownerId: owner, memberIds: members, rev: rev)
        } else {
            self.share = nil
        }
        var by: [String: String] = [:]
        for day in (try? c.decode([Lenient<ByDay>].self, forKey: .days)) ?? [] {
            for raw in day.value?.items ?? [] {
                guard let it = raw.value, let who = it.by, !who.isEmpty else { continue }
                if it.kind == "spot", let id = it.spotId { by["s:\(id)"] = who }
                if it.kind == "location", let slug = it.slug { by["l:\(slug)"] = who }
            }
        }
        self.addedBy = by
    }
}

/// 仲間と共有したプランの欄（`GET /user/trips` の `shared: true` の行）
struct TripShare: Equatable {
    let ownerId: String
    let memberIds: [String]
    /// 版（`rev`）。日程を送るときに添え、ほかの仲間が先に変えていたらサーバーが 409 で断る
    let rev: Int

    func isOwner(_ uid: String?) -> Bool { uid != nil && uid == ownerId }
}

/// 1日ぶん。`date` は**置いた人が持たせたときだけ**ある（Web の画面は付けない）
struct TripDay: Codable, Equatable {
    var date: String?
    var items: [TripItem]

    init(date: String? = nil, items: [TripItem] = []) {
        self.date = date
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case date, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try? c.decode(String.self, forKey: .date)
        self.items = (try? c.decode([Lenient<TripItem>].self, forKey: .items))?.compactMap(\.value) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encode(items, forKey: .items)
    }
}

/// 日程に置く1か所。**台帳の撮影スポット**か**撮影地**のどちらか。
///
/// 2つは混ぜない（`SavedSpotKey` と同じ理由）。スポットは台帳の鍵
/// （`sp_…`＝`OfficialSpot.spotId`）で、撮影地は `/location/<slug>` の slug で持つ。
enum TripItem: Codable, Equatable {
    case spot(spotId: String, note: String?)
    case location(slug: String, note: String?)

    private enum CodingKeys: String, CodingKey { case kind, spotId, slug, note }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let note = try? c.decode(String.self, forKey: .note)
        switch try c.decode(String.self, forKey: .kind) {
        case "spot":
            self = .spot(spotId: try c.decode(String.self, forKey: .spotId), note: note)
        case "location":
            self = .location(slug: try c.decode(String.self, forKey: .slug), note: note)
        default:
            // 知らない種類は読まない（呼ぶ側の `Lenient` が落とす）
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "知らない種類")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .spot(let spotId, let note):
            try c.encode("spot", forKey: .kind)
            try c.encode(spotId, forKey: .spotId)
            try c.encodeIfPresent(note, forKey: .note)
        case .location(let slug, let note):
            try c.encode("location", forKey: .kind)
            try c.encode(slug, forKey: .slug)
            try c.encodeIfPresent(note, forKey: .note)
        }
    }
}

/// 読めない要素を `nil` にして、配列の残りを生かす包み（`SpotBody` も使う）。
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// 写真の行（`Photo`）に入れるため（`spotAuto`・`geoApprox`・2026-10-31）
extension Lenient: Equatable where T: Equatable {}

/// `{ "plans": [...] }`。**書き込みの応答も同じ形**（書いたあとの一覧）
struct TripPlanList: Decodable {
    let plans: [TripPlan]
    /// 書き込みは通ったが、共有したプランを読めなかった（サーバーの `sharedFailed`）。
    /// このときの一覧には共有したプランが入っていないので、画面は前に見えていた分を残す（`TripPlansModel.merged`）
    let sharedFailed: Bool

    private enum CodingKeys: String, CodingKey { case plans, sharedFailed }

    init(plans: [TripPlan], sharedFailed: Bool = false) {
        self.plans = plans
        self.sharedFailed = sharedFailed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // **`plans` が無ければ投げる**（形が違う応答を「0件」と混ぜない）
        plans = try c.decode([Lenient<TripPlan>].self, forKey: .plans).compactMap(\.value)
        sharedFailed = (try? c.decode(Bool.self, forKey: .sharedFailed)) ?? false
    }
}
