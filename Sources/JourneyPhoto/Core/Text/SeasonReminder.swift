import Foundation

/// **見頃のお知らせ**（行きたい場所の季節が来たら知らせる・端末の中だけ）。
///
/// owner・2026-09-30 の「毎日開く理由」案③。サーバーは使わない——端末の中で1件だけ予約する
/// ローカル通知（`SeasonReminderScheduler`）。
///
/// ## 決まりごと
///
///  - 予約するのは**次の季節の始まり**（3月・6月・9月・12月の1日）の朝9時（端末の時刻帯）に**1件だけ**。
///    季節ごとに1回＝「多くても週に1回」の約束の内側（案③）
///  - 知らせるのは、「行きたい」に入れた**公開済みのスポットのうち、その季節の案内を持つもの**があるときだけ。
///    無ければ予約しない（空の知らせを送らない）
///  - 季節の区切りは台帳と同じ（`SpotBodyText.season(ofMonth:)`）。**「見頃」とは言わない**
///    （台帳の季節の案内は時期を確かめた文ではない・`HomeTopCard` と同じ判断）
///  - 数は「行きたい場所の何か所」だけ（自分の数）。人数・順位は出さない
enum SeasonReminder {

    struct Plan: Equatable {
        /// 予約する時刻（端末の暦・`year` `month` `day` `hour`）
        let fireAt: DateComponents
        /// "spring"〜"winter"
        let season: String
        let title: String
        let body: String
    }

    /// 通知の識別子。**1つだけ**（入れ替えるたびに前の予約を消す）
    static let identifier = "journey-photo.season-reminder"
    /// 通知の中身の印（押したときにお知らせ画面へ飛ばさない）
    static let kind = "seasonReminder"
    /// 何時に鳴らすか（端末の時刻帯）
    static let hour = 9

    /// `now` のあとの最初の季節の始まり（その季節の最初の月の1日）
    static func nextSeasonStart(after now: Date, calendar: Calendar) -> (year: Int, month: Int) {
        let c = calendar.dateComponents([.year, .month], from: now)
        let year = c.year ?? 2000
        let month = c.month ?? 1
        // 季節の最初の月: 3・6・9・12
        for start in [3, 6, 9, 12] where start > month {
            return (year, start)
        }
        return (year + 1, 3)
    }

    /// 次の予約。知らせるものが無ければ nil
    static func plan(now: Date, spots: [OfficialSpot], wishlist: Set<String>, calendar: Calendar) -> Plan? {
        let next = nextSeasonStart(after: now, calendar: calendar)
        let season = SpotBodyText.season(ofMonth: next.month)
        let names = spots
            .filter { !$0.isDraft && wishlist.contains(SavedSpotKey.official($0.slug)) }
            .filter { spot in spot.seasons.contains { $0.season == season } }
            .sorted { $0.spotId < $1.spotId }
            .map(\.name)
        guard let first = names.first else { return nil }
        let label = TripLight.seasonLabel(season)
        let body = names.count == 1
            ? L("行きたい場所の「\(first)」に\(label)の撮影ガイドがあります。",
                "\(first) on your want-to-go list has a \(label.lowercased()) guide.")
            : L("行きたい場所の「\(first)」ほか\(names.count - 1)か所に\(label)の撮影ガイドがあります。",
                "\(first) and \(names.count - 1) more on your want-to-go list have \(label.lowercased()) guides.")
        var fireAt = DateComponents()
        fireAt.year = next.year
        fireAt.month = next.month
        fireAt.day = 1
        fireAt.hour = hour
        return Plan(fireAt: fireAt, season: season,
                    title: L("\(label)の撮影スポット", "\(label) photo spots"), body: body)
    }
}
