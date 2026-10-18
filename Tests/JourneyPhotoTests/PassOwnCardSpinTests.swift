import XCTest
@testable import JourneyPhoto

/// 自分のカードも指で回す・区間の発と着の釣り合い（2026-10-16 owner の頼み）
final class PassOwnCardSpinTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Sources の Swift を全部（注記を除いて）
    private func allSources() throws -> [(String, String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var out: [(String, String)] = []
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let path = String(url.path.dropFirst(root.path.count + 1))
            out.append((path, try source(path)))
        }
        return out
    }

    // MARK: - 区間の釣り合い

    /// 🔴 「東京 → フランス」: 発・着は同じ大きさ（長い方＝4 字が欄に収まる大きさ）・矢印は並びの中央
    func testRouteLayoutSharesOneSizeAndCentersArrow() {
        let route = PassCardStyle.routeLayout(origin: "東京", destination: "フランス")
        XCTAssertEqual(route.fontSize, (PassCardStyle.routeColumnWidth - route.markWidth) / 4, accuracy: 1e-9,
                       "長い方（と「発」「着」）に合わせていない")
        XCTAssertLessThan(route.fontSize, PassCardStyle.routeSize)
        XCTAssertEqual(route, PassCardStyle.routeLayout(origin: "フランス", destination: "東京"), "左右で大きさが変わる")
        XCTAssertEqual(route.arrowCenter, PassCardStyle.routeWidth / 2, accuracy: 1e-9, "矢印が中央にない")
        XCTAssertEqual(route.columnWidth * 2 + PassCardStyle.arrowWidth + PassCardStyle.arrowGap * 2,
                       PassCardStyle.routeWidth, accuracy: 1e-9, "左右の欄が同じ幅で並びを埋めない")
        // 4 字の欄に 4 字と「着」が入る
        XCTAssertLessThanOrEqual(PassCardStyle.routeEms("フランス") * route.fontSize + route.markWidth,
                                 route.columnWidth + 1e-9)
    }

    /// 区間の地名は**別々に縮めない**（`minimumScaleFactor` があると、収まる側だけが縮んで左右がそろわない。
    /// 2026-10-17 の Mac の画面写真で「東京」だけが 12pt まで縮んだ）
    func testRouteNamesDoNotShrinkSeparately() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        guard let start = cards.range(of: "private func routeName(") else { return XCTFail("routeName が無い") }
        let body = String(cards[start.lowerBound...].prefix(600))
        XCTAssertFalse(body.contains("minimumScaleFactor"), "発・着が別々に縮み、大きさがそろわなくなる")
        XCTAssertTrue(body.contains("fixedSize: CGFloat(route.fontSize)"), "発・着が同じ大きさで描かれていない")
    }

    /// 短い地名は大きいまま（30）・上限いっぱい（6 字）でも 15 を割らない・長すぎても 15 で止める
    func testRouteLayoutBounds() {
        XCTAssertEqual(PassCardStyle.routeLayout(origin: "札幌", destination: "京都").fontSize, PassCardStyle.routeSize)
        let six = String(repeating: "雪", count: PassExchange.labelLimit)
        let full = PassCardStyle.routeLayout(origin: six, destination: "京都")
        XCTAssertGreaterThanOrEqual(full.fontSize, PassCardStyle.routeMinSize)
        XCTAssertLessThanOrEqual(PassCardStyle.routeEms(six) * full.fontSize + full.markWidth, full.columnWidth + 1e-9,
                                 "6 字と「発」が欄に収まらない")
        let long = PassCardStyle.routeLayout(origin: "どこかから", destination: "サントリーニ島イアの町はずれ")
        XCTAssertEqual(long.fontSize, PassCardStyle.routeMinSize, accuracy: 1e-9)
        XCTAssertEqual(PassCardStyle.routeLayout(origin: "", destination: "").fontSize, PassCardStyle.routeSize)
        // 欧文は和文より狭く数える（「Somewhere」9 字でも和文 9 字ほど小さくしない）
        XCTAssertLessThan(PassCardStyle.routeEms("Somewhere"), 9)
        XCTAssertEqual(PassCardStyle.routeEms("東京"), 2)
    }

    /// 🔴 表の区間は、発・着とも同じ `routeLayout` の大きさ・同じ幅の欄で描く（別々に縮めない）
    func testFrontUsesSharedRouteLayout() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        for part in ["let route = PassCardStyle.routeLayout(origin: face.origin, destination: face.destination)",
                     "routeColumn(face.origin, mark: PassTicket.originMark, route)\n                .frame(width: CGFloat(route.columnWidth), alignment: .trailing)",
                     "routeColumn(face.destination, mark: PassTicket.destinationMark, route)\n                .frame(width: CGFloat(route.columnWidth), alignment: .leading)",
                     "routeName(text, route)",
                     ".font(.custom(JPFont.displayName, fixedSize: CGFloat(route.fontSize)))"] {
            XCTAssertTrue(cards.contains(part), "区間の描き方が違う: \(part)")
        }
        XCTAssertFalse(cards.contains("PassCardStyle.routeMinScale"), "発・着が別々に縮む")
        XCTAssertFalse(cards.contains("Spacer(minLength: CGFloat(PassCardStyle.arrowGap))"), "矢印が字数で中央からずれる")
    }

    // MARK: - 回す部品の共有

    /// 🔴 自分のカードの見本も、届いたカードと同じ `PassSpinTicket`・同じ手つき（`PassSpinDrag`）で回す。写しを作らない
    func testOwnCardSharesSpinTicket() throws {
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertTrue(pick.contains("PassSpinCard(front: previewFace, back: previewBack"), "自分のカードが回る部品を使っていない")
        XCTAssertFalse(pick.contains("PassCardFront(face: previewFace)"), "自分のカードが表だけの止まった絵のまま")
        let spin = try source("Features/Pass/PassSpinCard.swift")
        for part in ["PassSpinTicket(yaw: yaw, front: front, back: back, reduceMotion: reduceMotion, active: active)",
                     "@State private var spin = PassSpinDrag()", ".simultaneousGesture(", "spin.lockAxis(",
                     "spin.liveYaw(", "SpinMotion.snapTarget(", ".accessibilityAction { flip() }",
                     "PassSpinTicket.spokenSide(yaw)", "\"pass.pick.flip\"",
                     ".rotation3DEffect(.radians(reduceMotion ? 0 : yaw)",
                     "let shine: Double? = reduceMotion ? nil : SpinMotion.shine(yaw)",
                     ".allowsHitTesting(!back)", ".allowsHitTesting(back)", ".accessibilityHidden(!back)"] {
            XCTAssertTrue(spin.contains(part), "回す部品に \(part) が無い")
        }
        // 読み上げの名前で上書きしない（中身＝裏のひとことが読まれなくなる）
        XCTAssertFalse(spin.contains(".accessibilityLabel(spokenName)"))
        let viewer = try source("Features/Pass/PassViewerView.swift")
        for part in ["PassSpinTicket(yaw: yaw, front: content.face(), back: content.backFace()",
                     "@State private var spin = PassSpinDrag()", "spin.liveYaw(", "spin.end()",
                     "PassSpinTicket.spokenSide(yaw)"] {
            XCTAssertTrue(viewer.contains(part), "束の画面に \(part) が無い")
        }
        // 写しが無い: 回す部品・裏の部品・3D の回りはそれぞれ1か所だけ
        let all = try allSources()
        func count(_ needle: String) -> Int { all.reduce(0) { $0 + $1.1.components(separatedBy: needle).count - 1 } }
        XCTAssertEqual(count("struct PassSpinTicket"), 1)
        XCTAssertEqual(count("PassCardBack(face:"), 1, "裏を回す部品の外でも描いている（写し）")
        XCTAssertEqual(count(".rotation3DEffect(.radians(reduceMotion ? 0 : yaw)"), 1, "回す描き方の写しがある")
        XCTAssertEqual(count("PassSpinGesture.liveYaw("), 1, "手つきの写しがある（`PassSpinDrag` を通す）")
    }

    /// ScrollView の中: 最初に動いた向きで決め、横（たての 1.2 倍を越える）ときだけ回す
    func testAxisDecidesTurnOrScroll() {
        XCTAssertEqual(PassSpinGesture.axis(dx: 30, dy: 5), .horizontal)
        XCTAssertEqual(PassSpinGesture.axis(dx: -30, dy: 10), .horizontal)
        XCTAssertEqual(PassSpinGesture.axis(dx: 10, dy: 30), .vertical, "たての送りで回った")
        XCTAssertEqual(PassSpinGesture.axis(dx: 20, dy: 20), .vertical, "斜めの指で回った")
        var drag = PassSpinDrag()
        XCTAssertEqual(drag.lockAxis(dx: 2, dy: 20), .vertical)
        XCTAssertEqual(drag.lockAxis(dx: 200, dy: 20), .vertical, "途中で向きが変わった（送りながら回り出す）")
        _ = drag.end()
        XCTAssertNil(drag.axis)
        XCTAssertEqual(drag.lockAxis(dx: 40, dy: 3), .horizontal)
    }

    /// 手つきの覚え: 置いた時の回りを覚え（2回目は上書きしない）、離したら忘れる
    func testSpinDragRemembersBase() {
        var drag = PassSpinDrag()
        let t0 = Date(timeIntervalSince1970: 1000)
        drag.begin(yaw: .pi, now: t0)
        drag.begin(yaw: 0, now: t0.addingTimeInterval(0.3))
        XCTAssertEqual(drag.baseYaw, .pi)
        // 置いてすぐは束の画面と同じ弱めた回り
        XCTAssertEqual(drag.liveYaw(current: 3, dx: -150, width: 300, now: t0.addingTimeInterval(0.1)),
                       PassSpinGesture.liveYaw(base: .pi, dx: -150, width: 300, elapsed: 0.1), accuracy: 1e-9)
        let (duration, base) = drag.end(now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(duration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(base, .pi)
        XCTAssertNil(drag.startAt)
        XCTAssertNil(drag.baseYaw)
    }

    /// 読み上げの面の名前
    func testSpokenSide() {
        XCTAssertEqual(PassSpinTicket.spokenSide(0), "表")
        XCTAssertEqual(PassSpinTicket.spokenSide(.pi), "裏")
    }

    // MARK: - 自分のカードの裏

    /// 見本の裏は相手に届く形: 連絡先の形のひとことは載らない・居住地は「居住地から」のときだけ・区間と回数は「—」
    func testOwnBackPreview() {
        let home = PassTicketBackFace.preview(photoTitle: "霧の朝", note: "  霧の朝が好き  ", name: "mio",
                                              origin: .home, homePrefecture: "北海道")
        XCTAssertEqual(home.title, "霧の朝")
        XCTAssertEqual(home.note, PassExchange.cleanNote("  霧の朝が好き  "))
        XCTAssertEqual(home.issuer, PassTicket.issuer(name: "mio", prefecture: "北海道"))
        XCTAssertEqual(home.section, PassTicket.sectionLabel(nil))
        XCTAssertEqual(home.count, PassTicket.countLabel(.plain, meetingCount: nil))
        XCTAssertEqual(home.kind, .plain)
        let custom = PassTicketBackFace.preview(photoTitle: nil, note: "連絡は mio@example.com へ", name: "mio",
                                                origin: .custom, homePrefecture: "北海道")
        XCTAssertEqual(custom.note, "", "連絡先の形のひとことを見本に出した（相手には届かない）")
        XCTAssertEqual(custom.issuer, "mio", "自分で書いた発なのに居住地を出した")
        XCTAssertFalse(custom.title.isEmpty)
    }

    /// 届いたカードの裏は前と同じ中身（記録から作る）
    func testReceivedBackFace() throws {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"p1\",\"src\":\"/uploads/p1.jpg\",\"userId\":\"u1\"}".utf8))
        let card = PassEncounter(id: "c", photoId: "p1", note: "電話 090-1234-5678", showsFrom: true, metHour: Date(),
                                 deliverAt: Date(), placeName: "京都市", placeLat: nil, placeLng: nil, number: 3,
                                 opened: false, ownerId: "u1")
        let content = PassCardContent(card: card, photo: photo, owner: nil, fromPrefecture: "北海道", meetingCount: 2)
        let back = content.backFace()
        XCTAssertEqual(back.title, photo.displayTitle)
        XCTAssertEqual(back.note, "", "連絡先の形のひとことを出した")
        XCTAssertTrue(back.noteHidden, "伏せたと言わない")
        XCTAssertEqual(back.count, PassTicket.countLabel(.again(2), meetingCount: 2))
        XCTAssertEqual(back.issuer, PassTicket.issuer(name: content.name, prefecture: "北海道"))
    }
}
