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

    /// 途中の結果を受ける（棚の描き直し）。渡すのは今の要約と、そこから探した旅
    typealias Progress = @Sendable (DeviceTrips.Index, [LibraryTrip]) async -> Void

    /// 覚えていた要約（`start`）から続きを読み、読み終えた要約を返す。
    ///
    /// 1. 覚えていた分ですぐ棚を出す（読み直さない）
    /// 2. 何も無ければ新しい順に全部、途中なら続きから、読み終えていれば前回より新しい写真だけ
    /// 3. 読み終えた後で数が合わなければ識別子で突き合わせる（`DeviceTrips.needsSweep`）
    ///
    /// 取り消されたら、そこまでの分を書いて返す（次は続きから）
    static func run(start: DeviceTrips.Index?, now: Date, url: URL?, progress: Progress) async -> DeviceTrips.Index {
        let since = DeviceTrips.since(now: now)
        var index = start ?? DeviceTrips.Index()
        index.shots = index.shots.filter { $0.date >= since }
        index.skipped = index.skipped.filter { $0.date >= since }
        if !index.shots.isEmpty {
            await progress(index, DeviceTrips.found(in: index.shots))
        }

        switch DeviceTrips.firstStep(start) {
        case .full:
            // 地名の控えは残す（同じ旅なら引き直さない）
            let kept = index
            index = DeviceTrips.Index()
            index.names = kept.names
            index.zones = kept.zones
            index.failedAt = kept.failedAt
            await readFirst(nil, into: &index, since: since, url: url, progress: progress)
        case .resume(let before):
            await readFirst(before, into: &index, since: since, url: url, progress: progress)
        case .newer(let after):
            readNewer(after: after, into: &index, since: since)
        }

        if index.complete, !Task.isCancelled,
           DeviceTrips.needsSweep(index, libraryCount: fetch(since: since).count, since: since) {
            await sweep(&index, since: since)
        }
        // 取り消し（サインアウトで消した）のあとは書かない
        guard !Task.isCancelled else { return index }
        DeviceTripIndexFile.save(index, to: url)
        await progress(index, DeviceTrips.found(in: index.shots))
        return index
    }

    // MARK: - 取り出し

    /// 直近の画像（新しい順）。`before` があればそれ以前、`after` があればそれより後だけ。
    /// 絞り込みと並べ替えは PhotoKit に任せる（Linux の模型では作れないので外す。下の読みでも日時を見る）
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
    private static func summary(of asset: PHAsset, since: Date) -> (shot: LibraryShot, isSkipped: Bool)? {
        guard let date = asset.creationDate, date >= since else { return nil }
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            return (LibraryShot(id: asset.localIdentifier, date: date, lat: nil, lng: nil), true)
        }
        let coordinate = asset.location?.coordinate
        return (LibraryShot(id: asset.localIdentifier, date: date,
                            lat: DeviceTrips.rounded(coordinate?.latitude),
                            lng: DeviceTrips.rounded(coordinate?.longitude)), false)
    }

    /// 区切りの間に休む（画面の動きに譲る）
    private static func pause() async {
        try? await Task.sleep(nanoseconds: DeviceTrips.chunkPauseNanos)
    }

    /// 1つの区切りを読む。読んだ枚数・いちばん古い日時を返す
    private static func readChunk(_ result: PHFetchResult<PHAsset>, range: Range<Int>, since: Date,
                                  into index: inout DeviceTrips.Index) -> (read: Int, oldest: Date?) {
        var read = 0
        var oldest: Date?
        for position in range {
            guard let item = summary(of: result.object(at: position), since: since) else { continue }
            if item.isSkipped { index.skipped.append(item.shot) } else { index.shots.append(item.shot) }
            read += 1
            oldest = min(oldest ?? item.shot.date, item.shot.date)
            index.newest = max(index.newest ?? item.shot.date, item.shot.date)
        }
        return (read, oldest)
    }

    /// 初めての読み（`before` があれば続きから）。新しい順に区切って読み、
    /// `publishEvery` 枚ごとに棚へ、`saveEvery` 枚ごとに端末へ。上限（`maxShots`）で打ち止め
    private static func readFirst(_ before: Date?, into index: inout DeviceTrips.Index, since: Date,
                                  url: URL?, progress: Progress) async {
        let result = fetch(since: since, before: before)
        var sincePublish = 0
        var sinceSave = 0
        var position = 0
        while position < result.count {
            if Task.isCancelled { break }
            let end = min(position + DeviceTrips.chunkSize, result.count)
            let chunk = readChunk(result, range: position..<end, since: since, into: &index)
            if let oldest = chunk.oldest { index.frontier = min(index.frontier ?? oldest, oldest) }
            position = end
            sincePublish += chunk.read
            sinceSave += chunk.read
            if index.shots.count >= DeviceTrips.maxShots { break }
            if sinceSave >= DeviceTrips.saveEvery, !Task.isCancelled {
                tidy(&index, since: since)
                DeviceTripIndexFile.save(index, to: url)
                sinceSave = 0
            }
            if sincePublish >= DeviceTrips.publishEvery {
                tidy(&index, since: since)
                await progress(index, DeviceTrips.found(in: index.shots))
                sincePublish = 0
            }
            await pause()
        }
        tidy(&index, since: since)
        guard !Task.isCancelled else { return }
        index.complete = true
        index.frontier = nil
    }

    /// 前回より新しい写真だけ（ふつうは数枚・区切らない）
    private static func readNewer(after: Date, into index: inout DeviceTrips.Index, since: Date) {
        let result = fetch(since: since, after: after)
        var fresh = DeviceTrips.Index()
        for position in 0..<result.count {
            guard let item = summary(of: result.object(at: position), since: since),
                  item.shot.date > after else { continue }
            if item.isSkipped { fresh.skipped.append(item.shot) } else { fresh.shots.append(item.shot) }
            index.newest = max(index.newest ?? item.shot.date, item.shot.date)
        }
        index.shots = DeviceTrips.merged(index.shots, adding: fresh.shots, since: since)
        index.skipped = DeviceTrips.merged(index.skipped, adding: fresh.skipped, since: since, limit: .max)
    }

    /// 識別子で突き合わせる（消した写真を落とし、一部の許可で選び足した古い写真を足す）。
    /// **覚えている写真は日時・位置を読み直さない**——読むのは識別子だけ（区切って）
    private static func sweep(_ index: inout DeviceTrips.Index, since: Date) async {
        let result = fetch(since: since)
        var ids: [String] = []
        ids.reserveCapacity(result.count)
        var position = 0
        while position < result.count {
            if Task.isCancelled { return }
            let end = min(position + DeviceTrips.chunkSize * 4, result.count)
            for i in position..<end { ids.append(result.object(at: i).localIdentifier) }
            position = end
            await pause()
        }
        let known = DeviceTrips.sweep(known: index.shots + index.skipped, current: ids)
        let skippedIds = Set(index.skipped.map(\.id))
        var shots = known.kept.filter { !skippedIds.contains($0.id) }
        var skipped = known.kept.filter { skippedIds.contains($0.id) }
        if !known.unknown.isEmpty {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: known.unknown, options: nil)
            for i in 0..<fetched.count {
                guard let item = summary(of: fetched.object(at: i), since: since) else { continue }
                if item.isSkipped { skipped.append(item.shot) } else { shots.append(item.shot) }
                index.newest = max(index.newest ?? item.shot.date, item.shot.date)
            }
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

/// 端末の写真の一冊の棚（マイページの「旅の記録」）。**読むのは1か所**——起動のときと、
/// 写真を許可したときと、ライブラリが変わったときに、後ろで続きを読む
@MainActor
final class DeviceTripShelfStore: ObservableObject {

    static let shared = DeviceTripShelfStore()

    /// 説明の札を「今はしない」で閉じた
    static let introDismissedKey = "deviceTrips.introDismissed"

    @Published private(set) var status: PHAuthorizationStatus = PhotoLibrary.status
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
    private var rerunRequested = false
    private var observer: DeviceTripChangeObserver?
    private var changeDebounce: Task<Void, Never>?
    private let defaults: UserDefaults
    private let url: URL?

    init(defaults: UserDefaults = .standard, url: URL? = DeviceTripIndexFile.defaultURL()) {
        self.defaults = defaults
        self.url = url
        introDismissed = defaults.bool(forKey: Self.introDismissedKey)
    }

    /// 棚に出す一冊（`DeviceTrips.books`）
    func books(posted: [LibraryTrips.PostedShot], isMine: Bool) -> [LibraryTrip] {
        DeviceTrips.books(trips, posted: posted, zones: zones, isMine: isMine)
    }

    func dismissIntro() {
        introDismissed = true
        defaults.set(true, forKey: Self.introDismissedKey)
    }

    /// 許可を尋ねる（説明の札の主ボタン）。許されたらすぐ読み始める
    func requestAccess() async {
        status = await PhotoLibrary.requestAccess()
        startIfAllowed()
    }

    /// 許されていれば続きを読む（起動・前面に戻った・許可した）。**読んでいる最中なら、
    /// 終わったあとにもう一度だけ**（新しい写真を取りこぼさない）
    func startIfAllowed() {
        status = PhotoLibrary.status
        guard PhotoLibrary.canRead(status) else { return }
        didStart = true
        registerObserver()
        guard task == nil else {
            rerunRequested = true
            return
        }
        task = Task(priority: .background) { await runLoop() }
    }

    /// まだ一度も読み始めていなければ読む（棚が出たとき・前面に戻ったとき）。
    /// **許可の段は毎回読み直す**（設定アプリで許可して戻ってきた）
    func startIfNeeded() {
        status = PhotoLibrary.status
        guard !didStart else { return }
        startIfAllowed()
    }

    /// 一部だけ許可した人が写真を選び足す（選び終えたら、ライブラリの変化の知らせで読み直す）
    func addMorePhotos() async {
        guard !isPickingMore else { return }
        isPickingMore = true
        let presented = await PhotoLibrary.presentLimitedPicker()
        isPickingMore = false
        if presented { startIfAllowed() }
    }

    /// ライブラリが変わった。**3秒待ってから**読む（iCloud の同期は知らせが続けて来る）
    func libraryChanged() {
        changeDebounce?.cancel()
        changeDebounce = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            startIfAllowed()
        }
    }

    /// 端末の控えを消す（サインアウト・退会。`AuthStore.settleSignedOut`）。
    /// 写真の位置の控えを次の人に残さない
    func forget() {
        task?.cancel()
        task = nil
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
        DeviceTripIndexFile.remove(at: url)
    }

    private func registerObserver() {
        guard observer == nil else { return }
        let made = DeviceTripChangeObserver {
            Task { @MainActor in DeviceTripShelfStore.shared.libraryChanged() }
        }
        PHPhotoLibrary.shared().register(made)
        observer = made
    }

    private func runLoop() async {
        isScanning = true
        repeat {
            rerunRequested = false
            let url = url
            if !loadedFromDisk {
                // 書いた要約を読むのも後ろで（数MB）
                index = await Task.detached(priority: .background) { DeviceTripIndexFile.load(from: url) }.value
                loadedFromDisk = true
            }
            // **`Task.detached` にしない**——取り消し（`forget`）が届かず、消したあとに書き戻す。
            // MainActor の外の async の関数なので、呼ぶだけで画面の糸の外で走る（優先度は呼び手の低いまま）
            let finished = await DeviceTripLibrary.run(start: index, now: Date(), url: url) { index, trips in
                await DeviceTripShelfStore.shared.apply(index, trips)
            }
            guard !Task.isCancelled else { break }
            index = finished
            await resolveNames()
        } while rerunRequested && !Task.isCancelled
        isScanning = false
        task = nil
    }

    private func apply(_ index: DeviceTrips.Index, _ trips: [LibraryTrip]) {
        // 消したあと（サインアウト）に届いた後ろの仕事の結果は捨てる
        guard task != nil else { return }
        self.index = index
        shots = index.shots
        self.trips = trips
        names = index.names
        zones = index.zones
        if index.complete { hasCompleted = true }
    }

    /// 地名を**一冊につき1回**、1つずつ間を空けて引く（`DeviceTrips.toLookUp`）。
    /// 引けなくても一冊は出す（題は期間）
    private func resolveNames() async {
        guard var current = index else { return }
        let targets = DeviceTrips.toLookUp(trips, index: current, now: Date())
        guard !targets.isEmpty else { return }
        for (offset, trip) in targets.enumerated() {
            guard !Task.isCancelled, let center = trip.center else { return }
            if offset > 0 { try? await Task.sleep(nanoseconds: DeviceTrips.lookupPauseNanos) }
            let place = await PhotoLibrary.place(near: center)
            if let name = place.name {
                current.names[trip.id] = name
                current.failedAt[trip.id] = nil
            } else {
                current.failedAt[trip.id] = Date()
            }
            if let zone = place.timeZone { current.zones[trip.id] = zone.identifier }
            names = current.names
            zones = current.zones
        }
        guard !Task.isCancelled else { return }
        index = current
        let url = url
        let saved = current
        await Task.detached(priority: .background) { DeviceTripIndexFile.save(saved, to: url) }.value
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
