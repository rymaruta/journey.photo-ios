import XCTest
@testable import JourneyPhoto

/// すれちがい乗車券の発・着を自分で決める・きっぷを指で回す（2026-10-16 owner の頼み）
final class PassLabelsSpinTests: XCTestCase {

    // MARK: - 電波の中身の版

    /// 版 2 は発・着の字を運ぶ。版 1 の中身も読める
    func testPayloadV2RoundTripsAndV1StillReads() throws {
        let full = PassExchange.Payload(photoId: "p-1", showsFrom: false, note: "霧の朝",
                                        origin: "雪国", destination: "北陸ひとり旅")
        let v2 = try XCTUnwrap(PassExchange.encode(full))
        XCTAssertEqual(v2.first, 2)
        XCTAssertEqual(PassExchange.decode(v2), full)
        let v1 = try XCTUnwrap(PassExchange.encodeV1(full))
        XCTAssertEqual(v1.first, 1)
        let old = try XCTUnwrap(PassExchange.decode(v1), "版 1 を読めない")
        XCTAssertEqual(old.note, "霧の朝")
        XCTAssertEqual(old.origin, "", "版 1 に発の字が載った")
        XCTAssertEqual(old.destination, "")
    }

    /// 版 2 の並び（長さつき）・空の発着・いちばん長くても 512 を超えない
    func testPayloadV2LayoutAndSize() throws {
        let data = try XCTUnwrap(PassExchange.encode(.init(photoId: "ab", showsFrom: true, note: "x")))
        XCTAssertEqual([UInt8](data), [2, 1, 2, 0x61, 0x62, 1, 0x78, 0, 0])
        let big = PassExchange.Payload(photoId: String(repeating: "a", count: 64), showsFrom: true,
                                       note: String(repeating: "👨‍👩‍👧", count: 20),
                                       origin: String(repeating: "👨‍👩‍👧", count: 8),
                                       destination: String(repeating: "👨‍👩‍👧", count: 8))
        let encoded = try XCTUnwrap(PassExchange.encode(big))
        XCTAssertLessThanOrEqual(encoded.count, PassExchange.payloadByteLimit)
        XCTAssertNotNil(PassExchange.decode(encoded))
    }

    /// 🔴 相手の端末から来た値は信じない: 長さが崩れた・後ろに余り・字が長すぎる発着
    func testV2RejectsBrokenData() {
        XCTAssertNil(PassExchange.decode(Data([2, 0, 1, 0x61, 5, 0x61])), "長さが足りないひとことを読んだ")
        XCTAssertNil(PassExchange.decode(Data([2, 0, 1, 0x61, 0, 0, 0, 0x61])), "後ろの余りを見逃した")
        let longLabel = Array("123456789".utf8)
        XCTAssertNil(PassExchange.decode(Data([2, 0, 1, 0x61, 0, UInt8(longLabel.count)] + longLabel + [0])),
                     "9 字の発を読んだ")
        XCTAssertNil(PassExchange.decode(Data([3, 0, 1, 0x61, 0, 0, 0])), "知らない版を読んだ")
    }

    /// 発・着の字はひとことと同じ整え方（向きの制御・ゼロ幅・結合文字・8 字・32 バイト）
    func testLabelCleaning() {
        XCTAssertEqual(PassExchange.cleanLabel("北陸\u{202E}ひとり旅\u{200B}"), "北陸ひとり旅")
        XCTAssertEqual(PassExchange.cleanLabel("123456789"), "123456")
        XCTAssertLessThanOrEqual(PassExchange.cleanLabel(String(repeating: "👨‍👩‍👧", count: 8)).utf8.count,
                                 PassExchange.labelByteLimit)
        let zalgo = "雪" + String(repeating: "\u{0301}", count: 20)
        XCTAssertEqual(PassExchange.cleanLabel(zalgo).unicodeScalars.count, 1 + PassExchange.marksPerCharacterLimit)
        XCTAssertNil(PassExchange.labelProblem("金沢"))
        XCTAssertNotNil(PassExchange.labelProblem("123456789"))
        XCTAssertNotNil(PassExchange.labelProblem("1234567"), "7 字で訳が出ない")
        XCTAssertNotNil(PassExchange.labelProblem(String(repeating: "👨‍👩‍👧", count: 2)), "バイトで超えた訳が出ない")
    }

    // MARK: - 自動と自分で書く

    func testOriginChoices() {
        var s = PassSettings()
        XCTAssertEqual(s.origin, .home)
        s.setOrigin(.custom, text: "雪国")
        XCTAssertEqual(s.origin, .custom)
        XCTAssertEqual(s.originLabel, "雪国")
        XCTAssertFalse(s.showsFrom, "自分で書いたのに居住地も載る")
        s.setOrigin(.hidden)
        XCTAssertEqual(s.origin, .hidden)
        XCTAssertNil(s.originLabel)
        s.setOrigin(.home)
        XCTAssertEqual(s.origin, .home)
        XCTAssertTrue(s.showsFrom)
    }

    /// 前の版の設定（発・着の欄が無い）も読める
    func testOldSettingsDecode() throws {
        let json = #"{"enabled":true,"mode":"always","note":"a","showsFrom":false}"#
        let s = try JSONDecoder().decode(PassSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.origin, .hidden)
        XCTAssertNil(s.destinationLabel)
    }

    /// 区間: 書いた字があればそのまま、無ければ自動。下車の行はいつも受け取った側の位置
    func testTicketUsesWrittenLabelsButKeepsAlighting() {
        XCTAssertEqual(PassTicket.origin("北海道", written: "雪国"), "雪国")
        XCTAssertEqual(PassTicket.origin("北海道", written: nil), "北海道")
        XCTAssertEqual(PassTicket.destination("京都市", written: "北陸ひとり旅"), "北陸ひとり旅")
        XCTAssertEqual(PassTicket.destination("京都市", written: ""), "京都")
        XCTAssertTrue(PassTicket.alighting("京都市").contains("京都市"))
        XCTAssertEqual(PassTicket.previewOrigin(.custom, text: "雪国", homePrefecture: "北海道"), "雪国")
        XCTAssertEqual(PassTicket.previewOrigin(.home, text: "雪国", homePrefecture: "北海道"), "北海道")
        XCTAssertEqual(PassTicket.previewOrigin(.hidden, text: "", homePrefecture: "北海道"), PassTicket.origin(nil))
        XCTAssertEqual(PassTicket.previewDestination(custom: true, text: "金沢"), "金沢")
        XCTAssertNotEqual(PassTicket.previewDestination(custom: false, text: "金沢"), "金沢")
    }

    /// 伏せたら自動の形に戻す。通報の本文には発・着の字も入る
    func testHiddenLabelsFallBackAndReportCarriesThem() {
        var card = PassEncounter(id: "c", photoId: "p", note: "霧", showsFrom: true, metHour: Date(), deliverAt: Date(),
                                 placeName: "京都市", placeLat: nil, placeLng: nil, number: 1, opened: false, ownerId: "a",
                                 originLabel: "雪国", destinationLabel: "北陸")
        XCTAssertEqual(card.shownOrigin, "雪国")
        card.labelsHidden = true
        XCTAssertNil(card.shownOrigin)
        XCTAssertNil(card.shownDestination)
        XCTAssertEqual(PassTicket.destination(card.placeName, written: card.shownDestination), "京都")
        XCTAssertTrue(card.hasWrittenText)
        let note = ModerationService.passNoteReportNote(card.writtenText, note: nil)
        for part in ["ひとこと「霧」", "発「雪国」", "着「北陸」", ModerationService.passNoteMarker] {
            XCTAssertTrue(note.contains(part), part)
        }
    }

    func testSettingsRouteLine() {
        var s = PassSettings()
        s.setOrigin(.custom, text: "雪国")
        s.destinationLabel = "金沢"
        let line = PassSettingsText.route(s)
        XCTAssertTrue(line.contains("雪国") && line.contains("金沢"), line)
    }

    /// 🔴 発・着の両方を上限いっぱいに書いても、いちばん縮めれば区間に収まる（7 字では収まらない＝上限が正しい）
    func testRouteFitsAtTheLimit() {
        XCTAssertEqual(PassExchange.labelLimit, 6)
        XCTAssertTrue(PassCardStyle.routeFits(chars: PassExchange.labelLimit), "6 字＋6 字が区間に収まらない")
        XCTAssertFalse(PassCardStyle.routeFits(chars: PassExchange.labelLimit + 1))
        XCTAssertGreaterThanOrEqual(PassCardStyle.routeSize * Double(PassCardStyle.routeMinScale), 15, "明朝 15 を割る")
    }

    /// 「自分で書く」を空のまま保存したら、発は「出さない」・着は「すれちがった所」
    func testEmptyCustomFallsBack() {
        var s = PassSettings()
        s.setOrigin(.custom, text: "  ")
        XCTAssertEqual(s.origin, .hidden)
        s.setDestination(custom: true, text: "")
        XCTAssertNil(s.destinationLabel)
        s.setDestination(custom: true, text: "金沢")
        XCTAssertEqual(s.destinationLabel, "金沢")
        s.setDestination(custom: false, text: "金沢")
        XCTAssertNil(s.destinationLabel)
    }

    /// 🔴 素早く払ったとき、次へ移る前に裏が見えない（置いてすぐは回りを半分・裏の手前で止める）
    func testEarlyDragNeverShowsBack() {
        for dx in [-300.0, -150, 150, 300, 600] {
            let yaw = PassSpinGesture.liveYaw(base: 0, dx: dx, width: 300, elapsed: 0.1)
            XCTAssertFalse(SpinMotion.showsBack(yaw), "払いの途中で裏が見えた（dx \(dx)）")
            XCTAssertLessThanOrEqual(abs(yaw), PassSpinGesture.earlyLimit + 1e-9)
        }
        // 置いてしばらく経てば、指に付いてくる（裏まで回せる）
        XCTAssertTrue(SpinMotion.showsBack(PassSpinGesture.liveYaw(base: 0, dx: -150, width: 300, elapsed: 0.6)))
        XCTAssertEqual(PassSpinGesture.liveYaw(base: .pi, dx: 0, width: 300, elapsed: 0.1), .pi, accuracy: 1e-9)
    }

    // MARK: - 回す

    /// 90° を越えたら裏・270° を越えたら表
    func testShowsBackByAngle() {
        XCTAssertFalse(SpinMotion.showsBack(0))
        XCTAssertFalse(SpinMotion.showsBack(.pi / 2 - 0.01))
        XCTAssertTrue(SpinMotion.showsBack(.pi / 2 + 0.01))
        XCTAssertTrue(SpinMotion.showsBack(.pi))
        XCTAssertFalse(SpinMotion.showsBack(2 * .pi))
        XCTAssertTrue(SpinMotion.showsBack(-.pi))
        XCTAssertFalse(SpinMotion.showsBack(-2 * .pi + 0.2))
    }

    /// 離すと近い面に吸い付く（惰性の分だけ先を見る）。裏返しは半周先
    func testSnapAndFlip() {
        XCTAssertEqual(SpinMotion.snapTarget(yaw: 0.5, velocity: 0), 0)
        XCTAssertEqual(SpinMotion.snapTarget(yaw: 2.0, velocity: 0), .pi, accuracy: 1e-9)
        XCTAssertEqual(SpinMotion.snapTarget(yaw: 1.4, velocity: 6), .pi, accuracy: 1e-9, "勢いを見ない")
        XCTAssertEqual(SpinMotion.flipTarget(from: 0), .pi, accuracy: 1e-9)
        XCTAssertEqual(SpinMotion.flipTarget(from: .pi), 2 * .pi, accuracy: 1e-9)
    }

    /// メダルと同じ手触り（幅いっぱいで 1.5π・惰性の上限・減らす設定では弱く）
    func testSameFeelAsMedal() {
        XCTAssertEqual(SpinMotion.yawDelta(dx: 300, width: 300), 1.5 * .pi, accuracy: 1e-9)
        XCTAssertEqual(SpinMotion.releaseVelocity(vx: 1e6, width: 300, reduceMotion: false), SpinMotion.velocityLimit)
        XCTAssertEqual(SpinMotion.releaseVelocity(vx: -1e6, width: 300, reduceMotion: true), -SpinMotion.reducedVelocityLimit)
    }

    /// 光は正面で止まっているときは見えない（端の外）
    func testShineHiddenAtRest() {
        XCTAssertNil(PassTicketShine.stops(at: SpinMotion.shine(0)))
        XCTAssertNil(PassTicketShine.stops(at: SpinMotion.shine(.pi)))
        XCTAssertNotNil(PassTicketShine.stops(at: SpinMotion.shine(.pi / 2)))
    }

    /// 回すと払うの切り分け（きっぷの上はふつう回す・素早く短く払うと次・外で払うと次・減らす設定では回さない）
    func testRotateVersusSwipe() {
        func c(_ t: Double, _ p: Double, _ d: Double, onCard: Bool = true, reduce: Bool = false) -> PassSpinGesture.Outcome {
            PassSpinGesture.classify(translation: t, predicted: p, duration: d, onCard: onCard, reduceMotion: reduce,
                                     swipeDistance: 90)
        }
        XCTAssertEqual(c(-150, -180, 0.6), .rotate, "ゆっくり回したのに次へ進んだ")
        XCTAssertEqual(c(-60, -300, 0.15), .next, "素早く払ったのに回った")
        XCTAssertEqual(c(60, 300, 0.15), .previous)
        XCTAssertEqual(c(-200, -400, 0.2), .rotate, "大きく速く回したら次へ進んだ")
        XCTAssertEqual(c(-120, -120, 0.6, onCard: false), .next, "外で払っても次へ進まない")
        XCTAssertEqual(c(-120, -120, 0.6, reduce: true), .next, "減らす設定で回った")
        XCTAssertEqual(c(-30, -30, 0.6, reduce: true), PassSpinGesture.Outcome.none)
    }

    /// 🔴 0.25 秒を過ぎた瞬間に回りが跳ばない（弱めた回りから少しずつ指の量へ寄せる）
    func testLiveYawDoesNotJump() {
        for dx in [-300.0, -120, 80, 300] {
            var last = PassSpinGesture.liveYaw(base: 0, dx: dx, width: 300, elapsed: 0)
            var e = 0.0
            while e < 0.6 {
                e += 0.005
                let now = PassSpinGesture.liveYaw(base: 0, dx: dx, width: 300, elapsed: e)
                XCTAssertLessThan(abs(now - last), 0.3, "回りが跳んだ（dx \(dx)・\(e) 秒）")
                last = now
            }
            XCTAssertEqual(last, SpinMotion.yawDelta(dx: dx, width: 300), accuracy: 1e-9, "最後は指の量に追いつかない")
        }
    }

    /// 版 2 の特性があれば版 2 を読む（前のアプリの端末は版 1 だけ）
    func testReaderPrefersV2() {
        XCTAssertEqual(PassRadio.characteristicToRead([PassRadio.characteristicUUID, PassRadio.characteristicV2UUID]),
                       PassRadio.characteristicV2UUID)
        XCTAssertEqual(PassRadio.characteristicToRead([PassRadio.characteristicUUID]), PassRadio.characteristicUUID)
        XCTAssertNil(PassRadio.characteristicToRead([]))
    }
}
