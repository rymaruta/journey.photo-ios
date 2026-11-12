import Foundation

/// みんなの「行きたい」の**送る前の控え**と、**端末ごとのでたらめな ID**（2026-11-11・`SpotWants`）。
///
/// - 端末の ID は初めて送るときに作る（名前・メール・利用者の ID とつながらない）。ログインしても変えない
///   ——未ログインで払ってからログインした人を2回数えない（サーバーは端末ごと・撮影スポットごとに月1回）
/// - 控えは撮影スポットの鍵（`SPOT-<slug>`）だけ。5件たまったら送る・払う画面を閉じたら送る（`SpotWantSender`）。
///   ひとつ戻した札は、まだ送っていなければ外す
struct SpotWantQueue {

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let deviceKey = "journey-photo-want-device"
    private static let queueKey = "journey-photo-want-queue"
    static let limit = 40

    /// 端末の ID（無ければ作る）。英数字 32 字（サーバーは 16〜64 字の英数字・`-`・`_` を受ける）
    var deviceId: String {
        if let have = defaults.string(forKey: Self.deviceKey), Self.isDeviceId(have) { return have }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(id, forKey: Self.deviceKey)
        return id
    }

    static func isDeviceId(_ v: String) -> Bool {
        (16...64).contains(v.count) && v.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    var queued: [String] { defaults.stringArray(forKey: Self.queueKey) ?? [] }

    /// 足す。足したあとの件数を返す
    @discardableResult
    func add(slug: String) -> Int {
        let key = SavedSpotKey.official(slug)
        var list = queued
        if !list.contains(key) { list.append(key) }
        list = Array(list.suffix(Self.limit))
        defaults.set(list, forKey: Self.queueKey)
        return list.count
    }

    func remove(slug: String) {
        let key = SavedSpotKey.official(slug)
        defaults.set(queued.filter { $0 != key }, forKey: Self.queueKey)
    }

    /// 送れた鍵を外す
    func removeSent(_ keys: [String]) {
        let sent = Set(keys)
        defaults.set(queued.filter { !sent.contains($0) }, forKey: Self.queueKey)
    }
}
