import XCTest
@testable import JourneyPhoto

/// v2 の第9・10段（Pro と設定・アカウント）の見た目の決まり（Artifact「デザインシステム v2」の板・2026-10-14）。
///
/// 画面は Linux では描けないので、**値は数で**、**作りは元のファイルを読んで**見張る（`DesignFoundationTests` と
/// 同じやり方）。読むときは型・関数の範囲に絞り、呼び出しの**順**まで見る。
/// owner の好み（CLAUDE.md）が板より先: 写真のある画面の主ボタンは白・写真の無い画面は真鍮の塗り＋墨、
/// 退会の警告は赤 8%／30%、パスワードの「目のボタン」は足さない。
final class V2SettingsProTests: XCTestCase {

    // MARK: - 読む道具

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `start` から `end` までの文字（1つの関数・型の中だけを見る）
    private func slice(_ text: String, from start: String, to end: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let a = text.range(of: start) else {
            XCTFail("「\(start)」が無い", file: file, line: line)
            return ""
        }
        // 終わりの目印が無ければ落とす（注記の行は読む前に除いてあるので、注記を目印にすると黙って最後まで読む）
        guard let b = text.range(of: end, range: a.upperBound..<text.endIndex) else {
            XCTFail("「\(start)」の後に「\(end)」が無い", file: file, line: line)
            return ""
        }
        return String(text[a.lowerBound..<b.lowerBound])
    }

    /// `parts` がこの順に `text` に現れる（並びの入れ替え・呼び出しの削除で落ちる）
    private func assertInOrder(_ parts: [String], in text: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for part in parts {
            guard let found = text.range(of: part, range: cursor..<text.endIndex) else {
                XCTFail("\(what): 「\(part)」が無いか、順が違う", file: file, line: line)
                return
            }
            cursor = found.upperBound
        }
    }

    /// `top` を `alpha` の濃さで `bottom` に重ねた色
    private func blend(_ top: UInt32, alpha: Double, over bottom: UInt32) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let t = Double((top >> shift) & 0xFF), b = Double((bottom >> shift) & 0xFF)
            return UInt32((t * alpha + b * (1 - alpha)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    // MARK: - 設定（板 Settings）

    /// 節の見出しは真鍮の眉ラベル＋札。v1 の白 60% の小さい見出しを残さない。節の間は物差しの 32
    func testSettingsGroupsUseBrassEyebrowAndCard() throws {
        let settings = try source("Features/Settings/SettingsView.swift")
        let group = slice(settings, from: "struct SettingsGroup", to: "struct SettingsActionLabel")
        assertInOrder(["Text(title)", ".jpEyebrow()", ".foregroundStyle(WebTheme.accent)",
                       ".accessibilityAddTraits(.isHeader)", "JPCard { content }"], in: group, "設定の節")
        XCTAssertTrue(settings.contains("SettingsGroup(title) { content() }"), "設定の節が SettingsGroup を通らない")
        XCTAssertFalse(settings.contains("JPSectionTitle("), "設定に v1 の白い小見出しが残っている")
        XCTAssertEqual(SettingsLayout.sectionSpacing, JPSpace.section)
        XCTAssertEqual(SettingsLayout.headerSpacing, JPSpace.xs)

        let pro = try source("Features/Pro/ProSettingsSection.swift")
        XCTAssertTrue(pro.contains("SettingsGroup(\"Pro\") {"), "Pro の節が真鍮の眉ラベルの節でない")
        XCTAssertFalse(pro.contains("JPSectionTitle("))
    }

    /// 行の絵を外した（Pro の行の Pro マークだけ残す）。保存した旅の行は件数と容量を右の値に
    func testSettingsRowsHaveNoIconsExceptTheProMark() throws {
        let settings = try source("Features/Settings/SettingsView.swift")
        XCTAssertFalse(settings.contains("systemImage: \""), "設定の行に絵が残っている")
        XCTAssertFalse(settings.contains("iconColor:"), "アカウントの削除がまだ絵だけ赤")
        let pro = try source("Features/Pro/ProSettingsSection.swift")
        XCTAssertFalse(pro.contains("ProIconView("), "Pro の節の行に線の絵が残っている")
        XCTAssertTrue(pro.contains("icon: AnyView(ProMark(style: .iris, side: ProSettingsLayout.markSide))"))
        // 行の絵の箱（24）に収まり、羽根の線のある大きい版で出る
        XCTAssertLessThanOrEqual(ProSettingsLayout.markSide, 24)
        XCTAssertFalse(ProMarkFit.isSmall(side: ProSettingsLayout.markSide))
        let light = try source("Features/Pro/LightAlertSettingsRows.swift")
        XCTAssertFalse(light.contains("ProIconView("), "光と天気の知らせの行に線の絵が残っている")
        let offline = try source("Features/Trips/OfflineSavedView.swift")
        let row = slice(offline, from: "struct OfflineSavedSettingsRow", to: "\n}\n")
        XCTAssertTrue(row.contains("value: OfflineTripText.settingsDetail("), "保存した旅の件数が右の値でない")
        XCTAssertFalse(row.contains("icon:"), "保存した旅の行に絵が残っている")
    }

    /// アカウントの削除は名前ごと危険の色・矢印あり。控えを空にするは真鍮の字
    func testDangerAndActionRows() throws {
        let settings = try source("Features/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains(
            "SettingsActionLabel(title: L(\"アカウントの削除\", \"Delete account\"), color: WebTheme.danger,\n                                        chevron: true)"),
            "アカウントの削除の名前が危険の色でない")
        XCTAssertTrue(settings.contains("SettingsActionLabel(title: L(\"控えを空にする\", \"Clear cache\"), color: WebTheme.accent)"))
        let label = slice(settings, from: "struct SettingsActionLabel", to: "\n}\n")
        assertInOrder(["Text(title)", ".foregroundStyle(color)", ".frame(minHeight: 54)"], in: label, "色の行")
        // 系統の赤（role: .destructive の無指定）を画面の行に出さない
        XCTAssertFalse(settings.contains("role: .destructive"))
        // 危険の色は黒地の札の上で 4.5:1 を超える
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(BrandPalette.danger, BrandPalette.surface), 4.5)
    }

    /// 「通知がオフのため届きません」の帯: 地は brass-soft、説明も真鍮 85%（帯の上で 4.5:1 以上）
    func testLightAlertNoticeBand() throws {
        let rows = try source("Features/Pro/LightAlertSettingsRows.swift")
        let band = slice(rows, from: "private func pushNoticeRow", to: "private func fixPush")
        assertInOrder(["Text(notice.detail)",
                       ".foregroundStyle(WebTheme.accent.opacity(LightAlertSettingsStyle.noticeDetailOpacity))",
                       ".foregroundStyle(WebTheme.accent)", ".frame(maxWidth: .infinity, minHeight: 54",
                       ".background(WebTheme.accentSoft)"], in: band, "通知が届かない帯")
        XCTAssertEqual(LightAlertSettingsStyle.noticeDetailOpacity, 0.85)
        let detail = blend(BrandPalette.accent, alpha: LightAlertSettingsStyle.noticeDetailOpacity, over: BrandPalette.accentSoft)
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(detail, BrandPalette.accentSoft), 4.5)
    }

    // MARK: - Pro の案内（板 Paywall）

    func testPaywallValuesAndWhitePrimary() throws {
        XCTAssertEqual(ProPaywallStyle.heroHeight, 300)
        XCTAssertEqual(ProPaywallStyle.heroFade, 160)
        XCTAssertEqual(ProPaywallStyle.contentOverlap, 40)
        XCTAssertEqual(ProPaywallStyle.purchaseStyle, .primary, "写真のある画面の主ボタンは白（CLAUDE.md）")
        // 眉ラベルは写真が黒へ溶ける帯に乗るので白 88%（真鍮は黒地の上だけ・CLAUDE.md・2026-10-14 判断）

        let view = try source("Features/Pro/PaywallView.swift")
        let content = slice(view, from: "private var content: some View", to: "private func benefitRow")
        assertInOrder(["Text(\"JOURNEY PHOTO PRO\")", ".jpEyebrow()", ".foregroundStyle(Color.white.opacity(0.88))"],
                      in: content, "案内の眉ラベル（写真の溶けの上は白）")
        let benefit = slice(view, from: "private func benefitRow", to: "private var plans: some View")
        assertInOrder(["ProIconView(icon: benefit.icon, side: ProPaywallStyle.benefitIconSide, color: WebTheme.accent",
                       ".font(JPFont.bodyEmphasis)", ".font(JPFont.footnote)", ".foregroundStyle(WebTheme.text2)"],
                      in: benefit, "利点の行")
        XCTAssertFalse(benefit.contains("RoundedRectangle"), "利点の絵に v1 の箱が残っている")
        let card = slice(view, from: "private func planCard", to: "private var purchaseButton")
        assertInOrder([".foregroundStyle(WebTheme.text3)", "JPFont.number(JPTypeScale.figureMedium",
                       "on ? ProPaywallStyle.selectedPlanFill : Color.clear",
                       ".strokeBorder(on ? WebTheme.accent : WebTheme.line",
                       "lineWidth: on ? JPStroke.emphasis : JPStroke.hairline"], in: card, "プランの札")
        XCTAssertTrue(card.contains(".accessibilityAddTraits(on ? [.isSelected] : [])"), "選んだ札を縁の色だけで伝えている")
        XCTAssertTrue(view.contains(".jpPillButton(ProPaywallStyle.purchaseStyle)"))
        let close = slice(view, from: "private var closeButton", to: "\n    }\n}")
        XCTAssertTrue(close.contains(".jpGlass(in: Circle())"), "閉じるがガラスの丸でない")
        // 審査の決まり（規約・プライバシー・復元）は残す
        XCTAssertTrue(view.contains("paywall.restore"))
        XCTAssertTrue(view.contains("openURL(LegalConsent.privacyURL)"))
    }

    // MARK: - サポーター証・初期ユーザー章（板 SupporterCard・FoundingGift）

    func testSupporterCardScreen() throws {
        XCTAssertEqual(SupporterCardScreen.tilt.x, 6)
        XCTAssertEqual(SupporterCardScreen.tilt.y, -8)
        XCTAssertEqual(SupporterCardScreen.yearMedalSide, 92)
        XCTAssertEqual(SupporterCardScreen.notReachedOpacity, 0.4)
        let view = try source("Features/Pro/SupporterCardView.swift")
        let screen = slice(view, from: "struct SupporterCardView", to: "struct SupporterCardViewer")
        XCTAssertTrue(screen.contains(".background { WebTheme.background.ignoresSafeArea() }"), "地が黒でない")
        XCTAssertFalse(screen.contains("SupporterCardStyle.background"), "画面の地に v1 のグラデーションが残っている")
        XCTAssertTrue(screen.contains(".navigationTitle(L(\"サポーター証\", \"Supporter card\"))"))
        // 傾きは視差効果を減らす人には付けない
        XCTAssertTrue(screen.contains(".rotation3DEffect(.degrees(reduceMotion ? 0 : SupporterCardScreen.tilt.x)"))
        XCTAssertTrue(screen.contains(".rotation3DEffect(.degrees(reduceMotion ? 0 : SupporterCardScreen.tilt.y)"))
        // まだの年: 絵は 40%、字は text-3（字は薄めない）
        let medal = slice(screen, from: "private func yearMedal", to: "\n}\n")
        assertInOrder([".opacity(reached ? 1 : SupporterCardScreen.notReachedOpacity)",
                       "Text(SupporterText.yearLabel(year))",
                       ".foregroundStyle(reached ? WebTheme.text : WebTheme.text3)"], in: medal, "続けた年のメダル")
        // 手に取って回す全画面（3D）はそのまま
        let viewer = slice(view, from: "struct SupporterCardViewer", to: "enum SupporterCardStyle")
        XCTAssertTrue(viewer.contains(".background { SupporterCardStyle.background.ignoresSafeArea() }"))
        XCTAssertTrue(viewer.contains("MedalCoinView(textures: textures, fallbackImage: \"supporter-card-front\""))
    }

    func testFoundingGiftBrassPrimaryAndGlow() throws {
        XCTAssertEqual(FoundingGiftLayout.acceptStyle, .accent, "写真の無い画面の主ボタンは真鍮の塗り＋墨")
        XCTAssertEqual(FoundingGiftLayout.titleSize, 30)
        XCTAssertEqual(FoundingGiftLayout.glowDiameter, 360)
        XCTAssertEqual(FoundingGiftLayout.glowOpacity, 0.22)
        let view = try source("Features/Profile/FoundingGiftView.swift")
        assertInOrder(["Image(BadgeCatalog.largeImage(\"earlyUser\", tier: 1))", "RadialGradient(colors: [WebTheme.accent.opacity",
                       "Text(\"FOR OUR FIRST MEMBERS\")", ".jpEyebrow()",
                       ".font(JPFont.display(FoundingGiftLayout.titleSize",
                       ".jpPillButton(FoundingGiftLayout.acceptStyle)",
                       "Text(L(\"あとで\", \"Later\"))", ".frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)"],
                      in: view, "初期ユーザー章を贈る画面")
        XCTAssertFalse(view.contains("buttonText"), "主ボタンの字が土台の墨でない")
    }

    // MARK: - 光と天気の知らせ（板 LightAlert）

    func testLightForecastCards() throws {
        // 見本の札（`LightForecastText.sample`）で、2行目が「いつ · 天気」になる（v1 は天気を右上に分けていた）
        let now = Date(timeIntervalSince1970: 1_791_514_800)  // 2026-10-09 12:00 JST
        let cards = LightForecastText.cards(LightForecastText.sample(now: now), now: now)
        XCTAssertFalse(cards.isEmpty)
        for card in cards {
            XCTAssertEqual(LightForecastStyle.whenLine(card), card.when + " · " + card.weather)
        }
        XCTAssertEqual(LightForecastStyle.bestBorder, 1.5)
        XCTAssertGreaterThanOrEqual(LightForecastStyle.directionsMinWidth, WebTheme.minTapTarget)

        let view = try source("Features/Pro/LightForecastView.swift")
        XCTAssertTrue(view.contains("JPEyebrowLine(L(\"行きたい場所の光（今週）\""), "眉ラベルに消えていく線が無い")
        let cardView = slice(view, from: "private func cardView", to: "private func chanceChip")
        assertInOrder(["Text(card.name)", ".font(JPFont.rowTitle)", "Text(LightForecastStyle.whenLine(card))",
                       ".foregroundStyle(WebTheme.text2)", "chanceChip(card.kind, high: card.chance == .high)",
                       ".background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))",
                       ".strokeBorder(card.isBest ? WebTheme.accent : WebTheme.line"], in: cardView, "光の札")
        let chip = slice(view, from: "private func chanceChip", to: "private func thumbnail")
        assertInOrder([".foregroundStyle(high ? WebTheme.accentText : WebTheme.text2)",
                       ".background(high ? WebTheme.accent : Color.clear, in: Capsule())"], in: chip, "見込みの札")
        // 開いた中: 中へは白 8%、外へ（経路）は真鍮の線。当たりは 44
        let pill = slice(view, from: "private func linkPill", to: "private func weekView")
        assertInOrder([".foregroundStyle(outward ? WebTheme.accent : WebTheme.text)",
                       "minHeight: JPHeight.secondaryButton",
                       ".strokeBorder(outward ? WebTheme.accent.opacity(0.6) : Color.clear"], in: pill, "開いた中のカプセル")
        // 空・読めないは土台の状態の型。Pro の案内の一手は真鍮の塗り（EmptyState の一手）
        let states = slice(view, from: "private func emptyView", to: "private func load(refreshing")
        XCTAssertTrue(states.contains("EmptyState(title: LightForecastText.emptyTitle(empty)"))
        XCTAssertTrue(states.contains("actionTitle: L(\"Pro について見る\", \"About Pro\")"))
        // 識別子はボタンそのものに（EmptyState の一手に渡す）
        XCTAssertTrue(states.contains("actionIdentifier: \"lightForecast.paywall\""))
        XCTAssertTrue(states.contains("ErrorBanner(title: LightForecastText.failureTitle(failure)"))
        XCTAssertFalse(view.contains("Color(red: 0x12"), "札に v1 の #121212 が残っている")
    }

    // MARK: - Pro マーク（板 ProMarkOptions）

    /// 小さい版は真鍮の単色・PRO の札は真鍮の塗りに墨。大きい版は光る真鍮のまま
    func testProMarkSmallVersions() throws {
        XCTAssertTrue(ProMarkStyleV2.filledPlate(small: true))
        XCTAssertFalse(ProMarkStyleV2.filledPlate(small: false))
        XCTAssertTrue(ProMarkStyleV2.flatFill(small: true))
        XCTAssertFalse(ProMarkStyleV2.flatFill(small: false))
        // 墨の字は真鍮の塗りの上で 7:1 を超える（コメントの小ささでも読める）
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(BrandPalette.ink, BrandPalette.accent), 7)

        let mark = try source("Features/Profile/ProMark.swift")
        let iris = slice(mark, from: "private struct ProMarkIris", to: "private func aperture")
        assertInOrder(["if ProMarkStyleV2.flatFill(small: small) {", "Circle().fill(WebTheme.accent)",
                       "} else {", "LinearGradient(stops: ProMarkColors.stops(ProMarkColors.irisStops)"],
                      in: iris, "絞り羽根の小さい版")
        let plate = slice(mark, from: "private struct ProMarkPlate", to: "enum ProMarkStyleV2")
        assertInOrder(["let filled = ProMarkStyleV2.filledPlate(small: small)", "if filled {",
                       ".fill(WebTheme.accent)", "} else {", ".strokeBorder(sheen, lineWidth: line)",
                       "filled ? AnyShapeStyle(WebTheme.accentText) : AnyShapeStyle(sheen)"], in: plate, "PRO の札の小さい版")
    }

    // MARK: - 通知の説明（板 PushPrimer）

    /// 「あとで」の当たり 48（UI テストの 44 以上の決まり）・真鍮の主ボタン・シートの面
    func testPushPrimer() throws {
        XCTAssertGreaterThanOrEqual(PushPrimerLayout.laterHeight, 48)
        XCTAssertEqual(PushPrimerLayout.iconTile, 40)
        let view = try source("Features/Settings/PushPrimerView.swift")
        assertInOrder(["Text(L(\"オンにする\", \"Turn on\"))", ".jpPillButton(.accent)",
                       ".accessibilityIdentifier(\"push.primer.allow\")",
                       "Text(L(\"あとで\", \"Not now\"))", ".frame(maxWidth: .infinity, minHeight: PushPrimerLayout.laterHeight)",
                       ".accessibilityIdentifier(\"push.primer.later\")"], in: view, "通知の説明のボタン")
        XCTAssertTrue(view.contains(".background(WebTheme.sheet, ignoresSafeAreaEdges: .all)"))
        XCTAssertTrue(view.contains(".presentationBackground(WebTheme.sheet)"))
        XCTAssertTrue(view.contains(".background(WebTheme.surface, in: RoundedRectangle(cornerRadius: JPRadius.field))"),
                      "項目の印が 40 の角丸の箱に入っていない")
    }

    // MARK: - アカウント（板 ChangePassword・BlockedUsers・DeleteAccount）

    func testChangePasswordHasFocusRingButNoEyeButton() throws {
        XCTAssertEqual(ChangePasswordLayout.submitStyle, .accent)
        let view = try source("Features/Settings/ChangePasswordView.swift")
        assertInOrder(["SecureField(\"\", text: $current)", ".focused($focused, equals: .current)",
                       ".overlay(alignment: .bottom) { focusRing(focused == .current) }",
                       "SecureField(\"\", text: $updated)", ".focused($focused, equals: .updated)",
                       ".overlay(alignment: .bottom) { focusRing(focused == .updated) }",
                       ".jpPillButton(ChangePasswordLayout.submitStyle)"], in: view, "パスワードを変える")
        let ring = slice(view, from: "private func focusRing", to: "\n}\n")
        assertInOrder([".strokeBorder(WebTheme.accent", ".frame(height: JPHeight.field)", ".opacity(on ? 1 : 0)",
                       ".allowsHitTesting(false)"], in: ring, "入力中の縁")
        // owner の決め: 表示・非表示の目のボタンは足さない（新しい機能を入れない）
        XCTAssertFalse(view.contains("eye"), "パスワードの目のボタンを足している")
        XCTAssertFalse(view.contains("TextField("), "パスワードを見える欄に切り替える作りを足している")
    }

    func testBlockedUsersRows() throws {
        XCTAssertEqual(BlockedUsersLayout.avatarGrayscale, 0.6)
        let view = try source("Features/Settings/BlockedUsersView.swift")
        XCTAssertTrue(view.contains(".grayscale(BlockedUsersLayout.avatarGrayscale)"))
        assertInOrder(["Text(L(\"解除\", \"Unblock\"))", "minHeight: JPHeight.inlineButton",
                       ".overlay(Capsule().strokeBorder(WebTheme.line"], in: view, "解除のボタン")
        XCTAssertTrue(view.contains(".frame(minHeight: JPHeight.tallRow)"), "人の行が 64 でない")
        XCTAssertGreaterThanOrEqual(JPHeight.tallRow, WebTheme.minTapTarget)
    }

    func testDeleteAccountWarningAndEnableHint() throws {
        XCTAssertEqual(DeleteAccountText.warningFillOpacity, 0.08, "退会の警告の札は赤 8% の地（CLAUDE.md）")
        XCTAssertEqual(DeleteAccountText.warningBorderOpacity, 0.3, "退会の警告の札は赤 30% の縁（CLAUDE.md）")
        XCTAssertTrue(DeleteAccountText.enableHint(word: ConfirmWord.delete).contains(ConfirmWord.delete))
        let view = try source("Features/Settings/DeleteAccountView.swift")
        assertInOrder(["Image(systemName: \"exclamationmark.triangle\")", ".foregroundStyle(WebTheme.danger)",
                       "removed(L(\"投稿した写真と画像ファイル\"", "Text(L(\"この操作は取り消せません。\"",
                       ".background(WebTheme.danger.opacity(DeleteAccountText.warningFillOpacity)",
                       ".strokeBorder(WebTheme.danger.opacity(DeleteAccountText.warningBorderOpacity)",
                       "JPField("], in: view, "退会の警告の札")
        XCTAssertTrue(view.contains("canDelete || isWorking ? nil : DeleteAccountText.enableHint(word: Self.confirmWord)"),
                      "押せない理由を出していない")
        let bar = slice(view, from: "private var deleteBar", to: "private var enableHint")
        assertInOrder(["deleteButton", "if let enableHint {", "Text(enableHint)", ".jpBottomBar()"], in: bar, "下の帯")
        XCTAssertTrue(view.contains(".safeAreaInset(edge: .bottom) { deleteBar }"))
        // 系統の赤（#FF453A）を画面の行に出さない: 確定は土台の危険の塗り
        XCTAssertTrue(view.contains(".jpPillButton(.danger)"))
    }

    // MARK: - 構図の一覧（板 Compositions）

    func testCompositionCatalog() throws {
        let view = try source("Features/Settings/CompositionCatalogView.swift")
        let list = slice(view, from: "struct CompositionCatalogView", to: "struct CompositionExplanationView")
        XCTAssertTrue(list.contains("JPEyebrowLine(section.title)"), "節の見出しが真鍮の眉と線でない")
        XCTAssertFalse(list.contains("JPCard"), "一覧の行が札に入ったまま")
        XCTAssertTrue(list.contains(".navigationTitle(L(\"撮影ガイド\", \"Shooting guide\"))"))
        XCTAssertTrue(list.contains(".accessibilityIdentifier(\"composition.catalog.\\(kind.rawValue)\")"))
        let detail = slice(view, from: "struct CompositionExplanationView", to: "enum CompositionExample")
        XCTAssertTrue(detail.contains(".tint(WebTheme.accentDeep)"), "ガイド線のトグルが brass-deep でない")
        XCTAssertTrue(detail.contains("JPEyebrowLine(title)"))
        XCTAssertTrue(detail.contains("explanationSection(L(\"どんな構図？\", \"How it works\")"))
        XCTAssertTrue(detail.contains(".jpPillButton(.outline)"), "自分の写真で確かめるが線のボタンでない")
    }

    // MARK: - ログイン・規約（板 SignIn・LegalGate）

    /// 写真のある画面の主ボタンは白（CLAUDE.md の owner の好み。v2 の板の SignIn は真鍮の案だが取らない）
    func testSignInPrimaryIsWhiteAndTilesAreTilted() throws {
        XCTAssertEqual(SignInLayout.primaryStyle, .primary)
        XCTAssertEqual(SignInLayout.tileCount, 12)
        XCTAssertEqual(SignInLayout.tileTilt, -4)
        let view = try source("Features/Auth/SignInView.swift")
        XCTAssertFalse(view.contains(".jpPillButton(.accent)"), "ログインの画面に真鍮の主ボタンが残っている")
        XCTAssertEqual(view.components(separatedBy: ".jpPillButton(SignInLayout.primaryStyle)").count - 1, 4,
                       "ログイン・登録の完了・コードを送る・パスワードを変える の4つが白でない")
        let header = slice(view, from: "private var tileHeader", to: "private func tile(")
        assertInOrder(["count: SignInLayout.tileColumns", ".rotationEffect(.degrees(SignInLayout.tileTilt))",
                       ".clipped()", "LinearGradient(stops:"], in: header, "ログインの写真のタイル")
        XCTAssertTrue(view.contains(".prefix(SignInLayout.tileCount)"))
        XCTAssertTrue(view.contains(".font(JPFont.rowTitle)"), "ワードマークの下の一文が明朝でない")
    }

    func testLegalGate() throws {
        XCTAssertEqual(LegalGateLayout.heroHeight, 300)
        XCTAssertEqual(LegalGateLayout.agreeStyle, .primary)
        let view = try source("Features/Legal/LegalGateView.swift")
        // 写真の上の眉ラベルは白（CLAUDE.md）、規約のリンクは真鍮
        XCTAssertTrue(view.contains("Text(\"JOURNEY PHOTO\").jpEyebrow().foregroundStyle(Color.white.opacity(0.9))"))
        XCTAssertTrue(view.contains(".font(JPFont.body).foregroundStyle(WebTheme.accent) }"), "規約のリンクが真鍮でない")
        XCTAssertTrue(view.contains(".jpPillButton(LegalGateLayout.agreeStyle)"))
        XCTAssertTrue(view.contains(".accessibilityIdentifier(\"legal.agree\")"))
        let experience = slice(view, from: "private func experience", to: "private var safetyNote")
        XCTAssertTrue(experience.contains(".foregroundStyle(WebTheme.foreground)"), "約束の印が白でない")
        XCTAssertFalse(experience.contains("WebTheme.accent"))
    }

    // MARK: - 全体の決まり

    /// 本文系は 12pt 以上（眉ラベルだけ 11）・「捨てる」を使わない
    func testTextRulesAcrossTheseScreens() throws {
        let files = ["Features/Settings/SettingsView.swift", "Features/Settings/ChangePasswordView.swift",
                     "Features/Settings/BlockedUsersView.swift", "Features/Settings/DeleteAccountView.swift",
                     "Features/Settings/PushPrimerView.swift", "Features/Settings/CompositionCatalogView.swift",
                     "Features/Pro/PaywallView.swift", "Features/Pro/SupporterCardView.swift",
                     "Features/Pro/LightForecastView.swift", "Features/Pro/ProSettingsSection.swift",
                     "Features/Pro/LightAlertSettingsRows.swift", "Features/Profile/FoundingGiftView.swift",
                     "Features/Auth/SignInView.swift", "Features/Legal/LegalGateView.swift"]
        for file in files {
            let text = try source(file)
            XCTAssertFalse(text.contains(".caption2"), "\(file): 12pt を割る字")
            for small in 1...11 {
                XCTAssertFalse(text.contains(".font(.system(size: \(small))") || text.contains(".font(.system(size: \(small),"),
                               "\(file): \(small)pt の字")
            }
            for line in text.components(separatedBy: "\n") where line.contains("L(\"") {
                XCTAssertFalse(line.contains("捨て"), "\(file): 「捨てる」を使っている: \(line)")
            }
        }
    }
}

final class PaywallEyebrowContrastTests: XCTestCase {
    /// 白 88% の眉ラベルは、いちばん明るい地（白い写真＋溶けの下端）でも 4.5:1 を保つ
    func testWhiteEyebrowReadsOnTheBrightestFloor() {
        let floor = ProPaywallStyle.eyebrowFloorHex
        let level = Double(floor & 0xFF)
        let blended = UInt32((255 * 0.88 + level * 0.12).rounded())
        let white88 = (blended << 16) | (blended << 8) | blended
        XCTAssertGreaterThanOrEqual(BrandPalette.contrast(white88, floor), 4.5)
    }
}
