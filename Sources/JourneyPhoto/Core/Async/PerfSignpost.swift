import Foundation
#if canImport(os)
import os
#endif

/// 重さを測るための印（`OSSignposter`・2026-10-31 判断・札 #429 アプリ 1）。
///
/// **見た目も動きも変えない。** Instruments（Points of Interest・os_signpost）で、どこに時間を使っているかを
/// 区間で見るためだけに置く。印を付けるのは次の所:
///
/// - `launch`: アプリの `init` から、最初の画面（`RootView`）が出るまで
/// - `homeLoad`: ホームの一覧の読み込み（`GalleryViewModel.load`）の始めから終わりまで
/// - `spotIndexDecode`: 撮影スポットの索引（`spot-feed/index.json`・約 1.1MB・2,853件 2026-10-31）を解析する間
///
/// - `launchSync` ほか: 起動後の `.task(id: auth.state)` の同期の区間（`launchSync` は保存・いいねの同期の終わりまで。ブロック・行きたい場所は `LaunchDeferral` の待ちの後ろで含めない・2026-11-07。2026-11-04・札 #435 / #429。**包むだけで動作は変えない**）
///
/// 名前（`subsystem`・`category`・区間の名前）は UI テストの `XCTOSSignpostMetric` と Instruments で引くので、
/// 変えるときは `PerformanceTests` も合わせる。Linux の模型（`os` が無い）では何もしない
enum PerfSignpost {

    static let subsystem = "com.journeyphoto.JourneyPhoto"
    static let category = "Performance"

    enum Name: String, CaseIterable, Sendable {
        case launch = "Launch"
        case homeLoad = "HomeLoad"
        case homeSnapshotFetch = "HomeSnapshotFetch"
        case homeSnapshotProcess = "HomeSnapshotProcess"
        case homeFirstPage = "HomeFirstPage"
        case spotIndexDecode = "SpotIndexDecode"
        /// 起動後の `.task(id: auth.state)`（`JourneyPhotoApp`）の頭から `syncWishlist` の前まで（待ちを含む）
        case launchSync = "LaunchSync"
        /// その中の、待たない（同期の）部分: 6つの Store の `use` から `seenStories.use` まで（メインスレッドを占める時間）
        case launchSyncStores = "LaunchSyncStores"
        /// その中の `UploadDraftStore().sweepOrphans()`（`UserDefaults` を丸ごと読んで各キーを解く）
        case launchSyncSweepOrphans = "LaunchSyncSweepOrphans"
        /// その中の `DraftLibrary.prepare`
        case launchSyncDraftPrepare = "LaunchSyncDraftPrepare"
    }

    /// 始めた区間（終えるときに渡す）
    struct Interval: @unchecked Sendable {
        let name: Name
        #if canImport(os)
        fileprivate let state: OSSignpostIntervalState
        #endif
    }

    #if canImport(os)
    nonisolated(unsafe) private static let signposter = OSSignposter(subsystem: subsystem, category: category)
    #endif

    /// 区間を始める。`OSSignposter` は名前に `StaticString` しか取らないので、名前ごとに書き分ける
    static func begin(_ name: Name) -> Interval {
        #if canImport(os)
        let id = signposter.makeSignpostID()
        let state: OSSignpostIntervalState
        switch name {
        case .launch: state = signposter.beginInterval("Launch", id: id)
        case .homeLoad: state = signposter.beginInterval("HomeLoad", id: id)
        case .homeSnapshotFetch: state = signposter.beginInterval("HomeSnapshotFetch", id: id)
        case .homeSnapshotProcess: state = signposter.beginInterval("HomeSnapshotProcess", id: id)
        case .homeFirstPage: state = signposter.beginInterval("HomeFirstPage", id: id)
        case .spotIndexDecode: state = signposter.beginInterval("SpotIndexDecode", id: id)
        case .launchSync: state = signposter.beginInterval("LaunchSync", id: id)
        case .launchSyncStores: state = signposter.beginInterval("LaunchSyncStores", id: id)
        case .launchSyncSweepOrphans: state = signposter.beginInterval("LaunchSyncSweepOrphans", id: id)
        case .launchSyncDraftPrepare: state = signposter.beginInterval("LaunchSyncDraftPrepare", id: id)
        }
        return Interval(name: name, state: state)
        #else
        return Interval(name: name)
        #endif
    }

    static func end(_ interval: Interval) {
        #if canImport(os)
        switch interval.name {
        case .launch: signposter.endInterval("Launch", interval.state)
        case .homeLoad: signposter.endInterval("HomeLoad", interval.state)
        case .homeSnapshotFetch: signposter.endInterval("HomeSnapshotFetch", interval.state)
        case .homeSnapshotProcess: signposter.endInterval("HomeSnapshotProcess", interval.state)
        case .homeFirstPage: signposter.endInterval("HomeFirstPage", interval.state)
        case .spotIndexDecode: signposter.endInterval("SpotIndexDecode", interval.state)
        case .launchSync: signposter.endInterval("LaunchSync", interval.state)
        case .launchSyncStores: signposter.endInterval("LaunchSyncStores", interval.state)
        case .launchSyncSweepOrphans: signposter.endInterval("LaunchSyncSweepOrphans", interval.state)
        case .launchSyncDraftPrepare: signposter.endInterval("LaunchSyncDraftPrepare", interval.state)
        }
        #endif
    }

    /// 同期の処理をまるごと1区間で包む
    static func measure<T>(_ name: Name, _ body: () throws -> T) rethrows -> T {
        let interval = begin(name)
        defer { end(interval) }
        return try body()
    }

    // MARK: - 起動の区間（`init` で始め、最初の画面で1回だけ終える）

    nonisolated(unsafe) private static var launchInterval: Interval?
    private static let launchLock = NSLock()

    static func beginLaunch() {
        launchLock.lock()
        defer { launchLock.unlock() }
        guard launchInterval == nil else { return }
        launchInterval = begin(.launch)
    }

    /// 最初の画面が出たとき。**2回目からは何もしない**（画面の出し直しで区間を重ねない）
    static func endLaunch() {
        launchLock.lock()
        let interval = launchInterval
        launchInterval = nil
        launchLock.unlock()
        if let interval { end(interval) }
    }
}
