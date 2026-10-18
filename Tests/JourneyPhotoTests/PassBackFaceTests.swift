import XCTest
@testable import JourneyPhoto

/// 乗車券の裏も券面で描き分ける（**2026-10-18 札 #306**・板「すれちがい乗車券の裏面」
/// https://claude.ai/artifact/BgPadmCAZRPVjoicuTWyJ7）。裏の券面の決め方・「有効」の欄の行数・裏の字と地の比・
/// 書き方・機能の呼び名（「すれちがい乗車券」）を見張る
final class PassBackFaceTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func profile(pro: Bool?) throws -> UserProfile {
        let flag = pro.map { ",\"pro\":\($0)" } ?? ""
        return try JSONDecoder.api.decode(UserProfile.self, from: Data(
            "{\"userId\":\"u1\",\"name\":\"丸田\"\(flag)}".utf8))
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

    private func root() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 注記の行（`//`）を除いた本文
    private func source(_ path: String) throws -> String {
        let text = try String(contentsOf: root().appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func block(_ text: String, _ name: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: "struct \(name):"), "\(name) が無い")
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\nstruct ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    // MARK: - 裏の券面の決め方

    /// 🔴 届いたカード: 裏の券面は**表と同じ決め方**（`shown`）。Pro と確かめられたときだけ選んだ券面、ほかはマルス券
    func testReceivedBackUsesSameStyleAsFront() throws {
        for pro in [true, false, nil] as [Bool?] {
            for wire in [nil, 0, 1, 2, 3, 4, 5, 200] as [UInt8?] {
                let c = try content(face: wire, owner: try profile(pro: pro))
                let front = c.face(calendar: calendar).style
                let back = c.backFace().style
                XCTAssertEqual(back, front, "Pro \(String(describing: pro))・番号 \(String(describing: wire)) で表と裏が割れる")
                XCTAssertEqual(back, PassTicketFaceStyle.shown(wire: wire, ownerIsPro: pro))
            }
        }
        // 持ち主が分からない（プロフィールが読めない）ならマルス券
        XCTAssertEqual(try content(face: 4, owner: nil).backFace().style, .mars)
    }

    /// 自分の見本・人のトランクの乗車券: 裏は表と同じ券面（`own`・表の style をそのまま渡す）
    func testOwnPreviewBackUsesSameStyle() throws {
        for style in PassTicketFaceStyle.allCases {
            let back = PassTicketBackFace.preview(photoTitle: "霧の朝", note: "", name: "mio", origin: .hidden,
                                                  homePrefecture: nil, style: style)
            XCTAssertEqual(back.style, style)
            XCTAssertEqual(back.styled(.mars).style, .mars, "写しで券面を替えられない")
        }
        XCTAssertEqual(PassTicketBackFace.preview(photoTitle: nil, note: "", name: "mio", origin: .hidden,
                                                  homePrefecture: nil).style, .mars, "既定はマルス券")
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertTrue(pick.contains("origin: originChoice, homePrefecture: pass.homePrefecture, style: shownFace)"),
                      "見本の裏が表と同じ券面（shownFace＝own）を受け取っていない")
        XCTAssertTrue(pick.contains("via: PassTicket.via(L(\"旅先\", \"your trip\")), style: shownFace)"))
        let trunk = try source("Features/Trunk/TheirTrunkView.swift")
        XCTAssertTrue(trunk.contains("origin: choice, homePrefecture: prefecture, style: front.style)"),
                      "人のトランクの乗車券の裏が表の券面を受け取っていない")
        // 回す部品は、念のため表の券面で裏を描く（表と裏が割れない）
        let spin = try source("Features/Pass/PassSpinCard.swift")
        XCTAssertTrue(spin.contains("PassCardBack(face: self.back.styled(front.style),"))
    }

    // MARK: - 「有効」の欄

    /// 🔴 「有効」の値（「ずっと（帳に綴じる）」）は1行では欄に入らない。**この欄だけ2行まで**許し、どの券面の欄の幅でも
    /// 日本語・英語とも2行に収まる（見積もりは本文の字の幅・語の切れ目の余裕 15% つき）。字は縮めない
    func testValidityFieldWrapsToTwoLinesWithoutTruncating() {
        let size = Double(PassCardStyle.backValueSize)
        for text in [PassTicket.validityJa, PassTicket.validityEn] {
            let field = PassTicket.Field(label: "有効", value: text)
            XCTAssertEqual(PassCardStyle.backValueLines(field), 2, "「\(text)」が1行に切られる")
            for style in PassTicketFaceStyle.allCases {
                let width = PassCardStyle.backValueWidth(style)
                let lines = PassCardStyle.estimatedLines(text, size: size, width: width)
                XCTAssertGreaterThan(lines, 1, "「\(text)」は \(style) の欄（\(width)）に1行で入る見積もり——2行を許す訳が無い")
                XCTAssertLessThanOrEqual(lines, 2, "「\(text)」が \(style) の欄（\(width)）に2行でも入らない")
            }
        }
        // ほかの欄は1行のまま（格子の高さを変えない）
        for field in PassTicket.backFields(issuer: "東京の mio.k", section: "9,712 km", count: "はじめて")
            where ![PassTicket.validityJa, PassTicket.validityEn].contains(field.value) {
            XCTAssertEqual(PassCardStyle.backValueLines(field), 1, "\(field.label) が2行になる")
        }
        XCTAssertTrue([PassTicket.validityJa, PassTicket.validityEn].contains(PassTicket.validity))
        // 見積もりの元: 欄の幅（マルス券 126・罫の券面は字下げ・型押しは箱の内側を引く）
        XCTAssertEqual(PassCardStyle.backValueWidth(.mars), 126)
        XCTAssertEqual(PassCardStyle.backValueWidth(.leather), 119)
    }

    /// 画面の書き方: どの裏も欄の値の行数は `backValueLines`、縦は縮めずに伸ばす（`fixedSize`）。行は上でそろえる
    func testBackFieldsUseLineRule() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        let mars = try block(cards, "PassCardBack")
        XCTAssertTrue(mars.contains(".lineLimit(PassCardStyle.backValueLines(field))"), "マルス券の裏の「有効」が切れる")
        let backs = try source("Features/Pass/PassBacks.swift")
        let fields = try block(backs, "PassBackFields")
        XCTAssertTrue(fields.contains(".lineLimit(PassCardStyle.backValueLines(field))"), "特別な券面の裏の「有効」が切れる")
        XCTAssertTrue(fields.contains("HStack(alignment: .top, spacing: gap)"), "2行の欄で格子がずれる")
        for text in [mars, fields] {
            XCTAssertTrue(text.contains(".fixedSize(horizontal: false, vertical: true)"))
            XCTAssertFalse(text.contains("minimumScaleFactor"), "欄の字を縮めている")
        }
    }

    // MARK: - 字と地の比

    /// 🔴 裏で新しく出る地（06 の経緯線の上・10 の綿紙・26 の型押し）の字も 4.5 以上（`PassFacePalette.pairs`）
    func testBackTextContrast() {
        let backs = PassFacePalette.pairs.filter { $0.name.hasPrefix("裏 ") }
        XCTAssertGreaterThanOrEqual(backs.count, 9, "裏の組が足りない")
        for name in ["裏 06 注記", "裏 06 帯の字", "裏 10 注記", "裏 26 ラベル", "裏 26 値", "裏 26 箔の暗い所", "裏 26 番号"] {
            XCTAssertTrue(backs.contains { $0.name.hasPrefix(name) }, "\(name) を測っていない")
        }
        for pair in backs {
            let ratio = BrandPalette.contrast(pair.text, pair.ground)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(pair.name) が \(String(format: "%.2f", ratio))")
        }
        // 型押しの地は革より暗い（明るい字の比が上がる側）
        XCTAssertLessThan(BrandPalette.contrast(PassFacePalette.debossGround, 0x000000),
                          BrandPalette.contrast(PassFacePalette.leather, 0x000000))
    }

    // MARK: - 書き方

    /// 裏はマルス券ならこれまでどおり、ほかは券面ごとの裏。地は表と同じ素材の View・画像は使わない
    func testBackSwitchesByStyleAndReusesMaterials() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        let back = try block(cards, "PassCardBack")
        XCTAssertTrue(back.contains("if face.style == .mars {\n                marsBack"))
        XCTAssertTrue(back.contains("PassSpecialBack(face: face, shine: shine, visible: visible)"))
        let backs = try source("Features/Pass/PassBacks.swift")
        for (name, material) in [("PassBrassPlateBack", "PassBrassMaterial(light: light)"),
                                 ("PassGreatCircleBack", "PassRouteMaterial()"),
                                 ("PassFoilHardBack", "PassPaperMaterial()"),
                                 ("PassUrushiBack", "PassLacquerMaterial(light: light, dust: false)"),
                                 ("PassLeatherBack", "PassLeatherMaterial(light: light)")] {
            let view = try block(backs, name)
            XCTAssertTrue(view.contains(material), "\(name) が表の素材（\(material)）を使っていない")
            XCTAssertTrue(view.contains("PassBackLayout(face: face, ink:"), "\(name) が共通の並びを使っていない")
        }
        for word in ["Image(", "UIImage", "AsyncImage", "DownsampledRemoteImage"] {
            XCTAssertFalse(backs.contains(word), "裏に画像（\(word)）を使っている")
        }
        // 飾りは空きの中だけ（字の下に敷かない）
        let layout = try block(backs, "PassBackLayout<BandGround")
        let body = try XCTUnwrap(layout.components(separatedBy: "var body: some View {").last)
        XCTAssertTrue(body.contains("PassBackOrnamentSpace(minHeight: ornamentMinHeight) { ornament }"))
        XCTAssertEqual(body.components(separatedBy: "{ ornament }").count - 1, 1, "飾りを空きの外にも置いている")
        XCTAssertEqual(body.components(separatedBy: "ornament").count - 1, 2, "飾りを空きの外にも置いている")
    }

    /// 飾りは空きが飾りの高さ以上のときだけ
    func testOrnamentShowsOnlyWhenRoomIsEnough() {
        XCTAssertTrue(PassBackOrnamentSpace<PassHirame>.shows(height: 72, minHeight: 72))
        XCTAssertFalse(PassBackOrnamentSpace<PassHirame>.shows(height: 40, minHeight: 64))
        XCTAssertTrue(PassBackOrnamentSpace<PassHirame>.shows(height: 0, minHeight: 0))
    }

    /// 21 の蒔絵（2026-10-18 owner: すやり霞は「好きではない」・すすきは「余計」）: 右下の隅の平目地だけ。
    /// 粒は 140×64 の中で、右下の4分の1に半分より多く寄る
    func testUrushiOrnamentIsCornerDustOnly() throws {
        let size = PassHirame.size
        let dots = PassFaceTextures.hirameDots
        XCTAssertTrue(dots.contains { $0.bright } && dots.contains { !$0.bright }, "明るい粒と淡い粒がそろっていない")
        for dot in dots {
            XCTAssertTrue(dot.x - dot.r >= -1 && dot.x + dot.r <= size.width + 1
                          && dot.y - dot.r >= -1 && dot.y + dot.r <= size.height + 1, "粒が箱の外（\(dot)）")
        }
        let backs = try source("Features/Pass/PassBacks.swift")
        for gone in ["PassKasumi", "PassMakieSusuki", "addCurve"] {
            XCTAssertFalse(backs.contains(gone), "外した飾り（\(gone)）が残っている")
        }
        XCTAssertTrue(try block(backs, "PassUrushiBack").contains("PassHirame()"))
        XCTAssertTrue(try block(backs, "PassHirame").contains("alignment: .bottomTrailing"), "右下の隅に寄せていない")
        XCTAssertEqual(PassFaceTextures.hirameDots.count, PassFaceTextures.hirameCount, "粒が足りない")
        XCTAssertGreaterThan(PassFaceTextures.hirameCorner * 2, PassFaceTextures.hirameCount, "隅に寄っていない")
    }

    // MARK: - 呼び名

    /// 🔴 機能の呼び名は「すれちがい乗車券」（英語「Pass tickets」）。**古い呼び名「すれちがい」単独**（設定の行・題・
    /// 「すれちがいをオンに」「すれちがいの設定」など）が利用者に見える文に残っていない。
    /// 出来事の言い方（「すれちがった人」「はじめてのすれちがい」）と「すれちがい帳」はそのまま
    func testFeatureNameIsUnified() throws {
        XCTAssertTrue(["すれちがい乗車券", "Pass tickets"].contains(PassTicket.featureName))
        let forbidden = try NSRegularExpression(pattern:
            "\"すれちがい\"|「すれちがい」|すれちがい(を|が|は)(オン|オフ|止)|すれちがいの(設定|乗車券|カード)"
            // 英語: 前の呼び名「Pass」単独（「見送る」の Pass は別の語なので、すれちがいの文と組のものだけ見る）
            + "|\"すれちが[^\"]*\", \"Pass\"|Turn on Pass(?! ticket)|With Pass turned|Pass is (off|paused)"
            + "|Settings → Pass\"|\"Pass settings\"")
        let base = root().appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { ["swift", "strings", "json"].contains($0.pathExtension) } ?? []
        XCTAssertGreaterThan(files.count, 100)
        var found: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // 注記・サーバーへ送る印（通報の本文の見出し・利用者の画面には出ない）は除く
                if trimmed.hasPrefix("//") || line.contains("passNoteMarker") { continue }
                let range = NSRange(line.startIndex..., in: line)
                if forbidden.firstMatch(in: line, range: range) != nil {
                    found.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        XCTAssertEqual(found, [], "古い呼び名が残っている")
        // 設定の行・画面の題・オンにする説明の眉ラベルは同じ呼び名
        let settings = try source("Features/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains("section(PassTicket.featureName)"))
        XCTAssertTrue(settings.contains("JPRowLabel(title: PassTicket.featureName,"))
        let pass = try source("Features/Pass/PassSettingsView.swift")
        XCTAssertEqual(pass.components(separatedBy: "PassTicket.featureName").count - 1, 3)
    }
}
