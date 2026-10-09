import XCTest
@testable import JourneyPhoto
import UIKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// アプリを離れても写真の本体を送り終える仕組み（`BackgroundTransfer`）。
///
/// 背景の URLSession そのものは Linux に無く、実機でしか確かめられない。ここで見るのは
/// **その周りの決まり**——誰も待っていない転送の鍵を端末に控えて片付けること、
/// 時間切れのあと転送の終わりで猶予を取り直すこと、そして二重に投稿しないこと
@MainActor
final class BackgroundTransferTests: XCTestCase {

    nonisolated(unsafe) private var directory: URL!
    nonisolated(unsafe) private var session: URLSession!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg-transfer-\(UUID().uuidString)", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        session = URLSession(configuration: config)
        ScriptedProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func response(_ status: Int = 200) -> URLResponse {
        HTTPURLResponse(url: URL(string: "https://s3.example.test/put")!, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    // MARK: - 控え（端末に書く）

    /// 🔴 **誰も受け取らなかった鍵は、起動し直しても残る。** 起動直後はログインを
    /// 確かめられず、片付けは後になる——メモリだけだと、その間に消えて S3 に迷子が残る
    func testOrphanKeysSurviveRelaunchUntilSettled() async {
        let file = directory.appendingPathComponent("orphans.json")
        let first = OrphanKeys(fileURL: file)
        first.add("uploads/u1/a.jpg")
        first.add("uploads/u1/a.jpg")
        first.add("uploads/u1/b.jpg")

        let relaunched = OrphanKeys(fileURL: file)
        XCTAssertEqual(relaunched.keys(owner: "u1"), ["uploads/u1/a.jpg", "uploads/u1/b.jpg"],
                       "同じ鍵を2回控えた・残っていない")
        relaunched.remove("uploads/u1/a.jpg")
        XCTAssertEqual(OrphanKeys(fileURL: file).keys(owner: "u1"), ["uploads/u1/b.jpg"], "片付けた鍵がまた出てくる")
    }

    /// 控えには上限がある（古いものから落とす）
    func testOrphanKeysAreCapped() async {
        let keys = OrphanKeys(fileURL: nil)
        for i in 0..<(OrphanKeys.limit + 5) { keys.add("uploads/u1/k\(i)") }
        let kept = keys.keys(owner: "u1")
        XCTAssertEqual(kept.count, OrphanKeys.limit)
        XCTAssertEqual(kept.first, "uploads/u1/k5")
    }

    /// 🔴 **その人の鍵だけを出す。** 別の人の token で送ると 403 で断られ、その鍵を失う。
    /// 接頭辞が似ているだけの人（`u1` と `u10`）・`..` で外へ出る鍵も出さない
    func testOrphanKeysAreSplitByOwner() async {
        let keys = OrphanKeys(fileURL: nil)
        for key in ["uploads/u1/a.jpg", "uploads/u10/b.jpg", "uploads/u2/c.jpg", "uploads/u1/../u2/d.jpg"] {
            keys.add(key)
        }
        XCTAssertEqual(keys.keys(owner: "u1"), ["uploads/u1/a.jpg"])
        XCTAssertEqual(keys.keys(owner: "u2"), ["uploads/u2/c.jpg"])
        XCTAssertEqual(keys.keys(owner: ""), [])
    }

    /// 🔴 **読めなかった控えを上書きしない。** 鍵の掛かった端末で起こされると、最初のロック解除の
    /// 前は控えのファイルを読めないことがある。そこで足した1本を書くと、前の控えが消えていた
    func testUnreadableOrphanFileIsNotOverwritten() async throws {
        let file = directory.appendingPathComponent("orphans.json")
        OrphanKeys(fileURL: file).add("uploads/u1/a.jpg")
        let locked = Box(true)
        let keys = OrphanKeys(fileURL: file, readFile: { url in
            if locked.value { throw CocoaError(.fileReadNoPermission) }
            return try Data(contentsOf: url)
        })
        keys.add("uploads/u1/b.jpg")
        let onDisk = try JSONDecoder().decode([String].self, from: Data(contentsOf: file))
        XCTAssertEqual(onDisk, ["uploads/u1/a.jpg"], "読めないまま控えを上書きした")

        locked.value = false
        XCTAssertEqual(keys.keys(owner: "u1"), ["uploads/u1/a.jpg", "uploads/u1/b.jpg"], "読めたときに足し合わせていない")
        XCTAssertEqual(OrphanKeys(fileURL: file).keys(owner: "u1"), ["uploads/u1/a.jpg", "uploads/u1/b.jpg"],
                       "読めない間に足した鍵を書いていない")
    }

    /// 転送の札は起動し直しても OS が返す。読めない札は無視する
    func testTransferTagRoundTrips() async {
        let tag = TransferTag(file: "F1", key: "uploads/u1/a.jpg")
        XCTAssertEqual(TransferTag(encoded: tag.encoded), tag)
        XCTAssertNil(TransferTag(encoded: "not json"))
    }

    // MARK: - 帳面（誰が待っているか）

    /// 待つ人が居れば渡す。**控えには書かない**——渡した先が save するので、片付けると
    /// 投稿した写真の本体を消しかねない
    func testFinishedTransferGoesToItsWaiterAndIsNotOrphaned() async {
        let orphans = OrphanKeys(fileURL: nil)
        let book = TransferBook(orphans: orphans)
        let got = Box<Int?>(nil)
        book.wait(file: "F7") { result in got.value = (try? result.get() as? HTTPURLResponse)?.statusCode }
        XCTAssertTrue(book.isWaited(file: "F7"))

        XCTAssertTrue(book.finish(tag: TransferTag(file: "F7", key: "uploads/u1/a.jpg"), result: .success(response())))
        XCTAssertEqual(got.value, 200)
        XCTAssertFalse(book.isWaited(file: "F7"))
        XCTAssertEqual(orphans.keys(owner: "u1"), [], "待つ人に渡した鍵を片付けに回した")
    }

    /// 🔴 **待つ人は札の UUID で引く。** `taskIdentifier` は起動をまたぐと重なりうるので、番号で引くと
    /// 前の起動の転送の終わりを今の投稿が受け取り、まだ届いていない本体のまま save へ進みかねない。
    /// 別の札の終わりは今の投稿に渡さず、控えに回す
    func testCompletionOfAnotherTransferIsNotHandedToTheWaiter() async {
        let orphans = OrphanKeys(fileURL: nil)
        let book = TransferBook(orphans: orphans)
        let got = Box<[Int]>([])
        book.wait(file: "NEW") { result in got.value.append((try? result.get() as? HTTPURLResponse)?.statusCode ?? -1) }

        XCTAssertFalse(book.finish(tag: TransferTag(file: "OLD", key: "uploads/u1/old.jpg"), result: .success(response(403))))
        XCTAssertEqual(got.value, [], "前の起動の転送の終わりを今の投稿に渡した")
        XCTAssertEqual(orphans.keys(owner: "u1"), ["uploads/u1/old.jpg"])

        XCTAssertTrue(book.finish(tag: TransferTag(file: "NEW", key: "uploads/u1/new.jpg"), result: .success(response())))
        XCTAssertEqual(got.value, [200])
    }

    /// 🔴 **アプリが消されて起動し直したら、前の転送を待つ人は居ない。** その鍵は save されて
    /// いないので、控えに書いて後で片付ける
    func testTransferFromAPreviousLaunchIsOrphaned() async {
        let file = directory.appendingPathComponent("orphans.json")
        let before = TransferBook(orphans: OrphanKeys(fileURL: file))
        before.wait(file: "F3") { _ in XCTFail("消えた処理に渡した") }
        // ここでアプリが消された。起動し直した帳面には待つ人が居ない
        let after = TransferBook(orphans: OrphanKeys(fileURL: file))
        XCTAssertFalse(after.finish(tag: TransferTag(file: "F3", key: "uploads/u1/a.jpg"), result: .success(response())))
        XCTAssertEqual(OrphanKeys(fileURL: file).keys(owner: "u1"), ["uploads/u1/a.jpg"])
    }

    /// 同じ転送の終わりを2回渡さない（2回目は誰も待っていない扱い）
    func testFinishIsDeliveredOnlyOnce() async {
        let book = TransferBook(orphans: OrphanKeys(fileURL: nil))
        let count = Box(0)
        book.wait(file: "F1") { _ in count.value += 1 }
        book.finish(tag: TransferTag(file: "F1", key: "k"), result: .success(response()))
        book.finish(tag: TransferTag(file: "F1", key: "k"), result: .success(response()))
        XCTAssertEqual(count.value, 1)
    }

    /// 🔴 **この起動で作った転送は、起動直後の片付け（`reconnect`）が止めない。** 片付けが
    /// 前の起動の残りを探している間に最初の投稿が転送を作ると、止められ・本体を消されていた。
    /// 作る前に書く（`claim`）ので、待つ人を書く前でも見分けられる
    func testTransfersOfThisLaunchAreNotLeftovers() async {
        let book = TransferBook(orphans: OrphanKeys(fileURL: nil))
        book.claim(file: "MINE")
        XCTAssertFalse(book.isLeftover(TransferTag(file: "MINE", key: "uploads/u1/a.jpg")), "この起動の転送を止める")
        XCTAssertTrue(book.isFromThisLaunch(file: "MINE"), "この起動の本体のファイルを消す")
        XCTAssertTrue(book.isLeftover(TransferTag(file: "OLD", key: "uploads/u1/b.jpg")))
        XCTAssertTrue(book.isLeftover(nil), "札の読めない転送を残した")
        book.release(file: "MINE")
        XCTAssertTrue(book.isLeftover(TransferTag(file: "MINE", key: "uploads/u1/a.jpg")))
    }

    // MARK: - OS からの終わり（`didCompleteWithError`）

    /// 前の起動の転送の終わりを、OS から渡されたことにする（待つ人は居ない）
    private func completeFromTheSystem(_ transfer: BackgroundTransfer, key: String, file: String = UUID().uuidString) throws {
        let bodies = directory.appendingPathComponent("bodies", isDirectory: true)
        try FileManager.default.createDirectory(at: bodies, withIntermediateDirectories: true)
        let tag = TransferTag(file: file, key: key)
        try Data([1, 2, 3]).write(to: bodies.appendingPathComponent(tag.file))
        let task = session.uploadTask(with: URLRequest(url: URL(string: "https://s3.example.test/put")!),
                                      fromFile: bodies.appendingPathComponent(tag.file))
        task.taskDescription = tag.encoded
        transfer.urlSession(session, task: task, didCompleteWithError: URLError(.cancelled))
    }

    private func makeTransfer(onFinished: @escaping @MainActor () -> Void = {},
                              excludeFromBackup: @escaping (URL) -> Void = { _ in }) -> BackgroundTransfer {
        BackgroundTransfer(identifier: "test", directory: directory, isInForeground: { false },
                           fallback: SessionTransfer(session: session), onFinished: onFinished,
                           excludeFromBackup: excludeFromBackup)
    }

    /// 起動し直したあとに OS が渡してきた転送の終わり。**本体のファイルを消し、鍵を控えに書き、
    /// 猶予を取り直す**（渡す相手が居る回はその猶予で save へ進む）
    func testCompletionFromTheSystemCleansUpAndRenews() async throws {
        var renewed = 0
        let transfer = makeTransfer(onFinished: { renewed += 1 })
        try completeFromTheSystem(transfer, key: "uploads/u1/a.jpg", file: "F1")

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("bodies/F1").path), "送り終えた本体のファイルが残る")
        XCTAssertEqual(renewed, 1, "猶予を取り直していない")
        var discarded: [String] = []
        await transfer.discardOrphans(owner: "u1") { discarded.append($0); return true }
        XCTAssertEqual(discarded, ["uploads/u1/a.jpg"])
    }

    /// 🔴 **片付けに失敗した鍵は控えに残す**（圏外・401・503）。以前は先に控えを空にしてから
    /// 送り、失敗を捨てていたので、その鍵は二度と片付かなかった。**別の人の鍵には触らない**
    func testDiscardOrphansKeepsFailuresAndOtherUsersKeys() async throws {
        let transfer = makeTransfer()
        for key in ["uploads/u1/a.jpg", "uploads/u1/b.jpg", "uploads/u2/z.jpg"] {
            try completeFromTheSystem(transfer, key: key)
        }
        var sent: [String] = []
        await transfer.discardOrphans(owner: "u1") { key in
            sent.append(key)
            return key != "uploads/u1/b.jpg"
        }
        XCTAssertEqual(sent, ["uploads/u1/a.jpg", "uploads/u1/b.jpg"], "別の人の鍵をこの人の token で送った")

        // 次の回（裏から戻った・起動し直した）に、失敗した鍵だけを送り直す
        let relaunched = makeTransfer()
        var again: [String] = []
        await relaunched.discardOrphans(owner: "u1") { again.append($0); return true }
        XCTAssertEqual(again, ["uploads/u1/b.jpg"], "失敗した鍵を失った・済んだ鍵をまた送った")
        var other: [String] = []
        await relaunched.discardOrphans(owner: "u2") { other.append($0); return true }
        XCTAssertEqual(other, ["uploads/u2/z.jpg"], "別の人の鍵を失った")
    }

    /// 片付けの答えの読み方。**409（保存済みが使っている）は済んだ扱い**——消してはいけない鍵なので
    /// 控えから外す。確かめられなかった（503・401・圏外）は済んでいない
    func testDiscardOrphanTellsSettledFromRetryLater() async {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let uploads = UploadService(api: api, session: session)
        let cases: [(Int, Bool)] = [(200, true), (409, true), (403, true), (400, true),
                                    (503, false), (401, false), (429, false)]
        for (status, settled) in cases {
            ScriptedProtocol.reset()
            ScriptedProtocol.script = [.init(match: "/upload/discard", status: status, body: #"{"error":"x"}"#)]
            let result = await uploads.discardOrphan(key: "uploads/u1/a.jpg")
            XCTAssertEqual(result, settled, "\(status) の読み方が違う")
        }
        let offline = APIClient(baseURL: URL(string: "https://api.example.test")!,
                                tokenProvider: StubTokenProvider(token: nil), session: session)
        let signedOut = await UploadService(api: offline, session: session).discardOrphan(key: "uploads/u1/a.jpg")
        XCTAssertFalse(signedOut, "ログインしていない回を済んだ扱いにした")
    }

    /// 起動時に、本体の置き場所を作って iCloud のバックアップから外す
    func testReconnectExcludesTheTransferDirectoryFromBackup() async {
        var marked: [URL] = []
        let transfer = makeTransfer(excludeFromBackup: { marked.append($0) })
        transfer.reconnect()
        XCTAssertEqual(marked.map(\.standardizedFileURL.path), [directory.standardizedFileURL.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("bodies").path),
                      "無い場所に印を付けようとした（付かない）")
    }

    /// 裏に回ってから始める転送は、前面の URLSession で送る（背景で始めると OS が後回しにする）。
    /// 本体のファイルも作らない
    func testTransferStartedInTheBackgroundUsesTheForegroundSession() async throws {
        ScriptedProtocol.script = [.init(match: "/put", status: 200, body: "")]
        let transfer = makeTransfer()
        var request = URLRequest(url: URL(string: "https://s3.example.test/put")!)
        request.httpMethod = "PUT"
        let result = try await transfer.upload(request, body: Data([1]), key: "uploads/u1/a.jpg")
        XCTAssertEqual((result as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(ScriptedProtocol.calls.map(\.path), ["/put"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("bodies").path))
    }

    // MARK: - 猶予の取り直し

    private var begun: [String] = []
    private var ended: [UIBackgroundTaskIdentifier] = []
    private var expirations: [@MainActor @Sendable () -> Void] = []

    private func stubWindows() {
        begun = []
        ended = []
        expirations = []
        BackgroundWindow.beginTask = { [unowned self] name, expired in
            self.begun.append(name)
            self.expirations.append(expired)
            return UIBackgroundTaskIdentifier(rawValue: self.begun.count)
        }
        BackgroundWindow.endTask = { [unowned self] in self.ended.append($0) }
        addTeardownBlock { @MainActor in
            BackgroundWindow.beginTask = { name, expired in
                UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expired)
            }
            BackgroundWindow.endTask = { UIApplication.shared.endBackgroundTask($0) }
        }
    }

    /// 🔴 **時間切れで札を返しても、窓は閉じない。** 転送の終わりで起こされたら取り直す。
    /// 閉じた窓は取り直さない（閉じ忘れと同じく、OS にアプリごと止められる）
    func testExpiredWindowIsRenewedUntilClosed() async {
        stubWindows()
        let window = BackgroundWindow(name: "photo-upload")
        XCTAssertTrue(window.isHolding)

        expirations[0]()
        XCTAssertFalse(window.isHolding, "時間切れで札を返していない")
        XCTAssertEqual(ended.count, 1)

        BackgroundWindow.renewAll()
        XCTAssertTrue(window.isHolding, "転送の終わりで猶予を取り直していない")
        XCTAssertEqual(begun.count, 2)
        BackgroundWindow.renewAll()
        XCTAssertEqual(begun.count, 2, "持っているのに2枚目を取った")

        window.end()
        BackgroundWindow.renewAll()
        XCTAssertFalse(window.isHolding)
        XCTAssertEqual(begun.count, 2, "閉じた窓を取り直した")
        XCTAssertEqual(ended.count, 2)
    }

    /// 🔴 **送っている途中で時間切れになっても、本体の転送が終わったら猶予を取り直して
    /// save まで進む。保存は1回・同じ鍵・本体を置き直さない**（二重に投稿しない）。
    ///
    /// 裏に回って時間切れ → 止められる → 背景の転送が終わって起こされる、を模型でなぞる
    /// （`BackgroundTransfer.urlSession(_:task:didCompleteWithError:)` と同じ順——
    /// 猶予を取り直してから、待っていた処理に渡す）
    func testUploadThatOutlivesTheWindowFinishesWithOneSave() async throws {
        stubWindows()
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
            """),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
        var heldAtSave: Bool?
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session,
                            beforeRequest: { [unowned self] request in
                                guard request.url?.path == "/upload/save" else { return }
                                await MainActor.run { heldAtSave = self.begun.count > self.ended.count }
                            })
        let transfer = GatedTransfer()
        let model = UploadViewModel(uploads: UploadService(api: api, transfer: transfer),
                                    albums: AlbumService(api: api), photos: PhotoService(api: api),
                                    discovery: DiscoveryService(api: api))
        model.items = [PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(repeating: 0xFF, count: 16), fileName: "photo.jpg", contentType: "image/jpeg",
            exif: nil, coords: nil, takenOn: nil))]

        let sending = Task { await model.submit() }
        await transfer.untilStarted()
        // 裏に回って 30 秒——札を返す（ここでアプリは止められる）
        XCTAssertEqual(begun, ["photo-upload"])
        expirations[0]()
        XCTAssertEqual(ended.count, 1)
        // 本体の転送が終わって起こされた
        BackgroundWindow.renewAll()
        transfer.finish()
        await sending.value

        XCTAssertTrue(model.items.isEmpty, "送り終えていない")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(heldAtSave, true, "猶予を取り直さずに save を送った（実機では送る前に止められる）")
        XCTAssertEqual(transfer.keys, ["uploads/u1/abc.jpg"], "本体を置き直した")
        let paths = ScriptedProtocol.calls.map(\.path)
        XCTAssertEqual(paths.filter { $0 == "/upload/presigned-url" }.count, 1)
        XCTAssertEqual(paths.filter { $0 == "/upload/save" }.count, 1, "二重に保存した")
        XCTAssertEqual(begun.count, ended.count, "窓を閉じ忘れた（OS に止められる）")
    }
}

/// 本体の転送の模型。**終わらせるまで返らない**（裏で止められている間をなぞる）
private final class GatedTransfer: PhotoTransfer, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: CheckedContinuation<Void, Never>?
    private var started = false
    private var released = false
    private(set) var keys: [String] = []

    func upload(_ request: URLRequest, body: Data, key: String) async throws -> URLResponse {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if start(key: key, continuation) { continuation.resume() }
        }
        return HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    func untilStarted() async {
        for _ in 0..<500 where !isStarted() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func isStarted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    /// 始めた印を付け、もう終わらせてあれば true（すぐ返す）
    private func start(key: String, _ continuation: CheckedContinuation<Void, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        keys.append(key)
        started = true
        if released { return true }
        waiting = continuation
        return false
    }

    func finish() {
        lock.lock()
        released = true
        let waiting = self.waiting
        self.waiting = nil
        lock.unlock()
        waiting?.resume()
    }
}

/// 閉じ込めた値（`@Sendable` の中から書く・試験だけ）
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
