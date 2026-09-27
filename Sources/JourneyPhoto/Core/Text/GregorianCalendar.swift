import Foundation

extension Calendar {

    /// **端末の暦に関わらず西暦で数える**暦。タイムゾーンはこの暦のものを引き継ぐ
    /// （日付の区切りは見ている人の土地のまま）。
    ///
    /// `Calendar.current` は端末の設定で和暦・タイ仏暦・イスラム暦などになる。
    /// 「何日目」を紀元から数えると起点が暦ごとに違い（今日のテーマが人によって割れる）、
    /// 月はイスラム暦・ヘブライ暦だと季節と合わない（バグ探し 2026-09-27 #23）
    var gregorianKeepingZone: Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        return gregorian
    }
}
