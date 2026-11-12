import XCTest
@testable import JourneyPhoto

/// 名前の横のバッジの入口（2026-11-12 owner 案 A「メダル案 A だな」）。
///
/// - マイページの名前の横に点線の丸: **メダルを持っていて、名前の横に何も飾っていない人だけ**（`MyPageNameSlot.shows`）
/// - プロフィールの編集の「バッジ」の節（名前の横のバッジの行）は外した
///
/// 以前ここは「編集の欄の中にシートを付けない」（2026-10-09 owner「メダルを回す全画面で戻れなくなった」）を
/// 見張っていた。編集の入口ごと外したので、編集に名前の横の画面が残っていないことを見張る
final class ProfileEditNameSideTests: XCTestCase {

    private func profile(_ json: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
    }

    private static let at = "2026-10-01T00:00:00.000Z"

    // MARK: 丸を出す・出さない

    /// メダルを持っていて飾っていない → 出す
    func testSlotShowsForOwnerWithoutDisplayedBadge() throws {
        let p = try profile(#"{"userId":"u1","displayName":"丸田","badges":{"prefectures":{"tier":2,"at":"\#(Self.at)"}}}"#)
        XCTAssertTrue(MyPageNameSlot.shows(p))
    }

    /// 飾っている → 出さない（今の見た目のまま）
    func testSlotHiddenWhenBadgeIsDisplayed() throws {
        let p = try profile(#"{"userId":"u1","badges":{"prefectures":{"tier":2,"at":"\#(Self.at)"}},"displayBadge":"prefectures"}"#)
        XCTAssertNotNil(p.shownBadge)
        XCTAssertFalse(MyPageNameSlot.shows(p))
    }

    /// メダルを1つも持っていない → 出さない（古いサーバーの「無い」も同じ）
    func testSlotHiddenWithoutMedals() throws {
        XCTAssertFalse(MyPageNameSlot.shows(try profile(#"{"userId":"u1"}"#)))
        XCTAssertFalse(MyPageNameSlot.shows(try profile(#"{"userId":"u1","badges":{}}"#)))
        // 絵の無い（知らない）鍵だけ → 選ぶ画面に並ぶ物が無いので出さない
        XCTAssertFalse(MyPageNameSlot.shows(try profile(#"{"userId":"u1","badges":{"someFutureKey":{"tier":1,"at":"\#(Self.at)"}}}"#)))
    }

    /// 持っていない鍵・知らない鍵を選んでいても、名前の横に出ていなければ「飾っていない」→ 出す
    func testSlotShowsWhenChosenKeyIsNotActuallyShown() throws {
        let gone = try profile(#"{"userId":"u1","badges":{"prefectures":{"tier":2,"at":"\#(Self.at)"}},"displayBadge":"firstPhoto"}"#)
        XCTAssertNil(gone.shownBadge)
        XCTAssertTrue(MyPageNameSlot.shows(gone))
        let unknown = try profile(#"{"userId":"u1","badges":{"prefectures":{"tier":2,"at":"\#(Self.at)"},"someFutureKey":{"tier":1,"at":"\#(Self.at)"}},"displayBadge":"someFutureKey"}"#)
        XCTAssertTrue(MyPageNameSlot.shows(unknown))
    }

    /// 季節の章（Pro のメダル）だけを持っていても出す（選ぶ画面の「持っているバッジ」に並ぶ）
    func testSlotShowsForSeasonChapterOnly() throws {
        let chapters = ProChapters.owned(BadgeSet([EarnedBadge(key: "proAutumn2026", tier: 1, at: Self.at)]))
        try XCTSkipIf(chapters.isEmpty, "秋 2026 の章の絵が無い")
        let p = try profile(#"{"userId":"u1","badges":{"proAutumn2026":{"tier":1,"at":"\#(Self.at)"}}}"#)
        XCTAssertTrue(MyPageNameSlot.shows(p))
    }

    // MARK: 寸法・言葉（資料の案 A・デザインの板）

    func testSlotLooksAndSpeech() {
        XCTAssertEqual(MyPageNameSlot.side, 22)
        XCTAssertEqual(MyPageNameSlot.ringOpacity, 0.35)
        XCTAssertEqual(MyPageNameSlot.label, "名前の横にバッジを飾る")
    }

    // MARK: 置き場（ソースを読む）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// プロフィールの編集に「バッジ」の節（名前の横のバッジの行・名前の横の画面）が無い
    func testProfileEditHasNoNameSideRow() throws {
        let edit = try source("Sources/JourneyPhoto/Features/Profile/ProfileEditView.swift")
        XCTAssertFalse(edit.contains("nameSideSection"), "編集の「バッジ」の節が残っている")
        XCTAssertFalse(edit.contains("profileEdit.nameSide"), "編集の名前の横のバッジの行が残っている")
        XCTAssertFalse(edit.contains("NameSideBadgeView("), "編集から名前の横の画面を開いている")
        XCTAssertFalse(edit.contains("名前の横のバッジ\", \"Badge beside your name"), "編集の行の言葉が残っている")
    }

    /// マイページの名前の段: 名前 → 点線の丸（条件つき）→ QR → 編集。丸は名前の行と同じ選ぶ画面を開く
    func testMyPageNameRowOrderAndTarget() throws {
        let page = try source("Sources/JourneyPhoto/Features/Profile/MyPageView.swift")
        let name = try XCTUnwrap(page.range(of: "nameLine(profile)\n"))
        let slot = try XCTUnwrap(page.range(of: "if MyPageNameSlot.shows(profile) {"))
        let qr = try XCTUnwrap(page.range(of: "qrLink()\n"))
        let edit = try XCTUnwrap(page.range(of: "editLink()\n"))
        XCTAssertLessThan(name.lowerBound, slot.lowerBound)
        XCTAssertLessThan(slot.lowerBound, qr.lowerBound)
        XCTAssertLessThan(qr.lowerBound, edit.lowerBound)
        let body = try XCTUnwrap(page.range(of: "private func nameSlot() -> some View {"))
        let rest = page[body.upperBound...].prefix(1800)
        XCTAssertTrue(rest.contains("showNameSide = true"), "丸が選ぶ画面を開かない")
        XCTAssertTrue(rest.contains("WebTheme.minTapTarget, height: WebTheme.minTapTarget"), "当たりが 44pt でない")
        XCTAssertTrue(rest.contains("\"mypage.nameSlot\""))
        XCTAssertFalse(rest.contains("WebTheme.accent"), "丸を真鍮にしない（隣の QR の印が真鍮）")
    }

    /// 贈り物の画面の失敗の文は、新しい入口（マイページの名前の横）を言う
    func testFoundingGiftPointsToMyPage() throws {
        let gift = try source("Sources/JourneyPhoto/Features/Profile/FoundingGiftView.swift")
        XCTAssertFalse(gift.contains("プロフィールの編集の「名前の横のバッジ」"))
        XCTAssertTrue(gift.contains("マイページの名前の横からも飾れます"))
        let gate = try source("Sources/JourneyPhoto/Features/Profile/FoundingGiftGate.swift")
        XCTAssertFalse(gate.contains("プロフィールの編集の「名前の横のバッジ」"))
    }
}
