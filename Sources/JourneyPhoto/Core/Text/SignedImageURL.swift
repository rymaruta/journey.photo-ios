import Foundation

/// **署名つき画像 URL の期限を読む**（2026-10-18 判断・札 #294）。
///
/// 公開範囲を絞った写真（フォロワーのみ・親しい友達）の画像は、サーバーが CloudFront の
/// 署名つき URL（期限は10〜15分・photo-gallery `api-user/src/signedUrl.ts`）で返す。
/// `/private/*` が署名必須になると、**期限を過ぎた URL は 403** で割れる
/// ——一覧を開いたまま置いた・裏から戻った、で起きる。直す手は「一覧を取り直して
/// 新しい URL をもらう」しか無い。
///
/// `AsyncImage` の失敗からは HTTP の状態が読めないので、**「署名つきで期限を過ぎた
/// URL の失敗」を 403 とみなす**。期限内の失敗（圏外など）は取り直しても直らないので
/// 拾わない（取り直しが空回りし続けないように）。Web の `lib/utils/signedImage.ts` と同じ線。
enum SignedImageURL {

    /// 署名つき URL の期限。署名つきでなければ nil
    static func expiry(of url: URL) -> Date? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("Signature") != nil, value("Key-Pair-Id") != nil,
              let raw = value("Expires"), let seconds = TimeInterval(raw), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// 期限を過ぎた（または `skew` 秒のうちに過ぎる）署名つき URL か。
    /// `skew` は端末の時計のずれと、読み込みにかかる時間のぶん
    static func isExpired(_ url: URL, now: Date, skew: TimeInterval = 30) -> Bool {
        guard let expiry = expiry(of: url) else { return false }
        return expiry <= now.addingTimeInterval(skew)
    }
}

/// 期限切れで割れた画像を見て、**一覧を取り直すか**（画面を持たない計算）。
///
/// 格子では一度に何枚も割れるので、取り直しは `minInterval` に1回だけ
/// （1枚ごとに一覧を取り直さない）。**受ける画面ごとに1つ**持つ（`.task` の中の変数）。
struct SignedImageRefetchGate {
    var minInterval: TimeInterval = 15
    private(set) var lastRefetch: Date?

    init(minInterval: TimeInterval = 15) {
        self.minInterval = minInterval
    }

    /// 割れた画像の URL を受けて、取り直すなら true（そのとき時刻を覚える）
    mutating func shouldRefetch(after failedURL: URL?, now: Date) -> Bool {
        guard let failedURL, SignedImageURL.isExpired(failedURL, now: now) else { return false }
        if let lastRefetch, now.timeIntervalSince(lastRefetch) < minInterval { return false }
        lastRefetch = now
        return true
    }
}

extension Photo {
    /// この写真が画面に出しうる画像の URL（本体・派生）
    var imageURLStrings: [String] {
        [src, thumbSrc, src256, thumbAvif, thumbSm, thumbSmAvif, srcAvif].compactMap { $0 }.filter { !$0.isEmpty }
    }

    /// 割れた画像の URL が、この写真のものか
    func usesImageURL(_ url: URL) -> Bool {
        let target = url.absoluteString
        return imageURLStrings.contains(target)
    }
}

extension Array where Element == Photo {
    /// 割れた画像の URL を持つ写真が、この一覧に在るか（**関係ない画面は読み直さない**ための判定）
    func containsImageURL(_ url: URL) -> Bool {
        contains { $0.usesImageURL(url) }
    }
}

extension Notification.Name {
    /// 期限の切れた署名つき画像が割れた（`userInfo["url"]` にその URL）。`SignedImageExpiry` が流す
    static let signedImagesExpired = Notification.Name("JourneyPhoto.signedImagesExpired")
}

/// 割れた画像を受け取り、**期限の切れた署名つき URL なら、その URL を載せて合図を流す**（アプリに1つ）。
///
/// 画面ごとに取り直しの口を配って回らない——`RemoteImage` が1か所で報告し、
/// 署名つき URL を出す一覧（限定公開を重ねるホーム・探す・マイページ）が受ける。
/// **受ける側が「自分の一覧の写真か」を確かめ**、自分の `SignedImageRefetchGate` で間を置く
/// （マイページの1枚が割れても、ホームと探すは読み直さない・2026-10-18 のレビュー）。
///
/// どの actor からでも呼べる（`AsyncImage` の `onAppear` からも、画像を読む非同期の関数からも）。
enum SignedImageExpiry {
    static let urlKey = "url"

    static func report(_ failedURL: URL?, now: Date = Date(), center: NotificationCenter = .default) {
        guard let failedURL, SignedImageURL.isExpired(failedURL, now: now) else { return }
        center.post(name: .signedImagesExpired, object: nil, userInfo: [urlKey: failedURL])
    }

    /// 割れた URL を、画面の `.task` で `for await` できる形で流す
    /// （画面が消えれば `.task` が取り消され、受け口も外れる）
    static func signals(center: NotificationCenter = .default) -> AsyncStream<URL> {
        AsyncStream { continuation in
            let token = ObserverToken(center.addObserver(forName: .signedImagesExpired, object: nil, queue: nil) { note in
                if let url = note.userInfo?[urlKey] as? URL { continuation.yield(url) }
            })
            continuation.onTermination = { _ in center.removeObserver(token.value) }
        }
    }
}

/// 受け口の札を、取り消しの手続き（`@Sendable`）へ持ち出すための箱。触るのは外すときの1回だけ
private final class ObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol
    init(_ value: NSObjectProtocol) { self.value = value }
}
