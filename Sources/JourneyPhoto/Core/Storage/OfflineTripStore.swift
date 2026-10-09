import Combine
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 作例1枚の取り先（保存する前）
struct OfflineSampleSource: Equatable {
    let url: URL
    let title: String
    let credit: String
    let sourceUrl: URL?
    let licenseUrl: URL?
}

/// 保存に要る材料の取り方。**画面の側が組んで渡す**（地図の画像は MapKit、作例は台帳の本文）。
/// 試験では差し替える
struct OfflineTripSources {
    /// その場所の作例の候補（多めに渡してよい。先頭から `samplesPerStop` 枚まで取れたぶんを使う）
    var samples: (OfflineTripPlan.Stop) async -> [OfflineSampleSource]
    /// 画像を取る。圏外は `URLError` を投げる
    var download: (URL) async throws -> Data
    /// その場所の周りの地図の画像（JPEG）。座標が無い・描けなければ nil
    var stopMap: (OfflineTripPlan.Stop) async -> Data?
    /// 旅全体の地図の画像（番号の点つき）
    var overviewMap: ([OfflineTripPlan.Stop]) async -> Data?
}

/// 端末に保存した旅の置き場（「電波なしで使える旅」・板 72〜72e・2026-10-09）。
///
/// 置き場は **Application Support/offline-trips/<人>/<旅>/**。iCloud のバックアップからは外す
/// （端末で作り直せるもの。バックアップを膨らませない）。**人ごとに分ける**（同じ端末で人が変わったとき、
/// 前の人の旅を見せない・`StoryDraftStore` と同じ理由）。
///
/// 🔴 **保存はこの置き場が持つ**（画面ではない）。画面を移っても続き、アプリを閉じたら止まる。
/// 途中のもの（`<旅>.partial/`）は次に開いたとき「続きから保存」になる（owner 2026-10-09）。
/// 保存し直しは別の置き場に書き、書き終えてから入れ替える——途中で止まっても前の中身は残る。
@MainActor
final class OfflineTripStore: ObservableObject {

    @Published private(set) var manifests: [String: OfflineTripManifest] = [:]
    /// 走っている・途中で止まった・失敗した旅（保存済みの印もここに映す）
    @Published private(set) var statuses: [String: OfflineSaveStatus] = [:]

    private let root: URL
    private let fileManager: FileManager
    private var userDir: URL?
    /// 走っている保存。**印（`id`）で見分ける**——消した・人が替わったあとに止まり切っていない前の保存が、
    /// 新しく始めた保存の印や状態を書き換えないように（2026-10-09 判断）
    private var jobs: [String: Job] = [:]

    private struct Job {
        let id: UUID
        let task: Task<Void, Never>
    }

    /// この保存がまだ「いまの保存」か（消された・人が替わった・やり直された後なら false）
    private func isCurrent(_ planId: String, _ job: UUID) -> Bool { jobs[planId]?.id == job }
    /// 止めるを押した旅（取り消しの理由を「電波」と取り違えない）
    private var stopRequested: Set<String> = []

    static let manifestName = "manifest.json"
    static let partialInfoName = "partial.json"

    private let defaults: UserDefaults

    init(root: URL? = nil, fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.root = root ?? Self.defaultRoot(fileManager)
    }

    static func defaultRoot(_ fileManager: FileManager = .default) -> URL {
        (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory).appendingPathComponent("offline-trips", isDirectory: true)
    }

    /// 退会した人の保存した旅を消す（`AccountLocalData`）。前に使っていた人の印も、その人なら消す
    static func removeData(for userId: String, root: URL? = nil, defaults: UserDefaults = .standard,
                           fileManager: FileManager = .default) {
        guard !userId.isEmpty else { return }
        let dir = (root ?? defaultRoot(fileManager)).appendingPathComponent(hex(userId), isDirectory: true)
        try? fileManager.removeItem(at: dir)
        if defaults.string(forKey: lastUserKey) == userId { defaults.removeObject(forKey: lastUserKey) }
    }

    // MARK: - 読む

    /// 保存済みの旅（新しく保存した順）
    var saved: [OfflineTripManifest] {
        manifests.values.sorted { $0.savedAt > $1.savedAt }
    }

    var totalBytes: Int64 { manifests.values.reduce(0) { $0 + $1.bytes } }

    func manifest(_ planId: String) -> OfflineTripManifest? { manifests[planId] }

    func status(_ planId: String) -> OfflineSaveStatus { statuses[planId] ?? OfflineSaveStatus() }

    func isRunning(_ planId: String) -> Bool { jobs[planId] != nil }

    /// 保存した画像のありか。**保存済みの置き場の中だけ**（ファイル名に `/` を含むものは出さない）
    func fileURL(planId: String, file: String?) -> URL? {
        guard let file, !file.isEmpty, !file.contains("/"), !file.contains(".."),
              let dir = finalDir(planId) else { return nil }
        return dir.appendingPathComponent(file)
    }

    // MARK: - 人の切り替え

    /// ログインしている人の置き場に切り替える。**走っている保存は止める**（前の人の旅を次の人の置き場に書かない）
    func use(userId: String?) {
        let id = userId.flatMap { $0.isEmpty ? nil : $0 }
        defaults.set(id, forKey: Self.lastUserKey)
        switchTo(id)
    }

    /// 前に使っていた人の置き場（圏外で起動して本人の ID が取れなかった回）
    func useLastUser() {
        switchTo(defaults.string(forKey: Self.lastUserKey))
    }

    private func switchTo(_ userId: String?) {
        let next = userId.map { root.appendingPathComponent(Self.hex($0), isDirectory: true) }
        guard next != userDir else { return }
        // 前の人の保存を止め、**いまの保存から外す**（止まり切るまでの間に、前の人の旅の
        // 「止まった」「失敗した」を次の人の状態に書かない。前の人の途中のものは、その人に戻ったとき
        // 置き場から「続きから保存」で出る）
        for (_, job) in jobs { job.task.cancel() }
        jobs = [:]
        stopRequested = []
        userDir = next
        reload()
    }

    static let lastUserKey = "journey-photo-offline-trips-user"

    /// 置き場を読み直す（保存済みと、途中で止まったもの）
    func reload() {
        var found: [String: OfflineTripManifest] = [:]
        var statuses: [String: OfflineSaveStatus] = [:]
        guard let userDir,
              let names = try? fileManager.contentsOfDirectory(atPath: userDir.path) else {
            manifests = [:]
            self.statuses = self.statuses.filter { jobs[$0.key] != nil }
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for name in names where !name.hasSuffix(".partial") {
            let url = userDir.appendingPathComponent(name).appendingPathComponent(Self.manifestName)
            guard let data = try? Data(contentsOf: url),
                  let m = try? decoder.decode(OfflineTripManifest.self, from: data),
                  m.version == OfflineTripManifest.currentVersion else { continue }
            found[m.planId] = m
            statuses[m.planId] = OfflineSaveStatus.reduce(OfflineSaveStatus(), .finished(bytes: m.bytes, at: m.savedAt))
        }
        for name in names where name.hasSuffix(".partial") {
            let url = userDir.appendingPathComponent(name).appendingPathComponent(Self.partialInfoName)
            guard let data = try? Data(contentsOf: url),
                  let info = try? JSONDecoder().decode(PartialInfo.self, from: data) else { continue }
            if let running = self.statuses[info.planId], jobs[info.planId] != nil {
                statuses[info.planId] = running
                continue
            }
            let done = doneStops(in: userDir.appendingPathComponent(name)).count
            statuses[info.planId] = OfflineSaveStatus.reduce(statuses[info.planId] ?? OfflineSaveStatus(),
                                                             .foundPartial(done: done, total: info.total))
        }
        manifests = found
        self.statuses = statuses
    }

    // MARK: - 保存

    /// 保存する（続きから・保存し直しも同じ口）。**走っている間に呼んでも二重には走らない**
    func save(plan: TripPlan, stops: [OfflineTripPlan.Stop], sources: OfflineTripSources) {
        let planId = plan.planId
        guard jobs[planId] == nil, let partial = partialDir(planId) else { return }
        do {
            try prepareRoot()
            try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
            let info = PartialInfo(planId: planId, title: plan.title, total: stops.count)
            try JSONEncoder().encode(info).write(to: partial.appendingPathComponent(Self.partialInfoName), options: .atomic)
        } catch {
            apply(planId, .failed(OfflineTripText.failureMessage(Self.failure(error))))
            return
        }
        // 前に途中まで書いた場所のうち、**同じ場所・同じ中身**のものは使い回す
        let reusable = doneStops(in: partial).filter { saved in
            stops.contains { Self.sameStop(saved, $0) }
        }
        stopRequested.remove(planId)
        apply(planId, .started(total: stops.count, estimate: OfflineTripBytes.estimate(stops: stops.count),
                               alreadyDone: reusable.count))
        let id = UUID()
        jobs[planId] = Job(id: id, task: Task { [weak self] in
            await self?.run(plan: plan, stops: stops, partial: partial, reusable: reusable, sources: sources, job: id)
        })
    }

    /// 止める（途中まで残す・次は「続きから保存」）
    func stop(_ planId: String) {
        guard let job = jobs[planId] else { return }
        stopRequested.insert(planId)
        job.task.cancel()
    }

    /// 端末から削除（保存済みと途中のもの）。**旅行プランには触らない**
    func delete(_ planId: String) {
        jobs[planId]?.task.cancel()
        jobs[planId] = nil
        stopRequested.remove(planId)
        if let dir = finalDir(planId) { try? fileManager.removeItem(at: dir) }
        if let dir = partialDir(planId) { try? fileManager.removeItem(at: dir) }
        manifests[planId] = nil
        statuses[planId] = nil
    }

    /// 保存した旅をすべて端末から削除（板 72e）
    func deleteAll() {
        let ids = Set(manifests.keys).union(statuses.keys)
        for planId in ids { delete(planId) }
    }

    // MARK: - 中身

    private struct PartialInfo: Codable {
        let planId: String
        let title: String
        let total: Int
    }

    private func run(plan: TripPlan, stops: [OfflineTripPlan.Stop], partial: URL,
                     reusable: [OfflineTripManifest.Stop], sources: OfflineTripSources, job: UUID) async {
        let planId = plan.planId
        var done: [Int: OfflineTripManifest.Stop] = [:]
        for stop in stops {
            if let old = reusable.first(where: { Self.sameStop($0, stop) }) {
                done[stop.number] = old
            }
        }
        // 使い回さない記録は先に消す（番号がずれた古い記録を読まない）
        for name in (try? fileManager.contentsOfDirectory(atPath: partial.path)) ?? [] where name.hasPrefix("stop-") {
            try? fileManager.removeItem(at: partial.appendingPathComponent(name))
        }
        do {
            for (n, record) in done { try write(record, to: partial.appendingPathComponent("stop-\(n).json")) }
            for stop in stops where done[stop.number] == nil {
                try Task.checkCancellation()
                let record = try await saveStop(stop, into: partial, sources: sources)
                try Task.checkCancellation()
                try write(record, to: partial.appendingPathComponent("stop-\(stop.number).json"))
                done[stop.number] = record
                guard isCurrent(planId, job) else { throw CancellationError() }
                apply(planId, .progressed(done: done.count, bytes: OfflineTripBytes.count(in: partial, fileManager: fileManager)))
            }
            try Task.checkCancellation()
            var overview: String?
            if let data = await sources.overviewMap(stops) {
                try data.write(to: partial.appendingPathComponent("overview.jpg"), options: .atomic)
                overview = "overview.jpg"
            }
            try Task.checkCancellation()
            try finish(plan: plan, stops: stops, done: done, overview: overview, partial: partial, job: job)
        } catch {
            // 消された・人が替わった・やり直された後の前の保存は、何も書かずに終わる
            guard isCurrent(planId, job) else { return }
            jobs[planId] = nil
            let stoppedByUser = stopRequested.remove(planId) != nil
            if stoppedByUser || error is CancellationError {
                apply(planId, .stopped)
            } else {
                apply(planId, .failed(OfflineTripText.failureMessage(Self.failure(error))))
            }
        }
    }

    /// 1か所ぶん: 作例（3枚まで）と周りの地図
    private func saveStop(_ stop: OfflineTripPlan.Stop, into dir: URL,
                          sources: OfflineTripSources) async throws -> OfflineTripManifest.Stop {
        var samples: [OfflineTripManifest.Sample] = []
        for source in await sources.samples(stop) {
            guard samples.count < OfflineTripPlan.samplesPerStop else { break }
            try Task.checkCancellation()
            let data: Data
            do {
                data = try await sources.download(source.url)
            } catch {
                // **圏外は止める**（続きから保存）。1枚だけ取れない（消えた・壊れた）は飛ばして次へ
                if Self.isOffline(error) || error is CancellationError { throw error }
                continue
            }
            guard !data.isEmpty else { continue }
            let file = "s\(stop.number)-\(samples.count + 1).jpg"
            try data.write(to: dir.appendingPathComponent(file), options: .atomic)
            samples.append(OfflineTripManifest.Sample(file: file, title: source.title, credit: source.credit,
                                                      sourceUrl: source.sourceUrl, licenseUrl: source.licenseUrl))
        }
        var map: String?
        if stop.coords != nil, let data = await sources.stopMap(stop) {
            let file = "m\(stop.number).jpg"
            try data.write(to: dir.appendingPathComponent(file), options: .atomic)
            map = file
        }
        return OfflineTripManifest.Stop(number: stop.number, key: stop.key, name: stop.name, address: stop.address,
                                        coords: stop.coords, note: stop.note, light: stop.light,
                                        samples: samples, map: map)
    }

    /// 書き終えた: 記録を作り、保存済みの置き場と入れ替える
    private func finish(plan: TripPlan, stops: [OfflineTripPlan.Stop], done: [Int: OfflineTripManifest.Stop],
                        overview: String?, partial: URL, job: UUID) throws {
        let planId = plan.planId
        guard isCurrent(planId, job) else { throw CancellationError() }
        var days: [OfflineTripManifest.Day] = []
        for (di, _) in plan.days.enumerated() {
            let inDay = stops.filter { $0.dayIndex == di }.compactMap { done[$0.number] }
            guard !inDay.isEmpty else { continue }
            days.append(OfflineTripManifest.Day(number: di + 1, date: stops.first { $0.dayIndex == di }?.date,
                                                stops: inDay))
        }
        // 使っていないファイル（前の回の作例など）を消してから数える
        let used = Set(done.values.flatMap { $0.samples.map(\.file) + [$0.map].compactMap { $0 } } + [overview].compactMap { $0 })
        for name in (try? fileManager.contentsOfDirectory(atPath: partial.path)) ?? []
        where name.hasSuffix(".jpg") && !used.contains(name) {
            try? fileManager.removeItem(at: partial.appendingPathComponent(name))
        }
        var manifest = OfflineTripManifest(planId: planId, title: plan.title, startDate: plan.startDate,
                                           endDate: plan.endDate,
                                           // 秒で切る（記録は ISO 8601 の秒までなので、読み直した値と揃える）
                                           savedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
                                           print: OfflineTripPrint(plan),
                                           days: days, overviewMap: overview, bytes: 0)
        let manifestURL = partial.appendingPathComponent(Self.manifestName)
        try write(manifest, to: manifestURL)
        // 記録の分も数える（途中の印は入れ替えの前に消す）
        try? fileManager.removeItem(at: partial.appendingPathComponent(Self.partialInfoName))
        for name in (try? fileManager.contentsOfDirectory(atPath: partial.path)) ?? [] where name.hasPrefix("stop-") {
            try? fileManager.removeItem(at: partial.appendingPathComponent(name))
        }
        manifest.bytes = OfflineTripBytes.count(in: partial, fileManager: fileManager)
        try write(manifest, to: manifestURL)
        guard let final = finalDir(planId) else { return }
        if fileManager.fileExists(atPath: final.path) { try fileManager.removeItem(at: final) }
        try fileManager.moveItem(at: partial, to: final)
        jobs[planId] = nil
        stopRequested.remove(planId)
        manifests[planId] = manifest
        apply(planId, .finished(bytes: manifest.bytes, at: manifest.savedAt))
    }

    // MARK: - 下回り

    private func apply(_ planId: String, _ event: OfflineSaveStatus.Event) {
        statuses[planId] = OfflineSaveStatus.reduce(statuses[planId] ?? OfflineSaveStatus(), event)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func doneStops(in dir: URL) -> [OfflineTripManifest.Stop] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix("stop-") && $0.hasSuffix(".json") }
            .compactMap { try? decoder.decode(OfflineTripManifest.Stop.self, from: Data(contentsOf: dir.appendingPathComponent($0))) }
            // 書いた画像が残っているものだけ（消えていれば取り直す）
            .filter { stop in
                (stop.samples.map(\.file) + [stop.map].compactMap { $0 })
                    .allSatisfy { fileManager.fileExists(atPath: dir.appendingPathComponent($0).path) }
            }
    }

    /// 途中まで書いた場所を使い回してよいか: **番号・場所・メモ・光の時刻が同じ**とき
    /// （番号が違うと画像のファイル名と地図の点がずれる）
    static func sameStop(_ saved: OfflineTripManifest.Stop, _ planned: OfflineTripPlan.Stop) -> Bool {
        saved.number == planned.number && saved.key == planned.key && saved.name == planned.name
            && saved.note == planned.note && saved.light == planned.light && saved.coords == planned.coords
            && saved.address == planned.address
    }

    private func prepareRoot() throws {
        guard !fileManager.fileExists(atPath: root.path) else { return }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        Self.excludeFromBackup(root)
    }

    /// iCloud のバックアップから外す（下の階層も外れる）
    static func excludeFromBackup(_ url: URL) {
        #if os(Linux)
        _ = url
        #else
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        #endif
    }

    private func finalDir(_ planId: String) -> URL? {
        userDir?.appendingPathComponent(Self.hex(planId), isDirectory: true)
    }

    private func partialDir(_ planId: String) -> URL? {
        userDir?.appendingPathComponent(Self.hex(planId) + ".partial", isDirectory: true)
    }

    /// 鍵をファイル名に使える文字にする（`StoryDraftStore.imageFileName` と同じ16進）
    static func hex(_ key: String) -> String {
        key.utf8.map { String(format: "%02x", $0) }.joined()
    }

    static func isOffline(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                .cannotFindHost, .dataNotAllowed, .internationalRoamingOff].contains(e.code)
    }

    static func failure(_ error: Error) -> OfflineTripText.Failure {
        if isOffline(error) { return .offline }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteOutOfSpaceError { return .noSpace }
        if ns.domain == NSPOSIXErrorDomain, ns.code == 28 { return .noSpace }
        return .unknown
    }
}
