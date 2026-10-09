import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
// 前面に居るか（`applicationState`）と、起こされたときの猶予（`BackgroundWindow`）
import UIKit

/// S3 への PUT（写真の本体を置く）を運ぶ口。
///
/// 投稿の3手（`UploadService` の注記）のうち、**時間がかかるのはここだけ**。
/// 前後の API（presign・save）は小さいので、今までどおり前面の URLSession で送る
protocol PhotoTransfer: Sendable {
    /// `key` は置き先の S3 の鍵。途中でアプリが落ちて誰も受け取れなかったときに片付けるため
    func upload(_ request: URLRequest, body: Data, key: String) async throws -> URLResponse
}

/// 渡された URLSession でそのまま送る（試験・裏に回ってから始める転送）
struct SessionTransfer: PhotoTransfer {
    let session: URLSession

    /// 本体の転送は API 呼び出しより長くかかる
    static func standard() -> SessionTransfer {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        return SessionTransfer(session: URLSession(configuration: config))
    }

    func upload(_ request: URLRequest, body: Data, key: String) async throws -> URLResponse {
        try RequestCancellation.throwIfCancelled()
        let (_, response) = try await session.upload(for: request, from: body)
        return response
    }
}

/// **アプリを離れても、写真の本体を送り終える**（2026-10-09 owner の了承）。
///
/// 以前は PUT も前面の URLSession で、裏に回ると `beginBackgroundTask` の猶予（30秒ほど）
/// しか無く、切れると止められて投稿が落ちていた。ここは本体を**背景の URLSession**
/// （`URLSessionConfiguration.background`）に渡す——転送は OS（nsurlsessiond）が続けるので、
/// アプリが止められても・画面を消しても進む。
///
/// 流れ:
///
///     前面で PUT を始める → 背景の転送に渡し、終わるまで待つ
///     （裏に回って止められたら、待っている処理ごと眠る）
///     転送が終わる → OS がアプリを起こす（`handleEventsForBackgroundURLSession`）
///     → 猶予を取り直して（`BackgroundWindow.renewAll`）待っていた処理に渡す
///     → 続き（サムネ・save・曲）はその猶予の中で前面と同じ手順で走る
///
/// 🔴 **save は今までどおりアプリの中で送る。** 同じ鍵で送り直せば二重にならない
/// 決まり（`UploadService.stage`・「保存済み」の 409）はそのまま。ここは本体を運ぶだけ。
///
/// 🔴 **裏に回ってから始める転送は前面の URLSession で送る**（`isInForeground`）。
/// 裏で始めた背景の転送は OS が「急がないもの」として扱い（`isDiscretionary` が強制される）、
/// Wi-Fi や充電を待って何分も始まらないことがある——その間、画面は「3 / 5 枚目」のまま
/// 止まって見え、presign の 15 分（`upload.ts` の `expiresIn: 900`）も過ぎうる。
/// 前面の URLSession なら、猶予の中で通るか、すぐ失敗して「もう一度」で同じ鍵の save に戻れる。
///
/// 🔴 **アプリごと落ちた（メモリ不足で消された）ら、続きは送らない。** 下書き（題・撮影地）は
/// 画面のモデルにしか無く、本人も「出したつもりか」分からない（ストーリーの並びと同じ判断・
/// `StoryUploadCenter`）。
///
/// 片付けるのは**転送の終わりを誰も受け取らなかった鍵だけ**（`OrphanKeys` に書き、次にその人が
/// ログインしているときに `discardOrphans` で消す）。受け取りは save より前なので、ここで
/// 控えた鍵は save されていない。
///
/// ⚠️ **控えに入らず S3 に残る本体がある**: 転送の終わりを受け取った**あと**、save を送る前
/// （または save の応答を待つ間）にアプリが消された回。受け取った時点で帳面から外れるので、
/// その鍵は誰も覚えていない。save が通っていれば使われている鍵、通っていなければ迷子として残る
/// （以前の「PUT の後・save の前に落ちた」回と同じ。消すならサーバー側の掃除・確かめていない）
final class BackgroundTransfer: NSObject, PhotoTransfer, URLSessionTaskDelegate, @unchecked Sendable {

    static let shared = BackgroundTransfer()

    /// 背景の URLSession の名前。**起動し直しても同じ名前で作り直す**——OS は名前で前の転送を返す
    let identifier: String
    private let book: TransferBook
    /// 転送する本体を置く場所（背景の転送はファイルからしか送れない）
    private let bodies: URL
    private let isInForeground: @Sendable () async -> Bool
    private let fallback: PhotoTransfer
    /// 転送が終わって渡す直前に呼ぶ（既定は `BackgroundWindow.renewAll`）
    private let onFinished: @MainActor () -> Void
    /// iCloud のバックアップから外す口。**試験でだけ差し替える**（Linux は印を持てない）
    private let excludeFromBackup: (URL) -> Void

    private let lock = NSLock()
    private var madeSession: URLSession?
    /// OS から預かった「起こした用事が済んだら呼ぶ」もの
    private var systemCompletion: (() -> Void)?
    /// 控えの片付けが走っている（2か所から呼ばれても重ねない）
    private var discarding = false

    init(identifier: String = (Bundle.main.bundleIdentifier ?? "com.journeyphoto") + ".photo-upload",
         directory: URL = BackgroundTransfer.defaultDirectory,
         isInForeground: @escaping @Sendable () async -> Bool = {
             await MainActor.run { UIApplication.shared.applicationState != .background }
         },
         fallback: PhotoTransfer = SessionTransfer.standard(),
         onFinished: @escaping @MainActor () -> Void = { BackgroundWindow.renewAll() },
         excludeFromBackup: @escaping (URL) -> Void = BackgroundTransfer.markExcludedFromBackup,
         readFile: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }) {
        self.identifier = identifier
        self.bodies = directory.appendingPathComponent("bodies", isDirectory: true)
        self.book = TransferBook(orphans: OrphanKeys(fileURL: directory.appendingPathComponent("orphans.json"),
                                                     readFile: readFile))
        self.isInForeground = isInForeground
        self.fallback = fallback
        self.onFinished = onFinished
        self.excludeFromBackup = excludeFromBackup
        super.init()
    }

    static var defaultDirectory: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("photo-transfers", isDirectory: true)
    }

    /// 送るまでの一時の本体を、iCloud のバックアップに載せない（Application Support は既定で載る）
    static func markExcludedFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    private var session: URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let madeSession { return madeSession }
        #if canImport(FoundationNetworking)
        // Linux（模型）には背景の転送が無い。型を通すだけ
        let config = URLSessionConfiguration.default
        #else
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        // 転送が終わったら、止められていた・消されていたアプリを起こしてもらう
        config.sessionSendsLaunchEvents = true
        // 前面で始める転送はすぐ送る（急がないものとして後回しにさせない）
        config.isDiscretionary = false
        #endif
        config.timeoutIntervalForRequest = 120
        // presign の期限（15分）を過ぎた転送は S3 が断るので、待ち続けない
        config.timeoutIntervalForResource = 900
        // 渡すのは主スレッドで（猶予の取り直しは MainActor）
        let made = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        madeSession = made
        return made
    }

    // MARK: - 送る

    func upload(_ request: URLRequest, body: Data, key: String) async throws -> URLResponse {
        guard await isInForeground() else {
            return try await fallback.upload(request, body: body, key: key)
        }
        try RequestCancellation.throwIfCancelled()
        let tag = TransferTag(file: UUID().uuidString, key: key)
        // 🔴 **作る前に「この起動の転送」と書く。** 起動直後の `reconnect` が前の起動の残りを
        // 探している間に作ると、待つ人を書く前に見つかって止められ・本体を消されていた
        book.claim(file: tag.file)
        let file = bodies.appendingPathComponent(tag.file)
        do {
            try FileManager.default.createDirectory(at: bodies, withIntermediateDirectories: true)
            // 中身は `ImagePreparer` が整えた絵そのもの（GPS は抜いてある）。鍵の掛かった画面でも
            // OS が読めるよう、保護は既定（最初のロック解除まで）のまま。送り終えたら消す
            try body.write(to: file, options: .atomic)
            excludeFromBackup(file)
        } catch {
            book.release(file: tag.file)
            // 置けなければ今までどおり前面で送る（投稿は止めない）
            return try await fallback.upload(request, body: body, key: key)
        }
        let task = session.uploadTask(with: request, fromFile: file)
        task.taskDescription = tag.encoded
        let book = self.book
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLResponse, Error>) in
                // **待つ人を書いてから始める**——先に始めると、すぐ終わった回が「誰も待っていない」になる
                book.wait(file: tag.file) { continuation.resume(with: $0) }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - OS から

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 札の読めない転送は、この口が作ったものではない（誰にも渡さない）
        guard let tag = task.taskDescription.flatMap(TransferTag.init(encoded:)) else { return }
        try? FileManager.default.removeItem(at: bodies.appendingPathComponent(tag.file))
        let result: Result<URLResponse, Error>
        if let error {
            result = .failure(error)
        } else if let response = task.response {
            result = .success(response)
        } else {
            result = .failure(URLError(.badServerResponse))
        }
        // 🔴 **渡す前に猶予を取り直す。** 止められていたアプリが転送の終わりで起こされた回は、
        // ここで取り直さないと、続きの save を送る前にまた止められる
        let onFinished = self.onFinished
        MainActor.assumeIsolated { onFinished() }
        book.finish(tag: tag, result: result)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let completion = systemCompletion
        systemCompletion = nil
        lock.unlock()
        completion?()
    }

    /// `AppDelegate` の `handleEventsForBackgroundURLSession` から。
    /// 同じ名前で URLSession を作り直すと、OS が終わった転送を順に渡してくる
    func handleEvents(identifier: String, completion: @escaping () -> Void) {
        guard identifier == self.identifier else {
            completion()
            return
        }
        lock.lock()
        systemCompletion = completion
        lock.unlock()
        _ = session
    }

    /// 起動時に1回。**前の起動から残っている転送は、もう誰も受け取らないので止める**
    /// （止めた分は `didCompleteWithError` で控えに入り、あとで片付く）。
    /// 残っている本体のファイルのうち、前の起動のものも消す。**この起動で作ったものには触らない**
    /// （`TransferBook.isLeftover`）
    func reconnect() {
        let book = self.book
        let bodies = self.bodies
        // 置き場所ごと iCloud のバックアップから外す（中の本体・控えも外れる）。
        // 無い場所には印を付けられないので先に作る
        try? FileManager.default.createDirectory(at: bodies, withIntermediateDirectories: true)
        excludeFromBackup(bodies.deletingLastPathComponent())
        session.getAllTasks { tasks in
            var inUse: Set<String> = []
            for task in tasks {
                let tag = task.taskDescription.flatMap(TransferTag.init(encoded:))
                if book.isLeftover(tag) {
                    task.cancel()
                } else if let tag {
                    inUse.insert(tag.file)
                }
            }
            let files = (try? FileManager.default.contentsOfDirectory(atPath: bodies.path)) ?? []
            for name in files where !inUse.contains(name) && !book.isFromThisLaunch(file: name) {
                try? FileManager.default.removeItem(at: bodies.appendingPathComponent(name))
            }
        }
    }

    /// 誰も受け取らなかった転送の鍵のうち、**いまログインしている人の鍵だけ**を片付ける
    /// （別の人の token で送ると 403 で断られ、その鍵を失う）。
    /// `discard` が false（圏外・401・503 など、確かめられなかった）を返した鍵は控えに残す
    func discardOrphans(owner userId: String, _ discard: (String) async -> Bool) async {
        guard beginDiscarding() else { return }
        defer { endDiscarding() }
        for key in book.orphans(owner: userId) where await discard(key) {
            book.settleOrphan(key)
        }
    }

    /// 片付けを始めてよいか（走っている最中なら false）
    private func beginDiscarding() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !discarding else { return false }
        discarding = true
        return true
    }

    private func endDiscarding() {
        lock.lock()
        discarding = false
        lock.unlock()
    }
}

/// 転送に付ける札（`taskDescription`）。**起動し直しても OS が返してくる**ので、
/// 前の起動の転送でも、本体のファイルと置き先の鍵が分かる
struct TransferTag: Codable, Equatable {
    /// 本体を置いたファイルの名前（`bodies` の中）。**転送ごとに新しい UUID**——
    /// 待つ人もこれで引く（`taskIdentifier` は起動をまたぐと重なりうる）
    let file: String
    /// 置き先の S3 の鍵
    let key: String

    var encoded: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    init(file: String, key: String) {
        self.file = file
        self.key = key
    }

    init?(encoded: String) {
        guard let data = encoded.data(using: .utf8),
              let tag = try? JSONDecoder().decode(TransferTag.self, from: data) else { return nil }
        self = tag
    }
}

/// 背景の転送の帳面——**どの転送を誰が待っているか**と、誰も待っていなかった鍵。
///
/// 待つ人は処理の中（メモリ）にしか居ない。アプリが消されて起動し直したら、
/// 前の転送を待つ人はもう居ない——その鍵は save されていないので、控えに書いて片付ける
/// （save は待つ人が転送の終わりを受け取ってからしか送らない）。
///
/// 🔴 **引くのは札の UUID（`TransferTag.file`）。** `taskIdentifier` は URLSession の中の通し番号で、
/// 起動し直すと前の起動の転送と同じ番号が出うる——番号で引くと、前の起動の転送の終わりを
/// 今の投稿が受け取り、まだ届いていない本体のまま save へ進みかねない
final class TransferBook: @unchecked Sendable {
    typealias Resume = @Sendable (Result<URLResponse, Error>) -> Void

    private let lock = NSLock()
    private var waiters: [String: Resume] = [:]
    /// この起動で作った転送（`claim`）。起動直後の片付けがこれを止めない
    private var thisLaunch: Set<String> = []
    private let orphanKeys: OrphanKeys

    init(orphans: OrphanKeys) {
        self.orphanKeys = orphans
    }

    /// この起動で作る転送だと書く（転送を作る**前**に）
    func claim(file: String) {
        lock.lock()
        thisLaunch.insert(file)
        lock.unlock()
    }

    /// 作れなかった転送の印を外す
    func release(file: String) {
        lock.lock()
        thisLaunch.remove(file)
        lock.unlock()
    }

    func isFromThisLaunch(file: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return thisLaunch.contains(file)
    }

    /// 前の起動から残った転送か（止めてよいか）。札の読めないものも止める
    func isLeftover(_ tag: TransferTag?) -> Bool {
        guard let tag else { return true }
        return !isFromThisLaunch(file: tag.file)
    }

    func wait(file: String, resume: @escaping Resume) {
        lock.lock()
        waiters[file] = resume
        lock.unlock()
    }

    func isWaited(file: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiters[file] != nil
    }

    /// 転送が終わった。待つ人が居れば渡す（true）。**居なければ鍵を控えに書く**（false）。
    /// 渡すのは1回だけ（同じ転送の2回目は誰も待っていない扱い）
    @discardableResult
    func finish(tag: TransferTag, result: Result<URLResponse, Error>) -> Bool {
        lock.lock()
        let resume = waiters.removeValue(forKey: tag.file)
        thisLaunch.remove(tag.file)
        lock.unlock()
        if let resume {
            resume(result)
            return true
        }
        orphanKeys.add(tag.key)
        return false
    }

    /// その人の控えの鍵（取り出さない——片付けが済んだものだけ `settleOrphan` で外す）
    func orphans(owner userId: String) -> [String] { orphanKeys.keys(owner: userId) }

    func settleOrphan(_ key: String) { orphanKeys.remove(key) }
}

/// 誰も受け取らなかった転送の鍵の控え。**端末に書く**——起動し直した直後は
/// まだログインを確かめられず、片付けられるのは後になる。
///
/// 🔴 **読めなかった控えを上書きしない。** 鍵の掛かった端末で転送の終わりに起こされると、
/// 最初のロック解除の前はファイルを読めないことがある（データ保護）。そこで空として書くと、
/// 前の控えが消える。読めるまではメモリに持ち、読めたときに足し合わせて書く
final class OrphanKeys: @unchecked Sendable {
    /// 控える上限。古いものから落とす（片付け損ねても S3 に迷子が残るだけ）
    static let limit = 100

    private let fileURL: URL?
    private let readFile: (URL) throws -> Data
    private let lock = NSLock()
    private var keys: [String] = []
    /// 端末の控えを読み込めたか（無かったときも読めた扱い）
    private var loaded = false

    /// `fileURL` が nil ならメモリだけ。`readFile` は試験でだけ差し替える
    init(fileURL: URL?, readFile: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }) {
        self.fileURL = fileURL
        self.readFile = readFile
        loadIfNeeded()
    }

    func add(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        guard !key.isEmpty, !keys.contains(key) else { return }
        keys.append(key)
        if keys.count > Self.limit { keys.removeFirst(keys.count - Self.limit) }
        save()
    }

    /// その人の鍵（`uploads/<userId>/`）。**別の人の鍵は出さない**——その人の token では
    /// サーバーが 403 で断る（`upload.ts` の `discardUpload`）
    func keys(owner userId: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return keys.filter { Self.belongs($0, to: userId) }
    }

    func remove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        keys.removeAll { $0 == key }
        save()
    }

    /// 鍵がその人の置き場所（`uploadPolicy.ts` の `uploadPrefix`）の中か
    static func belongs(_ key: String, to userId: String) -> Bool {
        !userId.isEmpty && key.hasPrefix("uploads/\(userId)/") && !key.contains("..")
    }

    /// 控えのファイルを読む。**無ければ空で読めた扱い・あるのに読めなければ読めないまま**（書かない）
    private func loadIfNeeded() {
        guard !loaded else { return }
        guard let fileURL else {
            loaded = true
            return
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loaded = true
            return
        }
        guard let data = try? readFile(fileURL) else { return }
        let saved = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        // 読めない間にメモリへ足したものを後ろに足す
        var merged = saved
        for key in keys where !merged.contains(key) { merged.append(key) }
        if merged.count > Self.limit { merged.removeFirst(merged.count - Self.limit) }
        keys = merged
        loaded = true
        if merged != saved { save() }
    }

    private func save() {
        guard let fileURL, loaded else { return }
        if keys.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? JSONEncoder().encode(keys).write(to: fileURL, options: .atomic)
    }
}
