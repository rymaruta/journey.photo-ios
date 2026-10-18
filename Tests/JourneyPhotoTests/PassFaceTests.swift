import XCTest
@testable import JourneyPhoto

/// 乗車券の特別な券面（Pro・**2026-10-17 owner が確定**）。券面の決め方・電波の中身の往復・受け取った側の Pro の確かめ・
/// 光の計算・文字と地の比・読み上げを見張る
final class PassFaceTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func profile(_ id: String, pro: Bool?, passFace: Bool? = nil, markNone: Bool = false) throws -> UserProfile {
        let flag = pro.map { ",\"pro\":\($0)" } ?? ""
        let face = passFace.map { ",\"passFace\":\($0)" } ?? ""
        let mark = markNone ? ",\"proMarkStyle\":\"none\"" : ""
        return try JSONDecoder.api.decode(UserProfile.self, from: Data(
            "{\"userId\":\"\(id)\",\"name\":\"丸田\"\(flag)\(face)\(mark)}".utf8))
    }

    private func content(face: UInt8?, owner: UserProfile?) throws -> PassCardContent {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"p1\",\"src\":\"/uploads/p1.jpg\",\"userId\":\"u1\"}".utf8))
        let met = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 14))!
        let card = PassEncounter(id: "c", photoId: "p1", note: "", showsFrom: true, metHour: met, deliverAt: met,
                                 placeName: "パリ", placeLat: nil, placeLng: nil, number: 87, opened: false,
                                 ownerId: "u1", face: face)
        return PassCardContent(card: card, photo: photo, owner: owner, fromPrefecture: "東京都", meetingCount: 1)
    }

    // MARK: - 券面の決め方

    /// 🔴 受け取った側: **送った人が Pro だと確かめられたときだけ**選んだ券面。読めない・Pro でない・番号なし・
    /// 知らない番号はマルス券
    func testShownFaceNeedsVerifiedPro() {
        for style in PassTicketFaceStyle.allCases {
            XCTAssertEqual(PassTicketFaceStyle.shown(wire: style.rawValue, ownerIsPro: true), style)
            XCTAssertEqual(PassTicketFaceStyle.shown(wire: style.rawValue, ownerIsPro: false), .mars)
            XCTAssertEqual(PassTicketFaceStyle.shown(wire: style.rawValue, ownerIsPro: nil), .mars, "プロフィールが読めないのに特別な券面")
        }
        XCTAssertEqual(PassTicketFaceStyle.shown(wire: nil, ownerIsPro: true), .mars, "番号が無い（古い版）のにマルス券でない")
        XCTAssertEqual(PassTicketFaceStyle.shown(wire: 99, ownerIsPro: true), .mars, "知らない番号がマルス券でない")
        XCTAssertEqual(PassTicketFaceStyle.fromWire(6), .mars)
    }

    /// 自分の見本: Pro をやめたらマルス券（選んだ値は残る＝また Pro になれば戻る）
    func testOwnFaceFallsBackWhenProEnds() {
        XCTAssertEqual(PassTicketFaceStyle.own(chosen: 4, isPro: true), .urushi)
        XCTAssertEqual(PassTicketFaceStyle.own(chosen: 4, isPro: false), .mars)
        XCTAssertEqual(PassTicketFaceStyle.own(chosen: 4, isPro: nil), .mars)
        XCTAssertEqual(PassTicketFaceStyle.own(chosen: nil, isPro: true), .mars)
    }

    /// 電波の番号は一度出したら変えない（前の版が送った番号を、後の版が別の券面と読み違えない）
    func testWireNumbersAreFixed() {
        XCTAssertEqual(PassTicketFaceStyle.mars.rawValue, 0)
        XCTAssertEqual(PassTicketFaceStyle.brassPlate.rawValue, 1)
        XCTAssertEqual(PassTicketFaceStyle.greatCircle.rawValue, 2)
        XCTAssertEqual(PassTicketFaceStyle.foilHard.rawValue, 3)
        XCTAssertEqual(PassTicketFaceStyle.urushi.rawValue, 4)
        XCTAssertEqual(PassTicketFaceStyle.leather.rawValue, 5)
        XCTAssertEqual(PassTicketFaceStyle.pickerOrder.first, .mars)
        XCTAssertEqual(Set(PassTicketFaceStyle.pickerOrder), Set(PassTicketFaceStyle.allCases))
        XCTAssertEqual(PassTicketFaceStyle.allCases.filter(\.needsPro).count, 5)
    }

    /// 受け取ったカードの券面は、帳を開くときに引いた持ち主の公開プロフィール（`owners`）の Pro の印で決まる
    func testReceivedCardUsesOwnerProfile() throws {
        XCTAssertEqual(try content(face: 1, owner: try profile("u1", pro: true)).faceStyle, .brassPlate)
        XCTAssertEqual(try content(face: 1, owner: try profile("u1", pro: true)).face().style, .brassPlate)
        XCTAssertEqual(try content(face: 1, owner: try profile("u1", pro: false)).faceStyle, .mars)
        XCTAssertEqual(try content(face: 1, owner: try profile("u1", pro: nil)).faceStyle, .mars, "古いサーバー（pro が無い）")
        XCTAssertEqual(try content(face: 1, owner: nil).faceStyle, .mars, "プロフィールを引く前・引けなかった")
        XCTAssertEqual(try content(face: nil, owner: try profile("u1", pro: true)).faceStyle, .mars)
        XCTAssertEqual(try content(face: 77, owner: try profile("u1", pro: true)).faceStyle, .mars)
        // 🔴 サーバーの `passFace` があればそれで決める（印を外した Pro は公開プロフィールで pro:false になる）
        XCTAssertEqual(try content(face: 4, owner: try profile("u1", pro: false, passFace: true, markNone: true)).faceStyle,
                       .urushi, "印を外した Pro（pro:false, passFace:true）が特別な券面にならない")
        XCTAssertEqual(try content(face: 4, owner: try profile("u1", pro: true, passFace: false)).faceStyle,
                       .mars, "passFace:false なのに特別な券面")
        XCTAssertEqual(try content(face: 4, owner: try profile("u1", pro: true)).faceStyle, .urushi, "passFace 無し → pro で決めない")
        XCTAssertEqual(try content(face: 4, owner: try profile("u1", pro: false)).faceStyle, .mars)
        XCTAssertNil(try profile("u1", pro: true).passFaceFlag)
        // Pro の印が変わったら描き直す（同じカードでも別の値）
        XCTAssertNotEqual(try content(face: 1, owner: try profile("u1", pro: true)),
                          try content(face: 1, owner: try profile("u1", pro: false)))
    }

    /// 前の版の帳（券面の項目が無い）も読める・マルス券
    func testOldRecordsDecodeAsMars() throws {
        let json = #"{"id":"c","photoId":"p1","note":"","showsFrom":true,"metHour":0,"deliverAt":0,"number":1,"opened":false}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let card = try decoder.decode(PassEncounter.self, from: Data(json.utf8))
        XCTAssertNil(card.face)
        let settings = try decoder.decode(PassSettings.self, from: Data(#"{"enabled":true,"mode":"always","note":"","showsFrom":true}"#.utf8))
        XCTAssertNil(settings.faceStyle)
    }

    // MARK: - 電波の中身

    /// 版 3 の往復（券面ごと）。版 2 の中身は変えない（版 2 までのアプリが読む）
    func testV3RoundTripsFace() throws {
        for style in PassTicketFaceStyle.allCases {
            let payload = PassExchange.Payload(photoId: "p-1", showsFrom: true, note: "霧の朝", origin: "東京",
                                               destination: "フランス", face: style.rawValue)
            let data = try XCTUnwrap(PassExchange.encodeV3(payload))
            XCTAssertEqual(data.first, PassExchange.version3)
            XCTAssertEqual(PassExchange.decode(data), payload)
            // 版 2 は前と同じ形（末尾に券面の番号を足さない）
            let v2 = try XCTUnwrap(PassExchange.encode(payload))
            XCTAssertEqual(v2.first, PassExchange.version)
            XCTAssertEqual(data.count, v2.count + 1)
            XCTAssertEqual(PassExchange.decode(v2)?.face, 0, "版 2 から券面が読めてしまう")
        }
        // 版 1 は券面なし
        let v1 = try XCTUnwrap(PassExchange.encodeV1(PassExchange.Payload(photoId: "p", showsFrom: false, note: "", face: 3)))
        XCTAssertEqual(PassExchange.decode(v1)?.face, 0)
    }

    /// 知らない番号はそのまま運び（見せるときにマルス券）、末尾が欠けた・余った版 3 は落とす
    func testV3RejectsBrokenTail() throws {
        let payload = PassExchange.Payload(photoId: "p", showsFrom: true, note: "", face: 200)
        let data = try XCTUnwrap(PassExchange.encodeV3(payload))
        XCTAssertEqual(PassExchange.decode(data)?.face, 200)
        XCTAssertNil(PassExchange.decode(data.dropLast()), "券面の番号が欠けた版 3 を読んだ")
        XCTAssertNil(PassExchange.decode(data + Data([1])), "余りのある版 3 を読んだ")
    }

    /// 🔴 **電波に載る大きさの上限**（特性の値は 512 バイトまで）。いちばん長い中身でも 199 バイト
    func testV3FitsCharacteristicLimit() throws {
        let id = String(repeating: "a", count: PassExchange.photoIdLimit)
        let payload = PassExchange.Payload(photoId: id, showsFrom: true,
                                           note: String(repeating: "👨‍👩‍👧", count: 20),
                                           origin: String(repeating: "🇯🇵", count: 6),
                                           destination: String(repeating: "🇫🇷", count: 6), face: 5)
        let data = try XCTUnwrap(PassExchange.encodeV3(payload))
        XCTAssertLessThanOrEqual(data.count, 3 + 64 + 1 + 80 + 1 + 24 + 1 + 24 + 1)
        XCTAssertLessThanOrEqual(data.count, PassExchange.payloadByteLimit)
        XCTAssertEqual(PassExchange.payloadByteLimit, 512)
    }

    /// 読む側は版 3 > 版 2 > 版 1。前のアプリ（版 2 まで）の端末からも読める
    func testRadioPrefersV3() {
        let all = [PassRadio.characteristicUUID, PassRadio.characteristicV2UUID, PassRadio.characteristicV3UUID]
        XCTAssertEqual(PassRadio.characteristicToRead(all), PassRadio.characteristicV3UUID)
        XCTAssertEqual(PassRadio.characteristicToRead([PassRadio.characteristicUUID, PassRadio.characteristicV2UUID]),
                       PassRadio.characteristicV2UUID)
        XCTAssertEqual(PassRadio.characteristicToRead([PassRadio.characteristicUUID]), PassRadio.characteristicUUID)
        XCTAssertNotEqual(PassRadio.characteristicV3UUID, PassRadio.characteristicV2UUID)
    }

    // MARK: - 光

    func testLightFollowsGravityAndStaysStillWithReduceMotion() {
        let tilted = PassFaceLight.point(gravityX: 0.2, gravityY: -0.6, baselineY: -0.7)
        XCTAssertEqual(tilted.x, 0.82, accuracy: 1e-9)
        XCTAssertEqual(tilted.y, 0.34, accuracy: 1e-9)
        XCTAssertEqual(PassFaceLight.point(gravityX: 5, gravityY: 0, baselineY: 0).x, 1)
        XCTAssertEqual(PassFaceLight.point(gravityX: -5, gravityY: 0, baselineY: 0).x, 0)
        // 「視差効果を減らす」では動かさない（傾きも回しも）
        XCTAssertEqual(PassFaceLight.resolved(tilt: tilted, shine: 0.3, reduceMotion: true), .center)
        // 指で回している間は回りに合わせる・回していないときは傾き
        XCTAssertEqual(PassFaceLight.resolved(tilt: tilted, shine: 0.3, reduceMotion: false).x, 0.3)
        XCTAssertEqual(PassFaceLight.resolved(tilt: tilted, shine: -0.3, reduceMotion: false), tilted)
        XCTAssertFalse(PassFaceLight.needsUpdate(from: .center, to: PassFaceLight.Point(x: 0.505, y: 0.5)))
        XCTAssertTrue(PassFaceLight.needsUpdate(from: .center, to: PassFaceLight.Point(x: 0.52, y: 0.5)))
    }

    func testLightShapesStayInRange() {
        for x in stride(from: 0.0, through: 1.0, by: 0.1) {
            let light = PassFaceLight.Point(x: x, y: x)
            let h = PassFaceLight.brassHighlight(light)
            XCTAssertGreaterThan(h, 0.28)
            XCTAssertLessThan(h, 0.62)
            XCTAssertGreaterThanOrEqual(PassFaceLight.rimStop(light), 0.05)
            XCTAssertLessThanOrEqual(PassFaceLight.rimStop(light), 0.95)
            // 漆の鏡面の光は写真（上 19〜197 / 430）より下だけを走る
            XCTAssertGreaterThanOrEqual(PassFaceLight.lacquerCenter(light).y * 430, 197)
        }
        let points = PassFaceLight.gradientPoints(cssDegrees: 90)
        XCTAssertEqual(points.start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(points.end.x, 1, accuracy: 1e-9)
        XCTAssertEqual(points.end.y, 0.5, accuracy: 1e-9)
    }

    /// 06: 弧の端は発・着の点。「視差効果を減らす」では光を中ほどで止める
    func testGreatCircleArc() {
        let a = PassGreatCircle.point(0), b = PassGreatCircle.point(1)
        XCTAssertEqual(a.x, PassGreatCircle.start.x)
        XCTAssertEqual(b.x, PassGreatCircle.end.x)
        XCTAssertEqual(PassGreatCircle.progress(at: 123, reduceMotion: true), 0.5)
        XCTAssertEqual(PassGreatCircle.progress(at: 6, reduceMotion: false), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PassGreatCircle.parallels.count, 5)
        XCTAssertEqual(PassGreatCircle.meridians.count, 5)
        // 下の区間: 短い地名は 20・6 字＋6 字でも 13 を割らない
        XCTAssertEqual(PassGreatCircle.routeSize(origin: "東京", destination: "フランス"), 20)
        XCTAssertGreaterThanOrEqual(PassGreatCircle.routeSize(origin: "六字の地名あ", destination: "六字の地名い"),
                                    PassCardStyle.routeMinSize)
    }

    // MARK: - 字

    /// 🔴 文字と地の比（**測らずに「読める」と書かない**）。本文 4.5 以上
    func testFaceTextContrast() {
        var report: [String] = []
        for pair in PassFacePalette.pairs {
            let ratio = BrandPalette.contrast(pair.text, pair.ground)
            report.append(String(format: "%@ %.2f", pair.name, ratio))
            XCTAssertGreaterThanOrEqual(ratio, pair.required, "\(pair.name) が \(String(format: "%.2f", ratio))")
        }
        print("[券面の文字と地の比]\n" + report.joined(separator: "\n"))
    }

    /// 本文系の字は 12pt 以上（「ずっと有効」も 12・土台のマルス券に合わせる。眉ラベル・欄のラベル・No. は 11）
    func testFaceTextSizes() {
        XCTAssertGreaterThanOrEqual(PassCardStyle.metaSize, 12)
        XCTAssertGreaterThanOrEqual(PassCardStyle.fieldValueSize, 12)
        XCTAssertEqual(PassCardStyle.fieldLabelSize, 11)
        XCTAssertEqual(PassCardStyle.validitySize, 12)
        XCTAssertEqual(PassFaceRoute.maxSize, 24.5)
    }

    /// 読み上げ: 特別な券面は表の頭で券面の名前を言う（マルス券は前と同じ）
    func testSpokenHeadlineNamesTheFace() {
        XCTAssertEqual(PassTicketFaceStyle.mars.spokenHeadline("乗車券"), "乗車券")
        for style in PassTicketFaceStyle.allCases where style != .mars {
            let spoken = style.spokenHeadline("乗車券")
            XCTAssertTrue(spoken.hasPrefix("乗車券"))
            XCTAssertTrue(spoken.contains(style.name), "\(style) の名前を言わない")
        }
        XCTAssertEqual(PassTicketFaceStyle.urushi.name, "漆と蒔絵")
        XCTAssertEqual(PassTicket.embossedNumber("No.0087"), "87")
        XCTAssertNil(PassTicket.embossedNumber(nil))
        XCTAssertEqual(PassTicket.routeHeadline(.plain), "航路乗車券")
        XCTAssertEqual(PassTicket.routeHeadline(.first), PassTicket.eyebrow(.first))
    }

    // MARK: - 傾きの読み取り・弧の光（2026-10-17 の読み直し）

    /// 見えていて・前面で・光が動く券面で・「視差効果を減らす」でないときだけ。どれか1つでも外れたら読まない
    func testTiltReadsOnlyWhenEverythingAllows() {
        func reads(appeared: Bool = true, visible: Bool = true, foreground: Bool = true,
                   style: PassTicketFaceStyle = .brassPlate, reduceMotion: Bool = false) -> Bool {
            PassFaceLight.readsTilt(appeared: appeared, visible: visible, foreground: foreground,
                                    style: style, reduceMotion: reduceMotion)
        }
        XCTAssertTrue(reads())
        XCTAssertFalse(reads(appeared: false))
        XCTAssertFalse(reads(visible: false), "裏・全面の写真の下でも読む")
        XCTAssertFalse(reads(foreground: false))
        XCTAssertFalse(reads(reduceMotion: true), "「視差効果を減らす」に変えても読む")
        // 券面を替えたら決め直す: 光が動かない券面（マルス券・大圏航路）へは読まない
        XCTAssertFalse(reads(style: .mars))
        XCTAssertFalse(reads(style: .greatCircle))
        for style in [PassTicketFaceStyle.brassPlate, .foilHard, .urushi, .leather] { XCTAssertTrue(reads(style: style)) }
        // 06 の弧の光: 見えていない・「視差効果を減らす」では止める
        XCTAssertFalse(PassGreatCircle.paused(reduceMotion: false, visible: true))
        XCTAssertTrue(PassGreatCircle.paused(reduceMotion: true, visible: true))
        XCTAssertTrue(PassGreatCircle.paused(reduceMotion: false, visible: false))
    }

    // MARK: - 選ぶ欄（2026-10-17 の読み直し）

    /// Pro は選べる・Pro でないは鍵（押すと案内）・読めない（nil）は鍵をかけない／案内も開かない。マルス券はいつも選べる
    func testPickerOptionStates() {
        XCTAssertEqual(PassTicketFaceStyle.option(.urushi, isPro: true), .open)
        XCTAssertEqual(PassTicketFaceStyle.option(.urushi, isPro: false), .locked)
        XCTAssertEqual(PassTicketFaceStyle.option(.urushi, isPro: nil), .unknown)
        for isPro in [true, false, nil] as [Bool?] {
            XCTAssertEqual(PassTicketFaceStyle.option(.mars, isPro: isPro), .open)
        }
    }

    /// 暫定: Pro で Pro マークを外している人だけに「相手にはマルス券で届く」と言う
    /// サーバーの公開プロフィールに `passFace` が出るまでの間だけ（自分の公開プロフィールに無いときだけ）。読めなければ出さない
    func testProMarkNotice() {
        let notice = PassTicketFaceStyle.proMarkNotice(isPro: true, markRemoved: true, publicHasPassFace: false)
        XCTAssertEqual(notice, "Pro マークを外しているので、相手にはマルス券で届きます")
        XCTAssertNil(PassTicketFaceStyle.proMarkNotice(isPro: true, markRemoved: true, publicHasPassFace: true),
                     "サーバーが passFace を出しているのに知らせる")
        XCTAssertNil(PassTicketFaceStyle.proMarkNotice(isPro: true, markRemoved: true, publicHasPassFace: nil),
                     "公開プロフィールが読めないのに知らせる")
        XCTAssertNil(PassTicketFaceStyle.proMarkNotice(isPro: true, markRemoved: false, publicHasPassFace: false))
        XCTAssertNil(PassTicketFaceStyle.proMarkNotice(isPro: false, markRemoved: true, publicHasPassFace: false))
        XCTAssertNil(PassTicketFaceStyle.proMarkNotice(isPro: nil, markRemoved: true, publicHasPassFace: false))
    }
}

/// 端末の動きの管理者の取り合い（撮る画面の水準器と券面の光・2026-10-17）
@MainActor
final class DeviceMotionOwnerTests: XCTestCase {

    /// 🔴 止めてよいのは今の持ち主だけ。水準器が後から取ったら、券面の光は止めない（水準器の知らせを壊さない）
    func testOnlyCurrentOwnerMayStop() async {
        let level = NSObject(), tilt = NSObject()
        _ = DeviceMotionOwner.release(level)
        _ = DeviceMotionOwner.release(tilt)
        XCTAssertTrue(DeviceMotionOwner.isFree(for: tilt))
        DeviceMotionOwner.claim(tilt)
        // 水準器（撮る画面）が後から取る
        DeviceMotionOwner.claim(level)
        XCTAssertFalse(DeviceMotionOwner.isFree(for: tilt), "水準器が持っているのに券面が取れる")
        XCTAssertFalse(DeviceMotionOwner.release(tilt), "券面の光が水準器の知らせを止めてしまう")
        XCTAssertTrue(DeviceMotionOwner.release(level))
        XCTAssertTrue(DeviceMotionOwner.isFree(for: tilt))
        XCTAssertFalse(DeviceMotionOwner.release(level), "二度止める")
    }
}

/// 自分の設定と電波・受け取りの記録（置き場）
@MainActor
final class PassFaceStoreTests: XCTestCase {

    private var root: URL!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("passface-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: "passface-\(UUID().uuidString)")!
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() -> PassStore {
        let store = PassStore(root: root, defaults: defaults) { _, _, _ in }
        store.use(userId: "me")
        store.update {
            $0.enabled = true
            $0.cardPhotoId = "mine"
        }
        return store
    }

    /// 選んだ券面が電波の中身に載る（選んでいなければマルス券の 0）。帳を開き直しても残る
    func testPayloadCarriesChosenFace() async {
        let store = makeStore()
        XCTAssertEqual(store.payload?.face, 0)
        store.update { $0.faceStyle = PassTicketFaceStyle.leather.rawValue }
        XCTAssertEqual(store.payload?.face, 5)
        let again = PassStore(root: root, defaults: defaults) { _, _, _ in }
        again.use(userId: "me")
        XCTAssertEqual(again.settings.faceStyle, 5)
    }

    /// 受け取った券面の番号を記録に持つ（マルス券は持たない）
    func testRecordKeepsFace() async {
        let store = makeStore()
        let now = Date()
        let card = store.record(PassExchange.Payload(photoId: "other", showsFrom: true, note: "", face: 2), at: now)
        XCTAssertEqual(card?.face, 2)
        let plain = store.record(PassExchange.Payload(photoId: "other2", showsFrom: true, note: ""), at: now)
        XCTAssertNotNil(plain)
        XCTAssertNil(plain?.face)
    }
}

/// 画面の書き方を見張る（画面は Linux で動かせない）
final class PassFaceWiringTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func raw(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 本文の `struct 名前` から次の `struct ` までを取り出す
    private func block(_ text: String, _ name: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: "struct \(name):"), "\(name) が無い")
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\nstruct ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    /// 写真に色・形・反転・映り込み・ぼかし・合成・透明度を付ける修飾子
    private let forbidden = [".blur", ".blendMode", ".colorMultiply", ".colorInvert", ".saturation", ".contrast(",
                             ".brightness", ".hueRotation", ".grayscale", ".luminanceToAlpha", ".opacity",
                             ".mask", ".compositingGroup", ".drawingGroup", "scaleEffect", "rotation3DEffect",
                             "rotationEffect", ".shadow", ".tint", ".foregroundStyle", ".colorEffect",
                             ".layerEffect", ".distortionEffect", ".visualEffect"]

    /// 🔴 **設定した写真は一切加工しない**: 写真の窓（`PassFacePhoto` の印の間）には、枠に収めて角を丸める以外の
    /// 修飾子が付いていない
    func testPhotoWindowIsUntouched() throws {
        let text = try raw("Features/Pass/PassFaces.swift")
        let begin = try XCTUnwrap(text.range(of: "// PHOTO-WINDOW-BEGIN"))
        let end = try XCTUnwrap(text.range(of: "// PHOTO-WINDOW-END"))
        let window = String(text[begin.upperBound..<end.lowerBound])
        XCTAssertTrue(window.contains("DownsampledRemoteImage(url: photo.gridImageURL, contentMode: .fill"))
        for word in forbidden {
            XCTAssertFalse(window.contains(word), "写真の窓に \(word) が付いている")
        }
        // 写真の窓の外（押したとき）も、押す形を付けるだけ
        let photo = try block(try source("Features/Pass/PassFaces.swift"), "PassFacePhoto")
        for word in forbidden {
            XCTAssertFalse(photo.contains(word), "PassFacePhoto に \(word) が付いている")
        }
    }

    /// 文の中の部品の名前（大文字で始まり `(` が続くもの）
    private func componentNames(_ text: String) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_.])([A-Z][A-Za-z0-9]*)\\(")
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { m in
            Range(m.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    /// 写真の呼び出し（`PassFacePhoto(` … `onTap: onPhotoTap)`）の後ろを、写真に続けて付けた修飾子と、その後の文に分ける
    private func afterPhoto(_ text: String) throws -> (chained: [String], rest: String) {
        let start = try XCTUnwrap(text.range(of: "PassFacePhoto("), "写真が無い")
        let close = try XCTUnwrap(text.range(of: "onTap: onPhotoTap)", range: start.upperBound..<text.endIndex))
        var lines = String(text[close.upperBound...]).components(separatedBy: "\n").dropFirst()
        var chained: [String] = []
        while let line = lines.first, line.trimmingCharacters(in: .whitespaces).hasPrefix(".") {
            chained.append(line.trimmingCharacters(in: .whitespaces))
            lines = lines.dropFirst()
        }
        return (chained, lines.joined(separator: "\n"))
    }

    /// 券面の `body`（`var body` から、札の大きさを決める最後の行まで）
    private func faceBody(_ text: String, _ name: String) throws -> String {
        let all = try block(text, name)
        let start = try XCTUnwrap(all.range(of: "var body: some View {"), "\(name) に body が無い")
        let end = try XCTUnwrap(all.range(of: ".frame(width: 300, height: 430, alignment: .topLeading)",
                                          range: start.upperBound..<all.endIndex), "\(name) の body の終わりが無い")
        return String(all[start.upperBound..<end.lowerBound])
    }

    /// 写真より上の層に置いてよい部品（字と、その並べ方だけ）
    private let textOnly: Set<String> = ["Text", "VStack", "HStack", "Spacer", "AnyShapeStyle", "PassFaceTextShadow",
                                         "PassFaceHeadRow", "PassFaceRoute", "PassFaceFields", "PassFaceFooter", "L",
                                         // 数の型の変換（層ではない）
                                         "CGFloat", "Double"]

    /// 写真より後ろで使う小文字の部品（`bottom`・`route`・`routePart(` など）を、同じ札の中の定義
    /// （`private var 名前: some View {` / `private func 名前(`）まで引いて足す。定義の中の小文字の部品もたどる
    private func expandingMembers(_ text: String, in structText: String) -> String {
        let use = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_.$])([a-z][A-Za-z0-9]*)\\b")
        var seen = Set<String>()
        var queue = [text]
        var out = text
        while let chunk = queue.popLast() {
            let range = NSRange(chunk.startIndex..., in: chunk)
            for m in use.matches(in: chunk, range: range) {
                guard let r = Range(m.range(at: 1), in: chunk) else { continue }
                let name = String(chunk[r])
                guard !seen.contains(name) else { continue }
                seen.insert(name)
                for head in ["private var \(name): some View {", "private func \(name)("] {
                    guard let start = structText.range(of: head) else { continue }
                    let rest = structText[start.upperBound...]
                    let end = rest.range(of: "\n    private ")?.lowerBound ?? rest.endIndex
                    let body = String(rest[..<end])
                    out += "\n" + body
                    queue.append(body)
                }
            }
        }
        return out
    }

    /// 🔴 どの券面も写真は `PassFacePhoto` だけで描き、**写真の行から body の終わりまで、写真より後ろ（上の層）には
    /// 字の部品だけ**。写真に続けて付けてよいのは置き場（`.offset`）だけ
    func testFacesDrawPhotoOnlyThroughWindowAndNothingAbove() throws {
        let text = try source("Features/Pass/PassFaces.swift")
        for name in ["PassBrassPlateFace", "PassGreatCircleFace", "PassFoilHardFace", "PassUrushiFace", "PassLeatherFace"] {
            let all = try block(text, name)
            XCTAssertEqual(all.components(separatedBy: "PassFacePhoto(").count - 1, 1, "\(name) の写真が1枚でない")
            XCTAssertFalse(all.contains("DownsampledRemoteImage"), "\(name) が写真を直に描いている")
            let after = try afterPhoto(try faceBody(text, name))
            for line in after.chained {
                XCTAssertTrue(line.hasPrefix(".offset("), "\(name) の写真に \(line) が付いている")
            }
            let extra = componentNames(expandingMembers(after.rest, in: all)).subtracting(textOnly)
            XCTAssertTrue(extra.isEmpty, "\(name) の写真より上の層に字でない部品がある: \(extra.sorted())")
        }
        // 10 の写真の下端の真鍮の線は写真の下（y 200〜202）に置き、写真より下の層に描く
        let foil = try block(text, "PassFoilHardFace")
        XCTAssertTrue(foil.contains(".frame(width: 300, height: 2)\n                .offset(y: 200)"))
    }

    /// 🔴 マルス券も同じ窓で描き、写真に修飾子を続けない・重ねない。**表の外側**（`PassCardFront.body`）にも
    /// 写真ごと色や形を変える修飾子を付けず、重ねるのは外側の縁（`PassTicketEdge`）だけ
    func testMarsFaceAndFrontOutsideAreUntouched() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        let front = try block(cards, "PassCardFront")
        let mars = try XCTUnwrap(front.components(separatedBy: "private var marsFace: some View {").last?
            .components(separatedBy: "private var route: some View").first)
        XCTAssertTrue(mars.contains("PassFacePhoto(photo: face.photo, width: PassCardStyle.deckSize.width, height: PassCardStyle.photoHeight,"))
        let after = try afterPhoto(mars)
        XCTAssertTrue(after.chained.isEmpty, "マルス券の写真に \(after.chained) が付いている")
        for word in [".overlay", "ZStack(", ".mask"] {
            XCTAssertFalse(mars.contains(word), "マルス券に \(word) がある（写真に重なりうる）")
        }
        let body = try XCTUnwrap(front.components(separatedBy: "var body: some View {").dropFirst().first?
            .components(separatedBy: "private var marsFace: some View").first)
        let filters = forbidden.filter { ![".shadow", ".opacity", ".foregroundStyle", ".tint"].contains($0) }
        for word in filters {
            XCTAssertFalse(body.contains(word), "表の外側に \(word) が付いている（写真ごと変わる）")
        }
        let overlays = body.components(separatedBy: ".overlay(").dropFirst().map { String($0.prefix(15)) }
        XCTAssertEqual(overlays, ["PassTicketEdge("], "表の外側に縁以外が重なっている")
        XCTAssertFalse(body.contains(".dynamicTypeSize"), "表の外側に .dynamicTypeSize（土台の決め: 付けない）")
        // 特別な券面の入れ物にも付けない
        for name in ["PassSpecialFace", "PassFaceBody"] {
            let wrapper = try block(try source("Features/Pass/PassFaces.swift"), name)
            for word in filters { XCTAssertFalse(wrapper.contains(word), "\(name) に \(word) が付いている") }
        }
    }

    private func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 古い注記を残さない（2026-10-17 の読み直し）。`DeviceMotionOwner` は `LevelMotion` の説明の途中に挟まない
    func testNotesMatchTheCode() throws {
        let style = try raw("Core/Text/PassFaceStyle.swift")
        XCTAssertTrue(style.contains("`UserProfile.showsPassFace`"), "券面の決め方の注記が pro だけのまま")
        XCTAssertTrue(try raw("Features/Pass/PassFaces.swift").contains("ずっと有効 12 字間 0.04em"))
        XCTAssertTrue(try raw("Features/Pro/PaywallView.swift").contains("特別な乗車券（すれちがいの券面を選べる）を足して4つ"))
        let level = try raw("Features/Spots/LevelMotion.swift")
        XCTAssertTrue(level.contains("/// **実機では確かめていない**（Linux の模型でビルドを通しただけ）。\n@MainActor\nfinal class LevelMotion"),
                      "LevelMotion の説明の後ろに別の型が挟まっている")
        XCTAssertTrue(level.contains("間隔も変えない）\n@MainActor\nenum DeviceMotionOwner"))
    }

    /// メダルの全画面の試験（run 465）: 問い合わせの遅さで「閉じない」と誤って落ちない待ち方・見つけたら抜ける送り方
    func testMedalCloseWaitIsRobust() throws {
        let test = try repoFile("UITests/JourneyPhotoUITests/MedalViewerTests.swift")
        XCTAssertTrue(test.contains("private static let closeDeadline: TimeInterval = 20"))
        XCTAssertTrue(test.contains("let closed = closeButton.waitForNonExistence(timeout: Self.closeDeadline)"))
        XCTAssertTrue(test.contains("XCTAssertTrue(closed, \"\\(tag): × を押してもメダルの全画面が閉じない\")"),
                      "閉じない不具合を見逃す")
        XCTAssertFalse(test.contains("for _ in 0..<12 where"), "見つけた後も問い合わせ続ける")
        XCTAssertTrue(test.contains("if row.exists && row.isHittable && row.isEnabled { break }"))
    }

    /// 傾きの読み取りは表示中・前面・光が動く券面・「視差効果を減らす」でないときだけ
    func testTiltIsReadOnlyWhileShown() throws {
        // 読むかの決め方は表と裏で同じ部品（`PassTiltHold`・2026-10-18 に裏も傾きで光るようにして出した）
        let hold = try block(try source("Features/Pass/PassFaces.swift"), "PassTiltHold")
        XCTAssertTrue(hold.contains("PassFaceLight.readsTilt(appeared: appeared, visible: visible, foreground: scenePhase == .active,"))
        XCTAssertTrue(hold.contains(".onDisappear"))
        XCTAssertTrue(hold.contains("PassTiltMotion.shared.release()"))
        // 前面・「視差効果を減らす」・券面・見えているか、のどれが変わっても決め直す
        for value in ["scenePhase", "reduceMotion", "style", "visible"] {
            XCTAssertTrue(hold.contains(".onChange(of: \(value)) { _, _ in updateHold() }"), "\(value) が変わっても決め直さない")
        }
        let face = try block(try source("Features/Pass/PassFaces.swift"), "PassSpecialFace")
        XCTAssertTrue(face.contains(".modifier(PassTiltHold(style: face.style, visible: visible))"))
        let back = try block(try source("Features/Pass/PassBacks.swift"), "PassSpecialBack")
        XCTAssertTrue(back.contains(".modifier(PassTiltHold(style: face.style, visible: visible))"))
        // 裏を見ている間・全面の写真が上にある間は表を止める。裏は裏が見えている間だけ（見えているかを渡す）
        let spin = try source("Features/Pass/PassSpinCard.swift")
        XCTAssertTrue(spin.contains("PassCardFront(face: front, onPhotoTap: onPhotoTap, shine: shine, visible: active && !back)"))
        XCTAssertTrue(spin.contains("visible: active && back)"))
        XCTAssertTrue(try source("Features/Pass/PassViewerView.swift").contains("active: fullPhoto == nil"))
        XCTAssertTrue(try source("Features/Pass/PassCardPickView.swift").contains("active: !showPaywall"))
        let faces = try source("Features/Pass/PassFaces.swift")
        XCTAssertTrue(faces.contains("paused: PassGreatCircle.paused(reduceMotion: reduceMotion, visible: visible)"))
        // 動きの管理者は持ち主だけが止める（水準器を壊さない）
        let level = try source("Features/Spots/LevelMotion.swift")
        XCTAssertTrue(level.contains("if DeviceMotionOwner.release(self) { Self.manager.stopDeviceMotionUpdates() }"))
        XCTAssertTrue(try source("Features/Pass/PassTiltMotion.swift")
            .contains("if DeviceMotionOwner.release(self) { manager.stopDeviceMotionUpdates() }"))
        let motion = try source("Features/Pass/PassTiltMotion.swift")
        XCTAssertTrue(motion.contains("LevelMotion.manager"), "動きの管理者を2つ作っている")
        XCTAssertTrue(motion.contains("PassFaceLight.needsUpdate"), "細かな揺れでも描き直す")
        XCTAssertTrue(motion.contains("manager.stopDeviceMotionUpdates()"))
        XCTAssertFalse(try source("Features/Spots/LevelMotion.swift").contains("private static let manager"))
    }

    /// 表は券面で描き分け、読み上げで券面の名前を言う。選ぶ画面は Pro でない人を Pro の案内へ
    func testFrontSwitchesAndPickerGatesPro() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        XCTAssertTrue(cards.contains("PassSpecialFace(face: face, onPhotoTap: onPhotoTap, shine: shine, visible: visible)"))
        // 裏の角は表の券面の角に合わせる
        XCTAssertTrue(try source("Features/Pass/PassSpinCard.swift")
            .contains("PassCardBack(face: self.back.styled(front.style), shine: shine, corner: PassCardFront.corner(front.style),"))
        XCTAssertTrue(try block(cards, "PassCardBack").contains(".clipShape(RoundedRectangle(cornerRadius: corner))"))
        XCTAssertTrue(cards.contains("PassTicketFaceStyle.shown(wire: card.face, ownerIsPro: owner?.showsPassFace)"))
        let faces = try source("Features/Pass/PassFaces.swift")
        XCTAssertGreaterThanOrEqual(faces.components(separatedBy: "face.style.spokenHeadline(").count - 1, 3)
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertTrue(pick.contains("PassTicketFaceStyle.own(chosen: faceChoice.rawValue, isPro: profile?.isPro)"))
        XCTAssertTrue(pick.contains("case .locked:\n                deliveredAtPaywall = store.deliveredRevision\n                showPaywall = true"))
        XCTAssertTrue(pick.contains("case .unknown:\n                break"))
        XCTAssertTrue(pick.contains("Text(PassTicketFaceStyle.profileUnreadable)"))
        XCTAssertTrue(pick.contains("markRemoved: profile?.proMarkRemoved ?? false,\n                                                              publicHasPassFace: publicHasPassFace)"))
        XCTAssertTrue(pick.contains("publicHasPassFace = shown.map { $0.passFaceFlag != nil }"))
        XCTAssertTrue(pick.contains(".foregroundStyle(WebTheme.accent)\n                .accessibilityElement(children: .combine)\n                .accessibilityIdentifier(\"pass.pick.face.markNotice\")"))
        // 欄の読み上げは土台と同じ（空は「なし」）
        let fields = try block(try source("Features/Pass/PassFaces.swift"), "PassFaceFields")
        XCTAssertTrue(fields.contains(".accessibilityElement(children: .ignore)\n                .accessibilityLabel(PassTicket.spokenField(field))"))
        // Pro の案内の利点
        XCTAssertTrue(ProBenefit.all.contains { $0.title == "特別な乗車券" })
        XCTAssertTrue(pick.contains("PaywallView()"))
        XCTAssertTrue(pick.contains("if isPro { settings.faceStyle = face == .mars ? nil : face.rawValue }"))
        let radio = try source("Services/PassRadio.swift")
        XCTAssertTrue(radio.contains("radio.apply(payload: PassExchange.encodeV3(payload), v2: PassExchange.encode(payload),"))
    }
}
