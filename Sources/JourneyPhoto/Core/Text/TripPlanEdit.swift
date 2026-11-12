import Foundation

/// 旅行プランの日程を**並べ替える・別の日へ移す・ひとことを添える**ときの決まり（2026-09-30）。
///
/// 以前の画面は項目を「外す（×）」ことしかできず、順番も日も変えられなかった
/// ——「いつ・どの順で回るか」に並べる道具（`TripPlan` の注記）なのに、並びが動かせない。
/// 画面（`TripPlanDetailView`）はここを呼ぶだけにして、規則を Linux の `swift test` で見張る。
///
/// **断る形は `nil`。** 範囲外の添字・移す先の日がいっぱい（`TripPlanService.itemsPerDayMax`）の
/// ときは何も変えない。サーバーは上限を超えた日程を 403 で断るので、画面の側で先に止める。
enum TripPlanEdit {

    // MARK: - 日を消す

    /// 日を消す前に確かめるか。**予定の入った日だけ**（空の日はすぐ消す）。
    /// 日の見出しの削除は確認が無く、隣の地図のボタンを狙った指のずれで1日分が消えた
    /// （0755872 のレビュー・2026-09-30 owner の判断「推奨で」）
    static func confirmsRemoving(_ day: TripDay) -> Bool {
        !day.items.isEmpty
    }

    /// 日を消す。**確かめている間に日程が少しでも変わっていたら何もしない**（`nil`）——
    /// 添字だけで消すと、ほかの日を消したあとの確認で別の日が消える。消す日の中身だけを比べると、
    /// 同じ中身の日が並んでいて片方が差し替わったときに残りの日まで消えた（37b96ec のレビュー）
    static func removeDay(_ days: [TripDay], at index: Int, snapshot: [TripDay]) -> [TripDay]? {
        guard days == snapshot, days.indices.contains(index) else { return nil }
        var out = days
        out.remove(at: index)
        return out
    }

    /// 同じ日の中で1つ上へ（先頭なら `nil`）
    static func moveUp(_ days: [TripDay], day: Int, item: Int) -> [TripDay]? {
        guard item > 0 else { return nil }
        return move(days, from: (day, item), toDay: day, at: item - 1)
    }

    /// 同じ日の中で1つ下へ（末尾なら `nil`）
    static func moveDown(_ days: [TripDay], day: Int, item: Int) -> [TripDay]? {
        guard days.indices.contains(day), item + 1 < days[day].items.count else { return nil }
        return move(days, from: (day, item), toDay: day, at: item + 1)
    }

    /// 別の日の**末尾**へ移す（同じ日なら `nil`・移す先がいっぱいなら `nil`）
    static func moveToDay(_ days: [TripDay], day: Int, item: Int, toDay: Int) -> [TripDay]? {
        guard toDay != day, days.indices.contains(toDay) else { return nil }
        return move(days, from: (day, item), toDay: toDay, at: days[toDay].items.count)
    }

    /// 移す本体。`at` は**取り除いたあと**の移す先の日での位置（末尾まで可）
    static func move(_ days: [TripDay], from: (day: Int, item: Int), toDay: Int, at: Int) -> [TripDay]? {
        guard days.indices.contains(from.day),
              days[from.day].items.indices.contains(from.item),
              days.indices.contains(toDay) else { return nil }
        // 別の日へ移すときだけ、移す先の数を見る（同じ日の中は数が変わらない）
        if toDay != from.day, days[toDay].items.count >= TripPlanService.itemsPerDayMax { return nil }
        var out = days
        let moving = out[from.day].items.remove(at: from.item)
        guard at >= 0, at <= out[toDay].items.count else { return nil }
        out[toDay].items.insert(moving, at: at)
        return out
    }

    // MARK: - 運ぶ印で運ぶ（2026-11-10・札 #521・板 TripPlanDays）

    /// 運ぶ印が持つ中身（「trip|日|位置|項目の鍵」）。**落とした時点の日程で項目を探し直す**ので、
    /// 運んでいる間に日程が差し替わっても別の項目を動かさない（`locate` と同じ考え）
    static func dragPayload(day: Int, item: Int, of value: TripItem) -> String {
        "trip|\(day)|\(item)|\(SavedSpotsTrip.itemKey(value))"
    }

    /// 落とした。`toItem` はその行の上（nil はその日の末尾）。
    ///
    /// - どの向きでも**落とした行の上**に入る（落とす先の印は行の上の線）。日の末尾へはその日の追加の行に落とす
    /// - いっぱいの日へは運べない（`move` が断る）
    /// - 中身が読めない・項目が見つからない・動かない（同じ位置）ときは nil（何も変えない）
    static func dropped(_ days: [TripDay], payload: String, toDay: Int, toItem: Int?) -> [TripDay]? {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "trip", let day = Int(parts[1]), let item = Int(parts[2]),
              days.indices.contains(day), days.indices.contains(toDay) else { return nil }
        let key = parts[3]
        let items = days[day].items
        let found: Int?
        if items.indices.contains(item), SavedSpotsTrip.itemKey(items[item]) == key {
            found = item
        } else {
            found = items.indices.filter { SavedSpotsTrip.itemKey(items[$0]) == key }
                .min { abs($0 - item) < abs($1 - item) }
        }
        guard let from = found else { return nil }
        let sameDay = toDay == day
        let count = days[toDay].items.count
        let at: Int
        if let toItem {
            guard toItem >= 0, toItem < count else { return nil }
            // 落とした行の**上**に入れる（落とす先の印＝行の上の真鍮の線と同じ位置・確かめ役の指摘 2026-11-10）。
            // 同じ日で下へ運ぶときは、取り除いたぶん位置が1つ前に詰まる
            at = sameDay && toItem > from ? toItem - 1 : toItem
        } else {
            at = sameDay ? count - 1 : count
        }
        if sameDay && at == from { return nil }
        return move(days, from: (day, from), toDay: toDay, at: at)
    }

    // MARK: - どの頁からも「旅行プランに入れる」（2026-11-10・札 #521）

    /// 入れる。`day` が nil なら新しい日を足してそこへ。**いっぱいの日・60日を越える日は断る**（nil）
    static func adding(_ item: TripItem, to days: [TripDay], day: Int?) -> [TripDay]? {
        var out = days
        if let day {
            guard out.indices.contains(day), out[day].items.count < TripPlanService.itemsPerDayMax else { return nil }
            out[day].items.append(item)
        } else {
            guard out.count < TripPlanService.daysMax else { return nil }
            out.append(TripDay(items: [item]))
        }
        return out
    }

    /// もう入っている日（いちばん前の日）。無ければ nil
    static func dayContaining(_ item: TripItem, in days: [TripDay]) -> Int? {
        let key = SavedSpotsTrip.itemKey(item)
        return days.firstIndex { $0.items.contains { SavedSpotsTrip.itemKey($0) == key } }
    }

    /// 先に選んで開くプラン。**出発が近いプラン**（今日以降に出発するもののうち最も早い）→ 旅の最中 →
    /// 日付の無いプラン → 一覧の先頭。帰着済みは最後
    static func defaultPlan(_ plans: [TripPlan], today: String) -> TripPlan? {
        func rank(_ p: TripPlan) -> (Int, String) {
            let s = p.startDate ?? "", e = p.endDate ?? p.startDate ?? ""
            if !s.isEmpty, s >= today { return (0, s) }
            if !s.isEmpty, !e.isEmpty, s <= today, e >= today { return (1, s) }
            if s.isEmpty && e.isEmpty { return (2, "") }
            return (3, "")
        }
        return plans.enumerated().min { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            return ra != rb ? ra < rb : a.offset < b.offset
        }?.element
    }

    /// 先に選ぶ日。**入れる場所にいちばん近い場所がある日**（直線の距離）。座標が分からなければ最後の日。
    /// いっぱいの日は選ばない。日が無ければ nil（新しい日に入れる）
    static func suggestedDay(_ days: [TripDay], coords: Photo.Coords?,
                             coordsOf: (TripItem) -> Photo.Coords?) -> Int? {
        let open = days.indices.filter { days[$0].items.count < TripPlanService.itemsPerDayMax }
        guard !open.isEmpty else { return nil }
        guard let coords else { return open.last }
        var best: (day: Int, km: Double)?
        for d in open {
            for item in days[d].items {
                guard let c = coordsOf(item) else { continue }
                let km = TravelDistance.kilometers(from: coords, to: c)
                if best == nil || km < best!.km { best = (d, km) }
            }
        }
        return best?.day ?? open.last
    }

    /// 「この日程から外す」（「…」の中・2026-11-11）。**押した時点の日程で同じ項目を探し直す**（`locate`）。
    /// 見つからなければ nil（何もしない・呼ぶ側が知らせる）
    static func removing(_ days: [TripDay], day: Int, item: Int, original: TripItem) -> [TripDay]? {
        guard let at = locate(days, day: day, item: item, original: original) else { return nil }
        var out = days
        out[day].items.remove(at: at)
        return out
    }

    /// 移せる先の日（自分の日を除き、いっぱいでない日）。メニューに並べる
    static func movableDays(_ days: [TripDay], from day: Int) -> [Int] {
        days.indices.filter { $0 != day && days[$0].items.count < TripPlanService.itemsPerDayMax }
    }

    /// ひとことを付け替える。**前後の空白を落とし、空なら外す**。長さはサーバーと同じく
    /// UTF-16 の単位で `TripPlanService.noteMax` まで（字の途中では切らない・`PostLimits.clamp`）
    static func setNote(_ days: [TripDay], day: Int, item: Int, note raw: String) -> [TripDay]? {
        guard days.indices.contains(day), days[day].items.indices.contains(item) else { return nil }
        var out = days
        out[day].items[item] = out[day].items[item].withNote(noteToSend(raw))
        return out
    }

    /// ひとことを書き始めたときの項目が、**いま**どこにあるか（2026-09-30）。
    ///
    /// 書く欄を開いている間に日程が差し替わる（前に送った保存の応答が届き、サーバーの
    /// 姿に合わせ直す）ことがある。位置だけで書くと、同じ位置にある**別の項目**に書いて
    /// しまう。まず同じ位置が同じ項目かを見て、違えば同じ日の中で同じ項目を探す。
    /// 見つからなければ `nil`（書かない・呼ぶ側が知らせる）
    static func locate(_ days: [TripDay], day: Int, item: Int, original: TripItem) -> Int? {
        guard days.indices.contains(day) else { return nil }
        let items = days[day].items
        if items.indices.contains(item), items[item] == original { return item }
        // 同じ項目が同じ日に2つあるときは、**開いた位置にいちばん近い方**（先頭の方ではない）
        return items.indices
            .filter { items[$0] == original }
            .min { abs($0 - item) < abs($1 - item) }
    }

    /// 送るひとこと（空なら `nil`）
    static func noteToSend(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return PostLimits.clamp(trimmed, limit: TripPlanService.noteMax)
    }
}

extension TripItem {
    /// 添えたひとこと（無ければ `nil`）
    var note: String? {
        switch self {
        case .spot(_, let note), .location(_, let note):
            return note
        }
    }

    /// ひとことだけ差し替えた同じ項目
    func withNote(_ note: String?) -> TripItem {
        switch self {
        case .spot(let spotId, _): return .spot(spotId: spotId, note: note)
        case .location(let slug, _): return .location(slug: slug, note: note)
        }
    }
}
