import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JourneyPhoto

/// 部品箱: 押すとその場で付く・もう一度押すと外す・「元に戻す」を 3 秒（札 #711・2026-11-23 owner 承認）
final class TrunkPartsBoxTapTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 押して付け、「元に戻す」で前の付け方へ戻る。もう一度押すと外れる（見本で・サーバーに送らない）
    @MainActor
    func testTapPutsOnAndUndoRestores() async throws {
        let model = TrunkViewModel(preview: .sample, previewPro: false)
        await model.load(offline: false)
        let state = try XCTUnwrap(model.state)
        let before = state.equipped
        // 持っていて、まだ付けていない持ち手を1つ
        let part = try XCTUnwrap(TrunkPartCatalog.parts(of: .handle).first {
            state.ownedParts.contains($0.id) && !before.ids(.handle).contains($0.id)
        })
        let next = TrunkEquipText.toggling(part, on: before)
        XCTAssertFalse(next.full)
        let ok = await model.equip(next.equipped)
        XCTAssertTrue(ok)
        XCTAssertTrue(model.state?.equipped.ids(.handle).contains(part.id) ?? false, "押しても付かない")

        let toasts = ToastCenter()
        toasts.show(TrunkPartsBoxText.equippedNotice(part, on: true), seconds: TrunkPartsBoxText.undoSeconds,
                    undo: ToastCenter.Undo(title: TrunkPartsBoxText.undoTitle) { [model] in await model.equip(before) })
        XCTAssertEqual(toasts.current?.text, "「\(part.name)」を付けました")
        XCTAssertEqual(toasts.undo?.title, "元に戻す")
        await toasts.performUndo()
        XCTAssertEqual(model.state?.equipped, before, "「元に戻す」で前の付け方に戻らない")
        XCTAssertNil(toasts.current, "戻せたのに知らせが残る")

        // 付けている部品をもう一度押すと外れる
        let again = TrunkEquipText.toggling(part, on: TrunkEquipText.toggling(part, on: before).equipped)
        XCTAssertFalse(again.equipped.ids(.handle).contains(part.id), "もう一度押しても外れない")
    }

    /// 出している時間を決めた知らせは、時間が過ぎると消える（3 秒の「元に戻す」）
    @MainActor
    func testUndoToastHidesAfterGivenSeconds() async throws {
        let toasts = ToastCenter()
        toasts.show("付けました", seconds: 1, undo: ToastCenter.Undo(title: "元に戻す") { true })
        XCTAssertNotNil(toasts.undo)
        try await Task.sleep(nanoseconds: 1_400_000_000)
        XCTAssertNil(toasts.current, "決めた時間を過ぎても消えない")
        XCTAssertNil(toasts.undo)
    }

    func testWording() {
        let part = TrunkPartCatalog.parts(of: .lock)[0]
        XCTAssertEqual(TrunkPartsBoxText.equippedNotice(part, on: false), "「\(part.name)」を外しました")
        XCTAssertEqual(TrunkPartsBoxText.missingTitle, "まだ持っていない部品です")
        XCTAssertEqual(TrunkPartsBoxText.missingNote(fragments: 3),
                       "カプセルを回すと出ることがあります。かけらがあと2つたまると、好きな部品と交換できます。")
        XCTAssertEqual(TrunkPartsBoxText.missingNote(fragments: 5),
                       "カプセルを回すと出ることがあります。かけらが5つあるので、この部品と交換できます。")
        XCTAssertEqual(TrunkPartsBoxText.collectedCaption(owned: 9, total: 108), "9 / 108 集めました")
        XCTAssertEqual(TrunkPartsBoxText.coinsTitle(3), "硬貨 3 枚")
        XCTAssertEqual(TrunkPartsBoxText.tapHint, "押すと付けます。もう一度押すと外します。")
        for word in [TrunkPartsBoxText.missingNote(fragments: 0), TrunkPartsBoxText.exchangeTitle(part), TrunkPartsBoxText.tapHint] {
            XCTAssertFalse(word.contains("・") || word.contains("·"), word)
        }
    }

    /// 交換のボタンは、何と交換するかを部品の名前で言う（2026-11-23 確かめ役の指摘）
    func testExchangeButtonNamesThePart() throws {
        let part = TrunkPartCatalog.parts(of: .lock)[0]
        XCTAssertEqual(TrunkPartsBoxText.exchangeTitle(part), "かけら5つで「\(part.name)」と交換する")
        let sheet = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Trunk/TrunkPartsBoxView.swift"),
                               encoding: .utf8)
        XCTAssertTrue(sheet.contains("TrunkButtonFace(title: TrunkPartsBoxText.exchangeTitle(part), kind: .main)"),
                      "シートの交換のボタンに部品の名前が無い")
    }

    /// 画面写真の「部品を付けた」は、付けていない錠前を押す（2つ目の lock.2 は見本で付けているので、押すと外れる）
    func testScreenshotTapsAnUnequippedLock() throws {
        let locks = TrunkPartCatalog.parts(of: .lock).filter { TrunkSample.parts.contains($0.id) }
        XCTAssertEqual(locks.first?.id, "lock.1")
        XCTAssertNotEqual(TrunkSample.equipped.lock, locks.first?.id, "見本の1つ目の錠前を付けている")
        XCTAssertEqual(TrunkSample.equipped.lock, locks.dropFirst().first?.id, "見本の2つ目の錠前の前提が変わった")
        let ui = try String(contentsOf: root.appendingPathComponent("UITests/JourneyPhotoUITests/ScreenshotTests.swift"), encoding: .utf8)
        XCTAssertFalse(ui.contains("matching(identifier: \"trunk.parts.owned\").element(boundBy: 1)"),
                       "付けている錠前（lock.2）を押して「外しました」を撮っている")
        XCTAssertEqual(ui.components(separatedBy: "matching(identifier: \"trunk.parts.owned\").element(boundBy: 0)").count - 1, 2)
    }

    // MARK: 先に絵を替える・続けて押す・失敗したら戻す・通信中の「元に戻す」（サーバーの口で）

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TrunkSlowEquipProtocol.self]
        session = URLSession(configuration: config)
        TrunkSlowEquipProtocol.reset()
    }

    override func tearDown() {
        TrunkSlowEquipProtocol.reset()
        super.tearDown()
    }

    /// 錠前 lock.1 を付けた人のトランクを読んだ所。`equips` はそのあとの付け替えの答えの状態（順に1回ずつ。
    /// 200 なら送った付け方をそのまま返す）
    @MainActor
    private func serverModel(equips: [Int]) async throws -> TrunkViewModel {
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let model = TrunkViewModel(preview: nil)
        model.bind(TrunkService(api: api))
        TrunkSlowEquipProtocol.setUp(equipped: #"{"lock":"lock.1"}"#, equips: equips)
        await model.load(offline: false)
        XCTAssertEqual(try XCTUnwrap(model.state).equipped.lock, "lock.1")
        return model
    }

    private var equipCalls: [Data] { TrunkSlowEquipProtocol.equipBodies }

    @MainActor
    private func waitUntilBusy(_ model: TrunkViewModel) async {
        var spins = 0
        while !model.busy && spins < 1000 {
            await Task.yield()
            spins += 1
        }
    }

    /// 押したらすぐ絵が替わる（応答を待たない）。保存できたらそのまま
    @MainActor
    func testEquipShowsBeforeTheServerAnswers() async throws {
        let model = try await serverModel(equips: [200])
        let saving = model.equipNow(TrunkEquipped(lock: "lock.2"))
        XCTAssertEqual(model.state?.equipped.lock, "lock.2", "応答を待ってから絵を替えている")
        let ok = await saving.value
        XCTAssertTrue(ok)
        XCTAssertEqual(model.state?.equipped.lock, "lock.2")
        XCTAssertEqual(equipCalls.count, 1)
    }

    /// 保存できなかったら、絵をサーバーの付け方へ戻して一言
    @MainActor
    func testFailedEquipPutsThePictureBack() async throws {
        let model = try await serverModel(equips: [500])
        let saving = model.equipNow(TrunkEquipped(lock: "lock.2"))
        XCTAssertEqual(model.state?.equipped.lock, "lock.2")
        let ok = await saving.value
        XCTAssertFalse(ok)
        XCTAssertEqual(model.state?.equipped.lock, "lock.1", "保存できなかったのに付けた絵のまま")
        XCTAssertNotNil(model.actionError, "保存できなかったのに何も言わない")
    }

    /// 続けて押しても送りはぶつからない: 送る前に次を押したら最後の付け方だけを送る。送っている間に押したら、
    /// 前の応答で絵を古い付け方に戻さず、終わってから次を送る
    @MainActor
    func testRapidTapsDoNotCollide() async throws {
        let model = try await serverModel(equips: [200, 200, 200])
        // 送る前に2回: 送るのは最後の1回だけ
        let first = model.equipNow(TrunkEquipped(lock: "lock.2"))
        let second = model.equipNow(TrunkEquipped(lock: "lock.3"))
        XCTAssertEqual(model.state?.equipped.lock, "lock.3")
        _ = await first.value
        let ok = await second.value
        XCTAssertTrue(ok)
        XCTAssertEqual(equipCalls.count, 1, "続けて押した分を全部送っている")
        XCTAssertTrue(String(decoding: equipCalls[0], as: UTF8.self).contains("lock.3"))
        // 送っている間にもう1回
        let third = model.equipNow(TrunkEquipped(lock: "lock.2"))
        await waitUntilBusy(model)
        XCTAssertTrue(model.busy)
        let fourth = model.equipNow(TrunkEquipped(lock: "lock.3"))
        let thirdOK = await third.value
        XCTAssertTrue(thirdOK)
        XCTAssertEqual(model.state?.equipped.lock, "lock.3", "前の応答で絵が古い付け方に戻った")
        let fourthOK = await fourth.value
        XCTAssertTrue(fourthOK)
        XCTAssertEqual(model.state?.equipped.lock, "lock.3")
        XCTAssertEqual(equipCalls.count, 3)
    }

    /// 通信中に「元に戻す」を押しても戻る（前の書き込みの終わりを待つ。2026-11-23 確かめ役の指摘:「取り消せませんでした」になっていた）
    @MainActor
    func testUndoWhileSavingStillRestores() async throws {
        let model = try await serverModel(equips: [200, 200])
        let saving = model.equipNow(TrunkEquipped(lock: "lock.2"))
        await waitUntilBusy(model)
        XCTAssertTrue(model.busy, "送っている間を作れていない")
        let back = await model.undoEquip(to: TrunkEquipped(lock: "lock.1"))
        XCTAssertTrue(back, "通信中に押した「元に戻す」が失敗した")
        _ = await saving.value
        XCTAssertEqual(model.state?.equipped.lock, "lock.1")
        XCTAssertEqual(equipCalls.count, 2)
    }

    /// 「付け替える」の画面と入口は、どこにも残さない
    func testEquipScreenIsGone() throws {
        let dir = root.appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(atPath: dir.path)?.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") } ?? []
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("TrunkEquipView("), "\(file) に付け替えの画面が残っている")
            XCTAssertFalse(text.contains("\"trunk.parts.equip\""), "\(file) に付け替えの入口が残っている")
        }
    }
}

/// トランクの口の答え。**付け替えの答えだけ少し遅らせる**（送っている間に次を押す・「元に戻す」を押す場面を確かに作る。
/// すぐ答える `ScriptedProtocol` では、送っている間を Linux で掴めないことがあった）
final class TrunkSlowEquipProtocol: URLProtocol {

    static let delay: TimeInterval = 0.2

    private static let lock = NSLock()
    nonisolated(unsafe) private static var equipped = "{}"
    nonisolated(unsafe) private static var equips: [Int] = []
    nonisolated(unsafe) private static var bodies: [Data] = []

    /// 錠前を3つ持つトランク（`equipped` は読んだときの付け方）
    static func trunk(_ equipped: String) -> String {
        #"{"pocket":[],"stuck":[],"parts":["lock.1","lock.2","lock.3"],"equipped":\#(equipped)}"#
    }

    static func setUp(equipped: String, equips: [Int]) {
        lock.withLock {
            self.equipped = equipped
            self.equips = equips
            bodies = []
        }
    }

    static func reset() { setUp(equipped: "{}", equips: []) }

    /// 送った付け替えの本文（順に）
    static var equipBodies: [Data] { lock.withLock { bodies } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isEquip = (request.url?.path ?? "").hasSuffix("/user/trunk/equip")
        let answer: (status: Int, body: String) = Self.lock.withLock {
            guard isEquip else { return (200, Self.trunk(Self.equipped)) }
            let sent = request.httpBody ?? Self.read(request.httpBodyStream) ?? Data()
            Self.bodies.append(sent)
            let status = Self.equips.isEmpty ? 500 : Self.equips.removeFirst()
            return (status, status == 200 ? Self.trunk(String(decoding: sent, as: UTF8.self)) : "{}")
        }
        if isEquip { Thread.sleep(forTimeInterval: Self.delay) }
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
