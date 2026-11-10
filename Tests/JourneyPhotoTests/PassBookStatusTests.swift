import XCTest
@testable import JourneyPhoto

/// すれちがい帳の頭の1行（札 #519・提案「旅の道具の置き場」第5版の仕様 1・2）。
/// 7 つの状態の字と出す順（オフ ＞ 乗車券なし ＞ Bluetooth がオフ ＞ Bluetooth が許可されていない ＞
/// 距離が分からない ＞ 家の近く ＞ ふだん）、空の状態のボタンが出る条件、画面の配線。
final class PassBookStatusTests: XCTestCase {

    /// ふだんの形（オン・乗車券あり・電波あり・いつでも・すぐ届く）
    private func facts(_ change: (inout PassBookStatus.Facts) -> Void = { _ in }) -> PassBookStatus.Facts {
        var f = PassBookStatus.Facts(enabled: true, ticketChosen: true, bluetoothPoweredOff: false,
                                     bluetoothDenied: false, mode: .always, distanceReasonExists: false,
                                     awayToday: nil, delivery: .instant)
        change(&f)
        return f
    }

    func testTitles() {
        XCTAssertEqual(PassBookStatus.off.title, "すれちがい乗車券はオフです")
        for status in [PassBookStatus.noTicket, .bluetoothOff, .bluetoothNotAllowed, .distanceUnknown, .nearHome,
                       .running(.always, .instant)] {
            XCTAssertEqual(status.title, "すれちがい乗車券はオンです", "\(status)")
        }
    }

    func testDetailTexts() {
        XCTAssertEqual(PassBookStatus.off.detail, "オンにすると、近くにいたアプリの人と乗車券のカードを交換します")
        XCTAssertEqual(PassBookStatus.noTicket.detail, "乗車券を選ぶまで、交換は止まっています")
        XCTAssertEqual(PassBookStatus.bluetoothOff.detail, "Bluetooth がオフのため、交換は止まっています")
        XCTAssertEqual(PassBookStatus.bluetoothNotAllowed.detail, "Bluetooth の使用が許可されていません")
        XCTAssertEqual(PassBookStatus.distanceUnknown.detail, "家からの距離が分からないため、今日は交換しません")
        XCTAssertEqual(PassBookStatus.nearHome.detail, "家の近くなので、今日は交換しません")
        // ふだん:「〈いつ〉 · 〈届き方〉」
        XCTAssertEqual(PassBookStatus.running(.traveling, .instant).detail, "旅のあいだ · すぐ届く")
        XCTAssertEqual(PassBookStatus.running(.always, .evening).detail, "いつでも · 夕方にまとめて")
        XCTAssertEqual(PassBookStatus.running(.foreground, .instant).detail, "開いている間 · すぐ届く")
    }

    /// 上から先に当たったものだけを出す
    func testOrderOfReasons() {
        // 全部当たる形から1つずつ外していくと、仕様の順に出る
        var f = facts {
            $0.enabled = false; $0.ticketChosen = false; $0.bluetoothPoweredOff = true; $0.bluetoothDenied = true
            $0.mode = .traveling; $0.distanceReasonExists = true; $0.awayToday = false
        }
        XCTAssertEqual(PassBookStatus.resolve(f), .off)
        f.enabled = true
        XCTAssertEqual(PassBookStatus.resolve(f), .noTicket)
        f.ticketChosen = true
        XCTAssertEqual(PassBookStatus.resolve(f), .bluetoothOff)
        f.bluetoothPoweredOff = false
        XCTAssertEqual(PassBookStatus.resolve(f), .bluetoothNotAllowed, "許可を断った人が「ふだん」と出る")
        f.bluetoothDenied = false
        XCTAssertEqual(PassBookStatus.resolve(f), .distanceUnknown)
        f.distanceReasonExists = false
        XCTAssertEqual(PassBookStatus.resolve(f), .nearHome)
        f.awayToday = true
        XCTAssertEqual(PassBookStatus.resolve(f), .running(.traveling, .instant))
    }

    /// 距離の訳は「旅のあいだ」のときだけ。今日の分が分からない（nil）のも「分からない」
    func testDistanceOnlyWhileTraveling() {
        XCTAssertEqual(PassBookStatus.resolve(facts { $0.mode = .traveling; $0.awayToday = nil }), .distanceUnknown)
        XCTAssertEqual(PassBookStatus.resolve(facts { $0.mode = .traveling; $0.awayToday = true; $0.distanceReasonExists = true }),
                       .distanceUnknown)
        for mode in [PassExchange.Mode.always, .foreground] {
            XCTAssertEqual(PassBookStatus.resolve(facts { $0.mode = mode; $0.awayToday = false; $0.distanceReasonExists = true }),
                           .running(mode, .instant))
        }
        XCTAssertEqual(PassBookStatus.resolve(facts { $0.delivery = .evening }), .running(.always, .evening))
    }

    /// 空の状態: オフなら主ボタン「説明を読んでオンにする」、オンならボタンを出さない
    func testEmptyStateAction() {
        XCTAssertEqual(PassBookStatus.off.emptyActionTitle, "説明を読んでオンにする")
        XCTAssertEqual(PassBookStatus.off.emptyMessage, "オンにして出かけると、近くにいたアプリの人のカードが届きます。")
        for status in [PassBookStatus.noTicket, .bluetoothOff, .bluetoothNotAllowed, .distanceUnknown, .nearHome,
                       .running(.always, .instant)] {
            XCTAssertNil(status.emptyActionTitle, "オンなのに主ボタンが出る（\(status)）")
            XCTAssertEqual(status.emptyMessage, "出かけると、近くにいたアプリの人のカードが届きます。")
        }
        XCTAssertEqual(PassBookStatus.emptyActionIdentifier, "passBook.emptyTurnOn")
        XCTAssertEqual(PassBookStatus.statusIdentifier, "passBook.status")
    }

    func testHints() {
        XCTAssertEqual(PassBookStatus.hint(fromSettings: false), "すれちがい乗車券の設定を開きます")
        XCTAssertEqual(PassBookStatus.hint(fromSettings: true), "設定に戻ります")
    }

    /// 設定の「いつ」の下の訳と、頭の行の「距離が分からない」が同じ決まり
    func testTravelUnknownReasonIsShared() {
        XCTAssertNotNil(PassSettingsText.travelUnknownReason(homePrefecture: nil, locationAuthorized: true))
        XCTAssertNotNil(PassSettingsText.travelUnknownReason(homePrefecture: "京都府", locationAuthorized: false))
        XCTAssertNil(PassSettingsText.travelUnknownReason(homePrefecture: "京都府", locationAuthorized: true))
    }

    // MARK: - 配線（Linux では描けないので文で確かめる）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    func testBookWiring() throws {
        let book = try source("Features/Pass/PassBookView.swift")
        // 頭の行は板の行（JPRowLabel）を札（JPCard）に1つ。絵は ticket。左右 20・上 14
        XCTAssertTrue(book.contains("JPRowLabel(title: status.title, systemImage: \"ticket\", detail: status.detail)"))
        XCTAssertTrue(book.contains(".buttonStyle(JPRowButtonStyle())"))
        XCTAssertTrue(book.contains("statusRow(status)\n                    .padding(.horizontal, JPSpace.l)\n                    .padding(.top, 14)"))
        // 読み上げ: 名前＝題・値＝2行目・ヒント・識別子
        XCTAssertTrue(book.contains(".accessibilityLabel(status.title)"))
        XCTAssertTrue(book.contains(".accessibilityValue(status.detail)"))
        XCTAssertTrue(book.contains(".accessibilityHint(PassBookStatus.hint(fromSettings: fromSettings))"))
        XCTAssertTrue(book.contains(".accessibilityIdentifier(PassBookStatus.statusIdentifier)"))
        // 頭の行は数の段・空の状態の上（カードがあってもなくても出す）
        let row = try XCTUnwrap(book.range(of: "statusRow(status)\n"))
        let empty = try XCTUnwrap(book.range(of: "if contents.isEmpty {"))
        XCTAssertLessThan(row.lowerBound, empty.lowerBound)
        // 新しく OS の許可を求めない（読むのは今の状態だけ）
        XCTAssertFalse(book.contains("requestAuthorization"))
        XCTAssertFalse(book.contains("CBCentralManager("))
        // 空の状態は共通の EmptyState（帳だけ別に組まない）
        XCTAssertTrue(book.contains("EmptyState(title: L(\"まだカードがありません\", \"No cards yet\"), message: status.emptyMessage,\n                                   actionTitle: actionTitle, actionIdentifier: PassBookStatus.emptyActionIdentifier) {\n                            openSettings(intro: true)"))
        XCTAssertFalse(book.contains("passBook.emptySettings"))
        // 主ボタンは設定を積み、はじめから「オンにする」前の説明を出す
        XCTAssertTrue(book.contains("PassSettingsView(startsWithIntro: settingsIntro)"))
        let settings = try source("Features/Pass/PassSettingsView.swift")
        XCTAssertTrue(settings.contains("var startsWithIntro = false"))
        XCTAssertTrue(settings.contains("guard startsWithIntro, !introOffered else { return }"))
        XCTAssertTrue(settings.contains("guard !Task.isCancelled, !pass.settings.enabled else { return }\n            showIntro = true"))
    }
}
