import Foundation
import SwiftUI
import Photos
import CoreLocation

/// 端末の写真の一冊のために、写真ライブラリの**撮影日時・位置・識別子だけ**を読む
/// （決まりは `DeviceTrips`・2026-10-16）。
///
/// **画像は読まない。** `PHAsset` の持つ値を写すだけ。読むのは低い優先度の後ろの仕事で、
/// `DeviceTrips.chunkSize` 枚ごとに少し休む。MainActor に置かない。
enum DeviceTripLibrary {

    /// 直近の画像（新しい順）。`before` があればそれ以前、`after` があればそれより後だけ。
    /// 絞り込みと並べ替えは PhotoKit に任せる（Linux の模型では作れないので外す。読みでも日時を見る）
    static func fetch(since: Date, before: Date? = nil, after: Date? = nil) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        #if canImport(Darwin)
        var format = "creationDate >= %@"
        var arguments: [Any] = [since as NSDate]
        if let before {
            format += " AND creationDate <= %@"
            arguments.append(before as NSDate)
        }
        if let after {
            format += " AND creationDate > %@"
            arguments.append(after as NSDate)
        }
        options.predicate = NSPredicate(format: format, argumentArray: arguments)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        #endif
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    /// 1枚を要約に写す。撮影日時の無い写真・`since` より古い写真は nil。
    /// **スクリーンショットは `isSkipped`**（旅に入れない・数を合わせるためだけに覚える）
    static func summary(of asset: PHAsset, since: Date) -> DeviceTripSummary? {
        guard let date = asset.creationDate, date >= since else { return nil }
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            return DeviceTripSummary(shot: LibraryShot(id: asset.localIdentifier, date: date, lat: nil, lng: nil),
                                     isSkipped: true)
        }
        let coordinate = asset.location?.coordinate
        return DeviceTripSummary(shot: LibraryShot(id: asset.localIdentifier, date: date,
                                                   lat: DeviceTrips.rounded(coordinate?.latitude),
                                                   lng: DeviceTrips.rounded(coordinate?.longitude)),
                                 isSkipped: false)
    }
}

// MARK: - 読み口（試験で差し替える）

/// 1枚の要約と、旅に入れない写真（スクリーンショット）か
struct DeviceTripSummary: Equatable {
    let shot: LibraryShot
    let isSkipped: Bool
}

/// 取り出した写真の並び（新しい順）。**要約を読むのは `summary(at:)` を呼んだ1枚だけ**
protocol DeviceTripAssets {
    var count: Int { get }
    func id(at position: Int) -> String
    func summary(at position: Int, since: Date) -> DeviceTripSummary?
}

/// 写真ライブラリの読み口
protocol DeviceTripSource: Sendable {
    func fetch(since: Date, before: Date?, after: Date?) -> any DeviceTripAssets
    func assets(ids: [String]) -> any DeviceTripAssets
}

/// 本物の読み口（PhotoKit）
struct PhotoKitTripSource: DeviceTripSource {
    func fetch(since: Date, before: Date?, after: Date?) -> any DeviceTripAssets {
        PhotoKitTripAssets(result: DeviceTripLibrary.fetch(since: since, before: before, after: after))
    }

    func assets(ids: [String]) -> any DeviceTripAssets {
        PhotoKitTripAssets(result: PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
    }
}

private struct PhotoKitTripAssets: DeviceTripAssets {
    let result: PHFetchResult<PHAsset>
    var count: Int { result.count }
    func id(at position: Int) -> String { result.object(at: position).localIdentifier }
    func summary(at position: Int, since: Date) -> DeviceTripSummary? {
        DeviceTripLibrary.summary(of: result.object(at: position), since: since)
    }
}

// MARK: - 端末への書き込み（1本の列）

/// 要約を書く・消すを**1本の列にまとめる**（確かめ役の指摘・2026-10-16）。
///
/// 書く人（読み・地名）と消す人（サインアウト・退会）が別の糸で走ると、消したあとに
/// 前の読みが書き戻す。書くときに読みの番号（`generation`）を渡し、**消した番号より古い書き込みは捨てる**
actor DeviceTripIndexWriter {
    private let url: URL?
    /// これより古い番号の書き込みは捨てる
    private var minGeneration = 0
    /// 書いた回数（試験で見る）
    private(set) var saveCount = 0

    init(url: URL?) {
        self.url = url
    }

    func load() -> DeviceTrips.Index? {
        DeviceTripIndexFile.load(from: url)
    }

    @discardableResult
    func save(_ index: DeviceTrips.Index, generation: Int) -> Bool {
        guard generation >= minGeneration else { return false }
        DeviceTripIndexFile.save(index, to: url)
        saveCount += 1
        return true
    }

    /// 消す。`generation` より古い番号の書き込みは、このあと届いても捨てる
    func remove(generation: Int) {
        minGeneration = max(minGeneration, generation)
        DeviceTripIndexFile.remove(at: url)
    }
}

// MARK: - 読み

/// 覚えていた要約から続きを読む（1回ぶん）。
///
/// 1. 覚えていた分ですぐ棚を出す（`publishCached` のときだけ・その起動で初めての読み）
/// 2. 何も無ければ新しい順に全部、途中なら続きから、読み終えていれば前回より新しい写真だけ
/// 3. 読み終えた後で数が合わなければ識別子で突き合わせる（`needsSweep`・10分に1回まで）
/// 4. **読み始めの要約と同じなら、書かず、旅も探し直さない**（確かめ役の指摘・5万枚で約5MB と
///    `LibraryTrips.find` を毎回回していた）
///
/// 取り消されたら書かずに返す（サインアウトで消したあと）
struct DeviceTripScan {

    /// 途中の結果を受ける（棚の描き直し）。渡すのは今の要約と、そこから探した旅
    typealias Progress = @Sendable (DeviceTrips.Index, [LibraryTrip]) async -> Void

    let source: any DeviceTripSource
    let save: @Sendable (DeviceTrips.Index) async -> Void
    let progress: Progress
    var pauseNanos: UInt64 = DeviceTrips.chunkPauseNanos

    /// - Parameter forceSweep: 10分の制限を外して突き合わせる（本人が「写真を追加で選ぶ」で選び足した直後）
    func run(start: DeviceTrips.Index?, now: Date, publishCached: Bool,
             forceSweep: Bool = false) async -> DeviceTrips.Index {
        let since = DeviceTrips.since(now: now)
        var index = start ?? DeviceTrips.Index()
        index.shots = index.shots.filter { $0.date >= since }
        index.skipped = index.skipped.filter { $0.date >= since }
        if publishCached, !index.shots.isEmpty {
            await progress(index, DeviceTrips.found(in: index.shots))
        }

        switch DeviceTrips.firstStep(start) {
        case .full:
            index = Self.restarted(keepingNamesOf: index)
            await readFirst(nil, into: &index, since: since)
        case .resume(let before):
            await readFirst(before, into: &index, since: since)
        case .newer(let after):
            readNewer(after: after, into: &index, since: since)
        }

        if index.complete, !Task.isCancelled,
           forceSweep || DeviceTrips.maySweep(lastSweep: index.lastSweep, now: now),
           DeviceTrips.needsSweep(index, libraryCount: source.fetch(since: since, before: nil, after: nil).count,
                                  since: since) {
            index.lastSweep = now
            await sweep(&index, since: since)
        }
        // 取り消し（サインアウトで消した）のあとは書かない
        guard !Task.isCancelled else { return index }
        // **変わっていなければ書かず、探し直さない**
        guard index != start else { return index }
        await save(index)
        await progress(index, DeviceTrips.found(in: index.shots))
        return index
    }

    /// 頭から読み直す要約（地名の控えは残す・同じ旅なら引き直さない）
    static func restarted(keepingNamesOf old: DeviceTrips.Index) -> DeviceTrips.Index {
        var fresh = DeviceTrips.Index()
        fresh.names = old.names
        fresh.zones = old.zones
        fresh.failedAt = old.failedAt
        fresh.lastSweep = old.lastSweep
        return fresh
    }

    /// 区切りの間に休む（画面の動きに譲る）
    private func pause() async {
        guard pauseNanos > 0 else { return }
        try? await Task.sleep(nanoseconds: pauseNanos)
    }

    /// 初めての読み（`before` があれば続きから）。新しい順に区切って読み、
    /// `publishEvery` 枚ごとに棚へ、`saveEvery` 枚ごとに端末へ。上限（`maxShots`）で打ち止め
    private func readFirst(_ before: Date?, into index: inout DeviceTrips.Index, since: Date) async {
        let assets = source.fetch(since: since, before: before, after: nil)
        var sincePublish = 0
        var sinceSave = 0
        var position = 0
        while position < assets.count {
            if Task.isCancelled { return }
            let end = min(position + DeviceTrips.chunkSize, assets.count)
            var read = 0
            for i in position..<end {
                guard let item = assets.summary(at: i, since: since) else { continue }
                if item.isSkipped { index.skipped.append(item.shot) } else { index.shots.append(item.shot) }
                read += 1
                index.frontier = min(index.frontier ?? item.shot.date, item.shot.date)
                index.newest = max(index.newest ?? item.shot.date, item.shot.date)
            }
            position = end
            sincePublish += read
            sinceSave += read
            if index.shots.count >= DeviceTrips.maxShots { break }
            if sinceSave >= DeviceTrips.saveEvery {
                Self.tidy(&index, since: since)
                if Task.isCancelled { return }
                await save(index)
                sinceSave = 0
            }
            if sincePublish >= DeviceTrips.publishEvery {
                Self.tidy(&index, since: since)
                await progress(index, DeviceTrips.found(in: index.shots))
                sincePublish = 0
            }
            await pause()
        }
        Self.tidy(&index, since: since)
        guard !Task.isCancelled else { return }
        index.complete = true
        index.frontier = nil
    }

    /// 前回より新しい写真だけ（ふつうは数枚・区切らない）
    private func readNewer(after: Date, into index: inout DeviceTrips.Index, since: Date) {
        let assets = source.fetch(since: since, before: nil, after: after)
        var shots: [LibraryShot] = []
        var skipped: [LibraryShot] = []
        for i in 0..<assets.count {
            guard let item = assets.summary(at: i, since: since), item.shot.date > after else { continue }
            if item.isSkipped { skipped.append(item.shot) } else { shots.append(item.shot) }
            index.newest = max(index.newest ?? item.shot.date, item.shot.date)
        }
        guard !shots.isEmpty || !skipped.isEmpty else { return }
        index.shots = DeviceTrips.merged(index.shots, adding: shots, since: since)
        index.skipped = DeviceTrips.merged(index.skipped, adding: skipped, since: since, limit: .max)
    }

    /// 識別子で突き合わせる（消した写真を落とし、一部の許可で選び足した古い写真を足す）。
    /// **覚えている写真は日時・位置を読み直さない**——読むのは識別子だけ（区切って）。
    /// 知らない写真が `maxSweepReads` より多ければ、頭から読み直す（区切って読む道）
    private func sweep(_ index: inout DeviceTrips.Index, since: Date) async {
        let assets = source.fetch(since: since, before: nil, after: nil)
        var ids: [String] = []
        ids.reserveCapacity(assets.count)
        var position = 0
        while position < assets.count {
            if Task.isCancelled { return }
            let end = min(position + DeviceTrips.chunkSize * 4, assets.count)
            for i in position..<end { ids.append(assets.id(at: i)) }
            position = end
            await pause()
        }
        let known = DeviceTrips.sweep(known: index.shots + index.skipped, current: ids)
        // ⚠️ 写真が `maxShots`（5万枚）を超える人は、上限より古い写真がいつも「知らない写真」に入るので、
        // 突き合わせのたびにここで頭から読み直す（10分に1回まで・`maySweep`）。5万枚を超える人は少なく、
        // 読むのは日時と位置だけなので注記にとどめる（2026-10-16 判断・確かめ役の指摘）
        if known.unknown.count > DeviceTrips.maxSweepReads {
            index = Self.restarted(keepingNamesOf: index)
            await readFirst(nil, into: &index, since: since)
            return
        }
        let skippedIds = Set(index.skipped.map(\.id))
        var shots = known.kept.filter { !skippedIds.contains($0.id) }
        var skipped = known.kept.filter { skippedIds.contains($0.id) }
        var start = 0
        while start < known.unknown.count {
            if Task.isCancelled { return }
            let end = min(start + DeviceTrips.chunkSize, known.unknown.count)
            let fetched = source.assets(ids: Array(known.unknown[start..<end]))
            for i in 0..<fetched.count {
                guard let item = fetched.summary(at: i, since: since) else { continue }
                if item.isSkipped { skipped.append(item.shot) } else { shots.append(item.shot) }
                index.newest = max(index.newest ?? item.shot.date, item.shot.date)
            }
            start = end
            await pause()
        }
        index.shots = DeviceTrips.merged([], adding: shots, since: since)
        index.skipped = DeviceTrips.merged([], adding: skipped, since: since, limit: .max)
    }

    /// 重なりを除き、新しい順に並べ、上限で切る
    private static func tidy(_ index: inout DeviceTrips.Index, since: Date) {
        index.shots = DeviceTrips.merged([], adding: index.shots, since: since)
        index.skipped = DeviceTrips.merged([], adding: index.skipped, since: since, limit: .max)
    }
}

// MARK: - 棚

/// 端末の写真の一冊の棚（マイページの「旅の記録」）。**読むのは1か所**——起動のときと、
/// 写真を許可したときと、ライブラリが変わったときに、後ろで続きを読む。
///
/// **重くしない（確かめ役の指摘・2026-10-16）:**
/// - 変化の知らせでは、前の読みの始まりから `DeviceTrips.minRunInterval`（60秒）は読まない
/// - **前面にいる間だけ**読み始める（裏で来た知らせは、前面に戻ったときに1回）
/// - 突き合わせは10分に1回まで（`DeviceTrips.maySweep`）
@MainActor
final class DeviceTripShelfStore: ObservableObject {

    static let shared = DeviceTripShelfStore()

    /// 説明の札を「今はしない」で閉じた
    static let introDismissedKey = "deviceTrips.introDismissed"

    typealias PlaceLookup = @Sendable (Photo.Coords) async -> (name: String?, timeZone: TimeZone?)

    @Published private(set) var status: PHAuthorizationStatus
    /// 探した旅（新しい順・投稿済みの日の絞りの前）。棚は `books(posted:isMine:)`
    @Published private(set) var trips: [LibraryTrip] = []
    /// 一冊の地名（鍵は旅の id）
    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var zones: [String: String] = [:]
    /// 読んでいる最中
    @Published private(set) var isScanning = false
    /// 一度でも読み終えた（「見つかりませんでした」を出してよい）
    @Published private(set) var hasCompleted = false
    @Published private(set) var isPickingMore = false
    @Published private(set) var introDismissed: Bool

    /// 読んだ写真の要約（「旅の写真から」の流れに渡す・読み直さない）
    private(set) var shots: [LibraryShot] = []
    private var index: DeviceTrips.Index?
    private var loadedFromDisk = false
    /// 一度でも読み始めた（`startIfNeeded`）
    private var didStart = false
    private var task: Task<Void, Never>?
    /// 何回目の読みか。**自分の番のときだけ**印を消し、結果を受ける（古い読みが新しい読みの印を消さない）
    private var runId = 0
    /// 読みを始めた回数（試験・読みが2本走らないか）
    private(set) var runsStarted = 0
    /// 端末への書き込みの番号。消したら上げる（古い書き込みを捨てる・`DeviceTripIndexWriter`）
    private var generation = 0
    private var rerunRequested = false
    private var lastRunStart: Date?
    /// 前面にいるか（`RootView` が知らせる）。裏にいる間は読み始めない
    private var isActive = true
    /// ログインしているか（`setSignedIn`）
    private(set) var isSignedIn: Bool
    /// 次の読みで突き合わせの10分の制限を外す（`addMorePhotos`）
    private var sweepRequested = false
    /// 読めない段で端末のファイルを消した（読めない間は1回だけ）
    private var clearedWhileUnreadable = false
    /// 読みの輪を抜けた回数（試験・古い読みが終わったかを見る）
    private(set) var loopsFinished = 0
    /// 裏にいる間に変化の知らせが来た
    private var pendingChange = false
    private var observer: DeviceTripChangeObserver?
    private var changeDebounce: Task<Void, Never>?
    private var removal: Task<Void, Never>?
    private let defaults: UserDefaults
    private let writer: DeviceTripIndexWriter
    private let source: any DeviceTripSource
    private let statusProvider: () -> PHAuthorizationStatus
    private let place: PlaceLookup
    private let pauseNanos: UInt64
    private let lookupPauseNanos: UInt64
    private let now: () -> Date
    /// 変化の知らせを受ける役を登録するか（試験では登録しない）
    private let observesLibrary: Bool

    init(defaults: UserDefaults = .standard,
         url: URL? = DeviceTripIndexFile.defaultURL(),
         source: any DeviceTripSource = PhotoKitTripSource(),
         status: @escaping () -> PHAuthorizationStatus = { PhotoLibrary.status },
         place: @escaping PlaceLookup = { await PhotoLibrary.place(near: $0) },
         pauseNanos: UInt64 = DeviceTrips.chunkPauseNanos,
         lookupPauseNanos: UInt64 = DeviceTrips.lookupPauseNanos,
         now: @escaping () -> Date = Date.init,
         observesLibrary: Bool = true,
         signedIn: Bool = false) {
        self.defaults = defaults
        self.writer = DeviceTripIndexWriter(url: url)
        self.source = source
        self.statusProvider = status
        self.place = place
        self.pauseNanos = pauseNanos
        self.lookupPauseNanos = lookupPauseNanos
        self.now = now
        self.observesLibrary = observesLibrary
        self.isSignedIn = signedIn
        self.status = status()
        introDismissed = defaults.bool(forKey: Self.introDismissedKey)
    }

    /// 棚に出す一冊（`DeviceTrips.books`）。**許可が無ければ出さない**（あとで許可を外した）
    func books(posted: [LibraryTrips.PostedShot], isMine: Bool) -> [LibraryTrip] {
        guard PhotoLibrary.canRead(status) else { return [] }
        return DeviceTrips.books(trips, posted: posted, zones: zones, isMine: isMine)
    }

    func dismissIntro() {
        introDismissed = true
        defaults.set(true, forKey: Self.introDismissedKey)
    }

    /// 許可を尋ねる（説明の札の主ボタン）。許されたらすぐ読み始める。
    /// 許可のダイアログが閉じると前面に戻った扱い（`setActive`）でもう1回読みが頼まれるが、
    /// 変わっていなければ書かず探し直さない（`DeviceTripScan.run`）ので注記にとどめる
    func requestAccess() async {
        _ = await PhotoLibrary.requestAccess()
        startIfAllowed()
    }

    /// 許可の段を読み直す。**許可が無くなっていたら、覚えた要約を消す**（設定アプリで外した。
    /// 読めない写真の位置の控えを残さない・棚が空白にならない）
    @discardableResult
    func refreshStatus() -> Bool {
        status = statusProvider()
        let readable = PhotoLibrary.canRead(status)
        if readable {
            clearedWhileUnreadable = false
        } else if didStart || index != nil || !trips.isEmpty {
            forget()
        } else if !clearedWhileUnreadable {
            // **メモリが空でも端末のファイルは消す**——設定で許可を外すと iOS がアプリを終わらせ、
            // 次の起動ではメモリが空のまま（読めない段のあいだ1回だけ）
            clearedWhileUnreadable = true
            removeStoredFile()
        }
        return readable
    }

    /// 許されていれば続きを読む（起動・許可した・選び足した）。**読んでいる最中なら、
    /// 終わったあとにもう一度だけ**（新しい写真を取りこぼさない）
    func startIfAllowed() {
        guard refreshStatus() else { return }
        didStart = true
        registerObserver()
        guard task == nil else {
            rerunRequested = true
            return
        }
        runId += 1
        runsStarted += 1
        let run = runId
        task = Task(priority: .background) { await runLoop(run) }
    }

    /// まだ一度も読み始めていなければ読む（棚が出たとき）。**許可の段は毎回読み直す**
    func startIfNeeded() {
        guard refreshStatus(), !didStart else { return }
        startIfAllowed()
    }

    /// ログインしているか（`RootView`・`AuthStore.settleSignedOut`）。**ログインしていない間は、
    /// 前面に戻ったとき・変化の知らせで読み始めない**（サインアウトで消した要約を作り直さない）
    func setSignedIn(_ signedIn: Bool) {
        isSignedIn = signedIn
    }

    /// 前面に来た・裏へ回った（`RootView` の `scenePhase`）。前面に来たら許可を見直し、
    /// 裏にいる間に変化の知らせが来ていれば1回だけ読む。**読み始めるのはログインしているときだけ**
    func setActive(_ active: Bool) {
        isActive = active
        guard active else { return }
        guard refreshStatus(), isSignedIn else { return }
        if !didStart {
            startIfAllowed()
        } else if pendingChange {
            pendingChange = false
            libraryChanged()
        }
    }

    /// 一部だけ許可した人が写真を選び足す（選び終えたら読み直す）
    func addMorePhotos() async {
        guard !isPickingMore else { return }
        isPickingMore = true
        let presented = await PhotoLibrary.presentLimitedPicker()
        isPickingMore = false
        // 本人が選び足した直後の読みは、10分の突き合わせの制限を外す
        if presented {
            sweepRequested = true
            startIfAllowed()
        }
    }

    /// ライブラリが変わった。**前の読みの始まりから60秒・少なくとも3秒待ってから**読む
    /// （iCloud の同期は知らせが続けて来る）。裏にいる間は読まず、前面に戻ったときに読む
    func libraryChanged() {
        guard isSignedIn else { return }
        guard isActive else {
            pendingChange = true
            return
        }
        changeDebounce?.cancel()
        let delay = DeviceTrips.runDelay(lastRunStart: lastRunStart, now: now())
        changeDebounce = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard isActive else {
                pendingChange = true
                return
            }
            guard isSignedIn else { return }
            startIfAllowed()
        }
    }

    /// 読み終えるまで待つ（試験）
    func waitUntilIdle() async {
        while let running = task {
            await running.value
        }
    }

    /// 書いた回数（試験）
    func saveCount() async -> Int {
        await writer.saveCount
    }

    /// 端末の控えを消す（サインアウト・退会。`AuthStore.settleSignedOut`・許可を外した）。
    /// 写真の位置の控えを次の人に残さない
    func forget() {
        task?.cancel()
        task = nil
        runId += 1
        changeDebounce?.cancel()
        if let observer { PHPhotoLibrary.shared().unregisterChangeObserver(observer) }
        observer = nil
        index = nil
        loadedFromDisk = true
        shots = []
        trips = []
        names = [:]
        zones = [:]
        hasCompleted = false
        isScanning = false
        didStart = false
        rerunRequested = false
        pendingChange = false
        lastRunStart = nil
        removeStoredFile()
    }

    /// 端末のファイルだけを消す（古い番号の書き込みも捨てる）
    private func removeStoredFile() {
        generation += 1
        let writer = writer
        let removing = generation
        removal = Task { await writer.remove(generation: removing) }
    }

    /// 消し終えるまで待つ（試験）
    func waitForRemoval() async {
        await removal?.value
    }

    private func registerObserver() {
        guard observesLibrary, observer == nil else { return }
        let made = DeviceTripChangeObserver {
            Task { @MainActor in DeviceTripShelfStore.shared.libraryChanged() }
        }
        PHPhotoLibrary.shared().register(made)
        observer = made
    }

    private func runLoop(_ run: Int) async {
        defer { loopsFinished += 1 }
        isScanning = true
        var publishCached = false
        repeat {
            rerunRequested = false
            lastRunStart = now()
            if !loadedFromDisk {
                // 書いた要約を読むのも後ろで（数MB・書き込みと同じ列）
                let loaded = await writer.load()
                // 読んでいる間に消された（サインアウト）・新しい読みが始まった——古い要約を戻さない
                guard run == runId else { return }
                index = loaded
                loadedFromDisk = true
                publishCached = true
            }
            let writer = writer
            let saving = generation
            // **`Task.detached` にしない**——取り消し（`forget`）が届かない。
            // MainActor の外の async の関数なので、呼ぶだけで画面の糸の外で走る（優先度は呼び手の低いまま）
            let scan = DeviceTripScan(
                source: source,
                save: { await writer.save($0, generation: saving) },
                progress: { [weak self] index, trips in await self?.apply(index, trips, run: run) },
                pauseNanos: pauseNanos)
            let forceSweep = sweepRequested
            sweepRequested = false
            let finished = await scan.run(start: index, now: now(), publishCached: publishCached,
                                          forceSweep: forceSweep)
            publishCached = false
            guard !Task.isCancelled, run == runId else { break }
            index = finished
            if finished.complete { hasCompleted = true }
            await resolveNames(run: run)
            // 裏へ回ったら続けて読まない（前面に戻ったときに読む）
            if rerunRequested, !isActive {
                rerunRequested = false
                pendingChange = true
            }
        } while rerunRequested && !Task.isCancelled && run == runId
        // **自分の番のときだけ**印を消す（消したあとに始まった新しい読みの印を消さない）
        guard run == runId else { return }
        isScanning = false
        task = nil
    }

    private func apply(_ index: DeviceTrips.Index, _ trips: [LibraryTrip], run: Int) {
        // 消したあと（サインアウト）・古い読みの結果は捨てる
        guard run == runId else { return }
        self.index = index
        shots = index.shots
        self.trips = trips
        names = index.names
        zones = index.zones
        if index.complete { hasCompleted = true }
    }

    /// 地名を**一冊につき1回**、1つずつ間を空けて引く（`DeviceTrips.toLookUp`）。
    /// 引けなくても一冊は出す（題は期間）
    private func resolveNames(run: Int) async {
        guard var current = index else { return }
        let targets = DeviceTrips.toLookUp(trips, index: current, now: now())
        guard !targets.isEmpty else { return }
        for (offset, trip) in targets.enumerated() {
            guard !Task.isCancelled, run == runId, let center = trip.center else { return }
            if offset > 0, lookupPauseNanos > 0 { try? await Task.sleep(nanoseconds: lookupPauseNanos) }
            let found = await place(center)
            guard run == runId else { return }
            if let name = found.name {
                current.names[trip.id] = name
                current.failedAt[trip.id] = nil
            } else {
                current.failedAt[trip.id] = now()
            }
            if let zone = found.timeZone { current.zones[trip.id] = zone.identifier }
            names = current.names
            zones = current.zones
        }
        guard !Task.isCancelled, run == runId else { return }
        index = current
        await writer.save(current, generation: generation)
    }
}

/// ライブラリの変化の知らせを受ける役（本物は主の糸ではない糸で呼ぶ）
final class DeviceTripChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
