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
/// `StoryUploadCenter`）。誰も受け取らなかった転送の鍵は控え（`OrphanKeys`）に書き、
/// 次にログインしているときに片付ける（`discardOrphans`）。保存済みの写真が使っている鍵は
/// サーバーが消さない（`upload.ts` の `discardUpload`）
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

    private let lock = NSLock()
    private var madeSession: URLSession?
    /// OS から預かった「起こした用事が済んだら呼ぶ」もの
    private var systemCompletion: (() -> Void)?

    init(identifier: String = (Bundle.main.bundleIdentifier ?? "com.journeyphoto") + ".photo-upload",
         directory: URL = BackgroundTransfer.defaultDirectory,
         isInForeground: @escaping @Sendable () async -> Bool = {
             await MainActor.run { UIApplication.shared.applicationState != .background }
         },
         fallback: PhotoTransfer = SessionTransfer.standard(),
         onFinished: @escaping @MainActor () -> Void = { BackgroundWindow.renewAll() }) {
        self.identifier = identifier
        self.bodies = directory.appendingPathComponent("bodies", isDirectory: true)
        self.book = TransferBook(orphans: OrphanKeys(fileURL: directory.appendingPathComponent("orphans.json")))
        self.isInForeground = isInForeground
        self.fallback = fallback
        self.onFinished = onFinished
        super.init()
    }

    static var defaultDirectory: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("photo-transfers", isDirectory: true)
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
        let file = bodies.appendingPathComponent(tag.file)
        do {
            try FileManager.default.createDirectory(at: bodies, withIntermediateDirectories: true)
            // 中身は `ImagePreparer` が整えた絵そのもの（GPS は抜いてある）。鍵の掛かった画面でも
            // OS が読めるよう、保護は既定（最初のロック解除まで）のまま。送り終えたら消す
            try body.write(to: file, options: .atomic)
        } catch {
            // 置けなければ今までどおり前面で送る（投稿は止めない）
            return try await fallback.upload(request, body: body, key: key)
        }
        let task = session.uploadTask(with: request, fromFile: file)
        task.taskDescription = tag.encoded
        let taskId = task.taskIdentifier
        let book = self.book
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLResponse, Error>) in
                // **待つ人を書いてから始める**——先に始めると、すぐ終わった回が「誰も待っていない」になる
                book.wait(task: taskId) { continuation.resume(with: $0) }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - OS から

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let tag = task.taskDescription.flatMap(TransferTag.init(encoded:))
        if let tag { try? FileManager.default.removeItem(at: bodies.appendingPathComponent(tag.file)) }
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
        book.finish(task: task.taskIdentifier, key: tag?.key, result: result)
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
    /// 残っている本体のファイルのうち、どの転送にも使われていないものも消す
    func reconnect() {
        let book = self.book
        let bodies = self.bodies
        session.getAllTasks { tasks in
            var inUse: Set<String> = []
            for task in tasks {
                if book.isWaited(task: task.taskIdentifier) {
                    if let tag = task.taskDescription.flatMap(TransferTag.init(encoded:)) { inUse.insert(tag.file) }
                } else {
                    task.cancel()
                }
            }
            let files = (try? FileManager.default.contentsOfDirectory(atPath: bodies.path)) ?? []
            for name in files where !inUse.contains(name) {
                try? FileManager.default.removeItem(at: bodies.appendingPathComponent(name))
            }
        }
    }

    /// 誰も受け取らなかった転送の鍵を片付ける（ログインしているときに呼ぶ）
    func discardOrphans(_ discard: (String) async -> Void) async {
        for key in book.takeOrphans() { await discard(key) }
    }
}

/// 転送に付ける札（`taskDescription`）。**起動し直しても OS が返してくる**ので、
/// 前の起動の転送でも、本体のファイルと置き先の鍵が分かる
struct TransferTag: Codable, Equatable {
    /// 本体を置いたファイルの名前（`bodies` の中）
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
/// （save は待つ人が転送の終わりを受け取ってからしか送らない）
final class TransferBook: @unchecked Sendable {
    typealias Resume = @Sendable (Result<URLResponse, Error>) -> Void

    private let lock = NSLock()
    private var waiters: [Int: Resume] = [:]
    private let orphans: OrphanKeys

    init(orphans: OrphanKeys) {
        self.orphans = orphans
    }

    func wait(task: Int, resume: @escaping Resume) {
        lock.lock()
        waiters[task] = resume
        lock.unlock()
    }

    func isWaited(task: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiters[task] != nil
    }

    /// 転送が終わった。待つ人が居れば渡す（true）。**居なければ鍵を控えに書く**（false）。
    /// 渡すのは1回だけ（同じ転送の2回目は誰も待っていない扱い）
    @discardableResult
    func finish(task: Int, key: String?, result: Result<URLResponse, Error>) -> Bool {
        lock.lock()
        let resume = waiters.removeValue(forKey: task)
        lock.unlock()
        if let resume {
            resume(result)
            return true
        }
        if let key { orphans.add(key) }
        return false
    }

    func takeOrphans() -> [String] { orphans.takeAll() }
}

/// 誰も受け取らなかった転送の鍵の控え。**端末に書く**——起動し直した直後は
/// まだログインを確かめられず、片付けられるのは後になる
final class OrphanKeys: @unchecked Sendable {
    /// 控える上限。古いものから落とす（片付け損ねても S3 に迷子が残るだけ）
    static let limit = 100

    private let fileURL: URL?
    private let lock = NSLock()
    private var keys: [String]

    /// `fileURL` が nil ならメモリだけ
    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            keys = saved
        } else {
            keys = []
        }
    }

    func add(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !key.isEmpty, !keys.contains(key) else { return }
        keys.append(key)
        if keys.count > Self.limit { keys.removeFirst(keys.count - Self.limit) }
        save()
    }

    /// 全部を取り出して空にする
    func takeAll() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let taken = keys
        keys = []
        save()
        return taken
    }

    private func save() {
        guard let fileURL else { return }
        if keys.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? JSONEncoder().encode(keys).write(to: fileURL, options: .atomic)
    }
}
