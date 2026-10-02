import Foundation

/// ホームの上段の札（`HomeTopCard`）から**一度開いた**旅の一冊。
///
/// 「一冊ができました」の札は**開いたら下げる**（板 55 の②）。何度も同じ知らせを
/// 出さない——開いた一冊は、いつでもマイページの「旅の記録」から開ける。
///
/// 入れるのは `HomeTopCard.bookKey`: 日付で束ねた一冊は**旅の始まりの日**（旅の id は写真を
/// 足し引きするだけで変わるので使わない）、旅の写真の流れの束の一冊は**束の id**（`group#…`）。
///
/// 鍵は人ごとに分ける（同じ端末で人が替わったとき、前の人の印で札を下げない）。
/// 未ログインでは使わない（自分の写真が無いので一冊の札も出ない）。
/// **増え続けないよう、新しい順に `limit` 件だけ残す**
struct OpenedTripBooks {

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let key = "journey-photo-opened-trip-books"
    static let limit = 50

    private func key(for userId: String) -> String { "\(Self.key):\(userId)" }

    func ids(for userId: String?) -> Set<String> {
        guard let userId, !userId.isEmpty else { return [] }
        return Set(defaults.stringArray(forKey: key(for: userId)) ?? [])
    }

    func mark(_ bookKey: String, for userId: String?) {
        guard let userId, !userId.isEmpty, !bookKey.isEmpty else { return }
        var list = (defaults.stringArray(forKey: key(for: userId)) ?? []).filter { $0 != bookKey }
        list.append(bookKey)
        defaults.set(Array(list.suffix(Self.limit)), forKey: key(for: userId))
    }

    /// 退会した人の印を消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: key(for: userId))
    }
}
