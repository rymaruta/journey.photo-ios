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

    /// 日を消す。**確かめている間に日程が変わっていたら何もしない**（`nil`）——
    /// 添字だけで消すと、ほかの日を消したあとの確認で別の日が消える
    static func removeDay(_ days: [TripDay], at index: Int, expected: TripDay) -> [TripDay]? {
        guard days.indices.contains(index), days[index] == expected else { return nil }
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
