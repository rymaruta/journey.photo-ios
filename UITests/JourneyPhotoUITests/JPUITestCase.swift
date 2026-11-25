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
///
/// 2026-11-25 判断（Swift 6）: **UI テストはメインアクタの上で書く。** Xcode 27 の XCTest は `XCUIApplication`・
/// `XCUIElement` をメインアクタに置いた。XCTest は同期の試験をメインスレッドで走らせるので、試験のクラスを
/// `@MainActor` にしても動きは変わらない。この基に付ければ、子の試験のクラスはみな同じになる。
/// XCTestCase から受け継いだ口（`setUp`・`invokeTest`・`record`）は、元の宣言のとおりアクタに属さない
@MainActor
class JPUITestCase: XCTestCase {

    /// いま走っている試験（`XCUIApplication.jp()` が後始末を付ける先）
    nonisolated(unsafe) static weak var running: JPUITestCase?

    nonisolated override func invokeTest() {
        JPUITestCase.running = self
        defer { if JPUITestCase.running === self { JPUITestCase.running = nil } }
        super.invokeTest()
    }

    /// `jp()` が作ったアプリを、この試験の終わりに閉じる
    func closeAtEnd(_ app: XCUIApplication) {
        addTeardownBlock { JPAppClose.close(app) }
    }

    nonisolated override func record(_ issue: XCTIssue) {
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

    /// 試験の終わりに閉じる。もう止まっていれば何もしない（試験の本文・後始末の塊と同じくメインアクタの上で呼ぶ・2026-11-25 Swift 6）
    @MainActor
    static func close(_ app: XCUIApplication) {
        switch app.state {
        case .notRunning, .unknown: return
        default: break
        }
        // 閉じる前に pid を覚える（閉じたあとは 0 になる）
        let pid = processID(of: app)
        let started = Date()
        app.terminate()
        let stopped = app.wait(for: .notRunning, timeout: goneTimeout)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        // 2026-11-21 判断（run 1700・札 #681）: `.notRunning` になっても、本当のプロセスはまだ消えていないことがある
        // （グループの会話の画面の後のアプリは 7 秒で `.notRunning`、見張りでは 9 秒で消えた）。その直後に次の試験が
        // 起動すると、XCTest が新しいアプリを掴めず「does not have a process ID」で 200 秒止まった。
        // pid が分かれば、それが消えるまで待ってから次へ進む。分からなければ今の形（`.notRunning` まで）のまま
        guard let pid else {
            print("measured [terminate] 試験の終わりに閉じた \(ms)ms stopped=\(stopped) pid=不明")
            return
        }
        let gone = waitGone(pid: pid, timeout: goneTimeout)
        let total = Int(Date().timeIntervalSince(started) * 1000)
        print("measured [terminate] 試験の終わりに閉じた \(ms)ms stopped=\(stopped) pid=\(pid) 消えるまで \(total)ms gone=\(gone)")
    }

    /// アプリの pid（XCUIApplication の公にしていない値 `processID`）。持っていなければ nil（KVC で落とさないよう先に確かめる）
    @MainActor
    static func processID(of app: XCUIApplication) -> pid_t? {
        guard app.responds(to: NSSelectorFromString("processID")),
              let value = app.value(forKey: "processID") as? NSNumber else { return nil }
        let pid = value.int32Value
        return pid > 0 ? pid : nil
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
