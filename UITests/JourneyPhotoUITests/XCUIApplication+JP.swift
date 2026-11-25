import XCTest

/// UI テストで起動するアプリ（2026-11-19・#647）。**`XCUIApplication()` を直に作らず、`XCUIApplication.jp()` を使う。**
///
/// 🔴 **ログを標準エラーに写さない**（`OS_ACTIVITY_DT_MODE=NO`）。iOS 27.2 のシミュレーターでは、XCTest が
/// アプリの中で画面を読むたびに大量の記録を書く（run 1594 で、DM の試験の途中までに 105331 行・13265533 バイト。
/// ほとんどが `Got attributes…` `Fetching AX attributes…`）。これが標準エラーへ写され、読む人のいない書き出しが
/// 詰まると、書いたスレッドが止まる。run 1592 では、画面の問い合わせを処理するアプリの中のスレッドが
/// `_os_log_impl_mirror_to_stderr` → `writev` → `spec_write` → `lck_mtx_sleep` で止まり、同じ確かめが1回 31秒かかって
/// 3回とも返らず、DM の試験が 5分の上限を超えた（アプリの主スレッドは待っているだけ）。
/// 写しを止めた run 1596 では、同じ確かめが約 1.5秒で返り、DM の2本とも通った
extension XCUIApplication {
    static func jp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OS_ACTIVITY_DT_MODE"] = "NO"
        // システムの通知の窓口に触らせない（`PendingNotificationRemoval.disabled`）。iOS 27.2 のシミュレーターで
        // 窓口の最初の呼び出しが 44〜120秒戻らず、DM の試験のあとでアプリを終わらせる操作が 71〜216秒戻らない回があった
        // （run 1594、1597）。UI テストは通知の許可を出さないので、確かめる画面は変わらない
        app.launchArguments += ["-JPNoSystemNotifications", "YES"]
        // 効果音を鳴らさない（`SoundEffects.muteArgument`・カプセルが開く音など・2026-11-25）。試験の間に Mac のスピーカーから鳴らさない
        app.launchArguments += ["-JPNoSounds", "YES"]
        // 自分の試験で起動したアプリは自分の試験の終わりに閉じる（次の試験の launch に閉じる仕事を残さない・札 #681）
        JPUITestCase.running?.closeAtEnd(app)
        return app
    }
}
