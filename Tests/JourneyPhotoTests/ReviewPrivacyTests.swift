import XCTest
@testable import JourneyPhoto

/// 完成度レビューの「審査・プライバシー」の直し（2026-10-16）。
///
/// 審査で見比べられるもの（プライバシーマニフェスト・「App のプライバシー」の表・Notes・権限の文）は
/// ビルドが通っても食い違いに気づけないので、ファイルを読んで突き合わせる
final class ReviewPrivacyTests: XCTestCase {

    // MARK: - 読む道具

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 注記（`//`・`///`）の行を落としたソース
    private func code(_ path: String) throws -> String {
        try read(path).components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    private var manifest: String {
        get throws { try read("Sources/JourneyPhoto/Resources/PrivacyInfo.xcprivacy") }
    }

    /// 集めるデータの種類 → その行の中身（本人と紐づく・トラッキング・用途）
    private func collected() throws -> [String: String] {
        let text = try manifest
        var out: [String: String] = [:]
        for m in matches(#"<key>NSPrivacyCollectedDataType</key>\s*<string>(\w+)</string>(.*?)</dict>"#, in: text) {
            out[m[1]] = m[2]
        }
        return out
    }

    /// 理由の要る API の種類 → 理由コード
    private func accessedAPIs() throws -> [String: [String]] {
        let text = try manifest
        var out: [String: [String]] = [:]
        let pattern = #"<key>NSPrivacyAccessedAPIType</key>\s*<string>(\w+)</string>\s*<key>NSPrivacyAccessedAPITypeReasons</key>\s*<array>(.*?)</array>"#
        for m in matches(pattern, in: text) {
            out[m[1]] = matches(#"<string>([^<]+)</string>"#, in: m[2]).map { $0[1] }
        }
        return out
    }

    private func allSwiftSources() throws -> [(path: String, text: String)] {
        let base = root.appendingPathComponent("Sources/JourneyPhoto")
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            out.append((url.lastPathComponent, text))
        }
        return out
    }

    // MARK: - 1. 理由の要る API

    /// 🔴 **ディスクの空きを読んでいるのに申告が無かった**（`OfflineSavedView` の
    /// `volumeAvailableCapacityForImportantUsageKey`）。申告の無い使用は App Store Connect が弾く。
    /// 理由は 85F4.1（本人に見せるだけ）
    func testDiskSpaceIsDeclaredWithDisplayReason() throws {
        let apis = try accessedAPIs()
        XCTAssertEqual(apis["NSPrivacyAccessedAPICategoryDiskSpace"], ["85F4.1"],
                       "ディスクの空きの申告（85F4.1）が無い")
        XCTAssertEqual(apis["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
    }

    /// 理由の要る API を**ソース全体から洗い**、使っている種類が全部申告されているか
    /// （Apple の一覧: ファイルの日時・起動からの時間・ディスクの空き・キーボード・UserDefaults）
    func testEveryRequiredReasonAPIInSourcesIsDeclared() throws {
        let symbols: [String: [String]] = [
            "NSPrivacyAccessedAPICategoryDiskSpace": ["volumeAvailableCapacity", "volumeTotalCapacity",
                                                      "systemFreeSize", "systemSize", "statfs(", "statvfs("],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["creationDateKey", "contentModificationDateKey",
                                                          "contentAccessDateKey", "attributesOfItem",
                                                          "FileAttributeKey.creationDate",
                                                          "FileAttributeKey.modificationDate",
                                                          "getattrlist", "fstat(", "lstat("],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["systemUptime", "mach_absolute_time"],
            "NSPrivacyAccessedAPICategoryActiveKeyboards": ["activeInputModes"],
            "NSPrivacyAccessedAPICategoryUserDefaults": ["UserDefaults"],
        ]
        let declared = try accessedAPIs()
        let sources = try allSwiftSources()
        for (category, words) in symbols {
            let users = sources.filter { file in words.contains { file.text.contains($0) } }.map(\.path)
            if !users.isEmpty {
                XCTAssertNotNil(declared[category], "\(category) を使っている（\(users.prefix(3))）のに申告が無い")
                XCTAssertFalse(declared[category]?.isEmpty ?? true, "\(category) の理由コードが空")
            }
        }
    }

    // MARK: - 2. 集めるデータと「App のプライバシー」の表

    /// 🔴 **購入の記録を送っているのに申告が無かった**（`POST /user/purchases`）
    func testPurchaseHistoryIsDeclaredLinkedForAppFunctionality() throws {
        let service = try code("Sources/JourneyPhoto/Services/PurchaseService.swift")
        XCTAssertTrue(service.contains("\"/user/purchases\""), "前提が変わった: 購入を送っていない")
        let row = try XCTUnwrap(try collected()["NSPrivacyCollectedDataTypePurchaseHistory"], "購入履歴の申告が無い")
        XCTAssertTrue(row.contains("<key>NSPrivacyCollectedDataTypeLinked</key>\n            <true/>"), "本人と紐づくにしていない")
        XCTAssertTrue(row.contains("<key>NSPrivacyCollectedDataTypeTracking</key>\n            <false/>"), "トラッキングを false にしていない")
        XCTAssertTrue(row.contains("NSPrivacyCollectedDataTypePurposeAppFunctionality"))
    }

    /// 送っているデータ（写真・丸めた位置・プロフィール・コメント・返信・端末トークン・通報・購入）が
    /// マニフェストに全部ある。**それぞれ送っている口が今もあることも確かめる**（口が消えたら申告も見直す）
    func testEverythingTheAppSendsIsInTheManifest() throws {
        let sends: [(type: String, file: String, needle: String)] = [
            ("NSPrivacyCollectedDataTypePhotosorVideos", "Services/UploadService.swift", "\"/upload/presigned-url\""),
            ("NSPrivacyCollectedDataTypeCoarseLocation", "Services/UploadService.swift", "\"/upload/save\""),
            ("NSPrivacyCollectedDataTypeName", "Services/ProfileService.swift", "\"/user/profile\""),
            ("NSPrivacyCollectedDataTypeOtherUserContent", "Services/SocialService.swift", "/comments\""),
            ("NSPrivacyCollectedDataTypeOtherUserContent", "Services/ModerationService.swift", "/report\""),
            ("NSPrivacyCollectedDataTypeEmailsOrTextMessages", "Services/StoryService.swift", "/replies\""),
            ("NSPrivacyCollectedDataTypeDeviceID", "Services/PushService.swift", "\"/user/devices\""),
            ("NSPrivacyCollectedDataTypePurchaseHistory", "Services/PurchaseService.swift", "\"/user/purchases\""),
        ]
        let declared = try collected()
        for item in sends {
            let source = try code("Sources/JourneyPhoto/" + item.file)
            XCTAssertTrue(source.contains(item.needle), "前提が変わった: \(item.file) に \(item.needle) が無い")
            XCTAssertNotNil(declared[item.type], "\(item.type) の申告が無い（\(item.file) が送っている）")
        }
        for (type, row) in declared {
            XCTAssertTrue(row.contains("<false/>"), "\(type) がトラッキングになっている")
        }
    }

    /// マニフェストと `docs/APP_REVIEW.md` の「App のプライバシー」の表が**同じ種類**を持つ
    func testReviewDocTableMatchesTheManifest() throws {
        let labels: [String: String] = [
            "NSPrivacyCollectedDataTypeEmailAddress": "| メールアドレス |",
            "NSPrivacyCollectedDataTypeName": "| 名前（表示名） |",
            "NSPrivacyCollectedDataTypePhotosorVideos": "| 写真 |",
            "NSPrivacyCollectedDataTypeOtherUserContent": "| その他のユーザーコンテンツ",
            "NSPrivacyCollectedDataTypeCoarseLocation": "| おおよその位置 |",
            "NSPrivacyCollectedDataTypeUserID": "| ユーザーID |",
            "NSPrivacyCollectedDataTypeDeviceID": "| デバイスID",
            "NSPrivacyCollectedDataTypeEmailsOrTextMessages": "| メールまたはテキストメッセージ",
            "NSPrivacyCollectedDataTypePurchaseHistory": "| 購入履歴",
        ]
        let doc = try read("docs/APP_REVIEW.md")
        let start = try XCTUnwrap(doc.range(of: "## App Store Connect の「App のプライバシー」"))
        let end = try XCTUnwrap(doc.range(of: "## 年齢制限", range: start.upperBound..<doc.endIndex))
        let section = String(doc[start.upperBound..<end.lowerBound])
        let declared = try collected()
        for type in declared.keys {
            let label = try XCTUnwrap(labels[type], "表の名前が決まっていない種類: \(type)")
            XCTAssertTrue(section.contains(label), "表に \(label) の行が無い（マニフェストにはある）")
        }
        for (type, label) in labels where section.contains(label) {
            XCTAssertNotNil(declared[type], "表には \(label) があるのにマニフェストに \(type) が無い")
        }
        let rows = section.components(separatedBy: "\n").filter { $0.hasPrefix("| ") && !$0.hasPrefix("| データ") }
        XCTAssertEqual(rows.count, declared.count, "表の行の数とマニフェストの種類の数が合わない")
    }

    // MARK: - 3. 審査メモ

    func testReviewNotesExplainBluetoothPassAndPro() throws {
        let doc = try read("docs/APP_REVIEW.md")
        let notes = String(doc[..<(doc.range(of: "## 審査用アカウント")?.lowerBound ?? doc.endIndex)])
        let yml = try read("project.yml")
        for mode in ["bluetooth-central", "bluetooth-peripheral"] {
            XCTAssertTrue(yml.contains("- \(mode)"), "前提が変わった: \(mode)")
            XCTAssertTrue(notes.contains(mode), "Notes に背景の Bluetooth（\(mode)）の目的が無い")
        }
        for word in ["iPhone が2台", "動画の URL", "two iPhones", "video URL",
                     ".pro.monthly", ".pro.yearly", "Sandbox", "購入を復元", "Restore"] {
            XCTAssertTrue(notes.contains(word), "Notes に「\(word)」が無い")
        }
        XCTAssertEqual(ProPlan.allCases.map(\.productSuffix), ["pro.yearly", "pro.monthly"], "前提が変わった: 商品")
        let checklist = String(doc[(doc.range(of: "## 提出前の最終確認")?.upperBound ?? doc.startIndex)...])
        XCTAssertTrue(checklist.contains("EULA"), "提出前の確認に利用規約のリンク（EULA 欄）が無い")
        XCTAssertTrue(checklist.contains("この版と一緒に審査へ出した"), "提出前の確認に課金の商品を版と出すことが無い")
    }

    // MARK: - 4. 自動更新の一文

    func testPaywallStatesAutoRenewalAndHowToCancel() throws {
        let ja = ProPaywallText.autoRenewNotice
        for word in ["24時間前までに解約しない限り自動で更新", "請求", "サブスクリプション"] {
            XCTAssertTrue(ja.contains(word), "自動更新の一文に「\(word)」が無い")
        }
        let source = try read("Sources/JourneyPhoto/Core/Store/ProProducts.swift")
        XCTAssertTrue(source.contains("renews automatically unless you cancel at least 24 hours before the end of the current period"),
                      "英語の自動更新の一文が無い")
        let paywall = try code("Sources/JourneyPhoto/Features/Pro/PaywallView.swift")
        XCTAssertTrue(paywall.contains("Text(ProPaywallText.autoRenewNotice)"), "案内に自動更新の一文を出していない")
    }

    // MARK: - 5. すれちがいの地名引き

    func testPassPlaceLookupSendsOnlyRoundedCoordinates() throws {
        let raw = Photo.Coords(lat: 35.681236, lng: 139.767125)
        let sent = PassExchange.lookupCoords(raw)
        XCTAssertEqual(sent.lat, 35.68, accuracy: 1e-9)
        XCTAssertEqual(sent.lng, 139.77, accuracy: 1e-9)
        XCTAssertEqual(sent, LibraryTrips.roundedForLookup(raw))
        let radio = try code("Sources/JourneyPhoto/Services/PassRadio.swift")
        XCTAssertTrue(radio.contains("let rounded = PassExchange.lookupCoords(coords)"), "地名引きの前に丸めていない")
        XCTAssertTrue(radio.contains("CLLocation(latitude: rounded.lat, longitude: rounded.lng)"),
                      "丸めていない座標を CLGeocoder に渡している")
        XCTAssertFalse(radio.contains("CLLocation(latitude: coords.lat, longitude: coords.lng)"))
    }

    /// 位置の利用目的の文が実装と合う（おおよその位置だけを Apple の地図に渡す・サーバーへは送らない）
    func testLocationPurposeStringMatchesImplementation() throws {
        let yml = try read("project.yml")
        let ja = try read("Sources/JourneyPhoto/Resources/ja.lproj/InfoPlist.strings")
        let en = try read("Sources/JourneyPhoto/Resources/en.lproj/InfoPlist.strings")
        for text in [yml, ja] {
            XCTAssertTrue(text.contains("約1kmに丸めたおおよその位置だけを Apple の地図に渡し"))
            XCTAssertFalse(text.contains("位置を送信することはありません"), "Apple の地図へ渡しているのに「送信しない」と書いている")
        }
        XCTAssertTrue(en.contains("rounded to about 1 km) is sent to Apple Maps"))
        XCTAssertFalse(en.contains("Your location is never sent."))
    }

    // MARK: - 6. すれちがいの説明が電波の中身と合う

    /// 電波に載る中身（`PassExchange.Payload` の欄）が、説明に全部書いてある。
    /// **欄を足したらここが落ちる**——説明を足すこと
    func testPassPrivacyTextNamesEveryFieldOnTheAir() {
        let fields = Mirror(reflecting: PassExchange.Payload(photoId: "p", showsFrom: true, note: ""))
            .children.compactMap(\.label)
        let words: [String: String] = [
            "photoId": "乗車券の写真", "note": "ひとこと", "origin": "発と着の字",
            "destination": "発と着の字", "showsFrom": "居住地", "face": "券面の種類",
        ]
        let body = PassPrivacyText.noteBody
        let point = PassPrivacyText.introPoints.map(\.text).joined()
        for field in fields {
            let word = words[field]
            XCTAssertNotNil(word, "説明に対応の無い欄: \(field)")
            XCTAssertTrue(body.contains(word ?? field), "設定の説明に「\(word ?? field)」が無い")
            XCTAssertTrue(point.contains(word ?? field), "オンにする前の説明に「\(word ?? field)」が無い")
        }
        XCTAssertTrue(body.contains("居住地の都道府県"), "居住地を出す設定のときに何が出るか書いていない")
    }

    // MARK: - 7. ストーリーの返信の通報・ブロック

    private func reply(uid: String?, text: String? = "ひどい", deleted: Bool? = nil) -> StoryReply {
        StoryReply(rawId: "r1", uid: uid, name: "相手", text: text, emoji: nil, t: nil, deleted: deleted)
    }

    func testReplyMenuOffersReportAndBlockForOthersOnly() {
        XCTAssertEqual(StoryReplyActions(reply(uid: "u2"), me: "me"), StoryReplyActions(report: true, block: true))
        XCTAssertEqual(StoryReplyActions(reply(uid: "me"), me: "me"), StoryReplyActions(report: false, block: false),
                       "自分の返信に通報・ブロックを出している")
        XCTAssertEqual(StoryReplyActions(reply(uid: "u2", deleted: true), me: "me"), StoryReplyActions(report: true, block: false),
                       "退会した人はブロックできないが、書かれた字は通報できる")
        XCTAssertEqual(StoryReplyActions(reply(uid: nil), me: "me"), StoryReplyActions(report: true, block: false))
    }

    func testBlockedHereRepliesLeaveTheSheet() {
        let items = [reply(uid: "u2"), reply(uid: "u3"), reply(uid: nil)]
        XCTAssertEqual(StoryReplyActions.visible(items, blockedHere: ["u2"]).map(\.uid), ["u3", nil])
        XCTAssertEqual(StoryReplyActions.visible(items, blockedHere: []).count, 3)
    }

    /// 🔴 **ブロックの答えは、押した人がまだその人のときだけ書く**（2026-10-17）。
    /// 返信のシート・すれちがいの束・ストーリーの閲覧・ホームのカード
    func testBlockAnswerStaysWithThePersonWhoPressed() throws {
        XCTAssertTrue(StoryReplyActions.keepsBlock(sender: "a", viewer: "a"))
        XCTAssertFalse(StoryReplyActions.keepsBlock(sender: "a", viewer: "b"))
        XCTAssertFalse(StoryReplyActions.keepsBlock(sender: nil, viewer: nil))
        XCTAssertTrue(PassCardBlockRule.keepsResult(sender: "a", viewer: "a"))
        XCTAssertFalse(PassCardBlockRule.keepsResult(sender: "a", viewer: "b"),
                       "次の人の帳から、前の人のブロックでカードを外した")
        let sheet = try code("Sources/JourneyPhoto/Features/Stories/StoryRepliesSheet.swift")
        XCTAssertEqual(sheet.components(separatedBy: "StoryReplyActions.keepsBlock(sender: sender, viewer: hidden.owner)").count - 1, 2)
        let pass = try code("Sources/JourneyPhoto/Features/Pass/PassCardMenu.swift")
        XCTAssertEqual(pass.components(separatedBy: "PassCardBlockRule.keepsResult(sender: sender, viewer: hidden.owner)").count - 1, 2)
        let story = try code("Sources/JourneyPhoto/Features/Stories/StoryViewerView.swift")
        XCTAssertEqual(story.components(separatedBy: "guard hidden.owner == owner, owner != nil, current?.id == storyId else { return }").count - 1, 2,
                       "人が替わったあとも、見ている人の束を飛ばす")
        let home = try code("Sources/JourneyPhoto/Features/Gallery/HomeMosaic.swift")
        XCTAssertEqual(home.components(separatedBy: "guard sender != nil, hidden.owner == sender else { return }").count - 1, 2)
        let edit = try code("Sources/JourneyPhoto/Features/Profile/ProfileEditView.swift")
        // 2026-10-18: 8つ目は #304 のお礼（`claimReward`）。保存の途中で人が替わったら、次の人の分として頼まない
        XCTAssertEqual(edit.components(separatedBy: "Self.keepsSave(sender: sender, viewer: auth.userId)").count - 1, 8,
                       "保存の答え（名前・絵・閉じる・お礼）のどれかを、押した人かを見ずに書く")
        // 🔴 **絵を上げる直前**に押した人かを見る（2026-10-18・名指しで見張る）。数だけ見ていると、
        // この1つを外しても他の6つで足りてしまい、次の人の `profiles/<uid>` に前の人の絵を上げる
        let pick = try XCTUnwrap(edit.range(of: "guard let data else { continue }"))
        let upload = try XCTUnwrap(edit.range(of: "try await environment.profiles.uploadProfileImage(kind: kind, jpeg: data)",
                                              range: pick.upperBound..<edit.endIndex))
        let beforeUpload = String(edit[pick.upperBound..<upload.lowerBound])
        XCTAssertTrue(beforeUpload.contains("guard Self.keepsSave(sender: sender, viewer: auth.userId) else { return }"),
                      "アイコンのアップロードの前に、押した人かを見ていない")
    }

    /// 通報はメールで運営の宛先へ（サーバーに返信の通報の口が無く、写真の通報の口は自分のストーリーを 400 で断る）
    func testReplyReportMailCarriesWhoWhatAndWhere() throws {
        let target = ModerationService.ReportedComment(id: "r1", authorId: "u2", authorName: "A&B+C", text: "1 + 1 = 2 & more")
        let url = try XCTUnwrap(ModerationService.storyReplyReportURL(target, storyId: "story-1"))
        XCTAssertEqual(url.scheme, "mailto")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.path, LegalConsent.contactEmail)
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(Set(items.keys), ["subject", "body"], "本文の & で問い合わせの欄が割れた")
        XCTAssertTrue(items["subject"]?.hasPrefix(ModerationService.storyReplyMarker) == true)
        let body = items["body"] ?? ""
        for word in ["A&B+C (u2)", "r1", "story-1", "1 + 1 = 2 & more"] {
            XCTAssertTrue(body.contains(word), "通報のメールに「\(word)」が無い")
        }
    }

    /// `+` を符号にする（`queryItems` は `+` を残し、受け手によっては空白に読まれる）。
    /// 相手の分からない返信で空のかっこを出さない
    func testReplyReportMailEncodesPlusAndSkipsEmptyAuthorId() throws {
        let target = ModerationService.ReportedComment(id: "r1", authorId: "", authorName: "A+B", text: "1+1")
        let url = try XCTUnwrap(ModerationService.storyReplyReportURL(target, storyId: nil))
        XCTAssertFalse(url.absoluteString.contains("+"), "mailto に生の + が残っている: \(url.absoluteString)")
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        let body = ModerationService.storyReplyReportBody(target, storyId: nil)
        XCTAssertFalse(body.contains("()"), "相手の分からない返信で空のかっこを出している")
        XCTAssertTrue(body.contains("投稿者 / From: A+B\n"))
    }

    /// 「…」の無い行（自分の返信）は吹き出しの右に 32 を空ける（右端まで伸びない）
    func testOwnReplyBubbleKeepsTrailingRoom() {
        XCTAssertEqual(StoryReplyActions(report: false, block: false).trailingSpace, JPSpace.section)
        XCTAssertEqual(StoryReplyActions(report: true, block: false).trailingSpace, JPSpace.s)
        XCTAssertFalse(StoryReplyActions(report: false, block: false).hasMenu)
    }

    /// 🔴 シートの上には根のトーストが出ない——ブロックの結果・失敗が裏に隠れていた。
    /// メールを開けないときの宛先は、切れないよう確認（alert）で全部出し、コピーできる
    func testReplySheetShowsToastsAndAddressAlert() throws {
        let sheet = try code("Sources/JourneyPhoto/Features/Stories/StoryRepliesSheet.swift")
        XCTAssertTrue(sheet.contains(".overlay(alignment: .top) { ToastOverlay() }"), "シートにトーストを重ねていない")
        XCTAssertTrue(sheet.contains(".alert(StoryReplyActions.mailUnavailableTitle, isPresented: $mailUnavailable)"))
        XCTAssertTrue(sheet.contains("UIPasteboard.general.string = LegalConsent.contactEmail"), "宛先をコピーできない")
        XCTAssertFalse(sheet.contains("toasts.show(StoryReplyActions.mailUnavailable"), "宛先をトーストで出している（切れる）")
        XCTAssertTrue(StoryReplyActions.mailUnavailable.contains(LegalConsent.contactEmail))
        XCTAssertEqual(StoryReplyActions.copyAddress, "宛先をコピー")
    }

    /// Bluetooth の利用目的の文に、居住地を出す設定のとき相手に都道府県が出ることを書く
    func testBluetoothPurposeMentionsPrefecture() throws {
        for path in ["project.yml", "Sources/JourneyPhoto/Resources/ja.lproj/InfoPlist.strings"] {
            XCTAssertTrue(try read(path).contains("居住地を出す設定なら、相手にはプロフィールの都道府県が表示されます"), path)
        }
        XCTAssertTrue(try read("Sources/JourneyPhoto/Resources/en.lproj/InfoPlist.strings")
            .contains("they see the prefecture from your profile"))
    }

    func testReplySheetHasMenuWithConfirmedBlock() throws {
        let sheet = try code("Sources/JourneyPhoto/Features/Stories/StoryRepliesSheet.swift")
        XCTAssertTrue(sheet.contains("replyMenu(item, actions: actions)"), "返信の行に「…」が無い")
        XCTAssertTrue(sheet.contains(".blockConfirmation(presenting: $pendingBlock)"), "ブロックに確認が無い")
        XCTAssertTrue(sheet.contains("hidden.blockAndHide(uid, environment: environment)"), "ブロックをサーバーに送っていない")
        XCTAssertTrue(sheet.contains("ModerationService.storyReplyReportURL(target, storyId: storyId)"), "通報を送っていない")
        XCTAssertTrue(sheet.contains("ForEach(shown)"), "ブロックした人の返信が一覧に残る")
        let viewer = try code("Sources/JourneyPhoto/Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("storyId: current?.id)"), "通報のメールにどのストーリーかが入らない")
    }

    // MARK: - 8. 登録の確認の控えの鍵

    private func freshDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// 🔴 **鍵にメールアドレスがそのまま入っていた**（`jp_verify_taro@example.com`）
    func testPendingKeyDoesNotContainTheEmail() {
        let key = PendingVerification.key(for: "Taro@Example.com ")
        XCTAssertFalse(key.contains("taro"), "鍵にメールアドレスが入っている: \(key)")
        XCTAssertFalse(key.contains("example"))
        XCTAssertFalse(key.contains("@"))
        XCTAssertTrue(key.hasPrefix(PendingVerification.keyPrefix))
        XCTAssertEqual(key.count, PendingVerification.keyPrefix.count + 40, "SHA-1 の 16 進（40 字）でない")
        XCTAssertEqual(key, PendingVerification.key(for: "taro@example.com"), "大小・空白で鍵が変わる")
        XCTAssertNotEqual(key, PendingVerification.key(for: "jiro@example.com"))

        let defaults = freshDefaults("review-pending-1")
        PendingVerificationStore(defaults: defaults).remember(email: "taro@example.com", username: "uuid-1")
        let keys = defaults.dictionaryRepresentation().keys
        XCTAssertFalse(keys.contains { $0.contains("taro@example.com") }, "メールアドレスが鍵に残っている")
    }

    /// 前の形の鍵（メールそのまま）を起動のときに移し替えて消す。切れた控えは移さずに消す
    func testLegacyKeysAreMigratedAndRemoved() throws {
        let defaults = freshDefaults("review-pending-2")
        let encoder = JSONEncoder()
        struct Legacy: Codable { let username: String; let savedAt: Date; var displayName: String? }
        defaults.set(try encoder.encode(Legacy(username: "uuid-1", savedAt: Date(), displayName: "太郎")),
                     forKey: "jp_verify_taro@example.com")
        defaults.set(try encoder.encode(Legacy(username: "uuid-old", savedAt: Date().addingTimeInterval(-PendingVerification.ttl - 60))),
                     forKey: "jp_verify_old@example.com")

        let store = PendingVerificationStore(defaults: defaults)
        store.migrateLegacyKeys()

        let keys = defaults.dictionaryRepresentation().keys
        XCTAssertFalse(keys.contains { $0.hasPrefix(PendingVerification.legacyKeyPrefix) }, "前の形の鍵が残っている")
        XCTAssertEqual(store.username(for: "Taro@example.com"), "uuid-1", "移し替えで控えをなくした")
        XCTAssertEqual(store.displayName(for: "taro@example.com"), "太郎")
        XCTAssertNil(defaults.object(forKey: PendingVerification.key(for: "old@example.com")), "切れた控えまで移した")
    }

    /// 起動の移し替えより前に引かれても、前の形の鍵から拾って移す。退会の後始末は両方の形を探す
    func testLegacyEntryIsFoundOnLookupAndOnAccountDeletion() throws {
        let defaults = freshDefaults("review-pending-3")
        struct Legacy: Codable { let username: String; let savedAt: Date }
        let data = try JSONEncoder().encode(Legacy(username: "uuid-9", savedAt: Date()))
        defaults.set(data, forKey: "jp_verify_hana@example.com")
        let store = PendingVerificationStore(defaults: defaults)
        XCTAssertEqual(store.username(for: "hana@example.com"), "uuid-9")
        XCTAssertNil(defaults.object(forKey: "jp_verify_hana@example.com"), "引いたあとも前の形の鍵が残っている")

        defaults.set(data, forKey: "jp_verify_mei@example.com")
        store.forget(username: "uuid-9")
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(PendingVerification.keyPrefix) || $0.hasPrefix(PendingVerification.legacyKeyPrefix)
        }.isEmpty, "退会の後始末で控えが残った")
    }
}
