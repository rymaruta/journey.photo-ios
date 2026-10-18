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
/// （1枚ごとに一覧を取り直さない）。
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

extension Notification.Name {
    /// 期限の切れた署名つき画像が割れた（一覧を取り直す合図）。`SignedImageExpiry` が流す
    static let signedImagesExpired = Notification.Name("JourneyPhoto.signedImagesExpired")
}

/// 割れた画像を受け取り、取り直すと決めたら `signedImagesExpired` を流す（アプリに1つ）。
///
/// 画面ごとに取り直しの口を配って回らない——`RemoteImage` が1か所で報告し、
/// 署名つき URL を出す一覧（限定公開の取り口・マイページ）がこの合図で読み直す。
///
/// **どの actor からでも呼べる**（`AsyncImage` の `onAppear` からも、画像を読む非同期の関数からも）。
/// 覚えている時刻は鍵で守る。
enum SignedImageExpiry {
    private static let lock = NSLock()
    private static var gate = SignedImageRefetchGate()

    static func report(_ failedURL: URL?, now: Date = Date(), center: NotificationCenter = .default) {
        lock.lock()
        let refetch = gate.shouldRefetch(after: failedURL, now: now)
        lock.unlock()
        guard refetch else { return }
        center.post(name: .signedImagesExpired, object: nil)
    }

    /// 試験で間隔の覚えを消す
    static func resetForTesting() {
        lock.lock()
        gate = SignedImageRefetchGate()
        lock.unlock()
    }

    /// 取り直しの合図を、画面の `.task` で `for await` できる形で流す
    /// （画面が消えれば `.task` が取り消され、受け口も外れる）
    static func signals(center: NotificationCenter = .default) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let token = ObserverToken(center.addObserver(forName: .signedImagesExpired, object: nil, queue: nil) { _ in
                continuation.yield()
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
