import XCTest
import Darwin

/// UI テストの共通の基（2026-11-21・札 #681「UI テストが前のアプリの終わりに気づかず Failed to terminate で落ちる」）。
///
/// run 1696 の数字: 前の試験のアプリ（pid 53045）は、閉じろと言われて 5 秒以内に消えていた（見張り `Tools/hang-sample.sh`）。
/// それでも次の試験の `app.launch()` が「前のアプリを閉じる」仕事で約 60 秒待ち、「Failed to terminate」で落とした。
/// XCTest が、前のアプリの終わりに気づいていない。2026-11-21 は run 1677・1681・1683・1696 で、落ちる試験は毎回ちがった。
///
/// 2026-11-21 判断:
/// - **自分の試験で起動したアプリは、自分の試験の終わりに閉じる。** `XCUIApplication.jp()` が作ったアプリを覚え、
///   試験の後始末（teardown block）で `terminate()` し、`wait(for: .notRunning, timeout: 15)` で止まったことを確かめる。
///   次の試験の `launch()` に、前のアプリを閉じる仕事を残さない
/// - **「閉じられない」で落ちたときは、本当に残っているかを見てから決める**（失敗を見込む印で隠さない）。
///   失敗の文の pid が本当に無いか（`kill(pid, 0)` が ESRCH）を最大 15 秒待って確かめ、無ければ失敗にしない
///   （`measured [terminate]` の行を残す）。残っていれば今までどおり失敗にする（本当に固まったアプリは見逃さない）。
///   run 1681 では、自分の試験の終わりの `app.terminate()` で同じ失敗が出た。この扱いはその回も覆う
/// - pid を調べられない（`kill` が ESRCH 以外で断る）ときは「残っている」と見て、今までどおり失敗にする（安全側）
class JPUITestCase: XCTestCase {

    /// いま走っている試験（`XCUIApplication.jp()` が後始末を付ける先）
    nonisolated(unsafe) static weak var running: JPUITestCase?

    override func invokeTest() {
        JPUITestCase.running = self
        defer { if JPUITestCase.running === self { JPUITestCase.running = nil } }
        super.invokeTest()
    }

    /// `jp()` が作ったアプリを、この試験の終わりに閉じる
    func closeAtEnd(_ app: XCUIApplication) {
        addTeardownBlock { JPAppClose.close(app) }
    }

    override func record(_ issue: XCTIssue) {
        if let pid = JPAppClose.staleTerminatePid(issue.compactDescription) {
            if JPAppClose.waitGone(pid: pid, timeout: JPAppClose.goneTimeout) {
                print("measured [terminate] pid=\(pid) XCTest は閉じられないと言ったが、アプリはもう無い。失敗にしない（札 #681）")
                return
            }
            print("measured [terminate] pid=\(pid) 閉じられず、まだ残っている。失敗にする")
        }
        super.record(issue)
    }
}

/// アプリを閉じる決まり（`JPUITestCase` の後始末と、失敗の扱い）
enum JPAppClose {

    /// 止まるのを待つ・消えたのを確かめる上限（秒）
    static let goneTimeout: TimeInterval = 15

    /// 試験の終わりに閉じる。もう止まっていれば何もしない（XCTestCase と同じく isolation を持たない。試験の本文と同じ呼び方）
    static func close(_ app: XCUIApplication) {
        switch app.state {
        case .notRunning, .unknown: return
        default: break
        }
        let started = Date()
        app.terminate()
        let stopped = app.wait(for: .notRunning, timeout: goneTimeout)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        print("measured [terminate] 試験の終わりに閉じた \(ms)ms stopped=\(stopped)")
    }

    /// 「Failed to terminate com.journeyphoto.…:<pid>」の pid（この形でなければ nil）
    static func staleTerminatePid(_ text: String) -> pid_t? {
        guard let r = text.range(of: "Failed to terminate com.journeyphoto.") else { return nil }
        let rest = text[r.upperBound...]
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let digits = rest[rest.index(after: colon)...].prefix { $0.isNumber }
        guard let pid = pid_t(digits), pid > 0 else { return nil }
        return pid
    }

    /// pid が無くなったか（`kill(pid, 0)` が ESRCH）。上限まで 0.25 秒ごとに見る
    static func waitGone(pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }
}
