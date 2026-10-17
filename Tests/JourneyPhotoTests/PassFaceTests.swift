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

    private func profile(_ id: String, pro: Bool?) throws -> UserProfile {
        let flag = pro.map { ",\"pro\":\($0)" } ?? ""
        return try JSONDecoder.api.decode(UserProfile.self, from: Data("{\"userId\":\"\(id)\",\"name\":\"丸田\"\(flag)}".utf8))
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

    /// 本文系の字は 12pt 以上（眉ラベル・ラベル・ずっと有効・No. は 11）
    func testFaceTextSizes() {
        XCTAssertGreaterThanOrEqual(PassCardStyle.metaSize, 12)
        XCTAssertGreaterThanOrEqual(PassCardStyle.fieldValueSize, 12)
        XCTAssertEqual(PassCardStyle.fieldLabelSize, 11)
        XCTAssertEqual(PassCardStyle.validitySize, 11)
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

    /// 🔴 どの券面も写真は `PassFacePhoto` だけで描き、**写真の上に光・金粉・しぼの層を重ねない**
    /// （写真より後に書く層は字と札だけ）。写真の窓そのものにも修飾子を足さない
    func testFacesDrawPhotoOnlyThroughWindowAndNothingAbove() throws {
        let text = try source("Features/Pass/PassFaces.swift")
        let light = ["Material(", "Sheen", "Glint", "Dust", "Grain", "Hairline", "foil(light)", "LinearGradient(", "RadialGradient("]
        for name in ["PassBrassPlateFace", "PassGreatCircleFace", "PassFoilHardFace", "PassUrushiFace", "PassLeatherFace"] {
            let body = try block(text, name)
            XCTAssertEqual(body.components(separatedBy: "PassFacePhoto(").count - 1, 1, "\(name) の写真が1枚でない")
            XCTAssertFalse(body.contains("DownsampledRemoteImage"), "\(name) が写真を直に描いている")
            let after = try XCTUnwrap(body.components(separatedBy: "PassFacePhoto(").last)
            // 写真の窓の行（押したときの指定と置き場）だけを除いて見る
            let rest = after.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n")
            for word in light where name != "PassFoilHardFace" || word != "LinearGradient(" {
                XCTAssertFalse(rest.contains(word), "\(name) の写真より上に \(word) の層がある")
            }
            let windowLines = after.components(separatedBy: "\n").prefix(2).joined(separator: "\n")
            for word in forbidden {
                XCTAssertFalse(windowLines.contains(word), "\(name) の写真の窓に \(word) が付いている")
            }
        }
        // 10 の写真の下端の真鍮の線は写真の下（y 200〜202）に置き、写真の上には重ねない
        let foil = try block(text, "PassFoilHardFace")
        XCTAssertTrue(foil.contains(".frame(width: 300, height: 2)\n                .offset(y: 200)"))
        // マルス券も同じ窓で描く
        let cards = try source("Features/Pass/PassCards.swift")
        XCTAssertTrue(cards.contains("PassFacePhoto(photo: face.photo, width: PassCardStyle.deckSize.width, height: PassCardStyle.photoHeight,"))
    }

    /// 傾きの読み取りは表示中・前面・光が動く券面・「視差効果を減らす」でないときだけ
    func testTiltIsReadOnlyWhileShown() throws {
        let face = try block(try source("Features/Pass/PassFaces.swift"), "PassSpecialFace")
        XCTAssertTrue(face.contains("appeared && scenePhase == .active && face.style.followsTilt && !reduceMotion"))
        XCTAssertTrue(face.contains(".onDisappear"))
        XCTAssertTrue(face.contains("tilt.release()"))
        let motion = try source("Features/Pass/PassTiltMotion.swift")
        XCTAssertTrue(motion.contains("LevelMotion.manager"), "動きの管理者を2つ作っている")
        XCTAssertTrue(motion.contains("PassFaceLight.needsUpdate"), "細かな揺れでも描き直す")
        XCTAssertTrue(motion.contains("manager.stopDeviceMotionUpdates()"))
        XCTAssertFalse(try source("Features/Spots/LevelMotion.swift").contains("private static let manager"))
    }

    /// 表は券面で描き分け、読み上げで券面の名前を言う。選ぶ画面は Pro でない人を Pro の案内へ
    func testFrontSwitchesAndPickerGatesPro() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        XCTAssertTrue(cards.contains("PassSpecialFace(face: face, onPhotoTap: onPhotoTap, shine: shine)"))
        XCTAssertTrue(cards.contains("PassTicketFaceStyle.shown(wire: card.face, ownerIsPro: owner?.isPro)"))
        let faces = try source("Features/Pass/PassFaces.swift")
        XCTAssertGreaterThanOrEqual(faces.components(separatedBy: "face.style.spokenHeadline(").count - 1, 3)
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertTrue(pick.contains("PassTicketFaceStyle.own(chosen: faceChoice.rawValue, isPro: profile?.isPro)"))
        XCTAssertTrue(pick.contains("if locked {\n                deliveredAtPaywall = store.deliveredRevision\n                showPaywall = true"))
        XCTAssertTrue(pick.contains("PaywallView()"))
        XCTAssertTrue(pick.contains("if isPro { settings.faceStyle = face == .mars ? nil : face.rawValue }"))
        let radio = try source("Services/PassRadio.swift")
        XCTAssertTrue(radio.contains("radio.apply(payload: PassExchange.encodeV3(payload), v2: PassExchange.encode(payload),"))
    }
}
