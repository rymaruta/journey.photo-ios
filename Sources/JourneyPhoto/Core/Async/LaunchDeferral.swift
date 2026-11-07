import Foundation

/// 起動直後の「画面に今すぐ要らない同期」を、最初の画面が出たあとへ少し遅らせる（2026-11-07 判断）。
///
/// **なぜ**: 本番の Lambda は同時実行の上限が 10 で、起動の直後にホーム・未読通知・プロフィールの
/// 読み込みと、ログイン後の同期（端末登録・ブロック・行きたい場所・購入の送り直し）が重なると
/// 上限を超えてスロットル（503）になる。**画面を描くのに要るものは遅らせない**——遅らせるのは、
/// 画面に今すぐ出ない同期だけ（`JourneyPhotoApp` の `.task(id: auth.state)` の後半）。
///
/// - **起動して最初の1回だけ**待つ。ログイン・ログアウトで状態が変わった回は待たない
///   （ログインした直後の端末登録を遅らせない）。
/// - 待ち時間 `grace` は、最初の画面の読み込み（約 2〜3 本）が出払うのに足りる長さ。長くしすぎると
///   端末登録・ブロックの反映が遅れるので 1.5 秒に留める（ブロックした相手の写真は端末の控えで
///   すでに隠れているので、サーバーとの突き合わせが 1.5 秒遅れても見え方は変わらない）。
/// - 画面写真・UI テスト（`PreviewSession`）では待たない（絵の撮影の時間を延ばさない）。
final class LaunchDeferral: @unchecked Sendable {

    static let shared = LaunchDeferral()

    /// 起動の同期を遅らせる秒数
    static let grace: TimeInterval = 1.5

    private let lock = NSLock()
    private var consumed = false

    /// 試験が実際に待たずに済むよう差し替えられる
    private let pause: @Sendable (TimeInterval) async -> Void

    init(pause: @escaping @Sendable (TimeInterval) async -> Void = LaunchDeferral.sleep) {
        self.pause = pause
    }

    @Sendable private static func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    /// 最初の1回だけ `grace` 秒待つ。待ちを抜けたあとも続けてよいか（取り消されていなければ true）を返す。
    /// 2回目以降・`skip` のときは待たずに、取り消されていなければ true
    func waitOnce(skip: Bool = false, grace: TimeInterval = LaunchDeferral.grace) async -> Bool {
        let shouldWait = takeTurn(skip: skip)
        if shouldWait { await pause(grace) }
        return !Task.isCancelled
    }

    private func takeTurn(skip: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if consumed { return false }
        consumed = true
        return !skip
    }
}
