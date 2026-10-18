import XCTest
@testable import JourneyPhoto

/// 小さなきっぷ（帳の札・ホームの束）を**マルス券の縮小版**にした（2026-10-17）。発と着の字の大きさ・
/// 地と窓と縁を大きい札と同じ決まりで使うこと・写真に手を加えないこと・字の下限を見張る
final class PassMiniTicketTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `PassMiniTicket` の本体（次の struct まで）
    private func miniBody() throws -> String {
        let cards = try source("Features/Pass/PassCards.swift")
        let start = try XCTUnwrap(cards.range(of: "struct PassMiniTicket"))
        let end = try XCTUnwrap(cards.range(of: "struct PassTicketSlot"))
        return String(cards[start.lowerBound..<end.lowerBound])
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func profile(pro: Bool) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data("{\"userId\":\"u1\",\"name\":\"丸田\",\"pro\":\(pro)}".utf8))
    }

    private func content(origin: String, destination: String, face: UInt8?, pro: Bool) throws -> PassCardContent {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"p1\",\"src\":\"/uploads/p1.jpg\",\"userId\":\"u1\"}".utf8))
        let met = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 14))!
        let card = PassEncounter(id: "c", photoId: "p1", note: "", showsFrom: true, metHour: met, deliverAt: met,
                                 placeName: "パリ", placeLat: nil, placeLng: nil, number: 87, opened: false,
                                 ownerId: "u1", originLabel: origin, destinationLabel: destination, face: face)
        return PassCardContent(card: card, photo: photo, owner: try profile(pro: pro), fromPrefecture: "東京都",
                               meetingCount: 1)
    }

    /// 帳の札の幅（3列・小さい iPhone 98 〜 大きい iPhone 120）とホームの束（92）の、区間に使える幅
    private var widths: [Double] {
        [92, 98, 104, 120].map { $0 - Double(PassCardStyle.miniInset) * 2 }
    }

    // MARK: - 区間（発と着の字の大きさ）

    /// 🔴 長い地名・短い地名・Pro の券面のありなしで、発と着は同じ大きさ・矢印は中央・本文系の 12 を割らない
    func testMiniRouteKeepsBothSidesSameSize() throws {
        let pairs = [("東京", "フランス"), ("京都", "大阪"), ("ニューヨーク", "東京"), ("北海道", "沖縄県那覇市"),
                     ("Tokyo", "San Francisco"), ("どこか", "パリ")]
        let styles: [UInt8?] = [nil] + PassTicketFaceStyle.allCases.map(\.rawValue)
        for width in widths {
            for (origin, destination) in pairs {
                var sizes = Set<Double>()
                for style in styles {
                    for pro in [true, false] {
                        let face = try content(origin: origin, destination: destination, face: style, pro: pro)
                            .face(calendar: calendar)
                        let route = PassCardStyle.miniRoute(origin: face.origin, destination: face.destination,
                                                            width: width)
                        sizes.insert(route.fontSize)
                        // 逆向きでも同じ（発と着で別々に縮めない）
                        XCTAssertEqual(route, PassCardStyle.miniRoute(origin: face.destination, destination: face.origin,
                                                                      width: width), "\(origin)→\(destination): 左右で大きさが変わる")
                        XCTAssertEqual(route.arrowCenter, width / 2, accuracy: 1e-9, "矢印が中央に無い")
                        XCTAssertGreaterThanOrEqual(route.fontSize, 12, "区間の字が本文系の 12 を割る")
                        XCTAssertLessThanOrEqual(route.fontSize, PassCardStyle.miniRouteSize)
                        XCTAssertEqual(route.markWidth, 0, "小さなきっぷに入らない「発」「着」の幅を数えている")
                    }
                }
                XCTAssertEqual(sizes.count, 1, "\(origin)→\(destination): 券面で区間の字の大きさが変わる（\(sizes)）")
            }
        }
        // Pro の人の券は特別な券面になっている（上の比べが券面ありなしを本当に比べている）
        let pro = try content(origin: "東京", destination: "フランス", face: PassTicketFaceStyle.urushi.rawValue, pro: true)
        XCTAssertEqual(pro.face(calendar: calendar).style, .urushi)
        let plain = try content(origin: "東京", destination: "フランス", face: PassTicketFaceStyle.urushi.rawValue, pro: false)
        XCTAssertEqual(plain.face(calendar: calendar).style, .mars)
    }

    /// 短い地名は大きく（14）・欄に入りきらない長い地名は 12 まで。字数で片側だけ縮まない
    func testMiniRouteSizeFollowsLongerName() {
        let width = 98 - Double(PassCardStyle.miniInset) * 2
        let short = PassCardStyle.miniRoute(origin: "京都", destination: "大阪", width: width)
        XCTAssertEqual(short.fontSize, PassCardStyle.miniRouteSize, accuracy: 1e-9)
        let long = PassCardStyle.miniRoute(origin: "京都", destination: "ニューヨーク", width: width)
        XCTAssertEqual(long.fontSize, PassCardStyle.miniRouteMinSize, accuracy: 1e-9)
        XCTAssertEqual(long.columnWidth, short.columnWidth, accuracy: 1e-9, "左右の欄の幅が字数で変わる")
        // 3字は帳の札（98）にもホームの束（92）にも 12 で入る（2026-10-17 の画面写真: 束で「どこか」が切れていた）
        for card in [98.0, Double(PassCardStyle.stackSize.width)] {
            let three = PassCardStyle.miniRoute(origin: "京都市", destination: "金沢市",
                                                width: card - Double(PassCardStyle.miniInset) * 2)
            // 字幅の見積もりの外れに 1pt の余裕を持たせる（ぴったりだと「…」で切れ得る）
            XCTAssertLessThanOrEqual(3 * three.fontSize, three.columnWidth - 1, "\(card)pt の札で3字の地名が欄に余裕を持って入らない")
        }
    }

    /// 大きい札の並べ方は変わらない（引数を足しただけ）
    func testLargeRouteUnchanged() {
        let route = PassCardStyle.routeLayout(origin: "東京", destination: "フランス")
        XCTAssertEqual(route.columnWidth, (264 - 56 - 12) / 2, accuracy: 1e-9)
        XCTAssertEqual(route.arrowCenter, 132, accuracy: 1e-9)
    }

    // MARK: - 形（大きい札の部品を使い回す）

    /// 帳の札とホームの束は同じ小さなきっぷ。地・窓・縁・後ろの光は大きい札と同じ部品で、区間は `miniRoute`
    func testSlotAndStackUseMiniTicket() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        let slot = try XCTUnwrap(cards.range(of: "struct PassTicketSlot"))
        let full = try XCTUnwrap(cards.range(of: "struct PassPhotoFullView"))
        let rest = String(cards[slot.lowerBound..<full.lowerBound])
        XCTAssertEqual(rest.components(separatedBy: "PassMiniTicket(face:").count - 1, 2, "帳の札か束が小さなきっぷを使っていない")
        XCTAssertFalse(rest.contains("RemoteImage("), "帳の札・束が写真を自分で描いている（窓の決まりを通らない）")
        XCTAssertFalse(rest.contains("PassTicketPunch"), "前の改札の穴が残っている")
        XCTAssertTrue(try source("Features/Pass/PassHomeSlot.swift").contains("PassMiniStack(faces: cards.prefix(3).map { $0.face() })"),
                      "ホームの束に券面が渡っていない（Pro の券面が束に出ない）")

        let mini = try miniBody()
        for part in ["PassFaceGround(style: face.style, behindText: true)", "PassFaceGround.window(face.style)", "PassFacePhoto(photo: face.photo",
                     ".background { PassTicketGlow(kind: edgeKind, corner: corner) }",
                     ".overlay(PassTicketEdge(kind: edgeKind, corner: corner))",
                     "private var edgeKind: PassTicket.Kind { Self.edgeKind(face.kind, showsName: showsName) }",
                     "PassCardStyle.miniRoute(origin: face.origin, destination: face.destination, width: width)",
                     "Text(PassTicket.headline(.plain))", ".accessibilityLabel(PassTicket.spokenRoute("] {
            XCTAssertTrue(mini.contains(part), "小さなきっぷに \(part) が無い")
        }
        XCTAssertFalse(mini.contains("minimumScaleFactor"), "地名ごとに縮めている（左右がそろわない）")
        // 重い効果は小さな表示で止める（傾き・弧の光・細かい地紋）
        for heavy in ["PassSpecialFace", "PassTiltMotion", "TimelineView", "PassBrassMaterial", "PassLacquerMaterial",
                      "PassLeatherMaterial", "PassPaperMaterial", "drawingGroup"] {
            XCTAssertFalse(mini.contains(heavy), "小さなきっぷに重い効果 \(heavy) がある")
        }
        let faces = try source("Features/Pass/PassFaces.swift")
        let ground = try XCTUnwrap(faces.range(of: "struct PassFaceGround"))
        let swatch = try XCTUnwrap(faces.range(of: "struct PassFaceSwatch"))
        let groundBody = String(faces[ground.lowerBound..<swatch.lowerBound])
        for heavy in ["PassBrassHairline", "PassPaperGrain", "PassGoldDust", "PassLeatherGrain", "TimelineView", "drawingGroup"] {
            XCTAssertFalse(groundBody.contains(heavy), "小さく描く地に細かい地紋・動く光 \(heavy) がある")
        }
        XCTAssertTrue(faces.contains("PassFaceGround(style: style)"), "選ぶ画面の見本が地を別に描いている（写し）")
    }

    /// 🔴 設定した写真は加工しない: 小さなきっぷの写真は `PassFacePhoto` だけ。写真に色・形・ぼかしを付けない
    func testMiniPhotoIsUntouched() throws {
        let mini = try miniBody()
        for banned in [".blur(", ".saturation(", ".grayscale(", ".colorMultiply(", ".hueRotation(", ".contrast(",
                       ".brightness(", ".colorInvert(", ".blendMode(", ".mask(", "DownsampledRemoteImage(", "RemoteImage("] {
            XCTAssertFalse(mini.contains(banned), "小さなきっぷで写真に \(banned) を付けている")
        }
        // 窓は大きい札の窓と同じ位置（マルス券は写真 214・角は窓の決まり）
        XCTAssertEqual(PassFaceGround.window(.mars).height, PassCardStyle.photoHeight)
        XCTAssertEqual(PassFaceGround.window(.mars).width, PassCardStyle.deckSize.width)
        XCTAssertEqual(PassFaceGround.window(.brassPlate), CGRect(x: 14, y: 14, width: 272, height: 196))
        XCTAssertEqual(PassFaceGround.window(.urushi), CGRect(x: 19, y: 19, width: 262, height: 178))
        XCTAssertEqual(PassFaceGround.window(.leather), CGRect(x: 22, y: 22, width: 256, height: 178))
    }

    // MARK: - 字・角・種類

    /// 本文系 12 以上（番号と種類の言葉だけ 11）
    func testMiniTypeSizes() throws {
        XCTAssertGreaterThanOrEqual(PassCardStyle.miniHeadSize, 12)
        XCTAssertGreaterThanOrEqual(PassCardStyle.miniRouteMinSize, 12)
        XCTAssertGreaterThanOrEqual(PassCardStyle.metaSize, 12)
        XCTAssertGreaterThanOrEqual(PassCardStyle.numberSize, 11)
        let mini = try miniBody()
        // 字の大きさは決まった定数だけ（10 などの数を直に書かない）
        XCTAssertNil(mini.range(of: #"size: \d"#, options: .regularExpression), "小さなきっぷに字の大きさを直に書いた")
        XCTAssertNil(mini.range(of: #"fixedSize: \d"#, options: .regularExpression), "小さなきっぷに字の大きさを直に書いた")
    }

    /// 🔴 ホームの束（名前の行なし＝種類の言葉なし）は、縁の色と光だけで種類を伝えない: ふつうの縁で光らせない。
    /// 帳の札（種類の言葉あり）は種類ごとの縁
    func testStackDoesNotTellKindByEdgeAlone() throws {
        for kind in [PassTicket.Kind.first, .again(2), .far(900), .plain] {
            XCTAssertEqual(PassMiniTicket.edgeKind(kind, showsName: false), .plain, "束で種類を縁の色と光だけで伝えている")
            XCTAssertEqual(PassMiniTicket.edgeKind(kind, showsName: true), kind, "帳の札が種類ごとの縁でない")
        }
        let cards = try source("Features/Pass/PassCards.swift")
        let stack = try XCTUnwrap(cards.range(of: "struct PassMiniStack"))
        let full = try XCTUnwrap(cards.range(of: "struct PassPhotoFullView"))
        XCTAssertTrue(cards[stack.lowerBound..<full.lowerBound].contains("showsName: false"), "束に名前の行の判断が渡っていない")
        // 使われなくなった改札の穴は消した・空の枠の角は帳の札と同じ
        XCTAssertFalse(cards.contains("struct PassTicketPunch"))
        let book = try source("Features/Pass/PassBookView.swift")
        XCTAssertTrue(book.contains("RoundedRectangle(cornerRadius: PassCardStyle.miniCorner)"), "空の枠の角が札とそろっていない")
        XCTAssertFalse(book.contains("RoundedRectangle(cornerRadius: 8)"))
    }

    /// 角は板の束（9）。特別な券面は表の角の比で（硬券は小さく・革は大きく）
    func testMiniCorners() {
        XCTAssertEqual(PassMiniTicket.corner(.mars), PassCardStyle.stackCorner)
        XCTAssertLessThan(PassMiniTicket.corner(.foilHard), PassMiniTicket.corner(.mars))
        XCTAssertGreaterThan(PassMiniTicket.corner(.leather), PassMiniTicket.corner(.mars))
    }

    /// 小さな札の頭は「乗車券」だけなので、種類は名前の行の言葉で言う（色や縁だけで伝えない）。ふつうは添えない
    func testMiniKindWords() {
        XCTAssertNil(PassTicket.miniKind(.plain))
        let words = [PassTicket.Kind.first, .again(3), .far(900)].compactMap(PassTicket.miniKind)
        XCTAssertEqual(words.count, 3)
        XCTAssertEqual(Set(words).count, 3, "種類が言葉で見分けられない")
        XCTAssertEqual(PassTicket.miniKind(.again(3)), "3 度目")
        // 種類の言葉は 100pt の札の名前の行に入る長さ（4字まで）
        XCTAssertTrue(words.allSatisfy { $0.count <= 4 })
    }

    /// 読み上げは今と同じ: 帳の札はボタンの名前「〇〇 のカード」・ホームの束は読まない（札のボタンが読む）
    func testSpokenLabelsUnchanged() throws {
        let book = try source("Features/Pass/PassBookView.swift")
        XCTAssertTrue(book.contains("PassTicketSlot(content: content)"))
        XCTAssertTrue(book.contains(".accessibilityLabel(L(\"\\(content.name) のカード\", \"\\(content.name)\\u{2019}s card\"))"))
        let cards = try source("Features/Pass/PassCards.swift")
        let stack = try XCTUnwrap(cards.range(of: "struct PassMiniStack"))
        let full = try XCTUnwrap(cards.range(of: "struct PassPhotoFullView"))
        XCTAssertTrue(cards[stack.lowerBound..<full.lowerBound].contains(".accessibilityHidden(true)"), "束を読み上げている")
        let home = try source("Features/Pass/PassHomeSlot.swift")
        XCTAssertTrue(home.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(home.contains("今日すれちがった \\(cards.count)人のカードを開く"))
    }
}
